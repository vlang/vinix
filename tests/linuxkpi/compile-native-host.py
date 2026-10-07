#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Build the complete unchanged LinuxKPI host-model workload for native musl."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import runpy
import subprocess

ROOT = Path(__file__).resolve().parents[2]
TESTS = ROOT / "tests/linuxkpi"


def build(work, arch):
    work.mkdir(parents=True, exist_ok=True)
    source = Path(os.environ.get("LINUXKPI_SOURCE_DIR", ROOT / "third_party/linux-i915/linux-6.6.157"))
    if arch == "aarch64":
        sysroot = ROOT / "build-aarch64-userland/sysroot"
        gcc = sorted((ROOT / "build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl").iterdir())[-1]
        # The installed musl SDK's compiler-runtime archive has no outlined
        # AArch64 atomic helpers. Emit the native LL/SC sequence at each call.
        cc = [os.environ.get("CC_AARCH64", "/opt/homebrew/opt/llvm/bin/clang"), "--target=aarch64-linux-musl", "--sysroot=" + str(sysroot), "--gcc-install-dir=" + str(gcc), "-mno-outline-atomics"]
        link = ["-L" + str(sysroot / "lib"), "-fuse-ld=lld"]
        v_arch, assembly = "arm64", "aarch64"
    else:
        cc = [os.environ.get("CC_AMD64", "/opt/homebrew/Cellar/musl-cross/0.9.11/libexec/bin/x86_64-linux-musl-gcc")]
        link = []
        v_arch, assembly = "amd64", "x86_64"
    nm = os.environ.get("NM", "/opt/homebrew/opt/llvm/bin/llvm-nm")
    flags = ["-std=gnu11", "-fgnu89-inline", "-O2", "-g", "-fno-stack-protector", "-ffreestanding", "-fno-builtin", "-fwrapv", "-fno-strict-aliasing", "-Wall", "-Wextra", "-Werror", "-Wno-unused-parameter", "-Wno-unused-function", "-Wno-deprecated-declarations", "-pthread", "-D_GNU_SOURCE"]
    # GCC does not attach no_sanitize to global storage. These native objects
    # are unsanitized and therefore cannot acquire sanitizer red zones.
    if arch == "x86_64":
        # Upstream GENMASK validates arbitrary input types with native
        # constant expressions, including unsigned comparisons with zero.
        flags += ["-Wno-attributes", "-Wno-array-parameter", "-Wno-type-limits", "-Wno-misleading-indentation"]
    include = ["-DVINIX_LINUXKPI", "-DVINIX_LINUXKPI_HOST_TEST", "-DVINIX_LINUXKPI_FORMAT_HOST_TEST", "-D__KERNEL__",
        "-include", str(TESTS / "host_types.h"), "-include", "linux/kconfig.h", "-include", str(source / "include/linux/compiler_types.h"),
        "-iquote", str(ROOT / "kernel/c"), "-I" + str(work / "include"), "-I" + str(ROOT / "kernel/linuxkpi/include"), "-I" + str(source / "include"), "-I" + str(source / "include/uapi"), "-I" + str(source / "arch/x86/include"), "-I" + str(source / "arch/x86/include/uapi"), "-I" + str(source / "drivers/gpu/drm/i915")]
    for schema, header in (("spinlock", "spinlock_adapters"), ("atomic-exchange", "atomic_exchange"), ("overflow", "integer_policy")):
        subprocess.run(["python3", str(ROOT / "kernel/linuxkpi/generate-abi.py"), str(ROOT / ("kernel/linuxkpi/abi/" + schema + ".json")), str(work / ("include/vinix/" + header + ".h"))], check=True)
    subprocess.run(["python3", str(TESTS / "compile-v-core.py"), str(work / "compat.c"), "--arch", v_arch], check=True)
    # GCC diagnoses the committed V cache geometry's deliberate wider-size
    # overflow guards after folding narrower input bounds. Keep those guards.
    core_warnings = ["-Wno-type-limits", "-Wno-sign-compare"] if arch == "x86_64" else []
    subprocess.run(cc + flags + core_warnings + ["-DVINIX_V_RUNTIME", "-DVINIX_LINUXKPI_HOST_TEST", "-I" + str(ROOT / "kernel/c"), "-c", str(work / "compat.c"), "-o", str(work / "compat.o")], check=True)
    subprocess.run(["python3", str(TESTS / "compile-v-primitives.py"), "--host", "--arch", v_arch, str(work / "headercore.c")], check=True)
    subprocess.run(cc + flags + core_warnings + include + ["-c", str(work / "headercore.c"), "-o", str(work / "headercore.o")], check=True)
    generator = runpy.run_path(str(ROOT / "build-support/compile-v-module.py"))["generate"]
    generator(ROOT / "kernel/linuxkpi/exchangecore", work / "exchangecore.c", v_arch, ("nofloat",))
    subprocess.run(cc + flags + ["-c", str(work / "exchangecore.c"), "-o", str(work / "exchangecore.o")], check=True)
    for name in ("runtimefixture", "syncfixture", "i915policyfixture"):
        subprocess.run(["python3", str(TESTS / "compile-v-fixture.py"), name, "--host", "--arch", v_arch, str(work / (name + ".c"))], check=True)
        subprocess.run(cc + flags + include + ["-c", str(work / (name + ".c")), "-o", str(work / (name + ".o"))], check=True)
    generator(TESTS / "policyhost", work / "policyhost.c", v_arch, ("nofloat",))
    subprocess.run(cc + flags + ["-Dmain=vmh_host_entry", "-c", str(work / "policyhost.c"), "-o", str(work / "policyhost.o")], check=True)
    for name in ("linuxkpi_varargs", "linuxkpi_workqueue_abi", "linuxkpi_storage"):
        extra = ["-Dsnprintf=vinix_linuxkpi_format_test_snprintf", "-Dscnprintf=vinix_linuxkpi_format_test_scnprintf", "-Dsprintf=vinix_linuxkpi_format_test_sprintf"] if name == "linuxkpi_varargs" else []
        subprocess.run(cc + ["-DVINIX_LINUXKPI", "-DVINIX_LINUXKPI_HOST_TEST", "-I" + str(ROOT / ("kernel/asm/" + assembly)), *extra, "-c", str(ROOT / ("kernel/asm/" + assembly + "/" + name + ".S")), "-o", str(work / (name + ".o"))], check=True)
    subprocess.run(cc + ["-DVINIX_LINUXKPI", "-DVINIX_LINUXKPI_HOST_TEST", "-c", str(ROOT / "kernel/asm/x86_64/linuxkpi_fixture_abi.S"), "-o", str(work / "fixture_storage.o")], check=True)
    env = os.environ.copy()
    # A command argument, not shell source; host_suite splits this exact list.
    import shlex
    env.update(CC=shlex.join(cc + (["-Wno-attributes", "-Wno-array-parameter", "-Wno-type-limits", "-Wno-misleading-indentation", "-Wno-missing-braces"] if arch == "x86_64" else [])), NM=nm)
    subprocess.run(["python3", str(TESTS / "host_suite.py"), str(work), "--arch", v_arch, "--native"], env=env, check=True)
    upstream = [source / value for value in ("lib/list_sort.c", "lib/sort.c", "lib/rbtree.c", "lib/find_bit.c", "lib/hweight.c", "lib/ctype.c", "lib/siphash.c", "drivers/gpu/drm/i915/i915_config.c", "drivers/gpu/drm/i915/display/intel_qp_tables.c")]
    fixture = runpy.run_path(str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"))
    fixture["compile_module"](TESTS / "hostguest", work / "hostguest.o", arch, cc + flags)
    fixture["compile_serial"](work / "serial.o", arch, cc + flags)
    objects = [work / (name + ".o") for name in ("policyhost", "i915policyfixture", "runtimefixture", "syncfixture", "fixture_storage", "compat", "headercore", "exchangecore", "linuxkpi_varargs", "linuxkpi_storage", "linuxkpi_workqueue_abi", "hostguest", "serial")]
    # Imported find_bit.c's guarded GNU statement expressions trigger GCC's
    # conservative uninitialized-variable warning; keep upstream unchanged.
    upstream_warnings = ["-Wno-maybe-uninitialized"] if arch == "x86_64" else []
    command = cc + flags + upstream_warnings + include + ["-static", *map(str, objects), "@" + str(work / "host-fixtures.rsp"), *map(str, upstream), "-include", "linux/export.h", *link, "-o", str(work / "linuxkpi-host")]
    subprocess.run(command, check=True)
    hashes = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in work.glob("*.o")}
    receipt = {"arch": arch, "compiler": cc, "flags": flags, "link": command, "objects": hashes, "elf_sha256": hashlib.sha256((work / "linuxkpi-host").read_bytes()).hexdigest()}
    (work / "native-inputs.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print("LinuxKPI: strict native musl complete host workload built for " + arch, flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("work", type=Path)
    parser.add_argument("--arch", choices=("aarch64", "x86_64"), required=True)
    args = parser.parse_args()
    build(args.work.resolve(), args.arch)
