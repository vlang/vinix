// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// Standalone host integration test for the compositor/application process
// boundary. The parent execs this same binary in app mode, exactly as the
// installed per-app symlinks do on Vinix.
module main

import ui2

fn tree_has_id(element ui2.Element, id string) bool {
	if element.id == id {
		return true
	}
	for child in element.children {
		if tree_has_id(child, id) {
			return true
		}
	}
	return false
}

fn close_remote(mut app NativeApp) {
	if mut app is RemoteApp {
		app.close()
	}
}

fn main() {
	if options := app_process_options(arguments()[1..]) {
		run_app_process(options)
		return
	}
	desktop_ignore_broken_pipe()

	mut desktop := Desktop{}
	mut files := start_remote_app_at(arguments()[0], available_apps[0], mut desktop) or {
		panic(err)
	}
	if mut files is RemoteApp {
		assert files.pid > 0
	}
	files_tree := files.build(ui2.rect(0, 0, 460, 326)) or { panic(err) }
	assert files_tree.kind == .screen
	assert tree_has_id(files_tree, files_action_up)
	files.handle(files_action_up) or { panic(err) }
	free_tree(files_tree)
	close_remote(mut files)

	mut settings := start_remote_app_at(arguments()[0], available_apps[4], mut desktop) or {
		panic(err)
	}
	settings.handle('${settings_action_category}1') or { panic(err) }
	settings.handle('${settings_action_theme}1') or { panic(err) }
	assert desktop.settings.theme == .macos
	settings.handle('${settings_action_category}4') or { panic(err) }
	settings.handle(settings_scale_200_action) or { panic(err) }
	assert desktop_requested_scale() == desktop_scale_200
	settings_tree := settings.build(ui2.rect(0, 0, 620, 386)) or { panic(err) }
	assert settings_tree.kind == .screen
	assert tree_has_id(settings_tree, settings_scale_100_action)
	free_tree(settings_tree)
	close_remote(mut settings)
	desktop_restore_requested_scale()
}
