module appleadt

import g17decode as g
import imageextract as image
import math.big
import encoding.hex
import math
import strconv
import traceanalysis as j

fn C.strtod(source &char, end &&char) f64

// Predicate operands use numeric equality rather than coercing strings or
// rounding large integers through binary64 at the JSON boundary.
fn unsigned_parameter(request map[string]j.Value, name string) ?u64 {
	value := j.value(request, name)
	match value {
		bool { return if value { u64(1) } else { u64(0) } }
		int, i64, u8, u32, u64 {
			if value.str().starts_with('-') { return none }
			return u64(value)
		}
		j.Number {
			if !value.text.contains_any('.eE') {
				return strconv.parse_uint(value.text, 10, 64) or { return none }
			}
			parsed := unsafe { C.strtod(&char(value.text.str), nil) }
			bits := math.f64_bits(parsed)
			if bits & 0x7fffffffffffffff == 0 { return u64(0) }
			if bits >> 63 != 0 { return none }
			exponent := int((bits >> 52) & 0x7ff) - 1023
			if exponent < 0 || exponent >= 64 { return none }
			significand := (bits & 0xfffffffffffff) | u64(1) << 52
			if exponent >= 52 { return significand << u32(exponent - 52) }
			shift := u32(52 - exponent)
			if significand & ((u64(1) << shift) - 1) != 0 { return none }
			return significand >> shift
		}
		else { return none }
	}
}

fn span_json(node NodeSpan) j.Value {
	mut properties := map[string]j.Value{}
	for name, property in node.properties {
		properties[name] = j.Value(map[string]j.Value{
			'start': j.Value(property.span.start)
			'end':   j.Value(property.span.end)
			'flags': j.Value(property.flags)
		})
	}
	mut children := []j.Value{}
	for child in node.children { children << span_json(child) }
	return j.Value(map[string]j.Value{
		'properties': j.Value(properties)
		'children':   j.Value(children)
	})
}

fn u64_values(values []u64) j.Value { return j.Value(values.map(j.Value(it))) }

fn expected_word(value j.Value) !u32 {
	match value {
		bool, int, i64, u8, u32, u64 {}
		j.Number {
			if value.text.contains_any('.eE') {
				return error('struct.error: required argument is not an integer')
			}
		}
		else { return error('struct.error: required argument is not an integer') }
	}
	number := g.integer(value)!
	if number.signum < 0 || number > big.integer_from_u64(~u64(0)) {
		return error('struct.error: argument out of range')
	}
	if number > big.integer_from_u64(0xffffffff) {
		return error("struct.error: 'I' format requires 0 <= number <= 4294967295")
	}
	return u32(strconv.parse_uint(number.str(), 10, 32)!)
}

fn expected_words(request map[string]j.Value) ![]u32 {
	mut result := []u32{}
	for value in j.value(request, 'expected').arr() { result << expected_word(value)! }
	return result
}

fn requested_ordered_words(code []u8, expected []j.Value) !bool {
	mut offset := 0
	for value in expected {
		offset = find_word(code, expected_word(value)!, offset) or { return false }
		offset += 4
	}
	return true
}

pub fn query(data []u8, operation string, request map[string]j.Value) !j.Value {
	field := j.string_value(j.value(request, 'field'))
	match operation {
		'decompress_device_tree' {
			return j.Value(hex.encode(decompress_request(data, j.value(request, 'initial_capacity'))!))
		}
		'parse_adt' { return span_json(parse_spans(data)!) }
		'device_tree_im4p_payload' {
			im4p := image.unwrap_im4p(data)!
			kind := data[im4p.image_type.start..im4p.image_type.end]
			if kind.bytestr() != 'dtre' {
				return error('not a DeviceTree IM4P (type=${image.bytes_repr(kind)})')
			}
			return j.Value(map[string]j.Value{
				'start': j.Value(im4p.payload.start)
				'end':   j.Value(im4p.payload.end)
			})
		}
		'decode_cstring' { return j.Value(decode_cstring(data, field)!) }
		'decode_string_list' { return j.Value(decode_string_list(data, field)!.map(j.Value(it))) }
		'decode_u32_array' { return j.Value(decode_u32_array(data, field)!.map(j.Value(it))) }
		'decode_integer' { return j.Value(decode_integer(data, field)!) }
		'parse_reg_regions' {
			mut result := []j.Value{}
			for region in parse_reg_regions(data, field)! {
				result << j.Value([j.Value(region.address), j.Value(region.bytes)])
			}
			return j.Value(result)
		}
		'parse_pmgr_devices' {
			mut result := []j.Value{}
			for device in parse_pmgr_devices(data)! {
				result << j.Value(map[string]j.Value{
					'index':             j.Value(device.index)
					'handle':            j.Value(u32(device.handle))
					'name':              j.Value(device.name)
					'flags':             j.Value(device.flags)
					'pmp_selector':      j.Value(device.pmp_selector)
					'pmp_virtual_class': j.Value(int(device.pmp_virtual_class))
				})
			}
			return j.Value(result)
		}
		'resolve_gate' {
			return j.Value(resolve_gate_values(j.value(request, 'handle'), j.value(request, 'devices').arr())!)
		}
		'parse_pmgr_interrupt_config' {
			return j.Value(parse_pmgr_interrupt_config(data, field)!.map(j.Value(it)))
		}
		'parse_pmp_soc_devices' { return j.Value(parse_pmp_soc_devices(data)!.map(j.Value(it))) }
		'parse_pmp_ptd_ranges' { return j.Value(parse_pmp_ptd_ranges(data)!.map(j.Value(it))) }
		'direct_branch_targets' {
			return u64_values(direct_branch_targets(j.value(request, 'function_address'), data))
		}
		'pc_relative_targets' {
			return u64_values(pc_relative_targets(j.value(request, 'function_address'), data))
		}
		'direct_branch_count' {
			return j.Value(direct_branch_count(j.value(request, 'function_address'), data, unsigned_parameter(request, 'target') or { return j.Value(0) }))
		}
		'direct_branch_target_at' {
			offset := g.integer(j.value(request, 'offset'))!
			if offset.signum < 0 || offset > big.integer_from_int(data.len - 4) {
				return j.value(map[string]j.Value{}, '')
			}
			return j.Value(direct_branch_target_at(j.value(request, 'function_address'), data, int(strconv.parse_int(offset.str(), 10, 64)!)) or { return j.value(map[string]j.Value{}, '') })
		}
		'_has_sub_cmp_window' {
			return j.Value(has_sub_cmp_window(data, int(unsigned_parameter(request, 'source') or { return j.Value(false) }), unsigned_parameter(request, 'first') or { return j.Value(false) }, unsigned_parameter(request, 'count') or { return j.Value(false) }))
		}
		'_has_cmp_w_immediate' {
			return j.Value(has_cmp_w_immediate(data, int(unsigned_parameter(request, 'source') or { return j.Value(false) }), unsigned_parameter(request, 'immediate') or { return j.Value(false) }))
		}
		'_has_ldrb' {
			return j.Value(has_ldrb(data, int(unsigned_parameter(request, 'destination') or { return j.Value(false) }), int(unsigned_parameter(request, 'base') or { return j.Value(false) }), unsigned_parameter(request, 'immediate') or { return j.Value(false) }))
		}
		'_has_words_in_order' { return j.Value(has_words_in_order(data, expected_words(request)!)) }
		'_has_ordered_words' {
			return j.Value(requested_ordered_words(data, j.value(request, 'expected').arr())!)
		}
		'align_up' {
			return j.Value(j.Number{image.align_up_integer(g.integer(j.value(request, 'value'))!, g.integer(j.value(request, 'alignment'))!).str()})
		}
		else { return error('unknown native Apple ADT operation ${operation}') }
	}
}
