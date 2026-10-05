#!/usr/bin/env python3
"""Run independent C callers against the V sampler with ASan and UBSan."""
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="vinix-sampler-test-") as directory:
    work = Path(directory)
    generated = work / "sampler.c"
    subprocess.run(["python3", str(ROOT / "tests/alloc-bench/compile-v-sampler.py"),
                    str(generated), "--host-clock"], check=True)
    flags = ["clang", "-std=c11", "-O2", "-g", "-Wall", "-Wextra", "-Werror",
             "-fno-builtin", "-ffreestanding", "-fno-strict-aliasing",
             "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
             "-DVINIX_KALLOC_HOST_TEST", "-I" + str(ROOT / "kernel/c")]
    obj = work / "sampler.o"
    subprocess.run([*flags, "-c", str(generated), "-o", str(obj)], check=True)
    imports = subprocess.check_output(["nm", "-u", str(obj)], text=True)
    assert not re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b", imports), imports
    text = generated.read_text()
    assert "memdup(" not in text and "new_array" not in text
    executable = work / "test"
    subprocess.run([*flags[:-1], str(obj), str(ROOT / "tests/alloc-bench/kernel_sampler_test.c"),
                    "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
    print("Shared kernel allocator sampler: V source has no implicit allocator imports")
