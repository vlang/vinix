#!/usr/bin/env python3
"""Check Limine compatibility patching without downloads or compilation."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
BUILDER = ROOT / "scripts/build-limine-aarch64.sh"
PATCH = ROOT / "build-support/limine/12.8.0-vinix-base-revision-2.patch"
LABEL = "Limine 12.8.0 (aarch64, UEFI)"
GUARD = "Base revision %u is no longer supported for aarch64"
UPSTREAM = '''void limine_load(char *config, char *cmdline) {
    if (base_rev_p2_ptr != NULL) {
        *base_rev_p2_ptr = 0;
    }

#if defined (__aarch64__)
    if (base_revision < 6) {
        panic(true, "limine: Base revision %u is no longer supported for aarch64 (minimum: 6)", base_revision);
    }
#endif

    // Load requests
    requests_top = physical_base + image_size_before_bss;
    uint64_t *limine_reqs = NULL;
}
'''


@unittest.skipUnless(shutil.which("git"), "git is not installed")
class LiminePatchTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="vinix-limine-patch-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "scripts").mkdir()
        shutil.copy2(BUILDER, self.root / "scripts" / BUILDER.name)
        patch_dir = self.root / "build-support/limine"
        patch_dir.mkdir(parents=True)
        shutil.copy2(PATCH, patch_dir / PATCH.name)
        self.source = self.root / "boot-image/limine-src-12.8.0"
        self.driver = self.source / "common/protos/limine.c"
        self.driver.parent.mkdir(parents=True)
        self.driver.write_text(UPSTREAM)
        self.script(self.source / "configure", "touch GNUmakefile\n")
        commands = self.root / "fake-bin"
        commands.mkdir()
        self.script(commands / "llvm-objcopy", "exit 0\n")
        self.script(commands / "sysctl", "echo 2\n")
        self.script(
            commands / "make",
            f"if grep -Fq '{GUARD}' common/protos/limine.c; then exit 91; fi\n"
            f"mkdir -p bin\nprintf '%s\\n' '{LABEL}' > bin/BOOTAA64.EFI\n",
        )
        self.environment = os.environ.copy()
        self.environment.update(
            PATH=str(commands) + os.pathsep + os.environ.get("PATH", ""),
            GIT_CONFIG_GLOBAL=os.devnull,
            GIT_CONFIG_NOSYSTEM="1",
            LC_ALL="C",
        )

    def script(self, path, body):
        path.write_text("#!/bin/sh\nset -e\n" + body)
        path.chmod(0o755)

    def run_builder(self, *arguments):
        return subprocess.run(
            ["bash", str(self.root / "scripts" / BUILDER.name), *arguments],
            env=self.environment, cwd=self.root, capture_output=True,
            text=True, timeout=10,
        )

    def test_fresh_source_applies_compatibility_patch_before_build(self):
        result = self.run_builder()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("applying " + PATCH.name, result.stdout)
        self.assertNotIn(GUARD, self.driver.read_text())
        installed = self.root / "boot-image/limine-bin/BOOTAA64.EFI"
        self.assertIn(LABEL, installed.read_text())
        self.assertIn("Vinix base revision 2 compatibility", self.run_builder("--check").stdout)

    def test_already_patched_source_is_unchanged_on_rerun(self):
        first = self.run_builder()
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        before = self.driver.read_bytes()
        second = self.run_builder()
        self.assertEqual(second.returncode, 0, second.stdout + second.stderr)
        self.assertIn("already applied", second.stdout)
        self.assertEqual(self.driver.read_bytes(), before)

    def test_incompatible_source_is_rejected_before_build(self):
        self.driver.write_text(UPSTREAM.replace("requests_top =", "other_top ="))
        before = self.driver.read_bytes()
        result = self.run_builder()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("error: cannot apply", result.stderr)
        self.assertNotIn("==> building", result.stdout)
        self.assertEqual(self.driver.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
