module g13contract

import g13layout
import os

fn test_order_accepts_repeated_tokens() {
	require_order('flush reprotect flush unmap flush', ['flush', 'flush', 'flush'], 'sample')!
}

fn test_dependency_publication_rejects_callback_waits_and_missing_producer_gate() {
	source := os.read_file(os.join_path(g13layout.repo_root(), 'kernel/gpu/agx/file/pending.v'))!
	poll := section(source, 'fn poll_g13_pending(', '// Only the GPU worker consumes nodes.', 'test poll')!
	check_dependency_publication(poll)!
	for broken in [poll.replace('if !prior.published {', 'if !katomic.load(&prior.done) {'),
		poll.replace('if !prior.published {', 'if false {'),
		poll.replace('if !prior.published {', 'if !prior.published || !katomic.load(&prior.done) {'),
		poll.replace('if manager.state != .running { cancel_g13_pending(mut item, -19) }', '')] {
		if _ := check_dependency_publication(broken) { assert false, 'invalid dependency scheduling accepted' }
	}
}

fn test_order_rejects_a_reversed_contract() {
	if _ := require_order('unmap flush reprotect', ['reprotect', 'unmap'], 'sample') {
		assert false
	} else {
		assert err.msg().contains('out-of-order')
	}
}

fn test_submission_pipelining_preserves_initial_guards_and_bounded_fifo() {
	pending := os.read_file(os.join_path(g13layout.repo_root(), 'kernel/gpu/agx/file/pending.v'))!
	check_submission_pipelining(pending)!
	for broken in [pending.replace('item.initial_barriers |= u32(1) << pipe', ''),
		pending.replace('if gate >= 0 { unpublished[gate] }', 'if gate >= 0 { unpublished[gate] || item.initial_barriers != 0 }'),
		pending.replace('if gate < 0 && blocked_count < 128', 'if gate < 0'),
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
		pending.replace('!syncobj.queue_dependency_ready(dependencies.fences[index], queue_context)', 'false'),
		pending.replace('return false }\n\t}\n\treturn true', 'return false }\n\t}\n\t_ := syncobj.get_error(dependencies.fences[0])\n\treturn true'),
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
	check_queue_fence_contract(contexts, fences, queue, submit)!
	for broken in [contexts.replace('queue_context != 0 && ', ''),
		contexts.replace('fence.queue_context == queue_context', 'fence.context == queue_context'),
		contexts.replace('if value == ~u64(0) { u64(0) } else { value + 1 }', 'value + 1')] {
		if _ := check_queue_fence_contract(broken, fences, queue, submit) { assert false }
	}
	if _ := check_queue_fence_contract(contexts, fences.replace('queue_context u64', ''), queue, submit) { assert false }
	if _ := check_queue_fence_contract(contexts, fences, queue.replace('fence_context: fence_context', 'fence_context: 0'), submit) { assert false }
	if _ := check_queue_fence_contract(contexts, fences, queue, submit.replace('queue_resources.fence_context)', 'u64(request.queue_id))')) { assert false }
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
	os.write_file(os.join_path(directory, 'mmu.rs'), mmu)!
	os.write_file(os.join_path(directory, 'channel.rs'), channel)!
	assert check_asahi(fixture)! == ['Asahi KernelMapping cache-safe teardown order',
		'Asahi TX ring barrier before write-pointer publication']
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
