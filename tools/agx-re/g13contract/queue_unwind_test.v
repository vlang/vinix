module g13contract

import g13layout

fn test_unreturned_queue_record_is_freed_only_after_successful_cleanup() {
	source := read(g13layout.repo_root() + '/kernel/gpu/agx/gpu/g13.v')!
	check_queue_unwind_local(source)!
	for token in ['if !complete {', 'if !mgr.free_g13_queue_resources_locked(mut resources, resources.mappings_published) {',
		'resources.quarantined = true', 'unsafe { *retained = resources }', 'unsafe { *retained = nil }',
		'unsafe { free(resources) }', 'complete = true'] {
		if _ := check_queue_unwind_local(source.replace(token, '')) { assert false, token }
	}
}
