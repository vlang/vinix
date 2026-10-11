// SPDX-License-Identifier: GPL-2.0-or-later
module main
import os
import desktop.workflowcore

fn test_tag_changes_update_published_results_without_rebuilding_content() {
	home := os.real_path(os.temp_dir()) + '/vinix-tag-search-' + C.getpid().str()
	os.mkdir_all(home)!
	defer { os.rmdir_all(home) or {} }
	old_home := desktop_user_home
	desktop_user_home = home
	defer { desktop_user_home = old_home }
	path := home + '/document.txt'
	os.write_file(path, 'indexed content')!
	mut index := workflowcore.SearchIndex{}
	defer { index.close() }
	index.begin([workflowcore.SearchRoot{path: home, identity: workflowcore.identify(home)!, enabled: true, contents: true}])
	for index.indexing { index.tick() }
	index.save(home)!
	mut app := FilesContextApp{}
	app.files.settings = default_files_settings()
	app.files.settings.toggle_tag(path, 7)
	app.sync_index_tags(path)
	mut tagged := workflowcore.load_index(home)!
	assert tagged.query('tag:Work', 10) == [path]
	tagged.close()
	app.files.settings.toggle_tag(path, 7)
	app.sync_index_tags(path)
	mut untagged := workflowcore.load_index(home)!
	defer { untagged.close() }
	assert untagged.query('tag:Work', 10).len == 0
	assert untagged.query('indexed', 10) == [path]
}
