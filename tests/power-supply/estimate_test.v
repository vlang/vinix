// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Tests of kernel/psupply/estimate.v, run on the host by ./run.
module psupply

const second = u64(1000000000)

fn test_percent_rounds_and_knows_when_it_cannot_say() {
	assert percent_of(0, 0) == -1
	assert percent_of(0, 48000) == 0
	assert percent_of(48000, 48000) == 100
	assert percent_of(50000, 48000) == 100
	assert percent_of(24000, 48000) == 50
	assert percent_of(1000, 48000) == 2
	assert percent_of(239, 48000) == 0
	assert percent_of(240, 48000) == 1
}

fn test_a_reported_rate_gives_the_time_at_once() {
	mut e := Estimator{}
	// 30 Wh at 12 W is two and a half hours.
	e.sample(.discharging, 30000000, 12000000, 0)
	assert e.seconds_to_empty(30000000) == 9000
	assert e.seconds_to_full(30000000, 48000000) == 0
}

fn test_a_burst_moves_the_estimate_only_as_far_as_it_lasted() {
	mut e := Estimator{}
	e.sample(.discharging, 30000000, 10000000, 0)
	// Twelve seconds at three times the power: a tenth of the smoothing time,
	// so a tenth of the way from 10 W to 30 W.
	e.sample(.discharging, 30000000, 30000000, 12 * second)
	assert e.rate == 12000000
	// The same burst for two minutes or more is simply the new rate.
	e.sample(.discharging, 30000000, 30000000, 200 * second)
	assert e.rate == 30000000
	// And it comes down again the same way.
	e.sample(.discharging, 30000000, 10000000, 212 * second)
	assert e.rate == 28000000
}

fn test_plugging_in_forgets_the_discharge() {
	mut e := Estimator{}
	e.sample(.discharging, 30000000, 12000000, 0)
	e.sample(.charging, 30000000, 36000000, 5 * second)
	assert e.rate == 36000000
	assert e.seconds_to_empty(30000000) == 0
	// 18 Wh to go at 36 W.
	assert e.seconds_to_full(30000000, 48000000) == 1800
	e.sample(.full, 48000000, 0, 10 * second)
	assert e.rate == 0
	assert e.seconds_to_full(48000000, 48000000) == 0
}

fn test_a_battery_that_reports_no_rate_has_one_derived() {
	mut e := Estimator{}
	e.sample(.discharging, 30000000, 0, 0)
	assert e.seconds_to_empty(30000000) == 0
	// Too soon to tell: ten seconds is one step of the gauge.
	e.sample(.discharging, 29990000, 0, 10 * second)
	assert e.rate == 0
	// A minute in, 200 mWh have gone: 12 W.
	e.sample(.discharging, 29800000, 0, 60 * second)
	assert e.rate == 12000000
	assert e.seconds_to_empty(29800000) == 8940
	// A gauge that has not moved says nothing new.
	e.sample(.discharging, 29800000, 0, 120 * second)
	assert e.rate == 12000000
}

fn test_estimates_are_bounded() {
	mut e := Estimator{}
	// A trickle: weeks, by the division.
	e.sample(.discharging, 48000000, 1000, 0)
	assert e.seconds_to_empty(48000000) == longest_estimate_s
	// Figures large enough to overflow a careless multiplication.
	e.sample(.charging, 1, ~u64(0) / 2, 0)
	assert e.seconds_to_full(1, ~u64(0)) > 0
}

fn test_levels_follow_the_thresholds() {
	assert level_of(-1, .discharging, 10, 3) == .unknown
	assert level_of(100, .charging, 10, 3) == .full
	assert level_of(97, .full, 10, 3) == .full
	assert level_of(85, .discharging, 10, 3) == .high
	assert level_of(50, .discharging, 10, 3) == .normal
	assert level_of(10, .discharging, 10, 3) == .low
	assert level_of(4, .discharging, 10, 3) == .low
	assert level_of(3, .discharging, 10, 3) == .critical
	assert level_of(0, .charging, 10, 3) == .critical
}

fn test_only_a_discharging_battery_raises_an_alarm() {
	assert alarm_of(50, .discharging, false, 10, 3) == .none
	assert alarm_of(10, .discharging, false, 10, 3) == .low
	assert alarm_of(3, .discharging, false, 10, 3) == .critical
	// The battery's own word counts whatever the percentage says.
	assert alarm_of(40, .discharging, true, 10, 3) == .critical
	// On the charger nothing is urgent.
	assert alarm_of(1, .charging, true, 10, 3) == .none
	assert alarm_of(1, .not_charging, false, 10, 3) == .none
	// Without a percentage only the battery's word is left.
	assert alarm_of(-1, .discharging, false, 10, 3) == .none
	assert alarm_of(-1, .discharging, true, 10, 3) == .critical
}
