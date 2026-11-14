// SPDX-License-Identifier: GPL-2.0-or-later
module tlb

// G13's 16 KiB UAT range encoding, matching Asahi mem::tlbi_range on a
// 16 KiB CPU kernel. A plan streams operands without allocating an array.
const range_address_mask = (u64(1) << 37) - 1

pub struct RangePlan {
pub:
	page       bool
	prefix     u64
	start_page u64
	scale      u32
	units      u64
	count      u64
}

pub fn range_plan(asid u8, address u64, size u64) ?RangePlan {
	if size == 0 || size - 1 > ~address { return none }
	// Count touched 16 KiB pages without overflowing at the top of TTBR1.
	last_page := (address + size - 1) >> 14
	start_page := address >> 14
	pages := last_page - start_page + 1
	if pages == 1 {
		return RangePlan{
			page:   true
			prefix: (u64(asid) << 48) | ((address >> 12) & 0xffffffffffc)
			count:  1
		}
	}
	num := (pages + 1) >> 1
	mut bit_count := u32(0)
	mut num_bits_left := num
	for num_bits_left != 0 {
		bit_count++
		num_bits_left >>= 1
	}
	scale := if bit_count / 5 > 3 { u32(3) } else { bit_count / 5 }
	shift := 5 * scale
	units := (num + (u64(1) << shift) - 1) >> shift
	return RangePlan{
		prefix:     (u64(asid) << 48) | (u64(2) << 46) | (u64(scale) << 44)
		start_page: start_page & range_address_mask
		scale:      scale
		units:      units
		count:      (units + 31) / 32
	}
}

pub fn (plan &RangePlan) operand(index u64) ?u64 {
	if index >= plan.count { return none }
	if plan.page { return plan.prefix }
	units_left := plan.units - index * 32
	units := if units_left > 32 { u64(32) } else { units_left }
	// Advance BADDR between full operations without carrying into TG/ASID.
	base := (plan.start_page + (index * 32 << (5 * plan.scale + 1))) & range_address_mask
	return plan.prefix | ((units - 1) << 39) | base
}
