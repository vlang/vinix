// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import g13layout
import os
import strconv

pub fn require(condition bool, message string) ! {
	if !condition { return error(message) }
}

fn quoted(text string) string {
	quote := if text.contains("'") && !text.contains('"') { '"' } else { "'" }
	return quote + text.replace('\\', '\\\\').replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t').replace(quote, '\\' + quote) + quote
}

pub fn read(path string) !string {
	if !os.is_file(path) { return error('missing reference source: ${path}') }
	return os.read_file(path)
}

pub fn section(source string, start string, end string, label string) !string {
	begin := source.index(start) or { return error('${label}: missing ${quoted(start)}') }
	finish := source.index_after(end, begin + start.len) or { return error('${label}: missing terminator ${quoted(end)}') }
	return source[begin..finish]
}

pub fn require_order(source string, tokens []string, label string) ! {
	mut cursor := 0
	for token in tokens {
		found := source.index_after(token, cursor) or { return error('${label}: missing or out-of-order ${quoted(token)}') }
		cursor = found + token.len
	}
}

fn word(ch u8) bool { return ch.is_letter() || ch.is_digit() || ch == `_` }

pub fn integer_constant(source string, name string, label string) !u64 {
	mut position := 0
	for position < source.len {
		found := source.index_after(name, position) or { break }
		end := found + name.len
		position = end
		if (found > 0 && word(source[found - 1])) || (end < source.len && word(source[end])) {
			continue
		}
		equals := source.index_after('=', end) or { break }
		mut value := source[equals + 1..].trim_left(' \t\r\n')
		if value.starts_with('u64(') { value = value[4..].trim_left(' \t\r\n') }
		if !value.starts_with('0x') { continue }
		mut length := 2
		for length < value.len && (value[length].is_hex_digit() || value[length] == `_`) {
			length++
		}
		if length == 2 { continue }
		return strconv.parse_uint(value[2..length].replace('_', ''), 16, 64)!
	}
	return error('${label}: cannot find numeric constant ${name}')
}

pub fn git_revision(path string) string {
	mut process := os.new_process('git')
	process.set_args(['-C', path, 'rev-parse', '--short=12', 'HEAD'])
	process.set_redirect_stdio()
	process.run()
	output := process.stdout_slurp()
	process.wait()
	code := process.code
	process.close()
	return if code == 0 { output.trim_space() } else { 'unknown' }
}

pub fn check_m1n1(m1n1 string) ![]string {
	return check_m1n1_at(m1n1, g13layout.repo_root())
}

// The explicit repository argument lets regression fixtures test source drift
// without modifying the production tree or the upstream reference checkout.
pub fn check_m1n1_at(m1n1 string, repo string) ![]string {
	mut results := []string{}
	raw_rs := os.join_path(m1n1, 'rust/src/gpu/raw.rs')
	generated := g13layout.generate(raw_rs)!
	checked_in := read(os.join_path(repo, 'kernel/gpu/agx/fw/g13_initdata_layout.v'))!
	require(generated == checked_in, 'Vinix G13 InitData layout is stale against m1n1')!
	results << 'InitData 12.3/13.5 generated layouts'
	fw_channels := read(os.join_path(m1n1, 'proxyclient/m1n1/fw/agx/channels.py'))!
	normal_state := section(fw_channels, 'class ChannelStateFields', 'class FWControlStateFields', 'm1n1 channels')!
	require_order(normal_state, ['_SIZE = 0x30', 'READ_PTR = 0x00', 'WRITE_PTR = 0x20'], 'm1n1 normal channel state')!
	fwctl_state := section(fw_channels, 'class FWControlStateFields', 'class Channel(', 'm1n1 channels')!
	require_order(fwctl_state, ['_SIZE = 0x20', 'READ_PTR = 0x00', 'WRITE_PTR = 0x10'], 'm1n1 firmware-control channel state')!
	require(fw_channels.contains('[(FWCtlMsg, 0x14, 0x100)]'), 'm1n1 FwCtl ring ABI changed')!
	results << 'channel state offsets and FwCtl ring geometry'
	status_source := read(os.join_path(m1n1, 'proxyclient/m1n1/fw/agx/initdata.py'))!
	status := section(status_source, 'class InitData_FWStatus', 'class AGXHWDataShared1', 'm1n1 firmware status')!
	require_order(status, ['"fwctl_channel" / ChannelInfo', '"halt_count" / Int32ul', 'ZPadding(0xc)',
		'"halted" / Int32ul', 'ZPadding(0xc)', '"resume" / Int32ul', 'ZPadding(0xc)'], 'm1n1 firmware halt fields')!
	require(!status.contains('Ver('), 'm1n1 firmware halt layout is now version-dependent')!
	require(fw_channels.contains('"msg_type" / Hex(Const(8, Int32ul))'), 'm1n1 channel-error event tag changed')!
	results << 'G13 12.3/13.5 firmware halt fields and channel-error tag'
	runtime_channels := read(os.join_path(m1n1, 'proxyclient/m1n1/agx/channels.py'))!
	send_inval := section(runtime_channels, '    def send_inval(self, ctx, addr=0):', 'class GPUEventChannel', 'm1n1 FwCtl')!
	require_order(send_inval, ['msg.addr = addr', 'msg.unk_8 = 0', 'msg.context_id = ctx',
		'msg.unk_10 = 1', 'msg.unk_12 = 2', 'self.send_message(msg)'], 'm1n1 FwCtl invalidate')!
	vinix_channels := read(os.join_path(repo, 'kernel/gpu/agx/fw/channels.v'))!
	vinix_inval := section(vinix_channels, 'pub fn make_g13_fwctl_invalidate', '// Firmware log channel message', 'Vinix FwCtl')!
	require_order(vinix_inval, ['addr: addr', 'slot: slot', 'unk_10: 1', 'unk_12: 2'], 'Vinix FwCtl invalidate')!
	results << 'FwCtl invalidate opcode and handoff-slot message'
	m1n1_initdata := read(os.join_path(m1n1, 'proxyclient/m1n1/agx/initdata.py'))!
	require(m1n1_initdata.contains('initdata.regionA = agx.kshared.new_buf(0x4000, "InitData_RegionA")'), 'm1n1 RegionA allocation contract changed')!
	vinix_gpu := read(os.join_path(repo, 'kernel/gpu/agx/gpu/gpu.v'))!
	require(vinix_gpu.contains('graph.unknown_buffer = mgr.alloc_g13_shared_buffer(0x4000)'), 'Vinix RegionA is no longer firmware-writable shared memory')!
	results << 'firmware-writable InitData RegionA'
	m1n1_initdata_rs := read(os.join_path(m1n1, 'rust/src/gpu/initdata.rs'))!
	vinix_alloc := read(os.join_path(repo, 'kernel/gpu/agx/alloc/alloc.v'))!
	reference_timestamp := integer_constant(m1n1_initdata_rs, 'IOVA_KERN_TIMESTAMP_RANGE_START', 'm1n1 timestamp aperture')!
	vinix_timestamp := integer_constant(vinix_alloc, 'g13_timestamp_start', 'Vinix timestamp aperture')!
	require(reference_timestamp == vinix_timestamp, 'timestamp aperture mismatch: m1n1=0x${reference_timestamp:x}, Vinix=0x${vinix_timestamp:x}')!
	require(vinix_gpu.contains('mmu.uat_unknown_page, alloc.g13_timestamp_start'), 'Vinix no longer publishes the timestamp aperture to HwDataB')!
	results << 'timestamp aperture address and HwDataB publication'
	m1n1_objects := read(os.join_path(m1n1, 'proxyclient/m1n1/agx/object.py'))!
	allocator_start := m1n1_objects.index('class GPUAllocator') or { return error('m1n1 allocator: missing GPUAllocator') }
	allocator := m1n1_objects[allocator_start..]
	free_block := section(allocator, '    def free(self, obj):', '        if self.verbose:', 'm1n1 free')!
	require_order(free_block, ['flags2["AttrIndex"] = MemoryAttr.Shared', 'self.agx.uat.iomap_at',
		'self.agx.uat.flush_dirty()', 'prepare_cacheflush', 'send_inval', 'wait_cacheflush', 'VALID=0',
		'self.agx.uat.flush_dirty()', 'complete_cacheflush'], 'm1n1 cache-safe unmap')!
	vinix_shared := section(vinix_gpu, 'fn (mut mgr GpuManager) invalidate_g13_shared_buffer', 'fn (mut mgr GpuManager) invalidate_g13_driver_buffer', 'Vinix shared-buffer teardown')!
	require_order(vinix_shared, ['reprotect_kernel', 'flush_g13_uat_range',
		'cache_flush_pending = false', 'unmap_shared_buffer', 'flush_g13_uat_range'], 'Vinix shared-buffer teardown')!
	vinix_driver := section(vinix_gpu, 'fn (mut mgr GpuManager) invalidate_g13_driver_buffer', 'fn (mut mgr GpuManager) release_shared_buffer_backing', 'Vinix driver-buffer teardown')!
	require_order(vinix_driver, ['reprotect_driver_buffer_uncached', 'flush_g13_uat_range',
		'complete_driver_buffer_cache_flush', 'unmap_driver_buffer', 'flush_g13_uat_range'], 'Vinix driver-buffer teardown')!
	results << 'retry-safe reprotect/invalidate/unmap/invalidate teardown'
	vinix_channel := read(os.join_path(repo, 'kernel/gpu/agx/channel/channel.v'))!
	enqueue := section(vinix_channel, 'pub fn (mut ch TxChannel) enqueue_with_token', 'pub fn (ch &TxChannel) read_pointer', 'Vinix TX channel')!
	require_order(enqueue, ['C.memcpy', 'katomic.sync()', 'katomic.store(mut write_ptr'], 'Vinix TX channel publication')!
	results << 'TX ring entry barrier before write-pointer publication'
	vinix_jobs := read(os.join_path(repo, 'kernel/gpu/agx/gpu/g13.v'))!
	batch := section(vinix_jobs, 'fn (mut mgr GpuManager) submit_g13_queue_commands(', 'fn (mut mgr GpuManager) submit_g13_queue_command(', 'Vinix batched G13 publisher')!
	require_order(batch, ['*entry = command_va', 'katomic.sync()', 'katomic.store(mut &state.cpu_wptr',
		'C.memcpy(destination', 'katomic.sync()', 'katomic.store(mut outer_write'], 'Vinix batched G13 publication')!
	render := section(vinix_jobs, 'fn (mut mgr GpuManager) publish_g13_render_job_locked(', '// Transfer a prepared render pass', 'Vinix paired G13 publisher')!
	require_order(render, ['*vertex_entry_1 = job.vertex.va', 'katomic.sync()',
		'katomic.store(mut &fragment_state.cpu_wptr', 'C.memcpy(vertex_destination',
		'katomic.sync()', 'katomic.store(mut fragment_outer_write'], 'Vinix paired G13 publication')!
	results << 'batched compute/render entry barriers before inner and outer pointer publication'
	return results
}

pub fn check_asahi(asahi_linux string) ![]string {
	mmu := read(os.join_path(asahi_linux, 'drivers/gpu/drm/asahi/mmu.rs'))!
	drop := section(mmu, 'impl Drop for KernelMapping', '/// Shared UAT global', 'Asahi MMU')!
	require_order(drop, ['is_cached_noncoherent', 'remap_uncached_and_flush', 'unmap_pages',
		'tlbi_range'], 'Asahi cache-safe unmap')!
	channel := read(os.join_path(asahi_linux, 'drivers/gpu/drm/asahi/channel.rs'))!
	put := section(channel, '    pub(crate) fn put', '    /// Wait for', 'Asahi TX channel')!
	require_order(put, ['self.ring.ring[self.wptr as usize] = *msg', 'mem::sync()', 'T::set_wptr'], 'Asahi TX channel publication')!
	return ['Asahi KernelMapping cache-safe teardown order',
		'Asahi TX ring barrier before write-pointer publication']
}

// Omarchy ships the Asahi driver in linux-aurora. FWCTL cache maintenance
// does not replace these CPU-side outer-shareable GPU TLB broadcasts.
pub fn check_tlb_reference(asahi_linux string, repo string) ![]string {
	reference := read(os.join_path(asahi_linux, 'drivers/gpu/drm/asahi/mem.rs'))!
	vinix := read(os.join_path(repo, 'kernel/gpu/agx/tlb/tlb.v'))!
	check_tlb_instructions(reference, vinix)!
	mmu := read(os.join_path(asahi_linux, 'drivers/gpu/drm/asahi/mmu.rs'))!
	bind := section(mmu, '    pub(crate) fn bind(&self, vm:', 'binding.bind_token = Some(slot.token());', 'Asahi UAT bind')!
	require_order(bind, ['ttbs[idx].ttb0.store(ttb,', 'ttbs[idx].ttb1.store(ttb1,',
		'mem::tlbi_asid(idx as u8)', 'mem::sync()'], 'Asahi ASID reuse invalidation')!
	drop_start := mmu.index('impl Drop for VmInner') or { return error('Asahi UAT: missing VM teardown') }
	require_order(mmu[drop_start..], ['.ttb0.store(0,', '.ttb1.store(0,',
		'mem::tlbi_asid(idx as u8)', 'mem::sync()'], 'Asahi ASID teardown invalidation')!
	local := read(os.join_path(repo, 'kernel/gpu/agx/mmu/mmu.v'))!
	local_bind := section(local, 'pub fn (mgr &UatManager) bind_context(', 'pub fn (mgr &UatManager) unbind_context(', 'Vinix UAT bind')!
	require_order(local_bind, ['slots[ctx.id].ttb0 =', 'slots[ctx.id].ttb1 =',
		'handoff_unlock(mgr.handoff)', 'pt.bind_tlb(u8(ctx.id))'], 'Vinix ASID reuse invalidation')!
	local_unbind := section(local, 'pub fn (mgr &UatManager) unbind_context(', '// Map a driver-owned allocation into context zero.', 'Vinix UAT unbind')!
	require_order(local_unbind, ['slots[ctx.id].ttb0 = 0', 'slots[ctx.id].ttb1 = 0',
		'handoff_unlock(mgr.handoff)', 'pt.unbind_tlb()'], 'Vinix ASID teardown invalidation')!
	return ['outer-shareable GPU TLBI instructions and completion barriers',
		'ASID invalidation after root publication and removal']
}

fn check_tlb_instructions(reference string, vinix string) ! {
	all := section(reference, 'pub(crate) fn tlbi_all()', '/// Invalidate all TLB entries', 'Asahi GPU TLBI')!
	require(all.contains('tlbi vmalle1os'), 'Asahi global GPU TLBI instruction changed')!
	asid := section(reference, 'pub(crate) fn tlbi_asid(', '/// Invalidate a single page', 'Asahi GPU TLBI')!
	require(asid.contains('tlbi aside1os') && asid.contains('<< 48'), 'Asahi GPU ASID encoding changed')!
	local_all := section(vinix, 'pub fn invalidate_all()', 'pub fn invalidate_asid(', 'Vinix GPU TLBI')!
	require_order(local_all, ['dsb sy', 'tlbi vmalle1os', 'dsb sy', 'memory'], 'Vinix global GPU TLBI')!
	local_asid_start := vinix.index('pub fn invalidate_asid(') or { return error('Vinix GPU TLBI: missing ASID invalidation') }
	local_asid_end := vinix.index_after('pub fn invalidate_range(', local_asid_start) or { vinix.len }
	require_order(vinix[local_asid_start..local_asid_end], ['u64(asid) << 48', 'dsb sy', 'tlbi aside1os, operand',
		'dsb sy', 'memory'], 'Vinix ASID GPU TLBI')!
}

pub fn check_queue_recovery_reference(asahi_linux string, repo string) ![]string {
	base := os.join_path(asahi_linux, 'drivers/gpu/drm/asahi')
	manager := read(os.join_path(base, 'gpu.rs'))!
	workqueue := read(os.join_path(base, 'workqueue.rs'))!
	require_order(workqueue, ['let last_wptr = inner.pending[completed_commands - 1].inner.wptr()',
		'raw.cpu_freeptr.store(last_wptr, Ordering::Release)'], 'Asahi workqueue retirement')!
	recover := section(manager, '    fn recover(&self)', '    /// Return the packed GPU', 'Asahi recovery')!
	require_order(recover, ['raw.flags.halted.store(0, Ordering::SeqCst)',
		'raw.flags.resume.store(1, Ordering::SeqCst)'], 'Asahi halt/resume handshake')!
	ack := section(manager, '    fn ack_grow(&self, buffer_slot: u32, vm_slot: u32, counter: u32) {',
		'    fn fwctl(', 'Asahi TVB growth')!
	require_order(ack, ['raw.flags.halt_count.load', 'DeviceControlMsg::ver::GrowTVBAck',
		'halt_count: U64(halt_count)'], 'Asahi TVB halt counter')!
	local := read(os.join_path(repo, 'kernel/gpu/agx/gpu/g13.v'))!
	retirement := section(local, 'fn (mut mgr GpuManager) retire_g13_subqueue_locked(',
		'fn build_g13_attachments(', 'Vinix workqueue retirement')!
	require_order(retirement, ['sequence <= queue.retired_sequence', 'katomic.sync()',
		'katomic.store(mut &state.cpu_freeptr, slot)', 'queue.retired_sequence = sequence'],
		'Vinix workqueue retirement')!
	local_recovery := read(os.join_path(repo, 'kernel/gpu/agx/gpu/g13_recovery.v'))!
	require_order(local_recovery, ['fw.g13_pending_stamp_count', 'mgr.mark_g13_slot_error_locked',
		'katomic.store(mut &pending[index].info', 'katomic.load(&status.halted)',
		'katomic.store(mut &status.halted, u32(0))', 'katomic.sync()',
		'katomic.store(mut &status.resume, u32(1))'], 'Vinix recoverable fault protocol')!
	channels := read(os.join_path(base, 'fw/channels.rs'))!
	require_order(channels, ['GrowTVBAck {', 'subpipe: u32', 'halt_count: U64'], 'Asahi GrowTVBAck layout')!
	return ['host workqueue retirement pointer and wrap-safe publication',
		'pending-stamp fault classification and halt/resume handshake',
		'TVB growth ACK halt counter']
}

pub fn check_tvb_reference(asahi_linux string, repo string) ![]string {
	base := os.join_path(asahi_linux, 'drivers/gpu/drm/asahi')
	reference := read(os.join_path(base, 'buffer.rs'))!
	policy := section(reference, '    pub(crate) fn auto_grow(', '    /// Synchronously grow', 'Asahi TVB feedback')!
	require_order(policy, ['raw.max_pages.load', 'raw.reset.store(1, Ordering::Release)',
		'used_pages * 2', '.div_ceil(PAGES_PER_BLOCK)', '.min(inner.max_blocks_nomemless)',
		'used_pages * 3', '.div_ceil(PAGES_PER_BLOCK)', '.min(inner.max_blocks_nomemless)',
		'need_blocks <= cur_count', 'self.ensure_blocks(want_blocks)'], 'Asahi TVB feedback')!
	local := read(os.join_path(repo, 'kernel/gpu/agx/gpu/g13.v'))!
	local_policy := section(local, 'fn (mut mgr GpuManager) auto_grow_g13_tvb_locked(', '// Service firmware', 'Vinix TVB feedback')!
	require_order(local_policy, ['katomic.load(&stats.max_pages)', 'katomic.store(mut &stats.reset, u32(1))',
		'u64(g13_tvb_max_blocks_nomemless)', 'used_pages * 2', 'needed < limit',
		'need_blocks <= u64(buffer.blocks.len)', 'used_pages * 3', 'wanted < limit',
		'mgr.ensure_g13_tvb_blocks(mut buffer, u32(want_blocks), buffer.active_scenes != 0)'], 'Vinix TVB feedback')!
	scene := section(local, 'fn (mut mgr GpuManager) allocate_g13_render_scene_locked(', 'fn (mut mgr GpuManager) free_g13_render_job_locked(', 'Vinix scene allocation')!
	require_order(scene, ['mgr.auto_grow_g13_tvb_locked(mut buffer)',
		'mgr.ensure_g13_tvb_blocks(mut buffer, tile.min_tvb_blocks, buffer.active_scenes != 0)',
		'scene.user_buffer ='], 'Vinix TVB feedback before scene allocation')!
	growth := section(reference, '    pub(crate) fn ensure_blocks(', '    /// Create a new', 'Asahi TVB extension')!
	require_order(growth, ['let mut new_blocks', 'ualloc.array_gpuonly(BLOCK_SIZE)',
		'inner.blocks.reserve', 'new_blocks.into_iter()', 'raw.total.store',
		'raw.wptr.store', 'if inner.active_scenes == 0'], 'Asahi staged TVB extension')!
	local_growth := section(local, 'fn (mut mgr GpuManager) ensure_g13_tvb_blocks(', '// Asahi Buffer::auto_grow', 'Vinix TVB extension')!
	require_order(local_growth, ['memory.malloc_packed_fallible', 'for u32(staged.len)',
		'staged << block', 'mgr.flush_g13_uat_range', 'for index := u32(old_count)',
		'buffer.blocks = staged', 'katomic.store(mut &control.total',
		'katomic.store(mut &control.wptr', 'if !firmware_active'], 'Vinix staged TVB extension')!
	reference_scene := section(reference, '    pub(crate) fn new_scene(', '    /// Increment the buffer', 'Asahi scene lifetime')!
	require_order(reference_scene, ['if inner.active_slot.is_none()', 'inner.active_slot = Some(slot)',
		'inner.active_scenes += 1'], 'Asahi scene slot retention')!
	drop_scene := section(reference, 'impl Drop for Scene::ver', '/// Inner data for a single TVB', 'Asahi scene release')!
	require_order(drop_scene, ['inner.active_scenes -= 1', 'if inner.active_scenes == 0',
		'inner.active_slot = None'], 'Asahi last-scene slot release')!
	local_scene := section(local, 'fn (mut mgr GpuManager) retain_g13_scene_slot_locked(', '// Caller holds mgr.lock. No submitted job', 'Vinix scene lifetime')!
	require_order(local_scene, ['if buffer.active_scenes == 0', 'mgr.reserve_g13_tvb_slot()',
		'buffer.active_scenes++', 'buffer.active_scenes--', 'if buffer.active_scenes == 0',
		'mgr.g13_tvb_slots[buffer.slot] = false'], 'Vinix scene slot retention and release')!
	slots := read(os.join_path(base, 'slotalloc.rs'))!
	require_order(slots, ['if count == token.time', 'changed: false',
		'if slot.drop_time < oldest_time'], 'Asahi unchanged-token and oldest-free policy')!
	require_order(local_scene, ['mgr.g13_tvb_owners[buffer.slot] == buffer.info.va',
		'mgr.reserve_g13_tvb_slot()'], 'Vinix unchanged-token preference')!
	selection := section(local, 'fn (mut mgr GpuManager) reserve_g13_tvb_slot()', '// Caller holds mgr.lock. Buffer::new_scene', 'Vinix oldest-free policy')!
	require_order(selection, ['mgr.g13_tvb_release_clock - mgr.g13_tvb_free_order[slot]',
		'age > oldest_age', 'mgr.g13_tvb_slots[selected] = true'], 'Vinix oldest-free selection')!
	require_order(scene, ['fw.initialize_g13_buffer_scene',
		'mgr.retain_g13_scene_slot_locked(mut buffer)', 'complete = true'], 'Vinix scene lease after allocation')!
	require_order(reference_scene, ['let tpc = match inner.tpc.as_ref()',
		'Some(buf) if buf.len() >= tpc_size => buf.clone()',
		'(tpc_size + mmu::UAT_PGMSK) & !mmu::UAT_PGMSK',
		'inner.tpc = Some(buf.clone())'], 'Asahi shared tail-pointer cache')!
	tpc := read(os.join_path(repo, 'kernel/gpu/agx/gpu/g13_tpc.v'))!
	require_order(tpc, ['!old.retiring && old.buffer.size >= size', 'cached.references++',
		'memory.malloc_packed_fallible', 'context.alloc_driver_buffer_aligned(size, true, pgtable.uat_pgsz)',
		'mgr.invalidate_g13_tpc_locked(mut context, old)', 'owner.tail_pointer_cache = next',
		'mgr.release_g13_tpc_locked(mut context, old)', 'next.references++'], 'Vinix shared tail-pointer cache')!
	render := read(os.join_path(base, 'queue/render.rs'))!
	require_order(render, ['if scene.rebind() || tvb_grown || tvb_autogrown',
		'vtx_job.add(bind_buffer'], 'Asahi conditional TVB binding')!
	publisher := section(local, 'fn (mut mgr GpuManager) publish_g13_render_job_locked(', '// Transfer a prepared render pass', 'Vinix conditional TVB binding')!
	require_order(publisher, ['include_init :=', 'vertex_count :=', 'if include_init',
		'katomic.store(mut &vertex_state.cpu_wptr', 'owned_queue.render_buffer.needs_bind = false'], 'Vinix conditional TVB binding')!
	return ['TVB page-use feedback, two/three-times headroom and non-memoryless cap',
		'TVB feedback before minimum-dimension growth and scene allocation',
		'TVB complete allocation before table and counter publication',
		'TVB slot retained across active scenes and released by the final scene',
		'TVB unchanged-token preference and oldest-free selection',
		'TVB tail-pointer cache reuse and retained scene ownership on growth',
		'TVB binding on slot acquisition or heap growth']
}
