#!/usr/bin/env python3
"""Check Vinix's G13 firmware contract against local m1n1/Asahi sources.

This is deliberately a source-level gate. The Apple GPU ABI is not published,
and several bring-up bugs that previously needed an M1 reboot were already
spelled out in m1n1's reverse-engineered driver. Keep those discoveries tied to
their source and fail on drift before constructing another boot image.
"""

from __future__ import annotations

import argparse
import re
import subprocess
from pathlib import Path

import generate_g13_initdata_layout as initdata_layout


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
DEFAULT_M1N1 = initdata_layout.DEFAULT_M1N1


class ContractError(Exception):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ContractError(message)


def read(path: Path) -> str:
    if not path.is_file():
        raise ContractError(f"missing reference source: {path}")
    return path.read_text()


def section(source: str, start: str, end: str, label: str) -> str:
    begin = source.find(start)
    if begin < 0:
        raise ContractError(f"{label}: missing {start!r}")
    finish = source.find(end, begin + len(start))
    if finish < 0:
        raise ContractError(f"{label}: missing terminator {end!r}")
    return source[begin:finish]


def require_order(source: str, tokens: list[str], label: str) -> None:
    cursor = 0
    for token in tokens:
        found = source.find(token, cursor)
        if found < 0:
            raise ContractError(f"{label}: missing or out-of-order {token!r}")
        cursor = found + len(token)


def integer_constant(source: str, name: str, label: str) -> int:
    match = re.search(
        rf"\b{re.escape(name)}\b[^=]*=\s*(?:u64\()?\s*(0x[0-9a-fA-F_]+)",
        source,
    )
    if not match:
        raise ContractError(f"{label}: cannot find numeric constant {name}")
    return int(match.group(1).replace("_", ""), 16)


def git_revision(path: Path) -> str:
    try:
        return subprocess.run(
            ["git", "-C", str(path), "rev-parse", "--short=12", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def check_m1n1(m1n1: Path) -> list[str]:
    results: list[str] = []
    raw_rs = m1n1 / "rust/src/gpu/raw.rs"
    generated = initdata_layout.generate(raw_rs)
    checked_in = read(REPO_ROOT / "kernel/gpu/agx/fw/g13_initdata_layout.v")
    require(generated == checked_in, "Vinix G13 InitData layout is stale against m1n1")
    results.append("InitData 12.3/13.5 generated layouts")

    fw_channels = read(m1n1 / "proxyclient/m1n1/fw/agx/channels.py")
    normal_state = section(
        fw_channels, "class ChannelStateFields", "class FWControlStateFields", "m1n1 channels"
    )
    require_order(
        normal_state,
        ["_SIZE = 0x30", "READ_PTR = 0x00", "WRITE_PTR = 0x20"],
        "m1n1 normal channel state",
    )
    fwctl_state = section(
        fw_channels, "class FWControlStateFields", "class Channel(", "m1n1 channels"
    )
    require_order(
        fwctl_state,
        ["_SIZE = 0x20", "READ_PTR = 0x00", "WRITE_PTR = 0x10"],
        "m1n1 firmware-control channel state",
    )
    require("[(FWCtlMsg, 0x14, 0x100)]" in fw_channels, "m1n1 FwCtl ring ABI changed")
    results.append("channel state offsets and FwCtl ring geometry")

    runtime_channels = read(m1n1 / "proxyclient/m1n1/agx/channels.py")
    send_inval = section(
        runtime_channels, "    def send_inval(self, ctx, addr=0):", "class GPUEventChannel", "m1n1 FwCtl"
    )
    require_order(
        send_inval,
        [
            "msg.addr = addr",
            "msg.unk_8 = 0",
            "msg.context_id = ctx",
            "msg.unk_10 = 1",
            "msg.unk_12 = 2",
            "self.send_message(msg)",
        ],
        "m1n1 FwCtl invalidate",
    )
    vinix_channels = read(REPO_ROOT / "kernel/gpu/agx/fw/channels.v")
    vinix_inval = section(
        vinix_channels,
        "pub fn make_g13_fwctl_invalidate",
        "// Firmware log channel message",
        "Vinix FwCtl",
    )
    require_order(
        vinix_inval,
        ["addr: addr", "slot: slot", "unk_10: 1", "unk_12: 2"],
        "Vinix FwCtl invalidate",
    )
    results.append("FwCtl invalidate opcode and handoff-slot message")

    m1n1_initdata = read(m1n1 / "proxyclient/m1n1/agx/initdata.py")
    require(
        'initdata.regionA = agx.kshared.new_buf(0x4000, "InitData_RegionA")'
        in m1n1_initdata,
        "m1n1 RegionA allocation contract changed",
    )
    vinix_gpu = read(REPO_ROOT / "kernel/gpu/agx/gpu/gpu.v")
    require(
        "graph.unknown_buffer = mgr.alloc_g13_shared_buffer(0x4000)" in vinix_gpu,
        "Vinix RegionA is no longer firmware-writable shared memory",
    )
    results.append("firmware-writable InitData RegionA")

    m1n1_initdata_rs = read(m1n1 / "rust/src/gpu/initdata.rs")
    vinix_alloc = read(REPO_ROOT / "kernel/gpu/agx/alloc/alloc.v")
    reference_timestamp = integer_constant(
        m1n1_initdata_rs, "IOVA_KERN_TIMESTAMP_RANGE_START", "m1n1 timestamp aperture"
    )
    vinix_timestamp = integer_constant(
        vinix_alloc, "g13_timestamp_start", "Vinix timestamp aperture"
    )
    require(
        reference_timestamp == vinix_timestamp,
        f"timestamp aperture mismatch: m1n1={reference_timestamp:#x}, Vinix={vinix_timestamp:#x}",
    )
    require(
        "mmu.uat_unknown_page, alloc.g13_timestamp_start" in vinix_gpu,
        "Vinix no longer publishes the timestamp aperture to HwDataB",
    )
    results.append("timestamp aperture address and HwDataB publication")

    m1n1_objects = read(m1n1 / "proxyclient/m1n1/agx/object.py")
    allocator_start = m1n1_objects.find("class GPUAllocator")
    require(allocator_start >= 0, "m1n1 allocator: missing GPUAllocator")
    allocator = m1n1_objects[allocator_start:]
    free = section(allocator, "    def free(self, obj):", "        if self.verbose:", "m1n1 free")
    require_order(
        free,
        [
            'flags2["AttrIndex"] = MemoryAttr.Shared',
            "self.agx.uat.iomap_at",
            "self.agx.uat.flush_dirty()",
            "prepare_cacheflush",
            "send_inval",
            "wait_cacheflush",
            "VALID=0",
            "self.agx.uat.flush_dirty()",
            "complete_cacheflush",
        ],
        "m1n1 cache-safe unmap",
    )
    vinix_shared = section(
        vinix_gpu,
        "fn (mut mgr GpuManager) invalidate_g13_shared_buffer",
        "fn (mut mgr GpuManager) invalidate_g13_driver_buffer",
        "Vinix shared-buffer teardown",
    )
    require_order(
        vinix_shared,
        [
            "reprotect_kernel",
            "flush_g13_uat_range",
            "cache_flush_pending = false",
            "unmap_shared_buffer",
            "flush_g13_uat_range",
        ],
        "Vinix shared-buffer teardown",
    )
    vinix_driver = section(
        vinix_gpu,
        "fn (mut mgr GpuManager) invalidate_g13_driver_buffer",
        "fn (mut mgr GpuManager) release_shared_buffer_backing",
        "Vinix driver-buffer teardown",
    )
    require_order(
        vinix_driver,
        [
            "reprotect_driver_buffer_uncached",
            "flush_g13_uat_range",
            "complete_driver_buffer_cache_flush",
            "unmap_driver_buffer",
            "flush_g13_uat_range",
        ],
        "Vinix driver-buffer teardown",
    )
    results.append("retry-safe reprotect/invalidate/unmap/invalidate teardown")

    vinix_channel = read(REPO_ROOT / "kernel/gpu/agx/channel/channel.v")
    enqueue = section(
        vinix_channel,
        "pub fn (mut ch TxChannel) enqueue_with_token",
        "pub fn (ch &TxChannel) read_pointer",
        "Vinix TX channel",
    )
    require_order(
        enqueue,
        ["C.memcpy", "katomic.sync()", "katomic.store(mut write_ptr"],
        "Vinix TX channel publication",
    )
    results.append("TX ring entry barrier before write-pointer publication")
    return results


def check_asahi(asahi_linux: Path) -> list[str]:
    mmu = read(asahi_linux / "drivers/gpu/drm/asahi/mmu.rs")
    drop = section(mmu, "impl Drop for KernelMapping", "/// Shared UAT global", "Asahi MMU")
    require_order(
        drop,
        [
            "is_cached_noncoherent",
            "remap_uncached_and_flush",
            "unmap_pages",
            "tlbi_range",
        ],
        "Asahi cache-safe unmap",
    )
    channel = read(asahi_linux / "drivers/gpu/drm/asahi/channel.rs")
    put = section(channel, "    pub(crate) fn put", "    /// Wait for", "Asahi TX channel")
    require_order(
        put,
        ["self.ring.ring[self.wptr as usize] = *msg", "mem::sync()", "T::set_wptr"],
        "Asahi TX channel publication",
    )
    return [
        "Asahi KernelMapping cache-safe teardown order",
        "Asahi TX ring barrier before write-pointer publication",
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--m1n1", type=Path, default=DEFAULT_M1N1)
    parser.add_argument(
        "--asahi-linux",
        type=Path,
        help="optional Asahi Linux checkout containing drivers/gpu/drm/asahi",
    )
    args = parser.parse_args()

    try:
        results = check_m1n1(args.m1n1)
        print(f"m1n1 {git_revision(args.m1n1)}:")
        for result in results:
            print(f"  ok  {result}")
        if args.asahi_linux is not None:
            asahi_results = check_asahi(args.asahi_linux)
            print(f"Asahi Linux {git_revision(args.asahi_linux)}:")
            for result in asahi_results:
                print(f"  ok  {result}")
        else:
            print("Asahi Linux: skipped (pass --asahi-linux to check a checkout)")
    except ContractError as error:
        raise SystemExit(f"G13 reference contract failed: {error}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
