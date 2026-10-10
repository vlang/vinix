@[has_globals]
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
