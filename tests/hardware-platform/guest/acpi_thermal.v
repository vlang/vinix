// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// acpi-thermal: a thermal zone and fans described by firmware.
//
// The machine is given the table `thermal-bench` (hwhost/thermal_bench.v): a
// zone whose temperature follows a script as the kernel reads it, and four
// fans, one of each kind. This program never reads the temperature -- every
// read moves the script on -- and watches what the kernel does about it:
// which fans it runs and how fast, and how far it holds the processors back.
// The stages below must be seen in this order. At the end the script goes
// past the critical trip, and the kernel must turn the machine off itself.
module main

import os

const acpi_fans = '/sys/class/thermal/acpi_fans'

// What every fan was last told, as acpi_fans gives it: one line a fan.
struct FanOrders {
	fine     string // FAN0: any level
	switched string // FAN1: on or off by its own methods
	listed   string // FAN2: one of the levels it lists
	powered  string // FAN3: on or off by a power resource
}

fn fan_orders() FanOrders {
	text := read_text(acpi_fans) or { '' }
	mut found := map[string]string{}
	for line in text.split_into_lines() {
		words := line.fields()
		if words.len >= 3 {
			found[words[0]] = words[2]
		}
	}
	return FanOrders{
		fine:     found['FAN0']
		switched: found['FAN1']
		listed:   found['FAN2']
		powered:  found['FAN3']
	}
}

// The hwmon directory of the firmware's zone.
fn firmware_hwmon() !string {
	for name in list_dir('/sys/class/hwmon')! {
		if read_word('/sys/class/hwmon/${name}/name') == 'acpitz' {
			return '/sys/class/hwmon/${name}'
		}
	}
	return error('no hwmon device is called acpitz')
}

fn scenario_acpi_thermal(mut t Test) {
	// The zone, by its type; its temperature is left alone.
	mut zone := ''
	for name in list_dir(thermal_class) or { []string{} } {
		if name.starts_with('thermal_zone') && read_word('${thermal_class}${name}/type') == 'acpitz' {
			zone = thermal_class + name
		}
	}
	if !t.check(zone != '', 'no thermal zone of type acpitz') {
		return
	}
	hwmon := firmware_hwmon() or {
		t.check(false, err.msg())
		return
	}
	t.check(os.exists(acpi_fans), '${acpi_fans} is missing')
	// The fans in the order the hottest trip lists them; the two that
	// report a speed have an input.
	for number, label in ['FAN0', 'FAN1', 'FAN2', 'FAN3'] {
		found := read_word('${hwmon}/fan${number + 1}_label')
		t.check(found == label, 'fan${number + 1}_label is "${found}", not ${label}')
	}
	t.check(os.exists('${hwmon}/fan1_input') && os.exists('${hwmon}/fan3_input'), 'the fans that report a speed have no input file')
	t.check(!os.exists('${hwmon}/fan2_input') && !os.exists('${hwmon}/fan4_input'), 'a fan that is only switched claims to report a speed')

	// What must be seen, in order. Each stage is what the fans were told
	// and the speeds the two that report have; the third stage is the
	// processors being held back with everything still running.
	stages := ['idle: every fan off', 'warm: the two with levels at half', 'hot: every fan flat out',
		'too hot: the processors held back', 'warm again: half, the switched ones off',
		'idle again: every fan off, the limit lifted']
	mut stage := 0
	mut lowest_limit := i64(100)
	mut waited := 0
	for stage < stages.len && waited < 90000 {
		orders := fan_orders()
		limit := thermal_number('thermal_limit')
		fine_rpm := read_word('${hwmon}/fan1_input').int()
		listed_rpm := read_word('${hwmon}/fan3_input').int()
		if limit < lowest_limit {
			lowest_limit = limit
		}
		all_off := orders.fine == '0' && orders.listed == '0' && orders.switched == 'off'
			&& orders.powered == 'off' && fine_rpm == 0 && listed_rpm == 0
		// Half speed: level 50 for the fan that takes any level, and for
		// the fan with listed levels the nearest of them, 60.
		half := orders.fine == '50' && orders.listed == '50' && orders.switched == 'off'
			&& orders.powered == 'off' && fine_rpm == 2000 && listed_rpm == 2400
		flat_out := orders.fine == '100' && orders.listed == '100' && orders.switched == 'on'
			&& orders.powered == 'on' && fine_rpm == 4000 && listed_rpm == 4000
		reached := match stage {
			0 { all_off && limit == 100 }
			1 { half && limit == 100 }
			2 { flat_out }
			3 { flat_out && limit < 100 }
			4 { half }
			else { all_off && limit == 100 }
		}
		if reached {
			t.info('${stages[stage]} (fans ${orders.fine} ${orders.switched} ${orders.listed} ${orders.powered}, ${fine_rpm} and ${listed_rpm} rpm, limit ${limit})')
			stage++
			continue
		}
		sleep_ms(50)
		waited += 50
	}
	if !t.check(stage == stages.len, 'the kernel did not get as far as "${stages[if stage < stages.len {
		stage
	} else {
		stages.len - 1
	}]}": fans ${fan_orders()}, limit ${thermal_number('thermal_limit')}') {
		return
	}
	t.check(lowest_limit < 100, 'the processors were never held back')

	// The verdict first: the script is about to pass the critical trip, and
	// past it the kernel turns the machine off without asking this program.
	if t.failures == 0 {
		t.say('HWTEST PASS ${t.scenario}')
	} else {
		t.say('HWTEST FAIL ${t.scenario}')
		power_off()
	}
	t.step('going critical')
	idle()
}
