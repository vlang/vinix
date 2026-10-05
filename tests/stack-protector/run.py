#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Exercise the V canary through real compiler-protected C frames."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]

with tempfile.TemporaryDirectory(prefix="vinix-stack-protector-", dir="/tmp") as temporary:
    work = Path(temporary)
    (work / "v.mod").write_text("Module { name: 'vinix_stack_protector_tests' }\n")
    shutil.copy2(ROOT / "kernel/lib/stack_protector.v", work / "protector.v")
    (work / "ports.v").write_text("""module lib
fn C.vinix_stack_test_panic(message charptr)
fn stack_boot_entropy() u64 { return u64(0x713b38249a6255cb) }
@[noreturn]
fn kpanic(state voidptr, message charptr) {
    _ = state
    C.vinix_stack_test_panic(message)
    for {}
}
""")
    v = subprocess.check_output([
        "sh", "-c", '. "$1/build-support/find-v.sh"; printf "%s" "$V"',
        "find-v", str(ROOT)], text=True)
    subprocess.run([v, "-shared", "-no-builtin", "-os", "vinix", "-target-libc-headers",
                    "-nofloat", "-gc", "none", "-manualfree", "-o", str(work / "protector.c"),
                    str(work)], check=True, env={**os.environ, "V_C_ERROR_BUG_REPORT_DISABLED": "1"})
    compiler = os.environ.get("CC", "clang")
    common = [compiler, "-std=gnu11", "-O2", "-g", "-Wall", "-Wextra", "-Werror",
              "-fstack-protector-strong", "-mstack-protector-guard=global",
              "-fno-omit-frame-pointer", "-iquote", str(ROOT / "kernel/c")]
    production = common + ["-Wno-unused-function", "-Wno-unused-parameter",
                           "-ffreestanding", "-fno-builtin", "-fno-strict-aliasing"]
    subprocess.run(production + ["-c", str(work / "protector.c"),
                    "-o", str(work / "protector.o")], check=True)
    imports = subprocess.check_output(["nm", "-u", str(work / "protector.o")], text=True)
    if re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b", imports):
        raise RuntimeError("unexpected allocator import in stack protector:\n" + imports)
    subprocess.run(common + [str(Path(__file__).with_name("host.c")), str(work / "protector.o"),
                    "-o", str(work / "host")], check=True)
    subprocess.run([str(work / "host")], check=True)
    # Inspect the attribute inherited from the header independently of optimizer
    # decisions: neither generated initialization function may save a canary.
    subprocess.run(production + ["-S", "-emit-llvm", str(work / "protector.c"),
                    "-o", str(work / "protector.ll")], check=True)
    ir = (work / "protector.ll").read_text()
    for name in ("lib__stack_guard_init", "vinix_stack_guard_init"):
        definition = re.search(r"define[^\n]*@" + name + r"\([^\n]*#(\d+)[^\n]*\{", ir)
        if not definition:
            raise RuntimeError("missing initialization definition: " + name)
        attributes = re.search(r"attributes #" + definition[1] + r" = \{([^\n]*)\}", ir)
        if not attributes or re.search(r"\bssp(?:strong|req)?\b", attributes[1]):
            raise RuntimeError("initialization unexpectedly has stack protection: " + name)
    print("STACK PROTECTOR PASS: allocation imports and unprotected initialization attributes")
