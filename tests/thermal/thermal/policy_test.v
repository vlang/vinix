// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The policy of kernel/thermal/policy.v, run over traces of readings: the
// step-wise limit, each trip's hysteresis, and the counting of failures.
module thermal

// The self-test zone's trips: passive 80 C, hot 95 C, critical 105 C.
fn selftest_limits() Thresholds {
	trips := [
		Trip{
			kind:        .passive
			temperature: 80000
			hysteresis:  5000
		},
		Trip{
			kind:        .hot
			temperature: 95000
			hysteresis:  2000
		},
		Trip{
			kind:        .critical
			temperature: 105000
			hysteresis:  2000
		},
	]!
	return thresholds_of(&trips[0], 3)
}

// Put `readings` through the policy one after the other, starting from
// `state`, and return the limit after each.
fn limits_after(mut state ZoneState, limits Thresholds, readings []i64) []u32 {
	mut seen := []u32{}
	for reading in readings {
		verdict := judge_reading(state, limits, reading)
		state = verdict.state
		seen << limit_of_state(state.steps)
	}
	return seen
}

fn test_thresholds_take_the_lowest_trip_of_each_kind() {
	trips := [
		Trip{
			kind:        .passive
			temperature: 90000
			hysteresis:  1000
		},
		Trip{
			kind:        .critical
			temperature: 110000
			hysteresis:  -5
		},
		Trip{
			kind:        .passive
			temperature: 85000
			hysteresis:  3000
		},
	]!
	found := thresholds_of(&trips[0], 3)
	assert found.has_passive && found.passive == 85000 && found.passive_hyst == 3000
	assert !found.has_hot
	// A negative hysteresis is none.
	assert found.has_critical && found.critical == 110000 && found.critical_hyst == 0
	none_at_all := thresholds_of(&trips[0], 0)
	assert !none_at_all.has_passive && !none_at_all.has_hot && !none_at_all.has_critical
}

fn test_limit_of_state() {
	assert limit_of_state(0) == 100
	assert limit_of_state(1) == 90
	assert limit_of_state(5) == 50
	assert deepest_state == 9
	assert limit_of_state(deepest_state) == lowest_limit
	assert limit_of_state(1000) == lowest_limit
}

fn test_heating_takes_a_step_for_each_rising_reading() {
	mut state := ZoneState{}
	limits := selftest_limits()
	assert limits_after(mut state, limits, [i64(40000), 70000, 79999]) == [u32(100), 100, 100]
	// The first reading at the trip steps whatever the trend, and each
	// higher one after it.
	assert limits_after(mut state, limits, [i64(80000), 82000, 84000, 86000, 88000]) == [
		u32(90),
		80,
		70,
		60,
		50,
	]
	assert state.steps == 5
}

fn test_steady_and_falling_readings_above_the_trip_hold() {
	mut state := ZoneState{}
	limits := selftest_limits()
	limits_after(mut state, limits, [i64(81000), 83000])
	assert state.steps == 2
	assert limits_after(mut state, limits, [i64(83000), 83000, 82000, 80000]) == [u32(80), 80, 80,
		80]
	// Rising again takes the next step.
	assert limits_after(mut state, limits, [i64(80500)]) == [u32(70)]
}

fn test_first_reading_above_the_trip_steps_without_a_trend() {
	limits := selftest_limits()
	verdict := judge_reading(ZoneState{}, limits, 90000)
	assert verdict.state.steps == 1
	assert verdict.state.has_last && verdict.state.last == 90000
	// And the same temperature again does not.
	assert judge_reading(verdict.state, limits, 90000).state.steps == 1
}

fn test_the_hysteresis_holds_and_below_it_the_limit_comes_back() {
	mut state := ZoneState{}
	limits := selftest_limits()
	limits_after(mut state, limits, [i64(80000), 81000, 82000])
	assert state.steps == 3
	// 75 C is the edge: at it, hold; below it, a step back for each reading,
	// rising or not.
	assert limits_after(mut state, limits, [i64(79000), 76000, 75000]) == [u32(70), 70, 70]
	assert limits_after(mut state, limits, [i64(74999), 74999, 74000, 74500]) == [u32(80), 90, 100,
		100]
	assert state.steps == 0
}

fn test_the_limit_never_goes_below_the_lowest() {
	mut state := ZoneState{}
	limits := selftest_limits()
	mut readings := []i64{}
	for i in 0 .. 14 {
		readings << 80000 + i64(i) * 1000
	}
	seen := limits_after(mut state, limits, readings)
	assert seen[8] == 10
	assert seen[13] == 10
	assert state.steps == deepest_state
}

fn test_hot_goes_to_the_lowest_limit_at_once_and_is_logged_once() {
	limits := selftest_limits()
	mut verdict := judge_reading(ZoneState{}, limits, 96000)
	assert verdict.state.steps == deepest_state
	assert verdict.log_hot && !verdict.fire_critical
	// Still hot: no second line.
	verdict = judge_reading(verdict.state, limits, 97000)
	assert !verdict.log_hot && verdict.state.steps == deepest_state
	// Below the trip but inside its hysteresis: still the same excursion.
	verdict = judge_reading(verdict.state, limits, 94000)
	assert verdict.state.hot && verdict.state.steps == deepest_state
	verdict = judge_reading(verdict.state, limits, 95000)
	assert !verdict.log_hot
	// Below the hysteresis and back: a new one.
	verdict = judge_reading(verdict.state, limits, 92000)
	assert !verdict.state.hot
	verdict = judge_reading(verdict.state, limits, 95000)
	assert verdict.log_hot
}

fn test_cooling_from_hot_gives_the_limit_back_a_step_at_a_time() {
	mut state := ZoneState{}
	limits := selftest_limits()
	assert limits_after(mut state, limits, [i64(70000), 96000]) == [u32(100), 10]
	// Above the passive trip and falling: hold.
	assert limits_after(mut state, limits, [i64(90000), 85000]) == [u32(10), 10]
	assert limits_after(mut state, limits, [i64(60000), 60000, 60000]) == [u32(20), 30, 40]
}

fn test_critical_fires_once_for_each_excursion() {
	limits := selftest_limits()
	mut fired := 0
	mut state := ZoneState{}
	for reading in [i64(100000), 105000, 106000, 110000, 105000] {
		verdict := judge_reading(state, limits, reading)
		state = verdict.state
		if verdict.fire_critical {
			fired++
		}
	}
	assert fired == 1
	assert state.critical && state.steps == deepest_state
	// 104 C is inside the hysteresis: the same excursion.
	for reading in [i64(104000), 105000, 103000, 106000] {
		verdict := judge_reading(state, limits, reading)
		state = verdict.state
		if verdict.fire_critical {
			fired++
		}
	}
	assert fired == 1
	// Below 103 C the trip is armed again.
	for reading in [i64(102999), 105000, 105000] {
		verdict := judge_reading(state, limits, reading)
		state = verdict.state
		if verdict.fire_critical {
			fired++
		}
	}
	assert fired == 2
}

fn test_critical_without_a_hot_trip_still_takes_the_lowest_limit() {
	trips := [
		Trip{
			kind:        .passive
			temperature: 90000
			hysteresis:  2000
		},
		Trip{
			kind:        .critical
			temperature: 105000
			hysteresis:  2000
		},
	]!
	limits := thresholds_of(&trips[0], 2)
	verdict := judge_reading(ZoneState{}, limits, 105000)
	assert verdict.fire_critical && !verdict.log_hot
	assert verdict.state.steps == deepest_state
}

fn test_a_zone_with_only_a_hot_trip_gives_back_below_its_hysteresis() {
	trips := [
		Trip{
			kind:        .hot
			temperature: 90000
			hysteresis:  3000
		},
	]!
	limits := thresholds_of(&trips[0], 1)
	mut state := ZoneState{}
	assert limits_after(mut state, limits, [i64(80000), 91000]) == [u32(100), 10]
	assert limits_after(mut state, limits, [i64(89000), 87000]) == [u32(10), 10]
	assert limits_after(mut state, limits, [i64(86999), 86000]) == [u32(20), 30]
}

fn test_a_zone_with_no_trips_never_limits() {
	mut state := ZoneState{}
	assert limits_after(mut state, Thresholds{}, [i64(50000), 150000, 200000]) == [u32(100), 100,
		100]
}

fn test_failures_are_counted_and_do_not_move_the_limit() {
	limits := selftest_limits()
	mut state := ZoneState{}
	limits_after(mut state, limits, [i64(80000), 82000])
	assert state.steps == 2
	for expected in 1 .. int(failure_limit) {
		verdict := judge_failure(state)
		state = verdict.state
		assert state.failures == u32(expected)
		assert !verdict.fault && !state.faulted
		assert state.steps == 2 && state.last == 82000
	}
	// The fifth in a row switches the zone off, once, with the limit as it
	// was.
	verdict := judge_failure(state)
	assert verdict.fault && verdict.state.faulted
	assert verdict.state.failures == failure_limit
	assert verdict.state.steps == 2
	again := judge_failure(verdict.state)
	assert !again.fault && again.state.faulted && again.state.failures == failure_limit
	assert !wants_fast_polling(again.state)
}

fn test_a_good_reading_forgets_the_failures_before_it() {
	limits := selftest_limits()
	mut state := ZoneState{}
	for _ in 0 .. int(failure_limit) - 1 {
		state = judge_failure(state).state
	}
	assert state.failures == failure_limit - 1
	state = judge_reading(state, limits, 50000).state
	assert state.failures == 0
	for _ in 0 .. int(failure_limit) - 1 {
		state = judge_failure(state).state
	}
	assert !state.faulted
}

fn test_rearm_starts_a_zone_afresh_and_keeps_what_it_holds() {
	limits := selftest_limits()
	mut state := ZoneState{}
	limits_after(mut state, limits, [i64(80000), 82000, 84000])
	for _ in 0 .. int(failure_limit) {
		state = judge_failure(state).state
	}
	assert state.faulted && state.steps == 3
	state = rearm(state)
	assert !state.faulted && state.failures == 0 && !state.has_last && state.steps == 3
	// Its first reading has no trend: above the trip it holds what it has,
	// below the hysteresis it starts giving back.
	assert judge_reading(state, limits, 90000).state.steps == 3
	assert judge_reading(state, limits, 60000).state.steps == 2
}

fn test_fast_polling_while_a_zone_holds_the_limit() {
	limits := selftest_limits()
	mut state := ZoneState{}
	assert !wants_fast_polling(state)
	state = judge_reading(state, limits, 79000).state
	assert !wants_fast_polling(state)
	state = judge_reading(state, limits, 80000).state
	assert wants_fast_polling(state)
	state = judge_reading(state, limits, 60000).state
	assert !wants_fast_polling(state)
}

fn parsed(word string) i64 {
	return parse_signed(word) or { i64(-999999) }
}

fn test_parse_signed() {
	assert parsed('0') == 0
	assert parsed('80000') == 80000
	assert parsed('-274000') == -274000
	assert parsed('+5') == 5
	assert parsed('123456789012345678') == 123456789012345678
	for bad in ['', '-', '+', '12a', 'error', ' 5', '1.5', '1234567890123456789', '-1234567890123456789'] {
		if value := parse_signed(bad) {
			assert false, 'accepted "${bad}" as ${value}'
		}
	}
}
