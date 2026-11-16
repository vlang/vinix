// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_asahi_sync_lookup_contract(staging string, caller string, rust string, asahi string) ! {
	stage := section(staging, 'pub fn stage_sync_array(', 'pub fn install_output_syncs(', 'Native sync lookup errors')!
	require_order(stage, ['item.extensions != 0', 'return -22, SyncArray{}',
		'object := syncobj.lookup(owner, item.handle) or { return -2, SyncArray{} }',
		'if input', 'syncobj.get_timeline_fence(object, item.timeline_value)', 'return -22, SyncArray{}',
		'syncobj.get_fence(object) or { return -22, SyncArray{} }', 'return 0, SyncArray{'],
		'Missing syncobj is ENOENT after validation; a missing input fence remains EINVAL')!
	require_order(caller, ['input_syncs := agxsubmission.stage_sync_array(', 'if sync_result != 0 { return sync_result }',
		'output_syncs := agxsubmission.stage_sync_array(', 'if output_result != 0 { return output_result }'],
		'Input/output staging errors must propagate before backend effects')!
	lookup := section(rust, 'pub fn lookup_handle', '/// Returns the DMA fence', 'Asahi Rust object lookup')!
	require_order(lookup, ['bindings::drm_syncobj_find(', 'if ptr.is_null()', 'Err(ENOENT)', 'Ok(SyncObj { ptr })'],
		'Packaged Rust lookup returns ENOENT for an absent handle')!
	parse := section(asahi, 'impl SyncItem {', 'fn parse_array(', 'Asahi per-item parsing')!
	require_order(parse, ['Non-timeline sync object with a nonzero value', 'return Err(EINVAL)',
		'SyncObj::lookup_handle(file, data.handle)?', 'syncobj.fence_get().ok_or_else', 'EINVAL',
		'DRM_ASAHI_SYNC_TIMELINE_SYNCOBJ =>', 'SyncObj::lookup_handle(file, data.handle)?', 'Failed to get fence from timeline sync object', 'EINVAL'],
		'Packaged Asahi distinguishes absent objects from empty input fences')!
}
