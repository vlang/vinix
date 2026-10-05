#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Test production VMX exports, compile privileged ports and compare entry bytes."""
import argparse
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def symbol_bytes(path, name):
    """Read an ELF64 function without relying on a platform-specific nm."""
    data = path.read_bytes()
    header = struct.unpack_from("<16sHHIQQQIHHHHHH", data)
    if header[0][:6] != b"\x7fELF\x02\x01":
        raise RuntimeError(f"not little-endian ELF64: {path}")
    sections = [struct.unpack_from("<IIQQQQIIQQ", data, header[6] + i * header[11])
                for i in range(header[12])]
    for section in sections:
        if section[1] != 2:  # SHT_SYMTAB
            continue
        strings = sections[section[6]]
        names = data[strings[4]:strings[4] + strings[5]]
        for offset in range(section[4], section[4] + section[5], section[9]):
            symbol = struct.unpack_from("<IBBHQQ", data, offset)
            if names[symbol[0]:].split(b"\0", 1)[0].decode() == name:
                content = sections[symbol[3]]
                start = content[4] + symbol[4] - content[3]
                return data[start:start + symbol[5]]
    raise RuntimeError(f"missing {name} in {path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--original", type=Path,
                        help="optional pre-port vmx.c for exact entry byte comparison")
    args = parser.parse_args()
    compiler = os.environ.get("CC", "clang")
    v = subprocess.check_output([
        "sh", "-c", '. "$1/build-support/find-v.sh"; printf "%s" "$V"',
        "find-v", str(ROOT)], text=True)
    environment = {**os.environ, "V_C_ERROR_BUG_REPORT_DISABLED": "1"}
    include = ["-iquote", str(ROOT / "kernel/c")]
    common = [compiler, "-std=gnu11", "-O2", "-g", "-Wall", "-Wextra", "-Werror"]
    sanitizer = ["-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
    generated_flags = ["-Wno-unused-function", "-ffreestanding", "-fno-builtin",
                       "-fno-strict-aliasing", "-DVINIX_V_RUNTIME"]
    with tempfile.TemporaryDirectory(prefix="vinix-vmx-", dir="/tmp") as directory:
        work = Path(directory)

        def generate(name, files, arch, model=False):
            source = work / name
            source.mkdir()
            (source / "v.mod").write_text("Module { name: 'vinix_vmx_tests' }\n")
            # Rename architecture suffixes so the host can exercise adapters.
            for i, filename in enumerate(files):
                shutil.copyfile(ROOT / "kernel/lib" / filename, source / f"source{i}.v")
            output = work / f"{name}.c"
            command = [v, "-shared", "-no-builtin", "-os", "vinix", "-arch", arch,
                       "-target-libc-headers", "-nofloat", "-gc", "none", "-manualfree"]
            if model:
                command += ["-d", "vmx_test"]
            subprocess.run(command + ["-o", str(output), str(source)], check=True,
                           env=environment)
            return output

        def no_allocators(object_file):
            imports = subprocess.check_output(["nm", "-u", str(object_file)], text=True)
            if re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b", imports):
                raise RuntimeError("VMX unexpectedly imports an allocator:\n" + imports)

        fixture = ROOT / "tests/hypervisor/vmx_test.c"
        for name, files, model in [
            ("control", ["vmx.v", "vmx_controls_amd64.v"], True),
            ("unsupported", ["vmx.v", "vmx_arm64.v"], False),
        ]:
            source = generate(name, files, "amd64" if model else "arm64", model)
            obj = work / f"{name}.o"
            subprocess.run(common + sanitizer + include + generated_flags +
                           ["-c", str(source), "-o", str(obj)], check=True)
            no_allocators(obj)
            binary = work / name / "test"
            define = ["-DVMX_TEST_PORTS"] if model else []
            subprocess.run(common + sanitizer + include + define +
                           [str(fixture), str(obj), "-o", str(binary)], check=True)
            subprocess.run([str(binary)], check=True)

        source = generate("privileged", ["vmx.v", "vmx_controls_amd64.v",
                                        "vmx_state_amd64.v"], "amd64")
        text = source.read_text()
        # These operand sizes are part of compiler memory ordering, even when
        # the CPU instruction itself always reads/writes a fixed-size area.
        text += '\n_Static_assert(sizeof(lib__VmxFxState) == 512, "FXSAVE area");\n'
        text += '_Static_assert(sizeof(struct vinix_vmx_descriptor) == 10, "GDTR/IDTR area");\n'
        source.write_text(text)
        cross = [compiler, "-target", "x86_64-unknown-none-elf", "-std=gnu11", "-O2",
                 "-Wall", "-Wextra", "-Werror", "-mno-red-zone", "-ffreestanding",
                 "-fno-builtin", "-fno-strict-aliasing", "-I", str(ROOT / "kernel/c")]
        obj = work / "privileged.o"
        subprocess.run(cross + generated_flags + ["-c", str(source), "-o", str(obj)],
                       check=True)
        no_allocators(obj)
        objdump = os.environ.get("LLVM_OBJDUMP") or shutil.which("llvm-objdump")
        if not objdump:
            objdump = "/opt/homebrew/opt/llvm/bin/llvm-objdump"
        assembly = subprocess.check_output([objdump, "-d", "--no-show-raw-insn", str(obj)],
                                           text=True)
        for operation, instruction in [("on", "vmxon"), ("off", "vmxoff"),
                                       ("clear", "vmclear"), ("load", "vmptrld"),
                                       ("write", "vmwriteq"), ("read", "vmreadq")]:
            function = assembly.split(f"<vinix_vmx_{operation}>:", 1)[1].split("\n\n", 1)[0]
            instructions = [line.split("\t", 1)[1] for line in function.splitlines() if "\t" in line]
            position = next(i for i, line in enumerate(instructions) if line.startswith(instruction))
            if not instructions[position + 1].startswith("setbe"):
                raise RuntimeError(f"{instruction} must immediately capture CF/ZF")
        if not re.search(r'"vmwrite %\[value\], %\[field\]', text):
            raise RuntimeError("VMWRITE operand order changed")
        if not re.search(r'"vmread %\[field\], %\[result\]', text):
            raise RuntimeError("VMREAD operand order changed")
        # Inspect every production control block, not just the host adapters.
        blocks = re.findall(r"__asm__ volatile \((.*?)\);", text, re.S)
        controls = [block for block in blocks if re.search(r'"vm(?:xon|xoff|clear|ptrld|write|read)', block)]
        if len(controls) != 6 or any('"cc"' not in b or '"memory"' not in b for b in controls):
            raise RuntimeError("VMX flags/memory clobbers changed")
        print("VMX INSTRUCTION PASS: optimized x86 ports, CF/ZF capture, operands and barriers")

        entry = work / "entry.o"
        subprocess.run(cross + ["-c", str(ROOT / "kernel/asm/x86_64/vmx.S"), "-o", str(entry)],
                       check=True)
        if args.original:
            original = work / "original.o"
            subprocess.run(cross + ["-c", str(args.original.resolve()), "-o", str(original)],
                           check=True)
            old = symbol_bytes(original, "vinix_vmx_enter")
            new = symbol_bytes(entry, "vinix_vmx_enter")
            if not old or old != new:
                raise RuntimeError("VM entry bytes changed")
            print(f"VMX ENTRY PASS: all {len(new)} instruction bytes match original C assembly")
        print("PASS VMX production V C ABI, ASan/UBSan, x86 assembly and no allocator imports")


if __name__ == "__main__":
    main()
