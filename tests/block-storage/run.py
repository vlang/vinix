#!/usr/bin/env python3
"""Host fault tests for the production NVMe completion and DMA ownership paths.

Extract unchanged declarations/functions from the V driver, replacing only its
kernel dependencies with a deterministic MMIO/allocator model. This exercises
real completion consumption, flush commands, reset containment and DMA frees.
"""
from pathlib import Path
import os
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def function(source: str, name: str) -> str:
    match = re.search(r"^(?:pub )?fn [^\n]*\b" + re.escape(name) + r"\([^\n]*\{", source, re.M)
    if not match:
        raise RuntimeError(f"Missing production function {name}")
    depth = 1
    cursor = match.end()
    while depth:
        depth += (source[cursor] == "{") - (source[cursor] == "}")
        cursor += 1
    return source[match.start():cursor]


def write(base: Path, relative: str, contents: str) -> None:
    target = base / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(contents)


def main() -> None:
    source = (ROOT / "kernel/dev/nvme/nvme.v").read_text()
    declarations = source[:source.index("__global (")]
    declarations = re.sub(r"^import .*\n", "", declarations, flags=re.M)
    imports = "\n".join("import " + name for name in [
        "memory", "lib", "pci", "bitmap", "stat", "klock", "event.eventstruct",
        "errno", "katomic", "x86.hpet as hpet_clock",
    ])
    functions = "\n\n".join(function(source, name) for name in [
        "send_cmd", "send_cmd_and_wait", "fail_controller", "ready_timeout_ns",
        "rw_lba", "transfer", "sync",
    ])
    with tempfile.TemporaryDirectory(prefix="vinix-storage-host-") as directory:
        work = Path(directory)
        write(work, "v.mod", "Module { name: 'vinix_storage_host_tests' }\n")
        write(work, "nvme/nvme.v", declarations.replace("module nvme", "module nvme\n" + imports)
              + "\nconst page_size = u64(4096)\nconst higher_half = u64(0)\n"
              + "#include <stdio.h>\n#define kprintf printf\nfn C.kprintf(&char, ...voidptr) int\n"
              + functions)
        write(work, "pci/pci.v", "module pci\npub struct PCIBar {}\n")
        write(work, "stat/stat.v", """module stat
pub struct Stat {
pub mut:
 size i64
 blksize i64
 blocks i64
}
""")
        write(work, "event/eventstruct/event.v", "module eventstruct\npub struct Event {}\n")
        write(work, "klock/klock.v", """module klock
pub struct Lock {}
pub fn (mut lock Lock) acquire() {}
pub fn (mut lock Lock) release() {}
pub fn spin_hint() {}
""")
        write(work, "katomic/katomic.v", "module katomic\npub fn sync() {}\n")
        write(work, "lib/lib.v", """module lib
pub fn div_roundup[T](a T, b T) T { return (a + b - 1) / b }
""")
        write(work, "errno/errno.v", """module errno
pub const eio = 5
pub const enomem = 12
pub fn set(_ int) {}
""")
        write(work, "memory/memory.v", """@[has_globals]
module memory
__global live_pages = u64(0)
pub fn pmm_alloc_nozero_fallible(pages u64) voidptr {
 live_pages += pages
 return unsafe { malloc(int(pages * 4096)) }
}
pub fn pmm_free(pointer voidptr, pages u64) {
 live_pages -= pages
 unsafe { free(pointer) }
}
pub fn allocated_pages() u64 { return live_pages }
""")
        write(work, "bitmap/bitmap.v", """module bitmap
pub struct GenericBitmap {
mut:
 slots []bool
}
pub fn (mut b GenericBitmap) initialise(count u64) { b.slots = []bool{len: int(count)} }
pub fn (b GenericBitmap) alloc() ?u64 {
 for i, busy in b.slots {
  if !busy { unsafe { b.slots[i] = true }; return u64(i) }
 }
 return none
}
pub fn (b GenericBitmap) free_entry(index u64) { unsafe { b.slots[index] = false } }
""")
        write(work, "x86/hpet/hpet.v", """@[has_globals]
module hpet
__global tick_hook = fn () {}
__global ticks = u64(0)
pub fn nanoseconds() u64 {
 ticks += 1_000_000_000
 tick_hook()
 return ticks
}
pub fn set_hook(hook fn ()) { tick_hook = hook; ticks = 0 }
""")
        write(work, "nvme/completion_test.v", (ROOT / "tests/block-storage/completion_test.v").read_text())
        virtio = (ROOT / "kernel/aarch64/virtio_blk/virtio_blk.v").read_text()
        declarations = virtio[:virtio.index("__global (")]
        declarations = re.sub(r"^import .*\n", "", declarations, flags=re.M)
        imports = "\n".join("import " + name for name in [
            "aarch64.cpu", "aarch64.timer", "aarch64.uart", "errno", "klock",
            "event.eventstruct", "stat",
        ])
        functions = "\n\n".join(function(virtio, name) for name in [
            "mmio_r32", "mmio_w32", "write_descriptor", "collect_one", "sync",
        ])
        write(work, "virtio_blk/virtio_blk.v", declarations.replace("module virtio_blk", "module virtio_blk\n" + imports)
              + "\nfn C.memcpy(voidptr, voidptr, usize) voidptr\n" + functions)
        write(work, "aarch64/cpu/cpu.v", "module cpu\npub fn dmb_ish() {}\n")
        write(work, "aarch64/uart/uart.v", "module uart\npub fn puts(_ &char) {}\n")
        write(work, "aarch64/timer/timer.v", """module timer
import x86.hpet as hpet_clock
pub fn get_ns() u64 { return hpet_clock.nanoseconds() }
""")
        write(work, "virtio_blk/flush_test.v", (ROOT / "tests/block-storage/flush_test.v").read_text())
        ahci = (ROOT / "kernel/dev/ahci/ahci.v").read_text()
        declarations = ahci[:ahci.index("__global (")]
        declarations = re.sub(r"^import .*\n", "", declarations, flags=re.M)
        imports = "\n".join("import " + name for name in [
            "pci", "errno", "klock", "event.eventstruct", "stat", "katomic",
            "x86.hpet as hpet_clock",
        ])
        functions = "\n\n".join(function(ahci, name) for name in [
            "find_cmd_slot", "send_cmd", "sync",
        ])
        write(work, "ahci/ahci.v", declarations.replace("module ahci", "module ahci\n" + imports)
              + "\nconst higher_half = u64(0)\n" + functions)
        write(work, "ahci/flush_test.v", (ROOT / "tests/block-storage/ahci_test.v").read_text())
        subprocess.run([os.environ.get("V", "v"), "-enable-globals", "-gc", "none",
                        "test", "nvme", "virtio_blk", "ahci"], cwd=work, check=True)


if __name__ == "__main__":
    main()
