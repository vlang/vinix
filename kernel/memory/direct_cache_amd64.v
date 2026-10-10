// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module memory

import limine
import x86.cpu
import x86.msr

struct DirectMTRR {
	base u64
	top u64
	kind u8
}

__global (
	direct_mtrrs [256]DirectMTRR
	direct_mtrr_count int
	direct_cache_valid bool
	direct_default_wb bool
)

// Firmware's variable MTRRs are immutable after this boot snapshot. Fixed
// MTRRs cover only the first MiB, which is never promoted. Unknown layouts
// retain base pages; no MSR is read without the corresponding CPUID feature.
fn init_direct_cache_types() {
	valid, _, _, _, features := cpu.cpuid(1, 0)
	width_valid, width, _, _, _ := cpu.cpuid(0x80000008, 0)
	bits := width & 0xff
	if !valid || features & (u32(1) << 12) == 0 || !width_valid || bits < 32 || bits > 52 { return }
	cap := msr.rdmsr(0xfe)
	defaults := msr.rdmsr(0x2ff)
	if defaults & (u64(1) << 11) == 0 { return } // Disabled MTRRs: keep the UC aperture small.
	direct_default_wb = defaults & 0xff == 6
	mask := ((u64(1) << bits) - 1) & ~(page_size - 1)
	for i := u32(0); i < u32(cap & 0xff); i++ {
		if !record_direct_mtrr(msr.rdmsr(0x200 + 2 * i), msr.rdmsr(0x201 + 2 * i), mask) { return }
	}
	direct_cache_valid = true
}

fn record_direct_mtrr(raw_base u64, raw_mask u64, physical_mask u64) bool {
	if raw_mask & (u64(1) << 11) == 0 { return true }
	mask := raw_mask & physical_mask
	size := (~mask & physical_mask) + page_size
	base := raw_base & physical_mask
	if size == 0 || size & (size - 1) != 0 || base & (size - 1) != 0 { return false }
	direct_mtrrs[direct_mtrr_count] = DirectMTRR{base: base, top: base + size, kind: u8(raw_base)}
	direct_mtrr_count++
	return true
}

// A constant set of matching MTRRs proves uniformity. Reject even a same-type
// boundary inside a candidate, and any matching non-WB range. Thus unknown
// overlap rules and mixed cache types can never be hidden in one large leaf.
fn direct_cache_uniform(base u64) bool {
	if !direct_cache_valid || base < 0x100000 { return false }
	top := base + direct_large_size
	mut matched := false
	for i in 0 .. direct_mtrr_count {
		range := direct_mtrrs[i]
		if range.top <= base || range.base >= top { continue }
		if range.base > base || range.top < top || range.kind != 6 { return false }
		matched = true
	}
	return matched || direct_default_wb
}

fn direct_large_eligible(base u64) bool {
	if !direct_cache_uniform(base) { return false }
	memmap := memmap_req.response
	if memmap == unsafe { nil } { return false }
	for i := u64(0); i < memmap.entry_count; i++ {
		entry := unsafe { memmap.entries[i] }
		if entry.@type == limine.limine_memmap_usable && entry.length >= direct_large_size
			&& base >= entry.base && base - entry.base <= entry.length - direct_large_size { return true }
	}
	return false
}
