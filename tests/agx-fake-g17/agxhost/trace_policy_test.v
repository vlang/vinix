// SPDX-License-Identifier: GPL-2.0-only
module agxhost

import g17power as power
import traceanalysis as j

fn trace_test_value(text string) j.Value { return power.decode_device_json(text) or { panic(err) } }

fn test_original_numeric_equality_preserves_boolean_float_and_integer_width() {
	for pair in [['true', '1'], ['false', '0.0'], ['2', '2.0'], ['[NaN]', '[NaN]'],
		['18446744073709551616', '18446744073709551616.0']] {
		assert trace_equal(trace_test_value(pair[0]), trace_test_value(pair[1]))
	}
	for pair in [['9007199254740993', '9007199254740992.0'], ['18446744073709551615', '18446744073709551616.0'],
		['2', '2.5'], ['NaN', 'NaN'], ['"2"', '2']] {
		assert !trace_equal(trace_test_value(pair[0]), trace_test_value(pair[1]))
	}
	wide := '1' + '0'.repeat(400)
	assert trace_equal(trace_test_value(wide), trace_test_value(wide))
	assert !trace_equal(trace_test_value(wide), trace_test_value('Infinity'))
}

fn test_original_check_failure_order_and_typed_arguments() {
	if _ := trace_check([]j.Value{}, 'normal', 8) {
		assert false
	} else {
		assert err is TraceFailure && err.kind == 'IndexError'
		assert j.string_value(err.argument) == 'list index out of range'
	}
	for schema in ['1', '2.0'] {
		rows := trace_test_value('[{"event":"trace_start","schema":' + schema + '},{}]').arr()
		trace_check(rows, 'normal', 8) or {
			assert err is TraceFailure
			assert err.kind == if schema == '1' { 'AssertionError' } else { 'KeyError' }
			if schema == '2.0' { assert j.string_value(err.argument) == 'event' }
			continue
		}
		assert false
	}
}

fn test_original_section_first_match_unicode_and_unbounded_alignment() {
	section := 'sectname __interpose segname __DATA addr 0 size 80 offset 0 align 2^3 (8) reloff 0 nreloc 16'
	assert trace_interpose_section(section) or { panic(err) }
	assert trace_interpose_section(section.replace('2^3', '2^' + '9'.repeat(200))) or { panic(err) }
	assert trace_interpose_section(section.replace('2^3', '2^३').replace('(8)', '(٨)').replace('__interpose segname', '__interpose\u2003segname')) or { panic(err) }
	assert !(trace_interpose_section(section.replace('size 80', 'size 7f') + '\n' + section) or { panic(err) })
	trace_interpose_section(section.replace('size 80', 'size bad!') + '\n' + section) or {
		assert err is TraceFailure && err.kind == 'HexIntegerError'
		assert j.string_value(err.argument) == 'bad!'
		return
	}
	assert false
}

fn test_normalized_rows_own_numbers_after_source_retirement_and_split_unicode_lines() {
	mut source := '{"storage":"0x0","x":18446744073709551617}\u2028{"object":"0x403"}\r\n'.clone()
	rows := trace_normalized(source) or { panic(err) }
	unsafe { source.free() }
	source = ''
	assert rows.len == 2
	assert j.encode(rows[0], false) == '{"storage":"NULL","x":18446744073709551617}'
	assert j.encode(rows[1], false) == '{"object":"pointer-0"}'
}
