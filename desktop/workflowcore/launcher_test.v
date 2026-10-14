// SPDX-License-Identifier: GPL-2.0-or-later
module workflowcore

import os

fn launcher_test_home(name string) string {
	temporary := os.real_path(os.temp_dir())
	pid := os.getpid().str()
	defer { unsafe { temporary.free(); pid.free() } }
	path := temporary + '/vinix-launcher-' + name + '-' + pid
	os.rmdir_all(path) or {}
	os.mkdir_all(path) or { panic(err) }
	return path
}

fn launcher_test_free_results(paths []string) {
	unsafe { paths.free() }
}

fn test_launcher_folders_precede_documents_and_match_parent_components() {
	home := launcher_test_home('folders')
	defer { os.rmdir_all(home) or {} }
	os.mkdir_all(home + '/Projects/Design Notes')!
	os.write_file(home + '/projects.txt', 'document')!
	mut index := SearchIndex{}
	index.begin([SearchRoot{path: home, identity: identify(home)!, enabled: true, contents: true}])
	for index.indexing { index.tick() }
	defer { index.close() }
	paths := index.launcher_query('projects', home, 10)
	defer { launcher_test_free_results(paths) }
	assert paths.len == 3
	assert paths[0] != home + '/projects.txt'
	assert paths[1] != home + '/projects.txt'
	assert paths[2] == home + '/projects.txt'
	nested := index.launcher_query('PROJECTS/DESIGN', home, 7)
	defer { launcher_test_free_results(nested) }
	assert nested == [home + '/Projects/Design Notes']
	limited := index.launcher_query('projects', home, 1)
	defer { launcher_test_free_results(limited) }
	assert limited.len == 1 && limited[0] != home + '/projects.txt'
}

fn test_launcher_preserves_document_content_filters_and_root_policy() {
	home := launcher_test_home('policy')
	defer { os.rmdir_all(home) or {} }
	os.mkdir(home + '/Projects')!
	os.write_file(home + '/meeting.txt', 'uniquelysearchabledocument')!
	mut index := SearchIndex{}
	index.begin([SearchRoot{path: home, identity: identify(home)!, enabled: true, contents: true}])
	for index.indexing { index.tick() }
	defer { index.close() }
	content := index.launcher_query('uniquelysearchabledocument type:txt', home, 7)
	defer { launcher_test_free_results(content) }
	assert content == [home + '/meeting.txt']
	index.roots[0].contents = false
	no_content := index.launcher_query('uniquelysearchabledocument', home, 7)
	defer { launcher_test_free_results(no_content) }
	assert no_content.len == 0
	index.roots[0].enabled = false
	excluded := index.launcher_query('projects', home, 7)
	defer { launcher_test_free_results(excluded) }
	assert excluded.len == 0
}

fn test_launcher_explicit_paths_find_unindexed_directories_and_home() {
	base := launcher_test_home('paths')
	defer { os.rmdir_all(base) or {} }
	home := base + '/Home'
	os.mkdir_all(home + '/Documents')!
	os.mkdir_all(base + '/External/Workspace')!
	os.mkdir_all(base + '/External/Workshop')!
	os.write_file(base + '/External/Work.txt', 'not a directory')!
	os.symlink(base + '/External/Workspace', base + '/External/Work Link')!
	index := SearchIndex{}
	home_result := index.launcher_query('~', home, 7)
	defer { launcher_test_free_results(home_result) }
	assert home_result == [home]
	relative := index.launcher_query('~/Doc', home, 7)
	defer { launcher_test_free_results(relative) }
	assert relative == [home + '/Documents']
	exact := index.launcher_query(base + '/External/Workspace/', home, 7)
	defer { launcher_test_free_results(exact) }
	assert exact == [base + '/External/Workspace']
	partial := index.launcher_query(base + '/External/Work', home, 7)
	defer { launcher_test_free_results(partial) }
	assert partial.len == 2
	assert base + '/External/Workspace' in partial
	assert base + '/External/Workshop' in partial
	assert index.launcher_query('', home, 7).len == 0
	assert index.launcher_query('workspace', home, 0).len == 0
}

fn test_launcher_keeps_changed_folders_but_rejects_replacements() {
	home := launcher_test_home('identity')
	defer { os.rmdir_all(home) or {} }
	os.mkdir(home + '/Projects')!
	mut index := SearchIndex{}
	index.begin([SearchRoot{path: home, identity: identify(home)!, enabled: true}])
	for index.indexing { index.tick() }
	defer { index.close() }
	os.write_file(home + '/Projects/new.txt', 'child added after indexing')!
	changed := index.launcher_query('projects', home, 7)
	defer { launcher_test_free_results(changed) }
	assert changed == [home + '/Projects']
	os.rename(home + '/Projects', home + '/Old Projects')!
	os.mkdir(home + '/Projects')!
	replaced := index.launcher_query('projects', home, 7)
	defer { launcher_test_free_results(replaced) }
	assert replaced.len == 0
}

fn test_launcher_finds_home_folders_before_the_first_index_is_ready() {
	home := launcher_test_home('fallback')
	defer { os.rmdir_all(home) or {} }
	os.mkdir_all(home + '/Archive/Workspace')!
	os.mkdir(home + '/Workspace')!
	os.mkdir_all(home + '/.hidden/Workspace')!
	os.write_file(home + '/Workspace.txt', 'not a directory')!
	os.symlink(home + '/Archive/Workspace', home + '/Workspace Link')!
	index := SearchIndex{}
	paths := index.launcher_query('WORKSPACE', home, 7)
	defer { launcher_test_free_results(paths) }
	assert paths == [home + '/Workspace', home + '/Archive/Workspace']
	first := index.launcher_query('workspace', home, 1)
	defer { launcher_test_free_results(first) }
	assert first == [home + '/Workspace']
	nested := index.launcher_query('archive/work', home, 7)
	defer { launcher_test_free_results(nested) }
	assert nested == [home + '/Archive/Workspace']
	root_name := os.file_name(home)
	defer { unsafe { root_name.free() } }
	root := index.launcher_query(root_name, home, 1)
	defer { launcher_test_free_results(root) }
	assert root == [home]
}
