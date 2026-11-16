// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_memory_constant_lane_tables_widths_counts_forms_and_cache() {
	mut p := IRTypedProgram{types: [IRType{kind: .integer_t, bits: 8}, IRType{kind: .vector_t, count: 4, refs_count: 1}], references: [0]}
	mut constants := [IRConstant{}]; mut words := []u64{len: 16}
	pools := IRConstantPools{module_values: 1, scopes: [IRConstantScope{active: true}, IRConstantScope{active: true, base_id: 1}], constants: constants, words: words}
	bodies := IRFunctionBodies{scopes: [IRBodyScope{}, IRBodyScope{active: true, base_id: 1}]}
	source := IRTypedOperand{number: 0, type_index: 1}
	defer { p.free(); pools.free(); bodies.free() }
	mut checks := 0
	for bits in u32(1) .. 65 { for count in 1 .. 17 {
		p.types[0] = IRType{kind: .integer_t, bits: bits}; p.types[1] = IRType{kind: .vector_t, count: u64(count), refs_count: 1}
		for i in 0 .. count { words[i] = u64(i + 17) | ~constant_mask(bits) }
		for kind in [IRConstantKind.data, .integer, .zero, .poison, .undef] {
			constants[0] = IRConstant{kind: kind, type_index: 1, bits: bits, words_count: if kind == .data { count } else if kind == .integer { 1 } else { 0 }, splat: kind == .integer}
			mut b := MemoryIndexBuilder{p: p, pools: pools, bodies: bodies, scope: 1}
			b.nodes.flags |= .noslices
			base := b.constant_lanes(source, bits, count)!
			assert base == 0 && b.nodes.len == count && b.cache.len == 1
			assert b.constant_lanes(source, bits, count)! == base && b.nodes.len == count
			undef := b.nodes[base].flags
			assert undef == if kind == .undef { (u64(1) << u32(count)) - 1 } else { u64(0) }
			b.nodes << MemoryIndexNode{}
			b.nodes << MemoryIndexNode{}
			b.nodes << MemoryIndexNode{kind: .freeze_value, bits: bits, left: count + 1, root: true}
			for freeze in [false, true] { for index in 0 .. count + 2 {
				b.nodes[count] = MemoryIndexNode{value: u64(index), bits: 64}
				b.nodes[count + 1] = MemoryIndexNode{kind: .constant_lane, bits: bits, left: count, right: base, value: u64(count), flags: undef, root: !freeze}
				profile := IRMemoryProfile{index_nodes: b.nodes}
				fails := (kind == .undef && index < count) || (!freeze && (kind == .poison || index >= count))
				if values := profile.memory_index_values([]IRMemoryBinding{}) {
					assert !fails
					expected := if index >= count || kind in [.poison, .undef, .zero] { u64(0) } else { words[if kind == .integer { 0 } else { index }] & constant_mask(bits) }
					assert values[count + 2] == expected
				} else { assert fails }
				checks++
			} }
			// Revalidate full metadata before returning a previously cached table.
			saved := constants[0]; constants[0] = IRConstant{kind: .data, type_index: 1, bits: bits, words_count: count - 1}
			if _ := b.constant_lanes(source, bits, count) { assert false, 'cached malformed vector' }
			constants[0] = saved
			unsafe { b.nodes.free(); b.cache.free() }
		}
	} }
	assert checks == 107520
	println('AIR-MEMORY-CONSTANT-LANES: ${checks} data/splat/zero/poison/undef width/count/selector/freeze checks, cache reuse and metadata revalidation PASS')
}

fn test_memory_constant_lane_mixed_aggregate_and_budget() {
	p := IRTypedProgram{types: [IRType{kind: .integer_t, bits: 32}, IRType{kind: .vector_t, count: 4, refs_count: 1}], references: [0]}
	mut constants := [IRConstant{kind: .aggregate, type_index: 1, record: 0}, IRConstant{kind: .integer, type_index: 0, bits: 32, words_count: 1}, IRConstant{kind: .poison, type_index: 0, bits: 32}, IRConstant{kind: .undef, type_index: 0, bits: 32}, IRConstant{kind: .zero, type_index: 0, bits: 32}]
	pools := IRConstantPools{module_values: 5, scopes: [IRConstantScope{active: true}, IRConstantScope{active: true, base_id: 5}], constants: constants, words: [u64(17)]}
	bodies := IRFunctionBodies{scopes: [IRBodyScope{}, IRBodyScope{active: true, base_id: 5}]}
	stream := Stream{records: [Record{code: 7, values_count: 4}], values: [u64(1), 2, 3, 4]}
	source := IRTypedOperand{number: 0, type_index: 1}
	defer { p.free(); pools.free(); bodies.free(); stream.free() }
	for over in [false, true] {
		mut b := MemoryIndexBuilder{p: p, pools: pools, bodies: bodies, stream: stream, scope: 1, nodes: []MemoryIndexNode{len: if over { 253 } else { 252 }}}
		b.nodes.flags |= .noslices
		if base := b.constant_lanes(source, 32, 4) {
			assert !over && base == 252 && b.nodes.len == 256
			assert b.nodes[base].value == 17 && b.nodes[base].flags == 4
			assert b.nodes[base + 1].kind == .poison && b.nodes[base + 2].kind == .literal && b.nodes[base + 3].value == 0
			assert b.constant_lanes(source, 32, 4)! == base
			saved := constants[2]; constants[2] = IRConstant{kind: .opaque, type_index: 0, bits: 32}
			if _ := b.constant_lanes(source, 32, 4) { assert false, 'unselected opaque lane in cache' }; constants[2] = saved
		} else { assert over }
		unsafe { b.nodes.free(); b.cache.free() }
	}
	println('AIR-MEMORY-CONSTANT-LANE-GUARDS: mixed aggregate state, exact table budget and cached unselected opaque lane rejection PASS')
}
