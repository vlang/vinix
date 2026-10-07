#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Compile independent V LinuxKPI host tests against the production objects."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
TESTS = ROOT / "tests/linuxkpi"
# Every group has its own native header/type namespace and generated object.
GROUPS = (
    ("hostmodel", "host_model_v_contract.h"),
    ("hostbase", "hostbase_v_contract.h"),
    ("hosttask", "hosttask_v_contract.h"),
    ("hostseq", "hostseq_v_contract.h"),
    ("hosttaskflag", "hosttaskflag_v_contract.h"),
    ("hostio", "hostio_v_contract.h"),
    ("hostwork", "hostwork_v_contract.h"),
    ("synchost", "synchost_v_contract.h"),
    ("wwhost", "wwhost_v_contract.h"),
    ("timehost", "timehost_v_contract.h"),
    ("timerhost", "timerhost_v_contract.h"),
    ("usleephost", "usleephost_v_contract.h"),
    ("waithost", "waithost_v_contract.h"),
    ("policyhostsuite", "policyhost_v_contract.h"),
    ("stringhelpershost", "stringhelpershost_v_contract.h"),
    ("bitmaphost", "bitmaphost_v_contract.h"),
    ("cachehost", "cachehost_v_contract.h"),
    ("kstrtoxhost", "kstrtoxhost_v_contract.h"),
    ("stringtokenshost", "stringtokenshost_v_contract.h"),
    ("formathost", "formathost_v_contract.h"),
    ("loghost", "loghost_v_contract.h"),
)


def build(work, arch, sanitize=True):
    spec = importlib.util.spec_from_file_location("host_generator", TESTS / "compile-v-host.py")
    generator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(generator)
    source = Path(os.environ.get("LINUXKPI_SOURCE_DIR", ROOT / "third_party/linux-i915/linux-6.6.157"))
    compiler = shlex.split(os.environ.get("CC", "clang"))
    contracts = work / "host-contracts"
    contracts.mkdir(exist_ok=True)
    for name, header in GROUPS:
        directory = TESTS / ("hostmodel" if name == "hostmodel" else "hostfixtures/" + name)
        candidates = (directory / header, TESTS / header)
        contract = next((item for item in candidates if item.exists()), None)
        if contract is None:
            raise FileNotFoundError(header)
        shutil.copyfile(contract, contracts / header)
    subprocess.run(["python3", str(ROOT / "kernel/linuxkpi/generate-abi.py"),
                    str(TESTS / "host_percpu_abi.json"), str(contracts / "host_percpu_abi.h")], check=True)
    flags = compiler + ["-std=gnu11", "-fgnu89-inline", "-O1" if sanitize else "-O2", "-g", "-ffreestanding", "-fno-builtin",
        "-fwrapv", "-fno-strict-aliasing", "-ffunction-sections", "-fdata-sections",
        "-Wall", "-Wextra", "-Werror", "-Wno-unused-parameter", "-Wno-unused-function",
        "-Wno-unused-label", "-Wno-deprecated-declarations", "-D_FORTIFY_SOURCE=0",
        *(["-fsanitize=address,undefined", "-fno-omit-frame-pointer"] if sanitize else ["-fno-stack-protector", "-D_GNU_SOURCE"]), "-pthread",
        "-DVINIX_LINUXKPI", "-DVINIX_LINUXKPI_HOST_TEST", "-DVINIX_LINUXKPI_FORMAT_HOST_TEST", "-D__KERNEL__",
        "-include", str(TESTS / "host_types.h"), "-include", "linux/kconfig.h",
        "-include", str(source / "include/linux/compiler_types.h"),
        "-iquote", str(ROOT / "kernel/c"), "-I" + str(contracts), "-I" + str(work / "include"),
        "-I" + str(ROOT / "kernel/linuxkpi/include"), "-I" + str(source / "include"),
        "-I" + str(source / "include/uapi"), "-I" + str(source / "arch/x86/include"),
        "-I" + str(source / "arch/x86/include/uapi"), "-I" + str(source / "drivers/gpu/drm/i915")]
    objects = []
    for name, _ in GROUPS:
        directory = TESTS / ("hostmodel" if name == "hostmodel" else "hostfixtures/" + name)
        generated, object_file = work / (name + ".c"), work / (name + ".o")
        generator.generate(directory, generated, arch, shared_model=name != "hostmodel")
        subprocess.run(flags + ["-D__sputc=vmh_" + name + "_sputc", "-c", str(generated), "-o", str(object_file)], check=True)
        undefined = subprocess.check_output([os.environ.get("NM", "nm"), "-u", str(object_file)], text=True)
        (work / (name + ".undefined.txt")).write_text(undefined)
        if re.search(r"\b_?(?:memdup|v_malloc|new_array\w*)\b", undefined):
            raise RuntimeError("Implicit V allocation in " + name + ": " + undefined)
        objects.append(object_file)
    for name in ("host_model_tls", "formathost_abi", "loghost_abi"):
        object_file = work / (name + ".o")
        subprocess.run(compiler + ["-x", "assembler-with-cpp", "-c", str(TESTS / (name + ".S")), "-o", str(object_file)], check=True)
        objects.append(object_file)
    # Clang response files quote paths directly; no shell evaluates their text.
    (work / "host-fixtures.rsp").write_text("\n".join(json.dumps(str(item)) for item in objects) + "\n")
    print("LinuxKPI: independent native V host fixtures compiled without implicit V allocations", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("work", type=Path)
    parser.add_argument("--arch", choices=("arm64", "amd64"), required=True)
    parser.add_argument("--native", action="store_true", help="Build unsanitized target objects for a native guest; assertions remain active")
    args = parser.parse_args()
    build(args.work.resolve(), args.arch, not args.native)
