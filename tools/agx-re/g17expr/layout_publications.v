module g17expr

import g17decode as arm
import math.big
import json2
import traceanalysis as j

struct LayoutPublication {
	shared int
	source int
	offset int
}

fn (item LayoutPublication) value() j.Value {
	return j.Value([j.Value(item.shared), j.Value(item.source), j.Value(item.offset)])
}

fn sorted_publications(items []LayoutPublication) []LayoutPublication {
	mut result := []LayoutPublication{}
	for item in items { if item !in result { result << item } }
	result.sort_with_compare(fn (a &LayoutPublication, b &LayoutPublication) int {
		if a.shared != b.shared { return a.shared - b.shared }
		if a.source != b.source { return a.source - b.source }
		return a.offset - b.offset
	})
	return result
}

fn direct_shared_publications(code []u8) []LayoutPublication {
	instructions := arm.words(code)
	mut publications := []LayoutPublication{}
	mut current_shared := -1
	for index, instruction in instructions {
		load := fields('decode_ldr_x', instruction.word, big.zero_int) or { continue }
		if load[0].int() == 21 && load[1].int() in [0, 19] && load[2].int() in [0xa98, 0xbc8] {
			current_shared = load[2].int()
		}
		if load[0].int() != 1 || load[1].int() !in [0, 19] { continue }
		for following_index := index + 1; following_index < int_min(index + 36, instructions.len); following_index++ {
			following := instructions[following_index]
			if next := fields('decode_ldr_x', following.word, big.zero_int) {
				if next[0].int() == 1 && next[1].int() in [0, 19] { break }
			}
			store := fields('decode_str_x', following.word, big.zero_int) or { continue }
			if store[0].int() != 0 || current_shared < 0 { continue }
			base := store[1].int()
			offset := store[2].int()
			if base == 22 {
				publications << LayoutPublication{current_shared, load[2].int(), 0x254 + offset}
				break
			}
			if base == 21 {
				publications << LayoutPublication{current_shared, load[2].int(), offset}
				break
			}
			if base != 8 { continue }
			mut target_shared := -1
			mut bias := 0
			for prior_index := following_index - 1; prior_index > index; prior_index-- {
				prior := instructions[prior_index]
				if prior_load := fields('decode_ldr_x', prior.word, big.zero_int) {
					if prior_load[0].int() == 8 && prior_load[1].int() == 19 && prior_load[2].int() in [
						0xa98,
						0xbc8,
					] {
						target_shared = prior_load[2].int()
						break
					}
				}
				if prior_add := fields('decode_add_immediate', prior.word, big.zero_int) {
					if prior_add[0].int() == 8 && prior_add[1].int() == 21 {
						target_shared = current_shared
						bias = prior_add[2].int()
						break
					}
				}
			}
			if target_shared >= 0 {
				publications << LayoutPublication{target_shared, load[2].int(), bias + offset}
				break
			}
		}
	}
	return sorted_publications(publications)
}

fn auxiliary_shared_publications(code []u8) []LayoutPublication {
	instructions := arm.words(code)
	mut publications := []LayoutPublication{}
	for index, instruction in instructions {
		source := fields('decode_ldr_x', instruction.word, big.zero_int) or { continue }
		if source[0].int() != 1 || source[1].int() != 19 { continue }
		for following_index := index + 1; following_index < int_min(index + 36, instructions.len); following_index++ {
			following := instructions[following_index]
			if next := fields('decode_ldr_x', following.word, big.zero_int) {
				if next[0].int() == 1 && next[1].int() == 19 { break }
			}
			store := fields('decode_str_x', following.word, big.zero_int) or { continue }
			if store[0].int() != 0 || store[1].int() != 8 { continue }
			for prior_index := following_index - 1; prior_index > index; prior_index-- {
				target := fields('decode_ldr_x', instructions[prior_index].word, big.zero_int) or { continue }
				if target[0].int() == 8 && target[1].int() == 19 && target[2].int() in [
					0xaa8,
					0xbd8,
				] {
					shared := if target[2].int() == 0xaa8 { 0xa98 } else { 0xbc8 }
					publications << LayoutPublication{shared, source[2].int(), 0x1c0 + store[2].int()}
					break
				}
			}
			break
		}
	}
	return sorted_publications(publications)
}

fn publications_hex(items []LayoutPublication) string {
	return '[' + items.map("('0x" + it.shared.hex() + "', '0x" + it.source.hex() + "', '0x" + it.offset.hex() + "')").join(', ') + ']'
}

struct LayoutAllocation {
	key   j.Value
	value j.Value
}

fn layout_allocation_map(allocations []j.Value) ![]LayoutAllocation {
	mut result := []LayoutAllocation{}
	for item in allocations {
		node := runtime_allocation_node(item)!
		key := command_field(node, 'host_gpu_member')!
		value := command_field(node, 'bytes')!
		match key {
			[]j.Value { return error("TypeError: unhashable type: 'list'") }
			map[string]j.Value { return error("TypeError: unhashable type: 'dict'") }
			else {}
		}
		mut found := false
		for index, entry in result {
			if event_values_equal(entry.key, key) {
				result[index] = LayoutAllocation{key, value}
				found = true
				break
			}
		}
		if !found { result << LayoutAllocation{key, value} }
	}
	return result
}

fn layout_allocation_get(items []LayoutAllocation, member int) j.Value {
	for item in items { if runtime_equal(item.key, member) { return item.value } }
	return j.Value(json2.null)
}

fn layout_render_publications(items []LayoutPublication, sizes []LayoutAllocation, shared int) []j.Value {
	mut result := []j.Value{}
	for item in items {
		if item.shared != shared { continue }
		mut row := {
			'shared_cpu_member': j.Value(item.shared)
			'source_gpu_member': j.Value(item.source)
			'shared_offset':     j.Value(item.offset)
		}
		for size in sizes {
			if runtime_equal(size.key, item.source) {
				row['source_bytes'] = size.value
				break
			}
		}
		result << expr(row)
	}
	return result
}

fn shared_data_layout(allocations []j.Value, shared_code []u8, base_code []u8) !j.Value {
	direct := direct_shared_publications(shared_code)
	expected_direct := sorted_publications([LayoutPublication{0xa98, 0x300, 0},
		LayoutPublication{0xa98, 0x338, 8}, LayoutPublication{0xa98, 0x340, 0x10},
		LayoutPublication{0xa98, 0xac0, 0x200}, LayoutPublication{0xa98, 0x308, 0x254},
		LayoutPublication{0xa98, 0x310, 0x25c}, LayoutPublication{0xa98, 0x318, 0x264},
		LayoutPublication{0xa98, 0x328, 0x26c}, LayoutPublication{0xa98, 0x330, 0x274},
		LayoutPublication{0xbc8, 0x300, 0}, LayoutPublication{0xbc8, 0x338, 8},
		LayoutPublication{0xbc8, 0x340, 0x10}, LayoutPublication{0xbc8, 0xbf0, 0x200},
		LayoutPublication{0xbc8, 0x320, 0x471}])
	if direct != expected_direct {
		return error('unexpected direct firmware-shared publications: ' + publications_hex(direct))
	}
	auxiliary := auxiliary_shared_publications(base_code)
	mut expected_auxiliary := []LayoutPublication{}
	for role, sources in [[0xb40, 0xb60, 0xb48, 0xb68, 0xb50, 0xb70, 0xb58, 0xb78],
		[0xc70, 0xc90, 0xc78, 0xc98, 0xc80, 0xca0, 0xc88, 0xca8]] {
		shared := if role == 0 { 0xa98 } else { 0xbc8 }
		for index, source in sources {
			expected_auxiliary << LayoutPublication{shared, source, 0x1c0 + index * 8}
		}
	}
	expected_auxiliary = sorted_publications(expected_auxiliary)
	if auxiliary != expected_auxiliary {
		return error('unexpected auxiliary firmware-shared publications: ' + publications_hex(auxiliary))
	}
	layout_seq(shared_code, 'conditional platform shared-address source')!
	layout_seq(shared_code, 'conditional platform shared-address pointer')!
	if !contains_words(shared_code, [u32(0xf9016aa0)]) {
		return error('missing conditional platform shared-address publication')
	}
	sizes := layout_allocation_map(allocations)!
	expected_sizes := {
		0x300: 0x2710
		0x308: 0xc18
		0x310: 0x1048
		0x318: 0xe10
		0x320: 0x11dd0
		0x328: 0x68
		0x330: 0x800
		0x338: 0
		0x340: 0x88
		0xac0: 0x79800
		0xbf0: 0x79800
		0xb40: 0x30
		0xb48: 0x1b0
		0xb50: 0x30
		0xb58: 0x30
		0xb60: 0x4800
		0xb68: 0x28800
		0xb70: 0x9000
		0xb78: 0x4800
		0xc70: 0x30
		0xc78: 0x1b0
		0xc80: 0x30
		0xc88: 0x30
		0xc90: 0x4800
		0xc98: 0x28800
		0xca0: 0x9000
		0xca8: 0x4800
	}
	mut mismatched := []string{}
	for member, expected in expected_sizes {
		actual := layout_allocation_get(sizes, member)
		if !runtime_equal(actual, expected) {
			representation := if actual is string {
				j.quoted(actual)
			} else {
				j.string_value(runtime_repr_value(actual))
			}
			mismatched << "('0x" + member.hex() + "', " + representation + ', ' + expected.str() + ')'
		}
	}
	if mismatched.len > 0 {
		return error('unexpected firmware-shared target allocations: [' + mismatched.join(', ') + ']')
	}
	mut roles := []j.Value{}
	for role in 0 .. 2 {
		shared := if role == 0 { 0xa98 } else { 0xbc8 }
		gpu := if role == 0 { 0xab8 } else { 0xbe8 }
		roles << expr({
			'role':                   j.Value(role)
			'shared_cpu_member':      j.Value(shared)
			'shared_gpu_member':      j.Value(gpu)
			'direct_publications':    j.Value(layout_render_publications(direct, sizes, shared))
			'auxiliary_publications': j.Value(layout_render_publications(auxiliary, sizes, shared))
		})
	}
	return expr({
		'bytes':                            j.Value(0x4c0)
		'roles':                            j.Value(roles)
		'conditional_platform_publication': expr({
			'host_platform_member': j.Value(0x298)
			'enabled_offset':       j.Value(0xf754)
			'pointer_offset':       j.Value(0x13768)
			'shared_cpu_member':    j.Value(0xa98)
			'shared_offset':        j.Value(0x2d0)
		})
	})
}
