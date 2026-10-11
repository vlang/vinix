// SPDX-License-Identifier: GPL-2.0-or-later
module main
import os
import desktop.workflowcore

fn test_index_returns_named_folders_with_tags_and_live_permission_guards() {
	root := os.real_path(os.temp_dir()) + '/vinix-folder-index-' + C.getpid().str()
	os.mkdir_all(root + '/Projects')!
	defer { os.chmod(root + '/Projects', 0o700) or {}; os.rmdir_all(root) or {} }
	mut index := workflowcore.SearchIndex{}
	defer { index.close() }
	index.begin([workflowcore.SearchRoot{path: root, identity: workflowcore.identify(root)!, enabled: true, contents: true}])
	for index.indexing { index.tick() }
	index.set_tags(root + '/Projects', ['Work'])
	assert index.query('projects type:folder tag:work', 10) == [root + '/Projects']
	os.chmod(root + '/Projects', 0o600)!
	assert index.query('projects', 10).len == 0
}

fn test_index_content_metadata_policy_revocation_and_volume_replacement() {
	root := os.real_path(os.temp_dir()) + '/vinix-index-${os.getpid()}'
	os.mkdir_all(root + '/remote')!
	defer { os.rmdir_all(root) or {} }
	os.write_file(root + '/report.txt', 'the purple elephant')!
	os.write_file(root + '/remote/secret.txt', 'purple secret')!
	mut index := workflowcore.SearchIndex{}
	defer { index.close() }
	index.begin([
		workflowcore.SearchRoot{path: root, identity: workflowcore.identify(root)!, enabled: true, contents: true},
		workflowcore.SearchRoot{path: root + '/remote', identity: workflowcore.identify(root + '/remote')!, network: true},
	])
	for _ in 0 .. 100 { if !index.indexing { break }; index.tick() }
	assert index.query('purple', 20) == [root + '/report.txt']
	index.set_tags(root + '/report.txt', ['Work'])
	assert index.query('type:txt tag:work size:10', 20).len == 1
	index.save(root)!
	mut cached := workflowcore.load_index(root)!
	defer { cached.close() }
	assert cached.query('elephant', 20).len == 1
	cached.roots[0].contents = false
	assert cached.query('elephant', 20).len == 0
	assert cached.query('report', 20).len == 1
	cached.roots[0].contents = true
	os.chmod(root + '/report.txt', 0o000)!
	assert cached.query('elephant', 20).len == 0
	os.chmod(root + '/report.txt', 0o600)!
	os.rename(root + '/remote', root + '/disconnected')!
	os.mkdir(root + '/remote')!
	assert cached.query('secret', 20).len == 0
}

fn test_background_publication_honors_policy_changes_made_during_indexing() {
	root := os.real_path(os.temp_dir()) + '/vinix-index-policy-${C.getpid()}'
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	os.write_file(root + '/report.txt', 'ConfidentialIndexedPhrase')!
	mut current := workflowcore.SearchIndex{}
	defer { current.close() }
	current.begin([workflowcore.SearchRoot{path: root, identity: workflowcore.identify(root)!, enabled: true, contents: true}])
	for current.indexing { current.tick() }
	current.save(root)!
	mut worker := workflowcore.SearchIndex{}
	defer { worker.close() }
	worker.begin(current.roots)
	for worker.indexing { worker.tick() }
	current.roots[0].contents = false
	current.save(root)!
	worker.publish(root)!
	assert worker.query('confidentialindexedphrase', 10).len == 0
	assert worker.query('report', 10).len == 1
	assert worker.records[0].content.len == 0
	mut cached := workflowcore.load_index(root)!
	defer { cached.close() }
	assert !cached.roots[0].contents && cached.records[0].content == ''
}
