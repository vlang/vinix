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

fn test_memcpy_declaration_attributes() {
	blocks := [Block{parent: -1}, Block{id: 9, parent: 0}, Block{id: 10, parent: 0}]
	records := [Record{block: 1, code: 2, values_count: 4}, Record{block: 2, code: 3, values_start: 4, values_count: 5}, Record{block: 2, code: 3, values_start: 9, values_count: 9}, Record{block: 2, code: 3, values_start: 18, values_count: 9}, Record{block: 2, code: 3, values_start: 27, values_count: 4}]
	mut values := [u64(1), 2, 3, 4, 1, 0xffffffff, 1, 86, 3, 2, 1, 0, 9, 0, 52, 1, 102, 0, 3, 2, 0, 9, 0, 21, 1, 102, 0, 4, 4, 0, 60]
	defer { unsafe { blocks.free(); records.free(); values.free() } }
	stream := Stream{blocks: blocks, records: records, values: values}
	for version in u64(0) .. 3 { values[8] = (version << 56) | 3; assert intrinsic_declaration_attributes(stream, 1, 96, 4, .copy)! > 0 }
	values[8] = 3
	if _ := intrinsic_declaration_attributes(stream, 1, 96, 4, .read_write) { assert false, 'memmove must not admit noalias' }
	values[14] = 9
	if _ := intrinsic_declaration_attributes(stream, 1, 96, 4, .copy) { assert false, 'duplicate destination noalias' }
	values[14] = 52; values[23] = 9
	if _ := intrinsic_declaration_attributes(stream, 1, 96, 4, .copy) { assert false, 'duplicate source noalias' }
	values[23] = 52
	if _ := intrinsic_declaration_attributes(stream, 1, 96, 4, .copy) { assert false, 'writeonly source' }
	values[23] = 21; values[26] = 1
	if _ := intrinsic_declaration_attributes(stream, 1, 96, 4, .copy) { assert false, 'capturing source' }
	values[26] = 0; values[12] = 68
	if _ := intrinsic_declaration_attributes(stream, 1, 96, 4, .copy) { assert false, 'noundef destination' }
	values[12] = 9; values[0] = 4; values[1] = 3; values[2] = 2; values[3] = 1
	assert intrinsic_declaration_attributes(stream, 1, 96, 4, .copy)! > 0
	if _ := intrinsic_declaration_attributes(stream, 1, 1, 4, .copy) { assert false, 'attribute work budget' }
	println('AIR-MEMCPY-ATTRIBUTES: canonical noalias/read/write/captures(none), argmem versions 0/1/2, parameter group order and duplicate/property/budget exclusions; memmove noalias exclusion PASS')
}

fn test_memory_call_alignment_attributes() {
	blocks := [Block{parent: -1}, Block{id: 9, parent: 0}, Block{id: 10, parent: 0}]
	records := [Record{block: 1, code: 2, values_count: 2}, Record{block: 2, code: 3, values_start: 2, values_count: 5}, Record{block: 2, code: 3, values_start: 7, values_count: 5}]
	mut values := [u64(7), 8, 7, 1, 1, 1, 16, 8, 2, 1, 1, 32]
	defer { unsafe { blocks.free(); records.free(); values.free() } }
	stream := Stream{blocks: blocks, records: records, values: values}
	default_alignment, default_work := memory_call_alignment(stream, 0, 0)!
	assert default_alignment.destination == 1 && default_alignment.source == 1 && !default_alignment.source_set && default_work == 0
	for shift in 0 .. 27 {
		values[6] = u64(1) << shift; values[11] = u64(1) << ((shift + 5) % 27)
		alignment, work := memory_call_alignment(stream, 1, 64)!
		assert alignment.destination == values[6] && alignment.source == values[11] && alignment.source_set && work > 0
	}
	values[6] = 16; values[11] = 32
	for slot in [6, 11] { for bad in [u64(0), 3, 5, 67108865, 134217728, u64(1) << 63]! {
		values[slot] = bad
		if _, _ := memory_call_alignment(stream, 1, 64) { assert false, 'alignment bound/power' }
	}; values[slot] = if slot == 6 { u64(16) } else { u64(32) } }
	for slot in [3, 8] { saved := values[slot]; for bad in [u64(0), 3, 4, 0xffffffff]! {
		values[slot] = bad
		if _, _ := memory_call_alignment(stream, 1, 64) { assert false, 'non-pointer call attribute slot' }
	}; values[slot] = saved }
	values[8] = 1
	if _, _ := memory_call_alignment(stream, 1, 64) { assert false, 'duplicate destination slot' }
	values[8] = 2; values[0] = 8
	if _, _ := memory_call_alignment(stream, 1, 64) { assert false, 'duplicate source group' }
	values[0] = 7
	for slot in [4, 5, 9, 10] { values[slot] = 68
		if _, _ := memory_call_alignment(stream, 1, 64) { assert false, 'attribute kind/id' }
		values[slot] = 1
	}
	values[0] = 999
	if _, _ := memory_call_alignment(stream, 1, 64) { assert false, 'missing group' }
	values[0] = 7
	if _, _ := memory_call_alignment(stream, 2, 64) { assert false, 'missing list' }
	if _, _ := memory_call_alignment(stream, 1, 1) { assert false, 'scan budget' }
	single_records := [Record{block: 1, code: 2, values_count: 1}, records[1], records[2]]
	defer { unsafe { single_records.free() } }
	single := Stream{blocks: blocks, records: single_records, values: values}
	destination, _ := memory_call_alignment(single, 1, 64)!
	assert destination.destination == 16 && destination.source == 1 && !destination.source_set
	values[0] = 8
	source, _ := memory_call_alignment(single, 1, 64)!
	assert source.destination == 1 && source.source == 32 && source.source_set
	values[0] = 7; values[1] = 7; values[3] = 2; values[8] = 1
	if _, _ := memory_call_alignment(stream, 1, 64) { assert false, 'repeated valid group' }
	values[0] = 8; values[1] = 7; values[3] = 1; values[8] = 2
	ordered, _ := memory_call_alignment(stream, 1, 64)!
	assert ordered.destination == 16 && ordered.source == 32 && ordered.source_set
	println('AIR-MEMORY-CALL-ALIGNMENT: default/destination/source attributes, all powers through 64 MiB and bound/power/slot/kind/missing/duplicate/budget exclusions PASS')
}

fn test_inline_memcpy_declaration_attributes() {
	blocks := [Block{parent: -1}, Block{id: 9, parent: 0}, Block{id: 10, parent: 0}]
	records := [Record{block: 1, code: 2, values_count: 5}, Record{block: 2, code: 3, values_start: 5, values_count: 5}, Record{block: 2, code: 3, values_start: 10, values_count: 9}, Record{block: 2, code: 3, values_start: 19, values_count: 9}, Record{block: 2, code: 3, values_start: 28, values_count: 4}, Record{block: 2, code: 3, values_start: 32, values_count: 4}]
	mut values := [u64(1), 2, 3, 4, 5, 1, 0xffffffff, 1, 86, 3, 2, 1, 0, 9, 0, 52, 1, 102, 0, 3, 2, 0, 9, 0, 21, 1, 102, 0, 4, 3, 0, 60, 5, 4, 0, 60]
	defer { unsafe { blocks.free(); records.free(); values.free() } }
	stream := Stream{blocks: blocks, records: records, values: values}
	for version in u64(0) .. 3 { values[9] = (version << 56) | 3; assert intrinsic_declaration_attributes(stream, 1, 128, 4, .inline_copy)! > 0 }
	values[9] = 3
	if _ := intrinsic_declaration_attributes(stream, 1, 128, 4, .copy) { assert false, 'ordinary copy length immarg excluded' }
	work := intrinsic_declaration_attributes(stream, 1, 128, 4, .inline_copy)!
	assert intrinsic_declaration_attributes(stream, 1, work, 4, .inline_copy)! == work
	if _ := intrinsic_declaration_attributes(stream, 1, work - 1, 4, .inline_copy) { assert false, 'attribute budget' }
	for slot in [29, 33] { saved := values[slot]; values[slot] = if saved == 3 { u64(4) } else { u64(3) }
		if _ := intrinsic_declaration_attributes(stream, 1, 128, 4, .inline_copy) { assert false, 'duplicate length/volatile immarg' }
		values[slot] = 0
		if _ := intrinsic_declaration_attributes(stream, 1, 128, 4, .inline_copy) { assert false, 'return slot' }
		values[slot] = saved
	}
	for slot in [30, 31, 34, 35] { saved := values[slot]; values[slot] = 68
		if _ := intrinsic_declaration_attributes(stream, 1, 128, 4, .inline_copy) { assert false, 'exact immarg kind/property' }
		values[slot] = saved
	}
	values[4] = 4
	if _ := intrinsic_declaration_attributes(stream, 1, 128, 4, .inline_copy) { assert false, 'duplicate immarg group' }
	values[0] = 5; values[1] = 4; values[2] = 3; values[3] = 2; values[4] = 1
	assert intrinsic_declaration_attributes(stream, 1, 128, 4, .inline_copy)! > 0
	// The length immarg is optional; a literal is required at every call regardless.
	values[0] = 1; values[1] = 2; values[2] = 3; values[3] = 5
	short_records := [Record{block: 1, code: 2, values_count: 4}, records[1], records[2], records[3], records[4], records[5]]
	defer { unsafe { short_records.free() } }
	short := Stream{blocks: blocks, records: short_records, values: values}
	assert intrinsic_declaration_attributes(short, 1, 128, 4, .inline_copy)! > 0
	assert intrinsic_declaration_attributes(short, 1, 128, 4, .copy)! > 0
	println('AIR-INLINE-MEMCPY-ATTRIBUTES: five groups, optional length immarg, canonical pointer noalias/access/captures(none), argmem versions 0/1/2, order/duplicate/slot/kind/property/exact-budget guards and ordinary-copy exclusion PASS')
}

fn test_inline_memset_declaration_attributes() {
	blocks := [Block{parent: -1}, Block{id: 9, parent: 0}, Block{id: 10, parent: 0}]
	records := [Record{block: 1, code: 2, values_count: 4}, Record{block: 2, code: 3, values_start: 4, values_count: 5}, Record{block: 2, code: 3, values_start: 9, values_count: 7}, Record{block: 2, code: 3, values_start: 16, values_count: 4}, Record{block: 2, code: 3, values_start: 20, values_count: 4}]
	mut values := [u64(1), 2, 3, 4, 1, 0xffffffff, 1, 86, 2, 2, 1, 0, 52, 1, 102, 0, 3, 3, 0, 60, 4, 4, 0, 60]
	defer { unsafe { blocks.free(); records.free(); values.free() } }
	stream := Stream{blocks: blocks, records: records, values: values}
	for version in u64(0) .. 3 { values[8] = (version << 56) | 2; assert intrinsic_declaration_attributes(stream, 1, 128, 4, .inline_write)! > 0 }; values[8] = 2
	work := intrinsic_declaration_attributes(stream, 1, 128, 4, .inline_write)!
	assert intrinsic_declaration_attributes(stream, 1, work, 4, .inline_write)! == work
	if _ := intrinsic_declaration_attributes(stream, 1, work - 1, 4, .inline_write) { assert false, 'attribute budget' }
	if _ := intrinsic_declaration_attributes(stream, 1, 128, 4, .write) { assert false, 'ordinary fill length immarg excluded' }
	for slot in [17, 21] { saved := values[slot]
		for bad in [u64(0), 2, if saved == 3 { u64(4) } else { u64(3) }] { values[slot] = bad; if _ := intrinsic_declaration_attributes(stream, 1, 128, 4, .inline_write) { assert false, 'return/byte/duplicate immarg slot' } }; values[slot] = saved
	}
	for slot in [18, 19, 22, 23] { saved := values[slot]; values[slot] = 68; if _ := intrinsic_declaration_attributes(stream, 1, 128, 4, .inline_write) { assert false, 'exact immarg kind/property' }; values[slot] = saved }
	for bad in [u64(9), 21, 68] { values[12] = bad; if _ := intrinsic_declaration_attributes(stream, 1, 128, 4, .inline_write) { assert false, 'noalias/readonly/noundef destination' } }; values[12] = 52
	values[10] = 2; if _ := intrinsic_declaration_attributes(stream, 1, 128, 4, .inline_write) { assert false, 'source attributes on byte argument' }; values[10] = 1
	values[15] = 1; if _ := intrinsic_declaration_attributes(stream, 1, 128, 4, .inline_write) { assert false, 'capturing destination' }; values[15] = 0
	values[3] = 3; if _ := intrinsic_declaration_attributes(stream, 1, 128, 4, .inline_write) { assert false, 'duplicate length group' }
	values[0] = 4; values[1] = 3; values[2] = 2; values[3] = 1
	assert intrinsic_declaration_attributes(stream, 1, 128, 4, .inline_write)! > 0
	values[0] = 1; values[1] = 2; values[2] = 4
	short_records := [Record{block: 1, code: 2, values_count: 3}, records[1], records[2], records[3], records[4]]
	defer { unsafe { short_records.free() } }
	short := Stream{blocks: blocks, records: short_records, values: values}
	assert intrinsic_declaration_attributes(short, 1, 128, 4, .inline_write)! > 0 && intrinsic_declaration_attributes(short, 1, 128, 4, .write)! > 0
	println('AIR-INLINE-MEMSET-ATTRIBUTES: optional length immarg, four groups, destination writeonly/captures(none), argmem versions 0/1/2, independent immarg/byte/source/alias/capture/property/exact-budget guards and ordinary-fill exclusion PASS')
}
