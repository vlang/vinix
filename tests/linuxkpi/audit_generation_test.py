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

void native_adapter_caller(spinlock_t *lock, unsigned long *value)
{
    unsigned long flags;
    spin_lock_irqsave(lock, flags);
    (void)arch_xchg_relaxed(value, 1UL);
    (void)arch_cmpxchg_relaxed(value, 1UL, 2UL);
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
        for name in ("include", "arch"):
            (self.root / name).symlink_to(upstream / name, target_is_directory=True)
        self.source = self.root / "drivers/gpu/drm/i915/adapter_caller.c"
        self.source.parent.mkdir(parents=True)
        self.source.write_text(CALLER)
        self.run_subprocess = subprocess.run
        self.compiler_commands = []
        self.generated_directories = []
        self.generation_directories = []

    def run_command(self, command, **kwargs):
        if len(command) > 1 and Path(command[1]).name == "generate-abi.py":
            self.generation_directories.append(Path(command[-1]).parents[1])
        if command[0] == "clang":
            self.compiler_commands.append(command)
            generated = Path(command[command.index("-I") + 1])
            self.generated_directories.append(generated)
            self.assertTrue((generated / "vinix/spinlock_adapters.h").is_file())
            self.assertTrue((generated / "vinix/atomic_exchange.h").is_file())
            self.assertFalse(any("obj" in Path(value).parts for value in command))
        return self.run_subprocess(command, **kwargs)

    def invoke(self, name):
        output = self.directory / (name + ".json")
        stdout, stderr = io.StringIO(), io.StringIO()
        arguments = ["audit.py", "--source-dir", str(self.root), "--jobs", "1",
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
        self.assertEqual(len(self.compiler_commands), 2)
        self.assertEqual(len(set(self.generated_directories)), 2)
        for directory in self.generated_directories:
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


if __name__ == "__main__":
    unittest.main()
