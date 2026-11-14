// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_memset_declaration_attributes() {
	blocks := [Block{parent: -1}, Block{id: 9, parent: 0}, Block{id: 10, parent: 0}]
	records := [Record{block: 1, code: 2, values_count: 2}, Record{block: 2, code: 3, values_start: 2, values_count: 4}, Record{block: 2, code: 3, values_start: 6, values_count: 4}]
	mut values := [u64(7), 8, 7, 4, 0, 60, 8, 0xffffffff, 0, 18]
	defer { unsafe { blocks.free(); records.free(); values.free() } }
	stream := Stream{blocks: blocks, records: records, values: values}
	assert intrinsic_declaration_attributes(stream, 1, 64, 4, .write)! > 0
	for slot in [u64(0), 1, 2, 3, 5, 0xffffffff]! {
		values[3] = slot
		if _ := intrinsic_declaration_attributes(stream, 1, 64, 4, .write) { assert false, 'wrong immarg slot' }
	}
	values[3] = 4
	for attr in [u64(20), 21, 53, 54]! {
		values[9] = attr
		if _ := intrinsic_declaration_attributes(stream, 1, 64, 4, .write) { assert false, 'unsupported memory declaration property' }
	}
	values[9] = 18; values[5] = 18
	if _ := intrinsic_declaration_attributes(stream, 1, 64, 4, .write) { assert false, 'non-immarg parameter property' }
	values[5] = 60
	if _ := intrinsic_declaration_attributes(stream, 1, 1, 4, .write) { assert false, 'attribute budget' }
	records2 := [Record{block: 1, code: 2, values_count: 3}, Record{block: 2, code: 3, values_start: 3, values_count: 5}, Record{block: 2, code: 3, values_start: 8, values_count: 7}, Record{block: 2, code: 3, values_start: 15, values_count: 4}]
	mut values2 := [u64(1), 2, 3, 1, 0xffffffff, 1, 86, 2, 2, 1, 0, 52, 1, 102, 0, 3, 4, 0, 60]
	defer { unsafe { records2.free(); values2.free() } }
	stream2 := Stream{blocks: blocks, records: records2, values: values2}
	for version in u64(0) .. 3 {
		values2[7] = (version << 56) | 2
		assert intrinsic_declaration_attributes(stream2, 1, 64, 4, .write)! > 0
	}
	for bad in [u64(0), 1, 3, 6, (u64(3) << 56) | 2]! {
		values2[7] = bad
		if _ := intrinsic_declaration_attributes(stream2, 1, 64, 4, .write) { assert false, 'wrong memory effects/version' }
	}
	values2[7] = 2; values2[14] = 1
	if _ := intrinsic_declaration_attributes(stream2, 1, 64, 4, .write) { assert false, 'capturing destination' }
	values2[14] = 0; values2[11] = 21
	if _ := intrinsic_declaration_attributes(stream2, 1, 64, 4, .write) { assert false, 'readonly destination' }
	values2[11] = 52; values2[0] = 3; values2[2] = 1
	assert intrinsic_declaration_attributes(stream2, 1, 64, 4, .write)! > 0
	values2[0] = 2
	if _ := intrinsic_declaration_attributes(stream2, 1, 64, 4, .write) { assert false, 'duplicate destination group' }
	println('AIR-MEMSET-ATTRIBUTES: fourth immarg, destination writeonly/captures(none), memory(argmem: write) versions 0/1/2, group order and slot/property/effect/version/duplicate/budget exclusions PASS')
}

fn test_memmove_declaration_attributes() {
	blocks := [Block{parent: -1}, Block{id: 9, parent: 0}, Block{id: 10, parent: 0}]
	records := [Record{block: 1, code: 2, values_count: 4}, Record{block: 2, code: 3, values_start: 4, values_count: 5}, Record{block: 2, code: 3, values_start: 9, values_count: 7}, Record{block: 2, code: 3, values_start: 16, values_count: 7}, Record{block: 2, code: 3, values_start: 23, values_count: 4}]
	mut values := [u64(1), 2, 3, 4, 1, 0xffffffff, 1, 86, 3, 2, 1, 0, 52, 1, 102, 0, 3, 2, 0, 21, 1, 102, 0, 4, 4, 0, 60]
	defer { unsafe { blocks.free(); records.free(); values.free() } }
	stream := Stream{blocks: blocks, records: records, values: values}
	for version in u64(0) .. 3 { values[8] = (version << 56) | 3; assert intrinsic_declaration_attributes(stream, 1, 96, 4, .read_write)! > 0 }
	for bad in [u64(0), 1, 2, 7, (u64(3) << 56) | 3]! {
		values[8] = bad
		if _ := intrinsic_declaration_attributes(stream, 1, 96, 4, .read_write) { assert false, 'wrong memmove effects/version' }
	}
	values[8] = 3
	for bad in [u64(9), 52, 68]! {
		values[19] = bad
		if _ := intrinsic_declaration_attributes(stream, 1, 96, 4, .read_write) { assert false, 'source noalias/writeonly/noundef' }
	}
	values[19] = 21; values[22] = 1
	if _ := intrinsic_declaration_attributes(stream, 1, 96, 4, .read_write) { assert false, 'capturing source' }
	values[22] = 0; values[2] = 2
	if _ := intrinsic_declaration_attributes(stream, 1, 96, 4, .read_write) { assert false, 'duplicate destination group' }
	values[2] = 3; values[1] = 3
	if _ := intrinsic_declaration_attributes(stream, 1, 96, 4, .read_write) { assert false, 'duplicate source group' }
	values[0] = 4; values[1] = 3; values[2] = 2; values[3] = 1
	assert intrinsic_declaration_attributes(stream, 1, 96, 4, .read_write)! > 0
	if _ := intrinsic_declaration_attributes(stream, 1, 1, 4, .read_write) { assert false, 'scan budget' }
	if _ := intrinsic_declaration_attributes(stream, 1, 96, 4, .write) { assert false, 'memset may not admit memmove source group' }
	println('AIR-MEMMOVE-ATTRIBUTES: destination writeonly, source readonly, captures(none), fourth immarg, argmem read/write versions 0/1/2, group order and effect/property/duplicate/budget exclusions PASS')
}
