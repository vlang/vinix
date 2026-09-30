#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Exercise the production eraser and dead-local erasure on amd64 and arm64."""
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "kernel/c/explicit_bzero.c"
INCLUDE = ROOT / "kernel/c"

RUNTIME_TEST = r'''
#include <assert.h>
#include <stddef.h>
#include "explicit_bzero.h"
int main(void) {
    unsigned char b[258];
    for (size_t n = 0; n <= 256; ++n) {
        for (size_t i = 0; i < sizeof b; ++i) b[i] = 0xa5;
        vinix_explicit_bzero(b + 1, n);
        assert(b[0] == 0xa5);
        for (size_t i = 1; i <= n; ++i) assert(b[i] == 0);
        for (size_t i = n + 1; i < sizeof b; ++i) assert(b[i] == 0xa5);
    }
    vinix_explicit_bzero(NULL, 0);
    vinix_explicit_bzero(b, sizeof b);
    for (size_t i = 0; i < sizeof b; ++i) assert(b[i] == 0);
    return 0;
}
'''

DEAD_LOCAL_TEST = r'''
/* Including the production implementation lets the optimizer see everything. */
#include "explicit_bzero.c"
void erase_dead_local(void) {
    unsigned char secret[32];
    for (size_t i = 0; i < sizeof secret; ++i) secret[i] = 0xa5;
    vinix_explicit_bzero(secret, sizeof secret);
    /* The secret is deliberately never read after this call. */
}
'''


def run(args: list[str]) -> None:
    subprocess.run(args, check=True)


def main() -> None:
    cc = shutil.which("cc")
    clang = shutil.which("clang")
    if not cc or not clang:
        raise SystemExit("Both a host C compiler (cc) and clang are required")
    with tempfile.TemporaryDirectory(prefix="vinix-securemem-") as tmp:
        work = Path(tmp)
        runtime = work / "runtime.c"
        runtime.write_text(RUNTIME_TEST)
        for opt in ("-O0", "-O2", "-O3"):
            exe = work / ("runtime" + opt)
            run([cc, "-std=c99", "-Wall", "-Wextra", "-Werror", opt,
                 "-I" + str(INCLUDE), str(runtime), str(SOURCE), "-o", str(exe)])
            run([str(exe)])
            print(f"PASS: erasure bounds and zero length ({opt})", flush=True)
        # A host LTO build also exercises the production source with whole-program
        # visibility. A missing/broken LTO toolchain fails rather than being skipped.
        exe = work / "runtime-lto"
        run([cc, "-std=c99", "-O3", "-flto", "-I" + str(INCLUDE),
             str(runtime), str(SOURCE), "-o", str(exe)])
        run([str(exe)])
        print("PASS: erasure bounds and zero length (-O3 -flto)", flush=True)

        dead = work / "dead.c"
        dead.write_text(DEAD_LOCAL_TEST)
        for target, store in (
            ("x86_64-unknown-none", r"movb\s+\$0,"),
            ("aarch64-unknown-none", r"strb\s+wzr,"),
        ):
            asm = work / (target + ".s")
            run([clang, "--target=" + target, "-O3", "-ffreestanding",
                 "-fno-stack-protector", "-I" + str(INCLUDE),
                 "-S", str(dead), "-o", str(asm)])
            text = asm.read_text()
            body = text.split("erase_dead_local:", 1)[1].split(".Lfunc_end", 1)[0]
            if not re.search(store, body):
                raise AssertionError(f"{target}: zero stores missing from dead-local function\n{body}")
            print(f"PASS: dead-local zero stores survive -O3 ({target})", flush=True)


if __name__ == "__main__":
    main()
