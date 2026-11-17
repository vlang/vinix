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
	w := 'workqueue__'; f := 'gpu__agx__file__GpuFile__'; fake := 'fake__FakeG17File__'; dispose := w + 'free_workqueue'
	require(body(current, dispose)! == 'void ' + dispose + '(' + w + 'WorkQueue* queue) {\n\t{\n\t\tv_free(queue);\n\t}\n}\n', 'metadata disposer is exactly one free, no allocation or post-free access')!
	mut changed := 0
	for prefix in [f, fake] {
		name := prefix + if prefix == f { 'close' } else { 'finish_close_locked' }
		mut close := body(current, name)!
		pop := loop_block(close, dispose + '(')!
		owner := if prefix == f { 'f' } else { 'file' }
		ordered(pop, [owner + '->queues.len - 1', 'WorkQueue* queue =', 'array_delete(&' + owner + '->queues, v_index);', dispose + '(queue);'])!
		close = close.replace(pop, if prefix == f { '' } else { '\tarray__clear(&file->queues);\n' })
		same(current, old, name, close)!; changed++
		name2 := prefix + 'ioctl_queue_destroy'
		mut code := body(current, name2)!
		alias := if prefix == f { 'q' } else { 'queue' }
		snapshot := '\t\t\t\tworkqueue__WorkQueue* record = *' + alias + ';\n'
		call := '\t\t\t\t' + dispose + '(record);\n'
		require(code.count(snapshot) == 1 && code.count(call) == 1, 'one stable pointer and one final-owner disposal')!
		ordered(code, [w + 'WorkQueue__destroy(*' + alias + ');', snapshot.trim_space(), 'array_delete(&' + owner + '->queues,', dispose + '(record);', 'klock__Lock__release(&' + owner + '->lock);'])!
		same(current, old, name2, code.replace(snapshot, '').replace(call, ''))!; changed++
	}
	if changed == 4 {
		name := f + 'ioctl_queue_create'
		code := body(current, name)!
		require(code.count(dispose + '(queue);') == 2, 'both constructor failure branches dispose')!
		same(current, old, name, code.replace(dispose + '(queue);', '{\n\t\t\t\tv_free(queue);\n\t\t\t}'))!
		name2 := f + 'reap_detached_g13_queues_locked'
		code2 := body(current, name2)!
		call := '\t\t\t' + dispose + '(q);\n'
		require(code2.count(call) == 1, 'one detached final-owner disposal')!
		ordered(code2, ['has_file_references(', 'release_g13_queue_resources(', 'WorkQueue__destroy(q);', 'array_delete(&f->queues, i);', 'array_delete(&f->g13_queues, owner_index);', dispose + '(q);'])!
		same(current, old, name2, code2.replace(call, ''))!
		changed += 2
	}
	require(changed == 6 && current.count(dispose + '(') == 9, 'only seven ARM owner calls plus declaration/definition')!
	mut constructor := body(current, w + 'new_workqueue')!
	line := '\tworkqueue__WorkQueue* queue = (workqueue__WorkQueue*)memdup(&(workqueue__WorkQueue){.id = id, .vm_id = vm_id, .priority = priority, .caps = caps}, sizeof(workqueue__WorkQueue));\n'
	require(constructor.count(line) == 1, 'one unchanged-size constructor allocation')!
	constructor = constructor.replace(line, '').replace('.value = queue}', '.value = (workqueue__WorkQueue*)memdup(&(workqueue__WorkQueue){.id = id, .vm_id = vm_id, .priority = priority, .caps = caps}, sizeof(workqueue__WorkQueue))}')
	same(current, old, w + 'new_workqueue', constructor)!
	mut count := 0
	for name in [w + 'WorkQueue__destroy', w + 'WorkQueue__submit', w + 'WorkQueue__complete',
		'fake__fake_completion_worker', fake + 'close', fake + 'finish_pending_job', fake + 'ioctl_submit'] {
		same(current, old, name, body(current, name)!)!; count++
	}
	if changed == 6 {
		for suffix in ['release_g13_queue_resources', 'free_g13_queue_resources_locked', 'reap_g13_render_jobs', 'reap_g13_compute_jobs', 'invalidate_g13_context_locked', 'collect_g13_context_garbage_locked', 'collect_g13_heap_garbage_locked'] {
			name := 'gpu__agx__gpu__GpuManager__' + suffix
			same(current, old, name, body(current, name)!)!; count++
		}
		for name in [f + 'capture_submission_queue', 'gpu__agx__file__release_submission_queue', 'gpu__agx__file__process_pending_submissions', f + 'retire_mapping_locked'] {
			same(current, old, name, body(current, name)!)!; count++
		}
	}
	for name in [w + 'WorkQueue', w + 'WorkItem', 'fake__FakeG17File', 'fake__FakeG17PendingCompletion'] {
		require(declaration(current, name)! == declaration(old, name)!, 'unchanged layout: ' + name)!
	}
	return count
}
fn main() {
	assert os.args.len == 4 && os.args[1] in ['--native', '--selftest']
	current := os.read_file(os.args[2])!; old := os.read_file(os.args[3])!
	count := compare(current, old)!
	println('Logical queue C: exact final-owner additions, stable pointer snapshots, seven ARM call sites, unchanged layouts and ' + count.str() + ' unchanged cancellation/completion/ownership bodies passed.')
	if os.args[1] == '--selftest' {
		for pair in [['v_free(queue);', '/* leaked metadata */'],
			['workqueue__free_workqueue(record);', 'workqueue__free_workqueue(*queue);'],
			['workqueue__WorkQueue* record = *queue;', 'workqueue__WorkQueue* record = NULL;'],
			['array_delete(&file->queues, v_index);', 'array_delete(&file->queues, 0);'],
			['void workqueue__free_workqueue(workqueue__WorkQueue* queue) {', 'void workqueue__free_workqueue(workqueue__WorkQueue* queue) { malloc(1);'],
			['workqueue__WorkQueue__complete(completion->queue,', 'workqueue__WorkQueue__complete(NULL,']] {
			changed := current.replace(pair[0], pair[1]); require(changed != current, 'mutation anchor')!
			if _ := compare(changed, old) { panic('accepted C lifetime mutation') }
		}
		println('Logical queue C checker: six free/snapshot/index/allocation/last-access mutations rejected.')
	}
}
