#!/usr/bin/env python3
"""Package the shared V sampler as a macOS diagnostic kext using genuine GCC."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
COMMON_FLAGS = [
    "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-fno-builtin",
    "-ffreestanding", "-fno-stack-protector", "-mno-red-zone", "-mno-80387",
    "-mno-mmx", "-mno-sse", "-mno-sse2",
]
# Darwin GCC emits Mach-O with its small code model; -mcmodel=kernel is rejected.
DARWIN_FLAGS = ["-mkernel", "-fno-pie", "-fno-PIC", "-mmacosx-version-min=10.15"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gcc", default="gcc-mp-14")
    parser.add_argument("--library-path",
                        help="DYLD_LIBRARY_PATH for a relocated MacPorts GCC installation")
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument("--vm-config", type=Path,
                        help="optional target QEMU configuration to copy into manifest")
    args = parser.parse_args()
    gcc = shutil.which(args.gcc)
    if not gcc:
        parser.error(f"GCC executable not found: {args.gcc}")
    environment = os.environ.copy()
    if args.library_path:
        environment["DYLD_LIBRARY_PATH"] = args.library_path
    macros = subprocess.check_output([gcc, "-dM", "-E", "-"], input=b"", env=environment)
    if b"#define __GNUC__ " not in macros or b"#define __clang__ " in macros:
        parser.error("the C compiler must be GNU GCC; Apple /usr/bin/gcc is Clang")
    if b"#define __APPLE__ " not in macros or b"#define __x86_64__ " not in macros:
        parser.error("GCC must target x86_64 Apple Darwin for this diagnostic kext")
    compiler_version = subprocess.check_output([gcc, "--version"], text=True,
                                               env=environment).splitlines()[0]
    includes = subprocess.check_output([gcc, "-print-file-name=include"], text=True,
                                       env=environment).strip()
    if not Path(includes).is_dir():
        parser.error(f"GCC intrinsic headers not found: {includes}")
    state = args.state_dir.resolve()
    state.mkdir(parents=True, exist_ok=False)
    bundle = state / "AllocKernelBench.kext"
    executable = bundle / "Contents/MacOS/AllocKernelBench"
    executable.parent.mkdir(parents=True)
    info = {
        "CFBundleDevelopmentRegion": "English",
        "CFBundleExecutable": "AllocKernelBench",
        "CFBundleIdentifier": "org.vinix.AllocKernelBench",
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": "AllocKernelBench",
        "CFBundlePackageType": "KEXT",
        "CFBundleShortVersionString": "1.0.0",
        "CFBundleVersion": "1.0.0",
        "OSBundleRequired": "Root",
        "OSBundleLibraries": {
            "com.apple.kpi.libkern": "8.0.0", "com.apple.kpi.iokit": "8.0.0",
        },
    }
    (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
    generated = state / "heap_benchmark.c"
    subprocess.run(["python3", str(ROOT / "tests/alloc-bench/compile-v-sampler.py"),
                    str(generated)], check=True)
    shutil.copyfile(ROOT / "kernel/c/heap_benchmark_v.h", state / "heap_benchmark_v.h")
    metadata = state / "macos-kext-info.c"
    subprocess.run(["python3", str(ROOT / "tests/alloc-bench/compile-v-kmod-info.py"),
                    str(metadata)], check=True)
    sources = [generated, metadata]
    commands = []
    objects = []
    with (state / "build.log").open("wb") as log:
        for source in sources:
            assembly = state / (source.stem + ".s")
            obj = state / (source.stem + ".o")
            commands.extend([
                [gcc, *COMMON_FLAGS, *DARWIN_FLAGS, "-nostdinc", "-isystem", includes,
                 "-S", str(source), "-o", str(assembly)],
                ["xcrun", "clang", "-target", "x86_64-apple-macos10.15", "-mkernel",
                 "-mno-red-zone", "-c", str(assembly), "-o", str(obj)],
            ])
            for command in commands[-2:]:
                subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True,
                               env=environment)
            objects.append(str(obj))
        link = ["xcrun", "ld", "-arch", "x86_64", "-kext", "-undefined",
                "dynamic_lookup", "-no_uuid", *objects, "-o", str(executable)]
        commands.append(link)
        subprocess.run(link, stdout=log, stderr=subprocess.STDOUT, check=True)
    manifest = json.loads(args.vm_config.read_text()) if args.vm_config else {}
    manifest.update(
        compile_flags=COMMON_FLAGS, platform_compile_flags=DARWIN_FLAGS,
        source_sha256=hashlib.sha256(sources[0].read_bytes()).hexdigest(),
        adapter_sha256=hashlib.sha256(sources[1].read_bytes()).hexdigest(),
        metadata_language="V",
        metadata_source_sha256=hashlib.sha256((ROOT / "tests/alloc-bench/kmodmeta/core.v").read_bytes()).hexdigest(),
        metadata_generator_sha256=hashlib.sha256((ROOT / "tests/alloc-bench/compile-v-kmod-info.py").read_bytes()).hexdigest(),
        metadata_initialization="static native data; compiler aggregate initializer promoted before loading",
        sampler_header_sha256=hashlib.sha256((state / "heap_benchmark_v.h").read_bytes()).hexdigest(),
        sampler_language="V",
        compiler=compiler_version, build_commands=commands,
        compiler_library_path=args.library_path,
        execution_context="kext", arch="x86_64",
        build_method="V generated C; GNU GCC C-to-assembly; Apple assembler/linker",
        compilation_host=dict(system=platform.system(), release=platform.release(),
                              machine=platform.machine()),
        binary_sha256=hashlib.sha256(executable.read_bytes()).hexdigest(),
    )
    (state / "config.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(bundle)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
