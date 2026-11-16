// SPDX-License-Identifier: GPL-2.0-or-later
import os

const helpers = [
	'gpu__agx__file__GpuFile__reap_orphaned_g13_queues_locked',
	'gpu__agx__file__GpuFile__find_vm',
	'gpu__agx__file__GpuFile__find_owned_vm',
	'gpu__agx__file__GpuFile__ioctl_vm_destroy',
	'gpu__agx__file__GpuFile__reap_detached_vms_locked',
	'gpu__agx__file__GpuFile__reap_detached_g13_queues_locked',
	'gpu__agx__file__reap_open_detached_g13_queues',
	'gpu__agx__gpu__g13_tile_info',
	'gpu__agx__gpu__g13_div_round_up',
	'gpu__agx__gpu__g13_align_u32',
	'cpu__read_ctr_el0',
	'cpu__clean_invalidate_data_cache_line',
	'cpu__clean_invalidate_data_cache_to_poc',
	'memory__set_ram_direct_map_uncached',
	'bo__Table__mmap_attributes',
	'bo__Table__valid_mmap_range',
	'gpu__agx__file__GpuFile__mmap_attributes',
	'gpu__agx__file__GpuFile__valid_mmap_range',
	'gpu__agx__file__mmap_attributes_handle',
	'gpu__agx__file__retain_mmap_range_handle',
	'fw__g13_timestamp_user_ts_offset_for',
	'fw__g13_microseq_timestamp_v13_5',
	'fw__make_g13_vertex_v13_5',
	'fw__make_g13_compute_v13_5',
	'fw__make_g13_fragment_v13_5',
	'fw__g13_microseq_finalize_compute_v13_5',
	'gpu__agx__gpu__write_g13_start_vertex',
	'fw__g13_microseq_start_vertex_v13_5',
	'gpu__agx__gpu__GpuManager__g13_submission_status',
	'gpu__agx__file__GpuFile__ioctl_gem_bind_object',
	'gpu__agx__gpu__GpuManager__can_query_global_params',
	'params__copy_global',
	'pgtable__alloc_table_page',
	'gpu__agx__file__GpuFile__mapping_survivor_count_locked',
	'pgtable__UatPgtable__prepare_map_range',
	'gpu__agx__file__GpuFile__reserve_mapping_slots_locked',
	'gpu__agx__file__GpuFile__unbind_range_locked',
	'bo__create_size_error',
	'vm__bind_backing_size',
	'pgtable__UatPgtable__map_repeated_page',
	'vm__valid_bind_header',
	'vm__valid_bind_shape',
	'gpu__agx__file__GpuFile__capture_submission_queue',
	'gpu__agx__file__release_submission_queue',
	'gpu__agx__gpu__G13QueueResources__retain_file_reference',
	'gpu__agx__gpu__G13QueueResources__release_file_reference',
	'gpu__agx__gpu__G13QueueResources__has_file_references',
	'drm__ioctl_syncobj_create',
	'syncobj__new_syncobj_with_flags',
	'syncobj__insert_handle',
	'syncobj__import_syncobj',
	'drm__ioctl_syncobj_handle_to_fd',
	'drm__ioctl_syncobj_fd_to_handle',
	'drm__syncobj_from_fd',
	'drm__create_syncobj_fd',
	'drm__create_sync_file_fd',
	'drm__create_sync_file_fd_at',
	'file__fd_number_reserved_locked',
	'file__reserve_fd',
	'file__remove_fd_reservation_locked',
	'file__cancel_fd_reservation',
	'file__fdnum_install_reserved_fd',
	'file__fdnum_create_from_reserved_resource',
	'file__fdnum_create_from_fd',
	'file__fdnum_create_pair',
	'drm__SyncobjResource__unref',
	'drm__SyncFileResource__unref',
	'drm__SyncFileResource__poll_status',
	'drm__SyncFileResource__ioctl',
	'drm__sync_file_info_ioctl',
	'drm__sync_file_deadline_ioctl',
	'drm__sync_info_names',
	'drm__sync_name_append',
	'drm__sync_name_number',
	'syncobj__snapshot',
	'syncobj__get_timeline_fence',
	'submission__stage_sync_array',
	'submission__install_output_syncs',
	'syncobj__poll_fence',
	'syncobj__cancel_fence_event',
	'syncobj__DmaFence__notify_events_locked',
	'syncobj__next_namespace_handle',
	'syncobj__lookup',
	'syncobj__destroy',
	'syncobj__destroy_owner',
	'drm__syncobj_wait_geometry',
	'drm__new_syncobj_wait_buffer',
	'drm__new_syncobj_handle_buffer',
	'drm__SyncobjWaitBuffer__free_owned',
	'syncobj__prepare_capture',
	'syncobj__captured_fence',
	'syncobj__SyncObj__publish_captures_locked',
	'syncobj__release_capture',
	'drm__ioctl_syncobj_wait',
	'drm__ioctl_syncobj_reset',
	'drm__ioctl_syncobj_signal',
	'syncobj__new_private_stub',
	'syncobj__replace_fence',
	'syncobj__signal',
	'syncobj__signal_error',
	'fw__g13_fragment_tib_blocks',
	'vm__driver_window',
	'gpu__agx__gpu__GpuManager__retained_g13_queue_resources',
	'vm__IdentityPool__allocate',
	'mmu__allocate_context_identity',
	'gpu__agx__file__GpuFile__retire_mapping_locked',
	'gpu__agx__file__GpuFile__cleanup_closed_mappings_locked',
	'gpu__agx__gpu__GpuManager__flush_g13_file_mapping',
	'gpu__agx__file__install_g13_batch_barriers',
	'gpu__agx__gpu__GpuManager__initialize_g13_barriers_locked',
	'gpu__agx__gpu__GpuManager__g13_ring_has_space_locked',
	'gpu__agx__file__poll_g13_pending',
	'gpu__agx__file__g13_pending_dispatch_complete',
	'gpu__agx__file__process_pending_submissions',
	'gpu__agx__file__register_g13_pending',
	'gpu__agx__file__admit_g13_pending',
	'gpu__agx__file__submit_g13_pending',
	'gpu__agx__gpu__GpuManager__g13_batch_ready',
	'gpu__agx__gpu__GpuManager__admit_g13_batch_locked',
	'gpu__agx__gpu__GpuManager__submit_g13_batch',
	'gpu__agx__gpu__g13_batch_address',
	'gpu__agx__gpu__append_g13_batch_command',
	'gpu__agx__file__g13_dependencies_ready',
	'syncobj__queue_dependency_ready',
	'gpu__agx__gpu__GpuManager__queue_g13_submission',
	'gpu__agx__gpu__GpuManager__accept_g13_submission_locked',
	'gpu__agx__gpu__GpuManager__capture_g13_initial_events',
	'gpu__agx__gpu__GpuManager__release_g13_initial_events',
	'gpu__agx__gpu__GpuManager__resolve_g13_initial_barriers_locked',
	'gpu__agx__gpu__write_g13_barrier',
	'gpu__agx__gpu__release_g13_barrier_pins',
	'gpu__agx__event__WorkQueueEvents__resolve_initial',
	'gpu__agx__event__WorkQueueEvents__ticket',
	'gpu__agx__event__WorkQueueEvents__retain',
	'gpu__agx__event__WorkQueueEvents__release',
	'gpu__agx__event__WorkQueueEvents__can_publish',
	'gpu__agx__event__WorkQueueEvents__can_submit',
	'gpu__agx__event__WorkQueueEvents__admit',
	'gpu__agx__event__WorkQueueEvents__can_publish_batch',
	'gpu__agx__event__WorkQueueEvents__publish',
	'gpu__agx__gpu__g13_barrier_source',
]

fn result_type(name string) string {
	if name == 'gpu__agx__file__GpuFile__reap_orphaned_g13_queues_locked' { return 'void' }
	if name in ['gpu__agx__file__GpuFile__find_vm', 'gpu__agx__file__GpuFile__find_owned_vm'] { return '__v_option_mmu__UatContextptr' }
	if name == 'gpu__agx__file__GpuFile__ioctl_vm_destroy' { return 'i64' }
	if name == 'gpu__agx__file__GpuFile__reap_detached_vms_locked' { return 'void' }
	if name == 'gpu__agx__file__GpuFile__capture_submission_queue' { return '__v_option_gpu__agx__file__G13SubmissionQueue' }
	if name in ['gpu__agx__file__release_submission_queue', 'gpu__agx__gpu__G13QueueResources__retain_file_reference', 'gpu__agx__gpu__G13QueueResources__release_file_reference'] { return 'void' }
	if name in ['gpu__agx__file__GpuFile__reap_detached_g13_queues_locked', 'gpu__agx__file__reap_open_detached_g13_queues'] { return 'void' }
	if name == 'gpu__agx__gpu__g13_tile_info' { return '__v_option_gpu__agx__gpu__G13TileInfo' }
	if name in ['gpu__agx__gpu__g13_div_round_up', 'gpu__agx__gpu__g13_align_u32'] { return 'u32' }
	if name in ['cpu__read_ctr_el0', 'bo__Table__mmap_attributes', 'gpu__agx__file__GpuFile__mmap_attributes', 'gpu__agx__file__mmap_attributes_handle'] { return 'u64' }
	if name in ['cpu__clean_invalidate_data_cache_line', 'cpu__clean_invalidate_data_cache_to_poc'] { return 'void' }
	if name == 'fw__g13_timestamp_user_ts_offset_for' { return '__v_option_u64' }
	if name == 'fw__g13_microseq_timestamp_v13_5' { return 'fw__G13MicroseqTimestampV135' }
	if name == 'fw__make_g13_vertex_v13_5' { return 'fw__G13RunVertexV135' }
	if name == 'fw__make_g13_compute_v13_5' { return 'fw__G13RunComputeV135' }
	if name == 'fw__make_g13_fragment_v13_5' { return 'fw__G13RunFragmentV135' }
	if name == 'fw__g13_microseq_finalize_compute_v13_5' { return 'fw__G13MicroseqFinalizeComputeV135' }
	if name == 'gpu__agx__gpu__write_g13_start_vertex' { return 'u64' }
	if name == 'fw__g13_microseq_start_vertex_v13_5' { return 'fw__G13MicroseqStartVertexV135' }
	if name.ends_with('GpuManager__g13_submission_status') { return 'i64' }
	if name.ends_with('GpuFile__ioctl_gem_bind_object') { return 'i64' }
	if name.ends_with('GpuManager__can_query_global_params') { return 'bool' }
	if name == 'params__copy_global' { return 'i64' }
	if name == 'pgtable__alloc_table_page' { return '__v_option_u64ptr' }
	if name.ends_with('GpuFile__unbind_range_locked') { return 'i64' }
	if name.ends_with('GpuFile__mapping_survivor_count_locked') { return 'i64' }
	if name == 'bo__create_size_error' { return 'i64' }
	if name == 'vm__bind_backing_size' { return 'u64' }
	if name in ['file__reserve_fd', 'file__fdnum_install_reserved_fd', 'file__fdnum_create_from_reserved_resource', 'file__fdnum_create_from_fd', 'drm__create_sync_file_fd_at'] { return '__v_option_i64' }
	if name == 'file__cancel_fd_reservation' { return 'void' }
	if name == 'submission__stage_sync_array' { return 'multi_return_i64_submission__SyncArray' }
	if name == 'syncobj__get_timeline_fence' { return '__v_option_syncobj__DmaFenceptr' }
	if name == 'syncobj__snapshot' { return 'syncobj__FenceSnapshot' }
	if name == 'drm__SyncFileResource__ioctl' { return '__v_option_i64' }
	if name in ['drm__sync_file_info_ioctl', 'drm__sync_file_deadline_ioctl'] { return 'i64' }
	if name == 'drm__sync_info_names' { return 'void' }
	if name in ['drm__sync_name_append', 'drm__sync_name_number'] { return 'u32' }
	if name == 'drm__SyncFileResource__poll_status' { return 'i64' }
	if name in ['syncobj__cancel_fence_event', 'syncobj__DmaFence__notify_events_locked'] { return 'void' }
	if name in ['drm__create_syncobj_fd', 'drm__create_sync_file_fd'] { return '__v_option_i64' }
	if name in ['drm__SyncobjResource__unref', 'drm__SyncFileResource__unref'] { return '__v_option' }
	if name == 'drm__syncobj_wait_geometry' { return '__v_option_drm__SyncobjWaitGeometry' }
	if name in ['drm__new_syncobj_wait_buffer', 'drm__new_syncobj_handle_buffer'] { return '__v_option_drm__SyncobjWaitBuffer' }
	if name == 'drm__SyncobjWaitBuffer__free_owned' { return 'void' }
	if name in ['drm__ioctl_syncobj_create', 'drm__ioctl_syncobj_wait', 'drm__ioctl_syncobj_reset', 'drm__ioctl_syncobj_signal', 'drm__ioctl_syncobj_handle_to_fd', 'drm__ioctl_syncobj_fd_to_handle'] { return 'i64' }
	if name in ['syncobj__new_syncobj', 'syncobj__new_syncobj_with_flags', 'syncobj__lookup', 'drm__syncobj_from_fd'] { return '__v_option_syncobj__SyncObjptr' }
	if name in ['syncobj__next_namespace_handle', 'syncobj__insert_handle', 'syncobj__import_syncobj'] { return '__v_option_u32' }
	if name == 'syncobj__destroy_owner' { return 'void' }
	if name == 'syncobj__new_private_stub' { return '__v_option_syncobj__DmaFenceptr' }
	if name == 'syncobj__captured_fence' { return '__v_option_syncobj__DmaFenceptr' }
	if name in ['syncobj__signal', 'syncobj__signal_error', 'syncobj__SyncObj__publish_captures_locked', 'syncobj__release_capture', 'syncobj__replace_fence'] { return 'void' }
	if name == 'fw__g13_fragment_tib_blocks' { return '__v_option_u32' }
	if name == 'vm__driver_window' { return '__v_option_vm__DriverWindow' }
	if name.ends_with('retained_g13_queue_resources') { return '__v_option_gpu__agx__gpu__G13QueueResourcesptr' }
	if name.ends_with('IdentityPool__allocate') || name.ends_with('allocate_context_identity') { return '__v_option_u64' }
	if name.ends_with('process_pending_submissions') || name.ends_with('write_g13_barrier')
		|| name.ends_with('release_g13_initial_events') || name.ends_with('release_g13_barrier_pins')
		|| name.ends_with('submit_g13_pending') || name.ends_with('append_g13_batch_command') { return 'void' }
	if name.ends_with('GpuManager__submit_g13_batch') { return 'u64' }
	if name.ends_with('capture_g13_initial_events') { return '__v_option_gpu__agx__gpu__G13InitialEvents' }
	if name.ends_with('WorkQueueEvents__ticket') || name.ends_with('WorkQueueEvents__retain') || name.ends_with('g13_barrier_source') { return '__v_option_gpu__agx__event__Ticket' }
	if name.ends_with('WorkQueueEvents__resolve_initial') { return 'multi_return_int_gpu__agx__event__Ticket' }
	return 'bool'
}

fn function_body(source string, name string) !string {
	marker := result_type(name) + ' ' + name + '('
	mut cursor := 0
	mut found := ''
	for cursor < source.len {
		start := source.index_after(marker, cursor) or { break }
		line_end := source.index_after('\n', start) or { return error('unterminated signature: ' + name) }
		cursor = line_end + 1
		if !source[start..line_end].trim_space().ends_with('{') { continue }
		finish := source.index_after('\n}\n', cursor) or { return error('unterminated body: ' + name) }
		if found != '' { return error('duplicate body: ' + name) }
		found = source[start..finish + 3]
		cursor = finish + 3
	}
	if found == '' { return error('missing body: ' + name) }
	return found
}

fn check(source string) ! {
	for name in helpers {
		body := function_body(source, name)!
		mut allocation_scan := body
		if name.ends_with('GpuFile__reserve_mapping_slots_locked') {
			owned := 'memory__malloc_packed_fallible(bytes)'
			if body.count(owned) != 1 { return error('mapping splits require exactly one checked owned array reservation') }
			allocation_scan = body.replace(owned, 'owned_mapping_table_reservation')
		}
		if name == 'drm__sync_file_info_ioctl' {
			owned := 'memory__malloc_packed_fallible(sizeof(drm__ioctl__SyncFenceInfo))'
			if body.count(owned) != 1 { return error('sync-file info must have exactly one fallible detail allocation') }
			allocation_scan = body.replace(owned, 'owned_sync_file_detail')
		}
		if name == 'drm__sync_name_number' && !body.contains('u8 digits[20]') {
			return error('sync-file decimal formatting must use fixed stack storage')
		}
		if name.ends_with('WorkQueueEvents__retain') {
			owned := 'memory__malloc_packed_fallible(sizeof(gpu__agx__event__TicketBlock))'
			if body.count(owned) != 1 { return error('prepared backlog must have exactly one owned overflow allocation site') }
			allocation_scan = body.replace(owned, 'owned_ticket_block_allocation')
		}
		if name.ends_with('WorkQueueEvents__release') && (body.count('memory__free((void*)(block))') != 1 || body.count('memory__free(') != 1) {
			return error('prepared backlog must have exactly one overflow retirement free site')
		}
		if name == 'drm__new_syncobj_wait_buffer' {
			owned := 'memory__malloc_packed_fallible(geometry.bytes)'
			if body.count(owned) != 1 { return error('large wait storage must have exactly one checked owned allocation site') }
			allocation_scan = body.replace(owned, 'owned_wait_storage_allocation')
		}
		if name == 'drm__new_syncobj_handle_buffer' {
			owned := 'memory__malloc_packed_fallible(geometry.captures_offset)'
			if body.count(owned) != 1 { return error('reset storage must have exactly one checked prefix allocation site') }
			allocation_scan = body.replace(owned, 'owned_reset_storage_allocation')
		}
		if name == 'syncobj__new_private_stub' {
			owned := 'memory__malloc_packed_fallible(sizeof(syncobj__DmaFence))'
			if body.count(owned) != 1 { return error('private stub must have exactly one fallible fence allocation site') }
			if body.count('array_new(sizeof(syncobj__FenceWaiter*), 0, 0)') != 1 {
				return error('private stub waiter array must be initialized empty without allocation')
			}
			allocation_scan = body.replace(owned, 'retained_private_stub_allocation')
		}
		if name == 'syncobj__new_syncobj_with_flags' {
			owned := 'memory__malloc_packed_fallible(sizeof(syncobj__SyncObj))'
			if body.count(owned) != 1 { return error('syncobj creation must have exactly one fallible object allocation site') }
			if body.count('array_new(sizeof(syncobj__TimelinePoint), 0, 0)') != 1 {
				return error('private syncobj timeline array must be initialized empty without allocation')
			}
			allocation_scan = body.replace(owned, 'owned_syncobj_preparation_allocation')
		}
		if name == 'syncobj__import_syncobj' {
			owned := 'memory__malloc_packed_fallible(sizeof(syncobj__SyncobjHandle))'
			if body.count(owned) != 1 { return error('opaque import must have one fallible alias link allocation') }
			allocation_scan = body.replace(owned, 'owned_alias_link_allocation')
		}
		if name in ['drm__create_syncobj_fd', 'drm__create_sync_file_fd_at'] {
			kind := if name == 'drm__create_syncobj_fd' { 'SyncobjResource' } else { 'SyncFileResource' }
			for owned in ['memory__malloc_packed_fallible(sizeof(drm__' + kind + '))',
				'memory__malloc_packed_fallible(sizeof(resource__Resource))'] {
				if body.count(owned) != 1 { return error('export must have exactly one fallible wrapper and one fallible box allocation') }
				allocation_scan = allocation_scan.replace(owned, 'owned_transport_allocation')
			}
		}
		if name == 'drm__SyncobjWaitBuffer__free_owned' &&
			(body.count('memory__free(buffer->allocation)') != 1 || body.count('memory__free(') != 1) {
			return error('large wait storage must have exactly one matching owner free site')
		}
		for allocation in ['memdup', 'HEAP(', 'malloc', 'calloc', 'realloc', '__new_array',
			'new_array_from', 'array_clone', 'array_slice'] {
			if allocation_scan.contains(allocation) { return error(name + ': unexpected temporary allocation: ' + allocation) }
		}
		for copy in ['__v3_struct_eq', 'G13QueueResources __eq'] {
			if body.contains(copy) { return error(name + ': unexpected structural copy/comparison: ' + copy) }
		}
		if name.ends_with('process_pending_submissions') &&
			(!body.contains('void* blocked[128]') || !body.contains('bool unpublished[128]')) {
			return error('scheduler queue gates are not fixed stack arrays')
		}
		if (name.ends_with('register_g13_pending') || name.ends_with('admit_g13_pending') || name.ends_with('submit_g13_pending')) && !body.contains('G13SubmissionJob jobs[64]') {
			return error('acceptance references are not a fixed stack array')
		}
		if name == 'drm__ioctl_syncobj_wait' && (!body.contains('u32 handles[64]')
			|| !body.contains('void* objects[64]') || !body.contains('syncobj__FenceCapture captures[64]')) {
			return error('binary wait snapshots are not fixed stack storage')
		}
		if name in ['drm__ioctl_syncobj_reset', 'drm__ioctl_syncobj_signal'] && (!body.contains('u32 handles[64]')
			|| !body.contains('void* objects[64]') || body.contains('syncobj__FenceCapture captures[')) {
			return error('reset/signal snapshots must use fixed stack handles/objects without capture storage')
		}
		if name.ends_with('admit_g13_batch_locked') && (!body.contains('u32 events[3]') || !body.contains('u32 commands[3]')) {
			return error('batch capacity counts are not fixed stack arrays')
		}
		if name.ends_with('submit_g13_pending') && !body.contains('u32 positions[64]') { return error('batch transfer positions are not fixed stack storage') }
		if name.ends_with('GpuManager__submit_g13_batch') && (!body.contains('G13BatchPipe pipes[3]') || !body.contains('bool binds[64]')) {
			return error('native batch ring/bind plan is not fixed stack storage')
		}
		if name.ends_with('resolve_g13_initial_barriers_locked') && !body.contains('Ticket resolved[2]') {
			return error('resolved initial tickets are not a fixed stack array')
		}
	}
}

fn selftest() ! {
	mut fixture := ''
	for name in helpers {
		kind := result_type(name)
		ending := if kind == 'void' { 'return;' } else if kind == 'bool' { 'return true;' } else { 'return (' + kind + '){0};' }
		owned := if name.ends_with('WorkQueueEvents__retain') { 'memory__malloc_packed_fallible(sizeof(gpu__agx__event__TicketBlock));\n' }
			else if name.ends_with('GpuFile__reserve_mapping_slots_locked') { 'memory__malloc_packed_fallible(bytes);\n' }
			else if name == 'drm__sync_file_info_ioctl' { 'memory__malloc_packed_fallible(sizeof(drm__ioctl__SyncFenceInfo));\n' }
			else if name.ends_with('WorkQueueEvents__release') { 'memory__free((void*)(block));\n' }
			else if name == 'drm__new_syncobj_wait_buffer' { 'memory__malloc_packed_fallible(geometry.bytes);\n' }
			else if name == 'drm__new_syncobj_handle_buffer' { 'memory__malloc_packed_fallible(geometry.captures_offset);\n' }
			else if name == 'syncobj__new_private_stub' { 'memory__malloc_packed_fallible(sizeof(syncobj__DmaFence)); array_new(sizeof(syncobj__FenceWaiter*), 0, 0);\n' }
			else if name == 'syncobj__new_syncobj_with_flags' { 'memory__malloc_packed_fallible(sizeof(syncobj__SyncObj)); array_new(sizeof(syncobj__TimelinePoint), 0, 0);\n' }
			else if name == 'syncobj__import_syncobj' { 'memory__malloc_packed_fallible(sizeof(syncobj__SyncobjHandle));\n' }
			else if name in ['drm__create_syncobj_fd', 'drm__create_sync_file_fd_at'] {
				wrapper_kind := if name == 'drm__create_syncobj_fd' { 'SyncobjResource' } else { 'SyncFileResource' }
				'memory__malloc_packed_fallible(sizeof(drm__' + wrapper_kind + ')); memory__malloc_packed_fallible(sizeof(resource__Resource));\n'
			}
			else if name == 'drm__SyncobjWaitBuffer__free_owned' { 'memory__free(buffer->allocation);\n' } else { '' }
		captures := if name in ['drm__ioctl_syncobj_reset', 'drm__ioctl_syncobj_signal'] { '' } else { 'syncobj__FenceCapture captures[64];\n' }
		fixture += kind + ' ' + name + '(void) {\n' + owned + ' u8 digits[20];\n u32 handles[64];\n void* objects[64];\n ' + captures + ' void* blocked[128];\n bool unpublished[128];\n gpu__agx__gpu__G13SubmissionJob jobs[64];\n gpu__agx__event__Ticket resolved[2];\n u32 events[3];\n u32 commands[3];\n u32 positions[64];\n gpu__agx__gpu__G13BatchPipe pipes[3];\n bool binds[64];\n ' + ending + '\n}\n'
	}
	check(fixture)!
	for name in helpers {
		for allocation in ['memdup', 'HEAP(', 'malloc', 'calloc', 'realloc', '__new_array',
			'new_array_from', 'array_clone', 'array_slice', '__v3_struct_eq', 'G13QueueResources __eq'] {
			if _ := check(fixture.replace(name + '(void) {', name + '(void) { ' + allocation + ';')) {
				return error('allocation selftest accepted ' + name + ': ' + allocation)
			}
		}
	}
	for broken in ['', fixture + fixture,
		fixture.replace('memory__malloc_packed_fallible(bytes);', ''),
		fixture.replace('memory__malloc_packed_fallible(bytes);', 'memory__malloc_packed_fallible(1);'),
		fixture.replace('memory__malloc_packed_fallible(bytes);', 'memory__malloc_packed_fallible(bytes); memory__malloc_packed_fallible(bytes);'),
		fixture.replace('memory__malloc_packed_fallible(sizeof(drm__ioctl__SyncFenceInfo));', ''),
		fixture.replace('memory__malloc_packed_fallible(sizeof(drm__ioctl__SyncFenceInfo));', 'memory__malloc_packed_fallible(1);'),
		fixture.replace('memory__malloc_packed_fallible(sizeof(drm__ioctl__SyncFenceInfo));', 'memory__malloc_packed_fallible(sizeof(drm__ioctl__SyncFenceInfo)); memory__malloc_packed_fallible(sizeof(drm__ioctl__SyncFenceInfo));'),
		fixture.replace('u8 digits[20];', 'u8* digits;'),
		fixture.replace('memory__malloc_packed_fallible(sizeof(gpu__agx__event__TicketBlock));', ''),
		fixture.replace('memory__malloc_packed_fallible(sizeof(gpu__agx__event__TicketBlock));', 'memory__malloc_packed_fallible(1);'),
		fixture.replace('memory__malloc_packed_fallible(sizeof(gpu__agx__event__TicketBlock));', 'memory__malloc_packed_fallible(sizeof(gpu__agx__event__TicketBlock)); memory__malloc_packed_fallible(sizeof(gpu__agx__event__TicketBlock));'),
		fixture.replace('memory__free((void*)(block));', ''),
		fixture.replace('memory__free((void*)(block));', 'memory__free(queue);'),
		fixture.replace('memory__free((void*)(block));', 'memory__free((void*)(block)); memory__free((void*)(block));'),
		fixture.replace('memory__free((void*)(block));', 'memory__free((void*)(block)); memory__free(queue);'),
		fixture.replace('memory__malloc_packed_fallible(geometry.bytes);', ''),
		fixture.replace('memory__malloc_packed_fallible(geometry.bytes);', 'memory__malloc_packed_fallible(1);'),
		fixture.replace('memory__malloc_packed_fallible(geometry.bytes);', 'memory__malloc_packed_fallible(geometry.bytes); memory__malloc_packed_fallible(geometry.bytes);'),
		fixture.replace('memory__malloc_packed_fallible(geometry.captures_offset);', ''),
		fixture.replace('memory__malloc_packed_fallible(geometry.captures_offset);', 'memory__malloc_packed_fallible(geometry.bytes);'),
		fixture.replace('memory__malloc_packed_fallible(geometry.captures_offset);', 'memory__malloc_packed_fallible(geometry.captures_offset); memory__malloc_packed_fallible(geometry.captures_offset);'),
		fixture.replace('drm__ioctl_syncobj_reset(void) {', 'drm__ioctl_syncobj_reset(void) { syncobj__FenceCapture captures[64];'),
		fixture.replace('drm__ioctl_syncobj_signal(void) {', 'drm__ioctl_syncobj_signal(void) { syncobj__FenceCapture captures[64];'),
		fixture.replace('memory__malloc_packed_fallible(sizeof(syncobj__DmaFence));', ''),
		fixture.replace('memory__malloc_packed_fallible(sizeof(syncobj__DmaFence));', 'memory__malloc_packed_fallible(1);'),
		fixture.replace('memory__malloc_packed_fallible(sizeof(syncobj__DmaFence));', 'memory__malloc_packed_fallible(sizeof(syncobj__DmaFence)); memory__malloc_packed_fallible(sizeof(syncobj__DmaFence));'),
		fixture.replace('array_new(sizeof(syncobj__FenceWaiter*), 0, 0)', 'array_new(sizeof(syncobj__FenceWaiter*), 0, 1)'),
		fixture.replace('memory__malloc_packed_fallible(sizeof(syncobj__SyncObj));', ''),
		fixture.replace('memory__malloc_packed_fallible(sizeof(syncobj__SyncObj));', 'memory__malloc_packed_fallible(1);'),
		fixture.replace('memory__malloc_packed_fallible(sizeof(syncobj__SyncObj));', 'memory__malloc_packed_fallible(sizeof(syncobj__SyncObj)); memory__malloc_packed_fallible(sizeof(syncobj__SyncObj));'),
		fixture.replace('array_new(sizeof(syncobj__TimelinePoint), 0, 0)', 'array_new(sizeof(syncobj__TimelinePoint), 0, 1)'),
		fixture.replace('memory__malloc_packed_fallible(sizeof(syncobj__SyncobjHandle));', ''),
		fixture.replace('memory__malloc_packed_fallible(sizeof(syncobj__SyncobjHandle));', 'memory__malloc_packed_fallible(1);'),
		fixture.replace('memory__malloc_packed_fallible(sizeof(syncobj__SyncobjHandle));', 'memory__malloc_packed_fallible(sizeof(syncobj__SyncobjHandle)); memory__malloc_packed_fallible(sizeof(syncobj__SyncobjHandle));'),
		fixture.replace('memory__malloc_packed_fallible(sizeof(drm__SyncobjResource));', ''),
		fixture.replace('memory__malloc_packed_fallible(sizeof(drm__SyncFileResource));', 'memory__malloc_packed_fallible(1);'),
		fixture.replace('memory__malloc_packed_fallible(sizeof(resource__Resource));', ''),
		fixture.replace('memory__malloc_packed_fallible(sizeof(resource__Resource));', 'memory__malloc_packed_fallible(sizeof(resource__Resource)); memory__malloc_packed_fallible(sizeof(resource__Resource));'),
		fixture.replace('memory__free(buffer->allocation);', ''),
		fixture.replace('memory__free(buffer->allocation);', 'memory__free(buffer);'),
		fixture.replace('memory__free(buffer->allocation);', 'memory__free(buffer->allocation); memory__free(buffer->allocation);'),
		fixture.replace('void* blocked[128];', 'void** blocked;'),
		fixture.replace('bool unpublished[128];', 'bool* unpublished;'),
		fixture.replace('u32 handles[64];', 'u32* handles;'),
		fixture.replace('void* objects[64];', 'void** objects;'),
		fixture.replace('syncobj__FenceCapture captures[64];', 'syncobj__FenceCapture* captures;'),
		fixture.replace('G13SubmissionJob jobs[64];', 'G13SubmissionJob* jobs;'),
		fixture.replace('u32 events[3];', 'u32* events;'),
		fixture.replace('u32 commands[3];', 'u32* commands;'),
		fixture.replace('u32 positions[64];', 'u32* positions;'),
		fixture.replace('G13BatchPipe pipes[3];', 'G13BatchPipe* pipes;'),
		fixture.replace('bool binds[64];', 'bool* binds;'),
		fixture.replace('Ticket resolved[2];', 'Ticket* resolved;')] {
		if _ := check(broken) { return error('malformed storage selftest accepted') }
	}
	println('G13 prefix storage checker selftest: PASS')
}

fn main() {
	if os.args.len != 2 { eprintln('Usage: check-prefix-storage GENERATED_ARM_C | --selftest'); exit(2) }
	if os.args[1] == '--selftest' { selftest() or { eprintln(err); exit(1) }; return }
	source := os.read_file(os.args[1]) or { eprintln(err); exit(2) }
	check(source) or { eprintln(err); exit(1) }
	println('G13 submission/mapping storage: ${helpers.len} live helpers contain no temporary allocations; only checked owned overflow, request, syncobj/alias, transport/box and retained private completion allocation sites are permitted')
}
