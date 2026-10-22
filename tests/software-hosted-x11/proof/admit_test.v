module proof

import os

fn test_complete_inventory_rejects_added_mutated_and_retargeted_inputs() {
	root := os.join_path(os.temp_dir(), 'vinix-x11-proof-' + os.getpid().str())
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	os.write_file(root + '/original.v', 'module fixture\n')!
	os.write_file(root + '/other.v', 'module alternative\n')!
	os.symlink('original.v', root + '/selected.v')!
	before := tree(root, false)!
	tree_unchanged(root, false, before)!
	os.write_file(root + '/added.v', 'module added\n')!
	if _ := tree_unchanged(root, false, before) { assert false } else { assert err.msg().contains('complete input tree changed') }
	os.rm(root + '/added.v')!
	os.write_file(root + '/original.v', 'module changed\n')!
	if _ := tree_unchanged(root, false, before) { assert false } else { assert err.msg().contains('complete input tree changed') }
	os.write_file(root + '/original.v', 'module fixture\n')!
	os.rm(root + '/selected.v')!
	os.symlink('other.v', root + '/selected.v')!
	if _ := tree_unchanged(root, false, before) { assert false } else { assert err.msg().contains('complete input tree changed') }
}

fn test_frozen_source_inventory_rejects_additional_source() {
	root := os.join_path(os.temp_dir(), 'vinix-x11-sources-' + os.getpid().str())
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	os.write_file(root + '/original.v', 'module fixture\n')!
	before := tree(root, true)!
	os.write_file(root + '/ignored.log', 'unconsumed diagnostic\n')!
	copied_sources(root, before)!
	os.write_file(root + '/extra.v', 'module fixture\n')!
	if _ := copied_sources(root, before) { assert false } else { assert err.msg().contains('frozen source inventory differs') }
}

fn test_archived_build_sources_are_exact_and_reject_ambiguous_mapping() {
	root := os.join_path(os.temp_dir(), 'vinix-x11-archive-' + os.getpid().str())
	os.mkdir_all(root + '/source/tools')!
	defer { os.rmdir_all(root) or {} }
	path := archived_build_path(root, 'source/tools/example.v', '/original/tools/example.v')!
	assert path == root + '/source/tools/example.v'
	os.write_file(path, 'module original\n')!
	expected := digest(path)!
	verify(path, expected, 'archive baseline')!
	os.write_file(path, 'module changed\n')!
	if _ := verify(path, expected, 'archive changed') { assert false } else { assert err.msg().contains('assembled input digest differs') }
	os.rm(path)!
	if _ := verify(path, expected, 'archive absent') { assert false } else { assert err.msg() != '' }
	for bad in ['source/', 'source/../example.v', 'source//example.v', 'source/./example.v', 'source/a/../../example.v', 'source/a\\example.v', 'source/a\x00example.v'] {
		if _ := archived_build_path(root, bad, '/original/example.v') { assert false } else { assert err.msg() == 'invalid archived desktop source path' }
	}
	assert archived_build_path(root, 'compiler', '/original/compiler')! == '/original/compiler'
	if _ := archived_build_path(root, 'source/a.v', 'relative/a.v') { assert false } else { assert err.msg() == 'invalid original desktop input path' }
}
