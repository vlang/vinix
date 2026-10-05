#!/usr/bin/env python3
"""Check source-import coverage and rejection of incomplete compiler reports."""

import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("allocation_sources", HERE / "copy_sources.py")
sources = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sources)


class SourceTests(unittest.TestCase):
    def test_missing_imports_are_copied_without_unfiltering_existing_modules(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            kernel, destination = root / "kernel", root / "scratch"
            contents = {
                "v.mod": "Module { name: 'kernel' }\n",
                "main.v": "import drm.simple as simpledrm\nimport proc\n",
                "drm/simple/simple.v": "module simple\nimport drm.gem\n",
                "drm/gem/gem.v": "module gem\nimport drm.simple\n",
                "proc/proc.v": "module proc\n",
                "proc/proc_arm64.v": "module proc\n",
            }
            for name, text in contents.items():
                path = kernel / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text)
            files = root / "files"
            files.write_text("main.v\nproc/proc.v\n")
            copied = sources.copy_sources(kernel, files, destination)
            self.assertEqual(copied, ["drm/gem/gem.v", "drm/simple/simple.v",
                                      "main.v", "proc/proc.v"])
            self.assertFalse((destination / "proc/proc_arm64.v").exists())
            self.assertEqual((destination / "v.mod").read_text(), contents["v.mod"])


class RunnerTests(unittest.TestCase):
    def run_report(self, failed_arch="", update=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            test = root / "tests/kernel-allocs"
            test.mkdir(parents=True)
            for name in ("run.sh", "copy_sources.py"):
                shutil.copy2(HERE / name, test / name)
            support = root / "build-support"
            support.mkdir()
            shutil.copy2(HERE.parents[1] / "build-support/find-v.sh", support / "find-v.sh")
            kernel = root / "kernel"
            kernel.mkdir()
            (kernel / "main.v").write_text("module main\n")
            (kernel / "v.mod").write_text("Module { name: 'kernel' }\n")
            allowed = test / "allowed.txt"
            baseline = "main.v array initialization\t1\n"
            allowed.write_text(baseline)
            commands = root / "commands"
            commands.mkdir()
            make = commands / "make"
            make.write_text("#!/bin/sh\nprintf '%s\\n' 'for f in main.v; do :; done'\n")
            make.chmod(0o755)
            compiler = commands / "v"
            compiler.write_text("""#!/usr/bin/env python3
import os, sys
from pathlib import Path
arch = sys.argv[sys.argv.index('-arch') + 1]
source = Path(sys.argv[-1])
print(f'{source}/main.v:1:1: warning: allocation (array initialization)')
if os.environ.get('FAILED_ARCH') == arch:
    print('builder error: preserved compiler diagnostic', file=sys.stderr)
    raise SystemExit(7)
""")
            compiler.chmod(0o755)
            env = os.environ.copy()
            env.update(PATH=f"{commands}:{env['PATH']}", V=str(compiler),
                       FAILED_ARCH=failed_arch)
            command = ["sh", str(test / "run.sh")]
            if update:
                command.append("--update")
            result = subprocess.run(command, env=env, capture_output=True, text=True)
            return result, allowed.read_text(), baseline

    def test_complete_reports_from_both_architectures_are_checked(self):
        result, _, _ = self.run_report()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("aarch64: 1 source files", result.stderr)
        self.assertIn("x86_64: 1 source files", result.stderr)

    def test_compiler_errors_are_fatal_even_when_allocation_warnings_exist(self):
        for arch in ("arm64", "amd64"):
            with self.subTest(arch=arch):
                result, _, _ = self.run_report(failed_arch=arch)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("preserved compiler diagnostic", result.stderr)
                self.assertIn("allocation report is incomplete", result.stderr)
                self.assertNotIn("OK:", result.stderr)

    def test_update_cannot_accept_a_partial_report(self):
        result, allowed, baseline = self.run_report(failed_arch="amd64", update=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(allowed, baseline)


if __name__ == "__main__":
    unittest.main()
