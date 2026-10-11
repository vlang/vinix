// SPDX-License-Identifier: GPL-2.0-or-later
module main
import os
import desktop.workflowcore

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
	os.chmod(root + '/report.txt', 0o000)!
	assert cached.query('elephant', 20).len == 0
	os.chmod(root + '/report.txt', 0o600)!
	os.rename(root + '/remote', root + '/disconnected')!
	os.mkdir(root + '/remote')!
	assert cached.query('secret', 20).len == 0
}
