import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time


class InstallError(RuntimeError):
    pass


class MacLifecycle:
    def __init__(self, target, source, run=subprocess.run, sleep=time.sleep, clock=time.monotonic, runtime=None):
        self.target = Path(target)
        self.source = Path(source)
        self.run = run
        self.sleep = sleep
        self.clock = clock
        self.executable = self.target / "Contents/MacOS/Insonia"
        self.guardian = self.target / "Contents/Helpers/InsoniaGuard"
        self.job = f"gui/{os.getuid()}/com.henrick.insonia.guardian"
        self.runtime = runtime or Path.home() / "Library/Application Support/Insonia/runtime"
        self.prepared = False

    def command(self, arguments, timeout=15):
        try:
            return self.run([str(value) for value in arguments], capture_output=True, text=True, timeout=timeout)
        except (OSError, subprocess.TimeoutExpired) as error:
            raise InstallError("The installation operation could not be confirmed.") from error

    def json_command(self, executable, flag):
        result = self.command([executable, flag])
        try:
            value = json.loads(result.stdout)
        except (ValueError, TypeError) as error:
            raise InstallError("The application returned an invalid installation receipt.") from error
        if result.returncode or not isinstance(value, dict):
            raise InstallError("Finish the current session and its recovery before installing.")
        return value

    def ensure_idle(self):
        value = self.json_command(self.source / "Contents/MacOS/Insonia", "--check-local-update")
        if value.get("ok") is not True:
            raise InstallError("Finish the current session and its recovery before installing.")

    def ensure_no_updater(self):
        if not self.prepared and os.path.lexists(self.runtime / "update-relaunch.json"):
            raise InstallError("A previous application update is pending. Open Insonia to finish it before retrying.")
        identifier = "com.henrick.insonia"
        targets = [f"gui/{os.getuid()}/{identifier}-sparkle-updater", f"user/{os.getuid()}/{identifier}-sparkle-updater",
                   f"system/{identifier}-sparkle-updater", f"gui/{os.getuid()}/{identifier}-sparkle-progress",
                   f"user/{os.getuid()}/{identifier}-sparkle-progress"]
        for target in targets:
            result = self.command(["/bin/launchctl", "print", target])
            if result.returncode == 113:
                continue
            if result.returncode:
                raise InstallError("The application update state could not be checked.")
            pid = re.search(r"(?m)^\s*pid = (\d+)\s*$", result.stdout)
            runs = re.search(r"(?m)^\s*runs = (\d+)\s*$", result.stdout)
            if pid or not runs or int(runs[1]) == 0:
                raise InstallError("An application updater is still active; its files were preserved.")

    def identity(self, pid):
        result = self.command(["/bin/ps", "-p", str(pid), "-o", "uid=,lstart=,comm="])
        if result.returncode == 1 and not result.stdout.strip():
            return None
        if result.returncode:
            raise InstallError("The application process identity could not be checked.")
        fields = result.stdout.strip().split(None, 6)
        if len(fields) != 7 or fields[0] != str(os.getuid()):
            raise InstallError("The application process identity is invalid.")
        return tuple(fields[:6]), fields[6]

    def processes(self, executable):
        result = self.command(["/bin/ps", "-axo", "pid=,uid=,comm="])
        if result.returncode:
            raise InstallError("Running applications could not be checked.")
        values = []
        for line in result.stdout.splitlines():
            fields = line.strip().split(None, 2)
            if len(fields) == 3 and fields[2] == str(executable):
                try:
                    pid = int(fields[0])
                    if int(fields[1]) != os.getuid():
                        raise InstallError("An application process belongs to another user; its files were preserved.")
                except ValueError as error:
                    raise InstallError("The application process identity is invalid.") from error
                identity = self.identity(pid)
                if identity is not None and identity[1] == str(executable):
                    values.append((pid, identity))
        return values

    def wait_for_exit(self, identities, timeout=15):
        deadline = self.clock() + timeout
        while any(self.identity(pid) == identity for pid, identity in identities):
            if self.clock() >= deadline:
                raise InstallError("An existing application process has not finished; its files were preserved.")
            self.sleep(0.1)

    def guardian_job(self):
        result = self.command(["/bin/launchctl", "print", self.job])
        if result.returncode == 113:
            return None
        if result.returncode:
            raise InstallError("The recovery monitor registration could not be checked.")
        program = re.search(r"(?m)^\s*program = (.+)$", result.stdout)
        arguments = re.search(r"(?m)^\s*arguments = \{\n([\s\S]*?)\n\s*\}", result.stdout)
        if not program or program[1].strip() != str(self.guardian) or not arguments:
            raise InstallError("An unrelated recovery monitor was preserved.")
        values = [line.strip() for line in arguments[1].splitlines() if line.strip()]
        if values != [str(self.guardian)]:
            raise InstallError("An unrelated recovery monitor was preserved.")
        pid = re.search(r"(?m)^\s*pid = (\d+)\s*$", result.stdout)
        if re.search(r"(?m)^\s*pid =", result.stdout) and (not pid or int(pid[1]) <= 1):
            raise InstallError("The recovery monitor process identity is invalid.")
        if pid:
            identity = self.identity(int(pid[1]))
            if identity is not None and identity[1] != str(self.guardian):
                raise InstallError("The recovery monitor process changed; its files were preserved.")
        return result.stdout

    def stop(self):
        self.ensure_no_updater()
        self.ensure_idle()
        identities = self.processes(self.executable)
        if identities:
            escaped = str(self.target).replace("\\", "\\\\").replace('"', '\\"')
            result = self.command(["/usr/bin/osascript", "-e", f'tell application "{escaped}" to quit'])
            if result.returncode:
                raise InstallError("The current application did not quit; its files were preserved.")
            self.wait_for_exit(identities)
        if self.processes(self.executable):
            raise InstallError("The current application is still running; its files were preserved.")
        self.ensure_no_updater()
        self.ensure_idle()
        present = self.guardian_job() is not None
        guardians = self.processes(self.guardian)
        if present:
            result = self.command(["/bin/launchctl", "bootout", self.job])
            if result.returncode and self.guardian_job() is not None:
                raise InstallError("The recovery monitor did not stop; its files were preserved.")
        elif guardians:
            raise InstallError("An unregistered recovery monitor is still running; its files were preserved.")
        self.wait_for_exit(guardians)
        if self.guardian_job() is not None or self.processes(self.guardian):
            raise InstallError("The recovery monitor is still running; its files were preserved.")
        self.ensure_idle()

    def prepare(self):
        value = self.json_command(self.source / "Contents/MacOS/Insonia", "--prepare-local-update")
        if value.get("ok") is not True:
            raise InstallError("The update relaunch could not be prepared.")
        self.prepared = True

    def launch(self):
        for attempt in range(3):
            result = self.command(["/usr/bin/open", "-a", str(self.target), "--args", "--open-panel"])
            if result.returncode == 0:
                return
            if attempt < 2:
                result = self.command(["/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", "-f", str(self.target)])
                if result.returncode:
                    break
                self.sleep(0.5)
        raise InstallError("The new application could not be opened.")

    def wait_until_ready(self, timeout=15):
        deadline = self.clock() + timeout
        while True:
            if self.processes(self.executable):
                value = self.json_command(self.executable, "--diagnostics")
                if value.get("mode") is not None or value.get("sleepDisabled") is not False or value.get("brightnessRecoveryPending") is not False:
                    raise InstallError("The new application has an active or recovering session; cleanup was deferred.")
                if value.get("guardianHealthy") is True:
                    self.ensure_idle()
                    return
            if self.clock() >= deadline:
                raise InstallError("The new application did not confirm readiness.")
            self.sleep(0.1)


def install(source, target, reference, transaction_factory=None, lifecycle=None):
    if transaction_factory is None:
        from app_bundle import BundleTransaction
        transaction_factory = BundleTransaction
    source, target, reference = Path(source), Path(target), Path(reference)
    transaction = transaction_factory(target, reference)
    lifecycle = lifecycle or MacLifecycle(target, source)
    with transaction.locked():
        transaction.validate(source)
        if target.exists():
            transaction.validate(target)
        lifecycle.ensure_no_updater()
        lifecycle.ensure_idle()
        lifecycle.stop()
        lifecycle.prepare()
        transaction.replace(source, defer_cleanup=True)
        try:
            lifecycle.launch()
            lifecycle.wait_until_ready()
        except Exception as failure:
            try:
                lifecycle.stop()
                transaction.rollback()
            except Exception as recovery:
                raise InstallError("Installation did not finish. Its recovery transaction was preserved; finish any active session before retrying.") from recovery
            raise InstallError("Installation did not finish; the previous application was restored.") from failure
        try:
            transaction.commit()
        except Exception:
            return {"status": "installed_cleanup_pending", "target": str(target)}
    return {"status": "installed", "target": str(target)}


def main():
    root = Path(__file__).resolve().parents[1]
    if len(sys.argv) != 1:
        raise InstallError("Usage: ./install-app.sh")
    result = install(root / "build/products.noindex/Insonia.app", Path("/Applications/Insonia.app"), root / "Info.plist")
    print("Installed: " + result["target"])
    if result["status"] == "installed_cleanup_pending":
        print("The application is ready, but retirement cleanup is pending. Run the installer again after ongoing work finishes.")
        return 1
    print("The previous application was removed after the new application confirmed readiness.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
