#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Compare the native V fixtures with their immutable pre-port C goldens."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys

HERE = Path(__file__).resolve().parent
LOADER = HERE.parent
ROOT = LOADER.parent
ORIGINAL = "5a8e69285e09bedb9f949f5df2b80daa41c18e6a"


def run(command, **kwargs):
    return subprocess.run([str(x) for x in command], check=True, **kwargs)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--state-dir", type=Path, required=True)
    a = p.parse_args()
    work = a.state_dir.resolve()
    work.mkdir(parents=True, exist_ok=False)
    cc = os.environ.get("CC", "clang")
    flags = ["-O2", "-g", "-Wall", "-Wextra", "-Werror", "-fsanitize=address,undefined",
             "-fno-omit-frame-pointer", "-ffunction-sections", "-fdata-sections"]
    generated = ["-Wno-unused-function", "-Wno-unused-parameter", "-Wno-unused-label", "-fwrapv",
                 "-fno-strict-aliasing", "-I" + str(LOADER / "src"), "-I" + str(HERE)]
    gc = "-Wl,-dead_strip" if platform.system() == "Darwin" else "-Wl,--gc-sections"
    core = work / "core.c"
    run([sys.executable, LOADER / "compile-v.py", "--host", core])
    run([cc, "-std=gnu11", *flags, *generated, "-ffreestanding", "-fno-builtin",
         "-c", core, "-o", work / "core.o"])
    receipts = {"original_revision": ORIGINAL, "cases": []}
    for fixture, original in (("converter", "adt2fdt.c"), ("boot", "boot-runtime.c")):
        frozen = work / original
        frozen.write_bytes(subprocess.check_output(
            ["git", "show", ORIGINAL + ":apple-boot/tests/" + original], cwd=ROOT))
        receipts[original] = hashlib.sha256(frozen.read_bytes()).hexdigest()
        # Resolve the original relative public-header includes without changing
        # any fixture expression or algorithm.
        run([cc, "-std=gnu11", *flags, "-DAPPLE_BOOT_HOST", "-I" + str(HERE), gc,
             frozen, work / "core.o", "-o", work / (fixture + "-c")])
        source, obj = work / (fixture + ".c"), work / (fixture + ".o")
        run([sys.executable, HERE / "compile-fixture.py", fixture, source])
        run([cc, "-std=gnu11", *flags, *generated, "-c", source, "-o", obj])
        symbols = subprocess.check_output(["nm", "-u", str(obj)], text=True)
        assert not re.search(r"\b_?(?:calloc|realloc|memdup|new_array\w*)\b", symbols), symbols
        run([cc, *flags, gc, obj, work / "core.o", "-o", work / (fixture + "-v")])
        if fixture == "boot":
            c = subprocess.check_output([str(work / "boot-c")])
            v = subprocess.check_output([str(work / "boot-v")])
            assert c == v == b"Apple loader boot ABI/runtime: PASS\n", (c, v)
            receipts["boot"] = c.decode().strip()
    sys.path.insert(0, str(HERE))
    import qemu_iboot
    import ioreg_adt
    synthetic = work / "synthetic.adt"
    synthetic.write_bytes(qemu_iboot.build_adt(0x43000000, True))
    truncated = work / "truncated.adt"
    truncated.write_bytes(synthetic.read_bytes()[:-1])
    empty = work / "empty.adt"
    empty.write_bytes(b"")
    cases = [[], [work / "missing.adt", "OUT"], [synthetic, "OUT"],
             [synthetic, "OUT", "fixture bootargs"],
             [synthetic, "OUT", "--reg", "/arm-io/wdt", "--reg", "/missing"],
             [synthetic, "OUT", "args", "--reg", "/arm-io/aic", "ignored", "/chosen"],
             [synthetic, work / "missing-directory/out"], [truncated, "OUT"], [empty, "OUT"]]
    if platform.system() == "Darwin":
        real = work / "ioreg.adt"
        real.write_bytes(ioreg_adt.build()[0])
        cases += [[real, "OUT", "vinix.converter_check=1", "--reg", "/arm-io/wdt"]]
    for index, arguments in enumerate(cases):
        results = []
        for variant in ("c", "v"):
            output = work / (f"output-{index}-{variant}.fdt")
            argv = [str(output) if x == "OUT" else str(x) for x in arguments]
            result = subprocess.run(["adt2fdt", *argv], executable=work / ("converter-" + variant),
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            # Both filenames differ only to retain both binary outputs.
            err = result.stderr.replace(str(output).encode(), b"OUT")
            results.append((result.returncode, result.stdout, err,
                            output.read_bytes() if output.exists() else None))
        assert results[0] == results[1], (index, results)
        receipt = {"index": index, "returncode": results[0][0],
                   "stdout": results[0][1].decode(), "stderr": results[0][2].decode()}
        if results[0][3] is not None:
            receipt["fdt_sha256"] = hashlib.sha256(results[0][3]).hexdigest()
        receipts["cases"].append(receipt)
    (work / "validation.json").write_text(json.dumps(receipts, indent=2) + "\n")
    print(f"Apple loader fixture C/V parity: PASS ({len(cases)} converter cases, all boot goldens)")


if __name__ == "__main__":
    main()
