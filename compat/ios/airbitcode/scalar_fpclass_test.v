// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_scalar_fpclass_bits_and_masks() {
	// Two representatives per class: boundaries, both NaN signs/payloads.
	half := [u64(0x7c01), 0xfcff, 0x7e00, 0xffff, 0xfc00, 0xfc00, 0x8400, 0xfbff,
		0x8001, 0x83ff, 0x8000, 0x8000, 0, 0, 1, 0x3ff, 0x400, 0x7bff, 0x7c00, 0x7c00]!
	float := [u64(0x7f800001), 0xffbfffff, 0x7fc00000, 0xffffffff, 0xff800000, 0xff800000, 0x80800000, 0xff7fffff,
		0x80000001, 0x807fffff, 0x80000000, 0x80000000, 0, 0, 1, 0x7fffff, 0x800000, 0x7f7fffff, 0x7f800000, 0x7f800000]!
	mut comparisons := 0
	for bits in [u32(16), 32]! {
		for i in 0 .. 20 {
			value := if bits == 16 { half[i] } else { float[i] }
			assert scalar_fpclass(bits, value) == u32(1) << (i / 2)
			for mask in 0 .. 1024 {
				assert scalar_intrinsic_value(.is_fpclass, bits, value, u64(mask))! == u64(mask & (1 << (i / 2)) != 0)
				comparisons++
			}
		}
		name := 'llvm.is.fpclass.f${bits}'; defer { unsafe { name.free() } }
		assert scalar_intrinsic_name(name)! == .is_fpclass
		assert scalar_intrinsic_arity(.is_fpclass) == 2
	}
	for mask in [u64(1024), 0xffffffff, 0x100000000]! {
		if _ := scalar_intrinsic_value(.is_fpclass, 32, 0, mask) { assert false, 'invalid classification mask' }
	}
	for name in ['llvm.is.fpclass.f64', 'llvm.is.fpclass.v2f32', 'llvm.is.fpclass.f16.i32', 'air.is.fpclass.f32'] {
		if _ := scalar_intrinsic_name(name) { assert false, 'unsupported classification name' }
	}
	println('AIR-SCALAR-FPCLASS: ${comparisons} exact tests over all 1024 masks, ten classes/boundaries/signs and name/arity/mask guards PASS')
}

fn test_scalar_fpclass_immarg_attributes() {
	blocks := [Block{parent: -1}, Block{id: 9, parent: 0}, Block{id: 10, parent: 0}]
	records := [Record{block: 1, code: 2, values_count: 2}, Record{block: 2, code: 3, values_start: 2, values_count: 4}, Record{block: 2, code: 3, values_start: 6, values_count: 4}]
	mut values := [u64(7), 8, 7, 0xffffffff, 0, 18, 8, 2, 0, 60]
	defer { unsafe { blocks.free(); records.free(); values.free() } }
	stream := Stream{blocks: blocks, records: records, values: values}
	work := scalar_intrinsic_attributes_profile(stream, 1, 64, true)!
	assert work > 0
	assert scalar_intrinsic_attributes_profile(stream, 1, work, true)! == work
	if _ := scalar_intrinsic_attributes_profile(stream, 1, work - 1, true) { assert false, 'exact classification attribute work bound' }
	if _ := scalar_intrinsic_attributes(stream, 1, 64) { assert false, 'immarg leaked to other intrinsics' }
	for slot in [u64(0), 1, 3, 0xffffffff]! {
		values[7] = slot
		if _ := scalar_intrinsic_attributes_profile(stream, 1, 64, true) { assert false, 'wrong/duplicate immarg slot' }
	}
	values[7] = 2
	for attribute in [u64(18), 54, 105]! {
		values[9] = attribute
		if _ := scalar_intrinsic_attributes_profile(stream, 1, 64, true) { assert false, 'other parameter attribute' }
	}
	values[9] = 60; values[8] = 1
	if _ := scalar_intrinsic_attributes_profile(stream, 1, 64, true) { assert false, 'integer immarg encoding' }
	values[8] = 0; values[1] = 7
	if _ := scalar_intrinsic_attributes_profile(stream, 1, 64, true) { assert false, 'duplicate function group' }
	values[1] = 8
	if _ := scalar_intrinsic_attributes_profile(stream, 1, 1, true) { assert false, 'classification attribute work limit' }
	println('AIR-SCALAR-FPCLASS-ATTRIBUTES: exact parameter-two immarg, other-intrinsic/slot/attribute/encoding/duplicate/budget guards PASS')
}
