module g17decode

import encoding.hex
import math.big
import strconv
import traceanalysis as j

fn param(request map[string]j.Value, name string, fallback int) !int {
	if name !in request { return fallback }
	value := j.value(request, name)
	if value is bool { return if value { 1 } else { 0 } }
	return int(strconv.parse_int(j.string_value(value), 10, 64)!)
}

fn requested_integer(request map[string]j.Value, name string) !big.Integer {
	return integer(j.value(request, name))
}

fn requested_code(request map[string]j.Value) ![]u8 {
	return hex.decode(j.string_value(j.value(request, 'code')))
}

fn requested_instructions(request map[string]j.Value) ![]Instruction {
	mut result := []Instruction{}
	for item in j.value(request, 'instructions').arr() {
		pair := item.arr()
		if pair.len != 2 { return error('instruction needs offset and word') }
		result << Instruction{int(strconv.parse_int(j.string_value(pair[0]), 10, 64)!), u32(wide_mask(integer(pair[1])!))}
	}
	return result
}

// Synchronous compatibility dispatch for remaining Python consumers. Native V
// recovery families call the public routines directly, without this JSON ABI.
pub fn query(data []u8, operation string, request map[string]j.Value) !j.Value {
	if operation.starts_with('decode_') && operation != 'decode_kernel_auth_rebase' {
		return decode(operation, u32(wide_mask(requested_integer(request, 'word')!)), j.value(request, 'address'))
	}
	match operation {
		'macho_uuid' { return macho_uuid(data)! }
		'macho_symbols' {
			mut symbols := map[string]j.Value{}
			for name, address in macho_symbols(data)! { symbols[name] = j.Value(address) }
			return j.Value(symbols)
		}
		'virtual_to_file' {
			return j.Value(j.Number{virtual_to_file(data, requested_integer(request, 'address')!)!.str()})
		}
		'symbol_code' {
			address, span := symbol_code_span(data, j.string_value(j.value(request, 'name')))!
			return tuple(j.Value(address), j.Value(span.start), j.Value(span.end))
		}
		'words' {
			mut result := []j.Value{}
			for item in words(data) { result << tuple(j.Value(item.offset), j.Value(item.word)) }
			return j.Value(result)
		}
		'find_materialized_constant' {
			return j.Value(find_materialized_constant(data, j.value(request, 'target')))
		}
		'resolve_static_w_register', 'resolve_static_x_register' {
			items := requested_instructions(request)!
			before := param(request, 'before', items.len)!
			register := param(request, 'register', 0)!
			depth := param(request, 'depth', 0)!
			if depth > 8 { return missing() }
			if before > items.len || before < -items.len {
				return error('IndexError: list index out of range')
			}
			if before <= 0 { return missing() }
			if operation == 'resolve_static_w_register' {
				return j.Value(resolve_static_w_register(items, before, register, depth) or { return missing() })
			}
			return j.Value(resolve_static_x_register(items, before, register, depth) or { return missing() })
		}
		'g17_register_is_written' {
			return j.Value(register_is_written(u32(wide_mask(requested_integer(request, 'word')!)), param(request, 'register', 0)!))
		}
		'stores_covering' {
			mut result := []j.Value{}
			target := requested_integer(request, 'target')!
			for store in store_spans(data) {
				if store.base == param(request, 'base', 0)! && big.integer_from_int(store.low) <= target && target < big.integer_from_int(store.low + store.bytes) {
					result << j.Value(store.site)
				}
			}
			return j.Value(result)
		}
		'stores_covering_any' {
			mut targets := []i64{}
			for value in j.value(request, 'targets').arr() {
				target := integer(value)!
				if target >= big.integer_from_int(-1024) && target <= big.integer_from_int(65536) {
					targets << strconv.parse_int(target.str(), 10, 64)!
				}
			}
			return j.Value(stores_covering_any(data, targets))
		}
		'read_adrp_add_address' {
			return j.Value(read_adrp_add_address(j.value(request, 'function_address'), data, param(request, 'adrp_offset', 0)!, param(request, 'add_offset', 0)!)!)
		}
		'read_adrp_add_cstring' {
			return j.Value(read_adrp_add_cstring(data, j.value(request, 'function_address'), requested_code(request)!, param(request, 'adrp_offset', 0)!, param(request, 'add_offset', 0)!)!)
		}
		'read_virtual_u32_table' {
			mut result := []j.Value{}
			for value in read_virtual_u32_table(data, requested_integer(request, 'address')!, requested_integer(request, 'count')!)! {
				result << j.Value(value)
			}
			return j.Value(result)
		}
		'read_adrp_load' {
			span := read_adrp_load(data, j.value(request, 'function_address'), requested_code(request)!, param(request, 'adrp_offset', 0)!, param(request, 'load_offset', 0)!, param(request, 'expected_width', 0)!)!
			return tuple(j.Value(span.start), j.Value(span.end))
		}
		'decode_kernel_auth_rebase' {
			return j.Value(decode_kernel_auth_rebase(j.value(request, 'raw'))!)
		}
		'recover_vtable_target' {
			return j.Value(recover_vtable_target(data, j.string_value(j.value(request, 'vtable_name')), requested_integer(request, 'slot')!)!)
		}
		'require_instruction_sequence' {
			mut sequence := []u32{}
			for value in j.value(request, 'sequence').arr() {
				word := integer(value)!
				if word.signum < 0 || word > big.integer_from_u64(0xffffffff) {
					return error("struct.error: 'I' format requires 0 <= number <= 4294967295")
				}
				sequence << u32(wide_mask(word))
			}
			require_instruction_sequence(data, j.string_value(j.value(request, 'label')), sequence)!
			return missing()
		}
		'require_instruction_words_at' {
			// An ordered array preserves Python dict insertion order even on
			// hosts whose native map iteration order differs.
			for item in j.value(request, 'expected').arr() {
				pair := item.arr()
				offset := int(strconv.parse_int(j.string_value(pair[0]), 10, 64)!)
				wanted := integer(pair[1])!
				if wanted.signum < 0 || wanted > big.integer_from_u64(0xffffffff) {
					actual := word_at(data, offset)!
					label := j.string_value(j.value(request, 'label'))
					return error('unexpected ${label} instruction at ${hex_integer(big.integer_from_int(offset))}: 0x${actual:08x}, expected ${hex_integer(wanted)}')
				}
				require_instruction_words_at(data, j.string_value(j.value(request, 'label')), {
					offset: u32(wide_mask(wanted))
				})!
			}
			return missing()
		}
		'find_authenticated_target_references' {
			mut result := []j.Value{}
			for offset in find_authenticated_target_references(data, j.value(request, 'target')) {
				result << j.Value(offset)
			}
			return j.Value(result)
		}
		'utf8_replace' { return j.Value(utf8_replace(data)) }
		else { return error('unknown native G17 recovery operation ${operation}') }
	}
}
