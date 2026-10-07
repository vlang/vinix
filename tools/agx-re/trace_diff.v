module main

import encoding.hex
import os
import strconv
import traceanalysis as trace

const usage = 'usage: trace_diff [-h] [--event EVENT] [--left LEFT] [--right RIGHT]\n                  [--index INDEX] [--where KEY=VALUE] [--json] [--walk]\n                  trace'

fn fail(message string) {
	eprintln(usage)
	eprintln('trace_diff: error: ${message}')
	exit(2)
}

fn main() {
	mut path := ''
	mut event := 'segment'
	mut left_phase := 'clear'
	mut right_phase := 'triangle'
	mut index := 0
	mut filters := map[string]string{}
	mut as_json := false
	mut walk := false
	mut cursor := 1
	for cursor < os.args.len {
		argument := os.args[cursor]
		cursor++
		if argument in ['-h', '--help'] {
			println(usage + '\n\nCompare byte snapshots from two labelled phases in an AGX JSONL trace.\n\n--where KEY=VALUE  Require a JSON record field to equal VALUE; may be repeated.\n--walk             Parse each segment with the recovered record framing.')
			return
		}
		if argument == '--json' {
			as_json = true
			continue
		}
		if argument == '--walk' {
			walk = true
			continue
		}
		if argument.starts_with('--') {
			option := argument.all_before('=')
			if option !in ['--event', '--left', '--right', '--index', '--where'] {
				fail('unrecognized arguments: ${argument}')
			}
			mut value := ''
			if argument.contains('=') {
				value = argument.all_after('=')
			} else {
				if cursor >= os.args.len { fail('argument ${option}: expected one argument') }
				value = os.args[cursor]
				cursor++
			}
			match option {
				'--event' { event = value }
				'--left' { left_phase = value }
				'--right' { right_phase = value }
				'--index' {
					index = strconv.atoi(value) or {
						fail('argument --index: invalid int value: ${trace.quoted(value)}')
						0
					}
				}
				'--where' {
					separator := value.index('=') or {
						fail('invalid --where ${trace.quoted(value)}; expected KEY=VALUE')
						0
					}
					if separator == 0 {
						fail('invalid --where ${trace.quoted(value)}; expected KEY=VALUE')
					}
					filters[value[..separator]] = value[separator + 1..]
				}
				else {}
			}
		} else if path == '' {
			path = argument
		} else {
			fail('unrecognized arguments: ${argument}')
		}
	}
	if path == '' { fail('the following arguments are required: trace') }
	left := trace.load_snapshot(path, event, left_phase, index, filters) or {
		fail(err.msg())
		[]u8{}
	}
	right := trace.load_snapshot(path, event, right_phase, index, filters) or {
		fail(err.msg())
		[]u8{}
	}
	if walk {
		labels := [left_phase, right_phase]
		for position, data in [left, right] {
			phase := labels[position]
			walked := trace.walk_segment(data) or {
				fail(err.msg())
				trace.Object{}
			}
			records := trace.value(walked, 'records').arr()
			println('${phase}: magic=0x${trace.value(walked, 'magic').u64():x} ${trace.value(walked, 'declared_bytes').int()} bytes, ${records.len} record(s), ${trace.value(walked, 'trailing_bytes').int()} trailing')
			for number, entry in records {
				record := entry.as_map()
				println('  record ${number}: 0x${trace.value(record, 'offset').int():04x} +0x${trace.record_header_bytes:x} header +0x${trace.value(record, 'payload_bytes').int():x} payload -> 0x${trace.value(record, 'payload_end').int():04x}')
				header := trace.value(record, 'header').as_map()
				println('    stream fields: primary=0x${trace.value(header, 'primary_extension_bytes').u64():x} aux-u16=0x${trace.value(header, 'auxiliary_u16_flag').u64():x}/0x${trace.value(header, 'auxiliary_u16_bytes').u64():x} aux-u64=0x${trace.value(header, 'auxiliary_u64_flag').u64():x}/0x${trace.value(header, 'auxiliary_u64_bytes').u64():x}')
				if 'render_validation' in record {
					validation := trace.value(record, 'render_validation').as_map()
					println('    render validation: equal=${array_text(trace.value(validation, 'equal_bits'))} implies=${array_text(trace.value(validation, 'implication_bits'))} valid')
				}
				if 'primary_extension' in record {
					extension := trace.value(record, 'primary_extension').as_map()
					println('    primary extension: counts=${array_text(trace.value(extension, 'counts'))} item_bytes=${array_text(trace.value(extension, 'item_bytes'))} -> 0x${trace.value(extension, 'end').int():04x}')
				}
			}
		}
		return
	}
	runs := trace.difference_runs(left, right)
	mut run_records := []trace.Value{}
	mut different_bytes := 0
	for run in runs {
		different_bytes += run.end - run.start
		run_records << trace.Value(map[string]trace.Value{
			'start': trace.Value(run.start)
			'end':   trace.Value(run.end)
			'left':  trace.Value(hex.encode(left[imin(run.start, left.len)..imin(run.end, left.len)]))
			'right': trace.Value(hex.encode(right[imin(run.start, right.len)..imin(run.end, right.len)]))
		})
	}
	mut where := map[string]trace.Value{}
	for key, value in filters { where[key] = trace.Value(value) }
	result := map[string]trace.Value{
		'event':           trace.Value(event)
		'index':           trace.Value(index)
		'left':            trace.Value(left_phase)
		'left_bytes':      trace.Value(left.len)
		'right':           trace.Value(right_phase)
		'right_bytes':     trace.Value(right.len)
		'where':           trace.Value(where)
		'different_bytes': trace.Value(different_bytes)
		'runs':            trace.Value(run_records)
	}
	if as_json {
		println(trace.encode(trace.Value(result), true))
		return
	}
	println('${event} #${index}: ${left_phase}=${left.len} bytes, ${right_phase}=${right.len} bytes, ${different_bytes} differing bytes in ${runs.len} runs')
	for entry in run_records {
		run := entry.as_map()
		left_hex := trace.string_value(trace.value(run, 'left'))
		right_hex := trace.string_value(trace.value(run, 'right'))
		println('  0x${trace.value(run, 'start').int():04x}-0x${trace.value(run, 'end').int():04x}: ${left_phase}=${if left_hex != '' {
			left_hex
		} else {
			'-'
		}} ${right_phase}=${if right_hex != '' { right_hex } else { '-' }}')
	}
}

fn imin(a int, b int) int { return if a < b { a } else { b } }

fn array_text(value trace.Value) string {
	return trace.encode(value, false).replace(',', ', ')
}
