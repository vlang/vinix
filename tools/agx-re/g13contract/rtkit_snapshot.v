// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import os

fn check_rtkit_snapshot(transport string, manager string, linux string, rust string) ! {
	crash := section(linux, 'static void apple_rtkit_crashlog_rx(', 'static void apple_rtkit_ioreport_rx(', 'Asahi RTKit crash reader')!
	require_order(crash, ['u8 *bfr __free(kfree)', 'bfr = kzalloc(rtk->crashlog_buffer.size, GFP_KERNEL)',
		'apple_rtkit_memcpy(rtk, bfr, &rtk->crashlog_buffer', 'apple_rtkit_crashlog_dump(rtk, bfr',
		'rtk->crashed = true', 'rtk->ops->crashed(rtk->cookie, bfr'],
		'Asahi decodes and reports a private copy of the retained firmware buffer')!
	stop_rx := section(linux, 'static void apple_rtkit_stop_rx(', 'static void apple_rtkit_release_rx(', 'Asahi RTKit stop')!
	require_order(stop_rx, ['apple_rtkit_detach_rx(rtk)', 'destroy_workqueue(rtk->wq)'], 'Asahi quiesces RX before freeing buffers')!
	stop := section(linux, 'void apple_rtkit_free(', 'EXPORT_SYMBOL_GPL(apple_rtkit_free)', 'Asahi RTKit free')!
	require_order(stop, ['apple_rtkit_stop_rx(rtk)', 'apple_rtkit_free_buffer(rtk, &rtk->crashlog_buffer)'], 'Asahi keeps the buffer alive through receive work')!
	require_order(rust, ['T::shmem_alloc(', 'bfr_mut.buffer = sysmem.as_ptr()', 'bfr_mut.private = KBox::into_raw(boxed)',
		'fn shmem_destroy_callback', 'drop(KBox::from_raw(bfr_mut.private'],
		'Asahi Rust shmem bridge owns the mapped buffer until destruction')!

	read := section(transport, 'fn (rtk &RTKit) dump_crashlog()', 'fn management_type(', 'Vinix RTKit crash reader')!
	require_order(read, ['allocated > max_system_buffer_size', 'memory.pmm_alloc_nozero_nowait(pages)',
		'physical == unsafe { nil }', 'defer { memory.pmm_free(physical, pages) }', 'cpu.dmb_ishld()',
		'if !rtk.shmem_read(rtk.shmem_context, iova, data, allocated)', 'return', 'crashlog_u32(data, 0)'],
		'Vinix parses a fallible private snapshot with unconditional cleanup')!
	copy := section(manager, 'fn copy_rtkit_shmem(', 'struct G13ChannelAllocations {', 'Vinix RTKit buffer snapshot')!
	require_order(copy, ['mgr.rtkit_buffer_lock.acquire()', 'mgr.rtkit_buffer_lock.release()',
		'buffer.phys == 0 || iova < buffer.va || size > buffer.size', 'offset > buffer.size - size',
		'C.memcpy(destination, voidptr(buffer.phys + higher_half + offset), size)'], 'Vinix copies a bounded interval under the release lock')!
	receive := section(manager, 'fn (mut mgr GpuManager) handle_role_system_message(', '// Drain the ASC transport', 'Vinix RTKit system receive')!
	require_order(receive, ['role == 0 && mgr.hw_config.gpu_gen == .g13',
		'mailbox.msg_endpoint(&msg) != rtkit.ep_crashlog || mgr.rtk.system_iovas[rtkit.ep_crashlog] == 0',
		'mgr.lock.acquire()', 'defer { mgr.lock.release() }', 'if mgr.state != .running { return true }',
		'return mgr.rtk.handle_system_message_wait(msg, mgr.g13_rtkit_send_wait_locked())'],
		'G13 holds the shutdown lock for buffer allocation and passes it through to the guarded reply')!
	active := section(manager, 'fn rtkit_transport_running(', 'fn (mut mgr GpuManager) handle_role_system_message(', 'Vinix runtime TX liveness')!
	require(active.contains('return mgr.state == .running'), 'G13 declines TX retry after loss or shutdown')!
	require_order(active, ['if mgr.rtkit_send_irq == 0 { return mailbox.SendWait{} }', 'irq: mgr.rtkit_send_irq',
		'lock: unsafe { &mgr.lock }', 'active: rtkit_transport_running'], 'Only a reserved M1 route uses the guarded transmit wait')!
	pipe := section(manager, 'fn (mut mgr GpuManager) ring_g13_batch_pipe_locked(', '// Send a firmware-control message', 'Vinix batch pipe doorbell')!
	require(manager.contains('return (priority % 4) << 2 | (cmd_type % 3)'), 'Vinix uses the reference pipe and priority bits')!
	require_order(pipe, ['mgr.ring_g13_doorbell_locked(pipe_doorbell(priority, cmd_type))',
		'if mgr.state != .running { return false }', 'msg_tx_doorbell | u64(channel_id)',
		'mgr.rtk.send_message_wait(u8(ep_doorbell), message, mgr.g13_rtkit_send_wait_locked())'],
		'Vinix sends the reference work-pipe selector through the guarded transport')!
	system_reply := section(transport, 'fn (mut rtk RTKit) send_system_reply(', 'fn start_system_endpoints(', 'Vinix system reply transmit')!
	require_order(system_reply, ['rtk.send_message_wait(ep, data, wait)',
		'wait.lock != unsafe { nil } && !wait.active(wait.context)'],
		'Vinix transmits the scalar reply under the runtime gate and accepts cancellation once stopped')!
	release := section(manager, 'fn (mut mgr GpuManager) release_rtkit_buffers(', 'fn (mut mgr GpuManager) alloc_g13_channel_pair(', 'Vinix RTKit buffer lifetime')!
	require_order(release, ['mgr.rtkit_buffer_lock.acquire()', 'mgr.free_shared_buffer(mut mgr.rtkit_buffers[count])',
		'mgr.rtkit_buffers.clear()', 'mgr.rtkit_buffer_lock.release()'], 'Vinix releases RTKit backing under the snapshot lock')!
}

fn check_rtkit_crashlog(transport string, linux string, header string, decoder string) ! {
	crash := section(linux, 'static void apple_rtkit_crashlog_rx(', 'static void apple_rtkit_ioreport_rx(', 'Asahi RTKit crash receive')!
	require(linux.contains('#define APPLE_RTKIT_CRASHLOG_CRASH 1'), 'Asahi RTKit crash type')!
	require_order(crash, ['if (type != APPLE_RTKIT_CRASHLOG_CRASH)', 'return;', 'if (!rtk->crashlog_buffer.size)',
		'apple_rtkit_common_rx_get_buffer', 'apple_rtkit_crashlog_dump'], 'Asahi ignores unknown crash messages')!
	require(header.contains('sizeof(struct apple_rtkit_crashlog_header) == 0x20'), 'Asahi RTKit header size')!
	require_order(decoder, ['sizeof(struct apple_rtkit_crashlog_mbox_entry) == 0x18',
		'u64 regs[31];', 'u64 sp;', 'u64 pc;', 'u64 psr;', 'u64 far;', 'u64 esr;',
		'sizeof(struct apple_rtkit_crashlog_regs) == 0x350'], 'Asahi RTKit mailbox and exception geometry')!
	dispatch := decoder.all_after('void apple_rtkit_crashlog_dump(')
	require_order(dispatch, ['bfr + offset + 12', 'case APPLE_RTKIT_CRASHLOG_HEADER_FOURCC:',
		'case APPLE_RTKIT_CRASHLOG_STR:', 'case APPLE_RTKIT_CRASHLOG_VERSION:',
		'case APPLE_RTKIT_CRASHLOG_MBOX:', 'case APPLE_RTKIT_CRASHLOG_TIME:',
		'case APPLE_RTKIT_CRASHLOG_REGS:', 'offset += section_size'], 'Asahi handles the five standard crash records')!

	require(transport.contains('const crash_notification = u8(1)'), 'Vinix RTKit crash type')!
	receive := section(transport, 'pub fn (mut rtk RTKit) handle_system_message(', 'fn start_system_endpoints(', 'Vinix RTKit crash receive')!
	require_order(receive, ['ep_crashlog {', 'management_type(msg.data0) != crash_notification', 'return true',
		'rtk.system_iovas[ep] == 0', 'rtk.reply_system_buffer', 'rtk.dump_crashlog()', 'rtk.state = .error'],
		'Vinix ignores unknown notifications before negotiation or crash handling')!
	read := section(transport, 'fn (rtk &RTKit) dump_crashlog()', 'fn management_type(', 'Vinix RTKit record parser')!
	require_order(read, ['total < crashlog_header_size || u64(total) > allocated',
		'offset <= total - crashlog_entry_header_size', 'length < crashlog_entry_header_size || length > total - offset',
		'payload := offset + crashlog_entry_header_size', 'size := length - crashlog_entry_header_size',
		'if size >= 5', 'if size >= 17', 'if size >= 28', 'if size >= 8', 'if size >= 0x350', 'offset += length'],
		'Vinix validates snapshot and payload boundaries before decoding standard records')!
	mailbox := section(transport, 'fn (rtk &RTKit) print_crashlog_mailbox(', 'fn (rtk &RTKit) print_crashlog_registers(', 'Vinix RTKit mailbox decoder')!
	require_order(mailbox, ['offset + 16', 'offset + 24', 'count := (size - 28) / 24', 'i < count', 'offset + 28 + i * 24'],
		'Vinix decodes only complete mailbox entries in the payload')!
}

fn check_rtkit_buffer_retries(transport string, linux string) ! {
	buffer := section(linux, 'static int apple_rtkit_common_rx_get_buffer(', 'static void apple_rtkit_free_buffer(', 'Asahi RTKit shared buffer')!
	require_order(buffer, ['if (buffer->size)', 'request.size != buffer->size',
		'request.iova != buffer->iova', '(request.iova || buffer->is_mapped)', 'return -EBUSY;',
		'goto reply;', 'apple_rtkit_alloc_shmem(rtk, &request)', '*buffer = request;', 'reply:',
		'buffer->iova >> 12', 'buffer->size >> 12', 'apple_rtkit_send_message(rtk, ep, reply'],
		'Asahi reuses a live host allocation and publishes the original reply format')!

	reply := section(transport, 'fn (mut rtk RTKit) reply_system_buffer(', 'fn (mut rtk RTKit) acknowledge_log(', 'Vinix RTKit shared buffer')!
	require_order(reply, ['iova_mask := if ep == ep_oslog { oslog_iova_mask } else { buffer_iova_mask }',
		'size = (msg >> 36)', 'requested_iova = (msg << 12) & iova_mask', 'size = ((msg >> 44)',
		'requested_iova = msg & iova_mask', 'mut iova := rtk.system_iovas[ep]', 'if iova != 0',
		'size != rtk.system_sizes[ep]', 'requested_iova != 0 && requested_iova != (iova & iova_mask)',
		'return true', '} else {', 'requested_iova != 0', 'return rtk.nonfatal_log_errors',
		'iova = rtk.shmem_alloc(rtk.shmem_context, size)', 'if iova == 0', 'return rtk.nonfatal_log_errors',
		'rtk.system_iovas[ep] = iova', 'rtk.system_sizes[ep] = size', 'wire_iova := iova & iova_mask',
		'(size << 36) | (wire_iova >> 12)', '((size >> 12) << 44) | wire_iova',
		'sent := rtk.send_system_reply(ep, reply, wait)', 'return sent || ep != ep_crashlog || rtk.nonfatal_log_errors'],
		'Vinix stores the live mapping before sending and applies the configured timeout policy')!
	for function in ['ioreport', 'syslog', 'oslog'] {
		receiver := linux.all_after('static void apple_rtkit_${function}_rx(').all_before('\nstatic ')
		require(receiver.contains('apple_rtkit_common_rx_get_buffer'), 'Asahi ${function} shares retry logic')!
	}
	receiver := section(transport, 'pub fn (mut rtk RTKit) handle_system_message(', 'fn start_system_endpoints(', 'Vinix RTKit receive')!
	require_order(receiver, ['ep_ioreport {', 'if kind == buffer_request', 'return rtk.reply_system_buffer(ep, msg.data0, wait)',
		'ep_syslog {', 'if kind == buffer_request', 'return rtk.reply_system_buffer(ep, msg.data0, wait)',
		'ep_oslog {', 'kind := u8(msg.data0 >> 56)', 'if kind == buffer_request', 'return rtk.reply_system_buffer(ep, msg.data0, wait)'],
		'Vinix logging endpoints share the buffer retry handler')!
}

fn check_rtkit_buffer_startup(transport string, linux string, repo string) ! {
	buffer := section(linux, 'static int apple_rtkit_common_rx_get_buffer(', 'static void apple_rtkit_free_buffer(', 'Asahi RTKit setup')!
	require_order(buffer, ['if (!request.size)', 'goto error;',
		'err = apple_rtkit_alloc_shmem(rtk, &request)', 'if (err)', 'goto error;', '*buffer = request;',
		'apple_rtkit_send_message(rtk, ep, reply, NULL, false)', 'return 0;', 'error:', 'return err;'],
		'Asahi publishes no backing on setup failure and retains a negotiated buffer through reply failure')!
	crash := section(linux, 'static void apple_rtkit_crashlog_rx(', 'static void apple_rtkit_ioreport_rx(', 'Asahi RTKit crash setup')!
	require_order(crash, ['if (!rtk->crashlog_buffer.size)', 'apple_rtkit_common_rx_get_buffer', 'goto unmapped;',
		'if (!rtk->crashlog_inherited)', 'return;', 'rtk->crashed = true', 'unmapped:',
		'if (!rtk->crashlog_inherited)', 'return;'], 'A fresh Asahi crash endpoint can negotiate again after setup failure')!
	require(transport.contains('nonfatal_log_errors bool\n'), 'Vinix buffer failure policy defaults to strict handling')!
	manager := read(os.join_path(repo, 'kernel/gpu/agx/gpu/gpu.v'))!
	create := section(manager, 'pub fn new_gpu_manager(', 'fn (mut mgr GpuManager) boot_firmware_role(', 'Vinix G13 RTKit startup')!
	require_order(create, ['if cfg.gpu_gen == .g13 {', 'set_shmem_allocator(voidptr(mgr), allocate_rtkit_shmem)',
		'mgr.rtk.nonfatal_log_errors = true', '\n\t}', 'return mgr'], 'Only G13 enables nonfatal setup failures')!
	allocation := section(manager, 'fn alloc_buffer_from_heap(', 'fn (mut mgr GpuManager) alloc_shared_buffer_with_protection(', 'Vinix RTKit backing allocator')!
	require_order(allocation, ['pmm_alloc_aligned_fallible(pages, 4)', 'if phys == 0', 'return none',
		'va := heap.alloc(size, alloc.gpu_page_size) or {', 'memory.pmm_free(voidptr(phys), pages)', 'return none',
		'if !uat_mgr.map_kernel(va, phys, aligned_size, protection)', 'heap.cancel_unpublished(va)',
		'memory.pmm_free(voidptr(phys), pages)', 'return none', 'return SharedBuffer{'],
		'Failed G13 setup unwinds pages and unpublished heap reservations')!
	pgtable := read(os.join_path(repo, 'kernel/gpu/agx/pgtable/pgtable.v'))!
	mapping := section(pgtable, 'pub fn (mut pt UatPgtable) map(', 'pub fn (mut pt UatPgtable) map_repeated_page(', 'Vinix G13 mapping unwind')!
	require_order(mapping, ['defer { pt.lock.release() }', 'return pt.map_contiguous_locked(',
		'fn (mut pt UatPgtable) map_contiguous_locked(', 'defer { pt.invalidate_range_locked(iova, size) }',
		'if !pt.map_page_locked(', 'pt.unmap_page_locked(iova + j * uat_pgsz)', 'return false'],
		'G13 mapping failure removes partial leaves and invalidates before backing is returned')!
}
