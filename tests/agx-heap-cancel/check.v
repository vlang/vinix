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
fn ordered(source string, tokens []string) ! {
	mut cursor := 0
	for token in tokens { at := source.index_after(token, cursor) or { return error('missing/late: ' + token) }; cursor = at + token.len }
}
fn check_cancel(source string) ! {
	cancel := body(source, 'alloc__HeapAllocator__cancel_unpublished')!
	ordered(cancel, ['klock__Lock__acquire(&h->lock)', 'if ((record->va != va) || !record->in_use)',
		'alloc__HeapAllocator__retire_hole_order_locked(h, record->hole_order)', 'if (v_index == 0)',
		'alloc__HeapAllocator__retire_hole_order_locked(h, h->head_hole_order)',
		'h->head_hole_order = alloc__HeapAllocator__newest_hole_order_locked(h)',
		'previous->hole_order = alloc__HeapAllocator__newest_hole_order_locked(h)',
		'if ((record->va + record->size) == h->top)', 'previous->va + previous->size',
		'h->top = __if_val_0', 'array_delete(&h->allocations, v_index)', 'v_free(record);'])!
	for token in ['garbage_count', 'garbage_bytes', 'collect_garbage(', 'HeapAllocator__gc(',
		'memdup(', 'malloc(', 'vcalloc(', 'array_new(', 'u64__str('] { require(!cancel.contains(token), 'new cancellation body: ' + token)! }
	require(cancel.count('v_free(record);') == 1 && cancel.count('array_delete(') == 1, 'one exact unlink/free')!
	require(cancel.all_after('v_free(record);') == '\n\t\t\t}\n\t\t\t{\n\t\t\t\tklock__Lock__release(&h->lock);\n\t\t\t}\n\t\t\treturn;\n\t\t}\n\t}\n\t{\n\t\tklock__Lock__release(&h->lock);\n\t}\n}\n', 'no iterator or record access after free; every return unlocks')!
}
fn compare(current string, old string) ! {
	check_cancel(current)!
	caller := body(current, 'gpu__agx__gpu__alloc_buffer_from_heap')!
	require(caller.count('alloc__HeapAllocator__cancel_unpublished(heap, va);') == 1, 'one failed-map cancellation')!
	ordered(caller, ['if (!mmu__UatManager__map_kernel(', 'alloc__HeapAllocator__cancel_unpublished(heap, va);', 'memory__pmm_free(', 'return '])!
	restored := caller.replace('alloc__HeapAllocator__cancel_unpublished(heap, va);', 'alloc__HeapAllocator__release(heap, va);\n\t\talloc__HeapAllocator__gc(heap);')
	require(normalize(current, restored)! == normalize(old, body(old, 'gpu__agx__gpu__alloc_buffer_from_heap')!)!, 'only failed-map rollback calls change')!
	for name in ['new_heap', 'new_heap_with_garbage', 'new_heap_with_explicit_gc',
		'HeapAllocator__alloc', 'HeapAllocator__release', 'HeapAllocator__gc', 'HeapAllocator__gc_locked',
		'HeapAllocator__collect_garbage', 'HeapAllocator__collect_garbage_locked', 'HeapAllocator__find_address_locked',
		'HeapAllocator__garbage', 'HeapAllocator__retire_hole_order_locked', 'HeapAllocator__newest_hole_order_locked'] {
		require(normalize(current, body(current, 'alloc__' + name)!)! == normalize(old, body(old, 'alloc__' + name)!)!, 'heap body changed: ' + name)!
	}
	for name in ['GpuManager__collect_g13_heap_garbage_locked', 'GpuManager__flush_g13_fw_cache_locked',
		'GpuManager__free_g13_compute_job_locked', 'GpuManager__free_g13_render_job_locked',
		'GpuManager__free_g13_queue_resources_locked', 'GpuManager__release_shared_buffer_backing'] {
		require(normalize(current, body(current, 'gpu__agx__gpu__' + name)!)! == normalize(old, body(old, 'gpu__agx__gpu__' + name)!)!, 'existing GPU gate changed: ' + name)!
	}
	for name in ['mmu__UatManager__map_kernel', 'pgtable__UatPgtable__map', 'pgtable__UatPgtable__map_page_locked',
		'pgtable__UatPgtable__unmap_page_locked', 'pgtable__UatPgtable__invalidate_range_locked'] {
		require(normalize(current, body(current, name)!)! == normalize(old, body(old, name)!)!, 'page-table gate changed: ' + name)!
	}
	println('Cancellation native C: one allocation-free unlink/free with no post-free iterator access; exact rollback call substitution; 24 ownership/backing/barrier/page-table bodies unchanged.')
}
fn main() {
	assert os.args.len == 4
	current := os.read_file(os.args[2])!; old := os.read_file(os.args[3])!; compare(current, old)!
	if os.args[1] == '--selftest' {
		cancel := body(current, 'alloc__HeapAllocator__cancel_unpublished')!
		for pair in [
			['if ((record->va != va) || !record->in_use)', 'if (record->va != va)'],
			['v_free(record);', 'v_free(record); record->va = 0;'],
			['array_delete(&h->allocations, v_index);', 'h->garbage_count = 0; array_delete(&h->allocations, v_index);'],
			['v_free(record);', ''],
			['klock__Lock__release(&h->lock);', '// missing unlock'],
		] {
			changed := current.replace(cancel, cancel.replace(pair[0], pair[1])); require(changed != current, 'mutation anchor')!
			if _ := compare(changed, old) { panic('accepted cancellation mutation') }
		}
		println('Cancellation C checker: five live-owner/free/FIFO/unlock/post-free mutations rejected.')
	} else { assert os.args[1] == '--native' }
}
