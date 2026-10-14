// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn test_zed_is_a_hosted_desktop_application_with_keyboard_pointer_and_clipboard() {
	choices := available_apps.filter(it.title == 'Zed')
	assert choices.len == 1
	app := choices[0]
	assert app.process_name == 'vinix-zed'
	assert app.icon == 'asset:zed'
	assert app.width == zed_surface_width
	assert app.height == zed_surface_height + default_title_height
	assert app.keyboard && app.pointer && app.polling && app.us_keys
	assert !app.standalone
	assert hosted_session_client(app.process_name)
	assert app_start_actions.len == available_apps.len
	assert app_shortcut_actions.len == available_apps.len
	assert HostedText.zed_starting.text() == 'Starting Zed…'
	assert HostedText.zed_missing.text() == 'Zed is not installed.'
	assert HostedText.zed_exited.text() == 'Zed exited.'
}

fn test_first_boot_recognizes_the_private_zed_launcher_and_existing_steam() {
	zed := first_run_app_catalogue.filter(it.title == 'Zed')
	steam := first_run_app_catalogue.filter(it.title == 'Steam')
	assert zed.len == 1 && steam.len == 1
	assert '/usr/bin/run-zed' in zed[0].installed_paths
	assert '/usr/bin/steam' in steam[0].installed_paths
}
