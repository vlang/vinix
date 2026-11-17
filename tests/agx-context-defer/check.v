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
			key := code[i..end]; require(key in strings, key)!; out << strings[key].bytes(); i = end
		} else if (code[i..].starts_with('_t') || code[i..].starts_with('_a') || code[i..].starts_with('_i')) && i + 2 < code.len && code[i + 2].is_digit() {
			mut end := i + 2; for end < code.len && code[end].is_digit() { end++ }
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
fn compare(current string, old string) !int {
	p := 'gpu__agx__gpu__'; q := p + 'G13QueueResources'; m := p + 'GpuManager__'; phase := p + 'G13ContextRetirement__'
	append := body(current, m + 'append_g13_context_locked')!
	require(append == 'void ' + m + 'append_g13_context_locked(' + p + 'GpuManager* mgr, ' + q + '* resources) {\n' +
		'\tresources->context_next = NULL;\n\tif (mgr->g13_context_tail == NULL) {\n\t\tmgr->g13_context_head = resources;\n\t} else {\n' +
		'\t\tmgr->g13_context_tail->context_next = resources;\n\t}\n\tmgr->g13_context_tail = resources;\n}\n', 'FIFO append preserves original pointer identity without copy or allocation')!
	defer_ctx := body(current, m + 'defer_g13_context_locked')!
	require(defer_ctx == 'bool ' + m + 'defer_g13_context_locked(' + p + 'GpuManager* mgr, ' + q + '* resources) {\n' +
		'\tif (resources->context_retirement == ' + phase + 'complete) {\n\t\treturn true;\n\t}\n' +
		'\tif (resources->context_retirement == ' + phase + 'fresh) {\n\t\tresources->context_retirement = ' + phase + 'queued;\n' +
		'\t\t' + m + 'append_g13_context_locked(mgr, resources);\n\t}\n\treturn false;\n}\n', 'defer gate appends fresh nodes once and never publishes')!
	drain := body(current, m + 'collect_g13_context_garbage_locked')!
	require(drain == 'void ' + m + 'collect_g13_context_garbage_locked(' + p + 'GpuManager* mgr) {\n' +
		'\tif ((mgr->state != ' + p + 'GpuState__running) || (mgr->hw_config.gpu_gen != hw__GpuGen__g13)) {\n\t\treturn;\n\t}\n' +
		'\t' + q + '* current = mgr->g13_context_head;\n\tmgr->g13_context_head = NULL;\n\tmgr->g13_context_tail = NULL;\n' +
		'\twhile (current != NULL) {\n\t\t' + q + '* resources = current;\n\t\tcurrent = resources->context_next;\n\t\tresources->context_next = NULL;\n' +
		'\t\tif (!' + m + 'invalidate_g13_context_locked(mgr, resources) && (resources->context_retirement == ' + phase + 'queued)) {\n' +
		'\t\t\t' + m + 'append_g13_context_locked(mgr, resources);\n\t\t}\n\t}\n}\n', 'snapshot reads next before mutation, detaches roots and retries only unpublished nodes')!
	for code in [append, defer_ctx, drain] { for token in ['memdup(', 'malloc(', 'vcalloc(', 'array_new(', 'new_array', '__str(', 'file__'] {
		require(!code.contains(token), 'no new allocation or file-lock path: ' + token)!
	} }
	queue_free := body(current, m + 'free_g13_queue_resources_locked')!
	require(queue_free.count(m + 'defer_g13_context_locked(mgr, resources)') == 1, 'one deferred gate')!
	same(current, old, m + 'free_g13_queue_resources_locked', queue_free.replace(m + 'defer_g13_context_locked(', m + 'invalidate_g13_context_locked('))!
	entry := '\t' + m + 'collect_g13_context_garbage_locked(mgr);\n'
	allocation := body(current, m + 'alloc_g13_buffer_with_protection')!
	require(allocation.count(entry) == 1 && allocation.contains(entry + '\t' + m + 'collect_g13_heap_garbage_locked(mgr);'), 'drain before threshold collection')!
	same(current, old, m + 'alloc_g13_buffer_with_protection', allocation.replace(entry, ''))!
	stopped := body(current, m + 'release_all_g13_queue_resources')!
	roots := '\tmgr->g13_context_head = NULL;\n\tmgr->g13_context_tail = NULL;\n'
	node := '\t\t\tresources->context_next = NULL;\n'
	require(stopped.count(roots) == 1 && stopped.count(node) == 1, 'stopped drain clears roots and node links')!
	same(current, old, m + 'release_all_g13_queue_resources', stopped.replace(roots, '').replace(node, ''))!
	for item in [[q, '\t' + q + '* context_next;\n'], [p + 'GpuManager', '\t' + q + '* g13_context_head;\n\t' + q + '* g13_context_tail;\n']] {
		layout := declaration(current, item[0])!
		require(layout.count(item[1]) == 1 && layout.replace(item[1], '') == declaration(old, item[0])!, 'only nonowning intrusive pointers added: ' + item[0])!
	}
	for item in [[m + 'create_g13_queue_resources', ', .context_next = NULL'], [p + 'new_gpu_manager', ', .g13_context_head = NULL, .g13_context_tail = NULL']] {
		constructor := body(current, item[0])!; require(constructor.count(item[1]) == 1, 'pointer defaults initialized once')!
		same(current, old, item[0], constructor.replace(item[1], ''))!
	}
	mut unchanged := 0
	for name in ['alloc__new_heap', 'alloc__new_heap_with_garbage', 'alloc__new_heap_with_explicit_gc',
		'alloc__HeapAllocator__alloc', 'alloc__HeapAllocator__release', 'alloc__HeapAllocator__gc', 'alloc__HeapAllocator__collect_garbage',
		'alloc__HeapAllocator__collect_garbage_locked', 'alloc__HeapAllocator__cancel_unpublished',
		'channel__TxChannel__enqueue_with_token', 'channel__TxChannel__read_pointer', 'fw__make_g13_context_invalidate', 'fw__make_g13_cache_flush'] {
		same(current, old, name, body(current, name)!)!; unchanged++
	}
	for suffix in ['invalidate_g13_context_locked', 'collect_g13_heap_garbage_locked', 'flush_g13_fw_cache_locked',
		'release_g13_queue_resources', 'retained_g13_queue_resources', 'g13_queue_dispatch_blocked_locked',
		'free_shared_buffer', 'release_shared_buffer_backing', 'invalidate_g13_shared_buffer', 'invalidate_g13_queue_mappings_locked',
		'free_g13_render_buffer_locked', 'free_g13_render_job_locked', 'free_g13_compute_job_locked',
		'reap_g13_render_jobs', 'reap_g13_compute_jobs', 'shutdown', 'fail_g13_initialization'] {
		same(current, old, m + suffix, body(current, m + suffix)!)!; unchanged++
	}
	return unchanged
}
fn main() {
	assert os.args.len == 4
	current := os.read_file(os.args[2])!; old := os.read_file(os.args[3])!
	unchanged := compare(current, old)!
	println('Deferred context native C: exact original-pointer FIFO/snapshot bodies without allocations, exact gate/entry/stopped changes and three pointer defaults; ' + unchanged.str() + ' ABI/heap/backing/owner/ack bodies unchanged.')
	if os.args[1] == '--selftest' {
		for pair in [['mgr->g13_context_tail->context_next = resources;', 'mgr->g13_context_head->context_next = resources;'],
			['current = resources->context_next;', 'current = mgr->g13_context_head;'],
			['mgr->g13_context_tail = NULL;', '// omitted tail reset'],
			['G13ContextRetirement__queued))', 'G13ContextRetirement__pending))'],
			['resources->context_next = NULL;', '// omitted node reset'],
			['mgr->g13_context_head = resources;', 'mgr->g13_context_head = memdup(resources, sizeof(*resources));'],
			['GpuManager__defer_g13_context_locked(mgr, resources)', 'GpuManager__invalidate_g13_context_locked(mgr, resources)'],
			['GpuManager__collect_g13_context_garbage_locked(mgr);', '/* skipped context drain */'],
		] {
			changed := current.replace(pair[0], pair[1]); require(changed != current, 'mutation anchor')!
			if _ := compare(changed, old) { panic('accepted deferred context mutation') }
		}
		println('Deferred context C checker: eight FIFO/snapshot/replay/link/identity/gate/entry mutations rejected.')
	} else { assert os.args[1] == '--native' }
}
