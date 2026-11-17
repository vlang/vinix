// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import g13layout

fn check_timeline_signal_contract(drm string, wire string, signal string, stub string) ! {
	require(integer_constant(wire, 'drm_ioctl_syncobj_timeline_signal', 'Timeline SIGNAL opcode')! == 0xcd, 'Timeline SIGNAL opcode')!
	require_order(drm.all_after('fn common_ioctl_layout('), ['ioctl.drm_ioctl_syncobj_timeline_signal {',
		'size: u32(sizeof(ioctl.DrmSyncobjTimelineArray)), direction: ioctl_write | ioctl_read'], 'Timeline SIGNAL registration')!
	require_order(drm.all_after('fn core_ioctl('), ['ioctl.drm_ioctl_syncobj_timeline_signal {',
		'return ioctl_syncobj_timeline_signal(handle, data)'], 'Timeline SIGNAL dispatch')!
	require_order(drm.all_after('pub fn register_driver('), ['syncobj.shared_timeline_stub()', 'drm_devices_lock.acquire()'], 'Permanent completion initialized during DRM startup')!
	require_order(signal, ['request.flags != 0 || request.count_handles == 0', 'new_syncobj_handle_buffer(count)',
		'defer { buffer.free_owned() }', 'usercopy.copy_from_user(buffer.handles', 'syncobj.lookup(',
		'buffer.objects[index] = voidptr(object)', 'points_storage := memory.malloc_packed_fallible(bytes)',
		'defer { memory.free(points_storage) }', 'if request.points == 0', 'C.memset(points_storage, 0, bytes)',
		'usercopy.copy_from_user(points_storage', 'chains_storage := memory.malloc_packed_fallible(',
		'defer { memory.free(chains_storage) }', 'C.memset(chains_storage, 0,',
		'syncobj.release_chain_reservation(unsafe { chains[index] })', 'syncobj.reserve_chain() or { return -12 }',
		'chains[index] = chain', 'payload := syncobj.shared_timeline_stub()', 'syncobj.add_chain_point('],
		'All records and chain reservations before publication; reverse cleanup order')!
	require(signal.count('memory.malloc_packed_fallible(') == 2 && !signal.contains('new_private_stub(')
		&& !signal.contains('syncobj.signal(') && !signal.contains('syncobj.replace_fence('), 'Timeline signal must preserve previous prefixes with permanent payloads')!
	require_order(stub, ['__global timeline_stub_completion = DmaFence{}', 'pub fn shared_timeline_stub()',
		'timeline_stub_lock.acquire()', 'if !timeline_stub_completion.signaled', 'private_stub = true',
		'timestamp_ns = now_ns()', 'katomic.store(mut &timeline_stub_completion.signaled, true)',
		'timeline_stub_lock.release()', 'return unsafe { &timeline_stub_completion }'], 'Stable permanently owned completion')!
	require(!stub.contains('memory.') && !stub.contains('new_private_stub('), 'Shared completion must allocate nothing')!
}

fn test_timeline_signal_rejects_early_publication_missing_cleanup_and_private_payloads() {
	repo := g13layout.repo_root()
	drm := read(repo + '/kernel/drm/drm.v')!
	wire := read(repo + '/kernel/drm/ioctl/ioctl.v')!
	signal := read(repo + '/kernel/drm/syncobj_timeline_signal.v')!
	stub := read(repo + '/kernel/drm/syncobj/timeline_stub.v')!
	check_timeline_signal_contract(drm, wire, signal, stub)!
	for token in ['defer { buffer.free_owned() }', 'defer { memory.free(points_storage) }',
		'defer { memory.free(chains_storage) }', 'C.memset(chains_storage, 0,',
		'syncobj.release_chain_reservation(unsafe { chains[index] })', 'chains[index] = chain'] {
		if _ := check_timeline_signal_contract(drm, wire, signal.replace(token, ''), stub) { assert false, token }
	}
	if _ := check_timeline_signal_contract(drm, wire, signal + '\nsyncobj.replace_fence(', stub) { assert false }
	if _ := check_timeline_signal_contract(drm, wire, signal, stub.replace('timeline_stub_lock.acquire()', '')) { assert false }
	if _ := check_timeline_signal_contract(drm, wire, signal, stub.replace('if !timeline_stub_completion.signaled', 'if true')) { assert false }
}
