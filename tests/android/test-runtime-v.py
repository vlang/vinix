#!/usr/bin/env python3
"""Sanitize native callback retirement, fortify adapters and aggregate ABI."""
import argparse
import importlib.util
import os
from pathlib import Path
import platform
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--baseline", type=Path, help="Frozen original C implementation")
args = parser.parse_args()
if platform.system() != "Darwin" or platform.machine() != "arm64":
    raise SystemExit("This host adapter checks Darwin ARM64; run run-runtime-vm.py for native Linux ABI checks")
spec = importlib.util.spec_from_file_location("android_v_host_generator", ROOT / "build-support/compile-v-module.py")
compiler = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compiler)
spec_runtime = importlib.util.spec_from_file_location("android_v_runtime_generator", ROOT / "build-support/android/compile-v-runtime.py")
runtime = importlib.util.module_from_spec(spec_runtime)
spec_runtime.loader.exec_module(runtime)
with tempfile.TemporaryDirectory(prefix="vinix-android-host-") as directory:
    work = Path(directory)
    (work / "stdio_ext.h").write_text("#include <stdio.h>\nvoid __fseterr(FILE *);\n")
    # The production ABI uses Linux errno numbers. Preserve that ABI while
    # running the immutable Linux fixture against Darwin's real stream APIs.
    (work / "errno.h").write_text("#include_next <errno.h>\n#undef EOVERFLOW\n#define EOVERFLOW 75\n")
    flags = ["clang", "-O2", "-g", "-Wall", "-Wextra", "-Werror", "-Wno-unused-function",
             "-Wno-unused-label", "-Wno-unused-parameter", "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
             "-I", str(ROOT / "build-support/android"), "-I", str(ROOT / "tests/android"), "-I", str(work)]
    compiler.generate(ROOT / "tests/android/runtimehost", work / "host.c", "arm64", ["nofloat"])
    subprocess.run([*flags, "-c", str(work / "host.c"), "-o", str(work / "host.o")], check=True)
    runtime.generate(work / "runtime.c", "arm64")
    artifacts = [work / "runtime.c"] + ([args.baseline.resolve()] if args.baseline else [])
    results = []
    for index, source in enumerate(artifacts):
        obj = work / f"runtime-{index}.o"
        subprocess.run([*flags, "-D__linux__", "-D__errno_location=__error", "-Ddlsym=fixture_dlsym",
                        "-Dpthread_mutex_lock=fixture_pthread_mutex_lock",
                        "-Dpthread_mutex_trylock=fixture_pthread_mutex_trylock",
                        "-Dpthread_mutex_unlock=fixture_pthread_mutex_unlock",
                        "-c", str(source), "-o", str(obj)], check=True)
        imports = subprocess.check_output(["nm", "-u", str(obj)], text=True)
        assert not re.search(r"\b_?(?:malloc|calloc|realloc|memdup|new_array\w*)\b", imports), imports
        seen = []
        for probe in ("atfork-test", "fortify-test", "aggregate"):
            output = work / f"{index}-{probe}"
            fixture = [] if probe == "aggregate" else [str(ROOT / "tests/android" / (probe + ".c"))]
            # The host support owns main only for the aggregate fixture. Use
            # its generated symbol namespace for the immutable C probe mains.
            helper = work / "host.o"
            if fixture:
                helper = work / (probe + "-host.o")
                subprocess.run([*flags, "-Dmain=android_aggregate_main", "-c", str(work / "host.c"), "-o", str(helper)], check=True)
            subprocess.run([*flags, *fixture, str(helper), str(obj), "-Wl,-export_dynamic", "-o", str(output)], check=True)
            result = subprocess.run([str(output)], capture_output=True)
            assert result.returncode == 0, (index, probe, result.returncode, result.stdout, result.stderr)
            seen.append((probe, result.returncode, result.stdout, result.stderr))
            if probe == "aggregate":
                failed = subprocess.run([str(output)], env={**os.environ, "ANDROID_HOST_STATS_FAIL": "1"}, capture_output=True)
                assert failed.returncode == -6 and failed.stderr == b"Android allocator statistics ABI mismatch\n", failed
                seen.append(("provider-failure", failed.returncode, failed.stdout, failed.stderr))
        results.append(seen)
    if len(results) == 2:
        assert results[0] == results[1], "V and frozen C runtime fixture observations differ"
print("Android runtime host ASan/UBSan: original atfork retirement and fortify fixtures, 80-byte aggregate ABI, provider failure PASS")
