module g13contract

import g13layout

fn test_queue_references_require_initial_capture_transfer_and_final_release() {
	root := g13layout.repo_root()
	file := read(root + '/kernel/gpu/agx/file/file.v')!
	pending := read(root + '/kernel/gpu/agx/file/pending.v')!
	gpu := read(root + '/kernel/gpu/agx/gpu/g13.v')!
	vfs := read(root + '/kernel/fs/vfs.v')!
	check_queue_reference_local(file, pending, gpu, vfs)!
	for token in ['resources.retain_file_reference()', 'release_submission_queue(captured)',
		'usc_base: queue.usc_base', 'mut queue_resources := unsafe { captured.resources }',
		'transferred = true', 'katomic.inc(mut &pending.vm.inflight)'] {
		if _ := check_queue_reference_local(file.replace(token, ''), pending, gpu, vfs) { assert false, token }
	}
	if _ := check_queue_reference_local(file, pending.replace('queue.release_file_reference()', ''), gpu, vfs) { assert false }
	if _ := check_queue_reference_local(file, pending, gpu.replace('if owned.has_file_references() { return false }', ''), vfs) { assert false }
	if _ := check_queue_reference_local(file, pending, gpu, vfs.replace('fd.unref()', '')) { assert false }
}
