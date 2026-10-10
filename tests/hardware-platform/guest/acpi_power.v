// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// acpi-power: a PC's battery, charger and lid, as firmware describes them.
//
// QEMU's PC has none of the three, so the host gives this machine an ACPI
// table with a battery, a charger and a lid that act out a script (see
// power_bench() in the controller): charging, then the charger pulled and the
// battery draining at a steady 12 W to its last two percent, with the lid
// shut and opened again on the way. This program reads /sys once a second and
// checks that the kernel followed the script:
//
//   - what the battery is: capacity, voltage, chemistry, maker, cycle count;
//   - charging with the charger online, then discharging with it offline and
//     the machine reporting that it runs on its battery;
//   - a charge that only falls, and a time to empty that is the charge
//     divided by the rate;
//   - a sleep when the lid shuts, ended by the alarm this program keeps set;
//   - `Low` when little is left, then the request to power off that a
//     critical battery makes of init.
@[has_globals]
module main

import os

const battery = '/sys/class/power_supply/BAT0/'
const charger = '/sys/class/power_supply/ADP0/'

__global acpi_power_off_asked = false

fn on_critical_battery(_ os.Signal) {
	acpi_power_off_asked = true
}

fn scenario_acpi_power(mut t Test) {
	os.signal_opt(.usr2, on_critical_battery) or {
		t.check(false, 'could not install a SIGUSR2 handler: ${err}')
		return
	}
	// What the battery is. These do not change with the script.
	t.check(read_word(battery + 'type') == 'Battery', 'BAT0 type is "${read_word(battery + 'type')}"')
	t.check(read_word(charger + 'type') == 'Mains', 'ADP0 type is "${read_word(charger + 'type')}"')
	t.check(read_word(battery + 'present') == '1', 'BAT0 is not present')
	t.check(read_word(battery + 'energy_full_design') == '50000000', 'energy_full_design is ${read_word(
		battery + 'energy_full_design')}')
	t.check(read_word(battery + 'energy_full') == '48000000', 'energy_full is ${read_word(battery +
		'energy_full')}')
	t.check(read_word(battery + 'voltage_min_design') == '11400000', 'voltage_min_design is ${read_word(
		battery + 'voltage_min_design')}')
	t.check(read_word(battery + 'cycle_count') == '123', 'cycle_count is ${read_word(battery +
		'cycle_count')}')
	t.check(read_word(battery + 'technology') == 'Li-ion', 'technology is "${read_word(battery +
		'technology')}"')
	t.check(read_word(battery + 'model_name') == 'VNXBAT', 'model_name is "${read_word(battery +
		'model_name')}"')
	t.check(read_word(battery + 'manufacturer') == 'Vinix', 'manufacturer is "${read_word(battery +
		'manufacturer')}"')
	t.check(read_word(battery + 'serial_number') == '0042', 'serial_number is "${read_word(battery +
		'serial_number')}"')
	// A battery that counts energy has no charge files.
	t.check(!os.exists(battery + 'charge_now'), 'BAT0 has charge_now as well as energy_now')
	for device in ['BAT0:0', 'ADP0:0', 'LID0:0'] {
		t.check(os.is_link('/sys/bus/acpi/devices/${device}/driver'), '/sys/bus/acpi/devices/${device} has no driver')
	}

	mut saw_charging := false
	mut saw_discharging := false
	mut saw_low := false
	mut saw_lid_sleep := false
	mut last_energy := i64(0)
	mut estimates := 0
	for _ in 0 .. 70 {
		if acpi_power_off_asked {
			break
		}
		// Whenever the lid shuts, an alarm no more than three seconds away
		// is what opens this program's eyes again.
		write_text('/sys/class/rtc/rtc0/wakealarm', '+3') or {}
		status := read_word(battery + 'status')
		energy := read_word(battery + 'energy_now').i64()
		power := read_word(battery + 'power_now').i64()
		online := read_word(charger + 'online')
		if status == 'Charging' {
			saw_charging = true
			t.check(online == '1', 'charging with the charger reported offline')
			t.check(!saw_discharging, 'charging again after the charger was pulled')
		} else if status == 'Discharging' {
			if !saw_discharging {
				saw_discharging = true
				last_energy = energy
			}
			t.check(energy <= last_energy, 'the charge rose while discharging: ${last_energy} -> ${energy}')
			last_energy = energy
			// The charger's file may be a read behind the battery's for a
			// moment after it is pulled; the policy file follows both.
			to_empty := read_word(battery + 'time_to_empty_now').i64()
			if power > 0 && to_empty > 0 && read_word(battery + 'energy_now').i64() == energy {
				expected := energy * 3600 / power
				off := if to_empty > expected { to_empty - expected } else { expected - to_empty }
				t.check(off * 50 <= expected + 50, 'time_to_empty_now is ${to_empty} s with ${energy} uWh at ${power} uW (${expected} s)')
				estimates++
			}
		}
		if read_word(battery + 'capacity_level') == 'Low' {
			if !saw_low {
				// Long after the one reading that claimed to be critical with
				// most of the charge left, and before the battery really is.
				t.check(!acpi_power_off_asked, 'one critical reading from a battery that was not asked for a power off')
			}
			saw_low = true
		}
		if !saw_lid_sleep && read_word('/sys/power/lid/closes') == '1'
			&& read_word('/sys/power/suspend_stats/success') == '1' {
			saw_lid_sleep = true
			t.info('the lid shut and the machine slept ${read_word('/sys/power/suspend_stats/last_sleep_ms')} ms, woken by ${read_word('/sys/power/suspend_stats/last_wake')}')
		}
		sleep_ms(1100)
	}
	write_text('/sys/class/rtc/rtc0/wakealarm', '0') or {}
	t.check(saw_charging, 'the battery was never seen charging')
	t.check(saw_discharging, 'the battery was never seen discharging')
	t.check(estimates >= 3, 'time_to_empty_now was checked only ${estimates} times')
	t.check(saw_lid_sleep, 'the lid shutting did not put the machine to sleep: lid closes ${read_word('/sys/power/lid/closes')}, sleeps ${read_word('/sys/power/suspend_stats/success')}')
	t.check(read_word('/sys/power/lid/state') == 'open', 'the lid is ${read_word('/sys/power/lid/state')} at the end')
	t.check(saw_low, 'capacity_level was never Low')
	t.check(acpi_power_off_asked, 'a critical battery did not ask init to power off')
	t.check(read_word(charger + 'online') == '0', 'the charger is online at the end')
	t.check(read_word('/sys/class/power_supply/policy/on_battery') == '1', 'on_battery is not 1 at the end')
	t.check(read_word(battery + 'capacity_level') == 'Critical', 'capacity_level is ${read_word(battery +
		'capacity_level')} at the end')
	t.info('at the end: ${read_word(battery + 'capacity')}% ${read_word(battery + 'status')}, ${read_word(
		battery + 'energy_now')} uWh, time left checked ${estimates} times')
}
