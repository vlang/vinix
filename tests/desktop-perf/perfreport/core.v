// SPDX-License-Identifier: GPL-2.0-or-later
// Verdicts for captured guest output. This module does not launch a guest.
module perfreport

import json2
import math
import math.big

#include <stdio.h>

fn C.strtod(&char, &&char) f64
fn C.snprintf(&char, usize, &char, ...) i32

fn float_format(value f64, format string) string {
	mut bytes := []u8{len: 400}
	count := unsafe { C.snprintf(&char(bytes.data), usize(bytes.len), &char(format.str), value) }
	assert count >= 0 && count < bytes.len
	return bytes[..count].bytestr()
}

pub struct Number {
pub mut:
	text string
}

pub fn (mut number Number) from_json_number(text string) ! { number.text = text }

pub fn (number Number) to_json() string { return number.text }

pub type Value = Number | []Value | bool | json2.Null | map[string]Value | string
pub type Row = map[string]Value

pub fn (item Value) as_map() Row {
	return if item is map[string]Value { item } else { map[string]Value{} }
}

pub fn (item Value) arr() []Value { return if item is []Value { item } else { []Value{} } }

pub const scenarios = ['idle', 'apps', 'utilities', 'storage', 'productivity', 'tools', 'workflows',
	'pointer', 'drag', 'wakeups', 'churn', 'cache', 'ops']
pub const metrics = ['desktop_cpu', 'apps_cpu', 'total_cpu', 'physical_mb', 'desktop_mb', 'apps_mb',
	'total_mb']
pub const general_ops = ['stat', 'pipe', 'socketpair', 'inet_socket', 'eventfd', 'epoll', 'timerfd',
	'poll', 'proc_read', 'proc_list', 'readdir', 'dup', 'mmap', 'thread', 'signal', 'fault', 'fork',
	'memfd']
pub const file_ops = ['file', 'rename', 'unlink_open', 'rename_over', 'hardlink', 'mkdir', 'symlink',
	'unix_connect', 'unix_datagram']
pub const churn_programs = ['/bin/true', '/bin/sleep 0', '/usr/bin/curl --version',
	'/bin/busybox awk BEGIN{}']
pub const done = 'VINIX DESKTOP PERF: DONE'
const reports = ['PERF-WAKEUPS', 'PERF-CHURN', 'PERF-SLAB', 'PERF-CACHE', 'PERF-MEMINFO', 'PERF-OPS',
	'PERF-SITE']
const measurement_kinds = ['PERF-RESULT', 'PERF-WAKEUPS', 'PERF-CHURN', 'PERF-CACHE', 'PERF-OPS']

// JSON has no nonfinite numeric token. The import bridge tags these values.
pub fn from_wire(item Value) Value {
	return match item {
		map[string]Value {
			if item.len == 1 {
				if escaped := item['$escaped_map'] {
					if escaped is map[string]Value {
						mut decoded := map[string]Value{}
						for key, entry in escaped { decoded[key] = from_wire(entry) }
						return Value(decoded)
					}
				}
				entry := item['$nonfinite_number'] or { Value('') }
				if entry is string && entry in ['nan', 'inf', '-inf'] {
					return Value(Number{entry})
				}
			}
			mut result := map[string]Value{}
			for key, entry in item { result[key] = from_wire(entry) }
			Value(result)
		}
		[]Value { Value(item.map(from_wire(it))) }
		else { item }
	}
}

pub fn value(row Row, key string) Value { return row[key] or { Value(json2.null) } }

pub fn string_value(item Value) string {
	return match item {
		string { item }
		Number { item.text }
		bool {
			if item { 'True' } else { 'False' }
		}
		json2.Null { 'None' }
		else { json2.encode(item) }
	}
}

fn metric(item Value) !f64 {
	mut text := ''
	match item {
		bool { return if item { 1 } else { 0 } }
		string {
			text = normalize_number(item, false) or {
				return error('could not convert string to float: ' + quoted(if err.msg() == 'empty number' {
					''
				} else {
					item
				}))
			}
		}
		Number { text = item.text }
		else {
			name := match item {
				json2.Null { 'NoneType' }
				[]Value { 'list' }
				else { 'dict' }
			}
			return error("TypeError: float() argument must be a string or a number, not '" + name + "'")
		}
	}
	mut end := &char(unsafe { nil })
	floating := unsafe { C.strtod(&char(text.str), &end) }
	if unsafe { end == text.str || end != &char(text.str + text.len) } {
		return error('invalid float')
	}
	if item is Number && !text.contains_any('.eE') && text !in ['nan', 'inf', '-inf'] && math.is_inf(floating, 0) {
		return error('OverflowError: int too large to convert to float')
	}
	return floating
}

fn integer(item Value) !big.Integer {
	return match item {
		bool { big.integer_from_int(if item { 1 } else { 0 }) }
		Number {
			if item.text.contains_any('.eE') || item.text in ['nan', 'inf', '-inf'] {
				floating := metric(item)!
				if math.is_inf(floating, 0) {
					return error('OverflowError: cannot convert float infinity to integer')
				}
				if math.is_nan(floating) { return error('invalid integer') }
				// JSON float inputs are accepted by int(); transcript fields are strings.
				big.integer_from_string(float_format(math.trunc(floating), '%.0f'))!
			} else {
				big.integer_from_string(item.text)!
			}
		}
		string { big.integer_from_string(normalize_number(item, true)!)! }
		else { return error('invalid integer') }
	}
}

pub fn valid_desktop_result(row Row) !bool {
	seconds := metric(value(row, 'seconds')) or {
		if err.msg().starts_with('OverflowError: ') { return err }
		return false
	}
	scenario := string_value(value(row, 'scenario'))
	minimum := if scenario == 'workflows' {
		5
	} else if scenario in ['utilities', 'storage', 'productivity', 'tools'] {
		4
	} else {
		0
	}
	for key in [...metrics, 'system_used_mb'] {
		floating := metric(value(row, key)) or {
			if err.msg().starts_with('OverflowError: ') { return err }
			return false
		}
		if math.is_nan(floating) || math.is_inf(floating, 0) { return false }
	}
	if math.is_nan(seconds) || math.is_inf(seconds, 0) || seconds <= 0 { return false }
	processes := integer(value(row, 'processes')) or {
		if err.msg().starts_with('OverflowError: ') { return err }
		return false
	}
	return processes >= big.integer_from_int(minimum)
}

pub fn detail_values(row Row) Value {
	kind := row['report'] or { Value('PERF-RESULT') }
	mut result := [kind]
	if kind is string {
		keys := match kind {
			'PERF-WAKEUPS' { ['via'] }
			'PERF-CHURN' { ['program'] }
			'PERF-OPS' { ['op', 'dir'] }
			else { []string{} }
		}
		for key in keys { result << row[key] or { Value('') } }
	}
	return Value(result)
}

pub fn detail(row Row) []string {
	kind := if 'report' in row { string_value(value(row, 'report')) } else { 'PERF-RESULT' }
	return match kind {
		'PERF-WAKEUPS' { [kind, string_value(row['via'] or { Value('') })] }
		'PERF-CHURN' { [kind, string_value(row['program'] or { Value('') })] }
		'PERF-OPS' {
			[kind, string_value(row['op'] or { Value('') }), string_value(row['dir'] or { Value('') })]
		}
		else { [kind] }
	}
}

pub struct Identity {
pub:
	variant  string
	scenario string
	round    string
	detail   []string
}

fn (identity Identity) key() string { return json2.encode(identity) }

fn quoted(text string) string {
	quote := if text.contains("'") && !text.contains('"') { '"' } else { "'" }
	mut output := quote
	for ch in text.runes() {
		if ch.str() == quote {
			output += '\\' + quote
		} else if ch == `\\` {
			output += '\\\\'
		} else if ch == `\n` {
			output += '\\n'
		} else if ch == `\r` {
			output += '\\r'
		} else if ch == `\t` {
			output += '\\t'
		} else if !printable(ch) {
			if ch <= 0xff {
				output += '\\x${int(ch):02x}'
			} else if ch <= 0xffff {
				output += '\\u${int(ch):04x}'
			} else {
				output += '\\U${int(ch):08x}'
			}
		} else {
			output += ch.str()
		}
	}
	return output + quote
}

fn (identity Identity) repr() string {
	return '(' + quoted(identity.variant) + ', ' + quoted(identity.scenario) + ', ' + identity.round + ', ' + identity.detail.map(quoted(it)).join(', ') + ')'
}

pub fn expected(variants []string, selected []string, rounds int) []Identity {
	mut plan := map[string]Identity{}
	for variant in variants {
		for scenario in selected {
			mut details := [][]string{}
			match scenario {
				'wakeups' {
					for via in ['nanosleep', 'poll'] { details << ['PERF-WAKEUPS', via] }
				}
				'churn' {
					for program in churn_programs { details << ['PERF-CHURN', program] }
				}
				'cache' { details << ['PERF-CACHE'] }
				'ops' {
					for op in general_ops { details << ['PERF-OPS', op, '/tmp'] }
					for directory in ['/tmp', '/root'] {
						for op in file_ops { details << ['PERF-OPS', op, directory] }
					}
				}
				else { details << ['PERF-RESULT'] }
			}
			for round in 1 .. rounds + 1 {
				for description in details {
					identity := Identity{variant, scenario, round.str(), description}
					plan[identity.key()] = identity
				}
			}
		}
	}
	return plan.values()
}

pub struct Verdict {
pub mut:
	rows    []map[string]Value
	reports []string
	errors  []string
}

fn identity_for(row Row) Identity {
	return Identity{string_value(value(row, 'variant')), string_value(value(row, 'scenario')), string_value(value(row, 'round')), detail(row)}
}

pub fn inspect(transcript []u8, variants []string, selected []string, rounds int, timed_out bool, exit_code ?Value) Verdict {
	mut verdict := Verdict{}
	mut plan := map[string]Identity{}
	for identity in expected(variants, selected, rounds) { plan[identity.key()] = identity }
	mut seen := map[string]bool{}
	mut completions := 0
	for line in byte_lines(transcript) {
		if line.trim(' \t\r\n\x0b\x0c') == done { completions++ }
		decoded := utf8_replace(line.bytes())
		for marker in ['KERNEL PANIC', 'FATAL EXCEPTION', 'PERF-ERROR'] {
			if line.contains(marker) {
				verdict.errors << decoded
				break
			}
		}
		for marker in reports {
			if at := line.index(marker) {
				verdict.reports << utf8_replace(line[at..].bytes())
				break
			}
		}
		mut row := parse_measurement(line) or {
			if measurement_kinds.any(line.contains(it)) {
				verdict.errors << 'malformed measurement: ' + decoded
			}
			continue
		}
		payload := string_value(value(row, '_payload'))
		row.delete('_payload')
		for field in shell_split(payload) or {
			verdict.errors << 'malformed measurement fields: ' + err.msg() + ': ' + decoded
			[]string{}
		} {
			if !field.contains('=') { continue }
			key := field.all_before('=')
			if key in row || key == 'report' {
				verdict.errors << 'malformed measurement fields: duplicate field ' + key + ': ' + decoded
				break
			}
			row[key] = field.all_after('=')
		}
		verdict.rows << row
		identity := identity_for(row)
		key := identity.key()
		if key !in plan {
			verdict.errors << 'unexpected measurement: ' + identity.repr()
		} else if key in seen {
			verdict.errors << 'duplicate measurement: ' + identity.repr()
		} else {
			seen[key] = true
		}
		if 'report' !in row && !(valid_desktop_result(row) or { false }) {
			verdict.errors << 'missing or invalid desktop metrics: ' + identity.repr()
		}
		validate_report(row, identity, mut verdict.errors)
	}
	if timed_out { verdict.errors << 'overall measurement timeout expired' }
	if code := exit_code {
		if (code is Number && (metric(code) or { 1 }) != 0) || (code is bool && code) || (code !is Number && code !is bool) {
			verdict.errors << 'guest process exited with status ' + string_value(code)
		}
	}
	if completions != 1 {
		verdict.errors << 'expected one VINIX DESKTOP PERF: DONE marker, received ${completions}'
	}
	mut missing := plan.values().filter(it.key() !in seen)
	missing.sort_with_compare(fn (a &Identity, b &Identity) int {
		if a.variant != b.variant { return if a.variant < b.variant { -1 } else { 1 } }
		if a.scenario != b.scenario { return if a.scenario < b.scenario { -1 } else { 1 } }
		if a.round != b.round { return if a.round.int() < b.round.int() { -1 } else { 1 } }
		for index in 0 .. a.detail.len {
			if a.detail[index] != b.detail[index] {
				return if a.detail[index] < b.detail[index] { -1 } else { 1 }
			}
		}
		return 0
	})
	if missing.len != 0 {
		limit := if missing.len < 5 { missing.len } else { 5 }
		verdict.errors << '${missing.len} of ${plan.len} measurements missing: ' + missing[..limit].map(it.repr()).join('; ')
	}
	return verdict
}
