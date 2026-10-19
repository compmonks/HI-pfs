"""Exercise storage guards without running installers or privileged commands."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
BASH = shutil.which("bash")
RMDIR = shutil.which("rmdir")
CLEANUP_SCRIPTS = ("init.sh", "bootstrap.sh")


def shell_function(script, name):
    """Read a top-level function only; never source the destructive script."""
    source = (ROOT / "scripts" / script).read_text(encoding="utf-8")
    match = re.search(r"^" + name + r"\(\) \{\n.*?^\}", source, re.M | re.S)
    if match is None:
        raise AssertionError("Storage guard function missing: " + name)
    return match.group(0)


@unittest.skipUnless(BASH and RMDIR, "Requires bash and rmdir")
class StorageSafetyTests(unittest.TestCase):
    """Use real temporary directories, but mocked mount/privilege operations."""

    def run_cleanup(self, script, mount_path, mounted="0", unmount_status="0"):
        """Invoke just the guard with a strictly allowlisted sudo replacement."""
        mocks = r'''
log() { printf '%s\n' "$1"; }
mountpoint() { [[ "$MOCK_MOUNTED" == "1" ]]; }
sudo() {
  printf 'mock sudo: %s\n' "$*" >&2
  [[ "$#" == 3 && "$2" == "--" && "$3" == "$TEST_MOUNT" ]] || return 99
  case "$1" in
    umount) return "$MOCK_UNMOUNT_STATUS" ;;
    rmdir) "$TEST_RMDIR" -- "$TEST_MOUNT" ;;
    *) return 99 ;;
  esac
}
'''
        environment = {
            **os.environ,
            "TEST_MOUNT": str(mount_path),
            "TEST_RMDIR": RMDIR,
            "MOCK_MOUNTED": mounted,
            "MOCK_UNMOUNT_STATUS": unmount_status,
        }
        code = mocks + shell_function(script, "unmount_ssd")
        code += '\nunmount_ssd "$TEST_MOUNT" || exit 1\necho CONTINUED\n'
        return subprocess.run(
            [BASH, "--noprofile", "--norc", "-eu", "-c", code],
            env=environment, capture_output=True, text=True, check=False, timeout=5,
        )

    def test_failed_unmount_aborts_before_removing_even_empty_directory(self):
        """An unmount error cannot fall through to later cleanup."""
        for script in CLEANUP_SCRIPTS:
            with self.subTest(script=script), tempfile.TemporaryDirectory() as root:
                mount_path = Path(root) / "mount"
                mount_path.mkdir()
                result = self.run_cleanup(script, mount_path, mounted="1", unmount_status="32")
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(mount_path.is_dir())
                self.assertNotIn("rmdir", result.stderr)
                self.assertNotIn("CONTINUED", result.stdout)

    def test_successful_unmount_removes_only_empty_mount_directory(self):
        """A confirmed unmount permits nonrecursive empty-directory removal."""
        for script in CLEANUP_SCRIPTS:
            with self.subTest(script=script), tempfile.TemporaryDirectory() as root:
                mount_path = Path(root) / "mount"
                mount_path.mkdir()
                result = self.run_cleanup(script, mount_path, mounted="1")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse(mount_path.exists())
                self.assertIn("umount --", result.stderr)
                self.assertIn("rmdir --", result.stderr)

    def test_nonempty_directory_is_preserved_even_after_unmount_success(self):
        """Local data, or a raced remount, must never be recursively removed."""
        for script in CLEANUP_SCRIPTS:
            for mounted in ("0", "1"):
                with self.subTest(script=script, mounted=mounted):
                    with tempfile.TemporaryDirectory() as root:
                        mount_path = Path(root) / "mount"
                        mount_path.mkdir()
                        data = mount_path / "keep.txt"
                        data.write_text("preserve this data", encoding="utf-8")
                        result = self.run_cleanup(script, mount_path, mounted=mounted)
                        self.assertNotEqual(result.returncode, 0)
                        self.assertEqual(data.read_text(encoding="utf-8"), "preserve this data")
                        self.assertNotIn("CONTINUED", result.stdout)

    def test_absent_and_empty_unmounted_paths_are_safe(self):
        """Repeated cleanup needs neither an unmount nor recursive deletion."""
        for script in CLEANUP_SCRIPTS:
            for exists in (False, True):
                with self.subTest(script=script, exists=exists):
                    with tempfile.TemporaryDirectory() as root:
                        mount_path = Path(root) / "mount"
                        if exists:
                            mount_path.mkdir()
                        result = self.run_cleanup(script, mount_path)
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertFalse(mount_path.exists())
                        self.assertNotIn("umount --", result.stderr)

    def test_symlink_is_refused_without_touching_target(self):
        """An unexpected path alias is not a cleanup destination."""
        for script in CLEANUP_SCRIPTS:
            with self.subTest(script=script), tempfile.TemporaryDirectory() as root:
                target = Path(root) / "target"
                target.mkdir()
                mount_path = Path(root) / "mount"
                mount_path.symlink_to(target, target_is_directory=True)
                result = self.run_cleanup(script, mount_path)
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(mount_path.is_symlink())
                self.assertTrue(target.is_dir())
                self.assertNotIn("mock sudo:", result.stderr)

    def test_unknown_and_unsupported_filesystems_are_refused(self):
        """Blank/encrypted/unsupported devices require separate preparation."""
        guard = shell_function("setup.sh", "require_supported_filesystem")
        for filesystem in ("", "crypto_LUKS", "btrfs", "unreadable"):
            with self.subTest(filesystem=filesystem):
                result = subprocess.run(
                    [BASH, "-eu", "-c", guard + '\nrequire_supported_filesystem "$1" /dev/mock',
                     "test", filesystem],
                    capture_output=True, text=True, check=False, timeout=5,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Refusing to format", result.stderr)

    def test_supported_filesystems_are_accepted(self):
        """Existing supported filesystems retain their mount path."""
        guard = shell_function("setup.sh", "require_supported_filesystem")
        for filesystem in ("ext4", "exfat", "ntfs"):
            with self.subTest(filesystem=filesystem):
                result = subprocess.run(
                    [BASH, "-eu", "-c", guard + '\nrequire_supported_filesystem "$1" /dev/mock',
                     "test", filesystem],
                    capture_output=True, text=True, check=False, timeout=5,
                )
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_standalone_entrypoints_use_the_guards(self):
        """Keep duplicated standalone helpers and their call sites in sync."""
        self.assertEqual(
            shell_function("init.sh", "unmount_ssd"),
            shell_function("bootstrap.sh", "unmount_ssd"),
        )
        for script in CLEANUP_SCRIPTS:
            source = (ROOT / "scripts" / script).read_text(encoding="utf-8")
            self.assertIn("unmount_ssd || exit 1", source)
            self.assertNotRegex(source, r"rm\s+-rf\s+/mnt/ipfs")
        source = (ROOT / "scripts" / "setup.sh").read_text(encoding="utf-8")
        guard = 'require_supported_filesystem "$FSTYPE" "$PART" || return 1'
        self.assertLess(source.index(guard), source.index('sudo mount -t "$FSTYPE"'))
        self.assertNotIn("mkfs.", source)


if __name__ == "__main__":
    unittest.main()
