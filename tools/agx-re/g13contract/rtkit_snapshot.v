// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

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
		'return mgr.rtk.handle_system_message(msg)'], 'G13 runtime buffer requests complete under the shutdown lock')!
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

	reply := section(transport, 'fn (mut rtk RTKit) reply_system_buffer(', 'fn (rtk &RTKit) dump_syslog_entry(', 'Vinix RTKit shared buffer')!
	require_order(reply, ['iova_mask := if ep == ep_oslog { oslog_iova_mask } else { buffer_iova_mask }',
		'size = (msg >> 36)', 'requested_iova = (msg << 12) & iova_mask', 'size = ((msg >> 44)',
		'requested_iova = msg & iova_mask', 'mut iova := rtk.system_iovas[ep]', 'if iova != 0',
		'size != rtk.system_sizes[ep]', 'requested_iova != 0 && requested_iova != (iova & iova_mask)',
		'return true', '} else {', 'requested_iova != 0', 'return false', 'iova = rtk.shmem_alloc(rtk.shmem_context, size)',
		'if iova == 0', 'return false',
		'rtk.system_iovas[ep] = iova', 'rtk.system_sizes[ep] = size', 'wire_iova := iova & iova_mask',
		'(size << 36) | (wire_iova >> 12)', '((size >> 12) << 44) | wire_iova',
		'sent := rtk.send_message(ep, reply)', 'return sent || ep != ep_crashlog'],
		'Vinix stores the live mapping before sending and tolerates logging reply timeouts')!
	for function in ['ioreport', 'syslog', 'oslog'] {
		receiver := linux.all_after('static void apple_rtkit_${function}_rx(').all_before('\nstatic ')
		require(receiver.contains('apple_rtkit_common_rx_get_buffer'), 'Asahi ${function} shares retry logic')!
	}
	receiver := section(transport, 'pub fn (mut rtk RTKit) handle_system_message(', 'fn start_system_endpoints(', 'Vinix RTKit receive')!
	require_order(receiver, ['ep_ioreport {', 'if kind == buffer_request', 'return rtk.reply_system_buffer(ep, msg.data0)',
		'ep_syslog {', 'if kind == buffer_request', 'return rtk.reply_system_buffer(ep, msg.data0)',
		'ep_oslog {', 'if u8(msg.data0 >> 56) == buffer_request', 'return rtk.reply_system_buffer(ep, msg.data0)'],
		'Vinix logging endpoints share the buffer retry handler')!
}
