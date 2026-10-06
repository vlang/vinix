#!/usr/bin/env python3
"""Compile the unchanged production console policy with native fixture hooks."""
from pathlib import Path
import os
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def prepare(work):
    module = work / "policy"
    module.mkdir()
    policy = (ROOT / "kernel/kprint/printf_policy.v").read_text().replace("module kprint", "module policy")
    (module / "policy.v").write_text(policy)
    entries = (ROOT / "kernel/kprint/printf_entries.v").read_text().replace("module kprint", "module policy")
    (module / "entries.v").write_text(entries)
    shutil.copytree(ROOT / "kernel/abiargs", work / "abiargs")
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


def generate_policy(work, output, arch, prod):
    compiler = subprocess.check_output([
        "sh", "-c", '. "$1/build-support/find-v.sh"; printf "%s" "$V"',
        "find-v", str(ROOT)], text=True)
    subprocess.run([compiler, "-shared", "-no-builtin", "-no-closures", "-os", "vinix",
                    "-arch", arch, "-target-libc-headers", "-nofloat", "-gc", "none", "-manualfree",
                    *(["-prod"] if prod else []), "-o", str(output), str(work)], check=True,
                   env={**os.environ, "V_C_ERROR_BUG_REPORT_DISABLED": "1"})
