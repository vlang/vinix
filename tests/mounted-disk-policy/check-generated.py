#!/usr/bin/env python3
"""Audit production dispatch/token C and sanitize its exact geometry helpers."""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile


def function(source, name):
    match = re.search(r"(?m)^[\w *]+\b" + re.escape(name) + r"\([^;\n]*\) \{", source)
    if not match:
        raise RuntimeError(f"missing production function: {name}")
    depth = 1
    cursor = match.end()
    while depth:
        if source[cursor] == "{":
            depth += 1
        elif source[cursor] == "}":
            depth -= 1
        cursor += 1
    return source[match.start():cursor]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("blob", type=Path)
    parser.add_argument("--arch", choices=("aarch64", "amd64"), required=True)
    args = parser.parse_args()
    source = args.blob.read_text()
    names = [
        "resource__BlockIdentity__valid", "resource__BlockIdentity__overlaps",
        "resource__block_identity", "fs__begin_filesystem_block_mount",
        "fs__MknodDeviceResource__block_identity", "ext2__EXT2Filesystem__block_identity",
        "security__block_policy_index", "security__block_write_allowed_locked",
        "security__user_device_write_allowed", "security__begin_user_device_write",
        "security__end_user_device_write", "security__begin_block_mount",
        "security__finish_block_mount",
    ]
    names += (["virtio_blk__VirtioBlockDevice__block_identity"] if args.arch == "aarch64" else [
        "ahci__AHCIDevice__block_identity", "nvme__NVMENamespace__block_identity",
        "partition__Partition__block_identity", "partition__partition_identity",
    ])
    bodies = {name: function(source, name) for name in names}
    allocator = re.compile(r"\b(?:memdup|malloc|calloc|realloc|v_malloc|memory__malloc|__new_array\w*|array_slice|array_push|string__substr|new_array_from_c_array)\s*\(")
    for name, body in bodies.items():
        if allocator.search(body):
            raise RuntimeError(f"per-call allocation in {name}")
    for name in ("resource__block_identity", "fs__begin_filesystem_block_mount"):
        if bodies[name].count("vinix_stack_alloc(") != 1:
            raise RuntimeError(f"missing bounded caller-stack dispatch in {name}")
    transfer = function(source, "pipe__move_between")
    if not (transfer.index("security__begin_user_device_write(")
            < transfer.index("memory__malloc(") < transfer.index("resource__Resource__read(")):
        raise RuntimeError("transfer authorizes after allocating or consuming input")
    if transfer.count("security__end_user_device_write(block_token)") != 4:
        raise RuntimeError("transfer token is not released on all four exit paths")
    code = """#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
typedef uint64_t u64;
typedef uint32_t u32;
typedef int64_t i64;
typedef struct { bool is_block; u64 disk_id, start, length; } resource__BlockIdentity;
"""
    code += bodies["resource__BlockIdentity__valid"] + "\n"
    code += bodies["resource__BlockIdentity__overlaps"] + "\n"
    extra = ""
    if args.arch == "amd64":
        code += bodies["partition__partition_identity"] + "\n"
        for name in ("ahci__AHCIRegisters", "ahci__AHCIPortRegisters"):
            match = re.search(r"struct " + name + r" \{.*?\n\};", source, re.S)
            if not match:
                raise RuntimeError(f"missing hardware register layout: {name}")
            code += "#pragma pack(push, 1)\n" + match.group() + "\n#pragma pack(pop)\n"
        code += """typedef struct ahci__AHCIPortRegisters ahci__AHCIPortRegisters;
typedef struct { u32 cmd_slots; } ahci__AHCIController;
typedef struct { bool failed; ahci__AHCIPortRegisters *regs; ahci__AHCIController *parent_controller; } ahci__AHCIDevice;
typedef struct { bool ok; u32 value; } __v_option_u32;
"""
        code += function(source, "ahci__AHCIDevice__find_cmd_slot") + "\n"
        initialisation = function(source, "ahci__AHCIController__initialise")
        expression = re.search(r"c->port_cnt = ([^;]+);", initialisation)
        if not expression:
            raise RuntimeError("missing production CAP.NP decode")
        code += "static u32 ports(u32 cap) { struct ahci__AHCIRegisters reg = {.cap = cap}; struct ahci__AHCIRegisters *regs = &reg; return " + expression.group(1) + "; }\n"
        slots = re.search(r"c->cmd_slots = ([^;]+);", initialisation)
        if not slots:
            raise RuntimeError("missing production CAP.NCS decode")
        code += "static u32 command_slots(u32 cap) { struct ahci__AHCIRegisters reg = {.cap = cap}; struct ahci__AHCIRegisters *regs = &reg; return " + slots.group(1) + "; }\n"
        extra = """
    assert(sizeof(struct ahci__AHCIRegisters) == 0x100);
    assert(sizeof(struct ahci__AHCIPortRegisters) == 0x80);
    assert(offsetof(struct ahci__AHCIPortRegisters, sig) == 0x24);
    assert(offsetof(struct ahci__AHCIPortRegisters, ci) == 0x38);
    assert(offsetof(struct ahci__AHCIPortRegisters, vs) == 0x70);
    for (u32 last = 0; last < 32; last++) assert(ports(0xffffffe0u | last) == last + 1);
    for (u32 last = 0; last < 32; last++) assert(command_slots(0xffffe0ffu | (last << 8)) == last + 1);
    for (u32 count = 1; count <= 32; count++) {
        ahci__AHCIController controller = {.cmd_slots = count};
        ahci__AHCIPortRegisters registers = {0};
        ahci__AHCIDevice disk = {.regs = &registers, .parent_controller = &controller};
        u32 full = (u32)((UINT64_C(1) << count) - 1);
        registers.ci = full & ~(UINT32_C(1) << (count - 1));
        __v_option_u32 free = ahci__AHCIDevice__find_cmd_slot(&disk);
        assert(free.ok && free.value == count - 1);
        registers.ci = full;
        assert(!ahci__AHCIDevice__find_cmd_slot(&disk).ok);
        disk.failed = true;
        registers.ci = 0;
        assert(!ahci__AHCIDevice__find_cmd_slot(&disk).ok);
    }
    for (u64 offset = 0; offset <= 4096; offset += 256) {
        resource__BlockIdentity parent = {true, 1, 8192, 4096};
        resource__BlockIdentity part = partition__partition_identity(parent, offset, 256);
        assert(resource__BlockIdentity__valid(part) == (offset <= 3840));
        if (offset <= 3840) assert(part.disk_id == 1 && part.start == 8192 + offset && part.length == 256);
    }
    resource__BlockIdentity top = {true, 1, UINT64_MAX - 4096, 4096};
    assert(resource__BlockIdentity__valid(partition__partition_identity(top, 2048, 2048)));
    assert(!resource__BlockIdentity__valid(partition__partition_identity(top, UINT64_MAX, 1)));
"""
    code += """int main(void) {
    resource__BlockIdentity whole = {true, 1, 0, 4096};
    assert(resource__BlockIdentity__valid(whole));
    assert(!resource__BlockIdentity__valid((resource__BlockIdentity){true, 1, UINT64_MAX - 15, 32}));
    assert(!resource__BlockIdentity__valid((resource__BlockIdentity){true, 0, 0, 4096}));
    for (u64 start = 0; start < 8192; start += 256) {
        resource__BlockIdentity part = {true, 1, start, 256};
        assert(resource__BlockIdentity__overlaps(whole, part) == (start < 4096));
        assert(resource__BlockIdentity__overlaps(part, whole) == (start < 4096));
        part.disk_id = 2;
        assert(!resource__BlockIdentity__overlaps(whole, part));
    }
""" + extra + "\nputs(\"PASS: exact production geometry and register helpers under ASan/UBSan\"); return 0; }\n"
    with tempfile.TemporaryDirectory(prefix="vinix-block-generated-") as directory:
        work = Path(directory)
        (work / "test.c").write_text(code)
        subprocess.run(["clang", "-O2", "-Wall", "-Wextra", "-Werror", "-fsanitize=address,undefined",
                        str(work / "test.c"), "-o", str(work / "test")], check=True)
        subprocess.run([str(work / "test")], check=True)
    print(f"PASS {args.arch}: {len(bodies)} production dispatch/token helpers have no per-call allocation")


if __name__ == "__main__":
    main()
