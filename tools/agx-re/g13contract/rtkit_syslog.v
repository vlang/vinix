// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import os

fn check_rtkit_syslog(transport string, linux string) ! {
	init := section(linux, 'static void apple_rtkit_syslog_rx_init(', 'static bool should_crop_syslog_char(', 'Asahi RTKit Syslog init')!
	require_order(init, ['APPLE_RTKIT_SYSLOG_N_ENTRIES', 'APPLE_RTKIT_SYSLOG_MSG_SIZE',
		'rtk->syslog_n_entries = entries', 'rtk->syslog_msg_size = size'], 'Asahi replaces both Syslog fields on INIT')!
	log := section(linux, 'static void apple_rtkit_syslog_rx_log(', 'static void apple_rtkit_syslog_rx(', 'Asahi RTKit Syslog reader')!
	require_order(log, ['u8 idx = msg & 0xff', 'log_context[24]', 'entry_size = 0x20 + rtk->syslog_msg_size',
		'idx >= rtk->syslog_n_entries', 'idx >= rtk->syslog_buffer.size / entry_size',
		'idx * entry_size + 8', 'idx * entry_size + 8 + sizeof(log_context)', 'rtk->syslog_msg_size - 1',
		'should_crop_syslog_char', 'done:', 'apple_rtkit_send_message(rtk, APPLE_RTKIT_EP_SYSLOG, msg'],
		'Asahi bounds Syslog slot reads, crops text, and acknowledges skipped records')!
	require_order(transport, ['const syslog_context_offset = 8', 'const syslog_context_size = 24',
		'const syslog_max_message_size = 255'], 'Vinix Syslog wire geometry')!
	copy := section(transport, 'fn (rtk &RTKit) dump_syslog_entry(', '// Handle one RTKit transport message', 'Vinix RTKit Syslog reader')!
	require_order(copy, ['rtk.shmem_read == unsafe { nil }', 'message_size == 0', 'message_size > syslog_max_message_size',
		'index := u64(u8(msg))', 'index >= rtk.syslog_entries', 'index >= rtk.system_sizes[ep_syslog] / stride',
		'offset := index * stride + syslog_context_offset', 'cpu.dmb_ishld()', 'rtk.shmem_read(',
		'payload[syslog_context_size - 1] = 0', 'limit := syslog_context_size + message_size - 1',
		'payload[end] = 0', 'C.kprintf'], 'Vinix logs a bounded stack copy with both fields terminated')!
	receiver := section(transport, '\n\t\tep_syslog {', '\n\t\tep_oslog {', 'Vinix RTKit Syslog receiver')!
	require_order(receiver, ['if kind == syslog_init', 'rtk.syslog_entries = u32(msg.data0 & 0xff)',
		'rtk.syslog_msg_size = u32((msg.data0 >> 24) & 0xff)', 'if kind == syslog_log',
		'rtk.dump_syslog_entry(msg.data0)', 'return rtk.acknowledge_log(ep, msg.data0)'],
		'Vinix updates both Syslog fields and echoes every notification after the read attempt')!
}

fn check_rtkit_log_acks(transport string, linux string) ! {
	require_order(linux, ['#define APPLE_RTKIT_IOREPORT_UNKNOWN1 0x8',
		'#define APPLE_RTKIT_IOREPORT_UNKNOWN2 0xc', '#define APPLE_RTKIT_SYSLOG_LOG 5'],
		'Asahi IOReport and Syslog notification types')!
	ioreport := section(linux, 'static void apple_rtkit_ioreport_rx(', 'static void apple_rtkit_syslog_rx_init(', 'Asahi IOReport receive')!
	require_order(ioreport, ['case APPLE_RTKIT_IOREPORT_UNKNOWN1:', 'case APPLE_RTKIT_IOREPORT_UNKNOWN2:',
		'apple_rtkit_send_message(rtk, APPLE_RTKIT_EP_IOREPORT, msg,', 'NULL, false);', 'break;'],
		'Asahi echoes both IOReport notifications independently of send status')!
	syslog := section(linux, 'static void apple_rtkit_syslog_rx_log(', 'static void apple_rtkit_syslog_rx(', 'Asahi Syslog receive')!
	require(syslog.contains('done:\n\tapple_rtkit_send_message(rtk, APPLE_RTKIT_EP_SYSLOG, msg, NULL, false);'),
		'Asahi echoes Syslog after the read attempt independently of send status')!

	ioreport_v := section(transport, '\n\t\tep_ioreport {', '\n\t\tep_syslog {', 'Vinix IOReport receive')!
	require_order(ioreport_v, ['if kind == 0x8 || kind == 0xc', 'return rtk.acknowledge_log(ep, msg.data0)'],
		'Vinix echoes both IOReport messages verbatim')!
	ack := section(transport, 'fn (mut rtk RTKit) acknowledge_log(', 'fn (rtk &RTKit) dump_syslog_entry(', 'Vinix RTKit acknowledgement')!
	require(ack.count('rtk.send_message(') == 1, 'Send one acknowledgement per notification')!
	require_order(ack, ['sent := rtk.send_message(ep, data)', 'if !sent && rtk.nonfatal_log_errors',
		'log acknowledgement timed out', 'return sent || rtk.nonfatal_log_errors'],
		'Vinix keeps G13 receiving after acknowledgement failure and preserves strict-client errors')!
}

fn check_rtkit_agx_coherency(asahi_linux string, repo string, linux string) ! {
	asahi := os.join_path(asahi_linux, 'drivers/gpu/drm/asahi')
	alloc := read(os.join_path(asahi, 'gpu.rs'))!.all_after('fn shmem_alloc(').all_before('#[versions(AGX)]')
	require_order(alloc, ['gem::new_kernel_object(dev, size)', 'owned_vmap::<0>()', 'map_into_range(',
		'IOVA_KERN_RTKIT_RANGE', 'mmu::PROT_FW_SHARED_RW', 'RtkitObject { vmap, mapping }'],
		'Asahi AGX uses a CPU GEM view and shared firmware UAT mapping for RTKit')!
	require(read(os.join_path(asahi, 'pgtable.rs'))!.contains('PROT_FW_SHARED_RW: Prot = PROT_FW_RW.memattr(MEMATTR_UNCACHED)'),
		'Asahi AGX RTKit UAT mapping is uncached')!
	require(read(os.join_path(asahi, 'gem.rs'))!.contains('new_kernel_object_mapped(dev, size, false)'),
		'Asahi uses a regular GEM CPU view for RTKit')!
	helper := read(os.join_path(asahi_linux, 'drivers/gpu/drm/drm_gem_shmem_helper.c'))!
	require_order(helper.all_after('int drm_gem_shmem_vmap_locked('),
		['pgprot_t prot = PAGE_KERNEL', 'if (shmem->map_wc)', 'prot = pgprot_writecombine(prot)', 'vmap(shmem->pages'],
		'Asahi shmem uses PAGE_KERNEL for regular GEM CPU views')!
	arm64 := read(os.join_path(asahi_linux, 'arch/arm64/include/asm/pgtable-prot.h'))!
	require_order(arm64, ['#define PROT_NORMAL\t', 'PTE_ATTRINDX(MT_NORMAL)', '#define _PAGE_KERNEL\t',
		'(PROT_NORMAL | PTE_DIRTY)', '#define PAGE_KERNEL\t', '__pgprot(_PAGE_KERNEL)'], 'Asahi PAGE_KERNEL uses Normal memory')!
	mair := read(os.join_path(asahi_linux, 'arch/arm64/mm/proc.S'))!
	sysreg := read(os.join_path(asahi_linux, 'arch/arm64/include/asm/sysreg.h'))!
	require(mair.contains('MAIR_ATTRIDX(MAIR_ATTR_NORMAL, MT_NORMAL)')
		&& sysreg.contains('#define MAIR_ATTR_NORMAL\t\tUL(0xff)'), 'Asahi uses write-back for MT_NORMAL')!
	mmu := read(os.join_path(asahi, 'mmu.rs'))!
	require(mmu.all_after('fn map_in_range_with_mode(').contains('crate::gem::held_sg_table(gem, dev)'),
		'Asahi kernel UAT mappings acquire the GEM scatter/gather table')!
	shmem := read(os.join_path(asahi_linux, 'rust/kernel/drm/gem/shmem.rs'))!
	require(shmem.contains('bindings::drm_gem_shmem_get_pages_sgt(self.as_raw_shmem())')
		&& helper.contains('dma_map_sgtable(obj->dev->dev, sgt, DMA_BIDIRECTIONAL, 0)'),
		'Asahi GEM setup maps backing for bidirectional DMA with synchronization enabled')!
	direct := read(os.join_path(asahi_linux, 'kernel/dma/direct.h'))!
	require_order(direct.all_after('static inline dma_addr_t dma_direct_map_phys('),
		['if (!dev_is_dma_coherent(dev)', 'DMA_ATTR_SKIP_CPU_SYNC', 'arch_sync_dma_for_device(phys, size, dir)'],
		'Asahi noncoherent DMA setup synchronizes pages for the device')!
	dma := read(os.join_path(asahi_linux, 'arch/arm64/mm/dma-mapping.c'))!
	require(dma.all_after('void arch_sync_dma_for_device(').all_before('void arch_sync_dma_for_cpu(')
		.contains('dcache_clean_poc_nosync(start, start + size)'), 'Asahi ARM64 DMA setup cleans backing to PoC')!
	rust := read(os.join_path(asahi_linux, 'rust/kernel/soc/apple/rtkit.rs'))!
	setup := section(rust, 'fn shmem_setup_callback', 'fn shmem_destroy_callback', 'Asahi RTKit GEM setup')!
	require(!setup.contains('needs_dma_sync') && linux.contains('struct apple_rtkit_shmem request = {};'),
		'Asahi AGX starts with the optional streaming DMA sync flag clear')!
	copy := section(linux, 'static void apple_rtkit_memcpy(', 'static void apple_rtkit_crashlog_rx(', 'Asahi RTKit shared copy')!
	require_order(copy, ['bool sync = bfr->needs_dma_sync', 'if (sync)', 'dma_sync_single_range_for_cpu',
		'memcpy(dst, bfr->buffer + offset, len)', 'if (sync)', 'dma_sync_single_range_for_device'],
		'Asahi only performs streaming DMA synchronization when opted in')!

	gpu := read(os.join_path(repo, 'kernel/gpu/agx/gpu/gpu.v'))!
	allocate := section(gpu, 'fn allocate_rtkit_shmem(', 'fn copy_rtkit_shmem(', 'Vinix RTKit setup')!
	require_order(allocate, ['alloc_buffer_from_heap(mut mgr.g13_rtkit, size, pgtable.gpu_prot_fw_shared_rw',
		'cpu.clean_invalidate_data_cache_to_poc(u64(buffer.cpu_address()), buffer.size)',
		'mgr.rtkit_buffers << buffer', 'return iova'], 'Vinix prepares the whole G13 RTKit allocation before publishing its address')!
	require_order(gpu.all_after('fn alloc_buffer_from_heap('),
		['memory.pmm_alloc_aligned_fallible', 'phys + higher_half', 'uat_mgr.map_kernel(va, phys, aligned_size, protection)'],
		'Vinix maps PMM backing used via the CPU direct map')!
	pgtable := read(os.join_path(repo, 'kernel/gpu/agx/pgtable/pgtable.v'))!
	require(pgtable.all_after('pub const gpu_prot_fw_shared_rw = ').all_before('\n').contains('uat_memattr_normal_uncached'),
		'Vinix G13 RTKit UAT mapping is uncached')!
	cpu := read(os.join_path(repo, 'kernel/memory/virtual_arm64.v'))!
	require(cpu.contains('arm64_pte_attr_normal = u64(0) << 2')
		&& cpu.contains('map_page(j + higher_half, j, pte_present | pte_noexec | pte_writable)')
		&& cpu.contains('mair := u64(0xFF)'), 'Vinix maps ARM64 high RAM with the Normal Write-Back attribute')!
	mailbox := read(os.join_path(repo, 'kernel/apple/mailbox/mailbox.v'))!
	receive := section(mailbox, 'pub fn (mut mbox Mailbox) recv()', 'pub fn (mut mbox Mailbox) recv_blocking(', 'Vinix RTKit mailbox')!
	require_order(receive, ['mbox.read_reg64(mbox_i2a_recv0)', 'mbox.read_reg64(mbox_i2a_recv1)', 'cpu.dmb_sy()', 'return MboxMsg{'],
		'Vinix orders shared-memory reads after the mailbox notification')!
}
