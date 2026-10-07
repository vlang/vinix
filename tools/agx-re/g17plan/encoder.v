module g17plan

import traceanalysis { Value }
import json2
import math.big
import strconv

pub fn scalar(item Value, name string) !u64 {
	mut number := big.zero_int
	match item {
		string {
			number = signed_string_integer(item, name) or { return error('${name} is not an integer: ${repr(item)}') }
		}
		else { number = big.integer_from_string(integer_text(item, name)!)! }
	}
	if number < big.zero_int || number > big.integer_from_u64(word_mask) {
		return error('${name} is outside u64')
	}
	return strconv.parse_uint(number.str(), 10, 64)!
}

fn offset_map(item Value, name string) !map[string]Value {
	mut output := map[string]Value{}
	match item {
		json2.Null { return output }
		map[string]Value {
			record := item.as_map()
			for key, entry in record {
				offset_big := signed_string_integer(key, 'offset') or { return error('invalid external ${name} offset ${repr(Value(key))}') }
				offset := offset_big.str()
				if offset_big < big.zero_int || offset in output {
					label := if offset_big < big.zero_int {
						'-0x' + offset_big.abs().hex()
					} else {
						'0x' + offset_big.hex()
					}
					return error('invalid duplicate external ${name} offset ${label}')
				}
				output[offset] = entry
			}
		}
		else { return error('external ${name} must be an object') }
	}
	return output
}

fn per_pass(item Value, index int, passes int, name string) !Value {
	return match item {
		[]Value {
			if item.len != passes { return error('${name} needs exactly ${passes} pass values') }
			item[index]
		}
		else { item }
	}
}

fn overrides(values map[string]Value, index int, passes int) !map[int]bool {
	mut output := map[int]bool{}
	for offset, item in values {
		number := big.integer_from_string(offset)!
		label := '0x' + number.hex()
		value := per_pass(item, index, passes, 'decision ${label}')!
		taken := match value {
			string {
				if value !in ['taken', 'fallthrough'] {
					return error('decision ${label} must be taken or fallthrough')
				}
				value == 'taken'
			}
			bool { value }
			else { return error('decision ${label} must be boolean, taken, or fallthrough') }
		}
		// Keys outside the recovered offset domain remain valid external metadata,
		// but cannot match a graph event. Never narrow them into a matching key.
		if number <= big.integer_from_u64(0x7fffffffffffffff) {
			output[int(strconv.parse_int(offset, 10, 64)!)] = taken
		}
	}
	return output
}

fn external_value(values map[string]Value, offset int, index int, passes int, reason string) !u64 {
	item := values[offset.str()] or { return error('event ${hex_offset(offset)} needs an explicit external value: ${reason}') }
	return scalar(per_pass(item, index, passes, 'event ${hex_offset(offset)}')!, 'event ${hex_offset(offset)} value')
}

fn write(mut buffer []u8, offset int, bytes int, value u64) ! {
	if offset < 0 || bytes < 0 || offset > buffer.len - bytes {
		return error('write [${hex_offset(offset)}, ${hex_sum(offset, bytes)}) is outside a 0x${buffer.len:x}-byte buffer')
	}
	if bytes < 8 && value > mask_bits(bytes * 8) { return error('int too big to convert') }
	for i in 0 .. bytes { buffer[offset + i] = u8(value >> (i * 8)) }
}

pub struct Encoded {
pub:
	command    []u8
	descriptor []u8
	plan       map[string]Value
}

pub fn encode_3d(abi map[string]Value, descriptor_input []u8, gpu u64, template ?[]u8, externals Value) !Encoded {
	channels := required_obj(abi, 'channels')!
	layout := required_obj(channels, 'command_3d_register_lists')!
	codec := required_obj(channels, 'register_entry_codec')!
	bytes := field(layout, 'command_bytes', 'command bytes')!
	if descriptor_input.len < descriptor_bytes {
		return error('descriptor has 0x${descriptor_input.len:x} bytes; need 0x${descriptor_bytes:x}')
	}
	if gpu == 0 { return error('command GPU address must be a nonzero u64') }
	mut command := []u8{len: bytes}
	zero_template := template == none
	if input := template {
		if input.len < bytes {
			return error('template has 0x${input.len:x} bytes; need 0x${bytes:x}')
		}
		command = input[..bytes].clone()
	}
	mut descriptor := descriptor_input[..descriptor_bytes].clone()
	external_inputs := if !truth(externals) {
		map[string]Value{}
	} else {
		match externals {
			map[string]Value { externals.as_map() }
			else { return error('external input must be a JSON object') }
		}
	}
	decisions := offset_map(val(external_inputs, 'decisions'), 'decisions')!
	values := offset_map(val(external_inputs, 'values'), 'values')!
	raw_hardware := val(external_inputs, 'hardware')
	mut hardware := map[string]u64{}
	if truth(raw_hardware) {
		match raw_hardware {
			map[string]Value {
				for name, entry in raw_hardware { hardware[name] = scalar(entry, name)! }
			}
			else { return error('hardware inputs must be a JSON object') }
		}
	}
	folded := fold_accelerator_inputs(abi, hardware)!
	passes := field(layout, 'passes', 'register passes')!
	stride := field(layout, 'stride', 'register stride')!
	stream := field(layout, 'stream_offset', 'stream offset')!
	capacity := field(layout, 'stream_bytes', 'stream bytes')!
	address := field(layout, 'gpu_address_offset', 'GPU address offset')!
	count := field(layout, 'entry_count_offset', 'entry count offset')!
	length := field(layout, 'byte_length_offset', 'byte length offset')!
	entry_bytes := field(layout, 'entry_bytes', 'entry bytes')!
	summary := required_obj(layout, 'descriptor_summary')!
	selector_mask := masked_integer(required(codec, 'selector_mask')!, 'selector mask')!
	mode_mask := masked_integer(required(codec, 'mode_mask')!, 'mode mask')!
	template_mask := masked_integer(required(codec, 'preserved_template_mask')!, 'template mask')!
	value_offset := field(codec, 'value_offset', 'value offset')!
	events := catalog(folded, '3D')!
	mut paths := []Value{}
	mut external_events := []int{}
	for pass_index in 0 .. passes {
		path := derive_path(folded, descriptor, command, overrides(decisions, pass_index, passes)!)!
		byte_length := path.len * entry_bytes
		if byte_length > capacity || path.len > 0xffff {
			return error('pass ${pass_index}: recovered path needs 0x${byte_length:x} stream bytes')
		}
		base := pass_index * stride
		stream_gpu := gpu + u64(base + stream)
		if stream_gpu < gpu { return error('pass ${pass_index}: stream GPU address overflows') }
		write(mut command, base + address, 8, stream_gpu)!
		write(mut command, base + count, 2, u64(path.len))!
		write(mut command, base + length, 2, u64(byte_length))!
		summary_offset := field(summary, 'offset', 'summary offset')! + pass_index * field(summary, 'stride', 'summary stride')!
		write(mut descriptor, summary_offset, 8, stream_gpu)!
		write(mut descriptor, summary_offset + 8, 2, u64(path.len))!
		write(mut descriptor, summary_offset + 10, 6, 0)!
		for index, offset in path {
			event := events[offset]
			value := evaluate(required(event, 'value_source')!, descriptor, command) or {
				if err.code() != unresolved_code { return err }
				external_value_result := external_value(values, offset, pass_index, passes, err.msg())!
				if offset !in external_events { external_events << offset }
				external_value_result
			}
			entry_offset := base + stream + index * entry_bytes
			selector := (load(command, entry_offset, 4, false)! & template_mask) | (masked_integer(val(event, 'selector'), 'selector')! & selector_mask) | (masked_integer(val(event, 'mode'), 'mode')! & mode_mask)
			write(mut command, entry_offset, 4, selector)!
			write(mut command, entry_offset + value_offset, 8, value)!
		}
		paths << Value(number_array(path))
	}
	mut plan := compile_plan(folded, command, descriptor, gpu)!
	external_events.sort()
	plan['encoder'] = map[string]Value{
		'kind':                   Value('recovered-host-reference')
		'zero_template':          Value(zero_template)
		'external_event_offsets': Value(number_array(external_events))
		'paths':                  Value(paths)
	}
	return Encoded{command, descriptor, plan}
}
