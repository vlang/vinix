#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Compare native overflow/constant/policy behavior with immutable C headers."""
import argparse
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
ORIGINAL = "d0a65f5953058f4f7542cd588acbb38039491c04"


def load(name, path):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def prepare(work, arch, suffix=""):
    compiler = load("overflow_compiler", ROOT / "build-support/compile-v-module.py")
    abi = load("overflow_abi", ROOT / ("kernel/linuxkpi/generate-abi.py" + suffix))
    for module, parent in (("overflowfixture", "tests/linuxkpi"), ("overflowdomain", "tests/linuxkpi")):
        source = work / module
        source.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / parent / module / ("core.v" + suffix), source / "core.v")
        compiler.generate(source, work / (module + ".c"), arch, ["nofloat"])
    (work / "headercore").mkdir()
    shutil.copyfile(ROOT / "kernel/linuxkpi/headercore" / ("policy.v" + suffix), work / "headercore/policy.v")
    abi.generate(ROOT / ("kernel/linuxkpi/abi/overflow.json" + suffix), work,
                 work / "V/include/vinix/integer_policy.h")
    original = work / "original/include"
    for header in ("linux/overflow.h", "linux/slab.h", "linux/preempt.h", "linux/irqflags.h"):
        path = original / header
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(subprocess.check_output(["git", "show", ORIGINAL + ":kernel/linuxkpi/include/" + header], cwd=ROOT))
    # Keep the pinned type-or-expression/constant family byte-for-byte. Only
    # compiler builtin bindings move to the generated declaration adapter.
    overflow = (original / "linux/overflow.h").read_text()
    matches = re.findall(r"^#define check_(?:add|sub|mul)_overflow[^\n]*\n", overflow, re.M)
    if len(matches) != 3:
        raise AssertionError("Expected exactly three pinned compiler bindings")
    replacement = re.sub(r"^#define check_(?:add|sub|mul)_overflow[^\n]*\n", "", overflow, flags=re.M)
    replacement = replacement.replace("#include <linux/const.h>\n",
                                      "#include <linux/const.h>\n#include <vinix/integer_policy.h>\n", 1)
    target = work / "V/include/linux/overflow.h"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(replacement)
    for header, macro in (("slab.h", "ZERO_OR_NULL_PTR"), ("preempt.h", "preemptible")):
        old = (original / "linux" / header).read_text()
        changed, count = re.subn(r"^#define " + macro + r"\([^\n]*\n",
                                 "#include <vinix/integer_policy.h>\n", old, flags=re.M)
        if count != 1:
            raise AssertionError((header, macro, count))
        (work / "V/include/linux" / header).write_text(changed)
    (original / "vinix").mkdir(parents=True, exist_ok=True)
    # This is a declaration/include wrapper around exact immutable headers,
    # materialized only outside the checkout. No original body is rewritten.
    (original / "vinix/integer_policy.h").write_text(
        '#include <linux/overflow.h>\n#include <linux/slab.h>\n#include <linux/preempt.h>\n'
        )
    for kind in ("original", "V"):
        abi.generate(ROOT / "kernel/linuxkpi/abi/spinlock.json", ROOT / "kernel/linuxkpi",
                     work / kind / "include/vinix/spinlock_adapters.h")
        abi.generate(ROOT / "kernel/linuxkpi/abi/atomic-exchange.json", ROOT / "kernel/linuxkpi",
                     work / kind / "include/vinix/atomic_exchange.h")
    subprocess.run(["python3", str(ROOT / "tests/linuxkpi/compile-v-primitives.py"), "--host",
                    "--arch", arch, "--implementations-only", str(work / "primitive.c")], check=True)
    return compiler, abi


def constant_flags():
    kinds = {"I8": "signed char", "U8": "unsigned char", "I16": "short", "U16": "unsigned short",
             "I32": "int", "U32": "unsigned int", "I64": "long long", "U64": "unsigned long long",
             "I128": "__int128", "U128": "unsigned __int128"}
    result = ["-DVOP_MAX_" + name + "=type_max(" + native + ")" for name, native in kinds.items()]
    result += ["-DVOP_POLICY_INT=(__builtin_types_compatible_p(__typeof__(preemptible()), int) && "
               "__builtin_types_compatible_p(__typeof__(ZERO_OR_NULL_PTR((void *)0)), int))"]
    result += ["-DVOP_ZERO_CONST_I32=ZERO_OR_NULL_PTR(16)",
               "-DVOP_ZERO_CONST_PTR=ZERO_OR_NULL_PTR((void *)0)"]
    return result


def domains(work, flags):
    # Native type syntax is an ABI declaration flag. The same independent V
    # source is compiled against both exact original and generated adapters.
    kinds = [("signed _BitInt(17)", "0"), ("unsigned _BitInt(17)", "0"),
             ("signed _BitInt(32)", "type_max(vop_domain_t)"),
             ("unsigned _BitInt(8)", "type_max(vop_domain_t)"),
             ("signed _BitInt(128)", "type_max(vop_domain_t)"),
             ("unsigned _BitInt(257)", "0"),
             ("overflowdomain__DomainValue", "type_max(vop_domain_t)"),
             ("volatile int", "type_max(vop_domain_t)"),
             ("const int", "0"), ("_Atomic(int)", "0"), ("_Bool", "0"),
             ("float", "0"), ("signed _BitInt(17)", "type_max(vop_domain_t)")]
    reports = []
    for number, (native_type, maximum) in enumerate(kinds):
        outcomes = []
        for kind in ("original", "V"):
            target = work / kind / ("domain-" + str(number) + ".o")
            native = flags[:1] + ["-I" + str(work / kind / "include")] + flags[1:]
            declarations = ["-Dvop_domain_t=" + native_type, "-DVOP_DOMAIN_SIZE=sizeof(vop_domain_t)",
                            "-DVOP_DOMAIN_MAX=" + maximum,
                            "-DVOP_DOMAIN_BOOL=__builtin_types_compatible_p(vop_domain_t, _Bool)"]
            compiled = subprocess.run(native + declarations + ["-c", str(work / "overflowdomain.c"), "-o", str(target)],
                                      capture_output=True, text=True)
            if compiled.returncode:
                outcomes.append((False, ""))
                continue
            executable = target.with_suffix(".test")
            dead_strip = "-Wl,-dead_strip" if platform.system() == "Darwin" else "-Wl,--gc-sections"
            subprocess.run(native + [str(target), dead_strip, "-o", str(executable)], check=True)
            result = subprocess.run([str(executable)], capture_output=True, text=True, check=True,
                                    env={**os.environ, "ASAN_OPTIONS": "detect_stack_use_after_return=1", "UBSAN_OPTIONS": "halt_on_error=1"}, timeout=10)
            if result.stderr:
                raise AssertionError((native_type, result.stderr))
            outcomes.append((True, result.stdout))
        if outcomes[0] != outcomes[1]:
            raise AssertionError((native_type, maximum, outcomes))
        reports.append({"type": native_type, "constant": maximum, "accepted": outcomes[0][0],
                        "observation": outcomes[0][1].strip()})
    print("Native operand/constant domains: " + json.dumps(reports, sort_keys=True))


def run(arch=None):
    linux = Path(os.environ.get("LINUXKPI_SOURCE_DIR", ROOT / "third_party/linux-i915/linux-6.6.157"))
    machine = platform.machine().lower()
    native_arch = "arm64" if machine in ("arm64", "aarch64") else "amd64"
    arch = arch or native_arch
    if machine not in ("arm64", "aarch64", "x86_64", "amd64"):
        raise ValueError(f"Unsupported native host: {machine}")
    with tempfile.TemporaryDirectory(prefix="vinix-overflow-policy-") as directory:
        work = Path(directory)
        prepare(work, arch)
        flags = [os.environ.get("CC", "clang"), "-std=gnu11", "-fgnu89-inline", "-O1", "-g",
                 "-ffreestanding", "-fno-builtin", "-fwrapv", "-fno-strict-aliasing",
                 "-ffunction-sections", "-fdata-sections", "-Wall", "-Wextra", "-Werror",
                 "-Wno-unused-function", "-Wno-unused-parameter", "-D_FORTIFY_SOURCE=0",
                 "-D__sputc=vop_header_sputc", "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
                 "-DVINIX_LINUXKPI", "-DVINIX_LINUXKPI_HOST_TEST", "-D__KERNEL__", "-Dvop_i128=__int128",
                 "-include", str(ROOT / "tests/linuxkpi/host_types.h"), "-include", "linux/kconfig.h",
                 "-include", str(linux / "include/linux/compiler_types.h"), "-iquote", str(ROOT / "kernel/c"),
                 "-I" + str(ROOT / "kernel/linuxkpi/include"), "-I" + str(linux / "include"),
                 "-I" + str(linux / "include/uapi"), "-I" + str(linux / "arch/x86/include"),
                 "-I" + str(linux / "arch/x86/include/uapi")]
        if platform.system() == "Darwin" and arch != native_arch:
            flags[1:1] = ["-target", "x86_64-apple-darwin" if arch == "amd64" else "arm64-apple-darwin"]
        domains(work, flags)
        outputs = []
        for kind in ("original", "V"):
            native = flags[:1] + ["-I" + str(work / kind / "include")] + flags[1:]
            objects = []
            # IRQ primitives were already ported before this pinned revision;
            # both oracles link the same unchanged V implementation.
            for module in ("overflowfixture", "primitive"):
                source = work / (module + ".c")
                target = work / kind / (module + ".o")
                subprocess.run(native + (constant_flags() if module == "overflowfixture" else []) +
                               ["-c", str(source), "-o", str(target)], check=True)
                symbols = subprocess.check_output(["nm", "-u", str(target)], text=True)
                if re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b", symbols):
                    raise AssertionError(f"Implicit allocation in {module}:\n{symbols}")
                objects.append(str(target))
            executable = work / kind / "test"
            dead_strip = "-Wl,-dead_strip" if platform.system() == "Darwin" else "-Wl,--gc-sections"
            subprocess.run(native + objects + [dead_strip, "-o", str(executable)], check=True)
            result = subprocess.run([str(executable)], capture_output=True, text=True, check=True,
                                    env={**os.environ, "ASAN_OPTIONS": "detect_stack_use_after_return=1", "UBSAN_OPTIONS": "halt_on_error=1"}, timeout=60)
            print(kind + ": " + result.stdout.strip())
            outputs.append((result.stdout, result.stderr))
        if outputs[0] != outputs[1]:
            raise AssertionError(outputs)
    print("LinuxKPI overflow:589824 exhaustive narrow checks, mixed native128 boundaries, constants and lvalues passed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", choices=("arm64", "amd64"))
    args = parser.parse_args()
    run(args.arch)
