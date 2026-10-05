#!/usr/bin/env python3
"""Compile the production V console policy with independent C ABI callers."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
V = subprocess.check_output(["sh", "-c", '. "$1/build-support/find-v.sh"; printf "%s" "$V"',
                             "find-v", str(ROOT)], text=True)
with tempfile.TemporaryDirectory(prefix="vinix-print-") as directory:
    work = Path(directory)
    module = work / "policy"
    module.mkdir()
    policy = (ROOT / "kernel/kprint/printf_policy.v").read_text().replace("module kprint", "module policy")
    (module / "policy.v").write_text(policy)
    (module / "host.v").write_text('''@[translated]
@[has_globals]
module policy
#include "host.h"
fn C.fixture_serial(u8, i32)
fn C.fixture_terminal(&char, u64)
fn C.fixture_kwrite(&char, u64)
fn C.fixture_acquire()
fn C.fixture_release()
struct HostLock {}
__global printf_lock HostLock
fn (_ HostLock) acquire() { C.fixture_acquire() }
fn (_ HostLock) release() { C.fixture_release() }
fn policy_serial(c u8, panic bool) { C.fixture_serial(c, i32(panic)) }
fn policy_terminal(text &char, len u64) { C.fixture_terminal(text, len) }
fn kwrite(text &char, len u64) { C.fixture_kwrite(text, len) }
''')
    (work / "host.h").write_text('''#include <stdint.h>
void fixture_serial(unsigned char, int);
void fixture_terminal(char *, uint64_t);
void fixture_kwrite(char *, uint64_t);
void fixture_acquire(void);
void fixture_release(void);
''')
    (work / "v.mod").write_text("Module { name: 'print_test' }\n")
    (work / "entry.v").write_text("module main\nimport policy as _\n")
    shim = (ROOT / "kernel/c/printf.c").read_text()
    # Keep sanitizer/libc printing symbols intact, including stderr's FILE type.
    shim = shim.replace("#include <stdio.h>", "struct __file { int unused; };\ntypedef struct __file FILE;")
    for original, alias in (("printf", "fixture_printf"), ("printf_panic", "fixture_panic"),
                            ("kprintf", "fixture_kprintf"), ("fprintf", "fixture_fprintf"),
                            ("stderr", "fixture_stderr")):
        shim = re.sub(r"\b" + original + r"\b", alias, shim)
    (work / "shim.c").write_text(shim)
    bench = (ROOT / "kernel/c/printf_benchmark.c").read_text().replace("printf_benchmark", "fixture_benchmark")
    (work / "bench.c").write_text(bench)
    for prod in (False, True):
        generated = work / "policy.c"
        subprocess.run([V, "-shared", "-no-builtin", "-no-closures", "-os", "vinix",
                        "-target-libc-headers", "-nofloat", "-gc", "none", "-manualfree",
                        *( ["-prod"] if prod else [] ), "-o", str(generated), str(work)], check=True,
                       env={**os.environ, "V_C_ERROR_BUG_REPORT_DISABLED": "1"})
        flags = ["clang", "-std=gnu11", "-O2", "-g", "-ffreestanding", "-fno-builtin",
                 "-fsanitize=address,undefined", "-fno-omit-frame-pointer", "-DVINIX_V_RUNTIME",
                 "-I" + str(work), "-I" + str(ROOT / "kernel/c"), "-Wno-unused-function"]
        obj = work / "policy.o"
        subprocess.run([*flags, "-c", str(generated), "-o", str(obj)], check=True)
        symbols = subprocess.check_output(["nm", "-u", str(obj)], text=True)
        assert not re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b", symbols), symbols
        executable = work / "test"
        subprocess.run([*flags, *( ["-DPROD"] if prod else [] ), str(obj), str(work / "shim.c"),
                        str(work / "bench.c"), str(ROOT / "tests/kernel-print/test.c"),
                        "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)
    print("Console policy: debug/production C ABI, 1,026 chunk lengths, panic/assertion/benchmark output; no implicit allocator imports")
