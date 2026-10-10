// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// thermal and thermal-selftest: temperatures, and what the machine does
// about them.
//
// A virtual machine has no temperature sensors, and `thermal` checks that the
// kernel finds none and invents none: no zones, the limit on CPU performance
// at 100, the polling thread never started. On a PC it also checks the
// mechanism the sensor drivers stand on: reading a model-specific register
// that does not exist must come back as a failure, here and on another CPU,
// and not as a fault that stops the machine.
//
// thermal-selftest needs a kernel built with -d thermal_selftest, which has
// a zone whose temperature this program sets (emul_temp), with trips at 80,
// 95 and 105 degrees. It walks the zone through an afternoon: heating past
// the passive trip lowers the limit ten points per rising reading; cooling
// below the hysteresis gives it back step by step; the hot trip drops it to
// the floor at once; a sensor that stops answering disables the zone after
// five failures without touching the limit. Last, it reports its verdict and
// takes the zone past the critical trip, where the kernel must turn the
// machine off by itself -- which the host sees.
module main

import os

const thermal_class = '/sys/class/thermal/'

fn thermal_number(file string) i64 {
	return read_word(thermal_class + file).i64()
}

// Waits for the polling thread to make `passes` more passes.
fn wait_passes(passes int) bool {
	target := thermal_number('poll_count') + passes
	for _ in 0 .. 200 {
		if thermal_number('poll_count') >= target {
			return true
		}
		sleep_ms(50)
	}
	return false
}

fn zone_called(kind string) string {
	names := list_dir(thermal_class) or { return '' }
	for name in names {
		if name.starts_with('thermal_zone') && read_word('${thermal_class}${name}/type') == kind {
			return '${thermal_class}${name}/'
		}
	}
	return ''
}

fn scenario_thermal(mut t Test) {
	names := list_dir(thermal_class) or { []string{} }
	zones := names.filter(it.starts_with('thermal_zone'))
	t.check(zones.len == 0, 'a machine with no sensors has zones: ${zones}')
	t.check(thermal_number('thermal_limit') == 100, 'thermal_limit is ${thermal_number('thermal_limit')} with no zone')
	t.check(read_word('${cpu_root}/cpufreq/thermal_limit') == '100', 'the frequency drivers see a limit of ${read_word('${cpu_root}/cpufreq/thermal_limit')}')
	before := thermal_number('poll_count')
	sleep_ms(1500)
	t.check(thermal_number('poll_count') == before, 'the polling thread runs with nothing to poll')
	$if amd64 {
		probe := read_text(thermal_class + 'x86_probe') or {
			t.check(false, 'x86_probe: ${err.msg()}')
			return
		}
		// 0x1b is the local APIC's base, which every processor has; 0x804
		// is a reserved x2APIC register, which none does.
		t.check(probe.contains('rdmsr 0x0000001b: 0x'), 'a register that exists could not be read')
		t.check(probe.contains('rdmsr 0x00000804: fault'), 'a register that does not exist did not fail cleanly')
		t.check(probe.contains('rdmsr 0x00000804 on cpu 1: fault'), 'a missing register read on another CPU did not fail cleanly')
		t.info('missing registers fail cleanly, here and on another CPU; no sensor driver started')
	}
}

fn scenario_thermal_selftest(mut t Test) {
	zone := zone_called('vinix_selftest')
	t.check(zone != '', 'no vinix_selftest zone: is this a kernel built with -d thermal_selftest?')
	if zone == '' {
		return
	}
	set := fn [zone] (millidegrees string) {
		write_text(zone + 'emul_temp', millidegrees) or {}
	}
	limit := fn () i64 {
		return thermal_number('thermal_limit')
	}
	set('70000')
	wait_passes(2)
	t.check(limit() == 100, 'the limit is ${limit()} at 70 degrees')

	// Heating: one step down for each reading that is higher than the last.
	mut heating := []i64{}
	for degrees in ['80000', '82000', '84000', '86000'] {
		set(degrees)
		wait_passes(1)
		// The reading may have been taken twice; only a rise costs a step.
		wait_passes(1)
		heating << limit()
	}
	t.check(heating == [i64(90), 80, 70, 60], 'heating through 80, 82, 84, 86 degrees gave limits ${heating}')
	t.check(thermal_number('cooling_device0/cur_state') == 4, 'cur_state is ${thermal_number('cooling_device0/cur_state')} at a limit of 60')
	// Holding: the same temperature again costs nothing more.
	wait_passes(3)
	t.check(limit() == 60, 'the limit moved to ${limit()} at a steady 86 degrees')

	// Cooling below the hysteresis gives it all back.
	set('70000')
	t.check(wait_until(8000, fn () bool {
		return thermal_number('thermal_limit') == 100
	}), 'the limit is ${limit()} eight seconds after cooling to 70 degrees')

	// Hot: straight to the floor, and back when it has cooled.
	set('96000')
	wait_passes(2)
	t.check(limit() == 10, 'the limit is ${limit()} at 96 degrees, past the hot trip')
	set('60000')
	t.check(wait_until(15000, fn () bool {
		return thermal_number('thermal_limit') == 100
	}), 'the limit is ${limit()} fifteen seconds after cooling from hot')

	// A sensor that stops answering is not a temperature.
	set('82000')
	wait_passes(2)
	held := limit()
	set('error')
	t.check(wait_until(10000, fn [zone] () bool {
		return read_word(zone + 'mode') == 'disabled'
	}), 'the zone is still ${read_word(zone + 'mode')} after its sensor failed')
	t.check(limit() == held, 'a failing sensor moved the limit from ${held} to ${limit()}')
	set('60000')
	write_text(zone + 'mode', 'enabled') or { t.check(false, 'enabling the zone: ${err.msg()}') }
	t.check(wait_until(15000, fn () bool {
		return thermal_number('thermal_limit') == 100
	}), 'the limit is ${limit()} after the zone was enabled again')
	t.info('heating gave limits ${heating}; hot gave 10; a failed sensor held ${held}')

	// The verdict first: past the critical trip the kernel turns the machine
	// off, and this program does not get to say anything afterwards.
	sleep_ms(200)
	if t.failures == 0 {
		t.say('HWTEST PASS ${t.scenario}')
	} else {
		t.say('HWTEST FAIL ${t.scenario}')
		power_off()
	}
	t.step('going critical')
	set('106000')
	idle()
}

fn scenario_iommu_selftest(mut t Test) {
	names := list_dir('/sys/class/iommu') or { []string{} }
	t.check(names.len > 0, 'no IOMMU unit is listed')
	for name in names {
		path := '/sys/class/iommu/${name}/selftest'
		if !os.exists(path) {
			t.check(false, '${name} has no selftest file: is this a kernel built with the self-test?')
			continue
		}
		report := read_text(path) or { '' }
		t.check(report.contains('result: PASS'), '${name}: ${report.replace('\n', ' | ')}')
		for line in report.split_into_lines() {
			if line.starts_with('result:') || line.starts_with('checks:') {
				t.info('${name} ${line}')
			}
		}
	}
}
