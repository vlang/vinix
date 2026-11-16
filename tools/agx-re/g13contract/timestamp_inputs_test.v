module g13contract

import g13layout

fn test_resolved_timestamp_destinations_require_independent_selection_and_post_conversion_writes() {
	native := read(g13layout.repo_root() + '/kernel/gpu/agx/gpu/g13.v')!
	check_timestamp_inputs_local(native)!
	for token in ['|| vertex_user_timestamps[1] != 0', '|| fragment_user_timestamps[0] != 0',
		'|| user_timestamps[1] != 0', 'if vertex_timestamps {', 'if fragment_timestamps {',
		'if compute_timestamps {', 'write_g13_timestamp_pair(voidptr(u64(job.fragment.cpu_address()) + fragment_user_ts_offset), fragment_user_timestamps)'] {
		if _ := check_timestamp_inputs_local(native.replace(token, '')) { assert false, token }
	}
}
