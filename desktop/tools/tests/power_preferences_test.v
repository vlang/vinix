// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn power_preference_home(name string) string {
	home := os.join_path(os.temp_dir(), 'vinix-power-preferences-${name}-${os.getpid()}')
	os.rmdir_all(home) or {}
	os.mkdir(home) or { panic(err) }
	return home
}

fn test_power_preferences_defaults_round_trip_and_validate() {
	defaults := Settings{}
	assert defaults.display_off_minutes == 10 && defaults.sleep_minutes == 0
	assert defaults.lid_action == .suspend && defaults.power_profile == .automatic

	record := desktop_encode_preferences(DesktopPreferences{})?
	assert record.ends_with('display_off_after=10\nsleep_after=never\nlid_action=suspend\npower_profile=auto\n')
	p := DesktopPreferences{
		settings: Settings{
			display_off_minutes: 5
			sleep_minutes:       30
			lid_action:          .ignore
			power_profile:       .power_saver
		}
	}
	custom := desktop_encode_preferences(p)?
	assert custom.ends_with('display_off_after=5\nsleep_after=30\nlid_action=ignore\npower_profile=power_saver\n')
	assert desktop_parse_preferences(custom)? == p

	// A snapshot from before these keys keeps the display's ten minutes and
	// asks nothing new of the kernel: no sleep, and its own lid and profile.
	legacy := desktop_parse_preferences('version=1\ntheme=macos\n')?
	assert legacy.settings.display_off_minutes == 10 && legacy.settings.sleep_minutes == 0
	assert legacy.settings.lid_action == .suspend && legacy.settings.power_profile == .automatic
	assert legacy.settings.theme == .macos

	// Every timeout Settings offers, alone and in each pair that holds.
	for display_off in idle_timeout_choices {
		for sleep in idle_timeout_choices {
			pair := DesktopPreferences{
				settings: Settings{
					display_off_minutes: display_off
					sleep_minutes:       sleep
				}
			}
			holds := display_off == 0 || sleep == 0 || display_off <= sleep
			assert idle_timeouts_valid(display_off, sleep) == holds
			assert desktop_preferences_valid(pair) == holds
			if holds {
				assert desktop_parse_preferences(desktop_encode_preferences(pair)?)? == pair
			} else {
				// A pair that does not hold is not written, and one found in a
				// file is not half applied.
				assert desktop_encode_preferences(pair) == none
				assert desktop_parse_preferences('version=1\ndisplay_off_after=${display_off}\nsleep_after=${sleep}') == none
			}
		}
	}
	for profile in power_profiles {
		named := desktop_parse_preferences('version=1\npower_profile=${profile.code()}')?
		assert named.settings.power_profile == profile
	}
	assert desktop_parse_preferences('version=1\nlid_action=ignore')?.settings.lid_action == .ignore

	// A record naming only when to sleep brings the display's default down
	// to it; naming a later display-off beside it is a contradiction.
	sleep_only := desktop_parse_preferences('version=1\nsleep_after=5')?
	assert sleep_only.settings.sleep_minutes == 5 && sleep_only.settings.display_off_minutes == 5
	later := desktop_parse_preferences('version=1\nsleep_after=30')?
	assert later.settings.sleep_minutes == 30 && later.settings.display_off_minutes == 10
	display_only := desktop_parse_preferences('version=1\ndisplay_off_after=60')?
	assert display_only.settings.display_off_minutes == 60 && display_only.settings.sleep_minutes == 0

	for invalid in ['version=1\ndisplay_off_after=0', 'version=1\ndisplay_off_after=3',
		'version=1\ndisplay_off_after=61', 'version=1\ndisplay_off_after=-1',
		'version=1\ndisplay_off_after=10m', 'version=1\ndisplay_off_after=Never',
		'version=1\ndisplay_off_after=', 'version=1\ndisplay_off_after=99999999999',
		'version=1\nsleep_after=0', 'version=1\nsleep_after=7', 'version=1\nsleep_after=off',
		'version=1\nlid_action=sleep', 'version=1\nlid_action=', 'version=1\nlid_action=[suspend]',
		'version=1\nlid_action=suspend ignore', 'version=1\npower_profile=automatic',
		'version=1\npower_profile=powersave', 'version=1\npower_profile=',
		'version=1\npower_profile=Balanced',
		'version=1\ndisplay_off_after=5\ndisplay_off_after=5',
		'version=1\nsleep_after=never\nsleep_after=never',
		'version=1\nlid_action=suspend\nlid_action=ignore',
		'version=1\npower_profile=auto\npower_profile=balanced'] {
		assert desktop_parse_preferences(invalid) == none, invalid
	}
}

fn test_power_settings_keep_the_display_no_later_than_sleep() {
	mut settings := Settings{}
	// Sleeping sooner than the display turns off brings the display forward.
	settings.set_sleep_minutes(5)
	assert settings.sleep_minutes == 5 && settings.display_off_minutes == 5
	// Keeping the display on longer than the machine pushes sleep back.
	settings.set_display_off_minutes(15)
	assert settings.display_off_minutes == 15 && settings.sleep_minutes == 15
	settings.set_display_off_minutes(2)
	assert settings.display_off_minutes == 2 && settings.sleep_minutes == 15
	settings.set_sleep_minutes(60)
	assert settings.display_off_minutes == 2 && settings.sleep_minutes == 60
	// Never is not a time to compare with: either may be never by itself.
	settings.set_display_off_minutes(0)
	assert settings.display_off_minutes == 0 && settings.sleep_minutes == 60
	settings.set_sleep_minutes(1)
	assert settings.display_off_minutes == 0 && settings.sleep_minutes == 1
	settings.set_sleep_minutes(0)
	settings.set_display_off_minutes(60)
	assert settings.display_off_minutes == 60 && settings.sleep_minutes == 0
	// A timeout that is not offered changes nothing.
	for minutes in [-1, 3, 61, 1000] {
		settings.set_display_off_minutes(minutes)
		settings.set_sleep_minutes(minutes)
		assert settings.display_off_minutes == 60 && settings.sleep_minutes == 0
	}
	for display_off in idle_timeout_choices {
		for sleep in idle_timeout_choices {
			mut either := Settings{}
			either.set_display_off_minutes(display_off)
			either.set_sleep_minutes(sleep)
			assert idle_timeouts_valid(either.display_off_minutes, either.sleep_minutes)
			assert either.sleep_minutes == sleep
			either.set_display_off_minutes(display_off)
			assert idle_timeouts_valid(either.display_off_minutes, either.sleep_minutes)
			assert either.display_off_minutes == display_off
		}
	}
}

fn test_power_preferences_are_saved_with_everything_else() {
	home := power_preference_home('snapshot')
	defer { os.rmdir_all(home) or {} }
	mut p := desktop_load_preferences(home)
	assert p == DesktopPreferences{}
	mut settings := Settings{
		theme: .macos
	}
	assert p.save_changes(settings, desktop_current_scale(), home)
	for field in 0 .. 4 {
		match field {
			0 { settings.set_sleep_minutes(30) }
			1 { settings.set_display_off_minutes(2) }
			2 { settings.lid_action = .ignore }
			else { settings.power_profile = .performance }
		}
		assert p.save_changes(settings, desktop_current_scale(), home)
		loaded := desktop_load_preferences(home)
		assert loaded.settings == settings
		assert loaded.settings.theme == .macos && loaded.scale == 0
		assert os.ls(home)! == [desktop_preferences_name]
	}
	record := os.read_file(desktop_preferences_path(home))!
	assert record.contains('\ntheme=macos\n')
	assert record.ends_with('display_off_after=2\nsleep_after=30\nlid_action=ignore\npower_profile=performance\n')
	// An unchanged frame writes nothing: the file is the one already there.
	os.rm(desktop_preferences_path(home))!
	assert p.save_changes(settings, desktop_current_scale(), home)
	assert os.ls(home)!.len == 0
	// Going back to the defaults is a change like any other.
	assert p.save_changes(Settings{}, desktop_current_scale(), home)
	assert desktop_load_preferences(home) == DesktopPreferences{}
}
