// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn test_clock_preferences_defaults_round_trip_and_validate() {
	defaults := Settings{}
	assert defaults.clock_24_hour
	assert defaults.clock_show_seconds
	assert defaults.clock_show_date
	assert defaults.clock_show_weekday

	p := DesktopPreferences{
		settings: Settings{
			clock_24_hour: false
			clock_show_seconds: false
			clock_show_date: false
			clock_show_weekday: false
		}
	}
	record := desktop_encode_preferences(p)?
	assert record.contains('clock_24_hour=false\n')
	assert record.contains('clock_show_seconds=false\n')
	assert record.contains('clock_show_date=false\n')
	assert record.contains('clock_show_weekday=false\n')
	loaded := desktop_parse_preferences(record)?
	assert !loaded.settings.clock_24_hour
	assert !loaded.settings.clock_show_seconds
	assert !loaded.settings.clock_show_date
	assert !loaded.settings.clock_show_weekday

	// Older version-1 snapshots omit the additive clock keys and keep the
	// historical 24-hour clock with seconds, date and weekday.
	legacy := desktop_parse_preferences('version=1\n')?
	assert legacy.settings.clock_24_hour
	assert legacy.settings.clock_show_seconds
	assert legacy.settings.clock_show_date
	assert legacy.settings.clock_show_weekday

	for invalid in ['version=1\nclock_24_hour=1', 'version=1\nclock_24_hour=yes',
		'version=1\nclock_show_seconds=0', 'version=1\nclock_show_seconds=no',
		'version=1\nclock_show_date=1', 'version=1\nclock_show_date=yes',
		'version=1\nclock_show_weekday=0', 'version=1\nclock_show_weekday=no',
		'version=1\nclock_24_hour=true\nclock_24_hour=false',
		'version=1\nclock_show_seconds=true\nclock_show_seconds=false',
		'version=1\nclock_show_date=true\nclock_show_date=false',
		'version=1\nclock_show_weekday=true\nclock_show_weekday=false'] {
		assert desktop_parse_preferences(invalid) == none
	}
}
