// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn require(ok bool, message string) ! { if !ok { return error(message) } }
fn body(source string, name string) !string {
	for line in source.split_into_lines() {
		if line.len == 0 || line[0].is_space() || !line.contains(' ' + name + '(') || !line.ends_with(' {') { continue }
		start := source.index(line) or { return error(name) }; end := source.index_after('\n}\n', start) or { return error(name) }
		return source[start..end + 3]
	}
	return error('missing C definition: ' + name)
}
fn normalize(source string, code string) !string {
	mut strings := map[string]string{}
	for line in source.split_into_lines() { if line.starts_with('_SL(_str_') {
		key := line.all_after('_SL(').all_before(','); strings[key] = line.all_after(key + ', ')
	} }
	mut temps := map[string]string{}; mut out := []u8{}; mut i := 0
	for i < code.len {
		if code[i..].starts_with('_str_') {
			mut end := i + 5; for end < code.len && code[end].is_digit() { end++ }
			key := code[i..end]; require(key in strings, key)!; out << strings[key].bytes(); i = end; continue
		}
		mut end := i
		for token in ['__for_idx_', '__or_opt_', '__or_val_', '_t', '_a', '_i'] {
			if !code[i..].starts_with(token) || i + token.len >= code.len || !code[i + token.len].is_digit() { continue }
			end = i + token.len; for end < code.len && code[end].is_digit() { end++ }; break
		}
		if end > i {
			key := code[i..end]; if key !in temps { temps[key] = '_TMP' + temps.len.str() }
			out << temps[key].bytes(); i = end
		} else { out << code[i]; i++ }
	}
	return out.bytestr()
}
fn declaration(source string, name string) !string {
	start := source.index('struct ' + name + ' {') or { return error(name) }
	end := source.index_after('\n};', start) or { return error(name) }; return source[start..end + 3]
}
fn same(current string, old string, name string, code string) ! {
	a := normalize(current, code)!; b := normalize(old, body(old, name)!)!
	if a != b {
		if directory := os.getenv_opt('AGX_DEFER_DIAGNOSTICS') {
			os.write_file(directory + '/current-' + name + '.txt', a)!
			os.write_file(directory + '/baseline-' + name + '.txt', b)!
		}
		return error('unchanged body: ' + name)
	}
}
fn ordered(code string, tokens []string) ! {
	mut offset := 0
	for token in tokens { pos := code.index_after(token, offset) or { return error('missing/out-of-order ' + token) }; offset = pos + token.len }
}
fn loop_block(code string, token string) !string {
	pos := code.index(token) or { return error(token) }
	start := code[..pos].last_index('\n\t{') or { return error('loop start') }
	end := code.index_after('\n\t}\n', pos) or { return error('loop end') }
	return code[start + 1..end + 4]
}
fn compare(current string, old string) !int {
	p := 'gpu__agx__gpu__'; f := 'gpu__agx__file__GpuFile__'; m := p + 'GpuManager__'
	dispose := p + 'free_g13_queue_record'
	code := body(current, dispose)!
	require(code == 'void ' + dispose + '(' + p + 'G13QueueResources* resources) {\n\t{\n\t\tv_free(resources);\n\t}\n}\n', 'production disposer is exactly one free without later reads or allocation; debug assertions are compiled out')!
	require(current.count(dispose + '(') == 5, 'only three final-owner call sites plus declaration and definition')!
	mut close := body(current, f + 'close')!
	guards := loop_block(close, p + 'G13QueueResources__has_file_references(')!
	ordered(guards, ['f->g13_queues.len', p + 'G13QueueResources__has_file_references(ownership.resources)', 'klock__Lock__release(&f->lock);', 'return false;'])!
	close = close.replace(guards, '')
	manager_guard := '((f->timestamp_objects.len != 0) || (f->g13_queues.len != 0))'
	require(close.count(manager_guard) == 1, 'manager absence retains nonempty G13 ownership')!
	close = close.replace(manager_guard, '(f->timestamp_objects.len != 0)')
	pop := loop_block(close, dispose + '(')!
	ordered(pop, ['f->g13_queues.len - 1', 'ownership =', 'array_delete(&f->g13_queues, v_index);', dispose + '(ownership.resources);'])!
	close = close.replace(pop, '')
	same(current, old, f + 'close', close)!
	for suffix in ['reap_detached_g13_queues_locked', 'reap_orphaned_g13_queues_locked'] {
		reap := body(current, f + suffix)!
		call := '\t\t\t' + dispose + '(ownership.resources);\n'
		require(reap.count(call) == 1, 'one final-owner call in reaper')!
		ordered(reap, [p + 'G13QueueResources__has_file_references(', m + 'release_g13_queue_resources(', 'array_delete(&f->g13_queues,', dispose + '(ownership.resources);'])!
		same(current, old, f + suffix, reap.replace(call, ''))!
	}
	mut unchanged := 0
	for suffix in ['create_g13_queue_resources', 'free_g13_queue_resources_locked', 'invalidate_g13_context_locked',
		'defer_g13_context_locked', 'append_g13_context_locked', 'collect_g13_context_garbage_locked', 'collect_g13_heap_garbage_locked',
		'release_g13_queue_resources', 'retained_g13_queue_resources', 'release_all_g13_queue_resources', 'g13_queue_dispatch_blocked_locked',
		'free_shared_buffer', 'release_shared_buffer_backing', 'invalidate_g13_queue_mappings_locked',
		'free_g13_render_job_locked', 'free_g13_compute_job_locked', 'reap_g13_render_jobs', 'reap_g13_compute_jobs',
		'shutdown', 'capture_g13_initial_events', 'release_g13_initial_events'] {
		same(current, old, m + suffix, body(current, m + suffix)!)!; unchanged++
	}
	for name in [p + 'G13QueueResources__retain_file_reference', p + 'G13QueueResources__release_file_reference',
		p + 'G13QueueResources__has_file_references', f + 'capture_submission_queue', f + 'retire_mapping_locked',
		'gpu__agx__file__release_submission_queue', 'gpu__agx__file__process_pending_submissions',
		'alloc__HeapAllocator__alloc', 'alloc__HeapAllocator__release', 'alloc__HeapAllocator__collect_garbage_locked'] {
		same(current, old, name, body(current, name)!)!; unchanged++
	}
	for name in [p + 'G13QueueResources', p + 'GpuManager', 'gpu__agx__file__GpuFile', 'gpu__agx__file__G13QueueOwnership'] {
		require(declaration(current, name)! == declaration(old, name)!, 'owning layout unchanged: ' + name)!
	}
	return unchanged
}
fn main() {
	assert os.args.len == 4
	current := os.read_file(os.args[2])!; old := os.read_file(os.args[3])!
	count := compare(current, old)!
	println('Queue record native C: one free with exactly three guarded final-owner callers, exact close/capture/manager/pop and reaper additions; four owning layouts and ' + count.str() + ' backing/context/capture/initial-event/pending/heap bodies unchanged.')
	if os.args[1] == '--selftest' {
		for pair in [['v_free(resources);', '/* omitted free */'],
			['gpu__agx__gpu__free_g13_queue_record(ownership.resources);', '/* omitted final owner disposal */'],
			['array_delete(&f->g13_queues, v_index);', 'array_delete(&f->g13_queues, 0);'],
			['(f->g13_queues.len != 0)', '(false)'],
			['G13QueueResources__has_file_references(ownership.resources)', 'G13QueueResources__has_file_references(NULL)'],
			['void gpu__agx__gpu__free_g13_queue_record(gpu__agx__gpu__G13QueueResources* resources) {', 'void gpu__agx__gpu__free_g13_queue_record(gpu__agx__gpu__G13QueueResources* resources) { malloc(1);'],
			['resources->context_next = NULL;', '/* stale deferred link */'],
			['katomic__dec_T_u64(&queue->file_references);', '/* missing final queue reference release */']] {
			changed := current.replace(pair[0], pair[1]); require(changed != current, 'mutation anchor: ' + pair[0])!
			if _ := compare(changed, old) { panic('accepted final-owner lifetime mutation') }
		}
		println('Queue record C checker: eight disposal/owner-index/manager/capture/allocation/link/reference mutations rejected.')
	} else { assert os.args[1] == '--native' }
}
