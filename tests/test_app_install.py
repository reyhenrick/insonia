import importlib.util
import base64
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from contextlib import contextmanager


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("install_app", ROOT / "scripts/install_app.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FakeTransaction:
    def __init__(self, target, reference, events):
        self.target = target
        self.events = events
        self.old = None
        self.fail_validate = None
        self.fail_commit = False
        self.fail_rollback = False

    @contextmanager
    def locked(self):
        self.events.append("lock")
        try:
            yield self
        finally:
            self.events.append("unlock")

    def validate(self, path):
        self.events.append("validate:" + path.name)
        if path == self.fail_validate:
            raise RuntimeError("Wrong application identity")

    def replace(self, source, defer_cleanup=False):
        self.events.append("replace")
        if not defer_cleanup:
            raise AssertionError("Retirement must wait for runtime readiness")
        self.old = (self.target / "payload").read_text() if self.target.exists() else None
        self.target.mkdir(exist_ok=True)
        (self.target / "payload").write_text((source / "payload").read_text())

    def commit(self):
        self.events.append("commit")
        if self.fail_commit:
            raise RuntimeError("Cleanup unavailable")
        self.old = None

    def rollback(self):
        self.events.append("rollback")
        if self.fail_rollback:
            raise RuntimeError("Rollback unavailable")
        if self.old is None:
            shutil.rmtree(self.target)
        else:
            (self.target / "payload").write_text(self.old)
        self.old = None


class FakeLifecycle:
    def __init__(self, events):
        self.events = events
        self.fail = None
        self.stops = 0

    def event(self, name):
        self.events.append(name)
        if self.fail == name:
            raise MODULE.InstallError("Synthetic " + name + " failure")

    def ensure_no_updater(self):
        self.event("updater")

    def ensure_idle(self):
        self.event("idle")

    def stop(self):
        self.stops += 1
        self.event("stop" if self.stops == 1 else "stop-new")

    def prepare(self):
        self.event("prepare")

    def launch(self):
        self.event("launch")

    def wait_until_ready(self):
        self.event("ready")


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(suffix=".noindex")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.source = self.root / "Source.app"
        self.target = self.root / "Insonia.app"
        self.reference = self.root / "Info.plist"
        for path, value in [(self.source, "new"), (self.target, "old")]:
            path.mkdir()
            (path / "payload").write_text(value)
        self.events = []
        self.transaction = FakeTransaction(self.target, self.reference, self.events)
        self.lifecycle = FakeLifecycle(self.events)

    def install(self):
        return MODULE.install(self.source, self.target, self.reference,
                              transaction_factory=lambda *_: self.transaction, lifecycle=self.lifecycle)

    def test_success_waits_for_readiness_before_retirement(self):
        result = self.install()
        self.assertEqual(result["status"], "installed")
        self.assertEqual((self.target / "payload").read_text(), "new")
        self.assertIsNone(self.transaction.old)
        self.assertLess(self.events.index("validate:Source.app"), self.events.index("stop"))
        self.assertLess(self.events.index("prepare"), self.events.index("replace"))
        self.assertLess(self.events.index("ready"), self.events.index("commit"))
        self.assertEqual(self.events[-1], "unlock")

    def test_repeated_success_creates_no_backup_history(self):
        self.install()
        (self.source / "payload").write_text("newer")
        self.install()
        self.assertEqual((self.target / "payload").read_text(), "newer")
        self.assertIsNone(self.transaction.old)
        self.assertEqual(sorted(path.name for path in self.root.iterdir()), ["Insonia.app", "Source.app"])

    def test_untrusted_source_or_target_cannot_stop_app(self):
        for invalid in [self.source, self.target]:
            with self.subTest(invalid=invalid):
                self.events.clear()
                self.transaction.fail_validate = invalid
                with self.assertRaises(RuntimeError):
                    self.install()
                self.assertNotIn("stop", self.events)
                self.assertNotIn("replace", self.events)
                self.assertEqual((self.target / "payload").read_text(), "old")

    def test_active_session_pending_updater_or_failed_stop_preserves_target(self):
        for failure in ["updater", "idle", "stop", "prepare"]:
            with self.subTest(failure=failure):
                self.events.clear()
                self.lifecycle.fail = failure
                self.lifecycle.stops = 0
                with self.assertRaises(MODULE.InstallError):
                    self.install()
                self.assertNotIn("replace", self.events)
                self.assertEqual((self.target / "payload").read_text(), "old")

    def test_failed_launch_or_readiness_restores_previous_app(self):
        for failure in ["launch", "ready"]:
            with self.subTest(failure=failure):
                self.lifecycle.fail = failure
                self.lifecycle.stops = 0
                self.events.clear()
                with self.assertRaisesRegex(MODULE.InstallError, "previous application was restored"):
                    self.install()
                self.assertEqual((self.target / "payload").read_text(), "old")
                self.assertIn("stop-new", self.events)
                self.assertNotIn("commit", self.events)

    def test_uncertain_new_session_preserves_recovery_transaction(self):
        self.lifecycle.fail = "ready"
        original_stop = self.lifecycle.stop
        def stop():
            if self.lifecycle.stops:
                raise MODULE.InstallError("New session is active")
            original_stop()
        self.lifecycle.stop = stop
        with self.assertRaisesRegex(MODULE.InstallError, "recovery transaction was preserved"):
            self.install()
        self.assertEqual((self.target / "payload").read_text(), "new")
        self.assertEqual(self.transaction.old, "old")
        self.assertNotIn("rollback", self.events)

    def test_failed_rollback_preserves_recoverable_old_app(self):
        self.lifecycle.fail = "ready"
        self.transaction.fail_rollback = True
        with self.assertRaisesRegex(MODULE.InstallError, "recovery transaction was preserved"):
            self.install()
        self.assertEqual(self.transaction.old, "old")
        self.assertNotIn("commit", self.events)

    def test_failed_cleanup_keeps_healthy_new_app(self):
        self.transaction.fail_commit = True
        result = self.install()
        self.assertEqual(result["status"], "installed_cleanup_pending")
        self.assertEqual((self.target / "payload").read_text(), "new")
        self.assertEqual(self.transaction.old, "old")
        self.assertNotIn("rollback", self.events)


class CommandFixture:
    def __init__(self, target, source):
        self.target, self.source = target, source
        self.gui = True
        self.guardian = True
        self.registered = True
        self.fail_bootout = False
        self.stall_guardian = False
        self.foreign_guardian = False
        self.idle = True
        self.updater = False
        self.guardian_ready = True
        self.foreign_gui_owner = False
        self.open_failures = 0
        self.calls = []
        self.time = 0

    def sleep(self, interval):
        self.time += interval

    def run(self, args, **_):
        self.calls.append(args)
        code, output = 0, ""
        executable = str(self.target / "Contents/MacOS/Insonia")
        guardian = str(self.target / "Contents/Helpers/InsoniaGuard")
        if args[0] == "/bin/ps" and args[1] == "-axo":
            gui_owner = os.getuid() + 1 if self.foreign_gui_owner else os.getuid()
            output = (f"101 {gui_owner} " + executable + "\n" if self.gui else "") + (f"202 {os.getuid()} " + guardian + "\n" if self.guardian else "")
        elif args[0] == "/bin/ps":
            pid = int(args[2]); alive = self.gui if pid == 101 else self.guardian
            code = 0 if alive else 1
            output = f"{os.getuid()} Fri Oct 30 12:00:00 2026 " + (executable if pid == 101 else guardian) if alive else ""
        elif args[0] == "/usr/bin/osascript":
            self.gui = False
        elif args[0] == "/bin/launchctl" and args[1] == "print":
            if "sparkle" in args[2]:
                code, output = (0, "pid = 303\n") if self.updater else (113, "")
            elif not self.registered:
                code = 113
            else:
                program = "/unrelated/guardian" if self.foreign_guardian else guardian
                output = f"program = {program}\narguments = {{\n{program}\n}}\npid = 202\n"
        elif args[0] == "/bin/launchctl" and args[1] == "bootout":
            if self.fail_bootout:
                code = 1
            else:
                self.registered = False
                if not self.stall_guardian:
                    self.guardian = False
        elif args[-1] in ["--check-local-update", "--prepare-local-update"]:
            code = 0 if self.idle else 1
            output = json.dumps({"ok": self.idle})
        elif args[-1] == "--diagnostics":
            output = json.dumps({"guardianHealthy": self.guardian_ready, "sleepDisabled": not self.idle,
                                 "brightnessRecoveryPending": False, "mode": None})
        elif args[0] == "/usr/bin/open":
            if self.open_failures:
                self.open_failures -= 1
                code = 1
            else:
                self.gui, self.guardian, self.registered = True, True, True
        elif args[0].endswith("/lsregister"):
            pass
        else:
            raise AssertionError("Unexpected command: " + repr(args))
        return subprocess.CompletedProcess(args, code, output, "")


class MacLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(suffix=".noindex")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.target = self.root / "Insonia.app"
        self.source = self.root / "Source.app"
        self.fixture = CommandFixture(self.target, self.source)
        self.lifecycle = MODULE.MacLifecycle(self.target, self.source, run=self.fixture.run,
                                            sleep=self.fixture.sleep, clock=lambda: self.fixture.time,
                                            runtime=self.root / "runtime")

    def test_stop_waits_for_both_owned_processes(self):
        self.lifecycle.stop()
        self.assertFalse(self.fixture.gui)
        self.assertFalse(self.fixture.guardian)
        self.assertFalse(self.fixture.registered)
        scripts = [args for args in self.fixture.calls if args[0] == "/usr/bin/osascript"]
        self.assertEqual(scripts, [["/usr/bin/osascript", "-e", f'tell application "{self.target}" to quit']])
        self.assertFalse(any("pmset" in argument or "sudo" in argument for args in self.fixture.calls for argument in args))

    def test_failed_guardian_bootout_never_retires_bundle(self):
        self.fixture.fail_bootout = True
        with self.assertRaisesRegex(MODULE.InstallError, "recovery monitor did not stop"):
            self.lifecycle.stop()
        self.assertTrue(self.fixture.guardian)
        self.assertTrue(self.fixture.registered)

    def test_guardian_still_exiting_blocks_replacement(self):
        self.fixture.stall_guardian = True
        with self.assertRaisesRegex(MODULE.InstallError, "has not finished"):
            self.lifecycle.stop()
        self.assertTrue(self.fixture.guardian)

    def test_foreign_guardian_is_preserved(self):
        self.fixture.foreign_guardian = True
        with self.assertRaisesRegex(MODULE.InstallError, "unrelated recovery monitor"):
            self.lifecycle.stop()
        self.assertFalse(any(args[1:2] == ["bootout"] for args in self.fixture.calls))

    def test_active_session_does_not_quit_anything(self):
        self.fixture.idle = False
        with self.assertRaises(MODULE.InstallError):
            self.lifecycle.stop()
        self.assertTrue(self.fixture.gui)
        self.assertFalse(any(args[0] == "/usr/bin/osascript" for args in self.fixture.calls))

    def test_another_users_app_cannot_be_quit(self):
        self.fixture.foreign_gui_owner = True
        with self.assertRaisesRegex(MODULE.InstallError, "belongs to another user"):
            self.lifecycle.stop()
        self.assertFalse(any(args[0] == "/usr/bin/osascript" for args in self.fixture.calls))

    def test_pending_sparkle_or_marker_blocks_local_installer(self):
        self.fixture.updater = True
        with self.assertRaisesRegex(MODULE.InstallError, "updater is still active"):
            self.lifecycle.stop()
        self.fixture.updater = False
        self.lifecycle.runtime.mkdir()
        (self.lifecycle.runtime / "update-relaunch.json").write_text("{}")
        with self.assertRaisesRegex(MODULE.InstallError, "previous application update is pending"):
            self.lifecycle.stop()

    def test_readiness_requires_live_gui_and_recovery_monitor(self):
        self.lifecycle.stop()
        self.lifecycle.prepare()
        self.lifecycle.launch()
        self.lifecycle.wait_until_ready()
        self.assertTrue(self.lifecycle.prepared)
        self.fixture.guardian_ready = False
        with self.assertRaisesRegex(MODULE.InstallError, "did not confirm readiness"):
            self.lifecycle.wait_until_ready(timeout=0.3)

    def test_reused_pid_is_not_waited_or_signalled(self):
        self.lifecycle.wait_for_exit([(202, (("different",), str(self.lifecycle.guardian)))], timeout=0)
        self.assertFalse(any(args[0] in ["kill", "/bin/kill"] for args in self.fixture.calls))

    def test_stale_launch_registration_is_refreshed_and_retried(self):
        self.fixture.open_failures = 1
        self.lifecycle.launch()
        self.assertEqual(sum(args[0] == "/usr/bin/open" for args in self.fixture.calls), 2)
        self.assertEqual(sum(args[0].endswith("/lsregister") for args in self.fixture.calls), 1)

    def test_failed_launch_retry_is_bounded(self):
        self.fixture.open_failures = 10
        with self.assertRaisesRegex(MODULE.InstallError, "could not be opened"):
            self.lifecycle.launch()
        self.assertEqual(sum(args[0] == "/usr/bin/open" for args in self.fixture.calls), 3)


class TransactionIntegrationTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location("app_bundle_for_install_test", ROOT / "scripts/app_bundle.py")
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.temp = tempfile.TemporaryDirectory(suffix=".noindex")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.reference = self.root / "Info.plist"
        info = {"CFBundleIdentifier": "com.henrick.insonia", "CFBundleVersion": "9",
                "SUPublicEDKey": base64.b64encode(bytes(range(32))).decode()}
        self.reference.write_bytes(plistlib.dumps(info))
        self.source, self.target = self.root / "Source.app", self.root / "Insonia.app"
        for path, value in [(self.source, "new"), (self.target, "old")]:
            (path / "Contents").mkdir(parents=True)
            (path / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
            (path / "payload").write_text(value)
        self.events = []
        self.lifecycle = FakeLifecycle(self.events)
        self.cleanup_failure = False
        def registrar(path, registered):
            if self.cleanup_failure and not registered:
                raise self.module.BundleError("Synthetic unregister failure")
        self.transaction = self.module.BundleTransaction(self.target, self.reference,
            validator=lambda _: None, activity=lambda _: False,
            registrar=registrar, copier=lambda source, target: shutil.copytree(source, target, dirs_exist_ok=True))

    def install(self):
        return MODULE.install(self.source, self.target, self.reference,
                              transaction_factory=lambda *_: self.transaction, lifecycle=self.lifecycle)

    def test_real_atomic_replacements_retire_only_after_ready(self):
        self.assertEqual(self.install()["status"], "installed")
        self.assertFalse(self.transaction.directory.exists())
        self.assertEqual((self.target / "payload").read_text(), "new")
        (self.source / "payload").write_text("newer")
        self.assertEqual(self.install()["status"], "installed")
        self.assertEqual((self.target / "payload").read_text(), "newer")
        self.assertFalse(self.transaction.pending)

    def test_real_rollback_restores_the_previous_application(self):
        self.lifecycle.fail = "ready"
        with self.assertRaisesRegex(MODULE.InstallError, "previous application was restored"):
            self.install()
        self.assertEqual((self.target / "payload").read_text(), "old")
        self.assertFalse(self.transaction.pending)

    def test_cleanup_error_keeps_new_app_and_exact_committed_recovery(self):
        self.cleanup_failure = True
        self.assertEqual(self.install()["status"], "installed_cleanup_pending")
        self.assertEqual((self.target / "payload").read_text(), "new")
        self.assertTrue(self.transaction.pending)
        self.assertTrue(json.loads(self.transaction.journal.read_text())["committed"])
        self.cleanup_failure = False
        self.transaction.commit()
        self.assertFalse(self.transaction.pending)


if __name__ == "__main__":
    unittest.main(verbosity=2)
