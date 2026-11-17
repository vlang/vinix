// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn require(value bool, message string) ! { if !value { return error(message) } }

fn body(source string, name string) !string {
	for line in source.split_into_lines() {
		if line == '' || line[0].is_space() || !line.contains(' ' + name + '(') || !line.ends_with(' {') {
			continue
		}
		start := source.index(line) or { return error(name) }
		end := source.index_after('\n}\n', start) or { return error(name) }
		return source[start..end + 3]
	}
	return error('missing C definition: ' + name)
}

fn ordered(code string, tokens []string) ! {
	mut position := 0
	for token in tokens {
		at := code.index_after(token, position) or { return error('missing/out-of-order ' + token) }
		position = at + token.len
	}
}

fn check(source string) ! {
	prefix := 'gpu__agx__file__'
	for name in ['submission__stage_packet_syncs', 'submission__packet_sync_snapshot',
		'params__timestamp_ns', prefix + 'make_modern_global_params', prefix + 'dispatch_abi',
		prefix + 'ioctl_abi_handle', prefix + 'GpuFile__select_ioctl_abi',
		prefix + 'GpuFile__ioctl_modern_get_params', prefix + 'GpuFile__ioctl_modern_get_time',
		prefix + 'GpuFile__ioctl_modern_vm_create', prefix + 'GpuFile__ioctl_modern_vm_destroy',
		prefix + 'GpuFile__ioctl_modern_gem_create', prefix + 'GpuFile__ioctl_modern_gem_mmap_offset',
		prefix + 'GpuFile__ioctl_modern_gem_bind_object',
		prefix + 'GpuFile__ioctl_modern_queue_create', prefix + 'GpuFile__ioctl_modern_queue_destroy',
		prefix + 'GpuFile__ioctl_modern_submit', prefix + 'GpuFile__ioctl_modern_vm_bind'] {
		code := body(source, name)!
		for forbidden in ['memdup(', 'v_malloc(', 'v_calloc(', '__esc_', '__new_array_from_',
			'array_clone(', 'string__substr(', 'int__str(', 'u64__str('] {
			require(!code.contains(forbidden), name + ': hidden allocation ' + forbidden)!
		}
		if !name.ends_with('ioctl_modern_submit') {
			require(!code.contains('__new_array_'), name + ': unexpected array allocation')!
		}
	}
	submit := body(source, prefix + 'GpuFile__ioctl_modern_submit')!
	require(submit.count('memory__malloc_packed_fallible(') == 3, 'exactly packet/workspace/command scratch owners')!
	ordered(submit, ['capture_submission_queue(f, data->queue_id)', 'submission__stage_packet_syncs(',
		'memory__malloc_packed_fallible(data->cmdbuf_size)',
		'usercopy__copy_from_user(packet, data->cmdbuf, data->cmdbuf_size)',
		'submission__decode_packet(packet, data->cmdbuf_size, captured.usc_base, false, &commands, parser)',
		'submit_g13_staged(f, captured, commands, &inputs, &outputs, 0)', 'transferred = result == 0;'])!
	for owner in ['packet', 'workspace', 'storage'] {
		require(submit.contains('memory__free(' + owner + ');'), 'missing scratch cleanup ' + owner)!
	}
	require(submit.contains('release_submission_queue(captured)'), 'missing captured owner cleanup')!
	require(submit.contains('__new_array_noscan(0, 0, sizeof(submission__Command))'), 'only empty command-view metadata is initialized')!
	bind := body(source, prefix + 'GpuFile__ioctl_modern_vm_bind')!
	require(bind.count('memory__malloc_packed_fallible(') == 1 && bind.contains('memory__free(storage);'), 'one strided batch owner with cleanup')!
	ordered(bind, ['usercopy__copy_from_user(storage, data->userptr, bytes)',
		'for (; v_index < data->num_binds;', 'memcpy(&op,', 'GpuFile__ioctl_gem_bind(f, &old)'])!
	capture := body(source, prefix + 'GpuFile__capture_submission_queue')!
	ordered(capture, ['klock__Lock__acquire(&f->lock)',
		'G13QueueResources__retain_file_reference(resources)', '.usc_base = queue->usc_base'])!
	queue := body(source, prefix + 'GpuFile__create_queue')!
	ordered(queue, ['workqueue__new_workqueue(', 'logical->usc_base = usc_base;', 'array_push'])!
	selection := body(source, prefix + 'GpuFile__select_ioctl_abi')!
	ordered(selection, ['klock__Lock__acquire(&f->lock)', 'f->ioctl_abi != 0', 'f->ioctl_abi != abi',
		'f->ioctl_abi = abi;'])!
	registry := body(source, prefix + 'get_or_create_file')!
	ordered(registry, ['klock__Lock__acquire(&gpu__agx__file__file_map_lock)',
		'gpu__agx__file__new_gpu_file(', 'map__set(&gpu__agx__file__file_map,'])!
	for name in ['get_params', 'get_time', 'vm_create', 'vm_destroy', 'vm_bind', 'gem_create',
		'gem_mmap_offset', 'gem_bind_object', 'queue_create', 'queue_destroy', 'submit'] {
		require(source.contains('.handler = ' + prefix + 'modern_' + name + '_handler'), 'native table missing modern ' + name)!
	}
	require(source.contains('.ioctl_abi = ' + prefix + 'ioctl_abi_handle'), 'native driver must install its ABI selector')!
}

fn main() {
	assert os.args.len == 3 && os.args[1] in ['--native', '--selftest']
	source := os.read_file(os.args[2])!
	check(source)!
	if os.args[1] == '--selftest' {
		for old, replacement in {
			'submission__stage_packet_syncs(u64 owner, u64 pointer, u32 in_count, u32 out_count) {': 'submission__stage_packet_syncs(u64 owner, u64 pointer, u32 in_count, u32 out_count) {\nmemdup(0, 1);'
			'memory__free(workspace);':                                                              ''
			'copy_from_user(storage, data->userptr, bytes)':                                         'copy_from_user(storage, data->userptr, data->stride)'
			'.usc_base = queue->usc_base':                                                           '.usc_base = 0'
			'transferred = result == 0;':                                                            'transferred = false;'
			'.ioctl_abi = gpu__agx__file__ioctl_abi_handle':                                         '.ioctl_abi = NULL'
		} {
			require(source.contains(old), 'mutation token absent: ' + old)!
			if _ := check(source.replace(old, replacement)) {
				panic('native checker accepted ' + old)
			}
		}
		println('Six native boxing/free/copy/USC/transfer/registration mutations rejected.')
	}
	println('Native modern ABI: 18 bodies reject implicit allocations; scratch owners, whole-copy ordering, USC capture and driver dispatch checked.')
}
