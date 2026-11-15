// SPDX-License-Identifier: GPL-2.0-or-later
import os

const helpers = [
	'gpu__agx__file__install_g13_batch_barriers',
	'gpu__agx__gpu__GpuManager__initialize_g13_barriers_locked',
	'gpu__agx__gpu__GpuManager__publish_g13_compute_job_locked',
	'gpu__agx__gpu__GpuManager__submit_g13_queue_commands',
	'gpu__agx__gpu__GpuManager__publish_g13_render_job_locked',
	'gpu__agx__file__poll_g13_pending',
	'gpu__agx__file__g13_pending_dispatch_complete',
	'gpu__agx__file__process_pending_submissions',
]

fn function_body(source string, name string) !string {
	marker := (if name.ends_with('process_pending_submissions') { 'void ' } else { 'bool ' }) + name + '('
	mut cursor := 0
	mut found := ''
	for cursor < source.len {
		start := source.index_after(marker, cursor) or { break }
		line_end := source.index_after('\n', start) or { return error('unterminated signature: ' + name) }
		cursor = line_end + 1
		if !source[start..line_end].trim_space().ends_with('{') { continue }
		finish := source.index_after('\n}\n', cursor) or { return error('unterminated body: ' + name) }
		if found != '' { return error('duplicate body: ' + name) }
		found = source[start..finish + 3]
		cursor = finish + 3
	}
	if found == '' { return error('missing body: ' + name) }
	return found
}

fn check(source string) ! {
	for name in helpers {
		body := function_body(source, name)!
		for allocation in ['memdup', 'HEAP(', 'malloc', 'calloc', 'realloc', '__new_array',
			'new_array_from', 'array_clone', 'array_slice'] {
			if body.contains(allocation) { return error(name + ': unexpected temporary allocation: ' + allocation) }
		}
		if name.ends_with('publish_g13_compute_job_locked') && !body.contains('u64 storage[3];') {
			return error('compute prefix storage is not a fixed stack array')
		}
		if name.ends_with('process_pending_submissions') &&
			(!body.contains('void* blocked[128]') || !body.contains('bool unpublished[128]')) {
			return error('scheduler queue gates are not fixed stack arrays')
		}
	}
}

fn selftest() ! {
	mut fixture := ''
	for name in helpers {
		kind := if name.ends_with('process_pending_submissions') { 'void' } else { 'bool' }
		ending := if kind == 'void' { 'return;' } else { 'return true;' }
		fixture += kind + ' ' + name + '(void) {\n u64 storage[3];\n void* blocked[128];\n bool unpublished[128];\n ' + ending + '\n}\n'
	}
	check(fixture)!
	for name in helpers {
		for allocation in ['memdup', 'HEAP(', 'malloc', 'calloc', 'realloc', '__new_array',
			'new_array_from', 'array_clone', 'array_slice'] {
			if _ := check(fixture.replace(name + '(void) {', name + '(void) { ' + allocation + ';')) {
				return error('allocation selftest accepted ' + name + ': ' + allocation)
			}
		}
	}
	for broken in ['', fixture.replace('u64 storage[3];', 'u64* storage;'), fixture + fixture,
		fixture.replace('void* blocked[128];', 'void** blocked;'),
		fixture.replace('bool unpublished[128];', 'bool* unpublished;')] {
		if _ := check(broken) { return error('malformed storage selftest accepted') }
	}
	println('G13 prefix storage checker selftest: PASS')
}

fn main() {
	if os.args.len != 2 { eprintln('Usage: check-prefix-storage GENERATED_ARM_C | --selftest'); exit(2) }
	if os.args[1] == '--selftest' { selftest() or { eprintln(err); exit(1) }; return }
	source := os.read_file(os.args[1]) or { eprintln(err); exit(2) }
	check(source) or { eprintln(err); exit(1) }
	println('G13 submission storage: eight generated barrier/publisher/scheduler helpers contain no temporary allocations')
}
