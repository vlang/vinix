module g13contract

import g13layout
import os

fn test_order_accepts_repeated_tokens() {
	require_order('flush reprotect flush unmap flush', ['flush', 'flush', 'flush'], 'sample')!
}

fn test_dependency_publication_rejects_callback_waits_and_missing_batch_gate() {
	source := os.read_file(os.join_path(g13layout.repo_root(), 'kernel/gpu/agx/file/pending.v'))!
	poll := section(source, 'fn poll_g13_pending(', '\n}\n', 'test poll')!
	check_dependency_publication(poll)!
	for broken in [poll + '\nif !katomic.load(&item.commands[0].done) { return true }',
		poll.replace('if !manager.g13_queue_dispatch_blocked(item.queue)', 'if true'),
		poll.replace('submit_g13_pending(mut manager, mut item)', ''),
		poll.replace('if manager.state != .running { cancel_g13_pending(mut item, -19) }', '')] {
		if _ := check_dependency_publication(broken) { assert false, 'invalid dependency scheduling accepted' }
	}
}

fn test_batch_publication_rejects_early_visibility_and_lost_transfer_cleanup() {
	local := os.read_file(os.join_path(g13layout.repo_root(), 'kernel/gpu/agx/gpu/g13_batch.v'))!
	pending := os.read_file(os.join_path(g13layout.repo_root(), 'kernel/gpu/agx/file/pending.v'))!
	reference := 'frag_sub = Some(wqjob.submit()?); vtx_sub = Some(wqjob.submit()?); comp_sub = Some(wqjob.submit()?); raw.increase(job.notification_count); frag_sub.map(|a| gpu.run_job(a)); vtx_sub.map(|a| gpu.run_job(a)); comp_sub.map(|a| gpu.run_job(a));'
	check_batch_publication_contract(local, pending, reference)!
	for token in ['outer.validate_pointers(outer_rp, outer_wp)', 'pipes[pipe].outer_next == outer_rp',
		'free >= fw.g13_workqueue_entries', 'if !operation_active && !mgr.begin_g13_operation_locked() { return none }',
		'job.submitted = true',
		'katomic.store(mut &state.cpu_wptr, pipes[pipe].inner_next)'] {
		assert local.contains(token)
		if _ := check_batch_publication_contract(local.replace(token, ''), pending, reference) { assert false }
	}
	for token in ['if transferred != 0 { item.operation_active = true }', 'transferred & (u64(1) << index)',
		'command.compute_job, command.render_job = unsafe { nil }, unsafe { nil }'] {
		if _ := check_batch_publication_contract(local, pending.replace(token, ''), reference) { assert false }
	}
	if _ := check_batch_publication_contract(local, pending, reference.replace('comp_sub = Some(wqjob.submit()?)', 'skip')) { assert false }
	late := 'katomic.store(mut threshold,'
	if _ := check_batch_publication_contract(late + local.replace(late, ''), pending, reference) { assert false }
}

fn test_order_rejects_a_reversed_contract() {
	if _ := require_order('unmap flush reprotect', ['reprotect', 'unmap'], 'sample') {
		assert false
	} else {
		assert err.msg().contains('out-of-order')
	}
}

fn test_submission_pipelining_preserves_initial_guards_and_queue_fifo() {
	pending := os.read_file(os.join_path(g13layout.repo_root(), 'kernel/gpu/agx/file/pending.v'))!
	check_submission_pipelining(pending)!
	for broken in [pending.replace('entry.initial_barriers |= u32(1) << pipe', ''),
		pending.replace('earlier := queue.dispatch_blocked_in_poll', 'earlier := false'),
		pending.replace('queue.dispatch_blocked_in_poll = false', ''),
		pending.replace('!g13_pending_dispatch_complete(item)', 'false'),
		pending.replace('fn g13_pending_dispatch_complete(item &G13PendingSubmission) bool {',
			'fn g13_pending_dispatch_complete(item &G13PendingSubmission) bool { _ = item.callbacks_remaining')] {
		if _ := check_submission_pipelining(broken) { assert false, 'unsafe pipelining source contract accepted' }
	}
}

fn test_initial_snapshot_contract_rejects_pin_identity_and_acceptance_regressions() {
	repo := g13layout.repo_root()
	initial := os.read_file('${repo}/kernel/gpu/agx/gpu/g13_initial.v')!
	barriers := os.read_file('${repo}/kernel/gpu/agx/gpu/g13_barriers.v')!
	workqueue := os.read_file('${repo}/kernel/gpu/agx/event/workqueue.v')!
	manager := os.read_file('${repo}/kernel/gpu/agx/gpu/gpu.v')!
	check_initial_snapshot_contract(initial, barriers, workqueue, manager)!
	for broken in [initial.replace('value.valid && mgr.g13_events.initialized', 'value.valid'),
		initial.replace('voidptr(queue) != voidptr(owner)', 'queue != owner'),
		initial.replace('last.pipe != u32(pipe)', 'false'),
		initial.replace('owner.subqueues[0].events.ticket', 'owner.subqueues[1].events.ticket')] {
		if _ := check_initial_snapshot_contract(broken, barriers, workqueue, manager) { assert false }
	}
	if _ := check_initial_snapshot_contract(initial, barriers.replace('index < barriers.pin_count', 'index < barriers.count'), workqueue, manager) { assert false }
	if _ := check_initial_snapshot_contract(initial, barriers, workqueue.replace('queue.serial++', 'queue.serial--'), manager) { assert false }
	if _ := check_initial_snapshot_contract(initial, barriers, workqueue, manager.replace('mgr.accept_g13_submission_locked(jobs, count)', 'true')) { assert false }
}

fn test_input_dependency_contract_rejects_errno_propagation_and_early_release() {
	pending := os.read_file(os.join_path(g13layout.repo_root(), 'kernel/gpu/agx/file/pending.v'))!
	check_input_dependency_contract(pending)!
	for broken in [pending.replace('index < dependencies.count', 'index < 1'),
		pending.replace('!syncobj.queue_dependency_ready(dependencies.item(index).fence, queue_context)', 'false'),
		pending.replace('return false }\n\t}\n\treturn true', 'return false }\n\t}\n\t_ := syncobj.get_error(dependencies.item(0).fence)\n\treturn true'),
		pending.replace('if !g13_dependencies_ready(&item.dependencies, item.queue.fence_context) { return true }', ''),
		pending.replace('failure := g13_pending_error(item)', 'failure := 0')] {
		assert broken != pending
		if _ := check_input_dependency_contract(broken) { assert false, 'invalid input dependency policy accepted' }
	}
}

fn test_queue_fence_contract_rejects_reused_public_or_missing_identity() {
	repo := g13layout.repo_root()
	contexts := os.read_file('${repo}/kernel/drm/syncobj/queue.v')!
	fences := os.read_file('${repo}/kernel/drm/syncobj/syncobj.v')!
	queue := os.read_file('${repo}/kernel/gpu/agx/gpu/g13.v')!
	submit := os.read_file('${repo}/kernel/gpu/agx/file/file.v')!
	pending := os.read_file('${repo}/kernel/gpu/agx/file/pending.v')!
	check_queue_fence_contract(contexts, fences, queue, submit, pending)!
	for broken in [contexts.replace('queue_context != 0 && ', ''),
		contexts.replace('fence.queue_context == queue_context', 'fence.context == queue_context'),
		contexts.replace('if value == ~u64(0) { u64(0) } else { value + 1 }', 'value + 1')] {
		if _ := check_queue_fence_contract(broken, fences, queue, submit, pending) { assert false }
	}
	if _ := check_queue_fence_contract(contexts, fences.replace('queue_context u64', ''), queue, submit, pending) { assert false }
	if _ := check_queue_fence_contract(contexts, fences, queue.replace('fence_context: fence_context', 'fence_context: 0'), submit, pending) { assert false }
	if _ := check_queue_fence_contract(contexts, fences, queue, submit, pending.replace('queue.fence_context)', '1)')) { assert false }
	if _ := check_queue_fence_contract(contexts, fences, queue.replace('fence_seqno        u32', 'fence_seqno        u64'), submit, pending) { assert false }
	if _ := check_queue_fence_contract(contexts, fences, queue, submit, pending.replace('queue.next_fence_seqno()', '0')) { assert false }
	if _ := check_queue_fence_contract(contexts, fences, queue, submit, pending.replace('return fence\n}', 'return item.final_fence\n}')) { assert false }
	if _ := check_queue_fence_contract(contexts, fences, queue,
		submit.replace('install_output_syncs(output_syncs, fence)', 'install_output_syncs(output_syncs, pending.final_fence)'), pending) { assert false }
}

fn test_ring_admission_contract_rejects_gpu_only_space_and_missing_spare() {
	local := os.read_file(os.join_path(g13layout.repo_root(), 'kernel/gpu/agx/gpu/g13.v'))!
	reference := '    pub(crate) fn free_space(&self) -> usize { self.size as usize - self.pending.len() - 1 }\n    pub(crate) fn free_slots() {}\npub(crate) fn can_submit() { inner.free_space() > self.pending.len() }\npub(crate) fn submit() { inner.free_space() <= command_count }'
	check_ring_admission_contract(local, reference)!
	for broken in [local.replace('(published - retired) > u64(count)', '(published - retired) >= u64(count)'),
		local.replace('published > ~u64(0) - u64(count)', 'false'),
		local.replace('mgr.g13_ring_has_space_locked(queue.command_sequence, queue.retired_sequence, command_count)', 'true'),
		local.replace('mgr.g13_ring_has_space_locked(fragment_queue.command_sequence, fragment_queue.retired_sequence, 2)', 'true')] {
		assert broken != local
		if _ := check_ring_admission_contract(broken, reference) { assert false }
	}
	if _ := check_ring_admission_contract(local, reference.replace('self.pending.len()', 'gpu_doneptr')) { assert false }
}

fn test_event_admission_rejects_missing_spare_and_regressing_completion() {
	local := os.read_file(os.join_path(g13layout.repo_root(), 'kernel/gpu/agx/event/workqueue.v'))!
	reference := 'const MAX_JOB_SLOTS: u32 = 127\npub(crate) fn can_submit() { inner.free_slots() > self.event_count }\npub(crate) fn free_slots() { self.last_submitted; .last_completed; ls.delta(&lc); ((MAX_JOB_SLOTS as i32) - busy_slots).max(0) }'
	check_event_admission_contract(local, reference)!
	for broken in [local.replace('u32(free_slots) > count', 'u32(free_slots) >= count'),
		local.replace('admitted || queue.can_submit(1)', 'true'),
		local.replace('ticket.admitted = true', ''),
		local.replace('ticket.admitted = false', ''),
		local.replace('if !included { return false }', ''),
		local.replace('i32(values[index] - values[index - 1]) <= 0', 'false'),
		local.replace('i32(queue.published_value - queue.completed_value)', 'i32(value - queue.completed_value)'),
		local.replace('i32(value - queue.completed_value) > 0', 'true'),
		local.replace('queue.completed_value = value - u32(0x100)', 'queue.completed_value = 0'),
		local.replace('if submitted && ', 'if !submitted && ')] {
		assert broken != local
		if _ := check_event_admission_contract(broken, reference) { assert false }
	}
	if _ := check_event_admission_contract(local, reference.replace('> self.event_count', '>= self.event_count')) { assert false }
	credit := section(local, 'pub fn (mut queue WorkQueueEvents) record_completion(', 'pub fn (mut queue WorkQueueEvents) release(', 'credit unit')!
	for token in ['if !queue.owns_slot(slot)', 'ticket.active && ticket.value == value && ticket.published',
		'if i32(value - queue.completed_value) > 0 { queue.completed_value = value }', 'block = block.next'] {
		if _ := check_event_admission_contract(local.replace(credit, credit.replace(token, '')), reference) { assert false, token }
	}
	for token in ['queue.users--', 'ticket.active = false', 'memory.free(block)', 'release_stamp(slot)',
		'queue.published_value = value', 'queue.sequence = 0', 'queue.serial = 0', 'ticket.admitted = false'] {
		if _ := check_event_admission_contract(local.replace(credit, credit.replace_once('return true', token + '; return true')), reference) { assert false, token }
	}
}

fn test_prepared_backlog_rejects_fixed_hardware_cap_missing_rollback_and_early_free() {
	local := os.read_file(os.join_path(g13layout.repo_root(), 'kernel/gpu/agx/event/workqueue.v'))!
	reference := 'pub(crate) fn new_job() { inner.pending_jobs += 1; pending: KVec::new(); event_count: 0; } pub(crate) fn pipe_type() {}'
	check_prepared_backlog_contract(local, reference)!
	for token in ['value - queue.completed_value >= u32(0x80000000)', 'value - ticket.value >= u32(0x80000000)',
		'gpu_event_mgr.cancel_value(queue.slot, value)', 'tail.next = target', 'target.users++',
		'previous != unsafe { nil } && block.users == 0', 'previous.next = block.next', 'block = block.next'] {
		assert local.contains(token)
		if _ := check_prepared_backlog_contract(local.replace(token, ''), reference) { assert false }
	}
	if _ := check_prepared_backlog_contract(local.replace('if queue.users == ~u32(0)', 'if queue.users >= 127'), reference) { assert false }
	if _ := check_prepared_backlog_contract(local.replace('previous.next = block.next\n\t\t\t\tmemory.free(block)',
		'memory.free(block)\n\t\t\t\tprevious.next = block.next'), reference) { assert false }
	if _ := check_prepared_backlog_contract(local, reference.replace('inner.pending_jobs += 1', 'if free_slots() == 0 { return none }; inner.pending_jobs += 1')) { assert false }
}

fn test_batch_admission_rejects_partial_counts_and_lost_shutdown_gate() {
	local := os.read_file(os.join_path(g13layout.repo_root(), 'kernel/gpu/agx/gpu/g13_admission.v'))!
	pending := os.read_file(os.join_path(g13layout.repo_root(), 'kernel/gpu/agx/file/pending.v'))!
	reference := 'fn prepare() { sj_vtx.can_submit(); sj_frag.can_submit(); sj_comp.can_submit(); }'
	check_batch_admission_contract(local, pending, reference)!
	for token in ['index < count', 'voidptr(queue) != voidptr(owner)',
		'.events.ticket(job.vertex_event_slot, job.vertex_stamp_value)',
		'.events.ticket(job.fragment_event_slot, job.fragment_stamp_value)',
		'commands[2] += 1 + job.explicit_barriers.count', 'commands[1] += 2',
		'bound_blocks = block_count', '.events.can_submit(events[pipe])',
		'queue.subqueues[pipe].retired_sequence, commands[pipe])',
		'.events.admit(source.compute.event_slot, source.compute.stamp_value)',
		'.events.admit(source.render.fragment_event_slot, source.render.fragment_stamp_value)'] {
		assert local.contains(token)
		if _ := check_batch_admission_contract(local.replace(token, ''), pending, reference) { assert false }
	}
	for token in ['if !item.admitted', '_ = katomic.load(&item.callbacks_remaining)', 'item.admitted = true'] {
		assert pending.contains(token)
		if _ := check_batch_admission_contract(local, pending.replace(token, ''), reference) { assert false }
	}
	if _ := check_batch_admission_contract(local + '\njob.submitted = true', pending, reference) { assert false }
	if _ := check_batch_admission_contract(local, pending, reference.replace('sj_frag.can_submit()', 'sj_frag.run()')) { assert false }
}

fn test_integer_constant_accepts_v_casts_and_separators() {
	assert integer_constant('pub const aperture = u64(0xffff_ffae_1000_0000)', 'aperture', 'sample')! == u64(0xffffffae10000000)
	assert integer_constant('const blocks = u32(8)', 'blocks', 'sample')! == 8
	assert integer_constant('const blocks = u32(0x8)', 'blocks', 'sample')! == 8
	assert integer_constant('const blocks = 1_024', 'blocks', 'sample')! == 1024
}

fn test_checked_in_g13_contract_matches_local_m1n1() {
	if !os.is_dir(g13layout.default_m1n1()) { return }
	results := check_m1n1(g13layout.default_m1n1())!
	assert 'retry-safe reprotect/invalidate/unmap/invalidate teardown' in results
	assert 'TX ring entry barrier before write-pointer publication' in results
}

fn test_section_distinguishes_missing_start_and_terminator() {
	assert section('before START body END after', 'START', 'END', 'sample')! == 'START body '
	if _ := section('absent', 'START', 'END', 'sample') {
		assert false
	} else {
		assert err.msg() == "sample: missing 'START'"
	}
	if _ := section('START only', 'START', 'END', 'sample') {
		assert false
	} else {
		assert err.msg() == "sample: missing terminator 'END'"
	}
}

fn test_integer_constant_observes_word_boundaries_and_errors() {
	assert integer_constant('other_aperture = 0x12\naperture = 0x34', 'aperture', 'sample')! == 0x34
	if _ := integer_constant('aperture = value', 'aperture', 'sample') {
		assert false
	} else {
		assert err.msg() == 'sample: cannot find numeric constant aperture'
	}
}

fn test_asahi_contract_requires_teardown_and_publication_order() {
	fixture := os.join_path(os.temp_dir(), 'vinix-g13-contract-' + os.getpid().str())
	defer { os.rmdir_all(fixture) or { panic(err) } }
	directory := os.join_path(fixture, 'drivers/gpu/drm/asahi')
	os.mkdir_all(directory)!
	mmu := 'impl Drop for KernelMapping\nis_cached_noncoherent remap_uncached_and_flush unmap_pages tlbi_range\n/// Shared UAT global'
	channel := '    pub(crate) fn put\nself.ring.ring[self.wptr as usize] = *msg mem::sync() T::set_wptr\n    /// Wait for'
	workqueue := 'WorkError::Fault(info) if info.vm_slot != self.vm_slot => WorkError::Killed'
	os.write_file(os.join_path(directory, 'mmu.rs'), mmu)!
	os.write_file(os.join_path(directory, 'channel.rs'), channel)!
	os.write_file(os.join_path(directory, 'workqueue.rs'), workqueue)!
	assert check_asahi(fixture)! == ['Asahi KernelMapping cache-safe teardown order',
		'Asahi TX ring barrier before write-pointer publication', 'Asahi submitted work ASID for fault attribution']
	os.write_file(os.join_path(directory, 'mmu.rs'), mmu.replace('unmap_pages tlbi_range', 'tlbi_range unmap_pages'))!
	if _ := check_asahi(fixture) {
		assert false
	} else {
		assert err.msg() == "Asahi cache-safe unmap: missing or out-of-order 'tlbi_range'"
	}
	os.write_file(os.join_path(directory, 'mmu.rs'), mmu)!
	os.write_file(os.join_path(directory, 'channel.rs'), channel.replace('mem::sync() T::set_wptr', 'T::set_wptr mem::sync()'))!
	if _ := check_asahi(fixture) {
		assert false
	} else {
		assert err.msg() == "Asahi TX channel publication: missing or out-of-order 'T::set_wptr'"
	}
	os.write_file(os.join_path(directory, 'channel.rs'), channel)!
	os.write_file(os.join_path(directory, 'workqueue.rs'), workqueue.replace('self.vm_slot', 'vm.id'))!
	if _ := check_asahi(fixture) {
		assert false
	} else {
		assert err.msg() == 'Asahi fault routing must use the ASID recorded with the submitted work'
	}
}

fn test_unknown_checkout_revision_is_bounded_unknown() {
	assert git_revision('/nonexistent/vinix-g13-contract') == 'unknown'
}

fn test_gpu_tlbi_rejects_inner_shareable_instructions_and_missing_barriers() {
	reference := 'pub(crate) fn tlbi_all() { tlbi vmalle1os }\n/// Invalidate all TLB entries\n' +
		'pub(crate) fn tlbi_asid(asid: Asid) { tlbi aside1os ((asid as u64) << 48) }\n/// Invalidate a single page'
	vinix := 'pub fn invalidate_all() { dsb sy tlbi vmalle1os dsb sy memory }\n' +
		'pub fn invalidate_asid(asid u8) { u64(asid) << 48 dsb sy tlbi aside1os, operand dsb sy memory }'
	check_tlb_instructions(reference, vinix)!
	for broken in [vinix.replace('vmalle1os', 'vmalle1is'),
		vinix.replace('aside1os', 'aside1is'),
		vinix.replace('tlbi aside1os, operand dsb sy', 'tlbi aside1os, operand'),
		vinix.replace('u64(asid) << 48', 'u64(asid) << 56')] {
		if _ := check_tlb_instructions(reference, broken) {
			assert false, 'invalid GPU TLBI contract was accepted'
		}
	}
	if _ := check_tlb_instructions(reference.replace('aside1os', 'aside1is'), vinix) {
		assert false, 'reference drift was accepted'
	}
}
