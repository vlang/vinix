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
		if value.starts_with('u64(') || value.starts_with('u32(') { value = value[4..].trim_left(' \t\r\n') }
		hexadecimal := value.starts_with('0x')
		start := if hexadecimal { 2 } else { 0 }
		mut length := start
		for length < value.len && ((if hexadecimal { value[length].is_hex_digit() } else { value[length].is_digit() }) || value[length] == `_`) {
			length++
		}
		if length == start { continue }
		return strconv.parse_uint(value[start..length].replace('_', ''), if hexadecimal { 16 } else { 10 }, 64)!
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
		'*destination = fw.FwRunWorkQueueMsg', 'katomic.sync()', 'katomic.store(mut outer_write'], 'Vinix batched G13 publication')!
	render := section(vinix_jobs, 'fn (mut mgr GpuManager) publish_g13_render_job_locked(', '// Transfer a prepared render pass', 'Vinix paired G13 publisher')!
	require_order(render, ['*vertex_entry_1 = job.vertex.va', 'katomic.sync()',
		'katomic.store(mut &fragment_state.cpu_wptr', '*vertex_destination = fw.FwRunWorkQueueMsg',
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
	check_vm_geometry_local(read(os.join_path(repo, 'kernel/gpu/agx/vm/vm.v'))!,
		read(os.join_path(repo, 'kernel/gpu/agx/mmu/mmu.v'))!)!
	check_vm_geometry_reference(read(os.join_path(asahi_linux, 'drivers/gpu/drm/asahi/file.rs'))!,
		read(os.join_path(asahi_linux, 'drivers/gpu/drm/asahi/buffer.rs'))!,
		read(os.join_path(asahi_linux, 'drivers/gpu/drm/asahi/alloc.rs'))!)!
	check_gpu_permission_contract(read(os.join_path(repo, 'kernel/gpu/agx/pgtable/pgtable.v'))!,
		read(os.join_path(repo, 'kernel/gpu/agx/file/file.v'))!,
		read(os.join_path(asahi_linux, 'drivers/gpu/drm/asahi/pgtable.rs'))!,
		read(os.join_path(asahi_linux, 'drivers/gpu/drm/asahi/file.rs'))!)!
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
		'32 KiB native driver window normalization, heap split and minimum allocation alignment',
		'ASID invalidation after root publication and removal',
		'Distinct GPU-only coherent RO/WO/RW bind permissions and Asahi UAT selectors']
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

fn check_dependency_publication(poll string) ! {
	require_order(poll, ['failure := g13_pending_error(item)', 'if !item.admitted',
		'if !manager.g13_queue_dispatch_blocked(item.queue) { submit_g13_pending(mut manager, mut item) }',
		'completed_error := g13_pending_error(item)', 'cancel_g13_pending(mut item, completed_error)'], 'Vinix firmware batch scheduling')!
	require(!poll.contains('.done') && !poll.contains('command.wait_for'),
		'Vinix must publish installed firmware dependencies together without CPU callback waits')!
	require_order(poll, ['if katomic.load(&item.callbacks_remaining) != 0 { return true }',
		'if manager.state != .running { cancel_g13_pending(mut item, -19) }',
		'final_error := g13_pending_error(item)'], 'Vinix shutdown after callback acquisition')!
}

fn check_initial_snapshot_contract(initial string, barriers string, workqueue string, manager string) ! {
	init := initial.fields().join(' ')
	require_order(init, ['accept_g13_submission_locked', 'count > 64',
		'voidptr(queue) != voidptr(owner)',
		'owner.subqueues[0].events.ticket', 'owner.subqueues[physical].events.ticket',
		'queue.initial_events[pipe] = last[pipe]', 'capture_g13_initial_events',
		'!mgr.g13_events.initialized', 'mask & (u32(1) << pipe)',
		'voidptr(last.queue) != voidptr(queue)', 'last.pipe != u32(pipe)', 'owns_slot(last.ticket.slot)', 'event.retain_stamp(last.ticket.slot)',
		'event.release_stamp(prior.ticket.slot)', 'release_g13_initial_events',
		'value.valid && mgr.g13_events.initialized', 'value = G13InitialEvent{}'], 'Vinix initial snapshot ownership')!
	require_order(workqueue, ['serial := queue.serial', 'queue.serial++', 'serial: serial',
		'resolve_initial(captured Ticket)', 'stamp_value_completed', '!queue.owns_slot(captured.slot)',
		'i64(entry.serial - captured.serial) > 0', 'if !entry.published', 'InitialState.absent'], 'Vinix stable initial identity')!
	require(!workqueue.contains('queue.serial--'), 'Canceled tickets must not reuse their host identity')!
	resolution := section(barriers, 'fn (mut mgr GpuManager) resolve_g13_initial_barriers_locked(',
		'pub fn (mut mgr GpuManager) set_g13_compute_barriers(', 'Vinix initial resolution')!
	require_order(resolution, ['barriers.pin_count', 'barriers.waits[index]', 'events.resolve_initial',
		'state == .pending', 'state == .absent', 'write_g13_barrier', 'mgr.flush_g13_kernel_buffer',
		'barriers.count = count', 'barriers.initial_pending = false'], 'Vinix initial resolution')!
	require(barriers.all_after('fn release_g13_barrier_pins(').contains('index < barriers.pin_count'),
		'Omitted/compacted initial records must keep every physical pin until graph cleanup')!
	registration := section(manager, 'pub fn (mut mgr GpuManager) queue_g13_submission(', '__global (', 'Vinix initial acceptance')!
	require_order(registration, ['mgr.lock.acquire()', 'mgr.state != .running',
		'mgr.accept_g13_submission_locked(jobs, count)', 'enqueue(data)'], 'Vinix atomic initial acceptance')!
}

fn check_input_dependency_contract(pending string) ! {
	ready := section(pending, 'fn g13_dependencies_ready(', 'fn cancel_g13_pending(', 'Vinix input dependency readiness')!
	require_order(ready, ['index < dependencies.count', '!syncobj.queue_dependency_ready(dependencies.item(index).fence, queue_context)',
		'return false', 'return true'], 'Vinix input dependency readiness')!
	require(!ready.contains('get_error'), 'Signaled input fence errors must not cancel the dependent submission')!
	poll := section(pending, 'fn poll_g13_pending(', 'if !item.admitted', 'Vinix input dependency scheduling')!
	require_order(poll, ['if !item.dependencies_ready', 'if !g13_dependencies_ready(&item.dependencies, item.queue.fence_context) { return true }',
		'item.dependencies_ready = true', 'failure := g13_pending_error(item)',
		'cancel_g13_pending(mut item, if failure != 0'], 'Vinix input dependency scheduling')!
}

fn check_queue_fence_contract(contexts string, fences string, queue string, submit string) ! {
	require_order(contexts.fields().join(' '), ['next u64 = 1', 'fn (mut contexts QueueFenceContexts) allocate()',
		'if contexts.next == 0 { return none }', 'value := contexts.next',
		'contexts.next = if value == ~u64(0) { u64(0) } else { value + 1 }',
		'pub fn new_queue_context()', 'queue_context_lock.acquire()', 'defer { queue_context_lock.release() }',
		'return queue_contexts.allocate()', 'pub fn new_queue_fence(', 'queue_context: queue_context',
		'pub fn queue_dependency_ready(', 'queue_context != 0 && fence.queue_context == queue_context',
		'return is_signaled(fence)'], 'Vinix private queue fence identity')!
	fields := section(fences, 'pub struct DmaFence {', 'pub mut:', 'Vinix immutable fence provenance')!
	require(fields.contains('queue_context u64') && !fields.contains('&'), 'Queue fence provenance must be a private immutable scalar')!
	create := section(queue, 'pub fn (mut mgr GpuManager) create_g13_queue_resources(',
		'mut complete := false', 'Vinix queue fence context')!
	require_order(create, ['mgr.state != .running', 'syncobj.new_queue_context() or { return none }',
		'&G13QueueResources{', 'fence_context: fence_context'], 'Vinix queue fence context')!
	require(submit.contains('syncobj.new_queue_fence(f.owner_key, timer.get_ns(), queue_resources.fence_context)'),
		'Native output fences must carry the exact physical queue context')!
}

fn check_event_admission_contract(local string, reference string) ! {
	require_order(reference, ['const MAX_JOB_SLOTS: u32 = 127', 'pub(crate) fn can_submit(',
		'inner.free_slots() > self.event_count', 'pub(crate) fn free_slots(', 'self.last_submitted',
		'.last_completed', 'ls.delta(&lc)', '((MAX_JOB_SLOTS as i32) - busy_slots).max(0)'], 'Asahi host event admission')!
	retain := section(local, 'pub fn (mut queue WorkQueueEvents) retain(', 'pub enum InitialState', 'Vinix event baseline')!
	require_order(retain, ['value := advance_stamp', 'if queue.users == 0 {',
		'queue.completed_value = value - u32(0x100)', 'queue.published_value = queue.completed_value',
		'queue.users++'], 'Vinix event baseline')!
	release := section(local, 'pub fn (mut queue WorkQueueEvents) release(', 'pub fn (queue &WorkQueueEvents) busy()', 'Vinix event retirement')!
	require_order(release, ['if ticket.published != submitted',
		'if submitted && i32(value - queue.completed_value) > 0 { queue.completed_value = value }',
		'ticket.active = false', 'queue.users--'], 'Vinix monotonic host event completion')!
	credit := section(local, 'pub fn (mut queue WorkQueueEvents) record_completion(',
		'pub fn (mut queue WorkQueueEvents) release(', 'Retained event completion credit')!
	require_order(credit, ['if !queue.owns_slot(slot)', 'mut block := unsafe { &queue.tickets }',
		'for block != unsafe { nil }', 'for ticket in block.entries',
		'ticket.active && ticket.value == value && ticket.published',
		'if i32(value - queue.completed_value) > 0 { queue.completed_value = value }',
		'return true', 'block = block.next', 'return false'], 'Only retained published completions return monotonic credit')!
	for token in ['queue.users--', 'ticket.active = false', 'memory.free(', 'release_stamp(',
		'block.next =', 'queue.published_value =', 'queue.sequence', 'queue.serial', 'ticket.admitted'] {
		require(!credit.contains(token), 'Recording completion must preserve owner state: ' + token)!
	}
	capacity := section(local, 'pub fn (queue &WorkQueueEvents) can_submit(', '// Call only after the ring publication', 'Vinix event publication')!
	require_order(capacity, ['queue.users == 0', 'i32(queue.published_value - queue.completed_value) >> 8',
		'if busy >= 127 { i32(0) } else { i32(127) - busy }', 'return u32(free_slots) > count',
		'pub fn (mut queue WorkQueueEvents) admit(', '!queue.owns_slot(slot)',
		'ticket.active && ticket.value == value && !ticket.published', 'ticket.admitted = true',
		'pub fn (queue &WorkQueueEvents) can_publish(', 'queue.slot != slot',
		'for ticket in block.entries', 'ticket.published', 'admitted = ticket.admitted',
		'return found && (admitted || queue.can_submit(1))'], 'Vinix event publication spare')!
	require(!capacity.contains('stamp_value_completed') && !capacity.contains('gpu_event_mgr'), 'Raw GPU progress must not grant host event capacity')!
	publish := local.all_after('pub fn (mut queue WorkQueueEvents) publish(')
	require_order(publish, ['queue.can_publish(slot, value)', 'ticket.published = true',
		'ticket.admitted = false', 'queue.published_value = value'], 'Vinix successful event publication')!
	batch := section(local, 'pub fn (queue &WorkQueueEvents) can_publish_batch(', '// Asahi rejects out-of-order', 'Vinix complete event FIFO')!
	require_order(batch, ['count == 0 || count > 64 || !queue.owns_slot(slot)',
		'i32(values[index] - values[index - 1]) <= 0', 'ticket.active && ticket.value == values[index] && ticket.admitted && !ticket.published',
		'if !found { return false }', 'i32(ticket.value - values[count - 1]) > 0',
		'ticket.value == values[index]', 'if !included { return false }'], 'Vinix complete event FIFO')!
}

fn check_prepared_backlog_contract(local string, reference string) ! {
	new_job := section(reference, 'pub(crate) fn new_job(', 'pub(crate) fn pipe_type(', 'Asahi prepared job ownership')!
	require_order(new_job, ['inner.pending_jobs += 1', 'pending: KVec::new()', 'event_count: 0'], 'Asahi prepared job ownership')!
	require(!new_job.contains('MAX_JOB_SLOTS') && !new_job.contains('free_slots()'), 'Asahi preparation must not charge hardware event credit')!
	retain := section(local, 'pub fn (mut queue WorkQueueEvents) retain(', 'pub enum InitialState', 'Vinix prepared backlog')!
	require(!retain.contains('queue.users >= 127') && !retain.contains('128 * 0x100'), 'Prepared backlog must not be capped by the hardware publication window')!
	require_order(retain, ['value := advance_stamp', 'value - queue.completed_value >= u32(0x80000000)',
		'mut block := unsafe { &queue.tickets }', 'for block != unsafe { nil }',
		'for index, ticket in block.entries', 'value - ticket.value >= u32(0x80000000)',
		'block = block.next', 'if target == unsafe { nil }',
		'memory.malloc_packed_fallible(sizeof(TicketBlock))', 'if target == unsafe { nil }',
		'gpu_event_mgr.cancel_value(queue.slot, value)', 'return none', 'tail.next = target',
		'queue.sequence++', 'queue.serial++', 'target.entries[vacant] = PendingTicket{',
		'target.users++', 'queue.users++'], 'Vinix owned overflow allocation and rollback')!
	release := section(local, 'pub fn (mut queue WorkQueueEvents) release(', 'pub fn (queue &WorkQueueEvents) busy()', 'Vinix overflow retirement')!
	require_order(release, ['ticket.published != submitted', 'ticket.active = false',
		'block.users--', 'queue.users--', 'previous != unsafe { nil } && block.users == 0',
		'previous.next = block.next', 'memory.free(block)', 'queue.users == 0', 'release_stamp(queue.slot)', 'return true'], 'Vinix unlink-before-free overflow retirement')!
	for name in ['ticket(', 'resolve_initial(', 'admit(', 'can_publish_batch(', 'can_publish(', 'publish(', 'record_completion('] {
		start := local.index(') ' + name) or { return error('missing backlog traversal ' + name) }
		body := local[start..].all_before('\npub fn ')
		require(body.contains('block.entries') && body.contains('block = block.next'), 'Every ticket operation must visit overflow blocks: ' + name)!
	}
}

fn check_batch_admission_contract(local string, pending string, reference string) ! {
	require_order(reference, ['fn prepare(', 'sj_vtx', 'can_submit()', 'sj_frag', 'can_submit()',
		'sj_comp', 'can_submit()'], 'Asahi whole-batch readiness')!
	require_order(local, ['mgr.lock.acquire()', 'defer { mgr.lock.release() }',
		'count == 0 || count > 64', 'mut events := [3]u32{}', 'mut commands := [3]u32{}',
		'index < count', 'voidptr(queue) != voidptr(owner)',
		'.events.ticket(job.event_slot, job.stamp_value)', 'resolve_g13_initial_barriers_locked',
		'events[2]++', 'commands[2] += 1 + job.explicit_barriers.count',
		'.events.ticket(job.vertex_event_slot, job.vertex_stamp_value)',
		'.events.ticket(job.fragment_event_slot, job.fragment_stamp_value)',
		'resolve_g13_initial_barriers_locked', 'block_count := u32(job.tvb_size_bytes / fw.g13_tvb_block_size)',
		'include_init := needs_bind || bound_blocks < block_count',
		'commands[0] += job.explicit_barriers.count + if include_init { u32(2) } else { u32(1) }',
		'commands[1] += 2', 'events[0]++', 'events[1]++', 'needs_bind = false', 'bound_blocks = block_count',
		'for pipe in 0 .. 3', 'events[pipe] == 0', '.events.can_submit(events[pipe])',
		'g13_ring_has_space_locked(queue.subqueues[pipe].command_sequence,',
		'queue.subqueues[pipe].retired_sequence, commands[pipe])',
		'for index := u32(0); index < count; index++',
		'.events.admit(source.compute.event_slot, source.compute.stamp_value)',
		'.events.admit(source.render.vertex_event_slot, source.render.vertex_stamp_value)',
		'.events.admit(source.render.fragment_event_slot, source.render.fragment_stamp_value)'], 'Vinix whole-batch readiness')!
	for mutation in ['.submitted =', '.events.publish(', '.command_sequence +=', '.render_buffer.needs_bind =',
		'.render_buffer.bound_blocks ='] {
		require(!local.contains(mutation), 'Batch preflight must not publish or change live binding: ' + mutation)!
	}
	helper := section(pending, 'fn admit_g13_pending(', '// Called under manager.lock', 'Vinix borrowed batch references')!
	require_order(helper, ['mut jobs := [64]gpu.G13SubmissionJob{}', 'index < item.command_count',
		'manager.g13_batch_ready(jobs, item.command_count)'], 'Vinix borrowed batch references')!
	poll := section(pending, 'fn poll_g13_pending(', '// Only the worker changes these pointers.', 'Vinix batch admission scheduling')!
	require_order(poll, ['g13_dependencies_ready(', 'failure := g13_pending_error(item)', 'if !item.admitted',
		'if !admit_g13_pending(mut manager, item)', '_ = katomic.load(&item.callbacks_remaining)',
		'if manager.state != .running', 'cancel_g13_pending(mut item, -19)',
		'item.admitted = true', 'submit_g13_pending(mut manager, mut item)'], 'Vinix batch admission scheduling')!
}

fn check_batch_publication_contract(local string, pending string, reference string) ! {
	require_order(reference, ['frag_sub = Some(wqjob.submit()?)', 'vtx_sub = Some(wqjob.submit()?)',
		'comp_sub = Some(wqjob.submit()?)', 'raw.increase(job.notification_count)',
		'frag_sub.map(|a| gpu.run_job(a))', 'vtx_sub.map(|a| gpu.run_job(a))',
		'comp_sub.map(|a| gpu.run_job(a))'], 'Asahi fallible preparation before publication')!
	require_order(local, ['mgr.lock.acquire()', 'defer { mgr.lock.release() }',
		'admit_g13_batch_locked(jobs, count)', 'mut pipes := [3]G13BatchPipe{}', 'mut binds := [64]bool{}',
		'i32(job.stamp_value - pipes[2].last_value) <= 0',
		'i32(job.fragment_stamp_value - pipes[1].last_value) <= 0',
		'.events.can_publish_batch(pipes[pipe].slot, pipes[pipe].values, pipes[pipe].events)',
		'lock.acquire()', 'outer.validate_pointers(outer_rp, outer_wp)',
		'pipes[pipe].outer_next == outer_rp', 'free >= fw.g13_workqueue_entries',
		'pipes[pipe].count > fw.g13_workqueue_entries - used - 1',
		'g13_pending_submissions_locked()', 'old_pending > ~u32(0) - count',
		'katomic.store(mut pending, old_pending + count)', '!mgr.kick_firmware()',
		'katomic.store(mut pending, old_pending)', 'katomic.store(mut threshold,',
		'append_g13_batch_command(queue, 2', 'job.submitted, job.pending_counted = true, true',
		'job.vertex_ring_slot, job.vertex_retirement_sequence',
		'*destination = fw.FwRunWorkQueueMsg', 'katomic.sync()',
		'katomic.store(mut &state.cpu_wptr, pipes[pipe].inner_next)', 'katomic.sync()',
		'katomic.store(mut write, pipes[pipe].outer_next)', 'mgr.ring_pipe(queue.priority, u32(pipe))',
		'return if count == 64 { ~u64(0) }'], 'Vinix prepared batch publication')!
	require(local.count('mgr.ring_pipe(') == 1 && local.count('for pipe in [1, 0, 2]!') == 3,
		'Native batch must publish and notify once per participating pipe in reference order')!
	helper := section(pending, 'fn submit_g13_pending(', '// Called under manager.lock', 'Vinix batch ownership transfer')!
	require_order(helper, ['mut jobs := [64]gpu.G13SubmissionJob{}', 'mut positions := [64]u32{}',
		'positions[count] = index', 'manager.submit_g13_batch(jobs, count)',
		'transferred & (u64(1) << index)', 'command.compute_job, command.render_job = unsafe { nil }, unsafe { nil }',
		'command.published = true'], 'Vinix batch ownership transfer')!
	require(!helper.all_after('manager.submit_g13_batch(jobs, count)').contains('jobs['),
		'Transferred job metadata must never be dereferenced after publication returns')!
}

fn check_ring_admission_contract(local string, reference string) ! {
	free := section(reference, '    pub(crate) fn free_space(', '    pub(crate) fn free_slots(', 'Asahi host ring capacity')!
	require(free.contains('self.size as usize - self.pending.len() - 1'), 'Asahi ring capacity must count host-pending commands')!
	require_order(reference, ['pub(crate) fn can_submit(', 'inner.free_space() > self.pending.len()',
		'pub(crate) fn submit(', 'inner.free_space() <= command_count'], 'Asahi spare-entry admission')!
	gate := section(local, 'fn (mut mgr GpuManager) g13_ring_has_space_locked(',
		'fn (mut mgr GpuManager) submit_g13_queue_commands(', 'Vinix host ring capacity')!
	require_order(gate, ['retired > published', 'published - retired >= u64(fw.g13_workqueue_entries)',
		'published > ~u64(0) - u64(count)', 'mgr.state = .error',
		'u64(fw.g13_workqueue_entries) - 1 - (published - retired) > u64(count)'], 'Vinix host ring capacity')!
	compute := section(local, 'fn (mut mgr GpuManager) submit_g13_queue_commands(',
		'fn (mut mgr GpuManager) publish_g13_compute_job_locked(', 'Vinix compute admission')!
	require_order(compute, ['mgr.g13_ring_has_space_locked(queue.command_sequence, queue.retired_sequence, command_count)',
		'inner_done := katomic.load', 'command_count > inner_free', '*entry = command_va',
		'queue.command_sequence += u64(command_count)', 'katomic.store(mut &state.cpu_wptr'], 'Vinix compute admission')!
	render := section(local, 'fn (mut mgr GpuManager) publish_g13_render_job_locked(',
		'// Transfer a prepared render pass', 'Vinix render admission')!
	require_order(render, ['mgr.g13_ring_has_space_locked(vertex_queue.command_sequence, vertex_queue.retired_sequence, vertex_count)',
		'mgr.g13_ring_has_space_locked(fragment_queue.command_sequence, fragment_queue.retired_sequence, 2)',
		'vertex_inner_wp = katomic.load', 'if !valid {', 'vertex_queue.command_sequence += vertex_count'], 'Vinix paired host admission')!
}

fn check_submission_pipelining(pending string) ! {
	resolve := section(pending, 'fn resolve_g13_batch_dependencies(', 'fn g13_pending_error(', 'Vinix initial dependencies')!
	require_order(resolve, ['barrier == ioctl.asahi_barrier_none', 'barrier == 0',
		'item.initial_barriers |= u32(1) << pipe', 'barrier > counts[pipe]'], 'Vinix initial dependencies')!
	dispatch := section(pending, 'fn g13_pending_dispatch_complete(', '// Only the GPU worker consumes nodes.', 'Vinix dispatch completion')!
	require_order(dispatch, ['item.commands[index].compute_job != unsafe { nil }',
		'item.commands[index].render_job != unsafe { nil }', 'return false', 'return true'], 'Vinix dispatch completion')!
	require(!dispatch.contains('callbacks_remaining') && !dispatch.contains('syncobj.'),
		'Publication completion must not depend on retirement or a user fence')!
	drain := section(pending, 'fn process_pending_submissions()', 'pub fn service_file_work()', 'Vinix submission pipelining')!
	require_order(drain, ['mut unpublished := [128]bool{}', 'current = item.next',
		'mut gate := -1', 'gate = int(index)', 'if gate >= 0 { unpublished[gate] }',
		'blocked_count == 128', 'if earlier || poll_g13_pending',
		'if gate < 0 && blocked_count < 128', '!g13_pending_dispatch_complete(item)',
		'unpublished[gate] = true', 'retained_tail.next = pending_head', 'pending_head = retained_head'],
		'Vinix submission pipelining')!
	require(!drain.contains('item.initial_barriers != 0'), 'Initial events must not wait for whole-batch CPU retirement')!
}

pub fn check_queue_recovery_reference(asahi_linux string, repo string) ![]string {
	base := os.join_path(asahi_linux, 'drivers/gpu/drm/asahi')
	check_timestamp_inputs_local(read(os.join_path(repo, 'kernel/gpu/agx/gpu/g13.v'))!)!
	check_pending_timestamps_local(read(os.join_path(repo, 'kernel/gpu/agx/file/file.v'))!,
		read(os.join_path(repo, 'kernel/gpu/agx/file/pending.v'))!, read(os.join_path(repo, 'kernel/gpu/agx/file/submission_timestamps.v'))!)!
	check_pending_timestamps_reference(read(os.join_path(base, 'queue/compute.rs'))!, read(os.join_path(base, 'queue/render.rs'))!)!
	check_timestamp_capture_local(read(os.join_path(repo, 'kernel/gpu/agx/file/file.v'))!,
		read(os.join_path(repo, 'kernel/gpu/agx/file/timestamps.v'))!, read(os.join_path(repo, 'kernel/gpu/agx/gpu/gpu.v'))!)!
	check_timestamp_capture_reference(read(os.join_path(base, 'queue/common.rs'))!,
		read(os.join_path(base, 'queue/render.rs'))!, read(os.join_path(base, 'queue/compute.rs'))!, read(os.join_path(base, 'file.rs'))!)!
	check_orphan_queue_local(read(os.join_path(repo, 'kernel/gpu/agx/file/file.v'))!,
		read(os.join_path(repo, 'kernel/gpu/agx/gpu/g13.v'))!, read(os.join_path(repo, 'kernel/gpu/agx/gpu/gpu.v'))!)!
	check_orphan_queue_reference(read(os.join_path(base, 'file.rs'))!, read(os.join_path(base, 'queue/mod.rs'))!)!
	check_vm_detach_local(read(os.join_path(repo, 'kernel/gpu/agx/file/file.v'))!)!
	check_vm_detach_reference(read(os.join_path(base, 'file.rs'))!, read(os.join_path(base, 'mmu.rs'))!)!
	check_queue_reference_local(read(os.join_path(repo, 'kernel/gpu/agx/file/file.v'))!,
		read(os.join_path(repo, 'kernel/gpu/agx/file/pending.v'))!, read(os.join_path(repo, 'kernel/gpu/agx/gpu/g13.v'))!,
		read(os.join_path(repo, 'kernel/fs/vfs.v'))!)!
	check_queue_detach_local(read(os.join_path(repo, 'kernel/gpu/agx/file/file.v'))!,
		read(os.join_path(repo, 'kernel/gpu/agx/file/pending.v'))!, read(os.join_path(repo, 'kernel/gpu/agx/workqueue/workqueue.v'))!,
		read(os.join_path(repo, 'kernel/gpu/agx/gpu/gpu.v'))!)!
	check_queue_detach_reference(read(os.join_path(base, 'file.rs'))!, read(os.join_path(base, 'queue/mod.rs'))!)!
	_ = tiling_reference_v(read(os.join_path(base, 'queue/render.rs'))!, read(os.join_path(base, 'util.rs'))!)!
	check_cpu_cache_local(read(os.join_path(repo, 'kernel/drm/gem/gem.v'))!,
		read(os.join_path(repo, 'kernel/gpu/agx/bo/bo.v'))!, read(os.join_path(repo, 'kernel/gpu/agx/file/file.v'))!,
		read(os.join_path(repo, 'kernel/gpu/agx/driver/driver.v'))!, read(os.join_path(repo, 'kernel/memory/ram_cache_arm64.v'))!,
		read(os.join_path(repo, 'kernel/aarch64/cpu/data_cache.v'))!, read(os.join_path(repo, 'kernel/drm/drm.v'))!,
		read(os.join_path(repo, 'kernel/memory/mmap/mmap.v'))!)!
	check_cpu_cache_reference(read(os.join_path(base, 'gem.rs'))!)!
	check_compute_flag_local(read(os.join_path(repo, 'kernel/gpu/agx/gpu/g13.v'))!,
		read(os.join_path(repo, 'kernel/gpu/agx/fw/microseq.v'))!, read(os.join_path(repo, 'kernel/gpu/agx/fw/compute.v'))!)!
	check_compute_flag_reference(read(os.join_path(base, 'queue/compute.rs'))!, read(os.join_path(base, 'fw/microseq.rs'))!,
		read(os.join_path(base, 'fw/compute.rs'))!, read(os.join_path(base, 'fw/job.rs'))!, read(os.join_path(base, 'object.rs'))!,
		read(os.join_path(base, 'event.rs'))!, read(os.join_path(base, 'fw/types.rs'))!, read(os.join_path(base, 'fw/workqueue.rs'))!,
		read(os.join_path(repo, 'kernel/gpu/agx/fw/compute.v'))!)!
	check_work_tail_local(read(os.join_path(repo, 'kernel/gpu/agx/fw/vertex.v'))!, read(os.join_path(repo, 'kernel/gpu/agx/fw/compute.v'))!)!
	check_work_tail_reference(read(os.join_path(base, 'fw/vertex.rs'))!, read(os.join_path(base, 'fw/compute.rs'))!,
		read(os.join_path(base, 'fw/job.rs'))!, read(os.join_path(base, 'fw/types.rs'))!, read(os.join_path(base, 'float.rs'))!,
		read(os.join_path(repo, 'kernel/gpu/agx/fw/vertex.v'))!, read(os.join_path(repo, 'kernel/gpu/agx/fw/compute.v'))!)!
	check_fragment_tail_local(read(os.join_path(repo, 'kernel/gpu/agx/fw/fragment.v'))!)!
	check_fragment_tail_reference(read(os.join_path(base, 'fw/fragment.rs'))!,
		read(os.join_path(base, 'fw/job.rs'))!, read(os.join_path(base, 'queue/render.rs'))!,
		read(os.join_path(repo, 'kernel/gpu/agx/fw/fragment.v'))!)!
	check_microseq_field_reference(read(os.join_path(base, 'fw/microseq.rs'))!,
		read(os.join_path(base, 'queue/render.rs'))!, read(os.join_path(base, 'queue/compute.rs'))!)!
	check_timestamp_pair_local(read(os.join_path(repo, 'kernel/gpu/agx/gpu/g13.v'))!,
		read(os.join_path(repo, 'kernel/gpu/agx/fw/microseq.v'))!)!
	check_timestamp_pair_reference(timestamp_pair_model(read(os.join_path(base, 'fw/microseq.rs'))!,
		read(os.join_path(base, 'fw/vertex.rs'))!, read(os.join_path(base, 'fw/fragment.rs'))!,
		read(os.join_path(base, 'fw/compute.rs'))!, read(os.join_path(base, 'fw/job.rs'))!)!,
		read(os.join_path(base, 'queue/render.rs'))!, read(os.join_path(base, 'queue/compute.rs'))!,
		read(os.join_path(repo, 'kernel/gpu/agx/fw/microseq.v'))!)!
	check_vertex_cluster_local(read(os.join_path(repo, 'kernel/gpu/agx/gpu/g13.v'))!,
		read(os.join_path(repo, 'kernel/gpu/agx/fw/microseq.v'))!)!
	check_vertex_cluster_reference(read(os.join_path(base, 'queue/render.rs'))!,
		read(os.join_path(base, 'fw/microseq.rs'))!)!
	check_submit_device_local(read(os.join_path(repo, 'kernel/gpu/agx/file/file.v'))!, read(os.join_path(repo, 'kernel/gpu/agx/gpu/gpu.v'))!)!
	check_submit_device_reference(read(os.join_path(base, 'queue/mod.rs'))!)!
	check_timestamp_bind_local(read(os.join_path(repo, 'kernel/gpu/agx/file/file.v'))!)!
	check_timestamp_bind_reference(read(os.join_path(base, 'file.rs'))!, read(os.join_path(base, 'gpu.rs'))!,
		read(os.join_path(base, 'gem.rs'))!, read(os.join_path(base, 'mmu.rs'))!)!
	check_params_device_local(read(os.join_path(repo, 'kernel/gpu/agx/file/file.v'))!, read(os.join_path(repo, 'kernel/gpu/agx/gpu/gpu.v'))!)!
	check_params_device_reference(read(os.join_path(base, 'file.rs'))!, read(os.join_path(base, 'gpu.rs'))!)!
	check_params_copy_local(read(os.join_path(repo, 'kernel/gpu/agx/file/file.v'))!,
		read(os.join_path(repo, 'kernel/gpu/agx/fake/driver.v'))!, read(os.join_path(repo, 'kernel/gpu/agx/params/params.v'))!)!
	check_params_copy_reference(read(os.join_path(base, 'file.rs'))!, read(os.join_path(asahi_linux, 'include/uapi/drm/asahi_drm.h'))!)!
	check_bind_replace_local(read(os.join_path(repo, 'kernel/gpu/agx/file/file.v'))!, read(os.join_path(repo, 'kernel/gpu/agx/pgtable/pgtable.v'))!)!
	check_bind_replace_reference(read(os.join_path(base, 'mmu.rs'))!)!
	check_unbind_range_local(read(os.join_path(repo, 'kernel/gpu/agx/file/file.v'))!)!
	check_unbind_range_reference(read(os.join_path(base, 'file.rs'))!, read(os.join_path(base, 'mmu.rs'))!)!
	check_create_size_local(read(os.join_path(repo, 'kernel/gpu/agx/bo/bo.v'))!,
		read(os.join_path(repo, 'kernel/gpu/agx/file/file.v'))!, read(os.join_path(repo, 'kernel/gpu/agx/fake/driver.v'))!)!
	check_create_size_reference(read(os.join_path(base, 'gem.rs'))!, read(os.join_path(base, 'file.rs'))!)!
	check_single_page_local(read(os.join_path(repo, 'kernel/drm/ioctl/ioctl.v'))!,
		read(os.join_path(repo, 'kernel/gpu/agx/vm/vm.v'))!, read(os.join_path(repo, 'kernel/gpu/agx/file/file.v'))!,
		read(os.join_path(repo, 'kernel/gpu/agx/pgtable/pgtable.v'))!, read(os.join_path(repo, 'kernel/gpu/agx/fake/driver.v'))!)!
	check_single_page_reference(read(os.join_path(asahi_linux, 'include/uapi/drm/asahi_drm.h'))!, read(os.join_path(base, 'mmu.rs'))!)!
	check_bind_vm_lookup_contract(read(os.join_path(repo, 'kernel/gpu/agx/file/file.v'))!,
		read(os.join_path(repo, 'kernel/gpu/agx/vm/vm.v'))!, read(os.join_path(base, 'file.rs'))!)!
	check_submit_lookup_order_contract(read(os.join_path(repo, 'kernel/gpu/agx/file/file.v'))!, read(os.join_path(base, 'file.rs'))!)!
	check_identity_lookup_contract(read(os.join_path(repo, 'kernel/gpu/agx/file/file.v'))!, read(os.join_path(base, 'file.rs'))!)!
	check_asahi_sync_lookup_contract(read(os.join_path(repo, 'kernel/gpu/agx/submission/submission.v'))!,
		read(os.join_path(repo, 'kernel/gpu/agx/file/file.v'))!, read(os.join_path(asahi_linux, 'rust/kernel/drm/syncobj.rs'))!,
		read(os.join_path(base, 'file.rs'))!)!
	check_fd_reservation_contract(read(os.join_path(repo, 'kernel/file/reservation.v'))!,
		read(os.join_path(repo, 'kernel/file/file.v'))!, read(os.join_path(repo, 'kernel/proc/proc.v'))!)!
	check_export_reservation_reference(read(os.join_path(asahi_linux, 'drivers/gpu/drm/drm_syncobj.c'))!,
		read(os.join_path(asahi_linux, 'fs/file.c'))!)!
	check_timeline_boundary_contract(read(os.join_path(repo, 'kernel/drm/syncobj/syncobj.v'))!,
		read(os.join_path(repo, 'kernel/gpu/agx/submission/submission.v'))!,
		read(os.join_path(asahi_linux, 'drivers/dma-buf/dma-fence-chain.c'))!, read(os.join_path(base, 'file.rs'))!)!
	check_sync_file_deadline_contract(read(os.join_path(repo, 'kernel/drm/drm.v'))!,
		read(os.join_path(repo, 'kernel/drm/ioctl/ioctl.v'))!, read(os.join_path(repo, 'kernel/drm/sync_file_deadline.v'))!)!
	check_sync_file_deadline_reference(read(os.join_path(asahi_linux, 'drivers/dma-buf/sync_file.c'))!,
		read(os.join_path(asahi_linux, 'include/uapi/linux/sync_file.h'))!,
		read(os.join_path(asahi_linux, 'drivers/dma-buf/dma-fence.c'))!, read(os.join_path(asahi_linux, 'rust/kernel/dma_fence.rs'))!,
		read(os.join_path(asahi_linux, 'drivers/gpu/drm/scheduler/sched_fence.c'))!)!
	check_sync_file_info_contract(read(os.join_path(repo, 'kernel/drm/drm.v'))!,
		read(os.join_path(repo, 'kernel/drm/ioctl/ioctl.v'))!, read(os.join_path(repo, 'kernel/drm/sync_file_info.v'))!,
		read(os.join_path(repo, 'kernel/drm/syncobj/info.v'))!, read(os.join_path(repo, 'kernel/drm/syncobj/stub.v'))!)!
	check_sync_file_info_reference(read(os.join_path(asahi_linux, 'drivers/dma-buf/sync_file.c'))!,
		read(os.join_path(asahi_linux, 'include/uapi/linux/sync_file.h'))!,
		read(os.join_path(asahi_linux, 'drivers/dma-buf/dma-fence.c'))!, read(os.join_path(base, 'queue/mod.rs'))!)!
	check_sync_file_poll_contract(read(os.join_path(repo, 'kernel/drm/drm.v'))!,
		read(os.join_path(repo, 'kernel/drm/syncobj/syncobj.v'))!,
		read(os.join_path(repo, 'kernel/drm/syncobj/events.v'))!,
		read(os.join_path(asahi_linux, 'drivers/dma-buf/sync_file.c'))!)!
	check_sharing_contract(read(os.join_path(repo, 'kernel/drm/drm.v'))!,
		read(os.join_path(repo, 'kernel/drm/syncobj_fd.v'))!,
		read(os.join_path(repo, 'kernel/drm/syncobj/syncobj.v'))!,
		read(os.join_path(asahi_linux, 'drivers/gpu/drm/drm_syncobj.c'))!)!
	check_namespace_contract(read(os.join_path(repo, 'kernel/drm/syncobj/syncobj.v'))!,
		read(os.join_path(asahi_linux, 'drivers/gpu/drm/drm_syncobj.c'))!)!
	check_create_contract(read(os.join_path(repo, 'kernel/drm/drm.v'))!,
		read(os.join_path(repo, 'kernel/drm/syncobj/syncobj.v'))!,
		read(os.join_path(asahi_linux, 'drivers/gpu/drm/drm_syncobj.c'))!)!
	check_signal_contract(read(os.join_path(repo, 'kernel/drm/drm.v'))!,
		read(os.join_path(repo, 'kernel/drm/ioctl/ioctl.v'))!,
		read(os.join_path(repo, 'kernel/drm/syncobj/stub.v'))!,
		read(os.join_path(asahi_linux, 'drivers/gpu/drm/drm_syncobj.c'))!,
		read(os.join_path(asahi_linux, 'drivers/dma-buf/dma-fence.c'))!,
		read(os.join_path(asahi_linux, 'include/uapi/drm/drm.h'))!)!
	check_reset_contract(read(os.join_path(repo, 'kernel/drm/drm.v'))!,
		read(os.join_path(repo, 'kernel/drm/ioctl/ioctl.v'))!,
		read(os.join_path(repo, 'kernel/drm/wait_storage.v'))!,
		read(os.join_path(repo, 'kernel/drm/syncobj/syncobj.v'))!,
		read(os.join_path(asahi_linux, 'drivers/gpu/drm/drm_syncobj.c'))!,
		read(os.join_path(asahi_linux, 'include/uapi/drm/drm.h'))!)!
	check_wait_storage_contract(read(os.join_path(repo, 'kernel/drm/drm.v'))!,
		read(os.join_path(repo, 'kernel/drm/wait_storage.v'))!,
		read(os.join_path(asahi_linux, 'drivers/gpu/drm/drm_syncobj.c'))!)!
	check_wait_capture_contract(read(os.join_path(repo, 'kernel/drm/drm.v'))!,
		read(os.join_path(repo, 'kernel/drm/syncobj/syncobj.v'))!,
		read(os.join_path(repo, 'kernel/drm/syncobj/capture.v'))!,
		read(os.join_path(asahi_linux, 'drivers/gpu/drm/drm_syncobj.c'))!)!
	check_binary_wait_contract(read(os.join_path(repo, 'kernel/drm/drm.v'))!,
		read(os.join_path(asahi_linux, 'drivers/gpu/drm/drm_syncobj.c'))!)!
	check_fence_completion_contract(read(os.join_path(repo, 'kernel/drm/syncobj/syncobj.v'))!,
		read(os.join_path(asahi_linux, 'drivers/dma-buf/dma-fence.c'))!)!
	manager := read(os.join_path(base, 'gpu.rs'))!
	workqueue := read(os.join_path(base, 'workqueue.rs'))!
	check_render_retirement_reference(workqueue, read(os.join_path(base, 'queue/render.rs'))!)!
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
	check_render_retirement_local(local)!
	check_compute_retirement_local(local)!
	check_heap_metadata_local(read(os.join_path(repo, 'kernel/gpu/agx/alloc/alloc.v'))!)!
	check_heap_metadata_reference(read(os.join_path(base, 'alloc.rs'))!)!
	check_heap_bounds_local(read(os.join_path(repo, 'kernel/gpu/agx/alloc/alloc.v'))!)!
	check_heap_bounds_reference(read(os.join_path(base, 'alloc.rs'))!)!
	check_heap_release_policy_local(read(os.join_path(repo, 'kernel/gpu/agx/alloc/alloc.v'))!,
		read(os.join_path(repo, 'kernel/gpu/agx/gpu/gpu.v'))!)!
	check_heap_release_policy_reference(read(os.join_path(base, 'alloc.rs'))!, manager)!
	check_heap_pressure_local(read(os.join_path(repo, 'kernel/gpu/agx/alloc/alloc.v'))!,
		read(os.join_path(repo, 'kernel/gpu/agx/gpu/gpu.v'))!)!
	check_heap_pressure_reference(read(os.join_path(base, 'alloc.rs'))!)!
	check_heap_cancel_local(read(os.join_path(repo, 'kernel/gpu/agx/alloc/alloc.v'))!,
		read(os.join_path(repo, 'kernel/gpu/agx/gpu/gpu.v'))!, read(os.join_path(repo, 'kernel/gpu/agx/pgtable/pgtable.v'))!)!
	check_heap_cancel_reference(read(os.join_path(base, 'alloc.rs'))!)!
	check_teardown_gc_local(read(os.join_path(repo, 'kernel/gpu/agx/gpu/g13.v'))!,
		read(os.join_path(repo, 'kernel/gpu/agx/gpu/gpu.v'))!)!
	check_teardown_gc_reference(read(os.join_path(base, 'alloc.rs'))!, manager)!
	check_context_retire_local(read(os.join_path(repo, 'kernel/gpu/agx/fw/channels.v'))!,
		read(os.join_path(repo, 'kernel/gpu/agx/gpu/g13_context.v'))!, read(os.join_path(repo, 'kernel/gpu/agx/gpu/g13.v'))!)!
	check_context_retire_reference(manager, read(os.join_path(base, 'fw/channels.rs'))!, read(os.join_path(base, 'fw/workqueue.rs'))!)!
	check_context_defer_local(read(os.join_path(repo, 'kernel/gpu/agx/gpu/g13_context.v'))!,
		read(os.join_path(repo, 'kernel/gpu/agx/gpu/g13.v'))!, read(os.join_path(repo, 'kernel/gpu/agx/gpu/gpu.v'))!)!
	check_context_defer_reference(manager)!
	check_queue_unwind_local(read(os.join_path(repo, 'kernel/gpu/agx/gpu/g13.v'))!)!
	check_queue_records_local(read(os.join_path(repo, 'kernel/gpu/agx/file/file.v'))!,
		read(os.join_path(repo, 'kernel/gpu/agx/gpu/g13.v'))!)!
	check_queue_unwind_reference(read(os.join_path(base, 'queue/mod.rs'))!, read(os.join_path(base, 'buffer.rs'))!,
		read(os.join_path(base, 'fw/workqueue.rs'))!, read(os.join_path(base, 'alloc.rs'))!)!
	check_heap_gc_local(read(os.join_path(repo, 'kernel/gpu/agx/gpu/g13_garbage.v'))!,
		read(os.join_path(repo, 'kernel/gpu/agx/gpu/gpu.v'))!, read(os.join_path(repo, 'kernel/gpu/agx/fw/channels.v'))!)!
	check_heap_gc_reference(manager, read(os.join_path(base, 'fw/channels.rs'))!)!
	check_uat_poll_local(read(os.join_path(repo, 'kernel/gpu/agx/gpu/gpu.v'))!,
		read(os.join_path(repo, 'kernel/sched/sched_arm64.v'))!)!
	check_worker_scheduling_local(read(os.join_path(repo, 'kernel/gpu/agx/gpu/gpu.v'))!,
		read(os.join_path(repo, 'kernel/gpu/agx/gpu/g17.v'))!, read(os.join_path(repo, 'kernel/gpu/agx/fake/driver.v'))!,
		read(os.join_path(repo, 'kernel/sched/sched_arm64.v'))!, read(os.join_path(repo, 'kernel/sched/sched_amd64.v'))!)!
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
	parameters := read(os.join_path(base, 'asahi_core.rs'))!
	require_order(parameters, ['debug_flags: u64 {', 'default: 0,',
		'compute_preempt: i32 {', 'default: -1,'], 'Asahi default compute preemption')!
	require_order(workqueue, ['#[ver(G != G14X)]', 'false',
		'if pipe_type == PipeType::Compute && !preempt', 'prio.0 = 0;', 'prio.5 = 1;'],
		'Asahi G13 compute priority')!
	queue_init := section(local, 'fn (mut mgr GpuManager) initialize_g13_subqueue(',
		'fn (mut mgr GpuManager) invalidate_g13_queue_mappings_locked(', 'Vinix queue priority')!
	require(queue_init.contains('fw.g13_default_workqueue_priority(resources.priority, pipe_type)'),
		'Vinix subqueue must use pipe-specific priority')!
	priority := read(os.join_path(repo, 'kernel/gpu/agx/fw/workqueue.v'))!
	priority_init := section(priority, 'pub fn g13_default_workqueue_priority(',
		'pub fn initialize_g13_gpu_context(', 'Vinix queue priority')!
	require_order(priority_init, ['g13_workqueue_priority(priority)', 'if pipe_type == 2',
		'value.value_0 = 0', 'value.value_18 = 1'], 'Vinix G13 compute priority')!
	queue := read(os.join_path(base, 'queue/mod.rs'))!
	require_order(queue, ['job.add_dependency(fence)?', 'job.commit()?', 'let mut job = job.arm()',
		'job.push()'], 'Asahi asynchronous dependency scheduling')!
	file_source := read(os.join_path(repo, 'kernel/gpu/agx/file/file.v'))!
	check_queue_priority_local(file_source, read(os.join_path(repo, 'kernel/drm/ioctl/ioctl.v'))!, local)!
	check_queue_priority_reference(read(os.join_path(asahi_linux, 'include/uapi/drm/asahi_drm.h'))!,
		read(os.join_path(base, 'file.rs'))!)!
	check_private_bo_local(file_source, read(os.join_path(repo, 'kernel/gpu/agx/bo/bo.v'))!,
		read(os.join_path(repo, 'kernel/gpu/agx/mmu/mmu.v'))!, read(os.join_path(repo, 'kernel/drm/gem/gem.v'))!,
		read(os.join_path(repo, 'kernel/drm/drm.v'))!, read(os.join_path(repo, 'kernel/gpu/agx/vm/identity.v'))!)!
	check_private_bo_reference(read(os.join_path(base, 'gem.rs'))!)!
	check_user_mapping_contract(file_source, read(os.join_path(repo, 'kernel/gpu/agx/gpu/gpu.v'))!)!
	ioctl_submit := section(file_source, 'pub fn (mut f GpuFile) ioctl_submit(',
		'fn dispatch(', 'Vinix async submission ioctl')!
	require(!ioctl_submit.contains('wait_g13_fence') && !ioctl_submit.contains('syncobj.wait')
		&& !ioctl_submit.contains('sched.yield'), 'Vinix submission must not wait for dependencies or GPU work')!
	require_order(ioctl_submit, ['agxsubmission.stage_command_array', 'agxsubmission.stage_sync_array',
		'f.lock.acquire()', 'memory.malloc_packed_fallible(sizeof(G13PendingSubmission))',
		'gpu_manager.capture_g13_initial_events', 'gpu_manager.prepare_g13_compute_job', 'gpu_manager.prepare_g13_render_job',
		'install_g13_batch_barriers',
		'gpu_manager.release_g13_initial_events', 'agxsubmission.install_output_syncs', 'register_g13_pending'], 'Vinix prepared async submission')!
	pending := read(os.join_path(repo, 'kernel/gpu/agx/file/pending.v'))!
	check_submission_pipelining(pending)!
	check_ring_admission_contract(local, workqueue)!
	check_event_admission_contract(read(os.join_path(repo, 'kernel/gpu/agx/event/workqueue.v'))!, workqueue)!
	check_prepared_backlog_contract(read(os.join_path(repo, 'kernel/gpu/agx/event/workqueue.v'))!, workqueue)!
	check_batch_admission_contract(read(os.join_path(repo, 'kernel/gpu/agx/gpu/g13_admission.v'))!, pending, queue)!
	check_batch_publication_contract(read(os.join_path(repo, 'kernel/gpu/agx/gpu/g13_batch.v'))!, pending, queue)!
	check_input_dependency_contract(pending)!
	check_queue_fence_contract(read(os.join_path(repo, 'kernel/drm/syncobj/queue.v'))!,
		read(os.join_path(repo, 'kernel/drm/syncobj/syncobj.v'))!, local, ioctl_submit)!
	require_order(queue, ['let sched = sched::Scheduler::new(', 'let entity = sched::Entity::new(&sched,',
		'_sched: sched,', 'entity,'], 'Asahi per-user-queue scheduler ownership')!
	scheduler := read(os.join_path(asahi_linux, 'drivers/gpu/drm/scheduler/sched_entity.c'))!
	dependency_cb := section(scheduler, 'static bool drm_sched_entity_add_dependency_cb(',
		'static struct dma_fence *', 'Asahi scheduler input dependency callback')!
	require_order(dependency_cb, ['fence->context == entity->fence_context',
		'fence->context == entity->fence_context + 1', 'dma_fence_put(entity->dependency)',
		'return false', 's_fence = to_drm_sched_fence(fence)'], 'Asahi own-entity fence elision')!
	require_order(dependency_cb, ['!fence->error && s_fence', 'dma_fence_add_callback(entity->dependency',
		'return true', 'dma_fence_put(entity->dependency)', 'return false'], 'Asahi scheduler input dependency readiness')!
	require(!dependency_cb.contains('dma_fence_set_error'), 'Asahi input dependency callback must not propagate input errno')!
	pop := section(scheduler, 'struct drm_sched_job *drm_sched_entity_pop_job(',
		'void drm_sched_entity_select_rq(', 'Asahi scheduler pop')!
	require_order(pop, ['drm_sched_job_dependency(sched_job, entity)',
		'drm_sched_entity_add_dependency_cb(entity, sched_job)', 'if (entity->guilty',
		'dma_fence_set_error(&sched_job->s_fence->finished, -ECANCELED)', 'return sched_job'], 'Asahi scheduler pop')!
	run := section(read(os.join_path(asahi_linux, 'drivers/gpu/drm/scheduler/sched_main.c'))!,
		'static void drm_sched_run_job_work(', 'static struct workqueue_struct *drm_sched_alloc_wq(', 'Asahi scheduler run')!
	require_order(run, ['drm_sched_entity_pop_job(entity)', 'sched->ops->run_job(sched_job)',
		'drm_sched_fence_scheduled(s_fence, fence)', 'drm_sched_job_done(sched_job, fence->error)'], 'Asahi scheduler completion error origin')!
	require(!pending.contains('syncobj.wait') && !pending.contains('sched.yield'), 'Vinix dependency poller must not wait')!
	poll := section(pending, 'fn poll_g13_pending(', '// Only the GPU worker consumes nodes.', 'Vinix batch overlap')!
	check_dependency_publication(poll)!
	require_order(poll, ['g13_dependencies_ready(&item.dependencies, item.queue.fence_context)', 'failure := g13_pending_error(item)',
		'if !item.admitted', 'manager.g13_queue_dispatch_blocked', 'submit_g13_pending(mut manager, mut item)',
		'completed_error := g13_pending_error(item)',
		'if katomic.load(&item.callbacks_remaining) != 0', 'final_error := g13_pending_error(item)'],
		'Vinix dependency, per-subqueue FIFO and overlapping publication')!
	resolve := section(pending, 'fn resolve_g13_batch_dependencies(', 'fn g13_pending_error(', 'Vinix barrier resolution')!
	require_order(resolve, ['mut positions := [2][64]u32{}', 'barrier == 0', 'barrier > counts[pipe]',
		'positions[pipe][barrier - 1] + 1', 'positions[entry.pipe][counts[entry.pipe]] = index',
		'counts[entry.pipe]++'], 'Vinix subqueue-local barrier positions')!
	guard := section(local, 'fn (mgr &GpuManager) g13_queue_dispatch_blocked_locked(',
		'// Caller holds the manager lock during shutdown.', 'Vinix quarantine gate')!
	require(!guard.contains('job.submitted') && guard.count('job.quarantined') == 2 &&
		local.count('if mgr.g13_queue_dispatch_blocked_locked(owned.queue)') == 2,
		'Vinix overlap must gate quarantine under each publication lock')!
	submission := read(os.join_path(repo, 'kernel/gpu/agx/submission/submission.v'))!
	reference_file := read(os.join_path(base, 'file.rs'))!
	require(integer_constant(submission, 'max_commands', 'Vinix command count')! ==
		integer_constant(reference_file, 'MAX_COMMANDS_PER_SUBMISSION', 'Asahi command count')!,
		'Native hardware-command limit differs')!
	require_order(queue, ['const SQ_RENDER: usize = 0', 'const SQ_COMPUTE: usize = 1',
		'events[queue_idx].get(*index as usize)'], 'Asahi subqueue barrier numbering')!
	barrier_wire := read(os.join_path(base, 'fw/workqueue.rs'))!
	require_order(barrier_wire, ['pub(crate) struct Barrier {', 'wait_stamp: GpuWeakPointer<FwStamp>',
		'external_barrier: u32', 'internal_barrier_type: u32', 'padding: Pad<0x1c>'], 'Asahi barrier wire fields')!
	require_order(queue, ['Create Explicit Barrier', 'wait_stamp: event.fw_stamp_pointer',
		'wait_value: event.value', 'stamp_self: queue_job.event_info().value.next()',
		'uuid: 0xffffbbbb', 'external_barrier: 0', 'internal_barrier_type: 1',
		'queue_job.add(barrier, vm_slot)'], 'Asahi explicit barrier prefix')!
	barriers := read(os.join_path(repo, 'kernel/gpu/agx/gpu/g13_barriers.v'))!
	check_initial_snapshot_contract(read(os.join_path(repo, 'kernel/gpu/agx/gpu/g13_initial.v'))!, barriers,
		read(os.join_path(repo, 'kernel/gpu/agx/event/workqueue.v'))!, read(os.join_path(repo, 'kernel/gpu/agx/gpu/gpu.v'))!)!
	require_order(barriers.fields().join(' '), ['fn (mut mgr GpuManager) initialize_g13_barriers_locked(',
		'barriers.configured = true', 'event.retain_stamp(wait.slot)',
		'barriers.slots[index] = wait.slot', 'barriers.waits[index]', 'barriers.pin_count++', 'barriers.count++',
		'write_g13_barrier(&owner', 'mgr.flush_g13_kernel_buffer(&owner)', 'barriers.ready = true'],
		'Vinix owned firmware barrier prefix')!
	writer := section(barriers, 'fn write_g13_barrier(', '// Caller holds manager.lock.', 'Vinix barrier wire writer')!
	require_order(writer.fields().join(' '), ['wait_stamp: event.firmware_stamp_address(wait.slot)', 'wait_value: wait.value',
		'stamp_self: stamp_self', 'uuid: 0xffffbbbb', 'external_barrier: 0', 'internal_barrier_type: 1'], 'Vinix barrier wire writer')!
	require_order(local, ['job.explicit_barriers.offset = g13_barrier_tail_offset(sizeof(fw.G13InitBufferCommand))',
		'job.explicit_barriers.offset + g13_barrier_tail_size',
		'vertex_count := job.explicit_barriers.count +',
		'index < job.explicit_barriers.count', 'command_wp := (vertex_inner_wp + job.explicit_barriers.count)',
		'*vertex_entry_0 = job.init_buffer.va',
		'job.explicit_barriers.offset = g13_barrier_tail_offset(logical_microsequence_size)',
		'job.explicit_barriers.offset + g13_barrier_tail_size',
		'mgr.publish_g13_compute_job_locked(owned)'], 'Vinix private tail placement and barrier publication')!
	compute_prefix := section(local, 'fn (mut mgr GpuManager) publish_g13_compute_job_locked(',
		'fn (mut mgr GpuManager) submit_g13_queue_command(', 'Vinix compute barrier transaction')!
	require_order(compute_prefix, ['explicit_barriers.publishable', 'mut storage := [3]u64{}',
		'job.microsequence.va + job.explicit_barriers.offset', 'storage[job.explicit_barriers.count] = job.command.va',
		'mgr.submit_g13_queue_commands(job.queue, 2, storage, job.explicit_barriers.count + 1'], 'Vinix atomic compute prefix')!
	require(local.count('release_g13_barrier_pins(mut job.explicit_barriers)') == 2,
		'Both native job cleanup paths must release barrier pins')!
	stage := section(submission, 'pub fn stage_command_array(', '// The fake backend retains', 'Vinix mixed batch staging')!
	require_order(stage, ['count > max_commands', 'mut counts := [2]u32{}',
		'barrier > counts[pipe]', 'staged[index] = command', 'asahi_cmd_render { 0 } else { 1 }',
		'counts[pipe]++'], 'Vinix per-subqueue barrier validation')!
	require_order(pending, ['int(item.command_count) - 1', 'command.compute_job = unsafe { nil }',
		'manager.release_g13_compute_job', 'command.render_job = unsafe { nil }',
		'manager.release_g13_render_job'], 'Vinix reverse command cancellation')!
	require_order(pending, ['pending_head = unsafe { nil }', 'current = item.next',
		'if earlier || poll_g13_pending', 'katomic.load(&item.callbacks_remaining) == 0',
		'signal_g13_submission_fence(item.final_fence', 'memory.free(voidptr(item))',
		'retained_tail.next = pending_head', 'pending_head = retained_head'],
		'Vinix FIFO retry and callback-owned retirement')!
	completion := section(file_source, 'fn finish_g13_submit(', 'fn g13_render_completed(', 'Vinix aggregate fence')!
	require(!completion.contains('syncobj.signal'), 'Per-command completion must not signal the aggregate fence')!
	require_order(manager, ['impl Default for ID {', 'Self::new(2)',
		'let id = self.ids.queue.next()'], 'Asahi global queue identity')!
	require(queue.contains('generation: AtomicU32::new(id as u32)') &&
		workqueue.contains('uuid: id as u32'), 'Asahi notifier/workqueue identity changed')!
	require(local.contains('firmware_id: mgr.g13_queue_ids.allocate()') &&
		local.contains('priority, u32(resources.firmware_id), resources.context.va') &&
		local.contains('resources.threshold.va, u32(resources.firmware_id)') &&
		local.count('client_sequence: u8(resources.firmware_id & 0xff)') == 3 &&
		local.count('event_generation: u32(resources.firmware_id)') == 3,
		'Vinix firmware identity must be device-wide on every subqueue')!
	require(queue.contains('counter: AtomicU64::new(0)'), 'Asahi initial command counter changed')!
	compute := read(os.join_path(base, 'queue/compute.rs'))!
	require_order(compute, ['self.counter.fetch_add(1, Ordering::Relaxed)',
		'counter: U64(count)', 'counter: U64(count)'], 'Asahi compute command/start counter')!
	render := read(os.join_path(base, 'queue/render.rs'))!
	require_order(render, ['let aux_fb_info =', 'unk3: U64(0x100000)',
		'aux_fb_info,', 'aux_fb_info,'], 'Asahi Ventura auxiliary framebuffer defaults')!
	fragment_wire := read(os.join_path(repo, 'kernel/gpu/agx/fw/fragment.v'))!
	require_order(fragment_wire, ['g13_put_u64(voidptr(&out), 0x0c0, 0x100000)',
		'g13_put_u64(voidptr(&out), 0x6e8, 0x100000)'], 'Vinix Ventura auxiliary framebuffer defaults')!
	require_order(render, ['self.counter.fetch_add(2, Ordering::Relaxed)',
		'let count_vtx = count_frag + 1', 'counter: U64(count_frag)',
		'counter: U64(count_frag)', 'counter: U64(count_vtx)', 'counter: U64(count_vtx)'],
		'Asahi render command/start counters')!
	require_order(local, ['fragment_counter := queue.command_counter.reserve(2, v13_5)',
		'vertex_counter := fragment_counter + u64(1)',
		'fw.make_g13_vertex_v13_5(vertex, vertex_counter)',
		'fw.make_g13_fragment_v13_5(fragment, fragment_counter)',
		'v13_5, unsafe { &vertex_start }, vertex_counter,', 'v13_5, &fragment_start, fragment_counter,',
		'compute_counter := owned_queue.command_counter.reserve(1, v13_5)',
		'fw.make_g13_compute_v13_5(run, compute_counter)',
		'v13_5, &start, job.command.va + fw.g13_compute_v13_5_flag_offset, compute_counter,'],
		'Vinix shared command/start counters')!
	return ['Resolved timestamp pairs populate versioned native commands and independently select vertex/fragment/compute instructions while legacy callers provide empty pairs',
		'Timestamp capture retains detached mappings and file ownership, preserves lookup/offset errors, rolls back failed prefixes and serializes global timestamp allocation',
		'host workqueue retirement pointer and wrap-safe publication',
		'G13 submission returns ENODEV for error/stopped devices at a released manager-lock snapshot before job/output publication, preserving staging cleanup and unsupported-backend errors',
		'Zero-length BIND rejects before BO lookup, including SINGLE_PAGE, while legacy zero-encoded UNBIND_ALL retains its operation semantics',
		'Timestamp BIND ignores input output-handles, checks sum overflow before BO lookup and empty ranges after it; UNBIND resolves missing names before manager availability and preserves retained owners',
		'Global GET_PARAMS rejects error/stopped devices with ENODEV before formatting/copying, using a released manager-lock snapshot',
		'Global GET_PARAMS treats size as an input bound, shares one bounded prefix copy, permits zero-byte queries and preserves fault output/header semantics',
		'BIND preallocates fallible mapping/table storage before replacing idle overlaps, preserves survivors and aborts new installation after failed old invalidation',
		'UNBIND removes intersections across holes/multiple BOs, preallocates surviving fragments, preserves backing through failed invalidation and retries complete tombstones',
		'GEM-create size validation returns EINVAL for zero and EOVERFLOW for 16 KiB rounding overflow after private VM lookup and before allocation',
		'SINGLE_PAGE BIND consumes one BO page and repeats its PTE across the complete VA range with rollback/invalidation and retained backing',
		'BIND resolves its BO and validates size/global fields before VM lookup; unbind and private-window checks retain the mutation lock',
		'Missing submit queues precede command/sync staging, with no borrowed queue across copies and locked backend revalidation',
		'Absent VM/queue identities return ENOENT during VM destroy, queue create/destroy and submission without confusing invalid internal VM state',
		'VM-private BO domains reject foreign/recreated VMs, import, kernel timestamp mapping and PRIME export before publication',
		'User mapping backing survives failed invalidation; serialized flush/stop, VM mutation lock and new-submit admission retain ownership',
		'pending-stamp fault classification and halt/resume handshake',
		'TVB growth ACK halt counter',
		'G13 LOW/MEDIUM admission, reversed firmware bands, default compute priority and retained failed-create VM ownership',
		'First fence completion preserves its status and callbacks across later completion attempts',
		'Binary syncobj waits retain captured object/fence snapshots, validate all inputs and follow empty objects only with WAIT_FOR_SUBMIT',
		'Empty binary waits capture the first publication under the object lock, detach borrowed nodes on every exit and honor unmasked signals/thread exit',
		'Binary waits use checked owned storage above the inline capacity and detach captures before freeing that owner',
		'Binary syncobj RESET validates all handle identities before sequential nil replacement and preserves captured fences',
		'Binary syncobj SIGNAL validates all identities then installs private timestamped completions with sequential OOM prefix semantics',
		'Syncobj CREATE initializes fallible object/completion storage before namespace publication and frees only unpublished preparation on error',
		'Syncobj namespaces allocate/reuse nonzero 32-bit handles without fixed global/per-file object caps and retain detached snapshots',
		'Native asynchronous dependency polling, per-queue FIFO and callback-owned retirement',
		'Signaled input dependencies release waits without propagating input errno; own GPU failures remain separate',
		'Per-user-queue scheduler fence elision uses immutable, non-reused private scalar identities',
		'Compute and paired render admission count host-unretired ring commands and preserve the reference spare entry',
		'Whole-batch readiness counts all three pipes before publication, including compacted prefixes and simulated TVB bind/growth records; event and ring windows retain the reference spare',
		'Prepared reservations grow beyond the hardware window in owned overflow blocks, with fallible allocation rollback, signed-half-range safety and unlink-before-free retirement',
		'Native batch publication completes every fallible ring/wake preparation before notifier accounting or visibility, then exposes and notifies fragment/vertex/compute once each',
		'Native 64-command mixed batches, subqueue barrier bounds and reverse unwind',
		'Native intra-batch firmware dependencies, per-subqueue FIFO and locked quarantine gates',
		'Independent later submissions pipeline after older publication with initial firmware dependencies',
		'Initial event capture, stable host identities, cancellation fallback and pin-preserving prefix compaction',
		'G13 explicit barrier wire fields, private tails, physical stamp pins and atomic prefixes',
		'Device-wide firmware queue/notifier identity distinct from userspace handles',
		'Firmware 13.5 auxiliary framebuffer tail defaults',
		'Firmware 12.3 padding and 13.5 single-cluster vertex-start marker',
		'Firmware 13.5 start/finalize share the source-derived compute flag word',
		'Firmware 13.5 vertex/compute command extents and complete common fields follow the recursive source-layout model',
		'Firmware 13.5 fragment preserves declared parameter padding; the recursive field model includes source-derived auxiliary defaults',
		'Firmware timestamp instructions bind the source-derived optional user pair inside each retained command for all three engines and both phases',
		'Firmware start/finalize record fields, insertions and reserved defaults follow the selected source-layout model',
		'Base M1 tiling formulas, bounds, single-cluster specialization and packed parameter words are accepted by the restricted source-expression model',
		'Native GEM WRITEBACK selects matching CPU aliases; whole-BO VMAs and cache restoration precede backing reuse',
		'G13 QUEUE_DESTROY hides the namespace immediately while queue-specific references and failed invalidations retain physical queue ownership',
		'Initial G13 queue capture survives namespace removal during staging, transfers its owner to accepted work and drops it after final callbacks before the aggregate VM pin',
		'VM_DESTROY removes names independently of queues/jobs; existing queues retain physical contexts, idle user mappings retry acknowledged teardown, and contexts retire only after all owners end',
		'Failed G13 queue construction retries physical cleanup while its file/VM stays open; logical queues and captures remain owned, and only successful release returns the retained queue ID and VM pin',
		'Firmware 12.3/13.5 fragment sizes, depth insertion, firmware pointers, scratch/metadata and complete common tail follow the selected source-layout model',
		'Firmware 13.5 shared per-queue command/start counters']
}

pub fn check_tvb_reference(asahi_linux string, repo string) ![]string {
	base := os.join_path(asahi_linux, 'drivers/gpu/drm/asahi')
	check_fragment_tib_contract(read(os.join_path(repo, 'kernel/gpu/agx/gpu/g13.v'))!,
		read(os.join_path(repo, 'kernel/gpu/agx/fw/fragment.v'))!,
		read(os.join_path(base, 'queue/render.rs'))!)!
	reference := read(os.join_path(base, 'buffer.rs'))!
	policy := section(reference, '    pub(crate) fn auto_grow(', '    /// Synchronously grow', 'Asahi TVB feedback')!
	require_order(policy, ['raw.max_pages.load', 'raw.reset.store(1, Ordering::Release)',
		'used_pages * 2', '.div_ceil(PAGES_PER_BLOCK)', '.min(inner.max_blocks_nomemless)',
		'used_pages * 3', '.div_ceil(PAGES_PER_BLOCK)', '.min(inner.max_blocks_nomemless)',
		'need_blocks <= cur_count', 'self.ensure_blocks(want_blocks)'], 'Asahi TVB feedback')!
	local := read(os.join_path(repo, 'kernel/gpu/agx/gpu/g13.v'))!
	parameters := read(os.join_path(base, 'asahi_core.rs'))!
	require_order(parameters, ['initial_tvb_size: usize {', 'default: 0x8,'], 'Asahi initial TVB size')!
	require(integer_constant(local, 'g13_tvb_initial_blocks', 'Vinix initial TVB')! == 8,
		'Vinix initial TVB block count differs')!
	queue := read(os.join_path(base, 'queue/mod.rs'))!
	require_order(queue, ['let tvb_blocks = *module_parameters::initial_tvb_size.value()',
		'ret.inner.buffer.ensure_blocks(tvb_blocks)?', 'ret.q_vtx = Some'], 'Asahi initial TVB allocation')!
	initial := section(local, 'fn (mut mgr GpuManager) initialize_g13_render_buffer(',
		'// Grow the queue', 'Vinix initial TVB allocation')!
	require_order(initial, ['if !complete', 'mgr.free_g13_render_buffer_locked',
		'buffer.initialized = true', 'mgr.ensure_g13_tvb_blocks(mut buffer, g13_tvb_initial_blocks, false)',
		'complete = true'], 'Vinix initial TVB allocation and unwind')!
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
		'G13 fragment TIB words derive from the uTile sample footprint in 2 KiB blocks',
		'Initial eight-block TVB allocation before the first scene',
		'TVB feedback before minimum-dimension growth and scene allocation',
		'TVB complete allocation before table and counter publication',
		'TVB slot retained across active scenes and released by the final scene',
		'TVB unchanged-token preference and oldest-free selection',
		'TVB tail-pointer cache reuse and retained scene ownership on growth',
		'TVB binding on slot acquisition or heap growth']
}
