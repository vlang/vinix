// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise the hidden Files Settings factory across the real app pipe.
module main

import ui2

fn files_settings_process_has_id(element ui2.Element, id string) bool {
	if element.id == id {
		return true
	}
	for child in element.children {
		if files_settings_process_has_id(child, id) {
			return true
		}
	}
	return false
}

fn main() {
	if options := app_process_options(arguments()[1..]) {
		run_app_process(options)
		return
	}
	desktop_ignore_broken_pipe()
	mut desktop := Desktop{}
	mut settings := start_remote_app_at_with_timeout(arguments()[0], files_settings_factory(),
		mut desktop, app_response_timeout_ms) or { panic(err) }
	general := settings.build(ui2.rect(0, 0, 540, 520)) or { panic(err) }
	assert general.kind == .screen
	assert files_settings_process_has_id(general, files_settings_hidden)
	assert !files_settings_process_has_id(general, files_action_up)
	free_tree(general)
	settings.handle(files_settings_tags) or { panic(err) }
	tags := settings.build(ui2.rect(0, 0, 540, 520)) or { panic(err) }
	assert files_settings_process_has_id(tags, files_settings_add)
	free_tree(tags)
	if mut settings is RemoteApp {
		settings.close()
	}
}
