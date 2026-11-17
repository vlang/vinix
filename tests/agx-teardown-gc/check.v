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
		} else if (code[i..].starts_with('_t') || code[i..].starts_with('_a') || code[i..].starts_with('_i'))
			&& i + 2 < code.len && code[i + 2].is_digit() {
			mut end := i + 2; for end < code.len && code[end].is_digit() { end++ }
			key := code[i..end]; if key !in temps { temps[key] = '_TMP' + temps.len.str() }
			out << temps[key].bytes(); i = end
		} else { out << code[i]; i++ }
	}
	return out.bytestr()
}
fn compare(current string, old string) ! {
	mut removed := 0
	for name in ['free_g13_render_buffer_locked', 'free_g13_queue_resources_locked', 'free_g13_render_job_locked', 'free_g13_compute_job_locked'] {
		code := body(current, 'gpu__agx__gpu__GpuManager__' + name)!
		shared := '\talloc__HeapAllocator__gc(&mgr->g13_shared);\n'
		require(code.count(shared) == 1 && !code.contains('alloc__HeapAllocator__gc(&mgr->g13_private)')
			&& !code.contains('alloc__HeapAllocator__gc(&mgr->g13_gpu_readonly)'), 'normal teardown retains private pending ranges: ' + name)!
		mut restore := '\talloc__HeapAllocator__gc(&mgr->g13_private);\n'
		removed++
		if name.contains('_job_') { restore = '\talloc__HeapAllocator__gc(&mgr->g13_gpu_readonly);\n' + restore; removed++ }
		restored := code.replace(shared, restore + shared)
		require(normalize(current, restored)! == normalize(old, body(old, 'gpu__agx__gpu__GpuManager__' + name)!)!, 'only private GC calls may change: ' + name)!
	}
	require(removed == 6, 'exact six-call scope')!
	for name in ['new_heap', 'new_heap_with_garbage', 'new_heap_with_explicit_gc', 'HeapAllocator__alloc',
		'HeapAllocator__release', 'HeapAllocator__gc', 'HeapAllocator__gc_locked', 'HeapAllocator__collect_garbage',
		'HeapAllocator__collect_garbage_locked', 'HeapAllocator__find_address_locked', 'HeapAllocator__garbage',
		'HeapAllocator__retire_hole_order_locked', 'HeapAllocator__newest_hole_order_locked', 'HeapAllocator__cancel_unpublished'] {
		require(normalize(current, body(current, 'alloc__' + name)!)! == normalize(old, body(old, 'alloc__' + name)!)!, 'existing heap body changed: ' + name)!
	}
	for name in ['GpuManager__release_shared_buffer_backing', 'GpuManager__free_shared_buffer', 'unmap_shared_buffer',
		'GpuManager__invalidate_g13_shared_buffer', 'GpuManager__invalidate_g13_driver_buffer',
		'GpuManager__invalidate_g13_queue_mappings_locked', 'GpuManager__release_g13_render_scene_backing_locked',
		'GpuManager__release_g13_scene_slot_locked', 'GpuManager__release_g13_tpc_locked', 'GpuManager__invalidate_g13_tpc_locked',
		'GpuManager__free_g13_channel_allocations', 'GpuManager__release_g13_event_resources_locked', 'GpuManager__shutdown',
		'GpuManager__fail_g13_initialization', 'GpuManager__collect_g13_heap_garbage_locked', 'GpuManager__flush_g13_fw_cache_locked',
		'GpuManager__alloc_g13_buffer_with_protection', 'alloc_buffer_from_heap', 'GpuManager__reap_g13_render_jobs',
		'GpuManager__reap_g13_compute_jobs', 'GpuManager__release_all_g13_render_jobs', 'GpuManager__release_all_g13_compute_jobs',
		'GpuManager__release_all_g13_queue_resources'] {
		require(normalize(current, body(current, 'gpu__agx__gpu__' + name)!)! == normalize(old, body(old, 'gpu__agx__gpu__' + name)!)!, 'existing backing/cache/owner/stopped drain changed: ' + name)!
	}
	println('Teardown native C: exactly six private-GC removals in four bodies; 37 allocation/backing/cache/owner/stopped-drain bodies unchanged.')
}
fn main() {
	assert os.args.len == 4
	current := os.read_file(os.args[2])!; old := os.read_file(os.args[3])!; compare(current, old)!
	if os.args[1] == '--selftest' {
		for name in ['free_g13_render_buffer_locked', 'free_g13_queue_resources_locked', 'free_g13_render_job_locked', 'free_g13_compute_job_locked'] {
			code := body(current, 'gpu__agx__gpu__GpuManager__' + name)!
			changed := current.replace(code, code.replace('alloc__HeapAllocator__gc(&mgr->g13_shared);', 'alloc__HeapAllocator__gc(&mgr->g13_private); alloc__HeapAllocator__gc(&mgr->g13_shared);'))
			if _ := compare(changed, old) { panic('accepted premature collection') }
		}
		for pair in [['memory__pmm_free(', 'memory__pmm_free_wrong('], ['mgr->state = gpu__agx__gpu__GpuState__stopped;', '// omitted stopped state']] {
			changed := current.replace(pair[0], pair[1]); require(changed != current, 'mutation anchor')!
			if _ := compare(changed, old) { panic('accepted ownership/drain mutation') }
		}
		println('Teardown C checker: six premature-GC/backing/stopped-drain mutations rejected.')
	} else { assert os.args[1] == '--native' }
}
