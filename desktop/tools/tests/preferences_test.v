// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

#include <sys/stat.h>

fn C.mkfifo(path &char, mode u32) int

fn preference_test_home(name string) string {
	home := os.join_path(os.temp_dir(), 'vinix-preferences-${name}-${os.getpid()}')
	os.mkdir(home) or { panic(err) }
	return home
}

fn preference_test_custom() DesktopPreferences {
	return DesktopPreferences{
		scale: desktop_scale_200
		settings: Settings{
			button_side: .left
			taskbar_mode: .combined
			theme: .macos
			wallpaper_color: 4
			wallpaper_image: 2
		}
	}
}

fn test_preferences_first_boot_keeps_defaults_without_writing() {
	home := preference_test_home('defaults')
	defer { os.rmdir_all(home) or {} }
	mut p := desktop_load_preferences(home)
	assert p == DesktopPreferences{}
	assert p.configure_scale(1920, 1080) == desktop_scale_100
	assert p.configure_scale(2560, 1600) == desktop_scale_200
	assert p.save_changes(p.settings, desktop_scale_200, home)
	assert os.ls(home)!.len == 0
}

fn test_preferences_round_trip_every_field_and_both_scale_overrides() {
	home := preference_test_home('round-trip')
	defer { os.rmdir_all(home) or {} }
	base := preference_test_custom()
	for scale in [desktop_scale_200, desktop_scale_100, desktop_scale_200] {
		p := DesktopPreferences{ ...base, scale: scale }
		assert desktop_save_preferences(home, p)
		loaded := desktop_load_preferences(home)
		assert loaded == p
		for width in [1920, 2560] {
			assert loaded.configure_scale(width, 1600) == scale
			assert desktop_requested_scale() == scale
			assert desktop_current_scale() == scale
			w, h := desktop_scaled_physical_extents(scale)
			assert w == width / scale && h == 1600 / scale
		}
	}
	assert os.ls(home)! == [desktop_preferences_name]
	record := os.read_file(desktop_preferences_path(home))!
	assert record == 'version=1\nscale=2\nbutton_side=left\ntaskbar_mode=combined\ntheme=macos\nwallpaper_color=4\nwallpaper_image=2\n'
}

fn test_preferences_each_change_preserves_the_rest_of_the_snapshot() {
	home := preference_test_home('each-field')
	defer { os.rmdir_all(home) or {} }
	mut p := desktop_load_preferences(home)
	p.configure_scale(1920, 1080)
	mut settings := Settings{}
	for field in 0 .. 5 {
		match field {
			0 { settings.button_side = .left }
			1 { settings.taskbar_mode = .combined }
			2 { settings.theme = .macos }
			3 { settings.wallpaper_color = 4 }
			else { settings.wallpaper_image = 2 }
		}
		assert p.save_changes(settings, desktop_current_scale(), home)
		loaded := desktop_load_preferences(home)
		assert loaded.settings == settings
		assert loaded.scale == 0
		assert os.ls(home)! == [desktop_preferences_name]
	}
	// Appearance-only saves must leave automatic HiDPI detection intact.
	loaded := desktop_load_preferences(home)
	assert loaded.configure_scale(2560, 1600) == desktop_scale_200
	assert loaded.settings == preference_test_custom().settings
	// Returning to defaults is a real change too, not an omitted record.
	assert p.save_changes(Settings{}, desktop_scale_200, home)
	assert desktop_load_preferences(home) == DesktopPreferences{}
}

fn test_preferences_optional_keys_comments_and_unknown_keys() {
	assert desktop_parse_preferences('version=1')? == DesktopPreferences{}
	p := desktop_parse_preferences('# desktop\r\n version = 1 \r\n\n theme = macos\nfuture_key=value\n')?
	assert p.settings.theme == .macos
	assert p.settings.button_side == .right
	assert p.settings.taskbar_mode == .standard
	assert p.settings.wallpaper_image == -1
	assert p.scale == 0
	assert desktop_preference_index('2147483647')? == 2147483647
	assert desktop_preference_index('-1')? == -1
}

fn test_preferences_reject_invalid_versions_fields_duplicates_and_overflow() {
	home := preference_test_home('invalid')
	defer { os.rmdir_all(home) or {} }
	path := desktop_preferences_path(home)
	for record in ['', 'theme=macos', 'version=2', 'version=1\nversion=1',
		'version=1\nscale=0', 'version=1\nscale=200', 'version=1\nscale=2junk',
		'version=1\nscale=1\nscale=2', 'version=1\nbutton_side=up',
		'version=1\ntaskbar_mode=9', 'version=1\ntheme=other',
		'version=1\nwallpaper_color=-1', 'version=1\nwallpaper_color=${wallpaper_colors.len}',
		'version=1\nwallpaper_image=-2', 'version=1\nwallpaper_image=1junk',
		'version=1\nwallpaper_image=2147483648', 'version=1\nwallpaper_image=999999999999',
		'version=1\nwallpaper_image=+2', 'version=1\nwallpaper_image=',
		'version=1\nnot a setting', 'version=1\n=empty key', 'version=1\x00'] {
		assert desktop_parse_preferences(record) == none
		os.write_file(path, record)!
		loaded := desktop_load_preferences(home)
		assert loaded == DesktopPreferences{}
		assert loaded.configure_scale(1920, 1080) == desktop_scale_100
		assert os.read_file(path)! == record
	}
}

fn test_preferences_reads_reject_oversized_valid_prefixes() {
	home := preference_test_home('size-limit')
	defer { os.rmdir_all(home) or {} }
	path := desktop_preferences_path(home)
	prefix := 'version=1\nscale=2\n#'
	limit := prefix + 'x'.repeat(desktop_preferences_max_bytes - prefix.len)
	os.write_file(path, limit)!
	assert desktop_load_preferences(home).scale == desktop_scale_200
	os.write_file(path, limit + 'x')!
	assert desktop_load_preferences(home) == DesktopPreferences{}
	assert desktop_parse_preferences(limit + 'x') == none
}

fn test_preferences_only_persist_applied_scale_with_other_changes() {
	home := preference_test_home('commit')
	defer { os.rmdir_all(home) or {} }
	mut p := desktop_load_preferences(home)
	previous := p.configure_scale(1920, 1080)
	desktop_request_scale(desktop_scale_200)
	assert p.save_changes(p.settings, previous, home)
	assert os.ls(home)!.len == 0
	settings := Settings{ theme: .macos }
	assert p.save_changes(settings, previous, home)
	assert desktop_load_preferences(home).scale == 0
	desktop_restore_requested_scale()
	assert p.save_changes(settings, previous, '${home}/missing')
	desktop_request_scale(desktop_scale_200)
	desktop_commit_scale(desktop_scale_200)
	assert p.save_changes(settings, previous, home)
	loaded := desktop_load_preferences(home)
	assert loaded.scale == desktop_scale_200 && loaded.settings.theme == .macos
	assert p.save_changes(settings, desktop_scale_200, '${home}/missing')
}

fn test_preferences_atomic_replacement_keeps_old_open_file() {
	home := preference_test_home('atomic')
	defer { os.rmdir_all(home) or {} }
	path := desktop_preferences_path(home)
	old_preferences := preference_test_custom()
	old_record := desktop_encode_preferences(old_preferences)?
	assert desktop_save_preferences(home, old_preferences)
	mut old_file := os.open(path)!
	defer { old_file.close() }
	old_info := os.stat(path)!
	assert old_info.mode & 0o777 == 0o600
	assert desktop_save_preferences(home, DesktopPreferences{})
	mut data := []u8{len: old_record.len}
	assert old_file.read(mut data)! == old_record.len
	assert data.bytestr() == old_record
	assert desktop_load_preferences(home) == DesktopPreferences{}
	info := os.stat(path)!
	assert info.mode & 0o777 == 0o600
	assert info.inode != old_info.inode
	current := os.read_file(path)!
	for invalid in [DesktopPreferences{ scale: 3 },
		DesktopPreferences{ settings: Settings{ wallpaper_color: -1 } },
		DesktopPreferences{ settings: Settings{ wallpaper_image: -2 } }] {
		assert !desktop_save_preferences(home, invalid)
		assert os.read_file(path)! == current
	}
	assert os.ls(home)! == [desktop_preferences_name]
}

fn test_preferences_migrate_legacy_scale_to_one_file() {
	home := preference_test_home('migration')
	defer { os.rmdir_all(home) or {} }
	legacy := '${home}/${desktop_legacy_scale_name}'
	path := desktop_preferences_path(home)
	for record in ['1', '1\n', '2', '2\n'] {
		os.write_file(legacy, record)!
		p := desktop_load_preferences(home)
		assert p.scale == int(record[0] - `0`)
		assert p.settings == Settings{}
		assert desktop_load_preferences(home) == p
		assert os.ls(home)! == [desktop_preferences_name]
		os.rm(path)!
	}
	for record in ['', '0', '200', '2junk', '2\n\n', '2\x00'] {
		os.write_file(legacy, record)!
		assert desktop_load_preferences(home) == DesktopPreferences{}
		assert os.read_file(legacy)! == record
		assert !os.exists(path)
	}
}

fn test_preferences_unified_file_takes_precedence_even_when_damaged() {
	home := preference_test_home('precedence')
	defer { os.rmdir_all(home) or {} }
	legacy := '${home}/${desktop_legacy_scale_name}'
	path := desktop_preferences_path(home)
	assert desktop_save_preferences(home, DesktopPreferences{})
	os.write_file(legacy, '2\n')!
	assert desktop_load_preferences(home) == DesktopPreferences{}
	os.write_file(path, 'broken')!
	assert desktop_load_preferences(home) == DesktopPreferences{}
	assert os.read_file(legacy)! == '2\n'
	assert os.read_file(path)! == 'broken'
}

fn test_preferences_failed_save_keeps_live_state_and_retries_next_change() {
	home := preference_test_home('failure')
	defer { os.rmdir_all(home) or {} }
	path := desktop_preferences_path(home)
	legacy := '${home}/${desktop_legacy_scale_name}'
	assert desktop_load_preferences('') == DesktopPreferences{}
	assert !desktop_save_preferences('', preference_test_custom())
	assert !desktop_save_preferences('${home}/missing', preference_test_custom())
	// Force failure after the temporary file is written, before publication.
	os.mkdir(path)!
	os.write_file(legacy, '1\n')!
	mut p := DesktopPreferences{}
	previous := p.configure_scale(1920, 1080)
	desktop_request_scale(desktop_scale_200)
	desktop_commit_scale(desktop_scale_200)
	settings := preference_test_custom().settings
	assert !p.save_changes(settings, previous, home)
	assert desktop_current_scale() == desktop_scale_200
	assert desktop_requested_scale() == desktop_scale_200
	assert p.settings == settings
	assert p.save_changes(settings, desktop_scale_200, home)
	assert os.is_dir(path)
	assert os.ls(path)!.len == 0
	assert os.read_file(legacy)! == '1\n'
	assert os.ls(home)!.len == 2
	os.rmdir(path)!
	next := Settings{ ...settings, button_side: .right }
	assert p.save_changes(next, desktop_scale_200, home)
	loaded := desktop_load_preferences(home)
	assert loaded.settings == next && loaded.scale == desktop_scale_200
	assert os.ls(home)! == [desktop_preferences_name]
}

fn test_preferences_reject_existing_fifo_and_symlink_before_reading() {
	home := preference_test_home('special')
	defer { os.rmdir_all(home) or {} }
	path := desktop_preferences_path(home)
	assert C.mkfifo(&char(path.str), 0o600) == 0
	assert desktop_load_preferences(home) == DesktopPreferences{}
	os.rm(path)!
	legacy := '${home}/${desktop_legacy_scale_name}'
	assert C.mkfifo(&char(legacy.str), 0o600) == 0
	assert desktop_load_preferences(home) == DesktopPreferences{}
	os.rm(legacy)!
	target := os.join_path(home, 'unrelated')
	os.write_file(target, 'version=1\nscale=2\n')!
	os.symlink(target, path)!
	assert desktop_load_preferences(home) == DesktopPreferences{}
	assert desktop_save_preferences(home, DesktopPreferences{})
	assert os.read_file(target)! == 'version=1\nscale=2\n'
	assert desktop_load_preferences(home) == DesktopPreferences{}
}

fn test_preferences_dangling_symlink_does_not_trigger_legacy_migration() {
	home := preference_test_home('dangling-link')
	defer { os.rmdir_all(home) or {} }
	path := desktop_preferences_path(home)
	legacy := '${home}/${desktop_legacy_scale_name}'
	target := os.join_path(home, 'absent')
	os.symlink(target, path)!
	os.write_file(legacy, '2\n')!
	assert desktop_load_preferences(home) == DesktopPreferences{}
	assert os.is_link(path)
	assert !os.exists(target)
	assert os.read_file(legacy)! == '2\n'
}

fn test_preferences_legacy_directory_is_not_removed_by_save() {
	home := preference_test_home('legacy-directory')
	defer { os.rmdir_all(home) or {} }
	legacy := '${home}/${desktop_legacy_scale_name}'
	os.mkdir(legacy)!
	assert !desktop_save_preferences(home, preference_test_custom())
	assert os.is_dir(legacy)
	// Publication already succeeded; cleanup failure does not corrupt it.
	assert desktop_load_preferences(home) == preference_test_custom()
	assert os.ls(home)!.len == 2
}
