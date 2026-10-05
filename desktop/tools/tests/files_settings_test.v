// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

fn files_settings_has_id(element ui2.Element, id string) bool {
	if element.id == id { return true }
	for child in element.children {
		if files_settings_has_id(child, id) { return true }
	}
	return false
}

fn files_settings_has_entry(entries []FileEntry, name string) bool {
	for entry in entries {
		if entry.name == name { return true }
	}
	return false
}

fn test_files_settings_window_updates_files_in_both_views() {
	root := os.join_path(os.temp_dir(), 'vinix-files-settings-hidden-test')
	os.rmdir_all(root) or {}
	os.mkdir_all(root) or { panic(err) }
	defer { os.rmdir_all(root) or {} }
	os.write_file(os.join_path(root, '.local'), 'hidden') or { panic(err) }
	os.write_file(os.join_path(root, 'visible'), 'shown') or { panic(err) }
	mut app := FilesContextApp{}
	app.files.settings = default_files_settings()
	app.files.browser.read(root.clone())
	assert !files_settings_has_entry(app.files.browser.entries, '.local')
	mut settings_app := FilesContextApp{
		settings_only: true
	}
	settings_app.files.settings = default_files_settings()
	tree := settings_app.build(ui2.rect(0, 0, 540, 520)) or { panic(err) }
	assert files_settings_has_id(tree, files_settings_hidden)
	assert !files_settings_has_id(tree, files_action_up)
	free_tree(tree)
	settings_app.handle(files_settings_hidden) or { panic(err) }
	assert settings_app.files.settings.save(root)
	app.reload_files_settings(root)
	assert app.files.settings.show_hidden
	assert files_settings_has_entry(app.files.browser.entries, '.local')
	app.files.set_view_mode(.columns)
	assert files_settings_has_entry(app.files.columns.last().browser.entries, '.local')
	settings_app.handle(files_settings_hidden) or { panic(err) }
	assert settings_app.files.settings.save(root)
	app.reload_files_settings(root)
	assert !files_settings_has_entry(app.files.columns.last().browser.entries, '.local')
}

fn test_files_settings_shortcut_and_hidden_factory() {
	rest, found := files_settings_remove_shortcut('a${files_settings_command_comma}b')
	assert found
	assert rest == 'ab'
	rest_plain, found_plain := files_settings_remove_shortcut('abc')
	assert !found_plain
	assert rest_plain == 'abc'
	factory := files_settings_factory()
	assert factory.process_name == files_settings_process_name
	assert app_factory_named(files_settings_process_name) != none
}

fn test_files_view_mode_reopens_with_last_selected_mode() {
	root := os.join_path(os.temp_dir(), 'vinix-files-view-mode-test')
	child := os.join_path(root, 'child')
	os.rmdir_all(root) or {}
	os.mkdir_all(child) or { panic(err) }
	defer { os.rmdir_all(root) or {} }
	assert load_files_view_mode(root) == .list

	mut app := FilesContextApp{}
	app.files.settings = default_files_settings()
	app.files.browser.read(child.clone())
	app.handle_browser_action(files_action_view_columns, root) or { panic(err) }
	assert app.files.view_mode == .columns
	assert load_files_view_mode(root) == .columns

	mut reopened := FilesContextApp{}
	reopened.files.browser.read(child.clone())
	reopened.restore_files_view_mode(root)
	assert reopened.files.view_mode == .columns
	assert reopened.files.current_path() == child

	// Tag results use a temporary list view, without changing the preference.
	app.files.handle('${files_action_tag_prefix}0') or { panic(err) }
	assert app.files.view_mode == .list
	assert load_files_view_mode(root) == .columns

	mut settings := default_files_settings()
	settings.show_hidden = true
	assert settings.save(root)
	assert load_files_view_mode(root) == .columns
	app.handle_browser_action(files_action_view_list, root) or { panic(err) }
	assert load_files_view_mode(root) == .list
	reopened.restore_files_view_mode(root)
	assert reopened.files.view_mode == .list
	assert reopened.files.current_path() == child
	path := files_view_mode_path(root)
	defer { unsafe { path.free() } }
	os.write_file(path, 'unknown') or { panic(err) }
	assert load_files_view_mode(root) == .list
}

fn test_files_settings_gear_and_shortcut_focus_one_window() {
	mut desktop := Desktop{}
	desktop.apps << &FilesContextApp{}
	desktop.windows << Window{
		id:        1
		title:     'Files'
		x:         0
		y:         0
		width:     700
		height:    400
		app_index: 0
	}
	desktop.windows << Window{
		id:        2
		title:     files_settings_window_title
		x:         1000
		y:         0
		width:     540
		height:    550
		app_index: 0
		minimized: true
	}
	desktop.focus = 1
	desktop.forward_to_app(10, 10, files_action_settings)
	assert desktop.focus == 2
	assert !desktop.windows.last().minimized
	assert desktop.windows.len == 2
	desktop.focus = 1
	rest := desktop.take_files_settings_shortcut(files_settings_command_comma)
	assert rest == ''
	assert desktop.focus == 2
	assert desktop.windows.len == 2
}

fn test_files_tags_persist_and_follow_file_operations() {
	root := os.join_path(os.temp_dir(), 'vinix-files-settings-tags-test')
	os.rmdir_all(root) or {}
	os.mkdir_all(root) or { panic(err) }
	defer { os.rmdir_all(root) or {} }
	mut settings := default_files_settings()
	settings.show_hidden = true
	settings.toggle_tag('/a/folder', 0)
	settings.toggle_tag('/a/folder/child', 1)
	settings.rebase_path('/a/folder', '/b/renamed')
	assert settings.first_color('/a/folder') == 0
	assert settings.first_color('/b/renamed') == settings.tags[0].color
	assert settings.first_color('/b/renamed/child') == settings.tags[1].color
	settings.copy_path('/b/renamed', '/b/copied')
	assert settings.first_color('/b/copied/child') == settings.tags[1].color
	settings.remove_path('/b/renamed')
	assert settings.first_color('/b/renamed/child') == 0
	assert settings.save(root)
	loaded := load_files_settings(root)
	assert loaded.show_hidden
	assert loaded.first_color('/b/copied/child') == settings.tags[1].color
	mut empty := default_files_settings()
	for empty.tags.len > 0 { empty.remove_tag(0) }
	assert empty.save(root)
	assert load_files_settings(root).tags.len == 0
}

fn test_files_tag_sidebar_opens_tagged_items() {
	root := os.join_path(os.temp_dir(), 'vinix-files-tag-sidebar-test')
	os.rmdir_all(root) or {}
	os.mkdir_all(root) or { panic(err) }
	defer { os.rmdir_all(root) or {} }
	item := os.join_path(root, 'report.txt')
	os.write_file(item, 'report') or { panic(err) }
	mut app := FileBrowserApp{}
	app.settings = default_files_settings()
	app.settings.toggle_tag(item, 0)
	app.browser.read(root.clone())
	list := app.build(ui2.rect(0, 0, 700, 400)) or { panic(err) }
	assert files_settings_has_id(list, '${files_action_tag_prefix}0')
	free_tree(list)
	app.handle('${files_action_tag_prefix}0') or { panic(err) }
	assert app.active_tag_id == 0
	tagged := app.build(ui2.rect(0, 0, 700, 400)) or { panic(err) }
	assert files_settings_has_id(tagged, '${files_action_tag_row}0')
	free_tree(tagged)
	app.handle('${files_action_tag_row}0') or { panic(err) }
	assert app.active_tag_id == -1
	assert app.browser.path == root
	assert app.browser.selected_row >= 0
}

fn test_files_tag_picker_and_custom_tag_editing() {
	mut app := FilesContextApp{}
	app.files.settings = default_files_settings()
	app.set_context_path('/tmp/report.txt')
	app.handle(file_context_tags) or { panic(err) }
	assert app.tag_picker
	app.handle('${files_picker_toggle_prefix}0') or { panic(err) }
	assert app.files.settings.first_color('/tmp/report.txt') == app.files.settings.tags[0].color
	app.handle(files_picker_close) or { panic(err) }
	assert !app.tag_picker
	mut settings_app := FilesContextApp{
		settings_only: true
	}
	settings_app.files.settings = default_files_settings()
	settings_app.handle(files_settings_tags) or { panic(err) }
	settings_app.handle(files_settings_add) or { panic(err) }
	assert settings_app.settings_editing
	settings_app.key_input('Project\n')
	assert !settings_app.settings_editing
	assert settings_app.files.settings.tags.last().name == 'Project'
	settings_app.handle(files_settings_remove) or { panic(err) }
	assert settings_app.files.settings.tags.len == 10
}
