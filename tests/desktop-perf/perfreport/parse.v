// SPDX-License-Identifier: GPL-2.0-or-later
module perfreport

import math
import math.big

fn byte_space(ch u8) bool { return ch in [` `, `\t`, `\r`, `\n`, u8(11), 12] }

fn byte_lines(data []u8) []string {
	mut lines := []string{}
	mut start := 0
	mut index := 0
	for index < data.len {
		if data[index] in [`\r`, `\n`] {
			lines << data[start..index].bytestr()
			if data[index] == `\r` && index + 1 < data.len && data[index + 1] == `\n` { index++ }
			start = index + 1
		}
		index++
	}
	if start < data.len { lines << data[start..].bytestr() }
	return lines
}

// Consume only UTF-8's valid prefix on an invalid or incomplete sequence.
fn utf8_replace(data []u8) string {
	mut result := []u8{}
	mut index := 0
	for index < data.len {
		first := data[index]
		if first < 128 {
			result << first
			index++
			continue
		}
		width := if first >= 0xc2 && first <= 0xdf {
			2
		} else if first >= 0xe0 && first <= 0xef {
			3
		} else if first >= 0xf0 && first <= 0xf4 {
			4
		} else {
			0
		}
		mut consumed := 1
		if width != 0 {
			for consumed < width && index + consumed < data.len {
				byte := data[index + consumed]
				if byte < 0x80 || byte > 0xbf { break }
				if consumed == 1 && ((first == 0xe0 && byte < 0xa0) || (first == 0xed && byte > 0x9f) || (first == 0xf0 && byte < 0x90) || (first == 0xf4 && byte > 0x8f)) {
					break
				}
				consumed++
			}
		}
		if width != 0 && consumed == width {
			result << data[index..index + width]
		} else {
			result << [u8(0xef), 0xbf, 0xbd]
		}
		index += consumed
	}
	return result.bytestr()
}

fn shell_split(text string) ![]string {
	mut fields := []string{}
	mut token := ''
	mut quote := u8(0)
	mut started := false
	mut index := 0
	for index < text.len {
		ch := text[index]
		if quote == `'` {
			if ch == quote { quote = 0 } else { token += ch.ascii_str() }
		} else if ch == `\\` {
			index++
			if index >= text.len { return error('No escaped character') }
			next := text[index]
			if quote == `"` && next !in [`"`, `\\`] { token += '\\' }
			token += next.ascii_str()
			started = true
		} else if quote != 0 {
			if ch == quote { quote = 0 } else { token += ch.ascii_str() }
		} else if ch in [`'`, `"`] {
			quote = ch
			started = true
		} else if ch in [` `, `\t`, `\r`, `\n`] {
			if started {
				fields << token
				token = ''
				started = false
			}
		} else {
			token += ch.ascii_str()
			started = true
		}
		index++
	}
	if quote != 0 { return error('No closing quotation') }
	if started { fields << token }
	return fields
}

fn parse_measurement(line string) ?Row {
	// Regex search resumes after an invalid prefix, including a second marker
	// of the same kind on the same serial line.
	for start in 0 .. line.len {
		for kind in measurement_kinds {
			if line[start..].starts_with(kind + ' variant=') {
				if row := parse_at(line, start, kind) { return row }
			}
		}
	}
	return none
}

fn parse_at(line string, start int, kind string) ?Row {
	mut cursor := start + kind.len + 9
	variant_start := cursor
	for cursor < line.len && !byte_space(line[cursor]) { cursor++ }
	if cursor == variant_start || !line[cursor..].starts_with(' scenario=') { return none }
	variant := utf8_replace(line[variant_start..cursor].bytes())
	cursor += 10
	scenario_start := cursor
	for cursor < line.len && !byte_space(line[cursor]) { cursor++ }
	if cursor == scenario_start || !line[cursor..].starts_with(' round=') { return none }
	scenario := utf8_replace(line[scenario_start..cursor].bytes())
	cursor += 7
	round_start := cursor
	for cursor < line.len && line[cursor].is_digit() { cursor++ }
	if cursor == round_start || cursor >= line.len || line[cursor] != ` ` { return none }
	mut row := map[string]Value{
		'variant':  Value(variant)
		'scenario': Value(scenario)
		'round':    Value(Number{(big.integer_from_string(line[round_start..cursor]) or { return none }).str()})
		'_payload': Value(utf8_replace(line[cursor + 1..].bytes()))
	}
	if kind != 'PERF-RESULT' { row['report'] = kind }
	return row
}

fn validate_report(row Row, identity Identity, mut errors []string) {
	kind := if 'report' in row { string_value(value(row, 'report')) } else { 'PERF-RESULT' }
	required := match kind {
		'PERF-WAKEUPS' { ['interval_ms', 'wakeups', 'per_second', 'cpu', 'us_per_wakeup'] }
		'PERF-CHURN' { ['runs', 'retained_kb', 'per_run_bytes'] }
		'PERF-CACHE' { ['written_mb', 'used_mb', 'cached_kb', 'slab_kb'] }
		'PERF-OPS' { ['count', 'bytes_per_op'] }
		else { []string{} }
	}
	mut failure := ''
	for name in required {
		if name !in row {
			failure = quoted(name)
			break
		}
		item := value(row, name)
		floating := metric(item) or {
			failure = err.msg()
			break
		}
		if math.is_nan(floating) || math.is_inf(floating, 0) {
			failure = 'non-finite metric'
			break
		}
	}
	if failure == '' && required.len != 0 {
		name := required[0]
		expected_value := match kind {
			'PERF-WAKEUPS' { 16 }
			'PERF-CHURN' { 300 }
			'PERF-CACHE' { 32 }
			else { 200 }
		}
		actual := integer(value(row, name)) or {
			errors << 'missing or invalid report metrics: ' + identity.repr() + ': invalid literal for int() with base 10: ' + quoted(string_value(value(row, name)))
			return
		}
		if actual != big.integer_from_int(expected_value) {
			failure = 'expected ${name}=${expected_value}'
		}
	}
	if failure != '' {
		errors << 'missing or invalid report metrics: ' + identity.repr() + ': ' + failure
	}
}
