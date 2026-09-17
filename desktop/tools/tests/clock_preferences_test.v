// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn test_clock_preferences_defaults_round_trip_and_validate() {
	defaults := Settings{}
	assert defaults.clock_24_hour
	assert defaults.clock_show_seconds

	p := DesktopPreferences{
		settings: Settings{
			clock_24_hour: false
			clock_show_seconds: false
		}
	}
	record := desktop_encode_preferences(p)?
	assert record.contains('clock_24_hour=false\n')
	assert record.contains('clock_show_seconds=false\n')
	loaded := desktop_parse_preferences(record)?
	assert !loaded.settings.clock_24_hour
	assert !loaded.settings.clock_show_seconds

	// Older version-1 snapshots omit the new additive keys and keep the
	// historical 24-hour clock with seconds.
	legacy := desktop_parse_preferences('version=1\n')?
	assert legacy.settings.clock_24_hour
	assert legacy.settings.clock_show_seconds

	for invalid in ['version=1\nclock_24_hour=1', 'version=1\nclock_24_hour=yes',
		'version=1\nclock_show_seconds=0', 'version=1\nclock_show_seconds=no',
		'version=1\nclock_24_hour=true\nclock_24_hour=false',
		'version=1\nclock_show_seconds=true\nclock_show_seconds=false'] {
		assert desktop_parse_preferences(invalid) == none
	}
}
