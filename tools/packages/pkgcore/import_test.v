// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os

fn C.mkfifo(&char, u32) int

fn import_scratch(label string) !string {
	path := os.temp_dir() + '/vinix-import-' + label + '-' + os.getpid().str()
	os.mkdir_all(path)!
	return path
}

fn root_recipe(entries []RootEntry) RootRecipe {
	return RootRecipe{
		manifest: Package{
			id:           'imported'
			version:      '1.0.0'
			architecture: 'aarch64'
			name:         'Imported runtime'
			license:      'MIT'
			kind:         'runtime'
		}
		entries:  entries
	}
}

fn test_guest_root_import_materializes_aliases_without_host_resolution() {
	work := import_scratch('valid')!
	defer { os.rmdir_all(work) or {} }
	root := work + '/root'
	os.mkdir_all(root + '/usr/lib')!
	os.mkdir_all(root + '/opt')!
	os.write_file(root + '/usr/lib/libfixture.so.1', 'guest library')!
	os.chmod(root + '/usr/lib/libfixture.so.1', 0o4755)!
	os.symlink('libfixture.so.1', root + '/usr/lib/libfixture.so')!
	os.symlink('/usr/lib', root + '/lib')!
	os.symlink('../lib/libfixture.so', root + '/opt/relative')!
	recipe := root_recipe([RootEntry{ source: 'lib', path: 'lib' },
		RootEntry{ source: 'opt/relative', path: 'bin/alias' }])
	os.write_file(work + '/recipe.json', json2.encode(recipe))!
	first := pack_root(work + '/recipe.json', root, work + '/repository')!
	assert first.files.len == 3
	assert first.files.all(it.sha256 == first.files[0].sha256 && it.executable)
	assert first.files.map(it.path) == ['bin/alias', 'lib/libfixture.so', 'lib/libfixture.so.1']
	assert os.is_link(root + '/lib') && os.is_link(root + '/opt/relative')
	assert read_metadata(root + '/usr/lib/libfixture.so.1')! == 'guest library'
	// Selector order and symlink versus ordinary source do not change metadata.
	second_recipe := root_recipe([
		RootEntry{ source: 'usr/lib/libfixture.so.1', path: 'bin/alias' },
		RootEntry{ source: 'usr/lib', path: 'lib' },
	])
	os.write_file(work + '/second.json', json2.encode(second_recipe))!
	second := pack_root(work + '/second.json', root, work + '/second-repository')!
	assert first == second
	// Parent components apply after an intermediate symlink has been followed.
	os.mkdir_all(root + '/real/deep')!
	os.write_file(root + '/real/value', 'resolved parent')!
	os.symlink('/real/deep', root + '/opt/intermediate')!
	os.symlink('intermediate/../value', root + '/opt/parent')!
	os.write_file(work + '/parent.json', json2.encode(root_recipe([
		RootEntry{ source: 'opt/parent', path: 'value' },
	])))!
	parent := pack_root(work + '/parent.json', root, work + '/parent-repository')!
	assert parent.files.len == 1
	assert read_metadata(work + '/parent-repository/objects/' + parent.files[0].sha256)! == 'resolved parent'
}

fn test_guest_root_import_rejects_cycles_special_files_and_overlapping_output() {
	work := import_scratch('invalid')!
	defer { os.rmdir_all(work) or {} }
	root := work + '/root'
	os.mkdir_all(root + '/dir')!
	os.symlink('../..', root + '/dir/escape')!
	os.symlink('cycle-b', root + '/cycle-a')!
	os.symlink('cycle-a', root + '/cycle-b')!
	os.symlink('/dir', root + '/dir/again')!
	assert C.mkfifo((root + '/pipe').str, 0o600) == 0
	for path in ['dir/escape', 'cycle-a', 'dir', 'pipe'] {
		os.write_file(work + '/recipe.json', json2.encode(root_recipe([RootEntry{ source: path, path: 'payload' }])))!
		mut refused := false
		pack_root(work + '/recipe.json', root, work + '/repository') or { refused = true }
		assert refused, path
		assert !os.exists(work + '/repository/manifests')
	}
	for entries in [[RootEntry{ source: '../host', path: 'bin/app' }],
		[RootEntry{ source: 'dir', path: '/absolute' }],
		[RootEntry{ source: 'dir', path: 'lib' }, RootEntry{ source: 'dir', path: 'lib/nested' }]] {
		os.write_file(work + '/recipe.json', json2.encode(root_recipe(entries)))!
		mut refused := false
		pack_root(work + '/recipe.json', root, work + '/repository') or { refused = true }
		assert refused
	}
}
