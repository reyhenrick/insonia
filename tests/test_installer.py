import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest


PROJECT = Path(__file__).resolve().parent.parent
LABEL = "com.henrick.insonia.helper"


class InstallerTests(unittest.TestCase):
    def setUp(self):
        (PROJECT / "build").mkdir(exist_ok=True)
        self.fixture = tempfile.TemporaryDirectory(prefix="installer-test-", dir=PROJECT / "build")
        self.root = Path(self.fixture.name).resolve()
        self.system = self.root / "system"
        self.library = self.system / "Library"
        self.daemons = self.library / "LaunchDaemons"
        self.parent = self.library / "PrivilegedHelperTools"
        self.installed = self.parent / "com.henrick.insonia"
        self.helper = self.installed / "helper.sh"
        self.version = self.installed / "version"
        self.plist = self.daemons / f"{LABEL}.plist"
        self.runtime = self.system / "run"
        self.status = self.runtime / "insonia-helper-v3-status"
        self.marker = self.runtime / "insonia-helper-v3-booted"
        self.legacy = self.system / "usr/local/libexec"
        self.home = self.root / "App User & Family"
        self.events = self.root / "events"
        self.service = self.root / "service"
        self.power = self.root / "power"
        for directory in (self.daemons, self.parent, self.runtime, self.legacy, self.home):
            directory.mkdir(parents=True)
        self.power.write_text("1")
        self.events.write_text("")
        self.stubs = self.root / "stubs"
        self.stubs.mkdir()
        stub_source = r'''#!/usr/bin/python3
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import time

root = Path(os.environ["TEST_INSTALL_ROOT"])
name = Path(sys.argv[0]).name
args = sys.argv[1:]
with (root / "events").open("a") as log:
    log.write(json.dumps([name, *args]) + "\n")

def local_path(value):
    path = Path(value)
    if not path.is_relative_to(root):
        raise RuntimeError("Fixture refused an external write")
    return path

if name == "id":
    assert args[0] == "-u"
    print(0 if len(args) == 1 else 501)
elif name == "dscl":
    print("NFSHomeDirectory: " + str(root / "App User & Family"))
elif name == "stat":
    if args[1] == "%u" and args[-1] != os.environ.get("TEST_WRONG_OWNER"):
        print(0)
    elif args[1] == "%u":
        print(501)
    else:
        raise SystemExit(subprocess.call(["/usr/bin/stat", *args]))
elif name == "sudo":
    assert args[:3] == ["-u", "appuser", "/bin/mkdir"]
    assert args[3] == "-p"
    local_path(args[4]).mkdir(parents=True, exist_ok=True)
elif name == "install":
    directory = args[0] == "-d"
    offset = 1 if directory else 0
    assert args[offset:offset + 4] == ["-o", "root", "-g", "wheel"]
    assert args[offset + 4] == "-m"
    mode = int(args[offset + 5], 8)
    target = local_path(args[-1])
    if directory:
        target.mkdir(exist_ok=True)
    else:
        source = local_path(args[-2])
        shutil.copyfile(source, target)
    target.chmod(mode)
elif name == "pmset":
    power = root / "power"
    if args == ["-g"]:
        if os.environ.get("TEST_POWER_READ_FAILURE"):
            raise SystemExit(1)
        print(" SleepDisabled " + power.read_text())
    else:
        assert args == ["-a", "disablesleep", "0"]
        if os.environ.get("TEST_POWER_FAILURE"):
            raise SystemExit(1)
        if not os.environ.get("TEST_POWER_NOOP"):
            power.write_text("0")
elif name == "launchctl":
    label = "system/com.henrick.insonia.helper"
    service = root / "service"
    if args[0] in ("print", "bootout", "enable"):
        assert args == [args[0], label]
        if args[0] == "print":
            raise SystemExit(0 if service.exists() else 113)
        if args[0] == "bootout":
            if os.environ.get("TEST_BOOTOUT_FAILURE"):
                raise SystemExit(1)
            service.unlink()
    else:
        assert args[:2] == ["bootstrap", "system"]
        target = local_path(args[2])
        if os.environ.get("TEST_BOOTSTRAP_FAILURE"):
            raise SystemExit(1)
        config = plistlib.loads(target.read_bytes())
        assert config["Label"] == "com.henrick.insonia.helper"
        assert config["ProgramArguments"] == [str(root / "system/Library/PrivilegedHelperTools/com.henrick.insonia/helper.sh")]
        service.touch()
        receipt = os.environ.get("TEST_RECEIPT", "valid")
        if receipt != "none":
            text = "3 %s 0 -\n" % int(time.time()) if receipt == "valid" else receipt
            status = root / "system/run/insonia-helper-v3-status"
            status.write_text(text)
            status.chmod(0o644)
elif name == "sleep":
    pass
else:
    raise RuntimeError("Unexpected fixture command")
'''
        self.env = {**os.environ, "TEST_INSTALL_ROOT": str(self.root)}
        self.env.pop("SUDO_USER", None)
        source = (PROJECT / "install-helper.sh").read_text()
        self.sources = self.root / "sources"
        (self.sources / "helper").mkdir(parents=True)
        for command in ("id", "dscl", "stat", "sudo", "install", "pmset", "launchctl", "sleep"):
            stub = self.stubs / command
            stub.write_text(stub_source)
            if command == "stat":
                stub.write_text("""#!/bin/bash
set -eu
if [ "$2" = '%u' ]; then
    if [ "$3" = "${TEST_WRONG_OWNER:-}" ]; then printf '501\\n'; else printf '0\\n'; fi
else
    /usr/bin/stat "$@"
fi
""")
            stub.chmod(0o700)
            prefix = "/bin/" if command in ("launchctl", "sleep") else "/usr/bin/"
            source = source.replace(prefix + command, str(stub))
        for original, replacement in (
            ("/Library/LaunchDaemons", str(self.daemons)),
            ("/Library/PrivilegedHelperTools", str(self.parent)),
            ("/usr/local/libexec", str(self.legacy)),
            ("/var/run", str(self.runtime)),
        ):
            source = source.replace(original, replacement)
        self.script = self.sources / "install-helper.sh"
        self.script.write_text(source)
        helper_source = (PROJECT / "helper/insonia-helper.sh").read_text()
        (self.sources / "helper/insonia-helper.sh").write_text(helper_source)
        plist_source = (PROJECT / f"helper/{LABEL}.plist").read_text()
        (self.sources / f"helper/{LABEL}.plist").write_text(plist_source.replace("/Library", str(self.library)))

    def tearDown(self):
        self.fixture.cleanup()

    def run_installer(self, expected=0, *args):
        result = subprocess.run(
            ["/bin/bash", str(self.script), "--user", "appuser", *args],
            env=self.env, capture_output=True, text=True, timeout=60,
        )
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result

    def event_list(self):
        return [json.loads(line) for line in self.events.read_text().splitlines()]

    def assert_no_power_or_service_mutation(self):
        for command, *args in self.event_list():
            self.assertNotEqual(command, "pmset")
            self.assertFalse(command == "launchctl" and args[0] in ("bootout", "bootstrap", "enable"))

    def test_install_uses_protected_directory_and_v3_receipt(self):
        self.run_installer()
        self.assertEqual(self.version.read_text(), "3\n")
        self.assertEqual(self.helper.stat().st_mode & 0o777, 0o755)
        self.assertEqual(self.version.stat().st_mode & 0o777, 0o644)
        self.assertEqual(self.installed.stat().st_mode & 0o777, 0o755)
        self.assertEqual(self.power.read_text(), "0")
        self.assertTrue(self.status.read_text().startswith("3 "))
        config = plistlib.loads(self.plist.read_bytes())
        self.assertEqual(config["ProgramArguments"], [str(self.helper)])
        self.assertEqual(config["WatchPaths"], [str(self.home / "Library/Application Support/Insonia")])
        self.assertIn(str(self.home / "Library/Application Support/Insonia/desired-state"), self.helper.read_text())
        self.assertEqual(list(self.installed.glob(".install.*")), [])
        self.assertTrue((self.home / "Library/Application Support/Insonia/runtime").is_dir())
        self.assertTrue(any(event[:3] == ["sudo", "-u", "appuser"] for event in self.event_list()))

    def test_missing_parent_is_created_securely(self):
        self.parent.rmdir()
        self.run_installer()
        self.assertEqual(self.parent.stat().st_mode & 0o777, 0o755)

    def test_sticky_root_owned_parent_is_accepted(self):
        self.parent.chmod(0o1755)
        self.run_installer()
        self.assertTrue(self.helper.exists())

    def test_writable_ancestor_rejected(self):
        for mode in (0o775, 0o757):
            with self.subTest(mode=mode):
                self.library.chmod(mode)
                self.run_installer(3)
                self.assert_no_power_or_service_mutation()
        self.library.chmod(0o755)

    def test_directory_write_acl_is_rejected(self):
        subprocess.run(["/bin/chmod", "+a", "everyone allow add_file", str(self.parent)], check=True)
        self.run_installer(3)
        self.assert_no_power_or_service_mutation()

    def test_untrusted_owner_rejected(self):
        self.env["TEST_WRONG_OWNER"] = str(self.parent)
        self.run_installer(3)
        self.assert_no_power_or_service_mutation()

    def test_symlink_parent_rejected(self):
        self.parent.rmdir()
        target = self.root / "elsewhere"
        target.mkdir()
        self.parent.symlink_to(target)
        self.run_installer(3)
        self.assertEqual(list(target.iterdir()), [])
        self.assert_no_power_or_service_mutation()

    def test_symlink_destination_rejected(self):
        self.installed.mkdir()
        target = self.root / "do-not-change"
        target.write_text("keep")
        for path in (self.helper, self.version, self.plist, self.status, self.marker):
            with self.subTest(path=path):
                path.symlink_to(target)
                self.run_installer(3)
                self.assertEqual(target.read_text(), "keep")
                self.assert_no_power_or_service_mutation()
                path.unlink()

    def test_hardlinked_destination_rejected(self):
        self.installed.mkdir()
        target = self.root / "do-not-change"
        target.write_text("keep")
        os.link(target, self.helper)
        self.run_installer(3)
        self.assertEqual(target.read_text(), "keep")
        self.assert_no_power_or_service_mutation()

    def test_safe_legacy_installation_is_removed_after_migration(self):
        legacy_helper = self.legacy / "insonia-helper.sh"
        legacy_version = self.legacy / "insonia-helper.version"
        legacy_helper.write_text("old helper")
        legacy_version.write_text("2\n")
        self.service.touch()
        self.run_installer()
        self.assertFalse(legacy_helper.exists())
        self.assertFalse(legacy_version.exists())
        events = self.event_list()
        stop = next(i for i, e in enumerate(events) if e[:2] == ["launchctl", "bootout"])
        start = next(i for i, e in enumerate(events) if e[:2] == ["launchctl", "bootstrap"])
        self.assertLess(stop, start)
        self.assertTrue(self.service.exists())

    def test_unsafe_legacy_files_are_retained_and_reported(self):
        legacy_helper = self.legacy / "insonia-helper.sh"
        legacy_helper.write_text("keep")
        self.legacy.parent.chmod(0o775)
        result = self.run_installer()
        self.assertEqual(legacy_helper.read_text(), "keep")
        self.assertIn(str(legacy_helper), result.stderr)
        self.assertTrue(self.helper.exists())

    def test_obsolete_v2_receipts_are_never_accepted(self):
        old_status = self.runtime / "insonia-helper-v2-status"
        old_status.write_text("2 9999999999 0 -\n")
        self.env["TEST_RECEIPT"] = "none"
        self.run_installer(6)
        self.assertFalse(self.version.exists())
        self.assertTrue(old_status.exists())

    def test_invalid_receipt_does_not_publish_version(self):
        for receipt in ("2 0 0 -\n", "3 0 0 -\n", "3 invalid 0 -\n", "3 9999999999 0 -\n", "3 123 1 token\n"):
            with self.subTest(receipt=receipt):
                self.env["TEST_RECEIPT"] = receipt
                self.run_installer(6)
                self.assertFalse(self.version.exists())

    def test_bootstrap_failure_does_not_publish_version(self):
        self.env["TEST_BOOTSTRAP_FAILURE"] = "1"
        self.run_installer(4)
        self.assertFalse(self.version.exists())
        self.assertEqual(self.power.read_text(), "0")

    def test_bootout_failure_preserves_helper(self):
        self.run_installer()
        self.env["TEST_BOOTOUT_FAILURE"] = "1"
        self.run_installer(4, "--uninstall")
        self.assertTrue(self.helper.exists())
        self.assertTrue(self.service.exists())

    def test_uninstall_restores_and_verifies_sleep(self):
        self.run_installer()
        self.marker.touch()
        self.power.write_text("1")
        self.events.write_text("")
        self.run_installer(0, "--uninstall")
        self.assertEqual(self.power.read_text(), "0")
        for path in (self.helper, self.version, self.plist, self.status, self.marker, self.service, self.installed):
            self.assertFalse(path.exists(), str(path))
        self.assertTrue((self.home / "Library/Application Support/Insonia/runtime").is_dir())
        commands = [event for event in self.event_list() if event[0] in ("launchctl", "pmset")]
        self.assertEqual(commands[:4], [
            ["launchctl", "print", f"system/{LABEL}"],
            ["launchctl", "bootout", f"system/{LABEL}"],
            ["pmset", "-a", "disablesleep", "0"],
            ["pmset", "-g"],
        ])

    def test_failed_sleep_restore_keeps_installation_and_restarts_watchdog(self):
        self.run_installer()
        self.power.write_text("1")
        self.env["TEST_POWER_FAILURE"] = "1"
        self.run_installer(5, "--uninstall")
        self.assertEqual(self.power.read_text(), "1")
        self.assertTrue(self.helper.exists())
        self.assertTrue(self.version.exists())
        self.assertTrue(self.plist.exists())
        self.assertTrue(self.service.exists())

    def test_noop_sleep_restore_is_rejected(self):
        self.run_installer()
        self.power.write_text("1")
        self.env["TEST_POWER_NOOP"] = "1"
        self.run_installer(5, "--uninstall")
        self.assertTrue(self.helper.exists())
        self.assertTrue(self.service.exists())

    def test_uninstall_rejects_symlink_destination(self):
        self.run_installer()
        self.helper.unlink()
        target = self.root / "do-not-change"
        target.write_text("keep")
        self.helper.symlink_to(target)
        self.events.write_text("")
        self.run_installer(3, "--uninstall")
        self.assertEqual(target.read_text(), "keep")
        self.assert_no_power_or_service_mutation()

    def test_uninstall_without_installed_helper_still_verifies_sleep(self):
        self.run_installer(0, "--uninstall")
        self.assertEqual(self.power.read_text(), "0")
        self.assertFalse(self.installed.exists())

    def test_invalid_user_is_rejected(self):
        self.run_installer(2, "--user", "root")
        self.assert_no_power_or_service_mutation()


if __name__ == "__main__":
    unittest.main(verbosity=2)
