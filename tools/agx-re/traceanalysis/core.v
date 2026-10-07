module traceanalysis

import encoding.binary
import encoding.hex
import json2
import math.big
import os
import strconv

#include <stdlib.h>

fn C.strtod(source &char, end &&char) f64

pub const segment_header_bytes = 8
pub const record_header_bytes = 0xc0
pub const payload_length_offset = 0x9c
pub const primary_extension_length_offset = 0x90
pub const primary_extension_header_bytes = 0x10
pub const render_payload_bytes = 0x9d0
pub const pointer_bytes = 8
pub const pointer_scan_alignment = 4

// A raw number preserves JSON's integer/float distinction and every integer
// bit. Decoding into json2.Any would choose f64 and round GPU addresses.
pub struct Number {
pub mut:
	text string
}

pub fn (mut number Number) from_json_number(raw string) ! {
	number.text = raw
}

pub fn (number Number) to_json() string {
	return number.text
}

pub type Value = Number
	| []Value
	| bool
	| i64
	| int
	| json2.Null
	| map[string]Value
	| string
	| u8
	| u32
	| u64
pub type Object = map[string]Value

pub fn (item Value) u64() u64 {
	return match item {
		Number { strconv.parse_uint(item.text, 10, 64) or { 0 } }
		i64, int, u8, u32, u64 { u64(item) }
		else { u64(0) }
	}
}

pub fn (item Value) int() int { return int(item.u64()) }

pub fn (item Value) u8() u8 { return u8(item.u64()) }

pub fn (item Value) arr() []Value {
	if item is []Value { return item }
	return []Value{}
}

pub fn (item Value) as_map() Object {
	if item is map[string]Value { return item }
	return map[string]Value{}
}

pub fn decode(source string) !Value {
	return json2.decode[Value](source)
}

// Encode the dynamic schema directly. json2's generic sum-type encoder adds a
// `_type` field for struct alternatives; a raw JSON Number is a scalar.
pub fn encode(item Value, pretty bool) string {
	return encode_depth(item, pretty, 0)
}

fn encode_depth(item Value, pretty bool, depth int) string {
	match item {
		Number { return item.text }
		json2.Null { return 'null' }
		[]Value {
			mut values := []string{}
			for entry in item { values << encode_depth(entry, pretty, depth + 1) }
			if !pretty || values.len == 0 { return '[' + values.join(',') + ']' }
			padding := '  '.repeat(depth + 1)
			return '[\n' + padding + values.join(',\n' + padding) + '\n' + '  '.repeat(depth) + ']'
		}
		map[string]Value {
			mut values := []string{}
			separator := if pretty { ': ' } else { ':' }
			for key, entry in item {
				values << json2.encode(key) + separator + encode_depth(entry, pretty, depth + 1)
			}
			if !pretty || values.len == 0 { return '{' + values.join(',') + '}' }
			padding := '  '.repeat(depth + 1)
			return '{\n' + padding + values.join(',\n' + padding) + '\n' + '  '.repeat(depth) + '}'
		}
		else { return json2.encode(item) }
	}
}

pub fn number_hex(item Value) string {
	number := integer(item, 'number') or { return '0' }
	return number.hex()
}

pub fn value(record map[string]Value, key string) Value {
	return record[key] or { Value(json2.null) }
}

pub fn string_value(item Value) string {
	if item is string { return item }
	return python_repr(item)
}

fn python_repr(item Value) string {
	return match item {
		string { quoted(item) }
		Number { number_text(item.text) }
		i64, int, u8, u32, u64 { item.str() }
		bool {
			if item { 'True' } else { 'False' }
		}
		json2.Null { 'None' }
		[]Value {
			'[' + item.map(python_repr(it)).join(', ') + ']'
		}
		map[string]Value {
			mut entries := []string{}
			for key, entry in item { entries << '${quoted(key)}: ${python_repr(entry)}' }
			'{' + entries.join(', ') + '}'
		}
	}
}

fn number_text(text string) string {
	if !text.contains_any('.eE') {
		return (big.integer_from_string(text) or { return text }).str()
	}
	// libc rounds the full decimal token to nearest binary64. atof64's fast
	// exponent path can produce an adjacent value for these trace filters.
	terminated := text.clone()
	parsed := unsafe { C.strtod(&char(terminated.str), nil) }
	shortest := parsed.str()
	if shortest == '+inf' { return 'inf' }
	// V and Python both use shortest round-trip decimal digits. Python keeps
	// fixed notation for positive exponents below 16; V switches at 6.
	if exponent_position := shortest.index('e') {
		exponent := strconv.atoi(shortest[exponent_position + 1..]) or { return shortest }
		if exponent >= 0 && exponent < 16 {
			mantissa := shortest[..exponent_position]
			sign := if mantissa.starts_with('-') { '-' } else { '' }
			unsigned := mantissa.trim_left('-')
			digits := unsigned.replace('.', '')
			decimal_position := unsigned.all_before('.').len + exponent
			if decimal_position >= digits.len {
				return sign + digits + '0'.repeat(decimal_position - digits.len) + '.0'
			}
			return sign + digits[..decimal_position] + '.' + digits[decimal_position..]
		}
	}
	return shortest
}

pub fn quoted(text string) string {
	// Python repr chooses double quotes only when that avoids escaping a quote.
	quote := if text.contains("'") && !text.contains('"') { '"' } else { "'" }
	mut escaped := []string{}
	for character in text.runes() {
		escaped << match character {
			`\\` { '\\\\' }
			`\n` { '\\n' }
			`\r` { '\\r' }
			`\t` { '\\t' }
			else {
				if character < 32 || character == 127 {
					'\\x${u32(character):02x}'
				} else if character.str() == quote {
					'\\' + quote
				} else {
					character.str()
				}
			}
		}
	}
	return quote + escaped.join('') + quote
}

pub fn object(item Value) !map[string]Value {
	if item is map[string]Value {
		return item
	}
	return error('record is not an object')
}

pub fn get(record map[string]Value, key string) !Value {
	return record[key] or { return error(quoted(key)) }
}

pub fn get_object(record map[string]Value, key string) !map[string]Value {
	return object(get(record, key)!)
}

pub fn load_json(path string) !map[string]Value {
	source := os.read_file(path) or { return error('cannot load ${path}: ${err}') }
	parsed := decode(source) or { return error('cannot load ${path}: ${err}') }
	return object(parsed) or { return error('${path} does not contain a JSON object') }
}

pub fn load_jsonl(path string) ![]map[string]Value {
	source := os.read_file(path) or { return error('cannot load ${path}: ${err}') }
	mut records := []map[string]Value{}
	// split_into_lines does not introduce a spurious record for the final LF.
	for index, line in source.split_into_lines() {
		parsed := decode(line) or { return error('${path}:${index + 1}: invalid JSON: ${err}') }
		records << object(parsed) or { return error('${path}:${index + 1}: record is not an object') }
	}
	return records
}

pub fn bytes_fromhex(source string) ![]u8 {
	// bytes.fromhex accepts ASCII whitespace between whole bytes, but neither
	// odd nibbles nor 0x prefixes (encoding.hex.decode accepts both).
	mut compact := []u8{cap: source.len}
	mut position := 0
	for position < source.len {
		if source[position] in [u8(9), 10, 11, 12, 13, 32] {
			position++
			continue
		}
		if !is_hex(source[position]) {
			return error('non-hexadecimal number found in fromhex() arg at position ${position}')
		}
		if position + 1 >= source.len || !is_hex(source[position + 1]) {
			return error('non-hexadecimal number found in fromhex() arg at position ${position + 1}')
		}
		compact << source[position]
		compact << source[position + 1]
		position += 2
	}
	return hex.decode(compact.bytestr())
}

fn is_hex(value u8) bool {
	return (value >= `0` && value <= `9`) || (value >= `a` && value <= `f`)
		|| (value >= `A` && value <= `F`)
}

pub fn u32_at(data []u8, offset int) u32 {
	return binary.little_endian_u32(data[offset..offset + 4])
}

pub fn walk_segment(data []u8) !Object {
	if data.len < segment_header_bytes {
		return error('segment is shorter than its header')
	}
	magic := u32_at(data, 0)
	declared := u32_at(data, 4)
	if u64(declared) != u64(data.len) {
		return error('segment length field 0x${declared:x} does not match 0x${data.len:x}')
	}
	mut records := []Value{}
	mut offset := segment_header_bytes
	for offset + record_header_bytes <= data.len {
		header := map[string]Value{
			'primary_extension_bytes': Value(u32_at(data, offset + 0x90))
			'auxiliary_u16_flag':      Value(u32_at(data, offset + 0x88))
			'auxiliary_u16_bytes':     Value(u32_at(data, offset + 0x8c))
			'auxiliary_u64_flag':      Value(u32_at(data, offset + 0x94))
			'auxiliary_u64_bytes':     Value(u32_at(data, offset + 0x98))
		}
		payload := u32_at(data, offset + payload_length_offset)
		payload_end := u64(offset + record_header_bytes) + payload
		if payload_end > u64(data.len) {
			return error('record at 0x${offset:x} claims 0x${payload:x} payload bytes, past the 0x${data.len:x}-byte segment')
		}
		mut end := payload_end
		mut record := map[string]Value{
			'offset':        Value(offset)
			'header':        Value(header)
			'payload_bytes': Value(payload)
			'payload_end':   Value(payload_end)
		}
		extension_bytes := value(header, 'primary_extension_bytes').u64()
		if extension_bytes != 0 {
			header_end := payload_end + primary_extension_header_bytes
			extension_end := header_end + extension_bytes
			if extension_end > u64(data.len) {
				return error('record at 0x${offset:x} has a truncated primary extension')
			}
			counts := [Value(u32_at(data, int(payload_end))),
				Value(u32_at(data, int(payload_end) + 4))]
			item_bytes := [Value(counts[0].u64() * 2), Value(counts[1].u64() * 24)]
			item_end := header_end + item_bytes[0].u64() + item_bytes[1].u64()
			if item_end > extension_end {
				return error('record at 0x${offset:x} primary arrays run past the 0x${extension_bytes:x}-byte extension')
			}
			end = extension_end
			record['primary_extension'] = map[string]Value{
				'offset':        Value(payload_end)
				'header_bytes':  Value(primary_extension_header_bytes)
				'bytes':         Value(extension_bytes)
				'counts':        Value(counts)
				'element_bytes': Value([Value(2), Value(24)])
				'item_bytes':    Value(item_bytes)
				'item_end':      Value(item_end)
				'end':           Value(end)
			}
		}
		record['end'] = Value(end)
		if payload == render_payload_bytes {
			payload_offset := offset + record_header_bytes
			match_bits := [Value(data[payload_offset + 0x240] & 1),
				Value(data[payload_offset + 0x7e0] & 1)]
			implication_bits := [Value(data[payload_offset + 0x23c] & 1),
				Value(data[payload_offset + 0x646] & 1)]
			if match_bits[0].u8() != match_bits[1].u8()
				|| implication_bits[0].u8() != 0 && implication_bits[1].u8() == 0 {
				return error('record at 0x${offset:x} violates the recovered render payload invariants')
			}
			record['render_validation'] = map[string]Value{
				'equal_bits':       Value(match_bits)
				'implication_bits': Value(implication_bits)
				'valid':            Value(true)
			}
		}
		records << Value(record)
		offset = int(end)
	}
	return map[string]Value{
		'magic':          Value(magic)
		'declared_bytes': Value(declared)
		'records':        Value(records)
		'trailing_bytes': Value(data.len - offset)
	}
}

pub struct Run {
pub:
	start int
	end   int
}

pub fn difference_runs(left []u8, right []u8) []Run {
	limit := if left.len < right.len { left.len } else { right.len }
	mut runs := []Run{}
	mut start := -1
	for offset in 0 .. limit {
		if left[offset] != right[offset] && start < 0 {
			start = offset
		} else if left[offset] == right[offset] && start >= 0 {
			runs << Run{start, offset}
			start = -1
		}
	}
	if start >= 0 {
		runs << Run{start, limit}
	}
	if left.len != right.len {
		trailing_end := if left.len > right.len { left.len } else { right.len }
		if runs.len != 0 && runs.last().end == limit {
			runs[runs.len - 1] = Run{runs.last().start, trailing_end}
		} else {
			runs << Run{limit, trailing_end}
		}
	}
	return runs
}

fn python_filters(filters map[string]string) string {
	mut parts := []string{}
	for key, item in filters {
		parts << '${quoted(key)}: ${quoted(item)}'
	}
	return '{' + parts.join(', ') + '}'
}

pub fn load_snapshot(path string, event string, phase string, index int, filters map[string]string) ![]u8 {
	records := load_jsonl(path)!
	mut matches := []map[string]Value{}
	for record in records {
		if value(record, 'event') != Value(event) || value(record, 'phase') != Value(phase) {
			continue
		}
		mut matches_filters := true
		for key, expected in filters {
			if string_value(value(record, key)) != expected {
				matches_filters = false
				break
			}
		}
		if matches_filters {
			matches << record
		}
	}
	if index >= matches.len {
		return error('no ${quoted(event)} snapshot #${index} for phase ${quoted(phase)} matching ${python_filters(filters)}; found ${matches.len}')
	}
	actual_index := if index < 0 { matches.len + index } else { index }
	if actual_index < 0 {
		return error('snapshot index out of range')
	}
	prefix := value(matches[actual_index], 'data_prefix')
	if prefix !is string {
		return error('${quoted(event)} snapshot #${index} for phase ${quoted(phase)} has no data_prefix; rerun with AGX_TRACE_BYTES')
	}
	return bytes_fromhex(prefix)
}

// Parse Python's int(value, 0) strings, including separators and arbitrary
// width. Bounds are checked against the actual ABI limits before narrowing.
pub fn integer(item Value, label string) !big.Integer {
	mut text := ''
	mut base := 10
	match item {
		i64, int, u8, u32, u64 { text = item.str() }
		Number {
			if item.text.contains_any('.eE') {
				return error('${label} is not an integer')
			}
			text = item.text
		}
		string {
			text = item.trim_space()
			if text.contains('__') { return error('${label} is not an integer: ${quoted(item)}') }
			mut digits := text
			if digits.starts_with('+') || digits.starts_with('-') {
				digits = digits[1..]
			}
			if digits.len >= 2 && digits[0] == `0` {
				base = match digits[1] {
					`x`, `X` { 16 }
					`b`, `B` { 2 }
					`o`, `O` { 8 }
					else { 10 }
				}
				if base != 10 {
					if digits[2..].contains_any('+-') {
						return error('${label} is not an integer: ${quoted(item)}')
					}
					text = text[..text.len - digits.len] + digits[2..].trim_left('_')
				} else if digits.replace('_', '').trim('0') != '' {
					return error('${label} is not an integer: ${quoted(item)}')
				}
			}
			if text == '' || text.starts_with('_') || text.starts_with('+_')
				|| text.starts_with('-_') || text.ends_with('_') || text.contains('__') {
				return error('${label} is not an integer: ${quoted(item)}')
			}
			unsigned := if text.starts_with('+') || text.starts_with('-') {
				text[1..]
			} else {
				text
			}
			if unsigned == '' || unsigned.contains_any('+-') {
				return error('${label} is not an integer: ${quoted(item)}')
			}
		}
		else { return error('${label} is not an integer') }
	}
	parsed := big.integer_from_radix(text.replace('_', ''), u32(base)) or {
		if item is string {
			return error('${label} is not an integer: ${quoted(item)}')
		}
		return error('${label} is not an integer')
	}
	if parsed.signum < 0 {
		return error('${label} is negative')
	}
	return parsed
}

fn narrow(value big.Integer) u64 {
	return strconv.parse_uint(value.str(), 10, 64) or { panic('unbounded integer narrowing') }
}

pub struct CopyRange {
pub:
	stage             string
	payload_offset    big.Integer
	descriptor_member big.Integer
	bytes             big.Integer
}

pub fn copy_ranges(abi map[string]Value) ![]CopyRange {
	channels := get_object(abi, 'channels') or { return error('ABI is missing a descriptor copy map: ${err}') }
	common := get_object(channels, 'descriptor_3d_common_passthrough') or { return error('ABI is missing a descriptor copy map: ${err}') }
	render := get_object(channels, 'descriptor_ta_render_passthrough') or { return error('ABI is missing a descriptor copy map: ${err}') }
	source := get_object(common, 'source') or { return error('ABI is missing a descriptor copy map: ${err}') }
	common_base := integer(get(source, 'payload_offset') or { return error('ABI is missing a descriptor copy map: ${err}') }, 'common payload offset')!
	payload_bytes := integer(get(render, 'payload_bytes') or { return error('ABI is missing a descriptor copy map: ${err}') }, 'render payload size')!
	descriptor_bytes := integer(get(render, 'descriptor_bytes') or { return error('ABI is missing a descriptor copy map: ${err}') }, 'render descriptor size')!
	stages := ['ta-pre', 'common', 'ta-post']
	bases := [big.zero_int, common_base, big.zero_int]
	fields := [
		get(render, 'pre_common_copy_ranges') or { return error('ABI is missing a descriptor copy map: ${err}') },
		get(common, 'copy_ranges') or { return error('ABI is missing a descriptor copy map: ${err}') },
		get(render, 'post_common_copy_ranges') or { return error('ABI is missing a descriptor copy map: ${err}') },
	]
	mut result := []CopyRange{}
	for group, stage in stages {
		items := fields[group]
		if items !is []Value {
			return error('${stage} descriptor copy map is not a list')
		}
		for index, entry in items {
			if entry !is map[string]Value {
				return error('${stage} copy #${index} is not an object')
			}
			from := bases[group] + integer(value(entry, 'source_offset'), '${stage} copy #${index} source')!
			member := integer(value(entry, 'descriptor_member'), '${stage} copy #${index} descriptor member')!
			size := integer(value(entry, 'bytes'), '${stage} copy #${index} size')!
			if size == big.zero_int {
				return error('${stage} copy #${index} has zero size')
			}
			if from > payload_bytes || size > payload_bytes - from {
				return error('${stage} copy #${index} exceeds the render payload')
			}
			if member > descriptor_bytes || size > descriptor_bytes - member {
				return error('${stage} copy #${index} exceeds the descriptor')
			}
			result << CopyRange{stage, from, member, size}
		}
	}
	return result
}

pub fn map_payload_pointer(payload_offset int, ranges []CopyRange) []map[string]Value {
	mut mappings := []map[string]Value{}
	offset := big.integer_from_int(payload_offset)
	for field in ranges {
		if offset >= field.payload_offset && offset - field.payload_offset <= field.bytes
			&& big.integer_from_int(pointer_bytes) <= field.bytes - (offset - field.payload_offset) {
			// This output may intentionally exceed 64 bits for an arbitrary-width
			// user-supplied descriptor ABI, just as the original Python did.
			member := field.descriptor_member + offset - field.payload_offset
			mappings << map[string]Value{
				'stage':             Value(field.stage)
				'descriptor_member': Value(Number{member.str()})
				'descriptor_bytes':  Value(pointer_bytes)
			}
		}
	}
	return mappings
}

pub fn segment_snapshot(records []map[string]Value, phase string, index int) ![]u8 {
	mut matches := []map[string]Value{}
	for record in records {
		if value(record, 'event') == Value('segment') && value(record, 'phase') == Value(phase) {
			matches << record
		}
	}
	if index >= matches.len {
		return error('no segment snapshot #${index} for phase ${quoted(phase)}; found ${matches.len}')
	}
	actual := if index < 0 { matches.len + index } else { index }
	if actual < 0 { return error('snapshot index out of range') }
	prefix := value(matches[actual], 'data_prefix')
	if prefix !is string {
		return error('segment snapshot #${index} for phase ${quoted(phase)} has no data_prefix')
	}
	return bytes_fromhex(prefix) or { return error('segment snapshot #${index} for phase ${quoted(phase)} has invalid hex') }
}

pub struct ResourceRange {
pub:
	address u64
	size    u64
}

pub fn traced_resource_ranges(records []map[string]Value, phase string) ![]ResourceRange {
	mut ranges := []ResourceRange{}
	maximum := big.integer_from_u64(~u64(0)) + big.one_int
	for record in records {
		event := value(record, 'event')
		mut address_value := Value(json2.null)
		mut size_value := Value(json2.null)
		if event == Value('resource_snapshot') {
			if value(record, 'phase') != Value(phase) { continue }
			address_value = value(record, 'resource_gpu_address')
			size_value = value(record, 'resource_bytes')
		} else if event == Value('resource') {
			// Private resources have a range, but are never CPU-read.
			address_value = value(record, 'gpu_address')
			size_value = value(record, 'bytes')
		} else {
			continue
		}
		base := integer(address_value, 'resource GPU address')!
		size := integer(size_value, 'resource size')!
		if base == big.zero_int || size == big.zero_int || base > maximum - size {
			return error('phase ${quoted(phase)} contains an invalid resource range')
		}
		range := ResourceRange{narrow(base), narrow(size)}
		if range !in ranges { ranges << range }
	}
	ranges.sort_with_compare(fn (a &ResourceRange, b &ResourceRange) int {
		if a.address < b.address || a.address == b.address && a.size < b.size { return -1 }
		if a.address == b.address && a.size == b.size { return 0 }
		return 1
	})
	return ranges
}

pub fn render_payload_bounds(segment []u8) !(int, int) {
	walked := walk_segment(segment)!
	mut records := []map[string]Value{}
	for record in value(walked, 'records').arr() {
		item := record.as_map()
		if value(item, 'payload_bytes').int() == render_payload_bytes { records << item }
	}
	if records.len != 1 {
		return error('segment must contain exactly one recovered 0x9d0-byte render payload')
	}
	return value(records[0], 'offset').int() + record_header_bytes, value(records[0], 'payload_end').int()
}

pub fn correlate_phase(records []map[string]Value, abi map[string]Value, phase string, segment_index int) !Object {
	segment := segment_snapshot(records, phase, segment_index)!
	payload_start, payload_end := render_payload_bounds(segment)!
	resources := traced_resource_ranges(records, phase)!
	ranges := copy_ranges(abi)!
	mut occurrences := 0
	mut candidates := []Value{}
	mut unmapped := []Value{}
	for offset := 0; offset + pointer_bytes <= segment.len; offset += pointer_scan_alignment {
		address := binary.little_endian_u64(segment[offset..offset + pointer_bytes])
		for resource in resources {
			if address < resource.address || address - resource.address >= resource.size {
				continue
			}
			mut occurrence := map[string]Value{
				'segment_source_offset': Value(offset)
				'gpu_address':           Value(address)
				'resource_gpu_address':  Value(resource.address)
				'resource_offset':       Value(address - resource.address)
				'resource_bytes':        Value(resource.size)
			}
			occurrences++
			if offset < payload_start || offset + pointer_bytes > payload_end {
				occurrence['reason'] = Value('outside-render-payload')
				unmapped << Value(occurrence)
				continue
			}
			payload_offset := offset - payload_start
			occurrence['payload_offset'] = Value(payload_offset)
			mappings := map_payload_pointer(payload_offset, ranges)
			if mappings.len == 0 {
				occurrence['reason'] = Value('not-copied-to-descriptor')
				unmapped << Value(occurrence)
				continue
			}
			for mapping in mappings {
				mut candidate := occurrence.clone()
				for key, item in mapping { candidate[key] = item }
				candidates << Value(candidate)
			}
		}
	}
	return map[string]Value{
		'phase':                  Value(phase)
		'segment_index':          Value(segment_index)
		'render_payload_offset':  Value(payload_start)
		'render_payload_bytes':   Value(payload_end - payload_start)
		'traced_resource_ranges': Value(resources.len)
		'resource_occurrences':   Value(occurrences)
		'descriptor_candidates':  Value(candidates)
		'unmapped_occurrences':   Value(unmapped)
		'interpretation':         Value('candidate Apple payload-to-descriptor copies only; no Mesa semantic field mapping is claimed; private resources contribute ranges but are never CPU-read')
	}
}
