#!/usr/bin/env python3
"""Exercise audit header generation with the real generator and native headers.

The small caller isolates invocation cleanup and preparation failures. Import
verification and Kbuild enumeration are exercised by the full i915 audit.
"""
import contextlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "kernel/linuxkpi"))
import audit


CALLER = """#include <linux/spinlock.h>
#include <linux/atomic.h>
#include <linux/overflow.h>
#include <generated/bounds.h>
#define __GENERATING_BOUNDS_H
#include <linux/page-flags.h>
#include <linux/mmzone.h>
#include <linux/log2.h>
_Static_assert(NR_PAGEFLAGS == __NR_PAGEFLAGS, "actual configured page flags");
_Static_assert(MAX_NR_ZONES == __MAX_NR_ZONES, "actual configured zones");
_Static_assert(SPINLOCK_SIZE == sizeof(spinlock_t), "actual lock ABI");
_Static_assert(NR_CPUS_BITS == order_base_2(CONFIG_NR_CPUS), "configured CPUs");

void native_adapter_caller(spinlock_t *lock, unsigned long *value)
{
    unsigned long flags, sum;
    spin_lock_irqsave(lock, flags);
    (void)arch_xchg_relaxed(value, 1UL);
    (void)arch_cmpxchg_relaxed(value, 1UL, 2UL);
    (void)check_add_overflow(*value, 1UL, &sum);
    spin_unlock_irqrestore(lock, flags);
}
"""


class AuditGenerationTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="vinix-audit-generation-test-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name).resolve()
        self.root = self.directory / "linux"
        self.root.mkdir()
        upstream = audit.upstream.DEFAULT / ("linux-" + audit.upstream.PIN["version"])
        self.archive = upstream.parent / ("linux-" + audit.upstream.PIN["version"] + ".tar.xz")
        for name in ("include", "arch"):
            (self.root / name).symlink_to(upstream / name, target_is_directory=True)
        self.source = self.root / "drivers/gpu/drm/i915/adapter_caller.c"
        self.source.parent.mkdir(parents=True)
        self.source.write_text(CALLER)
        self.run_subprocess = subprocess.run
        self.compiler_commands = []
        self.generated_directories = []
        self.generation_directories = []
        self.bounds_commands = []

    def run_command(self, command, **kwargs):
        if len(command) > 1 and Path(command[1]).name == "generate-abi.py":
            self.generation_directories.append(Path(command[-1]).parents[1])
        if "-S" in command:
            self.bounds_commands.append(command)
        if str(self.source) in command:
            self.compiler_commands.append(command)
            generated = Path(command[command.index("-I") + 1])
            self.generated_directories.append(generated)
            self.assertTrue((generated / "vinix/spinlock_adapters.h").is_file())
            self.assertTrue((generated / "vinix/atomic_exchange.h").is_file())
            if (audit.HERE / "abi/overflow.json").is_file():
                self.assertTrue((generated / "vinix/integer_policy.h").is_file())
            bounds = generated / "generated/bounds.h"
            self.assertTrue(bounds.is_file())
            self.assertTrue(Path(str(bounds) + ".d").is_file())
            self.assertTrue(Path(str(bounds) + ".json").is_file())
            self.assertFalse(any("obj" in Path(value).parts for value in command))
        return self.run_subprocess(command, **kwargs)

    def invoke(self, name, compiler="clang"):
        output = self.directory / (name + ".json")
        stdout, stderr = io.StringIO(), io.StringIO()
        arguments = ["audit.py", "--source-dir", str(self.root), "--jobs", "1",
                     "--archive", str(self.archive), "--cc", compiler,
                     "--output", str(output)]
        with patch.object(sys, "argv", arguments), \
                patch.object(audit.upstream, "verify"), \
                patch.object(audit, "driver_sources", return_value=[self.source]), \
                patch.object(audit.subprocess, "run", side_effect=self.run_command), \
                contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            status = audit.main()
        return status, output, stdout.getvalue(), stderr.getvalue()

    def test_each_invocation_generates_and_removes_its_own_headers(self):
        for name in ("first", "second"):
            status, output, stdout, stderr = self.invoke(name)
            self.assertEqual(status, 0, stdout + stderr)
            report = json.loads(output.read_text())
            self.assertEqual((report["compiled"], report["total"]), (1, 1), report)
            self.assertEqual(report["bounds"]["configuration"]["CONFIG_MMU"], "1")
            self.assertEqual(report["bounds"]["archive_sha256"], audit.upstream.PIN["sha256"])
        self.assertEqual(len(self.compiler_commands), 2)
        self.assertEqual(len(self.bounds_commands), 2)
        self.assertEqual(len(set(self.generated_directories)), 2)
        for directory in self.generated_directories:
            self.assertFalse(directory.parent.exists())

    def test_bounds_compiler_failure_stops_before_driver_compilation(self):
        compiler = self.directory / "reject-bounds.py"
        compiler.write_text("#!" + sys.executable + "\n"
                            "import os, sys\n"
                            "if '-S' in sys.argv:\n"
                            "    print('injected bounds compiler failure', file=sys.stderr)\n"
                            "    sys.exit(1)\n"
                            "os.execvp('clang', ['clang'] + sys.argv[1:])\n")
        compiler.chmod(0o755)
        status, output, stdout, stderr = self.invoke("bounds-failure", str(compiler))
        self.assertEqual(status, 2, stdout + stderr)
        self.assertIn("injected bounds compiler failure", stderr)
        self.assertFalse(output.exists())
        self.assertEqual(self.compiler_commands, [])
        self.assertEqual(len(self.bounds_commands), 1)
        for directory in self.generation_directories:
            self.assertFalse(directory.parent.exists())

    def test_invalid_metadata_stops_before_the_compiler(self):
        invalid = self.directory / "invalid-metadata"
        (invalid / "abi").mkdir(parents=True)
        (invalid / "generate-abi.py").symlink_to(audit.HERE / "generate-abi.py")
        (invalid / "abi/spinlock.json").write_text("{ malformed metadata")
        with patch.object(audit, "HERE", invalid):
            status, output, stdout, stderr = self.invoke("failure")
        self.assertEqual(status, 2, stdout + stderr)
        self.assertIn("JSONDecodeError", stderr)
        self.assertFalse(output.exists())
        self.assertEqual(self.compiler_commands, [])
        self.assertEqual(self.generated_directories, [])
        self.assertEqual(len(self.generation_directories), 1)
        self.assertFalse(self.generation_directories[0].parent.exists())


    def test_invalid_optional_integer_metadata_stops_before_the_compiler(self):
        if not (audit.HERE / "abi/overflow.json").is_file():
            self.skipTest("integer-policy metadata is absent in this source snapshot")
        invalid = self.directory / "invalid-integer-metadata"
        (invalid / "abi").mkdir(parents=True)
        (invalid / "generate-abi.py").symlink_to(audit.HERE / "generate-abi.py")
        for name in ("spinlock.json", "atomic-exchange.json"):
            (invalid / "abi" / name).symlink_to(audit.HERE / "abi" / name)
        (invalid / "abi/overflow.json").write_text("{ malformed metadata")
        with patch.object(audit, "HERE", invalid):
            status, output, stdout, stderr = self.invoke("integer-failure")
        self.assertEqual(status, 2, stdout + stderr)
        self.assertIn("JSONDecodeError", stderr)
        self.assertFalse(output.exists())
        self.assertEqual(self.compiler_commands, [])
        self.assertEqual(self.generated_directories, [])
        self.assertEqual(len(self.generation_directories), 3)
        self.assertFalse(self.generation_directories[0].parent.exists())


if __name__ == "__main__":
    unittest.main()
