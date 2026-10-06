#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Exercise the V canary through real compiler-protected V caller frames."""
import os
from pathlib import Path
import re
import platform
import runpy
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
native_arch = os.environ.get("VINIX_STACK_TEST_ARCH", "aarch64" if platform.machine().lower() in ("arm64", "aarch64") else "x86_64")
if native_arch not in ("aarch64", "x86_64"):
    raise RuntimeError("unsupported stack protector host architecture")

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
    subprocess.run([v, "-shared", "-no-builtin", "-os", "vinix", "-arch",
                    "arm64" if native_arch == "aarch64" else "amd64", "-target-libc-headers",
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
    compile_module = runpy.run_path(str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"))["compile_module"]
    compile_module(ROOT / "tests/stack-protector/protectorfixture", work / "fixture.o", native_arch,
                   common + ["-fno-strict-aliasing"])
    subprocess.run(common + [str(work / "fixture.o"), str(work / "protector.o"),
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
    subprocess.run(common + ["-I", str(ROOT / "tests/stack-protector/protectorfixture"),
                             "-Wno-unused-function", "-Wno-unused-parameter", "-S", "-emit-llvm",
                             str(work / "fixture.c"), "-o", str(work / "fixture.ll")], check=True)
    fixture_ir = (work / "fixture.ll").read_text()
    for name in ("main", "protectorfixture__run", "protectorfixture__protected_frame"):
        definition = re.search(r"define[^\n]*@" + name + r"\([^\n]*#(\d+)[^\n]*\{", fixture_ir)
        if not definition:
            raise RuntimeError("missing independent fixture definition: " + name)
        attributes = re.search(r"attributes #" + definition[1] + r" = \{([^\n]*)\}", fixture_ir)
        protected = attributes and re.search(r"\bssp(?:strong|req)?\b", attributes[1])
        if bool(protected) != (name == "protectorfixture__protected_frame"):
            raise RuntimeError("wrong independent fixture stack protection: " + name)
        if name.endswith("protected_frame") and "noinline" not in attributes[1]:
            raise RuntimeError("independent protected frame may be inlined")
    print("STACK PROTECTOR PASS: allocation imports and unprotected initialization attributes")
    print("STACK PROTECTOR PASS: protected volatile V frame and unprotected caller attributes")
