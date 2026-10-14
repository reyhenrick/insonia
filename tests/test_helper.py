"""Behavioral tests execute the production watchdog with pmset isolated in a fixture."""
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest


class WatchdogTests(unittest.TestCase):
    def setUp(self):
        self.fixture = tempfile.TemporaryDirectory(prefix="helper-test-", dir="build")
        self.root = Path(self.fixture.name).resolve()
        self.state = self.root / "desired-state"
        self.heartbeat = self.root / "heartbeat"
        self.power = self.root / "power"
        self.marker = self.root / "booted"
        self.status = self.root / "status"
        self.power.write_text("1")
        self.state.write_text("1")
        self.heartbeat.write_text("6BF05EB6-F3B5-4BBE-A97B-38BF0E3E4791\n")
        stub = self.root / "pmset"
        stub.write_text("""#!/bin/bash
set -eu
if [ "$1" = -g ]; then
    [ ! -f "$TEST_READ_FAIL_FILE" ] || exit 1
    printf ' SleepDisabled %s\\n' "$(cat "$TEST_POWER_FILE")"
else
    [ ! -f "$TEST_FAIL_FILE" ] || exit 1
    [ ! -f "$TEST_NOOP_FILE" ] || exit 0
    printf '%s' "$3" > "$TEST_POWER_FILE"
fi
""")
        stub.chmod(0o700)
        source = Path("helper/insonia-helper.sh").read_text()
        for original, replacement in {
            "__STATE_FILE__": str(self.state), "__HEARTBEAT_FILE__": str(self.heartbeat),
            "__OWNER_UID__": str(os.getuid()), "/usr/bin/pmset": str(stub),
            "ROOT_UID='0'": f"ROOT_UID='{os.getuid()}'",
            "/var/run/insonia-helper-v3-booted": str(self.marker),
            "/var/run/insonia-helper-v3-status": str(self.status),
        }.items():
            source = source.replace(original, replacement)
        self.script = self.root / "watchdog.sh"
        self.script.write_text(source)
        self.env = {
            **os.environ, "TEST_POWER_FILE": str(self.power),
            "TEST_FAIL_FILE": str(self.root / "fail"),
            "TEST_READ_FAIL_FILE": str(self.root / "read-fail"),
            "TEST_NOOP_FILE": str(self.root / "noop"),
        }
        self.run_watchdog()

    def tearDown(self):
        self.fixture.cleanup()

    def run_watchdog(self, success=True):
        result = subprocess.run(["/bin/bash", str(self.script)], env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, success, result.stderr)
        return result

    def fresh(self):
        now = time.time()
        os.utime(self.heartbeat, (now, now))

    def pause_snapshot(self, mutation):
        ready = self.root / "ready"
        release = self.root / "release"
        once = self.root / "pause-once"
        once.touch()
        hook = f'''\n    if [ -f '{once}' ]; then
        /bin/rm '{once}'
        /usr/bin/touch '{ready}'
        while [ ! -f '{release}' ]; do /bin/sleep 0.01; done
    fi\n'''
        self.script.write_text(self.script.read_text().replace('    raw_stamp="$stamp"', '    raw_stamp="$stamp"' + hook))
        child = subprocess.Popen(["/bin/bash", str(self.script)], env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 5
            while not ready.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(ready.exists(), "watchdog did not reach snapshot checkpoint")
            mutation()
            release.touch()
            _, error = child.communicate(timeout=5)
            self.assertEqual(child.returncode, 0, error.decode())
        finally:
            release.touch()
            if child.poll() is None:
                child.terminate(); child.wait(timeout=5)

    def test_boot_always_reverts(self):
        self.assertEqual(self.power.read_text(), "0")
        self.assertTrue(self.status.read_text().startswith("3 "))

    def test_fresh_lease_enables(self):
        self.fresh(); self.run_watchdog()
        self.assertEqual(self.power.read_text(), "1")
        self.assertEqual(self.status.read_text().split()[3], self.heartbeat.read_text().strip())

    def test_off_on_during_snapshot_does_not_disable_new_session(self):
        self.fresh(); self.run_watchdog()
        self.state.write_text("0")
        def begin_new_session():
            self.heartbeat.write_text("00AF8EE2-C42A-419D-8086-20357C8D94CB\n")
            self.fresh(); self.state.write_text("1")
        self.pause_snapshot(begin_new_session)
        self.assertEqual(self.power.read_text(), "1", "stale stop must not turn off a new session")
        self.assertNotEqual(self.status.read_text().split()[3], self.heartbeat.read_text().strip())
        self.run_watchdog()
        self.assertEqual(self.status.read_text().split()[3], self.heartbeat.read_text().strip())

    def test_renewal_across_second_boundary_not_treated_as_future(self):
        self.fresh(); self.run_watchdog()
        def renew():
            time.sleep(1.1)
            self.fresh()
        self.pause_snapshot(renew)
        self.assertEqual(self.power.read_text(), "1")

    def test_stale_lease_reverts(self):
        self.fresh(); self.run_watchdog()
        os.utime(self.heartbeat, (time.time() - 31, time.time() - 31))
        self.run_watchdog()
        self.assertEqual(self.power.read_text(), "0")

    def test_future_heartbeat_rejected(self):
        os.utime(self.heartbeat, (time.time() + 100, time.time() + 100))
        self.run_watchdog(); self.assertEqual(self.power.read_text(), "0")

    def test_previous_boot_heartbeat_rejected(self):
        stamp = int(self.marker.stat().st_mtime) - 1
        os.utime(self.heartbeat, (stamp, stamp))
        self.run_watchdog(); self.assertEqual(self.power.read_text(), "0")

    def test_missing_heartbeat_reverts(self):
        self.fresh(); self.run_watchdog(); self.heartbeat.unlink()
        self.run_watchdog(); self.assertEqual(self.power.read_text(), "0")

    def test_missing_request_reverts(self):
        self.fresh(); self.run_watchdog(); self.state.unlink()
        self.run_watchdog(); self.assertEqual(self.power.read_text(), "0")

    def test_symlink_request_reverts(self):
        self.fresh(); self.run_watchdog()
        target = self.root / "request-target"; target.write_text("1")
        self.state.unlink(); self.state.symlink_to(target)
        self.run_watchdog(); self.assertEqual(self.power.read_text(), "0")

    def test_invalid_session_token_rejected(self):
        self.heartbeat.write_text("invalid")
        self.fresh(); self.run_watchdog()
        self.assertEqual(self.power.read_text(), "0")

    def test_invalid_request_rejected(self):
        self.fresh(); self.state.write_text("10")
        self.run_watchdog(); self.assertEqual(self.power.read_text(), "0")

    def test_symlink_heartbeat_rejected(self):
        target = self.root / "other"; target.write_text("alive")
        self.heartbeat.unlink(); self.heartbeat.symlink_to(target)
        self.run_watchdog(); self.assertEqual(self.power.read_text(), "0")

    def test_wrong_owner_rejected(self):
        self.fresh()
        self.script.write_text(self.script.read_text().replace(f"OWNER_UID='{os.getuid()}'", "OWNER_UID='99999'"))
        self.run_watchdog(); self.assertEqual(self.power.read_text(), "0")

    def test_disabled_request_reverts(self):
        self.fresh(); self.run_watchdog(); self.state.write_text("0")
        self.run_watchdog(); self.assertEqual(self.power.read_text(), "0")

    def test_pmset_failure_does_not_acknowledge(self):
        self.fresh(); self.status.unlink(); (self.root / "fail").touch()
        self.run_watchdog(success=False)
        self.assertFalse(self.status.exists())

    def test_symlink_receipt_cannot_be_written(self):
        target = self.root / "receipt-target"
        target.write_text("unchanged")
        self.status.unlink()
        self.status.symlink_to(target)
        self.power.write_text("1")
        result = self.run_watchdog(success=False)
        self.assertEqual(result.returncode, 3)
        self.assertEqual(target.read_text(), "unchanged")
        self.assertEqual(self.power.read_text(), "0")

    def test_symlink_boot_marker_cannot_be_written(self):
        target = self.root / "marker-target"
        target.write_text("unchanged")
        self.marker.unlink()
        self.marker.symlink_to(target)
        self.power.write_text("1")
        result = self.run_watchdog(success=False)
        self.assertEqual(result.returncode, 3)
        self.assertEqual(target.read_text(), "unchanged")
        self.assertEqual(self.power.read_text(), "0")

    def test_writable_runtime_receipt_is_rejected(self):
        self.status.chmod(0o666)
        self.power.write_text("1")
        result = self.run_watchdog(success=False)
        self.assertEqual(result.returncode, 3)
        self.assertEqual(self.power.read_text(), "0")

    def test_untrusted_runtime_owner_is_rejected(self):
        self.script.write_text(self.script.read_text().replace(f"ROOT_UID='{os.getuid()}'", "ROOT_UID='99999'"))
        self.power.write_text("1")
        result = self.run_watchdog(success=False)
        self.assertEqual(result.returncode, 3)
        self.assertEqual(self.power.read_text(), "0")

    def test_hardlinked_boot_marker_is_rejected(self):
        os.link(self.marker, self.root / "marker-alias")
        self.power.write_text("1")
        result = self.run_watchdog(success=False)
        self.assertEqual(result.returncode, 3)
        self.assertEqual(self.power.read_text(), "0")

    def test_noop_pmset_does_not_acknowledge(self):
        self.fresh()
        self.status.unlink()
        (self.root / "noop").touch()
        result = self.run_watchdog(success=False)
        self.assertEqual(result.returncode, 5)
        self.assertFalse(self.status.exists())

    def test_failed_power_read_does_not_acknowledge(self):
        self.fresh()
        self.status.unlink()
        (self.root / "read-fail").touch()
        self.run_watchdog(success=False)
        self.assertFalse(self.status.exists())

    def test_failed_first_boot_restore_does_not_create_marker(self):
        self.marker.unlink()
        self.status.unlink()
        self.power.write_text("1")
        (self.root / "noop").touch()
        result = self.run_watchdog(success=False)
        self.assertEqual(result.returncode, 5)
        self.assertFalse(self.marker.exists())
        self.assertFalse(self.status.exists())

    def test_receipt_is_readable_without_write_access(self):
        self.assertEqual(self.status.stat().st_mode & 0o777, 0o644)
        self.assertEqual(list(self.root.glob("status.*")), [])
        self.assertEqual(list(self.root.glob(".runtime.*")), [])

    def test_receipt_publication_does_not_follow_replaced_symlink(self):
        target = self.root / "receipt-directory"
        target.mkdir()
        sentinel = target / "status"
        sentinel.write_text("unchanged")
        statement = '/bin/mv -fh "$STATUS_TMP" "$STATUS_FILE"'
        replacement = f"/bin/rm -f \"$STATUS_FILE\"\n/bin/ln -s '{target}' \"$STATUS_FILE\"\n" + statement
        self.script.write_text(self.script.read_text().replace(statement, replacement))
        self.run_watchdog()
        self.assertEqual(sentinel.read_text(), "unchanged")
        self.assertFalse(self.status.is_symlink())
        self.assertTrue(self.status.read_text().startswith("3 "))
        self.assertEqual(list(self.root.glob(".runtime.*")), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
