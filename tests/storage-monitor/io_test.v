// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

fn monitor_test_run(interval &char, count &char) i32 {
	arguments := [&char(c'vinix-volume'), &char(c'monitor'), &char(c'/dev/test'), interval, count]!
	return run(5, unsafe { &arguments[0] })
}

fn test_monitor_uses_one_readonly_descriptor_flushes_each_sample_and_does_not_sleep_after_last() {
	monitor_model_reset(0)
	assert monitor_test_run(c'1', c'200') == 0
	assert monitor_model.opens == 1 && monitor_model.closes == 1
	assert monitor_model.status_calls == 400 && monitor_model.health_calls == 200
	assert monitor_model.sleeps == 199 && monitor_model.flushes == 200
		&& monitor_model.prints == 200
}

fn test_monitor_warns_recovers_and_retains_the_session_exit_status() {
	for mode, expected in [i32(0), 3, 4, 4, 1, 1, 1] {
		monitor_model_reset(mode)
		assert monitor_test_run(c'1', c'2') == expected
		assert monitor_model.opens == 1 && monitor_model.closes == 1
		assert monitor_model.sleeps == 1 && monitor_model.flushes == 2
		if mode == 5 { assert monitor_model.health_calls == 0
		 }
		if mode == 6 { assert monitor_model.health_calls == 1
		 }
	}
	monitor_model_reset(11)
	assert monitor_test_run(c'1', c'3') == 0 // Counter reset is a fresh baseline.
	monitor_model_reset(13)
	assert monitor_test_run(c'1', c'2') == 1
	assert monitor_model.health_calls == 2 && monitor_model.closes == 1
}

fn test_monitor_stops_on_bad_status_identity_health_or_output_and_closes_the_descriptor() {
	for mode in [7, 8, 9, 12, 14, 15, 17, 18]! {
		monitor_model_reset(mode)
		assert monitor_test_run(c'1', c'2') == 1
		assert monitor_model.opens == 1 && monitor_model.closes == 1
		if mode == 7 || mode == 9 { assert monitor_model.health_calls == 0
		 }
		if mode == 8 { assert monitor_model.health_calls == 1
		 } // No query on replacement.
		if mode == 12 || mode == 14 || mode == 15 { assert monitor_model.health_calls == 1
		 }
	}
	monitor_model_reset(10)
	assert monitor_test_run(c'1', c'2') == 1 && monitor_model.closes == 0
	monitor_model_reset(18)
	assert monitor_test_run(c'1', c'1') == 1
	assert monitor_model.prints == 1 && monitor_model.flushes == 0
	assert monitor_model.sleeps == 0 && monitor_model.closes == 1
}

fn test_monitor_retries_interrupted_sleep_and_rejects_invalid_arguments_before_opening() {
	monitor_model_reset(16)
	assert monitor_test_run(c'1', c'2') == 0
	assert monitor_model.sleeps == 2 && monitor_model.health_calls == 2
	for interval in [c'', c'0', c'-1', c'86401', c'18446744073709551616', c'1x']! {
		monitor_model_reset(0)
		assert monitor_test_run(interval, c'2') == 2 && monitor_model.opens == 0
	}
	for count in [c'', c'0', c'-1', c'18446744073709551616', c'1x']! {
		monitor_model_reset(0)
		assert monitor_test_run(c'1', count) == 2 && monitor_model.opens == 0
	}
	monitor_model_reset(0)
	arguments := [&char(c'vinix-volume'), &char(c'monitor'), &char(c'/dev/test')]!
	assert run(3, unsafe { &arguments[0] }) == 2 && monitor_model.opens == 0
}

fn test_monitor_accepts_optional_count_and_numeric_upper_bounds() {
	monitor_model_reset(18) // Stop an unbounded session at the output boundary.
	arguments := [&char(c'vinix-volume'), &char(c'monitor'), &char(c'/dev/test'), &char(c'1')]!
	assert run(4, unsafe { &arguments[0] }) == 1
	assert monitor_model.opens == 1 && monitor_model.closes == 1 && monitor_model.health_calls == 1
	monitor_model_reset(0)
	assert monitor_test_run(c'86400', c'1') == 0 && monitor_model.sleeps == 0
	monitor_model_reset(18)
	assert monitor_test_run(c'1', c'18446744073709551615') == 1
	assert monitor_model.opens == 1 && monitor_model.closes == 1
}
