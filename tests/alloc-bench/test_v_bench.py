#!/usr/bin/env python3
"""Compare portable benchmark semantics with immutable C, including rollback."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
ALIASES = {name: "vab_fixture_" + name for name in (
    "malloc", "free", "mmap", "munmap", "pipe", "close", "clock_gettime",
    "clock_getres", "uname", "sysconf")}
ALIASES["clock_gettime"] = "vab_fixture_clock_gettime"
ALIASES["clock_getres"] = "vab_fixture_clock_getres"


def build(work, flags, arch, original=None, model=False, guest=False):
    source = work / "bench.c"
    if original:
        source.write_bytes(original.read_bytes())
        manifest = {"source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                    "original": str(original)}
    else:
        manifest = runpy.run_path(str(HERE / "compile-v-bench.py"))["generate"](source, arch)
    compile_flags = [p for p in flags if not p.startswith(("-L", "-l", "-fuse-ld="))]
    obj = work / "bench.o"
    defines = [f"-D{k}={v}" for k, v in ALIASES.items()] if model else []
    if guest:
        defines.append("-Dmain=alloc_bench_native_main")
    subprocess.run(compile_flags + defines + ["-I", str(work), "-c", str(source), "-o", str(obj)], check=True)
    imports = subprocess.check_output([os.environ.get("NM", "nm"), "-u", str(obj)], text=True)
    assert not re.search(r"\b_?(?:calloc|realloc|memdup|v_malloc|new_array\w*)\b", imports), imports
    assert not re.search(r"\b(?:memdup|new_array\w*|v_malloc)\s*\(", source.read_text())
    objects = [obj]
    if model:
        provider = work / "provider.c"
        runpy.run_path(str(ROOT / "build-support/compile-v-module.py"))["generate"](HERE / "benchfixture", provider, arch)
        provider_obj = work / "provider.o"
        subprocess.run(compile_flags + ["-Wno-unused-function", "-Wno-unused-parameter", "-I", str(HERE / "benchfixture"), "-c", str(provider), "-o", str(provider_obj)], check=True)
        objects.append(provider_obj)
    if guest:
        entry = work / "guestentry"
        entry.mkdir()
        (entry / "entry-abi.h").write_text("#include <stdio.h>\n#include <unistd.h>\nint alloc_bench_native_main(int, char **);\n")
        (entry / "core.v").write_text("""module guestentry
#include <entry-abi.h>
fn C.alloc_bench_native_main(i32, &&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32
@[export: 'main']
pub fn run() i32 {
    unsafe {
        args := [&char(c'alloc-bench'), &char(c'--iterations'), &char(c'65'), &char(c'--samples'), &char(c'6'), &char(c'--label'), &char(c'native'), &char(nil)]!
        result := C.alloc_bench_native_main(7, &args[0])
        C.fflush(nil)
        if result == 0 { for { C.pause() } }
        return result
    }
}
""")
        generated = work / "entry.c"
        runpy.run_path(str(ROOT / "build-support/compile-v-module.py"))["generate"](entry, generated, arch)
        entry_obj = work / "entry.o"
        subprocess.run(compile_flags + ["-Wno-unused-function", "-Wno-unused-parameter", "-I", str(entry), "-c", str(generated), "-o", str(entry_obj)], check=True)
        objects.append(entry_obj)
        serial = work / "serial.o"
        runpy.run_path(str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"))["compile_serial"](serial, "aarch64" if arch == "arm64" else "x86_64", flags)
        objects.append(serial)
    exe = work / "test"
    subprocess.run(flags + (["-static"] if guest else []) + [str(p) for p in objects] + ["-o", str(exe)], check=True)
    manifest.update(compiler_flags=flags, arch=arch, model=model, guest=guest,
                    executable_sha256=hashlib.sha256(exe.read_bytes()).hexdigest(), imports=imports.splitlines())
    (work / "inputs.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return exe


def invoke(exe, args, mode="none", index=1):
    return subprocess.run([str(exe), *args], capture_output=True,
                          env={**os.environ, "VAB_FAIL": mode, "VAB_FAIL_INDEX": str(index),
                               "ASAN_OPTIONS": "detect_leaks=1", "UBSAN_OPTIONS": "halt_on_error=1"},
                          timeout=180)


def normalize(contents, help_text=False):
    contents = re.sub(rb"Usage: [^\n]+", b"Usage: PROGRAM [--iterations N] [--samples N] [--quick] [--label NAME]", contents)
    if help_text:
        contents = re.sub(rb"Build: [^\n]+", b"Build: generated benchmark", contents)
    return contents


def compare(v_exe, c_exe, work):
    cases = [("success", ["--iterations", str(n), "--samples", str(samples), "--label", "a_Z-0.1"], "none", 1)
             for n, samples in ((1, 5), (63, 6), (64, 5), (65, 6), (257, 31), (2000, 5))]
    cases += [("ordered", ["--quick", "--iterations", "65", "--samples", "6"], "none", 1),
              ("help", ["--help"], "none", 1), ("help_after_quick", ["--quick", "--help"], "none", 1)]
    invalid = [["--unknown"], ["--unknown", "value"], ["--samples"], ["--iterations"], ["--label"],
               *[["--iterations", s] for s in ("", "0", "-1", "+1", " 1", "1x", "1000000001", "18446744073709551616")],
               *[["--samples", s] for s in ("", "4", "32", "6x", "18446744073709551616")],
               *[["--label", s] for s in ("", "a" * 65, "a b", "a=b", "\u00ff")]]
    cases += [(f"invalid-{i}", args, "none", 1) for i, args in enumerate(invalid)]
    base = ["--iterations", "65", "--samples", "6"]
    # Every malloc failure position in the first mixed 64-object batch verifies
    # its prefix is freed in reverse; also cover the next batch and timed runs.
    malloc_positions = [1, 2, 65, 66, 130, 455, *range(456, 520), 520, 521, 910, 911, 912, 914, 915]
    cases += [(f"malloc-{i}", base, "malloc", i) for i in malloc_positions]
    for mode, positions in (("mmap", (1, 2, 28, 29, 30)), ("munmap", (1, 28, 29)),
                            ("pipe", (1, 2, 5)), ("close", (1, 2, 3, 4)),
                            ("clock", (1, 2, 3, 13, 24, 36, 72)),
                            ("close_both", (1,)), ("constant_clock", (1,)),
                            ("uname", (1,)), ("resolution", (1,)), ("pagesize", (1,))):
        cases += [(f"{mode}-{i}", base, mode, i) for i in positions]
    proofs = []
    for name, args, mode, index in cases:
        c = invoke(c_exe, args, mode, index)
        v = invoke(v_exe, args, mode, index)
        expected_help = name.startswith("help")
        c_out, v_out = normalize(c.stdout, expected_help), normalize(v.stdout, expected_help)
        assert (v.returncode, v_out, v.stderr) == (c.returncode, c_out, c.stderr), (name, v.returncode, c.returncode, v_out, c_out, v.stderr, c.stderr)
        assert not re.search(rb"runtime error|AddressSanitizer|LeakSanitizer", v.stderr + c.stderr)
        if name.startswith("success") or name == "ordered":
            assert v.returncode == 0 and b"ALLOC-DONE" in v_out
            assert len(re.findall(rb"^ALLOC-RESULT ", v_out, re.M)) == 6
        elif name.startswith("invalid"):
            assert v.returncode == 2
        elif not expected_help:
            assert v.returncode == 1 and b"ALLOC-ERROR" in v.stderr
        (work / f"{name}.stdout").write_bytes(v_out)
        (work / f"{name}.stderr").write_bytes(v.stderr)
        proofs.append({"case": name, "argv": args, "fault": mode, "index": index,
                       "returncode": v.returncode, "stdout_sha256": hashlib.sha256(v_out).hexdigest(),
                       "stderr_sha256": hashlib.sha256(v.stderr).hexdigest()})
    (work / "differential.json").write_text(json.dumps(proofs, indent=2) + "\n")
    print(f"Portable allocation benchmark: {len(cases)} C/V differential cases passed, including all 64 mixed-batch OOM prefixes")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--host-arch", choices=("arm64", "amd64"), default="arm64" if os.uname().machine in ("arm64", "aarch64") else "amd64")
    p.add_argument("--arch", choices=("aarch64", "x86_64"))
    p.add_argument("--state-dir", type=Path)
    p.add_argument("--original-reference", type=Path)
    p.add_argument("--kernel-dir", type=Path)
    p.add_argument("--guest-state-dir", type=Path)
    p.add_argument("--model", action="store_true", help="controlled clock and fault provider; no timing claim")
    a = p.parse_args()
    if a.arch and (not a.kernel_dir or not a.guest_state_dir):
        p.error("--arch requires --kernel-dir and --guest-state-dir")
    with tempfile.TemporaryDirectory(prefix="vinix-bench-test-") as directory:
        work = a.state_dir.resolve() if a.state_dir else Path(directory)
        if a.state_dir:
            work.mkdir(parents=True, exist_ok=False)
        arch = "arm64" if a.arch == "aarch64" else "amd64" if a.arch else a.host_arch
        if a.arch == "aarch64":
            sdk = Path(os.environ.get("VINIX_AARCH64_SYSROOT", ROOT / "build-aarch64-userland/sysroot"))
            cc = [os.environ.get("CC_AARCH64", "clang"), "--target=aarch64-linux-musl", f"--sysroot={sdk}", "-fuse-ld=lld", f"-L{sdk}/lib"]
        elif a.arch:
            cc = [os.environ.get("CC_AMD64", "x86_64-linux-musl-gcc")]
        else:
            cc = [os.environ.get("CC", "clang")]
            if os.uname().sysname == "Darwin":
                cc += ["-arch", "arm64" if arch == "arm64" else "x86_64"]
        flags = cc + ["-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-fno-builtin"]
        if not a.arch:
            flags += ["-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
        if a.arch:
            exe = build(work, flags, arch, a.original_reference, a.model, True)
            subprocess.run(["python3", str(ROOT / "tests/kernel-gaps/run.py"), "--arch", a.arch, "--prebuilt-init", str(exe), "--kernel-dir", str(a.kernel_dir), "--state-dir", str(a.guest_state_dir), "--no-network", "--timeout", "360", "--expect", "ALLOC-DONE label=native workloads=6 checksum=453", "--fail", "ALLOC-ERROR"], check=True)
        elif a.original_reference:
            (work / "v").mkdir(); (work / "c").mkdir()
            v = build(work / "v", flags, arch, model=True)
            c = build(work / "c", flags, arch, a.original_reference, model=True)
            compare(v, c, work)
        else:
            exe = build(work, flags, arch, model=a.model)
            output = invoke(exe, ["--iterations", "2000", "--samples", "6", "--label", "host"])
            assert output.returncode == 0 and b"ALLOC-DONE" in output.stdout, output.stderr
            (work / "stdout").write_bytes(output.stdout)
            (work / "stderr").write_bytes(output.stderr)
            print("Portable allocation benchmark: all six real host workloads passed")


if __name__ == "__main__":
    main()
