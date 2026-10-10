#!/usr/bin/env python3
"""Test production x86 tag ownership and direct-map splitting with host adapters."""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def function(source, name):
    start = source.index("fn " + name)
    start = source.rfind("\n", 0, start) + 1
    end = source.index("{", start) + 1
    depth = 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end] + "\n"


with tempfile.TemporaryDirectory(prefix="vinix-address-space-") as work:
    root = Path(work)
    (root / "v.mod").write_text("Module { name: 'address_space_test' }\n")
    modules = {
        "limine": """module limine
pub const limine_memmap_usable = u64(0)
pub struct LimineMemmapEntry { pub mut: base u64 length u64 @type u64 }
pub struct LimineMemmapResponse { pub mut: entry_count u64 entries &&LimineMemmapEntry = unsafe { nil } }
pub struct LimineMemmapRequest { pub mut: response &LimineMemmapResponse = unsafe { nil } }
""",
        "katomic": """module katomic
pub fn load[T](p &T) T { return *p }
pub fn store[T](mut p T, value T) { unsafe { C.memcpy(voidptr(p), &value, sizeof(T)) } }
pub fn dec[T](mut p T) bool { unsafe { *p -= 1 }; return *p != 0 }
""",
        "klock": """module klock
pub struct Lock { pub mut: held bool }
pub fn (mut l Lock) acquire() { assert !l.held; l.held = true }
pub fn (mut l Lock) release() { assert l.held; l.held = false }
""",
        "x86/cpu": """@[has_globals]
module cpu
__global (pub feature_bits u8 = 3 pub hardware_root u64 pub control u64)
pub fn cpuid(leaf u32, _ u32) (bool, u32, u32, u32, u32) {
 return true, 0, if feature_bits & 2 != 0 && leaf == 7 { u32(1) << 10 } else { u32(0) },
 if feature_bits & 1 != 0 && leaf == 1 { u32(1) << 17 } else { u32(0) }, 0
}
pub fn read_cr3() u64 { return hardware_root }
pub fn write_cr3(value u64) { hardware_root = value }
pub fn read_cr4() u64 { return control }
pub fn write_cr4(value u64) { control = value }
pub fn invlpg(_ u64) {}
""",
    }
    for name, content in modules.items():
        path = root / name
        path.mkdir(parents=True)
        (path / (path.name + ".v")).write_text(content)
    source = (ROOT / "kernel/memory/pcid_amd64.v").read_text()
    main = """@[has_globals]
module main
import katomic
import klock
import x86.cpu
import limine
#include <stdlib.h>
fn C.posix_memalign(&voidptr, usize, usize) int
fn C.__builtin_alloca(usize) voidptr
const pcid_enable_bit = u64(1) << 17
const cr3_no_flush = u64(1) << 63
const full_tlb_request = ~u64(0)
const pte_present = u64(1)
const pte_writable = u64(2)
const pte_user = u64(4)
const pte_noexec = u64(1) << 63
const pte_file_tracked = u64(1) << 9
const pte_file_dirty = u64(1) << 10
const page_accessed = u64(1) << 5
const page_dirty = u64(1) << 6
const pte_flags_mask = ~(u64(0xfff) | pte_noexec)
const amd64_large_page = u64(1) << 7
const large_pat = u64(1) << 12
const direct_large_size = u64(1) << 21
const page_size = u64(4096)
const higher_half = u64(0)
struct Pagemap { mut: top_level &u64 = unsafe { nil } tlb_tag u16 l klock.Lock }
__global (pcid_available bool = true pcid_lock klock.Lock pcid_used [64]u64
 tlb_shootdown fn (u64, u64, bool) = unsafe { nil } flush_kind u64 flush_tag u16 shootdowns int
 kernel_pagemap Pagemap direct_large_entries u64 la57 bool fail_pages bool live_pages int reserved_pages int vmm_initialised bool
 direct_mtrrs [256]DirectMTRR direct_mtrr_count int direct_cache_valid bool direct_default_wb bool memmap_req limine.LimineMemmapRequest)
fn full_fence() {}
fn invpcid(kind u64, tag u16) { flush_kind = kind; flush_tag = tag }
fn tlb_test_report(line string) { println(line) }
fn shootdown(root u64, _ u64, _ bool) {
 tag := root & 0xfff
 if tag != 0 { assert pcid_used[tag / 64] & (u64(1) << (tag % 64)) != 0 }
 shootdowns++
}
struct DirectMTRR { base u64 top u64 kind u8 }
fn user_address_limit() u64 { return 1 }
fn pmm_alloc_fallible(_ u64) &u64 {
 if fail_pages { return unsafe { nil } }
 mut ptr := unsafe { nil }
 assert C.posix_memalign(&ptr, 4096, 4096) == 0
 unsafe { C.memset(ptr, 0, 4096) }
 live_pages++
 return ptr
}
fn pmm_free(ptr voidptr, _ u64) { unsafe { free(ptr) }; live_pages--; assert live_pages >= 0 }
fn reserve_table_page(mut _ Pagemap) bool { reserved_pages++; return true }
fn release_table_page(mut _ Pagemap) { reserved_pages--; assert reserved_pages >= 0 }
fn (p &Pagemap) invalidate(_ u64) { shootdowns++ }
fn (mut p Pagemap) account_resident(_ u64, _ bool, _ bool) {}
fn (mut p Pagemap) protect_file_page_unlocked(_ u64) {}
"""
    for name in ("enable_pcid(", "take_pcid(", "(pagemap &Pagemap) tagged_root(",
                 "switch_cr3(", "invalidate_local_tlb(", "(pagemap &Pagemap) prepare_tlb_teardown(",
                 "(pagemap &Pagemap) invalidate_context(", "(mut pagemap Pagemap) release_tlb_tag(",
                 "pcid_selftest("):
        main += function(source, name)
    cache = (ROOT / "kernel/memory/direct_cache_amd64.v").read_text()
    for name in ("record_direct_mtrr(", "direct_cache_uniform(", "direct_large_eligible("):
        main += function(cache, name)
    large = (ROOT / "kernel/memory/largepage_amd64.v").read_text()
    for name in ("small_leaf_flags(", "large_leaf_phys(", "amd64_leaf_level(",
                 "(pagemap &Pagemap) kernel_pde(", "(pagemap &Pagemap) kernel_block_matches(",
                 "(pagemap &Pagemap) split_kernel_leaf(", "(pagemap &Pagemap) kernel_leaf_phys(", "map_direct_span("):
        main += function(large, name)
    mapper = (ROOT / "kernel/memory/virtual_amd64.v").read_text()
    for name in ("get_next_level(", "(pagemap &Pagemap) virt2pte(", "(pagemap &Pagemap) virt2phys(",
                 "(mut pagemap Pagemap) map_page(", "(mut pagemap Pagemap) map_page_unlocked(",
                 "(mut pagemap Pagemap) flag_page(", "table_empty_after_clear(",
                 "(mut pagemap Pagemap) unmap_page(", "(mut pagemap Pagemap) unmap_page_unlocked("):
        main += function(mapper, name)
    main += """
fn main() {
 for features in 0 .. 3 {
 cpu.feature_bits = u8(features); pcid_available = true; cpu.control = pcid_enable_bit
 enable_pcid()
 assert !pcid_available && cpu.control & pcid_enable_bit == 0 && take_pcid() == 0
 }
 cpu.feature_bits = 3; pcid_available = true; enable_pcid()
 assert cpu.control & pcid_enable_bit != 0 && flush_kind == 2
 tlb_shootdown = shootdown
 for tag := u16(1); tag < 4096; tag++ { assert take_pcid() == tag }
 assert take_pcid() == 0 && pcid_used[0] & 1 == 0
 mut map_ := Pagemap{top_level: unsafe { &u64(0x12345000) }, tlb_tag: 127}
 switch_cr3(map_.tagged_root()); assert cpu.hardware_root == (u64(0x1234507f) | cr3_no_flush)
 cpu.hardware_root = 0x88888000 // CPU switched away, so the old tag is inactive
 invalidate_local_tlb(map_.tagged_root(), 0x400000, false)
 assert flush_kind == 1 && flush_tag == 127
 map_.prepare_tlb_teardown(); assert shootdowns == 1 && pcid_used[1] & (u64(1) << 63) != 0
 map_.release_tlb_tag(); assert map_.tlb_tag == 0 && shootdowns == 2
 assert take_pcid() == 127 && take_pcid() == 0
 for tag := u16(1); tag < 4096; tag++ { map_.tlb_tag = tag; map_.release_tlb_tag() }
 for word in pcid_used { assert word == 0 }
 pcid_selftest()
 for word in pcid_used { assert word == 0 }
 switch_cr3(0x100000); assert cpu.hardware_root == 0x100000 // fallback never suppresses flushing
 assert small_leaf_flags(pte_present | amd64_large_page | large_pat) == pte_present | amd64_large_page
 assert !direct_cache_uniform(direct_large_size) // unverified CPU must use small pages
 direct_cache_valid = true; direct_default_wb = true
 assert !direct_cache_uniform(0) && direct_cache_uniform(direct_large_size)
 physical_mask := u64(0xffffffff000)
 assert record_direct_mtrr(0x200000 | 6, (physical_mask & ~u64(0xfffff)) | 0x800, physical_mask)
 assert !direct_cache_uniform(direct_large_size) // an MTRR boundary bisects the candidate
 direct_mtrr_count = 0
 assert record_direct_mtrr(0x200000 | 0, (physical_mask & ~u64(0x1fffff)) | 0x800, physical_mask)
 assert !direct_cache_uniform(direct_large_size) // uniformly UC is deliberately not promoted
 direct_mtrr_count = 0; direct_default_wb = false
 assert record_direct_mtrr(0x200000 | 6, (physical_mask & ~u64(0x1fffff)) | 0x800, physical_mask)
 assert direct_cache_uniform(direct_large_size) && !direct_cache_uniform(2 * direct_large_size)
 direct_mtrr_count = 0
 assert !record_direct_mtrr(0x201000 | 6, (physical_mask & ~u64(0x1fffff)) | 0x800, physical_mask)
 assert !record_direct_mtrr(6, (physical_mask & ~u64(0x101fff)) | 0x800, physical_mask)
 direct_default_wb = true
 assert !direct_large_eligible(direct_large_size) // missing firmware map
 mut ram := limine.LimineMemmapEntry{base: direct_large_size, length: direct_large_size, @type: 1}
 entries := [unsafe { &ram }]!
 mut firmware := limine.LimineMemmapResponse{entry_count: 1, entries: unsafe { &entries[0] }}
 memmap_req.response = unsafe { &firmware }
 assert !direct_large_eligible(direct_large_size) // reserved/MMIO
 ram.@type = 0; ram.base++
 assert !direct_large_eligible(direct_large_size) // entry starts inside candidate
 ram.base--; ram.length--
 assert !direct_large_eligible(direct_large_size) // entry ends inside candidate
 ram.length++
 assert direct_large_eligible(direct_large_size)
 kernel_pagemap.top_level = pmm_alloc_fallible(1)
 map_direct_span(direct_large_size, 2 * direct_large_size)
 assert direct_large_entries == 1 && live_pages == 3 && reserved_pages == 2
 entry := kernel_pagemap.kernel_pde(direct_large_size, false) or { panic('PDE') }
 original := unsafe { *entry }
 assert kernel_pagemap.virt2phys(direct_large_size + 4096 + 19) or { 0 } == direct_large_size + 4096
 kernel_pagemap.map_page(direct_large_size + 4096, direct_large_size + 4096,
 pte_present | pte_writable | pte_noexec) or { panic('unchanged block') }
 assert live_pages == 3 && reserved_pages == 2 && unsafe { *entry } == original
 fail_pages = true
 kernel_pagemap.map_page(direct_large_size + 4096, 0x400000, pte_present | pte_noexec) or {}
 assert live_pages == 3 && reserved_pages == 2 && unsafe { *entry } == original
 fail_pages = false; vmm_initialised = true
 kernel_pagemap.map_page(direct_large_size + 4096, 0x400000, pte_present | pte_noexec) or { panic('split') }
 assert live_pages == 4 && reserved_pages == 3 && direct_large_entries == 0
 assert kernel_pagemap.virt2phys(direct_large_size + 4096) or { 0 } == 0x400000
 neighbor := kernel_pagemap.virt2pte(direct_large_size + 8192, false) or { panic('neighbor') }
 assert unsafe { *neighbor } & pte_writable != 0
 kernel_pagemap.flag_page(direct_large_size + 8192, pte_present | pte_noexec) or { panic('protect') }
 assert unsafe { *neighbor } & pte_writable == 0
 kernel_pagemap.unmap_page(direct_large_size + 4096) or { panic('partial unmap') }
 if _ := kernel_pagemap.virt2phys(direct_large_size + 4096) { assert false }
 assert kernel_pagemap.virt2phys(direct_large_size + 8192) or { 0 } == direct_large_size + 8192
 for i := u64(0); i < 512; i++ {
 if i != 1 { kernel_pagemap.unmap_page(direct_large_size + i * page_size) or { panic('cleanup') } }
 }
 assert live_pages == 1 && reserved_pages == 0 // the root is caller-owned
 pmm_free(kernel_pagemap.top_level, 1); assert live_pages == 0
 println('TLB host: PCID ownership, inactive invalidation, fallback, MTRR boundaries, large split and rollback PASS')
}
"""
    (root / "main.v").write_text(main)
    subprocess.run([os.environ.get("V", "v"), "-enable-globals", "run", str(root)], check=True)
