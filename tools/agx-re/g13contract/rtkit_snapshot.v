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
