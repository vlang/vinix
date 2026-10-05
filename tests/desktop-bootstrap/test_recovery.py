#!/usr/bin/env python3
"""Check disk-root recovery preparation without running QEMU or touching disks."""

import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / "scripts/run-aarch64.sh"

TOOL_STUB = r'''
import json
import os
from pathlib import Path
import sys

tool = Path(sys.argv[0]).name
args = sys.argv[1:]
output = Path(args[args.index("-o") + 1])
with Path(os.environ["TEST_EVENTS"]).open("a") as events:
    events.write(json.dumps({"tool": tool, "args": args,
                            "init_published": (Path(os.environ["TEST_INIT_DIR"]) / "init").exists()}) + "\n")
output.write_bytes(b"fixture " + tool.encode())
if os.environ.get("TEST_FAIL_TOOL") == tool:
    sys.exit(23)
'''


def runner_function(name):
    # Top-level function braces start in column zero; their bodies' braces are
    # indented. Include the real body so the checks follow runner changes.
    match = re.search(r"^" + re.escape(name) + r"\(\) \{\n.*?^\}\n",
                      RUNNER.read_text(), flags=re.MULTILINE | re.DOTALL)
    if match is None:
        raise AssertionError("runner function missing: " + name)
    return match.group(0)


class RecoveryPayloadTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="vinix-recovery-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.init_dir = self.root / "init"
        self.init_dir.mkdir()
        self.bin_dir = self.root / "bin"
        self.bin_dir.mkdir()
        for name in ["clang", "ld.lld"]:
            tool = self.bin_dir / name
            tool.write_text("#!/usr/bin/env python3\n" + TOOL_STUB)
            tool.chmod(0o755)
        self.full_image = self.root / "full.tar"
        self.full_image.write_bytes(b"full desktop payload")
        self.state_path = self.root / "state"
        self.event_path = self.root / "events.jsonl"
        self.fixture = self.root / "runner-fixture.sh"
        self.fixture.write_text(
            "set -euo pipefail\n"
            'INIT_DIR="$TEST_INIT_DIR"\n'
            'SCRIPT_DIR="$TEST_REPO_DIR"\n'
            'INITRAMFS="$TEST_FULL_IMAGE"\n'
            'INITRAMFS_COMPRESSED=1\n'
            'DISK_ROOT_FALLBACK="${TEST_FALLBACK:-recovery}"\n'
            'RECOVERY_DIR=""\n'
            'NO_BUILD=1\n' +
            runner_function("vinix_build_minimal_init") +
            runner_function("vinix_select_disk_root_payload") +
            'if [ "${TEST_ACTION:-select}" = build ]; then\n'
            '    vinix_build_minimal_init\n'
            'else\n'
            '    vinix_select_disk_root_payload\n'
            'fi\n'
            'printf "%s\\n" "$INITRAMFS" "$INITRAMFS_COMPRESSED" "$RECOVERY_DIR" > "$TEST_STATE"\n'
        )
        self.environment = {
            **os.environ,
            "PATH": str(self.bin_dir) + os.pathsep + os.environ["PATH"],
            "TMPDIR": str(self.root),
            "TEST_INIT_DIR": str(self.init_dir),
            "TEST_REPO_DIR": str(ROOT),
            "TEST_FULL_IMAGE": str(self.full_image),
            "TEST_EVENTS": str(self.event_path),
            "TEST_STATE": str(self.state_path),
        }

    def run_fixture(self, **overrides):
        return subprocess.run(["bash", str(self.fixture)], env={**self.environment, **overrides},
                              cwd=self.root, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def successful_run(self, **overrides):
        result = self.run_fixture(**overrides)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        payload, compressed, recovery = self.state_path.read_text().splitlines()
        return Path(payload), compressed, recovery

    def events(self):
        if not self.event_path.exists():
            return []
        return [json.loads(line) for line in self.event_path.read_text().splitlines()]

    def assert_no_compile_temporaries(self):
        self.assertEqual(list(self.init_dir.glob(".init*")), [])

    def assert_recovery_archive(self, payload, expected):
        self.assertLess(payload.stat().st_size, 128 * 1024)
        with tarfile.open(payload) as archive:
            files = [member for member in archive if member.isfile()]
            self.assertEqual([member.name for member in files], ["./sbin/init"])
            self.assertEqual(files[0].mode & 0o777, 0o755)
            self.assertEqual(archive.extractfile(files[0]).read(), expected)

    def test_fresh_no_build_run_prepares_tiny_recovery_archive(self):
        payload, compressed, recovery = self.successful_run()
        self.assertEqual(compressed, "0")
        self.assertEqual(payload.parent, Path(recovery))
        self.assertNotEqual(payload, self.full_image)
        self.assert_recovery_archive(payload, b"fixture ld.lld")
        self.assertTrue(os.access(self.init_dir / "init", os.X_OK))
        self.assertEqual([event["tool"] for event in self.events()], ["clang", "ld.lld"])
        self.assertTrue(all(not event["init_published"] for event in self.events()))
        self.assert_no_compile_temporaries()

    def test_existing_init_is_packed_without_compilation(self):
        init = self.init_dir / "init"
        init.write_bytes(b"previous init")
        init.chmod(0o755)
        payload, compressed, _ = self.successful_run()
        self.assertEqual(compressed, "0")
        self.assert_recovery_archive(payload, b"previous init")
        self.assertEqual(self.events(), [])

    def test_existing_minimal_archive_is_reused_without_compilation(self):
        minimal = self.init_dir / "initramfs-minimal.tar"
        with tarfile.open(minimal, "w", format=tarfile.USTAR_FORMAT) as archive:
            member = tarfile.TarInfo("./sbin/init")
            member.size = len(b"archived init")
            member.mode = 0o755
            archive.addfile(member, io.BytesIO(b"archived init"))
        before = minimal.read_bytes()
        payload, compressed, recovery = self.successful_run()
        self.assertEqual(payload, minimal)
        self.assertEqual(compressed, "0")
        self.assertEqual(recovery, "")
        self.assertEqual(minimal.read_bytes(), before)
        self.assertEqual(self.events(), [])
        self.assertFalse((self.init_dir / "init").exists())

    def test_compiler_or_linker_failure_stops_and_cleans_temporaries(self):
        for failing_tool, expected in [("clang", ["clang"]), ("ld.lld", ["clang", "ld.lld"])]:
            with self.subTest(tool=failing_tool):
                self.event_path.unlink(missing_ok=True)
                result = self.run_fixture(TEST_FAIL_TOOL=failing_tool)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual([event["tool"] for event in self.events()], expected)
                self.assertFalse(self.state_path.exists())
                self.assertFalse((self.init_dir / "init").exists())
                self.assertEqual(list(self.root.glob("vinix-recovery.*")), [])
                self.assert_no_compile_temporaries()

    def test_failed_rebuild_preserves_previously_published_init(self):
        init = self.init_dir / "init"
        init.write_bytes(b"previous init")
        init.chmod(0o755)
        result = self.run_fixture(TEST_ACTION="build", TEST_FAIL_TOOL="ld.lld")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(init.read_bytes(), b"previous init")
        self.assertTrue(os.access(init, os.X_OK))
        self.assert_no_compile_temporaries()

    def test_image_fallback_preserves_chosen_payload(self):
        payload, compressed, recovery = self.successful_run(TEST_FALLBACK="image")
        self.assertEqual(payload, self.full_image)
        self.assertEqual(compressed, "1")
        self.assertEqual(recovery, "")
        self.assertEqual(self.full_image.read_bytes(), b"full desktop payload")
        self.assertEqual(self.events(), [])
        self.assertFalse((self.init_dir / "init").exists())

    def test_real_tools_build_executable_aarch64_elf(self):
        if not shutil.which("clang") or not shutil.which("ld.lld"):
            self.skipTest("clang and ld.lld are needed for the real ELF check")
        payload, compressed, _ = self.successful_run(PATH=os.environ["PATH"])
        binary = (self.init_dir / "init").read_bytes()
        self.assertEqual(binary[:6], b"\x7fELF\x02\x01")
        self.assertEqual(int.from_bytes(binary[16:18], "little"), 2)  # ET_EXEC
        self.assertEqual(int.from_bytes(binary[18:20], "little"), 183)  # EM_AARCH64
        self.assertNotEqual(int.from_bytes(binary[24:32], "little"), 0)  # entry point
        self.assertEqual(compressed, "0")
        self.assert_recovery_archive(payload, binary)
        self.assertEqual(self.events(), [])
        self.assert_no_compile_temporaries()


if __name__ == "__main__":
    unittest.main()
