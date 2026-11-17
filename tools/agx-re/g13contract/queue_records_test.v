module g13contract

import g13layout

fn test_final_queue_records_wait_for_every_owner_and_cleanup_gate() {
	root := g13layout.repo_root()
	file := read(root + '/kernel/gpu/agx/file/file.v')!
	queues := read(root + '/kernel/gpu/agx/gpu/g13.v')!
	check_queue_records_local(file, queues)!
	for token in ['!resources.has_file_references()', 'resources.context_next == unsafe { nil }', 'unsafe { free(resources) }', '} @[freed]\n\tmut complete := false'] {
		if _ := check_queue_records_local(file, queues.replace(token, '')) { assert false, token }
	}
	for token in ['if ownership.resources.has_file_references() { f.lock.release(); return false }',
		'|| f.g13_queues.len != 0', 'gpu.free_g13_queue_record(ownership.resources)'] {
		if _ := check_queue_records_local(file.replace(token, ''), queues) { assert false, token }
	}
}
