// SPDX-License-Identifier: GPL-2.0-or-later
import os

const helpers = [
	'gpu__agx__file__install_g13_batch_barriers',
	'gpu__agx__gpu__GpuManager__initialize_g13_barriers_locked',
	'gpu__agx__gpu__GpuManager__publish_g13_compute_job_locked',
	'gpu__agx__gpu__GpuManager__submit_g13_queue_commands',
	'gpu__agx__gpu__GpuManager__g13_ring_has_space_locked',
	'gpu__agx__gpu__GpuManager__publish_g13_render_job_locked',
	'gpu__agx__file__poll_g13_pending',
	'gpu__agx__file__g13_pending_dispatch_complete',
	'gpu__agx__file__process_pending_submissions',
	'gpu__agx__file__register_g13_pending',
	'gpu__agx__file__admit_g13_pending',
	'gpu__agx__gpu__GpuManager__g13_batch_ready',
	'gpu__agx__file__g13_dependencies_ready',
	'syncobj__queue_dependency_ready',
	'gpu__agx__gpu__GpuManager__queue_g13_submission',
	'gpu__agx__gpu__GpuManager__accept_g13_submission_locked',
	'gpu__agx__gpu__GpuManager__capture_g13_initial_events',
	'gpu__agx__gpu__GpuManager__release_g13_initial_events',
	'gpu__agx__gpu__GpuManager__resolve_g13_initial_barriers_locked',
	'gpu__agx__gpu__write_g13_barrier',
	'gpu__agx__gpu__release_g13_barrier_pins',
	'gpu__agx__event__WorkQueueEvents__resolve_initial',
	'gpu__agx__event__WorkQueueEvents__ticket',
	'gpu__agx__event__WorkQueueEvents__retain',
	'gpu__agx__event__WorkQueueEvents__release',
	'gpu__agx__event__WorkQueueEvents__can_publish',
	'gpu__agx__event__WorkQueueEvents__can_submit',
	'gpu__agx__event__WorkQueueEvents__admit',
	'gpu__agx__event__WorkQueueEvents__publish',
	'gpu__agx__gpu__g13_barrier_source',
]

fn result_type(name string) string {
	if name.ends_with('process_pending_submissions') || name.ends_with('write_g13_barrier')
		|| name.ends_with('release_g13_initial_events') || name.ends_with('release_g13_barrier_pins') { return 'void' }
	if name.ends_with('capture_g13_initial_events') { return '__v_option_gpu__agx__gpu__G13InitialEvents' }
	if name.ends_with('WorkQueueEvents__ticket') || name.ends_with('WorkQueueEvents__retain') || name.ends_with('g13_barrier_source') { return '__v_option_gpu__agx__event__Ticket' }
	if name.ends_with('WorkQueueEvents__resolve_initial') { return 'multi_return_int_gpu__agx__event__Ticket' }
	return 'bool'
}

fn function_body(source string, name string) !string {
	marker := result_type(name) + ' ' + name + '('
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
		for copy in ['__v3_struct_eq', 'G13QueueResources __eq'] {
			if body.contains(copy) { return error(name + ': unexpected structural copy/comparison: ' + copy) }
		}
		if name.ends_with('publish_g13_compute_job_locked') && !body.contains('u64 storage[3];') {
			return error('compute prefix storage is not a fixed stack array')
		}
		if name.ends_with('process_pending_submissions') &&
			(!body.contains('void* blocked[128]') || !body.contains('bool unpublished[128]')) {
			return error('scheduler queue gates are not fixed stack arrays')
		}
		if (name.ends_with('register_g13_pending') || name.ends_with('admit_g13_pending')) && !body.contains('G13SubmissionJob jobs[64]') {
			return error('acceptance references are not a fixed stack array')
		}
		if name.ends_with('g13_batch_ready') && (!body.contains('u32 events[3]') || !body.contains('u32 commands[3]')) {
			return error('batch capacity counts are not fixed stack arrays')
		}
		if name.ends_with('resolve_g13_initial_barriers_locked') && !body.contains('Ticket resolved[2]') {
			return error('resolved initial tickets are not a fixed stack array')
		}
	}
}

fn selftest() ! {
	mut fixture := ''
	for name in helpers {
		kind := result_type(name)
		ending := if kind == 'void' { 'return;' } else if kind == 'bool' { 'return true;' } else { 'return (' + kind + '){0};' }
		fixture += kind + ' ' + name + '(void) {\n u64 storage[3];\n void* blocked[128];\n bool unpublished[128];\n gpu__agx__gpu__G13SubmissionJob jobs[64];\n gpu__agx__event__Ticket resolved[2];\n u32 events[3];\n u32 commands[3];\n ' + ending + '\n}\n'
	}
	check(fixture)!
	for name in helpers {
		for allocation in ['memdup', 'HEAP(', 'malloc', 'calloc', 'realloc', '__new_array',
			'new_array_from', 'array_clone', 'array_slice', '__v3_struct_eq', 'G13QueueResources __eq'] {
			if _ := check(fixture.replace(name + '(void) {', name + '(void) { ' + allocation + ';')) {
				return error('allocation selftest accepted ' + name + ': ' + allocation)
			}
		}
	}
	for broken in ['', fixture.replace('u64 storage[3];', 'u64* storage;'), fixture + fixture,
		fixture.replace('void* blocked[128];', 'void** blocked;'),
		fixture.replace('bool unpublished[128];', 'bool* unpublished;'),
		fixture.replace('G13SubmissionJob jobs[64];', 'G13SubmissionJob* jobs;'),
		fixture.replace('u32 events[3];', 'u32* events;'),
		fixture.replace('u32 commands[3];', 'u32* commands;'),
		fixture.replace('Ticket resolved[2];', 'Ticket* resolved;')] {
		if _ := check(broken) { return error('malformed storage selftest accepted') }
	}
	println('G13 prefix storage checker selftest: PASS')
}

fn main() {
	if os.args.len != 2 { eprintln('Usage: check-prefix-storage GENERATED_ARM_C | --selftest'); exit(2) }
	if os.args[1] == '--selftest' { selftest() or { eprintln(err); exit(1) }; return }
	source := os.read_file(os.args[1]) or { eprintln(err); exit(2) }
	check(source) or { eprintln(err); exit(1) }
	println('G13 submission storage: thirty generated barrier/publisher/scheduler/initial-event/dependency/admission helpers contain no temporary allocations')
}
