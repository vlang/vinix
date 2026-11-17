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
fn ordered(source string, tokens []string) ! {
	mut cursor := 0
	for token in tokens { cursor = (source.index_after(token, cursor) or { return error(token) }) + token.len }
}
fn declaration(source string, name string) !string {
	start := source.index('struct ' + name + ' {') or { return error(name) }
	end := source.index_after('\n};', start) or { return error(name) }
	return source[start..end + 3]
}
fn check(source string, prefix string) ! {
	collect := body(source, prefix + 'GpuManager__collect_g13_heap_garbage_locked')!
	ordered(collect, ['HeapAllocator__garbage(&mgr->g13_private)', 'u64 private_count =',
		'HeapAllocator__garbage(&mgr->g13_gpu_readonly)', 'u64 readonly_count =',
		'if (!' + prefix + 'g13_heap_garbage_needs_collection(',
		'if (!' + prefix + 'GpuManager__flush_g13_fw_cache_locked(mgr))', 'return;',
		'HeapAllocator__collect_garbage(&mgr->g13_private, private_count)',
		'HeapAllocator__collect_garbage(&mgr->g13_gpu_readonly, readonly_count)'])!
	require(collect.count('HeapAllocator__collect_garbage(') == 2 && !collect.contains('HeapAllocator__gc('), 'only two captured prefixes may retire')!
	barrier := body(source, prefix + 'GpuManager__flush_g13_fw_cache_locked')!
	ordered(barrier, ['fw__make_g13_cache_flush(', 'fw__FwDeviceControlMsg message =',
		'channel__TxChannel__enqueue_with_token(&mgr->channels.device_ctrl, (void*)(&message))',
		'if (!' + prefix + 'GpuManager__ring_device_control(mgr))', 'return false;',
		'while (channel__TxChannel__read_pointer(&mgr->channels.device_ctrl) != token)',
		'1000000000', 'katomic__sync()', 'return true;'])!
	threshold := body(source, prefix + 'g13_heap_garbage_needs_collection')!
	require(threshold.count(' > ') == 4 && !threshold.contains(' >= '), 'strict independent thresholds')!
	command := body(source, 'fw__make_g13_cache_flush')!
	ordered(command, ['hw__FirmwareAbi__v12_3', '0x14', 'hw__FirmwareAbi__v13_5_partial', '0x11',
		'u8* bytes = (u8*)(&message)', '(bytes)[context_offset] = 0xff', '(bytes)[context_offset + 1] = 0xff'])!
	for method in [collect, barrier, command, threshold] {
		for token in ['memdup(', 'malloc(', 'vcalloc(', 'array_new(', 'IError', 'sched__yield('] {
			require(!method.contains(token), 'new firmware GC operations must use stack/scalar storage and safe polling: ' + token)!
		}
	}
	println('Heap GC C: captured FIFO counts follow acknowledged token; strict thresholds, stack command and allocation-free polling verified.')
}
fn native(current string, baseline string) ! {
	prefix := 'gpu__agx__gpu__'
	check(current, prefix)!
	for suffix in ['alloc', 'release', 'gc', 'gc_locked', 'collect_garbage_locked',
		'find_address_locked', 'retire_hole_order_locked', 'newest_hole_order_locked'] {
		symbol := 'alloc__HeapAllocator__' + suffix
		require(body(current, symbol)! == body(baseline, symbol)!, 'allocator ownership changed: ' + suffix)!
	}
	for name in ['alloc__checked_heap_align_up', 'alloc__heap_allocation_address'] {
		require(body(current, name)! == body(baseline, name)!, 'checked placement changed')!
	}
	for suffix in ['free_shared_buffer', 'release_shared_buffer_backing', 'invalidate_g13_shared_buffer',
		'free_g13_render_job_locked', 'free_g13_compute_job_locked', 'reap_g13_render_jobs', 'reap_g13_compute_jobs',
		'release_g13_queue_resources', 'flush_g13_uat_range'] {
		symbol := prefix + 'GpuManager__' + suffix
		require(body(current, symbol)! == body(baseline, symbol)!, 'existing backing/teardown gate changed: ' + suffix)!
	}
	for suffix in ['enqueue_with_token', 'read_pointer', 'has_fault'] {
		symbol := 'channel__TxChannel__' + suffix
		require(body(current, symbol)! == body(baseline, symbol)!, 'ring transport changed: ' + suffix)!
	}
	allocation := body(current, prefix + 'GpuManager__alloc_g13_buffer_with_protection')!
	ordered(allocation, ['protection != pgtable__gpu_prot_fw_private_rw', 'protection != pgtable__gpu_prot_gpu_ro_fw_private_rw',
		prefix + 'GpuManager__collect_g13_heap_garbage_locked(mgr)', 'protection == pgtable__gpu_prot_fw_private_rw'])!
	entry := '\tif ((protection != pgtable__gpu_prot_fw_private_rw) && (protection != pgtable__gpu_prot_fw_shared_rw) && (protection != pgtable__gpu_prot_fw_shared_ro) && (protection != pgtable__gpu_prot_gpu_ro_fw_private_rw)) {\n' +
		'\t\treturn (__v_option_gpu__agx__gpu__SharedBuffer){.ok = false};\n\t}\n' +
		'\t' + prefix + 'GpuManager__collect_g13_heap_garbage_locked(mgr);\n'
	require(allocation.count(entry) == 1 && allocation.replace(entry, '') == body(baseline, prefix + 'GpuManager__alloc_g13_buffer_with_protection')!,
		'only protection validation and threshold collection precede the existing allocation body')!
	for name in ['alloc__Allocation', 'alloc__HeapAllocator', prefix + 'GpuManager', prefix + 'SharedBuffer',
		prefix + 'G13RenderJobResources', prefix + 'G13ComputeJobResources', prefix + 'G13QueueResources',
		'gpu__agx__event__WorkQueueEvents', 'fw__FwDeviceControlMsg'] {
		require(declaration(current, name)! == declaration(baseline, name)!, 'owning layout changed: ' + name)!
	}
	println('Native heap GC: ten allocator bodies, nine existing GPU lifetime/flush bodies, three channel bodies and nine owning layouts match baseline; exact allocation-entry transformation verified.')
}
fn allocation_counts(source string) (map[string]int, map[string]int, map[string]int) {
	mut sites := map[string]int{}; mut sources := map[string]int{}; mut totals := map[string]int{}
	for line in source.split_into_lines() {
		if line.starts_with('aarch64: ') || line.starts_with('x86_64: ') {
			parts := line.fields(); sources[parts[0]] = parts[1].int(); totals[parts[0]] = parts[4].int()
		}
		if line.starts_with('NEW: ') { continue }
		position := line.index('.v:') or { continue }
		tail := line[position + 3..]; space := tail.index(' ') or { continue }
		location := tail[..space].split(':')
		if location.len != 2 || location[0].int() <= 0 || location[1].int() <= 0 { continue }
		sites[line[..position + 2] + ' ' + tail[space + 1..]]++
	}
	assert sites.len > 100 && sources.len == 2 && totals.len == 2
	return sites, sources, totals
}
fn compare_allocations(current string, baseline string) ! {
	old_sites, old_sources, old_totals := allocation_counts(baseline)
	new_sites, new_sources, new_totals := allocation_counts(current)
	require(old_sites == new_sites && old_totals == new_totals, 'allocation sites or per-file/per-kind counts changed')!
	for arch, count in old_sources {
		require(new_sources[arch] == count + if arch == 'aarch64:' { 1 } else { 0 }, 'only one ARM GPU source was added')!
		println(arch + ' allocation sites unchanged: ' + old_totals[arch].str() + '; source files ' + count.str() + ' -> ' + new_sources[arch].str())
	}
	println('Existing allowance failures remain; no allowance was changed.')
}
fn main() {
	assert os.args.len in [3, 4]
	source := os.read_file(os.args[2])!
	match os.args[1] {
		'--host' { check(source, 'gpu__')! }
		'--native' { native(source, os.read_file(os.args[3])!)! }
		'--allocations' { compare_allocations(source, os.read_file(os.args[3])!)! }
		'--selftest' {
			check(source, 'gpu__')!
			for pair in [[' != token)', ' == token)'], ['private_count);', 'readonly_count);'],
				['u8* bytes = (u8*)(&message);', 'malloc(1); u8* bytes = (u8*)(&message);'],
				[' > ', ' >= '], ['katomic__sync();', 'sched__yield(false);']] {
				changed := source.replace(pair[0], pair[1]); require(changed != source, 'mutation anchor')!
				if _ := check(changed, 'gpu__') { panic('accepted invalid GC C') }
			}
			println('Heap GC C checker: five token/count/allocation/threshold/scheduler mutations rejected.')
		}
		else { panic('usage: check --host|--selftest C or --native C BASELINE_C') }
	}
}
