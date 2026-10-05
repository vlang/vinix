#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Compare both native V Steam preload policies with immutable original C."""
import argparse
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import shutil

ROOT = Path(__file__).resolve().parents[2]
ORIGINAL = "8f7239d1fd4c593746279699f6ff25df5f4dd7bd"


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def build_native(work):
    """Build libc-free fixtures in each actual x86 ABI, including i386 offsets."""
    compiler = load("vmodule", ROOT / "build-support/compile-v-module.py")
    robust = load("robust", ROOT / "build-support/steam/compile-v-robust.py")
    for i386 in (False, True):
        name = "i386" if i386 else "x86_64"
        directory = work / (name + "-native")
        directory.mkdir(parents=True, exist_ok=True)
        source = directory / "robustfixture"
        if source.exists():
            shutil.rmtree(source)
        shutil.copytree(ROOT / "tests/steam/robustfixture", source)
        (source / "concurrency.v").unlink()
        path = source / "core.v"
        text = path.read_text()
        for header in ("assert.h", "stdio.h", "string.h"):
            text = text.replace("#include <" + header + ">", "")
        for previous, replacement in [("assert", "assert"), ("puts", "puts"), ("strcmp", "strcmp")]:
            text = text.replace("fn C." + previous + "(", "@[c_extern]\nfn C.robust_bare_" + replacement + "(")
            text = text.replace("C." + previous + "(", "C.robust_bare_" + replacement + "(")
        path.write_text(text)
        fixture = directory / "fixture.c"
        compiler.generate(source, fixture, arch="i386" if i386 else "amd64",
                          defines=(["steam_i386"] if i386 else []) + ["steam_robust_bare"])
        helpers = directory / "helpers.c"
        compiler.generate(ROOT / "tests/steam/robustbare", helpers, arch="i386" if i386 else "amd64")
        helper_header = directory / "helpers.h"
        compiler.emit_header(ROOT / "tests/steam/robustbare", helpers, helper_header)
        fixture.write_text('#include "helpers.h"\n' + fixture.read_text())
        for artifact in (fixture, helpers):
            artifact.write_text(robust.diagnostic_declarations() +
                                artifact.read_text().replace("#include <inttypes.h>\n", ""))
        production = directory / "production.c"
        robust.generate(production, i386)
        original = directory / "original.c"
        original.write_bytes(subprocess.check_output([
            "git", "-C", str(ROOT), "show", ORIGINAL + ":build-support/steam/robust-list-" + name + ".c"]))
        flags = ["clang", "--target=" + name + "-linux-gnu", "-ffreestanding", "-fno-builtin",
                 "-fno-stack-protector", "-O2", "-ffunction-sections", "-fdata-sections",
                 "-Wall", "-Wextra", "-Werror", "-Wno-unused-function", "-Wno-unused-label", "-Wno-unused-parameter"]
        common_objects = []
        for artifact in (fixture, helpers, ROOT / "tests/steam/robust-bare-start.S"):
            obj = directory / (artifact.stem + ".o")
            subprocess.run(flags + ["-c", str(artifact), "-o", str(obj)], check=True)
            common_objects.append(obj)
        remaps = {"dlsym": "robust_fixture_dlsym", "pthread_self": "robust_fixture_pthread_self",
                  "syscall": "robust_subject_syscall", "mmap": "robust_subject_mmap",
                  "mmap64": "robust_subject_mmap64", "munmap": "robust_subject_munmap",
                  "uname": "robust_subject_uname"}
        for label, subject in [("v", production), ("original", original)]:
            obj = directory / (label + ".o")
            subprocess.run(flags + ["-D" + key + "=" + value for key, value in remaps.items()] +
                           ["-c", str(subject), "-o", str(obj)], check=True)
            abi = directory / (label + "-abi.o")
            subprocess.run(flags + (["-DSTEAM_ROBUST_ORIGINAL"] if label == "original" else []) +
                           ["-c", str(ROOT / "tests/steam/robust-fixture-abi.S"), "-o", str(abi)], check=True)
            extra_objects = []
            if label == "v":
                native_abi = directory / "forward-abi.o"
                subprocess.run(flags + ["-c", str(ROOT / "build-support/steam/robust-syscall.S"),
                                       "-o", str(native_abi)], check=True)
                extra_objects.append(native_abi)
            subprocess.run(["/opt/homebrew/bin/ld.lld", "-m", "elf_i386" if i386 else "elf_x86_64",
                            "-static", "--gc-sections", "-e", "_start", "-o", str(directory / label),
                            *map(str, common_objects), str(obj), str(abi), *map(str, extra_objects)], check=True)
        print(name + " actual native ABI fixtures linked", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--native", action="store_true", help="Also emit libc-free i386 and x86-64 fixtures")
    args = parser.parse_args()
    temporary = tempfile.TemporaryDirectory(prefix="vinix-steam-robust-proof-") if not args.output_dir else None
    work = args.output_dir.resolve() if args.output_dir else Path(temporary.name)
    work.mkdir(parents=True, exist_ok=True)
    compiler = load("vmodule", ROOT / "build-support/compile-v-module.py")
    robust = load("robust", ROOT / "build-support/steam/compile-v-robust.py")
    remaps = {"dlsym": "robust_fixture_dlsym", "pthread_self": "robust_fixture_pthread_self",
              "syscall": "robust_subject_syscall", "mmap": "robust_subject_mmap",
              "mmap64": "robust_subject_mmap64", "munmap": "robust_subject_munmap",
              "uname": "robust_subject_uname"}
    flags = ["clang", "-O1", "-g", "-fno-builtin", "-fsanitize=address,undefined",
             "-fno-omit-frame-pointer", "-Wall", "-Wextra", "-Werror",
             "-Wno-unused-function", "-Wno-unused-label", "-Wno-unused-parameter"]
    for i386 in (False, True):
        name = "i386" if i386 else "x86_64"
        fixture = work / (name + "-fixture.c")
        compiler.generate(ROOT / "tests/steam/robustfixture", fixture,
                          defines=["steam_i386"] if i386 else [])
        production = work / (name + "-v.c")
        robust.generate(production, i386, host=True)
        original = work / (name + "-original.c")
        original.write_bytes(subprocess.check_output([
            "git", "-C", str(ROOT), "show", ORIGINAL + ":build-support/steam/robust-list-" + name + ".c"]))
        outputs = []
        for label, source in [("v", production), ("original", original)]:
            subject = work / (name + "-" + label + ".o")
            subprocess.run(flags + ["-D" + key + "=" + value for key, value in remaps.items()] +
                           ["-c", str(source), "-o", str(subject)], check=True)
            executable = work / (name + "-" + label)
            native_abi = [str(ROOT / "build-support/steam/robust-syscall.S")] if label == "v" else []
            subprocess.run(flags + (["-DSTEAM_ROBUST_ORIGINAL"] if label == "original" else []) +
                           [str(fixture), str(subject), str(ROOT / "tests/steam/robust-fixture-abi.S"),
                            *native_abi, "-o", str(executable)], check=True)
            output = subprocess.run([str(executable)], capture_output=True, check=True)
            outputs.append((output.stdout, output.stderr))
        assert outputs[0] == outputs[1], outputs
        print(name + " sanitizer/native ABI differential PASS", flush=True)
    if args.native:
        build_native(work)
    if temporary:
        temporary.cleanup()


if __name__ == "__main__":
    main()
