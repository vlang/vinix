// SPDX-License-Identifier: GPL-2.0-or-later
module main
import os
import desktop.workflowcore

fn workflow_test_tree() string {
	path := os.real_path(os.temp_dir()) + '/vinix-documents-${os.getpid()}'
	os.rmdir_all(path) or {}
	os.mkdir_all(path) or { panic(err) }
	return path
}

fn test_shared_atomic_save_keeps_original_on_conflict_and_rejects_links() {
	root := workflow_test_tree()
	defer { os.rmdir_all(root) or {} }
	path := root + '/document'
	os.write_file(path, 'original')!
	os.chmod(path, 0o640)!
	original := workflowcore.identify(path)!
	workflowcore.atomic_save(path, 'saved'.bytes(), workflowcore.SaveOptions{expected: original})!
	assert os.read_file(path)! == 'saved'
	assert workflowcore.identify(path)!.mode & 0o777 == 0o640
	workflowcore.atomic_save(path, 'stale'.bytes(), workflowcore.SaveOptions{expected: original}) or {
		assert os.read_file(path)! == 'saved'
		return
	}
	assert false, 'stale save must be refused'
}

fn test_background_copy_cancel_checkpoint_resume_and_conflict() {
	root := workflow_test_tree()
	defer { os.rmdir_all(root) or {} }
	os.mkdir(root + '/destination')!
	bytes := []u8{len: 1024 * 1024, init: u8(index % 251)}
	os.write_file_array(root + '/source', bytes)!
	mut job := workflowcore.new_transfer([root + '/source'], root + '/destination', .copy)!
	job.tick()
	assert job.completed_bytes > 0 && !os.exists(root + '/destination/source')
	job.checkpoint(root + '/journal')!
	job.cancel()
	assert job.state == .cancelled
	job.close()
	mut resumed := workflowcore.resume_transfer(root + '/journal')!
	defer { resumed.close() }
	for _ in 0 .. 50 { if resumed.state != .running { break }; resumed.tick() }
	assert resumed.state == .complete, resumed.message
	assert os.read_bytes(root + '/destination/source')! == bytes
	mut conflict := workflowcore.new_transfer([root + '/source'], root + '/destination', .copy)!
	defer { conflict.close() }
	conflict.tick()
	assert conflict.state == .conflict
	conflict.resolve(.keep_both)
	for _ in 0 .. 50 { if conflict.state != .running { break }; conflict.tick() }
	assert conflict.state == .complete, conflict.message
	assert os.read_bytes(root + '/destination/source (1)')! == bytes
}

fn test_background_tree_copies_links_without_following_and_preserves_modes() {
	root := workflow_test_tree()
	defer { os.rmdir_all(root) or {} }
	os.mkdir_all(root + '/source/nested')!
	os.mkdir(root + '/destination')!
	os.write_file(root + '/source/nested/document', 'document')!
	os.chmod(root + '/source/nested/document', 0o640)!
	os.symlink('/does-not-exist', root + '/source/nested/link')!
	os.chmod(root + '/source/nested', 0o550)!
	mut job := workflowcore.new_transfer([root + '/source'], root + '/destination', .copy)!
	defer { job.close() }
	for _ in 0 .. 100 { if job.state != .running { break }; job.tick() }
	assert job.state == .complete, job.message
	assert os.read_file(root + '/destination/source/nested/document')! == 'document'
	assert os.is_link(root + '/destination/source/nested/link')
	assert workflowcore.identify(root + '/destination/source/nested')!.mode & 0o777 == 0o550
	os.chmod(root + '/source/nested', 0o700)!
	os.chmod(root + '/destination/source/nested', 0o700)!
}

fn test_shared_document_autosave_recovery_versions_and_external_save_conflict() {
	root := workflow_test_tree()
	defer { os.rmdir_all(root) or {} }
	path := root + '/document'
	os.write_file(path, 'first')!
	mut doc := workflowcore.new_document(root, path)!
	defer { doc.close() }
	assert doc.load(1000)!.bytestr() == 'first'
	doc.autosave('recovered draft'.bytes())!
	assert doc.recovery()!.bytes.bytestr() == 'recovered draft'
	doc.save('second'.bytes(), false)!
	assert os.read_file(path)! == 'second'
	versions := doc.versions()!
	assert versions.len == 1
	assert doc.version(versions[0], 1000)!.bytestr() == 'first'
	os.write_file(path, 'external')!
	doc.save('overwrite'.bytes(), false) or { assert os.read_file(path)! == 'external'; return }
	assert false, 'external edits must be preserved'
}
