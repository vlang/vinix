module g17expr

import encoding.hex
import json2
import math.big
import strconv
import g17decode as arm
import traceanalysis as j

pub struct FixtureCode {
pub:
	address u64
	bytes   []u8
}

pub struct FixtureImage {
pub:
	entries map[string]u64
	codes   map[string]FixtureCode
}

pub fn (source FixtureImage) symbols() !map[string]u64 { return source.entries }

pub fn (source FixtureImage) code(name string) !(u64, []u8) {
	code := source.codes[name] or { return error('KeyError: ${name}') }
	return code.address, code.bytes
}

fn request_int(request map[string]j.Value, key string, fallback int) !int {
	if key !in request { return fallback }
	value := arm.integer(j.value(request, key))!
	bound := big.integer_from_string('4611686018427387904')!
	if value > bound { return int(u64(1) << 62) }
	if value < big.zero_int - bound { return -int(u64(1) << 62) }
	return int(strconv.parse_int(value.str(), 10, 64)!)
}

fn request_instructions(request map[string]j.Value) ![]Instruction {
	mut result := []Instruction{}
	for item in j.value(request, 'instructions').arr() {
		pair := item.arr()
		if pair.len != 2 { return error('instruction needs offset and word') }
		result << Instruction{ offset: arm.integer(pair[0])!, word: request_word(pair[1])!, exact_word: arm.integer(pair[1])! == big.integer_from_u64(request_word(pair[1])!), full_word: arm.integer(pair[1])! }
	}
	return result
}

pub fn fixture_image(request map[string]j.Value) !FixtureImage {
	mut entries := map[string]u64{}
	for name, address in j.value(request, 'symbols').as_map() { entries[name] = address.u64() }
	mut codes := map[string]FixtureCode{}
	for name, value in j.value(request, 'codes').as_map() {
		code := value.as_map()
		codes[name] = FixtureCode{j.value(code, 'address').u64(), hex.decode(j.string_value(j.value(code, 'code')))!}
	}
	return FixtureImage{entries, codes}
}

pub fn handles(operation string) bool {
	return operation == 'public_constants' || operation == 'recover_g17_report' || legacy_handles(operation) || operation in ['census_g17_member_writes', 'census_g17_code_member_writes'] || layout_handles(operation) || event_handles(operation) || command_handles(operation) || runtime_handles(operation) || config_handles(operation) || operation in [
		'find_dominating_g17_register_write',
		'g17_definition_dominates_use',
		'trace_g17_known_call_return',
		'trace_g17_stack_load',
		'trace_g17_register_copy',
		'trace_g17_condition_expression',
		'trace_g17_four_way_compare_merge',
		'trace_g17_optional_bit_set_merge',
		'trace_g17_cl_base_merge',
		'trace_g17_cl_mode_bit_merge',
		'trace_g17_control_flow_merge',
		'trace_g17_value_expression',
		'classify_g17_value_argument',
		'recover_g17_register_selectors',
		'recover_g17_inline_register_records',
	]
}

// This JSON entrypoint preserves the remaining Python callers while recovery
// algorithms and native tests use typed instructions and image providers.
pub fn query(data []u8, operation string, request map[string]j.Value) !j.Value {
	if operation == 'public_constants' { return public_constant_manifest() }
	if operation == 'recover_g17_report' { return controller_report(data, request) }
	if legacy_handles(operation) { return legacy_query(data, operation, request) }
	if operation in ['census_g17_member_writes', 'census_g17_code_member_writes'] { return census_query(data, operation, request) }
	if layout_handles(operation) { return layout_query(data, operation, request) }
	if event_handles(operation) { return event_query(data, operation, request) }
	if config_handles(operation) { return config_query(data, operation, request) }
	if runtime_handles(operation) { return runtime_query(data, operation, request) }
	if command_handles(operation) { return command_query(data, operation, request) }
	if operation == 'recover_g17_register_selectors' || operation == 'recover_g17_inline_register_records' {
		if 'symbols' in request {
			source := fixture_image(request)!
			return j.Value(if operation == 'recover_g17_register_selectors' {
				register_selectors_with_source(source)!
			} else {
				inline_register_records_with_source(source)!
			})
		}
		return j.Value(if operation == 'recover_g17_register_selectors' {
			register_selectors(data)!
		} else {
			inline_register_records(data)!
		})
	}
	instructions := request_instructions(request)!
	use_index := request_int(request, 'use_index', instructions.len)!
	register := request_int(request, 'register', 4)!
	depth := request_int(request, 'depth', 0)!
	mut seen := []Visit{}
	for item in j.value(request, 'seen').arr() {
		pair := item.arr()
		seen_use := arm.integer(pair[0])!
		seen_register := arm.integer(pair[1])!
		if operation == 'trace_g17_value_expression' && seen_use == request_big(request, 'use_index', instructions.len)! && seen_register == request_big(request, 'register', 4)! {
			return j.Value(json2.null)
		}
		bound := big.integer_from_string('4611686018427387904')!
		if seen_use > bound || seen_use < big.zero_int - bound || seen_register > bound || seen_register < big.zero_int - bound {
			continue
		}
		seen << Visit{int(strconv.parse_int(seen_use.str(), 10, 64)!), int(strconv.parse_int(seen_register.str(), 10, 64)!)}
	}
	if use_index > instructions.len && operation != 'g17_definition_dominates_use' {
		if operation == 'trace_g17_value_expression' && depth > max_expression_depth {
			return j.Value(json2.null)
		}
		return index_error(request, 'use_index')
	}
	match operation {
		'rank_static_w', 'rank_static_x' {
			before := request_int(request, 'before', instructions.len)!
			if depth > 8 { return j.Value(json2.null) }
			if before > instructions.len || (operation == 'rank_static_w' && before < -instructions.len) {
				return error('IndexError: list index out of range')
			}
			if before <= 0 { return j.Value(json2.null) }
			if operation == 'rank_static_w' {
				if result := static_w_register(instructions, before, register, depth) {
					return j.Value(result)
				}
			} else {
				if result := static_x_register(instructions, before, register, depth) {
					return j.Value(result)
				}
			}
			return j.Value(json2.null)
		}
		'find_dominating_g17_register_write' {
			if index := find_dominating_register_write(instructions, use_index, register) {
				return j.Value(index)
			}
			return j.Value(json2.null)
		}
		'g17_definition_dominates_use' {
			definition := request_int(request, 'definition_index', 0)!
			if definition >= instructions.len || definition < -instructions.len || instructions.len == 0 || use_index < -instructions.len {
				return error('IndexError: list index out of range')
			}
			return j.Value(definition_dominates_use(instructions, definition, use_index))
		}
		'trace_g17_known_call_return' {
			return optional_expression(known_call_return(instructions, use_index, depth, seen))
		}
		'trace_g17_stack_load' {
			load_index := request_int(request, 'load_index', use_index)!
			if load_index > instructions.len { return error('IndexError: list index out of range') }
			if load_index == instructions.len {
				mut augmented := instructions.clone()
				augmented << Instruction{
					offset: if instructions.len > 0 {
						instructions.last().offset + big.integer_from_int(4)
					} else {
						big.zero_int
					}
					word:   0xd503201f
				}
				if _ := stack_load(augmented, load_index, request_big(request, 'member', 0)!, request_big(request, 'width', 8)!, depth, seen) {
					return error('IndexError: list index out of range')
				}
				return j.Value(json2.null)
			}
			return optional_expression(stack_load(instructions, load_index, request_big(request, 'member', 0)!, request_big(request, 'width', 8)!, depth, seen))
		}
		'trace_g17_register_copy' {
			copy_index := request_int(request, 'copy_index', use_index)!
			source := request_int(request, 'source', register)!
			if source >= 19 && source <= 28 && copy_index >= instructions.len {
				if copy_index > instructions.len {
					return error('IndexError: list index out of range')
				}
				if _ := find_dominating_register_write(instructions, copy_index, source) {
					return error('IndexError: list index out of range')
				}
				return j.Value(json2.null)
			}
			return optional_expression(register_copy(instructions, copy_index, source))
		}
		'trace_g17_condition_expression' {
			if use_index == instructions.len && instructions.any(flags_set(it.word)) {
				return error('IndexError: list index out of range')
			}
			return optional_expression(condition_expression(instructions, use_index, depth, seen))
		}
		'trace_g17_four_way_compare_merge' {
			return optional_expression(four_way_compare_merge(instructions, use_index, register, depth, seen))
		}
		'trace_g17_optional_bit_set_merge' {
			return optional_expression(optional_bit_set_merge(instructions, use_index, register, depth, seen))
		}
		'trace_g17_cl_base_merge' {
			return optional_expression(cl_base_merge(instructions, use_index, register, depth, seen))
		}
		'trace_g17_cl_mode_bit_merge' {
			return optional_expression(cl_mode_bit_merge(instructions, use_index, register, depth, seen))
		}
		'trace_g17_control_flow_merge' {
			return optional_expression(control_flow_merge(instructions, use_index, register, depth, seen))
		}
		'trace_g17_value_expression' {
			return optional_expression(value_expression(instructions, use_index, register, depth, seen))
		}
		'classify_g17_value_argument' {
			before := request_int(request, 'before', use_index)!
			if before > instructions.len { return error('IndexError: list index out of range') }
			return j.Value(classify_value_argument(instructions, before, register)!)
		}
		else { return error('unknown G17 expression operation ${operation}') }
	}
}

fn request_word(value j.Value) !u32 {
	modulus := big.integer_from_u64(0x100000000)
	mut reduced := arm.integer(value)! % modulus
	if reduced.signum < 0 { reduced += modulus }
	return u32(strconv.parse_uint(reduced.str(), 10, 64)!)
}

fn request_big(request map[string]j.Value, key string, fallback int) !big.Integer {
	if key !in request { return big.integer_from_int(fallback) }
	return arm.integer(j.value(request, key))
}

fn index_error(request map[string]j.Value, key string) IError {
	value := request_big(request, key, 0) or { return error(err.msg()) }
	maximum := big.integer_from_string('9223372036854775808') or { panic(err) }
	if value > maximum { return error("IndexError: cannot fit 'int' into an index-sized integer") }
	return error('IndexError: list index out of range')
}
