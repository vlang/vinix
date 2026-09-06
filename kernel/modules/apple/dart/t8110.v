module dart

// Apple T8110-family DART2 format used by the T6050 PMP wrappers. This file
// deliberately contains only the pure entry codec and read-only DeviceTree
// admission contract. The older DART implementation in dart.v programs the
// incompatible T8020 register/table format and must not be used for T8110.

import devicetree

const t8110_page_shift = u32(14)
const t8110_page_size = u64(1) << t8110_page_shift
const t8110_page_mask = t8110_page_size - 1
const t8110_address_bits = u32(42)
const t8110_pte_physical_mask = u64(0x3ffffffc00)
const t8110_pte_valid = u64(1) << 0
const t8110_pte_no_cache = u64(1) << 1
const t8110_pte_no_write = u64(1) << 2
const t8110_pte_no_read = u64(1) << 3
const t8110_pte_subpage_end = u64(0xfff) << 40
const t8110_ttbr_valid = u32(1) << 0
const t8110_die_stride = u64(0x4000000000)
const t8110_pmp_vm_base = u64(0x10000000000)
const t8110_pmp_vm_size = u64(0x1000000000)

pub struct T8110DartContract {
pub:
	die             u32
	registers       [2]devicetree.DTReg
	active_sids     []u32
	bypassed_sids   []u32
	translated_sids []u32
	mapper_index    u32
	mapper_handle   u32
	vm_base         u64
	vm_size         u64
}

// AppleT8110DART formats this property's name as "bypass-${SID}" and records
// its presence in the per-SID bypass bitset. The selected T6050 properties are
// empty booleans; accepting data-bearing variants would silently discard a
// bypass-address contract that Vinix does not implement.
fn t8110_empty_boolean_property(node &devicetree.DTNode, name string) i32 {
	property := devicetree.get_property(node, name) or { return 0 }
	if property.len != 0 {
		return -1
	}
	return 1
}

fn t8110_string_property_contains(node &devicetree.DTNode, property string,
	expected string) bool {
	values := devicetree.get_string_list(node, property) or { return false }
	for value in values {
		if value == expected {
			return true
		}
	}
	return false
}

fn t8110_u32_array_equals(actual []u32, expected []u32) bool {
	if actual.len != expected.len {
		return false
	}
	for index := 0; index < expected.len; index++ {
		if actual[index] != expected[index] {
			return false
		}
	}
	return true
}

// DART2 stores physical bits [41:14] in entry bits [37:10]. All table and
// leaf pages are exactly 16 KiB aligned.
pub fn t8110_encode_table_entry(physical u64) ?u64 {
	if physical & t8110_page_mask != 0 || physical >> t8110_address_bits != 0 {
		return none
	}
	return ((physical >> 4) & t8110_pte_physical_mask) | t8110_pte_valid
}

// This encoder is deliberately full-page-only. Apple routes partial byte-range
// requests through its protected PPL/SPTM mapper; the UUID-pinned public driver
// does not expose how those requests become DART2 subpage fields. In particular,
// this must not be used to recreate the iBoot-owned PMP firmware mappings.
pub fn t8110_encode_full_page_leaf_entry(physical u64, readable bool, writable bool,
	cacheable bool) ?u64 {
	if !readable && !writable {
		return none
	}
	mut entry := t8110_encode_table_entry(physical) or { return none }
	entry |= t8110_pte_subpage_end
	if !readable {
		entry |= t8110_pte_no_read
	}
	if !writable {
		entry |= t8110_pte_no_write
	}
	if !cacheable {
		entry |= t8110_pte_no_cache
	}
	return entry
}

pub fn t8110_decode_entry_physical(entry u64) ?u64 {
	if entry & t8110_pte_valid == 0 {
		return none
	}
	return (entry & t8110_pte_physical_mask) << 4
}

// T8110 has one 32-bit TTBR per SID. Its address is shifted right by 14 and
// then placed at bit 2, which is equivalent to physical >> 12 plus valid bit 0.
pub fn t8110_encode_ttbr(physical u64) ?u32 {
	if physical & t8110_page_mask != 0 || physical >> t8110_address_bits != 0 {
		return none
	}
	return u32((physical >> t8110_page_shift) << 2) | t8110_ttbr_valid
}

pub fn t8110_decode_ttbr(value u32) ?u64 {
	if value & t8110_ttbr_valid == 0 {
		return none
	}
	return (u64(value & ~t8110_ttbr_valid) >> 2) << t8110_page_shift
}

// The UUID-matched kernel's index tables operate on a 16 KiB page number.
// Level zero is the five-bit root; levels one through three are 11-bit tables.
pub fn t8110_page_table_index(iova u64, level u32) ?u64 {
	if iova >> t8110_address_bits != 0 || level >= 4 {
		return none
	}
	page := iova >> t8110_page_shift
	return match level {
		0 { (page & u64(0x3e00000000)) >> 33 }
		1 { (page & u64(0x1ffc00000)) >> 22 }
		2 { (page & u64(0x3ff800)) >> 11 }
		3 { page & u64(0x7ff) }
		else {
			return none
		}
	}
}

// Exercise every recovered field without touching DART registers or tables.
// This is called by the T6050 admission check before any hardware gate opens.
pub fn validate_t8110_codec() bool {
	physical := u64(0x284500000)
	table := t8110_encode_table_entry(physical) or { return false }
	leaf := t8110_encode_full_page_leaf_entry(physical, true, false, false) or {
		return false
	}
	ttbr := t8110_encode_ttbr(physical) or { return false }
	return t8110_decode_entry_physical(table) or { return false } == physical
		&& t8110_decode_entry_physical(leaf) or { return false } == physical
		&& leaf & t8110_pte_subpage_end == t8110_pte_subpage_end
		&& leaf & t8110_pte_no_read == 0
		&& leaf & t8110_pte_no_write != 0
		&& leaf & t8110_pte_no_cache != 0
		&& t8110_decode_ttbr(ttbr) or { return false } == physical
		&& t8110_page_table_index(0x1000000, 0) or { return false } == 0
		&& t8110_page_table_index(0x1000000, 3) or { return false } == 0x400
}

fn find_t6050_pmp_mapper(dart_node &devicetree.DTNode, die u32) ?&devicetree.DTNode {
	expected_name := if die == 0 { 'mapper-pmp0' } else { 'mapper-pmp1' }
	mut found_index := -1
	for index, child in dart_node.children {
		if child.name == expected_name
			&& t8110_string_property_contains(child, 'compatible', 'iommu-mapper') {
			if found_index >= 0 {
				return none
			}
			found_index = index
		}
	}
	if found_index < 0 {
		return none
	}
	return dart_node.children[found_index]
}

// Recover the exact T6050 PMP mapper binding from the boot DeviceTree. This
// performs no MMIO mapping or access. In particular it does not assume Vinix
// owns a protected TTBR merely because the bootloader left one installed.
pub fn get_t6050_pmp_dart_contract(die u32,
	wrapper &devicetree.DTNode) ?T8110DartContract {
	if die >= 2 {
		return none
	}
	path := if die == 0 { '/arm-io/dart-pmp0' } else { '/arm-io/dart-pmp1' }
	dart_node := devicetree.find_node(path) or { return none }
	if !t8110_string_property_contains(dart_node, 'compatible', 'dart,t8110') {
		return none
	}
	regions := devicetree.get_translated_reg_ranges(dart_node) or { return none }
	if regions.len != 2 {
		return none
	}
	die_offset := u64(die) * t8110_die_stride
	if regions[0].base != 0x841a0000 + die_offset || regions[0].size != 0xc000
		|| regions[1].base != 0x841b0000 + die_offset || regions[1].size != 0x4000 {
		return none
	}
	sids := devicetree.get_le_u32_array(dart_node, 'sid') or { return none }
	expected_bypassed_sids := [u32(2), 5, 6, 7, 8, 9]
	for sid := u32(0); sid < 16; sid++ {
		state := t8110_empty_boolean_property(dart_node, 'bypass-${sid}')
		mut expected := false
		for bypassed_sid in expected_bypassed_sids {
			if sid == bypassed_sid {
				expected = true
				break
			}
		}
		if (expected && state != 1) || (!expected && state != 0) {
			return none
		}
	}
	if !t8110_u32_array_equals(sids, [u32(0), 1, 2, 5, 6, 7, 8, 9])
		|| devicetree.get_le_u32(dart_node, 'page-size') or { return none } != u32(t8110_page_size)
		|| devicetree.get_le_u32(dart_node, 'sid-count') or { return none } != 16
		|| devicetree.get_le_u32(dart_node, 'dart-options') or { return none } != 0x65
		|| devicetree.get_le_u32(dart_node, 'flush-by-dva') or { return none } != 0
		|| devicetree.get_le_u64(dart_node, 'vm-base') or { return none } != t8110_pmp_vm_base
		|| devicetree.get_le_u64(dart_node, 'vm-size') or { return none } != t8110_pmp_vm_size {
		return none
	}
	mapper := find_t6050_pmp_mapper(dart_node, die) or { return none }
	mapper_index := devicetree.get_le_u32(mapper, 'reg') or { return none }
	mapper_handle := devicetree.get_le_u32(mapper, 'AAPL,phandle') or { return none }
	wrapper_parent := devicetree.get_le_u32(wrapper, 'iommu-parent') or { return none }
	if mapper_index != 0 || mapper_handle == 0 || wrapper_parent != mapper_handle {
		return none
	}
	return T8110DartContract{
		die: die
		registers: [regions[0], regions[1]]!
		active_sids: sids
		bypassed_sids: expected_bypassed_sids
		translated_sids: [u32(0), 1]
		mapper_index: mapper_index
		mapper_handle: mapper_handle
		vm_base: t8110_pmp_vm_base
		vm_size: t8110_pmp_vm_size
	}
}
