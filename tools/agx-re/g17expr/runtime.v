module g17expr

import encoding.binary
import encoding.hex
import g17decode as arm
import math.big
import json2
import traceanalysis as j
import g17power as power

#include <stdlib.h>

fn C.strtod(text &char, end &&char) f64

fn runtime_handles(operation string) bool {
	return operation in ['find_direct_symbol_callers', 'recover_g17_bootstrap_roots',
		'recover_g17_constant_virtual_returns', 'recover_g17_memory_map_virtual_address',
		'recover_g17_init_sequence_provider', 'recover_g17_platform_config',
		'recover_g17_brn_workaround_table', 'recover_g17_bootstrap_region',
		'recover_g17_small_shared_data', 'recover_g17_runtime_controls',
		'recover_g17_runtime_initialization', 'recover_g17_runtime_power_policy',
		'recover_g17_runtime_performance_policy', 'recover_g17_runtime_platform_policy',
		'recover_g17_shared_platform_values', 'recover_g17_zero_initialized_allocations',
		'recover_g17_role0_bootstrap_regions', 'recover_g17_pio_mappings', 'recover_g17_pio_uat_mapping',
		'recover_g17_address_space_layout', 'recover_g17_color_matrices',
		'recover_g17_hardware_config_constants', 'recover_g17_setup_config_constants',
		'recover_g17_chip_info', 'recover_g17_power_sample_period', 'recover_g17_default_mcache_writes',
		'recover_g17_enabled_usc_config', 'recover_g17_uat_config_flag', 'recover_g17_gptbat_base',
		'recover_g17_gpu_identity_config', 'recover_g17_feature_defaults']
}

fn runtime_bytes(request map[string]j.Value, key string) ![]u8 {
	value := command_field(request, key)!
	return match value {
		string { hex.decode(value)! }
		map[string]j.Value { hex.decode(text(value, 'bytes_hex'))! }
		else { return error('TypeError: code must be bytes') }
	}
}

fn runtime_names(names []string) []string { return names.map(runtime_symbol(it)) }

fn runtime_check(code []u8, label string) ! {
	arm.require_instruction_words_at(code, label, runtime_words(label))!
}

fn runtime_seq(code []u8, label string) ! {
	arm.require_instruction_sequence(code, label, runtime_sequence(label))!
}

fn runtime_proof_steps(operation string, codes map[string][]u8) ! {
	for step in runtime_proofs(operation) {
		code := codes[step[2]] or { return error('missing code ' + step[2]) }
		if step[0] == 'require_instruction_sequence' {
			runtime_seq(code, step[1])!
		} else {
			runtime_check(code, step[1])!
		}
	}
}

fn encoded_words(words []u32) []u8 {
	mut data := []u8{len: words.len * 4}
	for index, word in words {
		binary.little_endian_put_u32(mut data[index * 4..index * 4 + 4], word)
	}
	return data
}

fn byte_count(data []u8, sequence []u8) int {
	mut count := 0
	for position := 0; position <= data.len - sequence.len; {
		if data[position..position + sequence.len] == sequence {
			count++
			position += sequence.len
		} else {
			position++
		}
	}
	return count
}

fn contains_words(data []u8, sequence []u32) bool {
	return byte_count(data, encoded_words(sequence)) > 0
}

fn runtime_allocation_size(allocations []j.Value) ! {
	mut size := j.Value(json2.null)
	for item in allocations {
		node := runtime_allocation_node(item)!
		if !runtime_equal(command_field(node, 'host_cpu_member')!, 0x380) { continue }
		if !runtime_equal(command_field(node, 'host_gpu_member')!, 0x388) { continue }
		size = command_field(node, 'bytes')!
		break
	}
	if runtime_equal(size, 0x1ca0) { return }
	return error('unexpected G17 runtime-data allocation size: ' + j.string_value(runtime_repr_value(size)))
}

fn runtime_repr_value(value j.Value) j.Value {
	return match value {
		j.Number {
			j.Value(j.Number{match value.text {
				'NaN' { 'nan' }
				'Infinity' { 'inf' }
				'-Infinity' { '-inf' }
				else { value.text }
			}})
		}
		[]j.Value {
			mut items := []j.Value{}
			for item in value { items << runtime_repr_value(item) }
			j.Value(items)
		}
		map[string]j.Value {
			mut items := map[string]j.Value{}
			for key, item in value { items[key] = runtime_repr_value(item) }
			expr(items)
		}
		else { value }
	}
}

fn runtime_allocations(request map[string]j.Value) ![]j.Value {
	if 'allocations_text' in request {
		return runtime_allocation_items(power.decode_device_json(text(request, 'allocations_text'))!)
	}
	return runtime_allocation_items(at(request, 'allocations'))
}

fn runtime_allocation_type(value j.Value) string {
	return match value {
		json2.Null { 'NoneType' }
		bool { 'bool' }
		j.Number {
			if value.text.contains_any('.eE') || value.text in ['NaN', 'Infinity', '-Infinity'] {
				'float'
			} else {
				'int'
			}
		}
		int, i64, u8, u32, u64 { 'int' }
		else { 'object' }
	}
}

fn runtime_allocation_node(value j.Value) !map[string]j.Value {
	return match value {
		map[string]j.Value { value }
		[]j.Value { return error('TypeError: list indices must be integers or slices, not str') }
		string { return error('TypeError: string indices must be integers') }
		else {
			return error("TypeError: '" + runtime_allocation_type(value) + "' object is not subscriptable")
		}
	}
}

fn runtime_allocation_items(value j.Value) ![]j.Value {
	return match value {
		[]j.Value { value }
		map[string]j.Value {
			mut items := []j.Value{}
			for key, _ in value { items << j.Value(key) }
			items
		}
		string {
			mut items := []j.Value{}
			for character in value.runes() { items << j.Value(character.str()) }
			items
		}
		else {
			return error("TypeError: '" + runtime_allocation_type(value) + "' object is not iterable")
		}
	}
}

// Equality with these small, exact layout integers follows Python numeric
// equality; strings are distinct and fractional floats are not truncated.
fn runtime_equal(value j.Value, expected int) bool {
	return match value {
		bool { expected == if value { 1 } else { 0 } }
		j.Number {
			if value.text.contains_any('.eE') || value.text in ['NaN', 'Infinity', '-Infinity'] {
				text := value.text.clone()
				unsafe { C.strtod(&char(text.str), nil) } == f64(expected)
			} else {
				(big.integer_from_string(value.text) or { return false }) == big.integer_from_int(expected)
			}
		}
		int, i64, u8, u32, u64 {
			(big.integer_from_string(value.str()) or { return false }) == big.integer_from_int(expected)
		}
		else { false }
	}
}

fn (image CommandImage) literal(address big.Integer, code []u8, adrp int, load int, width int, request map[string]j.Value, key string) ![]u8 {
	if image.fixture {
		options := at(request, key + '_fixture').as_map()
		loads := at(options, 'adrp_load').as_map()
		name := '${address.str()}:${adrp}:${load}:${width}'
		return hex.decode(j.string_value(loads[name] or { return error('KeyError: ' + name) }))!
	}
	span := arm.read_adrp_load(image.bytes, scalar(address), code, adrp, load, width)!
	return image.bytes[span.start..span.end]
}

fn runtime_query(data []u8, operation string, request map[string]j.Value) !j.Value {
	if operation == 'find_direct_symbol_callers' {
		return j.Value(runtime_direct_callers(data, at(request, 'target'))!.map(j.Value(it)))
	}
	if operation == 'recover_g17_bootstrap_roots' { return expr(bootstrap_roots(request)!) }
	if operation == 'recover_g17_small_shared_data' { return expr(small_shared_data(request)!) }
	if operation == 'recover_g17_runtime_controls' { return expr(runtime_controls(request)!) }
	if operation in ['recover_g17_bootstrap_region', 'recover_g17_runtime_initialization',
		'recover_g17_runtime_performance_policy', 'recover_g17_zero_initialized_allocations',
		'recover_g17_role0_bootstrap_regions', 'recover_g17_setup_config_constants'] {
		if operation == 'recover_g17_bootstrap_region' && runtime_bytes(request, 'page_shift_code')! != encoded_words([
			u32(0xd503245f),
			0x528001c0,
			0xd65f03c0,
		]) {
			return error('G17 firmware page shift is not the checked 14-bit value')
		}
		if operation == 'recover_g17_runtime_initialization' {
			runtime_allocation_size(runtime_allocations(request)!)!
		}
		mut codes := map[string][]u8{}
		for step in runtime_proofs(operation) { codes[step[2]] = runtime_bytes(request, step[2])! }
		runtime_proof_steps(operation, codes)!
		return runtime_metadata(operation)
	}
	key := if 'driver_fixture' in request { 'driver' } else { 'image' }
	image := command_image(data, request, key)!
	return expr(runtime_image_contract(image, operation, request, key)!)
}
