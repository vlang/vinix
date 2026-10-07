module main

import os
import strconv
import traceanalysis as trace

const usage = 'usage: map_g17_resource_descriptors [-h] --abi ABI [--phase PHASES]\n                                    [--segment-index SEGMENT_INDEX] [--json]\n                                    trace'

fn fail(message string) {
	eprintln(usage)
	eprintln('map_g17_resource_descriptors: error: ${message}')
	exit(2)
}

fn main() {
	mut path := ''
	mut abi_path := ''
	mut phases := []string{}
	mut segment_index := 0
	mut as_json := false
	mut cursor := 1
	for cursor < os.args.len {
		argument := os.args[cursor]
		cursor++
		if argument in ['-h', '--help'] {
			println(usage + '\n\nMap traced Apple resource pointers through recovered G17 descriptor copies.\nOnly candidate copies are reported; no Mesa semantic mapping is claimed.\n\n--phase PHASES  May be repeated (default: clear, triangle).')
			return
		}
		if argument == '--json' {
			as_json = true
			continue
		}
		if argument.starts_with('--') {
			option := argument.all_before('=')
			if option !in ['--abi', '--phase', '--segment-index'] {
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
				'--abi' { abi_path = value }
				'--phase' { phases << value }
				'--segment-index' {
					segment_index = strconv.atoi(value) or {
						fail('argument --segment-index: invalid int value: ${trace.quoted(value)}')
						0
					}
				}
				else {}
			}
		} else if path == '' {
			path = argument
		} else {
			fail('unrecognized arguments: ${argument}')
		}
	}
	mut required := []string{}
	if path == '' { required << 'trace' }
	if abi_path == '' { required << '--abi' }
	if required.len != 0 { fail('the following arguments are required: ' + required.join(', ')) }
	if segment_index < 0 { fail('--segment-index must not be negative') }
	if phases.len == 0 { phases = ['clear', 'triangle'] }
	records := trace.load_jsonl(path) or {
		fail(err.msg())
		[]map[string]trace.Value{}
	}
	abi := trace.load_json(abi_path) or {
		fail(err.msg())
		map[string]trace.Value{}
	}
	mut reports := []trace.Value{}
	for phase in phases {
		report := trace.correlate_phase(records, abi, phase, segment_index) or {
			fail(err.msg())
			trace.Object{}
		}
		reports << trace.Value(report)
	}
	if as_json {
		println(trace.encode(trace.Value(map[string]trace.Value{
			'phases': trace.Value(reports)
		}), true))
	} else {
		for report in reports { print_report(report.as_map()) }
	}
}

fn print_report(report trace.Object) {
	phase := trace.string_value(trace.value(report, 'phase'))
	candidates := trace.value(report, 'descriptor_candidates').arr()
	unmapped := trace.value(report, 'unmapped_occurrences').arr()
	println('${phase}: ${trace.value(report, 'traced_resource_ranges').int()} traced range(s), ${trace.value(report, 'resource_occurrences').int()} pointer occurrence(s), ${candidates.len} descriptor candidate(s), ${unmapped.len} unmapped')
	for entry in candidates {
		item := entry.as_map()
		println('  segment +0x${trace.value(item, 'segment_source_offset').u64():x} payload +0x${trace.value(item, 'payload_offset').u64():x} -> descriptor +0x${trace.number_hex(trace.value(item, 'descriptor_member'))} (${trace.string_value(trace.value(item, 'stage'))}): 0x${trace.value(item, 'gpu_address').u64():x} in 0x${trace.value(item, 'resource_gpu_address').u64():x}+0x${trace.value(item, 'resource_offset').u64():x}/0x${trace.value(item, 'resource_bytes').u64():x}')
	}
	for entry in unmapped {
		item := entry.as_map()
		payload := if 'payload_offset' in item {
			' payload +0x${trace.value(item, 'payload_offset').u64():x}'
		} else {
			''
		}
		println('  unmapped segment +0x${trace.value(item, 'segment_source_offset').u64():x}${payload}: 0x${trace.value(item, 'gpu_address').u64():x} (${trace.string_value(trace.value(item, 'reason'))})')
	}
	println('  note: ${trace.string_value(trace.value(report, 'interpretation'))}')
}
