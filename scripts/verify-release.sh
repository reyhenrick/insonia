#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

/usr/bin/python3 - "$@" <<'PY'
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import stat
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
import zipfile

ROOT = Path.cwd()
ARCHITECTURES = {"arm64", "x86_64"}
PRIVATE_NAMES = {".git", ".codex", ".claude", ".env", ".idea", ".vscode", ".build", ".swiftpm", "build", "dist", "work", "installed-backups", "node_modules", "__pycache__"}
ARTIFACTS = {"Insonia-macOS.dmg", "Insonia-macOS.zip", "release-metadata.json", "SHA256SUMS.txt"}

def require(condition, message):
    if not condition:
        raise RuntimeError(message)

def command(arguments, required=True):
    result = subprocess.run(arguments, capture_output=True, text=True)
    if required and result.returncode:
        raise RuntimeError(f"{arguments[0]} failed: {(result.stderr or result.stdout).strip()}")
    return result

def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()

def private_path(path):
    return any(part in PRIVATE_NAMES or part.startswith(".env.") or part.endswith((".p12", ".p8", ".pem", ".key", ".mobileprovision")) or ".keychain" in part for part in path.parts)

def signature(path, architecture=None, required=True):
    args = ["codesign", "-dv", "--verbose=4"]
    if architecture:
        args.extend(["--arch", architecture])
    result = command(args + [str(path)], required=required)
    if result.returncode:
        require("code object is not signed at all" in result.stderr, f"Could not inspect signature: {path.name}")
        return {"mode": "unsigned"}
    output = result.stderr + result.stdout
    adhoc = "Signature=adhoc" in output
    authority = re.search(r"^Authority=(.+)$", output, re.MULTILINE)
    team = re.search(r"^TeamIdentifier=(.+)$", output, re.MULTILINE)
    hardened = bool(re.search(r"flags=.*\([^)]*runtime[^)]*\)", output))
    timestamped = bool(re.search(r"^Timestamp=", output, re.MULTILINE))
    require(adhoc or (authority and authority.group(1).startswith("Developer ID Application:")), f"Unsupported distribution signature: {path.name}")
    return {
        "mode": "ad-hoc" if adhoc else "developer-id",
        "authority": authority.group(1) if authority else None,
        "teamIdentifier": team.group(1) if team and team.group(1) != "not set" else None,
        "hardenedRuntime": hardened,
        "secureTimestamp": timestamped,
    }

def verify_app(app):
    require(app.is_dir() and not app.is_symlink(), f"Application is missing or linked: {app}")
    require({p.name for p in app.iterdir()} == {"Contents"}, "Unexpected files beside Contents in the application")
    contents = app / "Contents"
    require({p.name for p in contents.iterdir()} == {"Info.plist", "MacOS", "Helpers", "Resources", "_CodeSignature"}, "Unexpected application bundle contents")
    for path in app.rglob("*"):
        relative = path.relative_to(app)
        require(not path.is_symlink(), f"Unexpected application symlink: {relative}")
        require(not private_path(relative), f"Private file or directory in application: {relative}")
        require(path.name != ".DS_Store", f"Finder state in application: {relative}")
    with (contents / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    require(info.get("CFBundleIdentifier") == "com.henrick.insonia", "Unexpected bundle identifier")
    require(info.get("CFBundleName") == info.get("CFBundleDisplayName") == info.get("CFBundleExecutable") == "Insonia", "Bundle naming must be Insonia")
    require(info.get("LSMinimumSystemVersion") == "26.0", "Bundle minimum macOS version must be 26.0")
    version = info.get("CFBundleShortVersionString", "")
    require(re.fullmatch(r"\d+\.\d+\.\d+", version), "Use a three-part release version in Info.plist")
    resources = contents / "Resources"
    for name in ["LICENSE", "Assets.car", "Insonia.icns", "Help/index.html", "helper-install/install-helper.sh", "helper-install/helper/insonia-helper.sh", "helper-install/helper/com.henrick.insonia.helper.plist"]:
        require((resources / name).is_file(), f"Missing bundled resource: {name}")
    for locale in ("en", "pt", "es", "fr", "de", "it"):
        strings = resources / f"{locale}.lproj/Localizable.strings"
        require(strings.is_file(), f"Missing bundled language: {locale}")
        command(["plutil", "-lint", str(strings)])
    for relative in ("helper-install/install-helper.sh", "helper-install/helper/insonia-helper.sh"):
        command(["bash", "-n", str(resources / relative)])
    command(["plutil", "-lint", str(contents / "Info.plist"), str(resources / "helper-install/helper/com.henrick.insonia.helper.plist")])
    signatures = []
    for relative in ("MacOS/Insonia", "Helpers/InsoniaGuard"):
        executable = contents / relative
        require(executable.is_file() and os.access(executable, os.X_OK), f"Missing executable: {relative}")
        architectures = command(["xcrun", "lipo", "-archs", str(executable)]).stdout.split()
        require(set(architectures) == ARCHITECTURES, f"{relative} is not universal arm64 + x86_64")
        for architecture in sorted(ARCHITECTURES):
            build = command(["xcrun", "vtool", "-arch", architecture, "-show-build", str(executable)]).stdout
            require(re.search(r"platform\s+MACOS\b", build) and re.search(r"minos\s+26\.0(?:\.0)?\s", build), f"Incorrect deployment target for {relative} ({architecture})")
            signatures.append(signature(executable, architecture))
        command(["codesign", "--verify", "--strict", "--all-architectures", str(executable)])
    require(all(value == signatures[0] for value in signatures), "Application and guardian signatures differ")
    if signatures[0]["mode"] == "developer-id":
        require(signatures[0]["hardenedRuntime"] and signatures[0]["secureTimestamp"], "Developer ID binaries require hardened runtime and a secure timestamp")
    command(["codesign", "--verify", "--deep", "--strict", "--all-architectures", str(app)])
    return {"name": "Insonia", "version": version, "bundleIdentifier": info["CFBundleIdentifier"], "minimumMacOS": "26.0", "architectures": sorted(ARCHITECTURES), "signing": signatures[0]}

def notarization(app, dmg, mode):
    app_ticket = command(["xcrun", "stapler", "validate", str(app)], required=False).returncode == 0
    dmg_ticket = command(["xcrun", "stapler", "validate", str(dmg)], required=False).returncode == 0
    status = "stapled-ticket-validated" if app_ticket or dmg_ticket else ("not-notarized" if mode == "ad-hoc" else "not-verified")
    return {"status": status, "submittedByPackaging": False, "appStapledTicketValid": app_ticket, "diskImageStapledTicketValid": dmg_ticket}

def metadata(app, dmg, archive):
    application = verify_app(app)
    commit = command(["git", "rev-parse", "--verify", "HEAD"], required=False)
    return {
        "schemaVersion": 1,
        "createdAt": datetime.now(timezone.utc).isoformat(),
        "sourceCommitAtPackaging": commit.stdout.strip() if commit.returncode == 0 else None,
        "packagingXcode": command(["xcodebuild", "-version"]).stdout.strip(),
        "application": application,
        "diskImageSigning": signature(dmg, required=False),
        "notarization": notarization(app, dmg, application["signing"]["mode"]),
        "installationGuideIncluded": (app / "Contents/Resources/Help/index.html").is_file(),
        "artifacts": {path.name: {"sha256": digest(path), "bytes": path.stat().st_size} for path in (dmg, archive)},
    }

def fingerprint(app):
    return {str(path.relative_to(app)): [digest(path), bool(path.stat().st_mode & 0o111)] for path in app.rglob("*") if path.is_file()}

def verify_release(directory):
    require(directory.is_dir(), f"Release directory is missing: {directory}")
    require({path.name for path in directory.iterdir()} == ARTIFACTS, "Release directory must contain exactly DMG, ZIP, SHA256SUMS.txt and release-metadata.json")
    require(all(path.is_file() and not path.is_symlink() for path in directory.iterdir()), "Release artifacts must be regular files")
    checksums = {}
    for line in (directory / "SHA256SUMS.txt").read_text().splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  (Insonia-macOS\.(?:dmg|zip)|release-metadata\.json)", line)
        require(match and match.group(2) not in checksums, "Invalid or duplicate checksum entry")
        checksums[match.group(2)] = match.group(1)
    require(set(checksums) == ARTIFACTS - {"SHA256SUMS.txt"}, "Missing release checksums")
    for name, expected in checksums.items():
        require(digest(directory / name) == expected, f"Checksum mismatch: {name}")
    record = json.loads((directory / "release-metadata.json").read_text())
    require(record.get("schemaVersion") == 1, "Unsupported release metadata schema")
    dmg = directory / "Insonia-macOS.dmg"
    archive = directory / "Insonia-macOS.zip"
    require(record["artifacts"] == {path.name: {"sha256": digest(path), "bytes": path.stat().st_size} for path in (dmg, archive)}, "Artifact metadata does not match downloads")
    command(["hdiutil", "verify", str(dmg)])
    with tempfile.TemporaryDirectory(prefix="insonia-verify-", dir=ROOT / "build") as temporary:
        temporary = Path(temporary)
        unpacked = temporary / "zip"
        unpacked.mkdir()
        with zipfile.ZipFile(archive) as stream:
            names = set()
            for item in stream.infolist():
                path = PurePosixPath(item.filename)
                require(item.filename not in names, "Duplicate ZIP member")
                names.add(item.filename)
                require(path.parts and not path.is_absolute() and ".." not in path.parts and "\\" not in item.filename, "Unsafe ZIP path")
                require(path.parts[0] in {"Insonia.app", "README-install.html", "__MACOSX"}, f"Unexpected ZIP content: {path}")
                if path.parts[0] == "__MACOSX":
                    require(item.is_dir() or (len(path.parts) > 1 and path.name.startswith("._")), f"Unexpected ZIP metadata: {path}")
                require(not private_path(path) and not stat.S_ISLNK(item.external_attr >> 16), f"Private or linked ZIP content: {path}")
        command(["ditto", "-x", "-k", str(archive), str(unpacked)])
        zip_app = unpacked / "Insonia.app"
        application = verify_app(zip_app)
        require(record["application"] == application, "Application metadata does not match ZIP")
        guide = zip_app / "Contents/Resources/Help/index.html"
        has_guide = guide.is_file()
        require(record["installationGuideIncluded"] == has_guide, "Installation guide metadata is incorrect")
        require((unpacked / "README-install.html").is_file() == has_guide, "ZIP installation guide is missing or unexpected")
        if has_guide:
            require(digest(guide) == digest(unpacked / "README-install.html"), "ZIP installation guide differs from bundled help")
        mount = temporary / "mount"
        mount.mkdir()
        attached = False
        try:
            command(["hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen", "-owners", "off", "-mountpoint", str(mount), str(dmg)])
            attached = True
            expected = {"Insonia.app", "Applications", ".VolumeIcon.icns"}
            if has_guide:
                expected.add("README-install.html")
            require({path.name for path in mount.iterdir()} == expected, "Unexpected disk image contents")
            applications = mount / "Applications"
            require(applications.is_symlink() and os.readlink(applications) == "/Applications", "Missing Applications shortcut in disk image")
            require(verify_app(mount / "Insonia.app") == application, "DMG application differs from ZIP")
            require(fingerprint(mount / "Insonia.app") == fingerprint(zip_app), "DMG and ZIP bundle files differ")
            if has_guide:
                require(digest(mount / "README-install.html") == digest(guide), "DMG installation guide differs from bundled help")
        finally:
            if attached:
                command(["hdiutil", "detach", str(mount)])
        require(record["diskImageSigning"] == signature(dmg, required=False), "Disk image signature metadata is incorrect")
        if record["diskImageSigning"]["mode"] != "unsigned":
            command(["codesign", "--verify", "--strict", str(dmg)])
        require(record["notarization"] == notarization(zip_app, dmg, application["signing"]["mode"]), "Notarization metadata is incorrect")
    print(f"Verified DMG and ZIP: Insonia {application['version']}, arm64 + x86_64, macOS 26.0+, {application['signing']['mode']}, notarization {record['notarization']['status']}")

try:
    arguments = sys.argv[1:]
    (ROOT / "build").mkdir(exist_ok=True)
    if len(arguments) == 2 and arguments[0] == "--app":
        result = verify_app(Path(arguments[1]).resolve())
        print(f"Verified universal application: Insonia {result['version']} ({result['signing']['mode']})")
    elif len(arguments) == 4 and arguments[0] == "--metadata":
        print(json.dumps(metadata(*(Path(path).resolve() for path in arguments[1:])), indent=2))
    elif len(arguments) <= 1 and (not arguments or not arguments[0].startswith("-")):
        verify_release(Path(arguments[0]).resolve() if arguments else ROOT / "dist")
    else:
        raise RuntimeError("Usage: scripts/verify-release.sh [dist-directory | --app Insonia.app | --metadata Insonia.app file.dmg file.zip]")
except (RuntimeError, OSError, ValueError, KeyError, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
    print(f"Release verification failed: {error}", file=sys.stderr)
    sys.exit(1)
PY
