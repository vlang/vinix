#!/usr/bin/env python3
"""Compare maintained V native boundaries with their frozen C header bodies."""
import importlib.util
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
ORIGINAL = "8f7239d1fd4c593746279699f6ff25df5f4dd7bd"


def main():
    if platform.machine() not in ("arm64", "aarch64"):
        raise SystemExit("This differential boundary fixture requires an ARM64 host")
    spec = importlib.util.spec_from_file_location("vmodule", ROOT / "build-support/compile-v-module.py")
    compiler = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(compiler)
    with tempfile.TemporaryDirectory(prefix="vinix-native-boundaries-") as directory:
        work = Path(directory)
        flags = [os.environ.get("CC", "clang"), "-O2", "-g", "-Wall", "-Wextra", "-Werror",
                 "-Wno-unused-function", "-Wno-unused-parameter", "-ffreestanding", "-fno-builtin",
                 "-fno-strict-aliasing", "-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
        results = []
        for label in ("original", "v"):
            test = work / label
            test.mkdir()
            source = test / "uart"
            shutil.copytree(ROOT / "tests/native-boundaries/uart", source)
            for header in ("symbols.h", "apple_smc.h"):
                target = test / header
                if label == "original":
                    target.write_bytes(subprocess.check_output([
                        "git", "-C", str(ROOT), "show", ORIGINAL + ":kernel/c/" + header]))
                else:
                    shutil.copyfile(ROOT / "kernel/c" / header, target)
            objects = []
            if label == "v":
                shutil.copyfile(ROOT / "kernel/aarch64/uart/trace_arm64.v", source / "trace.v")
                for module, original in (("lib", "kernel/lib/callback_abi.v"),
                                         ("smc", "kernel/apple/smc/counter_arm64.v")):
                    native = test / module
                    native.mkdir()
                    shutil.copyfile(ROOT / original, native / "core.v")
                    generated = test / (module + ".c")
                    compiler.generate(native, generated, "arm64")
                    obj = generated.with_suffix(".o")
                    subprocess.run(flags + ["-c", str(generated), "-o", str(obj)], check=True)
                    imports = subprocess.check_output(["nm", "-u", str(obj)], text=True)
                    if re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b", imports):
                        raise RuntimeError("native boundary allocator import: " + imports)
                    objects.append(obj)
                assembly = (ROOT / "kernel/asm/aarch64/stack_pointer.S").read_text()
                assembly = re.sub(r"(?m)^\.type .*\n|^\.size .*\n|^\.section \.note.*\n", "", assembly)
                assembly = assembly.replace("read_current_sp", "_read_current_sp")
                native_sp = test / "stack_pointer.S"
                native_sp.write_text(assembly)
                obj = test / "stack_pointer.o"
                subprocess.run(flags + ["-c", str(native_sp), "-o", str(obj)], check=True)
                objects.append(obj)
            generated = test / "fixture.c"
            compiler.generate(source, generated, "arm64")
            binary = test / "fixture"
            subprocess.run(flags + ["-I", str(test), str(generated), *map(str, objects),
                                    "-o", str(binary)], check=True)
            result = subprocess.run([str(binary)], capture_output=True, text=True,
                                    env={**os.environ, "ASAN_OPTIONS": "detect_stack_use_after_return=1"})
            if result.returncode:
                raise RuntimeError(label + " fixture failed: " + result.stdout + result.stderr)
            results.append((result.stdout, result.stderr))
        if results[0] != results[1]:
            raise RuntimeError("native boundary differential output mismatch: " + repr(results))
        print(results[1][0], end="")
        print("Frozen C / production V ASan/UBSan and stack-use-after-return: PASS")


if __name__ == "__main__":
    main()
