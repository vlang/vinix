#!/usr/bin/env python3
"""Exercise desktop launcher bootstrap decisions without building or booting."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


RUNNER = Path(__file__).resolve().parents[2] / "scripts/run-desktop-aarch64.sh"
DEPENDENCY_DIRS = ["freestnd-c-hdrs", "cc-runtime", "c/flanterm"]
DEPENDENCY_FILES = ["c/nanoprintf.h", "c/uacpi/acpi.h", "c/lwip/include/lwip/init.h"]


class DesktopRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="vinix-desktop-runner-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "checkout"
        (self.root / "scripts").mkdir(parents=True)
        shutil.copy2(RUNNER, self.root / "scripts" / RUNNER.name)
        self.kernel = self.root / "kernel"
        self.image = self.root / "build-support/init-aarch64/initramfs-desktop.tar"
        self.write(self.kernel / "bin/vinix", "kernel fixture\n")
        self.write(self.image, "desktop fixture\n")
        self.write(
            self.root / "tools/prune-build-artifacts.py",
            'import os\nwith open(os.environ["TEST_EVENTS"], "a") as log:\n'
            '    log.write("prune\\n")\n',
        )
        self.write(
            self.root / "build-support/find-v.sh",
            'printf "compiler\\n" >> "$TEST_EVENTS"\n'
            'V="$SCRIPT_DIR/fake-bin/v"\n',
        )
        self.script(self.root / "fake-bin/v", "echo 'fixture V compiler'\n")
        self.script(self.root / "fake-bin/sysctl", "echo 2\n")
        self.script(self.root / "fake-bin/nproc", "echo 2\n")
        self.script(
            self.root / "scripts/build-qemu-ovmf-aarch64.sh",
            'printf "firmware\\n" >> "$TEST_EVENTS"\n'
            'mkdir -p boot-image\ntouch boot-image/edk2-aarch64-code-2048x1536.fd\n',
        )
        self.script(
            self.kernel / "get-deps",
            'printf "deps\\n" >> "$TEST_EVENTS"\n'
            'mkdir -p kernel/freestnd-c-hdrs kernel/cc-runtime kernel/c/flanterm '
            'kernel/c/uacpi kernel/c/lwip/include/lwip\n'
            'touch kernel/c/nanoprintf.h kernel/c/uacpi/acpi.h '
            'kernel/c/lwip/include/lwip/init.h\n',
        )
        self.script(
            self.root / "fake-bin/make",
            'printf "make\\n" >> "$TEST_EVENTS"\n'
            'test -f kernel/c/lwip/include/lwip/init.h || exit 91\n'
            'mkdir -p kernel/bin\ntouch kernel/bin/vinix\n',
        )
        self.script(
            self.root / "build-support/prepare-desktop-aarch64.sh",
            'test -f kernel/bin/vinix || exit 92\n'
            'printf "prepare\\n" >> "$TEST_EVENTS"\n',
        )
        self.script(
            self.root / "scripts/build-desktop-aarch64.sh",
            'printf "desktop\\n" >> "$TEST_EVENTS"\n'
            'touch build-support/init-aarch64/initramfs-desktop.tar\n',
        )
        self.script(
            self.root / "scripts/run-aarch64.sh",
            'test "$1" = --no-build || exit 93\n'
            'printf "boot\\n" >> "$TEST_EVENTS"\necho "fixture: reached QEMU runner"\n',
        )
        self.log = self.root / "events"
        self.environment = {key: value for key, value in os.environ.items()
                            if not key.startswith("VINIX_") and key != "V"}
        self.environment.update(
            TEST_EVENTS=str(self.log),
            PATH=str(self.root / "fake-bin") + os.pathsep + os.environ["PATH"],
        )

    def write(self, path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def script(self, path, body):
        self.write(path, "#!/bin/sh\nset -e\n" + body)
        path.chmod(0o755)

    def run_launcher(self, *arguments):
        result = subprocess.run(
            ["bash", str(self.root / "scripts" / RUNNER.name), *arguments], cwd=self.root,
            env=self.environment, capture_output=True, text=True, timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def events(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def warm_dependencies(self):
        for directory in DEPENDENCY_DIRS:
            (self.kernel / directory).mkdir(parents=True, exist_ok=True)
        for filename in DEPENDENCY_FILES:
            self.write(self.kernel / filename, "dependency fixture\n")

    def test_help_has_no_bootstrap_side_effects(self):
        result = self.run_launcher("--help")
        self.assertIn("Usage:", result.stdout)
        self.assertEqual(self.events(), [])
        self.assertFalse((self.root / "boot-image").exists())

    def test_missing_dependencies_are_fetched_before_kernel_build(self):
        (self.kernel / "bin/vinix").unlink()
        result = self.run_launcher()
        self.assertEqual(self.events(),
                         ["prune", "compiler", "firmware", "deps", "make",
                          "prepare", "desktop", "boot"])
        self.assertIn("fixture: reached QEMU runner", result.stdout)

    def test_warm_kernel_dependencies_are_reused(self):
        self.warm_dependencies()
        self.run_launcher("--no-desktop")
        self.assertEqual(self.events(), ["prune", "compiler", "firmware", "make", "boot"])

    def test_no_build_skips_dependency_and_desktop_bootstrap(self):
        result = self.run_launcher("--no-build")
        self.assertEqual(self.events(), ["prune", "firmware", "boot"])
        self.assertIn("fixture: reached QEMU runner", result.stdout)


if __name__ == "__main__":
    unittest.main()
