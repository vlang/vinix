module g13contract

import g13layout

fn test_sync_lookup_guard_rejects_errno_collapse_and_dropped_error_propagation() {
	repo := g13layout.repo_root()
	staging := read(repo + '/kernel/gpu/agx/submission/submission.v')!
	caller := read(repo + '/kernel/gpu/agx/file/file.v')!
	rust := 'pub fn lookup_handle { bindings::drm_syncobj_find(); if ptr.is_null() { Err(ENOENT) } else { Ok(SyncObj { ptr }) } }\n/// Returns the DMA fence'
	asahi := 'impl SyncItem {\nNon-timeline sync object with a nonzero value; return Err(EINVAL);\n' +
		'SyncObj::lookup_handle(file, data.handle)?; syncobj.fence_get().ok_or_else(|| EINVAL);\n' +
		'DRM_ASAHI_SYNC_TIMELINE_SYNCOBJ => SyncObj::lookup_handle(file, data.handle)?; Failed to get fence from timeline sync object; EINVAL;\nfn parse_array('
	check_asahi_sync_lookup_contract(staging, caller, rust, asahi)!
	for token in ['or { return -2, SyncArray{} }', 'syncobj.get_fence(object) or { return -22, SyncArray{} }'] {
		if _ := check_asahi_sync_lookup_contract(staging.replace(token, ''), caller, rust, asahi) { assert false, token }
	}
	for token in ['if sync_result != 0 { return sync_result }', 'if output_result != 0 { return output_result }'] {
		if _ := check_asahi_sync_lookup_contract(staging, caller.replace(token, ''), rust, asahi) { assert false, token }
	}
	if _ := check_asahi_sync_lookup_contract(staging, caller, rust.replace('ENOENT', 'EINVAL'), asahi) { assert false }
}
