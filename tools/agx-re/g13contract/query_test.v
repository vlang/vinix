// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import g13layout

fn check_query_contract(drm string, wire string, query string, chain string) ! {
	require(integer_constant(wire, 'drm_ioctl_syncobj_query', 'QUERY opcode')! == 0xcb, 'QUERY opcode')!
	require_order(wire.all_after('pub struct DrmSyncobjTimelineArray {'), ['handles       u64', 'points        u64', 'count_handles u32', 'flags         u32'], '24-byte QUERY layout')!
	require_order(drm.all_after('fn common_ioctl_layout('), ['ioctl.drm_ioctl_syncobj_query {',
		'size: u32(sizeof(ioctl.DrmSyncobjTimelineArray))', 'direction: ioctl_write | ioctl_read'], 'QUERY registration')!
	require_order(drm.all_after('fn core_ioctl('), ['ioctl.drm_ioctl_syncobj_query {', 'return ioctl_syncobj_query(handle, data)'], 'QUERY dispatch')!
	require_order(query, ['request.flags & ~ioctl.drm_syncobj_query_last_submitted != 0', 'request.count_handles == 0',
		'if count > 64', 'new_syncobj_handle_buffer(count)', 'defer { buffer.free_owned() }',
		'usercopy.copy_from_user(buffer.handles', 'syncobj.lookup(', 'buffer.objects[index] = voidptr(object)',
		'for index := u32(0); index < count; index++', 'syncobj.query_timeline_point(',
		'usercopy.copy_to_user(points + offset, unsafe { &point }, sizeof(point))'], 'QUERY validation, snapshots, per-entry outputs and owner cleanup')!
	require_order(chain.all_after('pub fn query_timeline_point('), ['get_fence(obj)', 'if !fence.chain { return 0 }',
		'if last_submitted { return fence.seqno }', 'cursor.chain_context != fence.chain_context',
		'last = unsafe { cursor }', 'cursor = chain_previous(cursor)',
		'if is_signaled(last) { last.seqno } else { last.chain_prev_seqno }'], 'Submitted versus completed prefix and unordered boundary')!
}

fn check_timeline_capability_contract(drm string, native string, fake string) ! {
	require_order(drm.all_after('fn core_ioctl('), ['ioctl.drm_ioctl_get_cap {', 'return ioctl_get_cap(dev, data)'],
		'GET_CAP dispatch uses the registered device')!
	cap := section(drm, 'fn ioctl_get_cap(', 'fn ioctl_gem_close(', 'DRM capability reporting')!
	require_order(cap, ['ioctl.drm_cap_syncobj_timeline {', 'dev.driver.features & driver_syncobj_timeline != 0',
		'return 0'], 'DRM timeline capability follows the registered device')!
	require_order(native, ['if !mgr.init(receive_irq, send_irq)', 'base_m1 := chip_id == 0x8103',
		'mut features := drm.driver_gem | drm.driver_render | drm.driver_compute',
		'if base_m1 {', 'features |= drm.driver_syncobj_timeline', '}',
		'agx_drm_driver := &drm.DrmDriver{', 'features: features', 'drm.register_driver_with_data(agx_drm_driver, voidptr(mgr))'],
		'Native base M1 enables timeline discovery after firmware initialization')!
	require(!fake.contains('drm.driver_syncobj_timeline'), 'The fake backend uses a sparse point map')!
}

fn test_timeline_capability_is_native_base_m1_only() {
	repo := g13layout.repo_root()
	drm := read(repo + '/kernel/drm/drm.v')!
	native := read(repo + '/kernel/gpu/agx/driver/driver.v')!
	fake := read(repo + '/kernel/gpu/agx/fake/driver.v')!
	check_timeline_capability_contract(drm, native, fake)!
	if _ := check_timeline_capability_contract(drm.replace('dev.driver.features & driver_syncobj_timeline != 0', 'true'), native, fake) { assert false }
	if _ := check_timeline_capability_contract(drm, native.replace('base_m1 := chip_id == 0x8103', 'base_m1 := true'), fake) { assert false }
	if _ := check_timeline_capability_contract(drm, native.replace('features |= drm.driver_syncobj_timeline', ''), fake) { assert false }
	if _ := check_timeline_capability_contract(drm, native, fake + '\ndrm.driver_syncobj_timeline') { assert false }
}

fn test_query_rejects_dispatch_layout_progress_cleanup_and_snapshot_drift() {
	repo := g13layout.repo_root()
	drm := read(repo + '/kernel/drm/drm.v')!
	wire := read(repo + '/kernel/drm/ioctl/ioctl.v')!
	query := read(repo + '/kernel/drm/syncobj_query.v')!
	chain := read(repo + '/kernel/drm/syncobj/chain.v')!
	check_query_contract(drm, wire, query, chain)!
	for token in ['request.count_handles == 0', 'defer { buffer.free_owned() }',
		'buffer.objects[index] = voidptr(object)', 'usercopy.copy_to_user(points + offset, unsafe { &point }, sizeof(point))'] {
		if _ := check_query_contract(drm, wire, query.replace(token, ''), chain) { assert false, token }
	}
	for token in ['if last_submitted { return fence.seqno }', 'cursor.chain_context != fence.chain_context',
		'last.chain_prev_seqno', 'cursor = chain_previous(cursor)'] {
		if _ := check_query_contract(drm, wire, query, chain.replace(token, '')) { assert false, token }
	}
	if _ := check_query_contract(drm.replace('return ioctl_syncobj_query(handle, data)', ''), wire, query, chain) { assert false }
	if _ := check_query_contract(drm, wire.replace('drm_ioctl_syncobj_query = u32(0xcb)', 'drm_ioctl_syncobj_query = u32(0xcc)'), query, chain) { assert false }
}
