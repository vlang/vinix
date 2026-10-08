// SPDX-License-Identifier: GPL-2.0-only
module agxhost

import g17power as power
import traceanalysis as j
import math
import math.big
import json2
import strconv

pub struct TraceFailure {
pub:
	kind string
	argument j.Value
	has_argument bool
	tuple_argument bool
}

pub fn (e TraceFailure) msg() string { return e.kind }
pub fn (e TraceFailure) code() int { return 0 }

fn trace_assert(value bool) ! {
	if !value { return TraceFailure{kind: 'AssertionError'} }
}

fn trace_assert_argument(value bool, argument j.Value, tuple bool) ! {
	if !value { return TraceFailure{kind: 'AssertionError', argument: argument, has_argument: true, tuple_argument: tuple} }
}

fn trace_event(row map[string]j.Value) !string {
	return j.string_value(row['event'] or { return TraceFailure{kind: 'KeyError', argument: j.Value('event'), has_argument: true} })
}

fn trace_type(value j.Value) string {
	return match value {
		string { 'str' }
		bool { 'bool' }
		[]j.Value { 'list' }
		map[string]j.Value { 'dict' }
		json2.Null { 'NoneType' }
		j.Number { if trace_floating(value) { 'float' } else { 'int' } }
		else { 'int' }
	}
}

fn trace_row(value j.Value) !map[string]j.Value {
	if value is map[string]j.Value { return value }
	message := match value {
		[]j.Value { 'list indices must be integers or slices, not str' }
		string { 'string indices must be integers' }
		else { "'" + trace_type(value) + "' object is not subscriptable" }
	}
	return TraceFailure{kind: 'TypeError', argument: j.Value(message), has_argument: true}
}

fn trace_event_value(value j.Value) !string { return trace_event(trace_row(value)!) }

fn trace_length(value j.Value) !int {
	return match value {
		string { value.runes().len }
		[]j.Value { value.len }
		map[string]j.Value { value.len }
		else { return TraceFailure{kind: 'TypeError', argument: j.Value("object of type '" + trace_type(value) + "' has no len()"), has_argument: true} }
	}
}

fn trace_integer_space(ch rune) bool {
	return ch in [rune(9), 10, 11, 12, 13, 32, 0x85, 0xa0, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003,
		0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000]
}

fn trace_regex_space(ch rune) bool { return trace_integer_space(ch) || ch in [rune(0x1c), 0x1d, 0x1e, 0x1f] }

struct TraceSectionCursor {
	characters []rune
mut:
	position int
}

fn (mut cursor TraceSectionCursor) literal(text string) bool {
	for offset, ch in text.runes() {
		if cursor.position + offset >= cursor.characters.len || cursor.characters[cursor.position + offset] != ch { return false }
	}
	cursor.position += text.len
	return true
}

fn (mut cursor TraceSectionCursor) space() bool {
	start := cursor.position
	for cursor.position < cursor.characters.len && trace_regex_space(cursor.characters[cursor.position]) { cursor.position++ }
	return cursor.position != start
}

fn (mut cursor TraceSectionCursor) token() string {
	start := cursor.position
	for cursor.position < cursor.characters.len && !trace_regex_space(cursor.characters[cursor.position]) { cursor.position++ }
	return cursor.characters[start..cursor.position].string()
}

fn (mut cursor TraceSectionCursor) digits() string {
	start := cursor.position
	for cursor.position < cursor.characters.len && trace_decimal_digit(cursor.characters[cursor.position]) >= 0 { cursor.position++ }
	return cursor.characters[start..cursor.position].string()
}

fn trace_lines(text string) []string {
	mut result := []string{}
	mut value := ''
	mut previous_cr := false
	for ch in text.runes() {
		if ch == 10 && previous_cr { previous_cr = false; continue }
		previous_cr = ch == 13
		if ch in [rune(10), 11, 12, 13, 0x1c, 0x1d, 0x1e, 0x85, 0x2028, 0x2029] {
			result << value
			value = ''
		} else { value += ch.str() }
	}
	if value != '' { result << value }
	return result
}

fn trace_decimal_digit(ch rune) int {
	if ch >= `0` && ch <= `9` { return int(ch - `0`) }
	if ch < 0x80 { return -1 }
	return (power.decimal_integer(j.Value(ch.str())) or { return -1 }).int()
}

fn trace_hex_digits(value string) !string {
	mut runes := value.runes()
	for runes.len != 0 && trace_integer_space(runes[0]) { runes.delete(0) }
	for runes.len != 0 && trace_integer_space(runes.last()) { runes.pop() }
	mut text := runes.string()
	mut sign := ''
	if text.starts_with('+') || text.starts_with('-') { sign = text[..1]; text = text[1..] }
	if text.to_lower().starts_with('0x') { text = text[2..]; if text.starts_with('_') { text = text[1..] } }
	if text == '' || text.starts_with('_') || text.ends_with('_') || text.contains('__') {
		return TraceFailure{kind: 'HexIntegerError', argument: j.Value(value), has_argument: true}
	}
	mut normalized := ''
	for ch in text.runes() {
		if ch == `_` { continue }
		digit := trace_decimal_digit(ch)
		if digit >= 0 { normalized += digit.str() }
		else if ch >= `a` && ch <= `f` { normalized += ch.str() }
		else if ch >= `A` && ch <= `F` { normalized += ch.str().to_lower() }
		else { return TraceFailure{kind: 'HexIntegerError', argument: j.Value(value), has_argument: true} }
	}
	return sign + normalized
}

fn trace_numeric(value j.Value) bool {
 return value is bool || value is j.Number || value is int || value is i64 || value is u8 || value is u32 || value is u64
}

fn trace_floating(value j.Value) bool {
 if value is j.Number { return value.text.contains_any('.eE') || value.text in ['NaN', 'Infinity', '-Infinity'] }
 return false
}

pub fn trace_equal(a j.Value, b j.Value) bool {
	return trace_equal_context(a, b, false)
}

fn trace_equal_context(a j.Value, b j.Value, nested bool) bool {
	// CPython's JSON constants share their NaN object; container comparisons
	// accept the same object before performing floating point equality.
	if nested && a is j.Number && b is j.Number && a.text == 'NaN' && b.text == 'NaN' { return true }
 if trace_numeric(a) && trace_numeric(b) {
  if !trace_floating(a) && !trace_floating(b) {
   return (power.decimal_integer(a) or { return false }) == (power.decimal_integer(b) or { return false })
  }
  if trace_floating(a) && trace_floating(b) { return (power.floating(a) or { return false }) == (power.floating(b) or { return false }) }
  number := if trace_floating(a) { a } else { b }
  integer := if trace_floating(a) { b } else { a }
  floating := power.floating(number) or { return false }
  if math.is_nan(floating) || math.is_inf(floating, 0) || math.floor(floating) != floating { return false }
  return (power.decimal_integer(number) or { return false }) == (power.decimal_integer(integer) or { return false })
 }

	if a is map[string]j.Value {
		if b !is map[string]j.Value { return false }
		if a.len != b.len { return false }
		for key, value in a {
			other := b[key] or { return false }
			if !trace_equal_context(value, other, true) { return false }
		}
		return true
	}
	if a is []j.Value {
		if b is []j.Value {
			if a.len != b.len { return false }
			for index, value in a { if !trace_equal_context(value, b[index], true) { return false } }
			return true
		}
		return false
	}
	return a == b
}

fn trace_required(row map[string]j.Value, name string) !j.Value {
	return row[name] or { return TraceFailure{kind: 'KeyError', argument: j.Value(name), has_argument: true} }
}

fn trace_output_method(methods []map[string]j.Value, name string, requested string, output string, status int) !bool {
	for method in methods {
		if j.string_value(method['method'] or { j.Value(json2.Null{}) }) != name { continue }
		if !trace_equal(trace_required(method, requested)!, j.Value(if name == 'getDeviceConfig' { 8 } else { 2 })) { continue }
		if !trace_equal(trace_required(method, output)!, j.Value(if name == 'getDeviceConfig' { 4 } else { 1 })) { continue }
		if trace_equal(trace_required(method, 'status')!, j.Value(status)) { return true }
	}
	return false
}

fn trace_small_pointer(value string) !bool {
	mut text := trace_hex_digits(value)!
	if text.starts_with('-') { return true }
	if text.starts_with('+') { text = text[1..] }
	text = text.trim_left('0')
	if text == '' { return true }
	if text.len > 3 { return false }
	number := strconv.parse_uint(text, 16, 64) or { return error(err.msg()) }
	return number <= 1026
}

// Pointer labels are internal to each comparison. Both unchanged fixture logs
// use the same key walk; pointer identities are preserved across every row.
pub fn trace_normalized(text string) ![]j.Value {
	mut pointers := map[string]string{}
	mut result := []j.Value{}
	for line in trace_lines(text) {
		value := power.decode_device_json(line) or { return TraceFailure{kind: 'JSONDecodeError', argument: j.Value(line), has_argument: true} }
		if value !is map[string]j.Value {
			return TraceFailure{kind: 'AttributeError', argument: j.Value("'" + trace_type(value) + "' object has no attribute 'keys'"), has_argument: true}
		}
		mut row := value.as_map().clone()
		for key in ['storage', 'start', 'end', 'object', 'cpu_address', 'cursor', 'limit'] {
			pointer_value := row[key] or { continue }
			if pointer_value !is string { return TraceFailure{kind: 'TypeError', argument: j.Value("int() can't convert non-string with explicit base"), has_argument: true} }
			pointer := j.string_value(pointer_value)
			if pointer in ['0x0', '(nil)'] {
				row[key] = 'NULL'
			} else if !trace_small_pointer(pointer)! {
				if pointer !in pointers { pointers[pointer] = 'pointer-' + pointers.len.str() }
				row[key] = pointers[pointer]
			}
		}
		result << row
	}
	return result
}

pub fn trace_check(rows []j.Value, mode string, limit int) ! {
	if rows.len == 0 { return TraceFailure{kind: 'IndexError', argument: j.Value('list index out of range'), has_argument: true} }
	trace_assert(trace_equal(rows[0], j.Value({'event': j.Value('trace_start'), 'schema': j.Value(2)})))!
	mut hooks := 0
	for row in rows { if trace_event_value(row)! == 'resource_hook' { hooks++ } }
	trace_assert(hooks == 401)!
	mut resources := 0
	for row in rows { if trace_event_value(row)! == 'resource' { resources++ } }
	trace_assert(resources == 1028)!
	mut snapshots := []map[string]j.Value{}
	for row in rows { if trace_event_value(row)! == 'resource_snapshot' { snapshots << row.as_map() } }
	trace_assert_argument(snapshots.len == if limit != 0 { 65 } else { 0 }, j.Value(snapshots.len), false)!
	mut prefix := []u8{}
	for index in 0 .. if limit < 16 { limit } else { 16 } { prefix << u8(index) }
	for snapshot in snapshots {
		offset := snapshot['resource_offset'] or { return TraceFailure{kind: 'KeyError', argument: j.Value('resource_offset'), has_argument: true} }
		// Python's short circuit does not read data_prefix after a bad offset.
		trace_assert(trace_equal(offset, j.Value(0)))!
		data := snapshot['data_prefix'] or { return TraceFailure{kind: 'KeyError', argument: j.Value('data_prefix'), has_argument: true} }
		trace_assert(trace_equal(data, j.Value(prefix.hex())))!
	}
	mut methods := []map[string]j.Value{}
	for row in rows { if trace_event_value(row)! == 'method' { methods << row.as_map() } }
	trace_assert(trace_output_method(methods, 'getDeviceConfig', 'requested_output_bytes', 'output_bytes', 17)!)!
	trace_assert(trace_output_method(methods, 'getSPTMEventCounters', 'requested_output_scalars', 'output_scalars', -5)!)!
	trace_assert(methods.any(trace_equal((it['input_read_status'] or { j.Value(json2.Null{}) }), j.Value(22)) &&
		trace_equal((it['output_read_status'] or { j.Value(json2.Null{}) }), j.Value(22))) == (limit != 0))!
	trace_assert(methods.any(j.string_value(it['method'] or { j.Value(json2.Null{}) }) == 'createDeadlineProfile' &&
		j.string_value(it['input_prefix'] or { j.Value(json2.Null{}) }) == '00010203040506') == (limit != 0))!
	trace_assert(methods.any(j.string_value(it['method'] or { j.Value(json2.Null{}) }) == 'destroyDeadlineProfile' && 'input_prefix' !in it))!
	trace_assert(methods.any(trace_equal((it['selector'] or { j.Value(json2.Null{}) }), j.Value(0x113)) && 'method' !in it))!
	for connection in [99, 66, 265] {
		trace_assert(methods.any(trace_equal((it['connection'] or { j.Value(json2.Null{}) }), j.Value(connection))) == (mode == 'all'))!
	}
	if limit == 65536 {
		mut found := false
		for method in methods {
			if j.string_value(method['method'] or { j.Value(json2.Null{}) }) != 'performanceCounterSamplerControl' { continue }
			input := method['input_prefix'] or { return TraceFailure{kind: 'KeyError', argument: j.Value('input_prefix'), has_argument: true} }
			if trace_length(input)! == 65536 * 2 { found = true; break }
		}
		trace_assert(found)!
	}
	trace_assert(trace_equal(rows.last(), j.Value({'event': j.Value('marker'), 'phase': j.Value('')})))!
}

pub fn trace_compare(actual []j.Value, expected []j.Value) ! {
	if trace_equal(j.Value(actual), j.Value(expected)) { return }
	for index, value in actual {
		if index >= expected.len { break }
		if !trace_equal(value, expected[index]) {
			return TraceFailure{kind: 'AssertionError', argument: j.Value([j.Value(index), value, expected[index]]), has_argument: true, tuple_argument: true}
		}
	}
	return TraceFailure{kind: 'AssertionError', argument: j.Value([j.Value(actual.len), j.Value(expected.len)]), has_argument: true, tuple_argument: true}
}

pub fn trace_interpose_section(text string) !bool {
	characters := text.runes()
	for start, ch in characters {
		if ch != `s` { continue }
		mut cursor := TraceSectionCursor{characters: characters, position: start}
		if !cursor.literal('sectname __interpose') || !cursor.space() || !cursor.literal('segname __DATA') ||
			!cursor.space() || !cursor.literal('addr ') || cursor.token() == '' || !cursor.space() || !cursor.literal('size ') { continue }
		size_capture := cursor.token()
		if size_capture == '' || !cursor.space() || !cursor.literal('offset ') || cursor.token() == '' ||
			!cursor.space() || !cursor.literal('align 2^') { continue }
		align := cursor.digits()
		if align == '' || !cursor.literal(' (') || cursor.digits() == '' || !cursor.literal(')') || !cursor.space() ||
			!cursor.literal('reloff ') || cursor.token() == '' || !cursor.space() || !cursor.literal('nreloc 16') { continue }
		size_text := trace_hex_digits(size_capture)!
		size := big.integer_from_radix(size_text, 16)!
		if size != big.integer_from_int(128) { return false }
		alignment := power.decimal_integer(j.Value(align))!
		return alignment >= big.integer_from_int(3)
	}
	return false
}
