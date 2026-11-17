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
	prefix := 'alloc__'
	allocate := body(current, prefix + 'HeapAllocator__alloc')!
	guard := '\t\tif (!h->gc_on_pressure) {\n\t\t\t__v_option_u64 _t3 = (__v_option_u64){.ok = false};\n\t\t\t{\n\t\t\t\tklock__Lock__release(&h->lock);\n\t\t\t}\n\t\t\treturn _t3;\n\t\t}\n'
	require(allocate.count(guard) == 1, 'pressure guard must return none with its heap lock released')!
	current_alloc := normalize(current, allocate.replace(guard, ''))!
	old_alloc := normalize(old, body(old, prefix + 'HeapAllocator__alloc')!)!
	if current_alloc != old_alloc {
		if directory := os.getenv_opt('AGX_PRESSURE_DIAGNOSTICS') {
			os.write_file(directory + '/allocation-current.txt', current_alloc)!
			os.write_file(directory + '/allocation-baseline.txt', old_alloc)!
		}
		return error('allocation differs only by pressure guard')
	}
	constructor := body(current, prefix + 'new_heap_with_explicit_gc')!
	require(constructor == prefix + 'HeapAllocator ' + prefix + 'new_heap_with_explicit_gc(string name, u64 start, u64 end) {\n\t' + prefix + 'HeapAllocator heap = ' + prefix + 'new_heap(name, start, end);\n\theap.gc_on_pressure = false;\n\treturn heap;\n}\n', 'exact stack-only explicit-policy constructor')!
	default_heap := body(current, prefix + 'new_heap')!
	require(default_heap.count('.gc_on_pressure = true, ') == 1, 'legacy pressure retry is default')!
	require(normalize(current, default_heap.replace('.gc_on_pressure = true, ', ''))! == normalize(old, body(old, prefix + 'new_heap')!)!, 'existing constructor adds only scalar policy')!
	manager := body(current, 'gpu__agx__gpu__new_gpu_manager')!
	require(manager.count(prefix + 'new_heap_with_explicit_gc(') == 2, 'two managed classes only')!
	require(normalize(current, manager.replace(prefix + 'new_heap_with_explicit_gc(', prefix + 'new_heap('))! == normalize(old, body(old, 'gpu__agx__gpu__new_gpu_manager')!)!, 'manager changes only two constructor calls')!
	for name in ['new_heap_with_garbage', 'HeapAllocator__release', 'HeapAllocator__gc', 'HeapAllocator__gc_locked',
		'HeapAllocator__collect_garbage', 'HeapAllocator__collect_garbage_locked', 'HeapAllocator__find_address_locked', 'HeapAllocator__garbage'] {
		require(normalize(current, body(current, prefix + name)!)! == normalize(old, body(old, prefix + name)!)!, 'heap ownership body unchanged: ' + name)!
	}
	for name in ['alloc_buffer_from_heap', 'GpuManager__collect_g13_heap_garbage_locked', 'GpuManager__flush_g13_fw_cache_locked',
		'GpuManager__free_g13_compute_job_locked', 'GpuManager__free_g13_render_job_locked', 'GpuManager__free_g13_queue_resources_locked'] {
		require(normalize(current, body(current, 'gpu__agx__gpu__' + name)!)! == normalize(old, body(old, 'gpu__agx__gpu__' + name)!)!, 'backing/barrier/teardown body unchanged: ' + name)!
	}
	println('Pressure native C: exact guard, scalar constructor/default and two class selections; fourteen ownership/backing/barrier/teardown bodies unchanged.')
}
fn main() {
	assert os.args.len == 4
	current := os.read_file(os.args[2])!; old := os.read_file(os.args[3])!
	compare(current, old)!
	if os.args[1] == '--selftest' {
		for pair in [
			['if (!h->gc_on_pressure)', 'if (h->gc_on_pressure)'],
			['heap.gc_on_pressure = false;', 'heap.gc_on_pressure = true;'],
			['.gc_on_pressure = true, ', '.gc_on_pressure = false, '],
			['alloc__new_heap_with_explicit_gc(_str_', 'alloc__new_heap(_str_'],
			['return _t3;\n\t\t}\n\t\talloc__HeapAllocator__gc_locked', 'return _t4;\n\t\t}\n\t\talloc__HeapAllocator__gc_locked'],
			['array__set(_a5, _i5', 'array__set(_a5, _i4'],
		] {
			changed := current.replace(pair[0], pair[1]); require(changed != current, 'mutation anchor')!
			if _ := compare(changed, old) { panic('accepted pressure mutation') }
		}
		println('Pressure C checker: six guard/default/constructor/selection/return/alias mutations rejected.')
	} else { assert os.args[1] == '--native' }
}
