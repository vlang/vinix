// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The guest half of the hardware tests: /sbin/init of a machine that has
// nothing else in it.
//
// The controller puts the name of one scenario in /etc/hwtest-scenario. This
// program runs it and says how it went on the serial port, which is all the
// host can see of it:
//
//   HWTEST START <scenario>            the scenario began
//   HWTEST STEP <text>                 a point the host may act on
//   HWTEST INFO <text>                 something measured, for the report
//   HWTEST FAIL <scenario>: <message>  a check did not hold
//   HWTEST PASS <scenario>             every check held
//   HWTEST FAIL <scenario>             at least one did not
//
// A scenario is a function `scenario_<name>(mut t Test)` in a file of its own
// and a line in run_scenario() below.
module main

// Runs the named scenario. False when this program has no such scenario.
fn run_scenario(name string, mut t Test) bool {
	match name {
		'devices' { scenario_devices(mut t) }
		else { return false }
	}
	return true
}

fn main() {
	mut t := new_test()
	name := read_word('/etc/hwtest-scenario')
	t.scenario = if name == '' { 'unknown' } else { name }
	t.say('HWTEST START ${t.scenario}')
	if !run_scenario(name, mut t) {
		t.check(false, 'the guest program has no scenario of this name')
	}
	t.finish()
}
