// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn require(ok bool, message string) ! { if !ok { return error(message) } }
fn body(source string, name string) !string {
	for line in source.split_into_lines() {
		if line.len == 0 || line[0].is_space() || !line.contains(' ' + name + '(') || !line.ends_with(' {') { continue }
		start := source.index(line) or { return error(name) }
		end := source.index_after('\n}\n', start) or { return error(name) }
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
fn ordered(code string, tokens []string) ! {
	mut offset := 0
	for token in tokens {
		position := code.index_after(token, offset) or { return error('missing or out-of-order: ' + token) }
		offset = position + token.len
	}
}
fn layout(source string) !string {
	start := source.index('struct gpu__agx__gpu__G13QueueResources {') or { return error('queue layout') }
	end := source.index_after('\n};', start) or { return error('queue layout end') }
	return source[start..end + 3]
}
fn compare(current string, old string) !int {
	p := 'gpu__agx__gpu__'
	context := body(current, p + 'GpuManager__invalidate_g13_context_locked')!
	ordered(context, ['resources->context_retirement == ' + p + 'G13ContextRetirement__complete',
		'resources->context_retirement == ' + p + 'G13ContextRetirement__pending',
		'mgr->state != ' + p + 'GpuState__running', 'mgr->hw_config.gpu_gen != hw__GpuGen__g13',
		'resources->context.va == 0', 'resources->context.phys == 0', '!resources->context.mapped',
		'alloc__HeapAllocator__garbage(&mgr->g13_private)', 'u64 private_count',
		'alloc__HeapAllocator__garbage(&mgr->g13_gpu_readonly)', 'u64 readonly_count',
		'katomic__sync();', 'fw__make_g13_context_invalidate(', 'channel__TxChannel__enqueue_with_token(',
		'resources->context_retirement = ' + p + 'G13ContextRetirement__pending;',
		'if (!' + p + 'GpuManager__ring_device_control(mgr))', 'timer__get_ns()',
		'while (channel__TxChannel__read_pointer(', 'channel__TxChannel__has_fault(',
		'1000000000', 'katomic__sync();', 'resources->context_retirement = ' + p + 'G13ContextRetirement__complete;',
		'alloc__HeapAllocator__collect_garbage(&mgr->g13_private, private_count);',
		'alloc__HeapAllocator__collect_garbage(&mgr->g13_gpu_readonly, readonly_count);', 'return true;'])!
	require(context.count('enqueue_with_token(') == 1 && context.count('ring_device_control(') == 1
		&& context.count('HeapAllocator__collect_garbage(') == 2 && !context.contains('HeapAllocator__gc(')
		&& !context.contains('= ' + p + 'G13ContextRetirement__fresh'), 'one publication and one captured collection per class')!
	wire := body(current, 'fw__make_g13_context_invalidate')!
	ordered(wire, ['context == NULL', 'size < 0x40', 'address == 0', 'abi == hw__FirmwareAbi__v12_3',
		'= 0x14;', 'abi == hw__FirmwareAbi__v13_5_partial', '= 0x11;', 'i64 context_offset',
		'= 0x1c;', '= 0x14;', 'i64 pointer_offset', 'fw__device_control_destroy_context_v12_3',
		'fw__device_control_destroy_context_v13_5', 'fw__FwDeviceControlMsg message',
		'u8* bytes = (u8*)(&message);', '(bytes)[8] = (data)[0x23];', '(bytes)[context_offset] = (data)[0];',
		'(bytes)[context_offset + 1] = (data)[1];', '(bytes)[context_offset + 2] = (data)[4];',
		'for (; i < 8; i++)', '(bytes)[pointer_offset + i] = (u8)', '(8 * i)', '.value = message'])!
	for code in [context, wire] {
		for token in ['memdup(', 'malloc(', 'vcalloc(', 'array_new(', 'new_array', '__str(', '(u64*)'] {
			require(!code.contains(token), 'new helpers are stack/scalar only: ' + token)!
		}
	}
	gate := 'if (invalidate && (!' + p + 'GpuManager__invalidate_g13_context_locked(mgr, resources) || !' + p + 'GpuManager__invalidate_g13_queue_mappings_locked(mgr, resources)))'
	old_gate := 'if (invalidate && !' + p + 'GpuManager__invalidate_g13_queue_mappings_locked(mgr, resources))'
	queue_free := body(current, p + 'GpuManager__free_g13_queue_resources_locked')!
	require(queue_free.count(gate) == 1, 'context gate precedes existing UAT gate')!
	require(normalize(current, queue_free.replace(gate, old_gate))! == normalize(old, body(old, p + 'GpuManager__free_g13_queue_resources_locked')!)!, 'queue free changes only context gate')!
	field := '\tint context_retirement;\n'
	require(layout(current)!.count(field) == 1 && layout(current)!.replace(field, '') == layout(old)!, 'queue adds one scalar retirement field')!
	initial := ', .context_retirement = ' + p + 'G13ContextRetirement__fresh'
	constructor := body(current, p + 'GpuManager__create_g13_queue_resources')!
	require(constructor.count(initial) == 1, 'fresh retirement initialized once')!
	require(normalize(current, constructor.replace(initial, ''))! == normalize(old, body(old, p + 'GpuManager__create_g13_queue_resources')!)!, 'constructor and unwind add only scalar default')!
	mut unchanged := 0
	for name in ['new_heap', 'new_heap_with_garbage', 'new_heap_with_explicit_gc', 'HeapAllocator__alloc',
		'HeapAllocator__release', 'HeapAllocator__gc', 'HeapAllocator__gc_locked', 'HeapAllocator__collect_garbage',
		'HeapAllocator__collect_garbage_locked', 'HeapAllocator__find_address_locked', 'HeapAllocator__garbage',
		'HeapAllocator__retire_hole_order_locked', 'HeapAllocator__newest_hole_order_locked', 'HeapAllocator__cancel_unpublished'] {
		require(normalize(current, body(current, 'alloc__' + name)!)! == normalize(old, body(old, 'alloc__' + name)!)!, 'unchanged heap body: ' + name)!
		unchanged++
	}
	for name in ['GpuManager__release_shared_buffer_backing', 'GpuManager__free_shared_buffer', 'unmap_shared_buffer',
		'GpuManager__invalidate_g13_shared_buffer', 'GpuManager__invalidate_g13_driver_buffer',
		'GpuManager__invalidate_g13_queue_mappings_locked', 'GpuManager__release_g13_render_scene_backing_locked',
		'GpuManager__release_g13_scene_slot_locked', 'GpuManager__release_g13_tpc_locked', 'GpuManager__invalidate_g13_tpc_locked',
		'GpuManager__free_g13_channel_allocations', 'GpuManager__release_g13_event_resources_locked', 'GpuManager__shutdown',
		'GpuManager__fail_g13_initialization', 'GpuManager__collect_g13_heap_garbage_locked', 'GpuManager__flush_g13_fw_cache_locked',
		'GpuManager__alloc_g13_buffer_with_protection', 'alloc_buffer_from_heap', 'GpuManager__reap_g13_render_jobs',
		'GpuManager__reap_g13_compute_jobs', 'GpuManager__release_all_g13_render_jobs', 'GpuManager__release_all_g13_compute_jobs',
		'GpuManager__release_all_g13_queue_resources', 'GpuManager__free_g13_render_buffer_locked',
		'GpuManager__free_g13_render_job_locked', 'GpuManager__free_g13_compute_job_locked',
		'G13QueueResources__retain_file_reference', 'G13QueueResources__release_file_reference', 'G13QueueResources__has_file_references',
		'GpuManager__retained_g13_queue_resources', 'GpuManager__release_g13_queue_resources',
		'GpuManager__g13_queue_dispatch_blocked', 'GpuManager__g13_queue_dispatch_blocked_locked'] {
		require(normalize(current, body(current, p + name)!)! == normalize(old, body(old, p + name)!)!, 'unchanged backing/cache/owner/drain: ' + name)!
		unchanged++
	}
	for name in ['fw__make_g13_cache_flush', 'fw__initialize_g13_gpu_context', 'channel__TxChannel__enqueue_with_token', 'channel__TxChannel__read_pointer', 'channel__TxChannel__has_fault'] {
		require(normalize(current, body(current, name)!)! == normalize(old, body(old, name)!)!, 'unchanged command/channel body: ' + name)!
		unchanged++
	}
	return unchanged
}
fn counts(source string) (map[string]int, []string) {
	mut sites := map[string]int{}; mut totals := []string{}
	for line in source.split_into_lines() {
		if line.starts_with('aarch64: ') || line.starts_with('x86_64: ') { totals << line }
		if line.starts_with('NEW: ') { continue }
		position := line.index('.v:') or { continue }
		tail := line[position + 3..]; space := tail.index(' ') or { continue }
		location := tail[..space].split(':')
		if location.len != 2 || location[0].int() <= 0 || location[1].int() <= 0 { continue }
		sites[line[..position + 2] + ' ' + tail[space + 1..]]++
	}
	assert sites.len > 100 && totals.len == 2; return sites, totals
}
fn main() {
	assert os.args.len == 4
	current := os.read_file(os.args[2])!; old := os.read_file(os.args[3])!
	if os.args[1] == '--allocations' {
		a, ta := counts(current); b, tb := counts(old)
		require(a == b && ta == tb.map(it.replace('aarch64: 834 source files', 'aarch64: 835 source files')), 'only one ARM source file may be added; allocation sites unchanged')!
		println('Per-file/per-kind sites match baseline; ARM source count 834 to 835 only, allocation counts unchanged; existing allowance failures remain.')
		return
	}
	unchanged := compare(current, old)!
	println('Context native C: stack-only ABI/publication helpers, exact queue gate and scalar state; ' + unchanged.str() + ' heap/backing/cache/owner/channel bodies unchanged.')
	if os.args[1] == '--selftest' {
		for pair in [
			['if (resources->context_retirement == gpu__agx__gpu__G13ContextRetirement__pending)', 'if (false)'],
			['resources->context_retirement = gpu__agx__gpu__G13ContextRetirement__pending;', '// omitted pending mark'],
			['collect_garbage(&mgr->g13_private, private_count)', 'collect_garbage(&mgr->g13_private, readonly_count)'],
			['__if_val_1 = 0x1c;', '__if_val_1 = 0x18;'],
			['!gpu__agx__gpu__GpuManager__invalidate_g13_context_locked(mgr, resources)', 'false'],
			['u8* bytes = (u8*)(&message);', 'malloc(1); u8* bytes = (u8*)(&message);'],
			['\tint context_retirement;\n', '\tint* context_retirement;\n'],
		] {
			changed := current.replace(pair[0], pair[1]); require(changed != current, 'mutation anchor')!
			if _ := compare(changed, old) { panic('accepted context ownership/ABI/allocation mutation') }
		}
		println('Context C checker: seven publication/count/ABI/gate/allocation/state mutations rejected.')
	} else { assert os.args[1] == '--native' }
}
