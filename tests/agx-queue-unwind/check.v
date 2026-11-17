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
	p := 'gpu__agx__gpu__'; m := p + 'GpuManager__'
	constructor := body(current, m + 'create_g13_queue_resources')!
	mut restored := constructor; mut removed := 0
	for depth in 1 .. 10 {
		indent := '\t'.repeat(depth)
		branch := ' else {\n' + indent + '\t{\n' + indent + '\t\tv_free(resources);\n' + indent + '\t}\n' + indent + '}'
		removed += restored.count(branch); restored = restored.replace(branch, '')
	}
	require(removed == 12 && constructor.count('v_free(resources);') == removed, 'all twelve lowered deferred frees must be in cleanup-success else arms')!
	same(current, old, m + 'create_g13_queue_resources', restored)!
	mut unchanged := 0
	for name in ['alloc__new_heap', 'alloc__new_heap_with_garbage', 'alloc__new_heap_with_explicit_gc',
		'alloc__HeapAllocator__alloc', 'alloc__HeapAllocator__release', 'alloc__HeapAllocator__gc', 'alloc__HeapAllocator__collect_garbage',
		'alloc__HeapAllocator__collect_garbage_locked', 'alloc__HeapAllocator__cancel_unpublished',
		'channel__TxChannel__enqueue_with_token', 'channel__TxChannel__read_pointer', 'fw__make_g13_context_invalidate', 'fw__make_g13_cache_flush'] {
		same(current, old, name, body(current, name)!)!; unchanged++
	}
	for suffix in ['free_g13_queue_resources_locked', 'invalidate_g13_context_locked', 'defer_g13_context_locked',
		'append_g13_context_locked', 'collect_g13_context_garbage_locked', 'collect_g13_heap_garbage_locked', 'flush_g13_fw_cache_locked',
		'release_g13_queue_resources', 'retained_g13_queue_resources', 'release_all_g13_queue_resources', 'g13_queue_dispatch_blocked_locked',
		'free_shared_buffer', 'release_shared_buffer_backing', 'invalidate_g13_shared_buffer', 'invalidate_g13_queue_mappings_locked',
		'free_g13_render_buffer_locked', 'free_g13_render_job_locked', 'free_g13_compute_job_locked',
		'reap_g13_render_jobs', 'reap_g13_compute_jobs', 'shutdown', 'fail_g13_initialization'] {
		same(current, old, m + suffix, body(current, m + suffix)!)!; unchanged++
	}
	for name in [p + 'GpuManager', p + 'G13QueueResources', p + 'SharedBuffer'] {
		require(declaration(current, name)! == declaration(old, name)!, 'unchanged owning layout: ' + name)!
	}
	return unchanged
}
fn main() {
	assert os.args.len == 4
	current := os.read_file(os.args[2])!; old := os.read_file(os.args[3])!
	unchanged := compare(current, old)!
	println('Queue unwind native C: twelve lowered cleanup-success frees only, unchanged ownership layouts and ' + unchanged.str() + ' heap/backing/context/quarantine/owner bodies.')
	if os.args[1] == '--selftest' {
		for pair in [['v_free(resources);', '/* omitted free */'], ['v_free(resources);', 'v_free(resources); v_free(resources);'],
			['if (!complete)', 'if (complete)'], ['resources->quarantined = true;', 'resources->quarantined = false;'],
			['GpuManager__free_g13_queue_resources_locked(mgr, resources, resources->mappings_published)', 'GpuManager__free_g13_queue_resources_locked(mgr, resources, false)'],
			['klock__Lock__release(&mgr->lock);', '/* omitted lock release */']] {
			changed := current.replace(pair[0], pair[1]); require(changed != current, 'mutation anchor')!
			if _ := compare(changed, old) { panic('accepted queue-unwind ownership mutation') }
		}
		println('Queue unwind C checker: six free/ownership/quarantine/publication/lock mutations rejected.')
	} else { assert os.args[1] == '--native' }
}
