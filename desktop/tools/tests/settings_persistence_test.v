// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

// Exercise the actual Settings actions and compositor scale application, not
// only the serializer. This file is staged with the full desktop/UI suite.
fn test_settings_actions_save_and_restore_one_complete_snapshot() {
	home := os.join_path(os.temp_dir(), 'vinix-settings-actions-${os.getpid()}')
	os.mkdir(home)!
	defer { os.rmdir_all(home) or {} }
	mut preferences := desktop_load_preferences(home)
	preferences.configure_scale(1920, 1080)
	mut desktop := Desktop{
		settings: preferences.settings
		canvas: new_canvas(1920, 1080)
	}
	defer { unsafe { free(voidptr(desktop.canvas.pixels)) } }
	mut app := SettingsApp{
		desktop: &desktop
		images: [WallpaperImage{ name: 'Test wallpaper', file: '/not-loaded.vwp' }]
	}
	app.handle('${settings_action_side}1')!
	app.handle('${settings_action_taskbar}1')!
	app.category = .theme
	app.handle('${settings_action_theme}1')!
	app.category = .wallpaper
	app.handle('${settings_action_color}4')!
	app.handle('${settings_action_image}0')!
	// These changes are saved even without any scale request.
	assert preferences.save_changes(desktop.settings, desktop_current_scale(), home)
	appearance := desktop_load_preferences(home)
	assert appearance.settings.button_side == .left
	assert appearance.settings.taskbar_mode == .combined
	assert appearance.settings.theme == .macos
	assert appearance.settings.wallpaper_color == 4
	assert appearance.settings.wallpaper_image == 0
	assert appearance.scale == 0

	app.category = .display
	previous := desktop_current_scale()
	app.handle(settings_scale_200_action)!
	assert desktop_requested_scale() == desktop_scale_200
	assert desktop_current_scale() == previous
	assert preferences.save_changes(desktop.settings, previous, home)
	assert desktop_load_preferences(home) == appearance
	desktop.apply_requested_scale()
	assert desktop.canvas.width == 960 && desktop.canvas.height == 540
	assert preferences.save_changes(desktop.settings, previous, home)
	restored := desktop_load_preferences(home)
	assert restored.settings == appearance.settings
	assert restored.configure_scale(1920, 1080) == desktop_scale_200
	assert restored.settings == desktop.settings
	assert os.ls(home)! == [desktop_preferences_name]

	// A later wallpaper change must preserve the saved scale and appearance.
	app.category = .wallpaper
	app.handle('${settings_action_color}1')!
	assert preferences.save_changes(desktop.settings, desktop_current_scale(), home)
	final_preferences := desktop_load_preferences(home)
	assert final_preferences.scale == desktop_scale_200
	assert final_preferences.settings.wallpaper_color == 1
	assert final_preferences.settings.wallpaper_image == -1
	assert final_preferences.settings.theme == .macos
	assert final_preferences.settings.button_side == .left
	assert final_preferences.settings.taskbar_mode == .combined
}
