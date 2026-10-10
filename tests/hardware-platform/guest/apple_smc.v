// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// apple-smc-selftest and its three variants: Apple's SMC as a battery, a
// charger, temperatures and a fan.
//
// No emulator has an SMC, so these need a kernel built with
// -d applesmc_selftest, in which a simulated one answers in place of the
// mailbox (kernel/apple/smc/core/sim_d_applesmc_selftest.v). This program
// moves that SMC through a battery's day by writing to
// /sys/devices/platform/apple-smc/smc/selftest, and checks what the kernel
// makes of it everywhere a program would look: /sys/class/power_supply,
// /sys/class/thermal, /sys/class/hwmon, and the two device nodes the desktop
// reads, /dev/battery and /dev/battery-power.
//
//   apple-smc-selftest          a laptop with a fan and a charge limit: what
//                               it is; the charger pulled; readings that are
//                               garbage once; the charge limit; a sleep; no
//                               memory kept by any of it; low, then critical
//                               and the request to power off; and at the end
//                               an SMC that stops answering
//   apple-smc-selftest-bare     one with no fan and no charge limit: neither
//                               has files
//   apple-smc-selftest-options  vinix.apple_smc=nosensors,nolimit
//   apple-smc-selftest-legacy   vinix.apple_smc=legacy: the device nodes and
//                               nothing else
@[has_globals]
module main

import os

#include <errno.h>

const smc_battery = '/sys/class/power_supply/macsmc-battery/'
const smc_charger = '/sys/class/power_supply/macsmc-ac/'
const smc_device = '/sys/devices/platform/apple-smc/'
const smc_status = '/sys/devices/platform/apple-smc/smc/status'
const smc_keys = '/sys/devices/platform/apple-smc/smc/keys'
const smc_control = '/sys/devices/platform/apple-smc/smc/selftest'
const smc_state = '/sys/devices/platform/apple-smc/smc/selftest_state'
const smc_limit = '/sys/class/power_supply/macsmc-battery/charge_control_end_threshold'

__global smc_power_off_asked = false

fn smc_on_critical(_ os.Signal) {
	smc_power_off_asked = true
}

// The value on the line `name value` of one of the driver's files; -1 when
// there is no such line.
fn smc_line(path string, name string) string {
	text := read_text(path) or { return '' }
	for line in text.split_into_lines() {
		if line.starts_with(name + ' ') {
			return line[name.len + 1..]
		}
	}
	return ''
}

fn smc_count(path string, name string) i64 {
	value := smc_line(path, name)
	return if value == '' { i64(-1) } else { value.i64() }
}

// Tell the simulated SMC something.
fn smc_sim(mut t Test, command string) {
	write_text(smc_control, command) or { t.check(false, 'selftest "${command}": ${err}') }
}

fn smc_check_word(mut t Test, path string, wanted string) {
	found := read_word(path)
	t.check(found == wanted, '${path} is "${found}", not "${wanted}"')
}

// Whether `path` comes to read `wanted` within `milliseconds`.
fn smc_wait_word(path string, wanted string, milliseconds int) bool {
	mut waited := 0
	for {
		if read_word(path) == wanted {
			return true
		}
		if waited >= milliseconds {
			return false
		}
		sleep_ms(100)
		waited += 100
	}
	return false
}

fn smc_expect(mut t Test, path string, wanted string, milliseconds int) {
	if !smc_wait_word(path, wanted, milliseconds) {
		t.check(false, '${path} is "${read_word(path)}" and not "${wanted}" after ${milliseconds} ms')
	}
}

// The directories of the SMC's zone: in /sys/class/thermal and in
// /sys/class/hwmon, which share its number.
fn smc_zone() (string, string) {
	names := list_dir('/sys/class/thermal') or { return '', '' }
	for name in names {
		if name.starts_with('thermal_zone') && read_word('/sys/class/thermal/${name}/type') == 'macsmc' {
			number := name['thermal_zone'.len..]
			return '/sys/class/thermal/${name}/', '/sys/class/hwmon/hwmon${number}/'
		}
	}
	return '', ''
}

// What a write to the charge limit comes to: 0, or its errno.
fn smc_set_limit(percent string) int {
	write_text(smc_limit, percent) or { return err.code() }
	return 0
}

// What every variant has: the two device nodes, as documented.
fn smc_check_nodes(mut t Test, percent string) {
	whole := read_text('/dev/battery') or { 'unreadable' }
	t.check(whole == percent + '\n', '/dev/battery reads "${whole.trim_space()}", not ${percent}')
	// The telemetry has its first sample a tenth of a second after the node
	// is made, when the thread first runs; this program starts sooner.
	mut power := ''
	for _ in 0 .. 20 {
		power = read_text('/dev/battery-power') or { '' }
		if power != '' {
			break
		}
		sleep_ms(100)
	}
	t.check(power == 'voltage_mv: 12300\ncurrent_ma: 1500\npower_mw: 18450\n', '/dev/battery-power reads "${power.replace('\n',
		', ')}"')
	// A program that reads a byte at a time gets the same text.
	fd := C.open(c'/dev/battery', C.O_RDONLY)
	mut collected := []u8{}
	if fd >= 0 {
		mut one := [1]u8{}
		for C.read(fd, &one[0], 1) == 1 {
			collected << one[0]
		}
		C.close(fd)
	}
	t.check(collected.bytestr() == percent + '\n', 'read a byte at a time, /dev/battery is "${collected.bytestr().trim_space()}"')
	// Neither is to be written.
	wfd := C.open(c'/dev/battery', C.O_WRONLY)
	if wfd >= 0 {
		t.check(C.write(wfd, c'1', 1) < 0, '/dev/battery took a write')
		C.close(wfd)
	}
}

fn smc_check_device(mut t Test) {
	smc_check_word(mut t, smc_device + 'state', 'bound')
	t.check(os.is_link('/sys/bus/platform/devices/apple-smc/driver'), 'apple-smc has no driver link')
	t.check(os.exists('/sys/bus/platform/drivers/macsmc'), 'there is no macsmc driver')
	t.check(smc_line(smc_status, 'transport') == 'ok', 'transport is "${smc_line(smc_status, 'transport')}"')
	t.check(smc_count(smc_status, 'simulated') == 1, 'this is not a self-test kernel: its SMC is not simulated')
}

// The battery as the simulated SMC starts out: on its charger at 62 percent.
fn smc_check_charging(mut t Test) {
	smc_check_word(mut t, smc_battery + 'type', 'Battery')
	smc_check_word(mut t, smc_battery + 'present', '1')
	smc_check_word(mut t, smc_battery + 'status', 'Charging')
	smc_check_word(mut t, smc_battery + 'capacity', '62')
	smc_check_word(mut t, smc_battery + 'capacity_level', 'Normal')
	smc_check_word(mut t, smc_battery + 'charge_now', '2604000')
	smc_check_word(mut t, smc_battery + 'charge_full', '4200000')
	smc_check_word(mut t, smc_battery + 'charge_full_design', '4380000')
	smc_check_word(mut t, smc_battery + 'current_now', '1500000')
	smc_check_word(mut t, smc_battery + 'voltage_now', '12300000')
	smc_check_word(mut t, smc_battery + 'voltage_min_design', '9000000')
	smc_check_word(mut t, smc_battery + 'cycle_count', '77')
	smc_check_word(mut t, smc_battery + 'model_name', 'bq40z651')
	smc_check_word(mut t, smc_battery + 'serial_number', 'F5D0VINIX0SIM0001')
	smc_check_word(mut t, smc_battery + 'technology', 'Unknown')
	smc_check_word(mut t, smc_battery + 'time_to_full_now', '3900')
	smc_check_word(mut t, smc_battery + 'time_to_empty_now', '0')
	// It counts charge, so it has no energy files.
	t.check(!os.exists(smc_battery + 'energy_now'), 'the battery has energy_now as well as charge_now')
	uevent := read_text(smc_battery + 'uevent') or { '' }
	t.check(uevent.contains('POWER_SUPPLY_NAME=macsmc-battery\n') && uevent.contains('POWER_SUPPLY_CAPACITY=62\n')
		&& uevent.contains('POWER_SUPPLY_STATUS=Charging\n'), 'uevent is ${uevent.replace('\n', ', ')}')
	smc_check_word(mut t, smc_charger + 'type', 'Mains')
	smc_check_word(mut t, smc_charger + 'online', '1')
	smc_check_word(mut t, '/sys/class/power_supply/policy/on_battery', '0')
}

// The four temperatures, and nothing that could act on them.
fn smc_check_temperatures(mut t Test, zone string, hwmon string) {
	smc_check_word(mut t, zone + 'temp', '38500')
	smc_check_word(mut t, zone + 'mode', 'enabled')
	t.check(!os.exists(zone + 'trip_point_0_type'), 'the SMC zone has a trip point')
	smc_check_word(mut t, hwmon + 'name', 'macsmc_hwmon')
	labels := ['NAND Flash Temperature', 'Battery Hotspot', 'Charge Regulator Temp', 'WiFi/BT Module Temp']
	values := ['38500', '31250', '44000', '47000']
	for i in 0 .. 4 {
		smc_check_word(mut t, '${hwmon}temp${i + 1}_input', values[i])
		smc_check_word(mut t, '${hwmon}temp${i + 1}_label', labels[i])
		t.check(!os.exists('${hwmon}temp${i + 1}_crit'), 'temp${i + 1} has a critical limit nobody gave it')
		t.check(!os.exists('${hwmon}temp${i + 1}_max'), 'temp${i + 1} has a maximum nobody gave it')
	}
	t.check(!os.exists(hwmon + 'temp5_input'), 'there is a fifth temperature')
	smc_check_word(mut t, '/sys/class/thermal/critical_count', '0')
	smc_check_word(mut t, '/sys/class/thermal/thermal_limit', '100')
}

// ── A measuring loop that asks the kernel for no memory of its own ──────────

// Read `path` once into a buffer on the stack. The count of bytes, or -1.
fn smc_touch(path string) int {
	mut buffer := [256]u8{}
	fd := C.open(&char(path.str), C.O_RDONLY)
	if fd < 0 {
		return -1
	}
	count := int(C.read(fd, &buffer[0], 256))
	C.close(fd)
	return count
}

const smc_touched = [
	'/sys/class/power_supply/macsmc-battery/status',
	'/sys/class/power_supply/macsmc-battery/capacity',
	'/sys/class/power_supply/macsmc-battery/capacity_level',
	'/sys/class/power_supply/macsmc-battery/charge_now',
	'/sys/class/power_supply/macsmc-battery/current_now',
	'/sys/class/power_supply/macsmc-battery/voltage_now',
	'/sys/class/power_supply/macsmc-battery/time_to_empty_now',
	'/sys/class/power_supply/macsmc-battery/model_name',
	'/sys/class/power_supply/macsmc-battery/charge_control_end_threshold',
	'/sys/class/power_supply/macsmc-battery/uevent',
	'/sys/class/power_supply/macsmc-ac/online',
	'/sys/class/power_supply/policy/on_battery',
	'/sys/devices/platform/apple-smc/smc/status',
	'/sys/devices/platform/apple-smc/smc/keys',
	'/dev/battery',
	'/dev/battery-power',
]

// `rounds` rounds a quarter of a second apart, each reading every file above
// and the zone's five times. Returns how many reads came back empty-handed.
fn smc_read_round(rounds int, zone_temp string, hwmon_temp string, hwmon_fan string) int {
	mut failed := 0
	for _ in 0 .. rounds {
		for _ in 0 .. 5 {
			for path in smc_touched {
				if smc_touch(path) <= 0 {
					failed++
				}
			}
			if smc_touch(zone_temp) <= 0 || smc_touch(hwmon_temp) <= 0 || smc_touch(hwmon_fan) <= 0 {
				failed++
			}
		}
		sleep_ms(250)
	}
	return failed
}

// ── The scenarios ───────────────────────────────────────────────────────────

fn scenario_apple_smc_selftest(mut t Test) {
	os.signal_opt(.usr2, smc_on_critical) or {
		t.check(false, 'could not install a SIGUSR2 handler: ${err}')
		return
	}
	if !t.check(os.exists(smc_control), 'no ${smc_control}: this kernel has no simulated SMC') {
		return
	}
	// ── What the machine is ────────────────────────────────────────────────
	smc_check_device(mut t)
	smc_check_nodes(mut t, '62')
	for name in ['classes', 'battery', 'charger', 'fans', 'charge_limit'] {
		t.check(smc_count(smc_status, name) == 1, 'status says ${name} ${smc_count(smc_status, name)}')
	}
	t.check(smc_count(smc_status, 'temperatures') == 4, 'status says ${smc_count(smc_status, 'temperatures')} temperatures')
	// Starting up read keys and asked about them. It stored none.
	t.check(smc_count(smc_status, 'key_writes') == 0, 'the driver wrote ${smc_count(smc_status, 'key_writes')} keys while starting')
	t.check(smc_count(smc_state, 'writes') == 0, 'the SMC was sent ${smc_count(smc_state, 'writes')} writes while starting')
	t.check(smc_count(smc_state, 'infos') > 20, 'the SMC was asked about only ${smc_count(smc_state, 'infos')} keys')
	keys := read_text(smc_keys) or { '' }
	for line in ['B0RM ui16 2 0x80', 'BCF0 ui32 4 0x80', 'CHNC hex_ 8 0x80', 'CHWA flag 1 0xc0', 'TH0x flt  4 0x80',
		'TCHP ioft 8 0x80', 'F0Ac flt  4 0x80'] {
		t.check(keys.contains(line + '\n'), 'keys has no line "${line}": ${keys.replace('\n', ', ')}')
	}
	smc_check_charging(mut t)
	smc_check_word(mut t, smc_limit, '100')
	zone, hwmon := smc_zone()
	if !t.check(zone != '', 'no thermal zone of type macsmc') {
		return
	}
	smc_check_temperatures(mut t, zone, hwmon)
	smc_check_word(mut t, hwmon + 'fan1_input', '2400')
	smc_check_word(mut t, hwmon + 'fan1_label', 'Fan')
	smc_check_word(mut t, hwmon + 'fan1_min', '1350')
	smc_check_word(mut t, hwmon + 'fan1_max', '5349')
	// The SMC runs its fan; nothing here may.
	t.check(!os.exists(hwmon + 'pwm1'), 'the SMC fan can be driven through pwm1')
	t.check(!os.exists(hwmon + 'fan2_input'), 'there is a second fan')

	// ── Sensors move ───────────────────────────────────────────────────────
	// 55.5 degrees, and 3000 revolutions a minute, as the floats they are.
	smc_sim(mut t, 'set TB0T 00005e42')
	smc_sim(mut t, 'set F0Ac 00803b45')
	smc_expect(mut t, hwmon + 'temp2_input', '55500', 4000)
	smc_expect(mut t, hwmon + 'fan1_input', '3000', 4000)

	// ── The charger is pulled ──────────────────────────────────────────────
	smc_sim(mut t, 'scene unplugged')
	smc_expect(mut t, smc_battery + 'status', 'Discharging', 4000)
	smc_expect(mut t, smc_charger + 'online', '0', 4000)
	smc_expect(mut t, '/sys/class/power_supply/policy/on_battery', '1', 4000)
	smc_expect(mut t, smc_battery + 'capacity', '60', 4000)
	smc_expect(mut t, smc_battery + 'charge_now', '2520000', 4000)
	smc_expect(mut t, smc_battery + 'current_now', '1200000', 4000)
	smc_expect(mut t, smc_battery + 'voltage_now', '11700000', 4000)
	// The SMC's own estimate, in minutes there and seconds here.
	smc_expect(mut t, smc_battery + 'time_to_empty_now', '7800', 8000)
	smc_check_word(mut t, smc_battery + 'time_to_full_now', '0')
	t.check(smc_wait_word('/dev/battery', '60', 3000), '/dev/battery reads "${read_word('/dev/battery')}" with the charger pulled')
	power := read_text('/dev/battery-power') or { '' }
	t.check(power.contains('current_ma: -1200\n') && power.contains('power_mw: -14000\n'), '/dev/battery-power reads "${power.replace('\n',
		', ')}" while discharging')

	// ── Readings that are garbage, once ────────────────────────────────────
	// An empty battery, the firmware's flag that it is about to give out, a
	// remaining charge of all ones, a temperature that is not a number and
	// one of five hundred degrees: each for a single read.
	before_jumps := smc_count(smc_status, 'percent_jumps')
	before_unconfirmed := smc_count(smc_status, 'critical_unconfirmed')
	before_implausible := smc_count(smc_status, 'implausible')
	smc_sim(mut t, 'once BUIC 00')
	smc_sim(mut t, 'once BCF0 01000000')
	smc_sim(mut t, 'once B0RM ffff')
	smc_sim(mut t, 'once TB0T ffffffff')
	smc_sim(mut t, 'once TH0x 0000fa43')
	mut lowest := 100
	mut looks := 0
	for _ in 0 .. 40 {
		capacity := read_word(smc_battery + 'capacity').int()
		if capacity < lowest {
			lowest = capacity
		}
		level := read_word(smc_battery + 'capacity_level')
		t.check(level == 'Normal', 'capacity_level is ${level} after one wild reading')
		charge := read_word(smc_battery + 'charge_now').i64()
		t.check(charge <= 4200000, 'charge_now is ${charge}, more than the battery holds')
		for file in ['temp1_input', 'temp2_input'] {
			word := read_word(hwmon + file)
			wanted := if file == 'temp1_input' { '38500' } else { '55500' }
			t.check(word == '' || word == wanted, '${file} read "${word}" after one wild reading')
		}
		looks++
		sleep_ms(150)
	}
	t.check(lowest == 60, 'capacity went to ${lowest} after one reading of 0')
	t.check(!smc_power_off_asked, 'one wild reading asked for a power off')
	t.check(smc_count(smc_status, 'percent_jumps') == before_jumps + 1, 'percent_jumps went from ${before_jumps} to ${smc_count(smc_status,
		'percent_jumps')}')
	t.check(smc_count(smc_status, 'critical_unconfirmed') == before_unconfirmed + 1, 'critical_unconfirmed went from ${before_unconfirmed} to ${smc_count(smc_status,
		'critical_unconfirmed')}')
	t.check(smc_count(smc_status, 'implausible') == before_implausible + 3, 'implausible went from ${before_implausible} to ${smc_count(smc_status,
		'implausible')}')
	smc_check_word(mut t, '/sys/class/thermal/critical_count', '0')
	smc_check_word(mut t, zone + 'mode', 'enabled')
	smc_check_word(mut t, smc_battery + 'status', 'Discharging')
	t.info('garbage: ${looks} looks over six seconds, capacity never under ${lowest}; jumps ${smc_count(smc_status,
		'percent_jumps')}, unconfirmed ${smc_count(smc_status, 'critical_unconfirmed')}, implausible ${smc_count(smc_status,
		'implausible')}')

	// ── The charge limit ───────────────────────────────────────────────────
	t.check(smc_set_limit('80') == 0, 'a limit of 80 was refused')
	smc_check_word(mut t, smc_limit, '80')
	t.check(smc_count(smc_state, 'writes') == 1 && smc_line(smc_state, 'last_written') == 'CHWA'
		&& smc_count(smc_state, 'last_byte') == 1 && smc_count(smc_state, 'chwa') == 1, 'after a limit of 80 the SMC has ${(read_text(smc_state) or {
		''
	}).replace('\n', ', ')}')
	// Only what the firmware takes is sent at all.
	for refused in ['70', '50', '90', '95', '99'] {
		answer := smc_set_limit(refused)
		t.check(answer == C.EINVAL, 'a limit of ${refused} came to errno ${answer}')
	}
	t.check(smc_count(smc_state, 'writes') == 1, 'a refused limit reached the SMC: ${smc_count(smc_state, 'writes')} writes')
	smc_check_word(mut t, smc_limit, '80')
	t.check(smc_set_limit('100') == 0, 'a limit of 100 was refused')
	smc_check_word(mut t, smc_limit, '100')
	t.check(smc_count(smc_state, 'chwa') == 0 && smc_count(smc_state, 'writes') == 2, 'after a limit of 100 the SMC has chwa ${smc_count(smc_state,
		'chwa')} and ${smc_count(smc_state, 'writes')} writes')
	// A firmware that says yes and keeps what it had is found out by the
	// reading back.
	smc_sim(mut t, 'fault ignore-writes')
	not_kept := smc_set_limit('80')
	t.check(not_kept == C.EIO, 'a limit the SMC did not keep came to errno ${not_kept}')
	smc_check_word(mut t, smc_limit, '100')
	smc_sim(mut t, 'fault none')
	// And one that refuses.
	smc_sim(mut t, 'protect CHWA')
	not_taken := smc_set_limit('80')
	t.check(not_taken == C.EIO, 'a limit the SMC refused came to errno ${not_taken}')
	smc_check_word(mut t, smc_limit, '100')
	t.check(smc_line(smc_status, 'transport') == 'ok', 'a refused write ended the channel')
	writes := smc_count(smc_state, 'writes')
	t.check(smc_count(smc_status, 'key_writes') == writes, 'the driver counts ${smc_count(smc_status, 'key_writes')} writes and the SMC ${writes}')
	t.info('charge limit: 80, 100 set and read back; 5 values refused unsent; ${writes} writes in all, every one of CHWA')

	// ── No memory kept ─────────────────────────────────────────────────────
	// Twenty-five rounds first, so that whatever grows once has grown; then
	// the kernel's grace period for what it frees late.
	smc_read_round(25, zone + 'temp', hwmon + 'temp2_input', hwmon + 'fan1_input')
	sleep_ms(1500)
	passes_before := smc_count(smc_status, 'passes')
	heap_before := heap_usage() or {
		t.check(false, '${err}')
		return
	}
	empty := smc_read_round(60, zone + 'temp', hwmon + 'temp2_input', hwmon + 'fan1_input')
	sleep_ms(1500)
	heap_after := heap_usage() or {
		t.check(false, '${err}')
		return
	}
	passes_after := smc_count(smc_status, 'passes')
	t.check(empty == 0, '${empty} reads came back empty while everything was in order')
	t.check(passes_after - passes_before >= 14, 'only ${passes_after - passes_before} passes in the measured time')
	t.check(heap_after.objects - heap_before.objects <= heap_noise_objects, 'live heap objects went from ${heap_before.objects} to ${heap_after.objects}')
	t.check(heap_after.large_pages <= heap_before.large_pages, 'large pages went from ${heap_before.large_pages} to ${heap_after.large_pages}')
	t.info('${passes_after - passes_before} passes and ${60 * 5 * 19} reads: live heap objects ${heap_before.objects} -> ${heap_after.objects}, large pages ${heap_before.large_pages} -> ${heap_after.large_pages}')

	// ── A sleep ────────────────────────────────────────────────────────────
	// A rehearsal, then four seconds asleep ended by the alarm. The thread
	// must have left the SMC alone for both, and found it again after.
	write_text('/sys/power/pm_test', 'devices') or { t.check(false, 'pm_test: ${err}') }
	write_text('/sys/power/state', 'freeze') or { t.check(false, 'the rehearsal was refused: ${err}') }
	write_text('/sys/power/pm_test', 'none') or {}
	t.check(smc_count(smc_status, 'parks') == 1, 'parks is ${smc_count(smc_status, 'parks')} after a rehearsal')
	smc_check_word(mut t, smc_battery + 'status', 'Discharging')
	rounds_before := smc_count(smc_status, 'rounds')
	commands_before := smc_count(smc_state, 'commands')
	write_text('/sys/class/rtc/rtc0/wakealarm', '+4') or { t.check(false, 'wakealarm: ${err}') }
	write_text('/sys/power/state', 'freeze') or { t.check(false, 'the sleep was refused: ${err}') }
	rounds_slept := smc_count(smc_status, 'rounds') - rounds_before
	commands_slept := smc_count(smc_state, 'commands') - commands_before
	slept := read_word('/sys/power/suspend_stats/last_sleep_ms').int()
	t.check(slept >= 3000, 'the machine slept ${slept} ms')
	t.check(smc_count(smc_status, 'parks') == 2 && smc_count(smc_status, 'late_parks') == 0, 'parks ${smc_count(smc_status,
		'parks')}, late ${smc_count(smc_status, 'late_parks')} after a sleep')
	// Forty turns of the thread fit in four seconds, and two hundred
	// exchanges. Parked, it has the few before the sleep and after it.
	t.check(rounds_slept <= 15, 'the thread took ${rounds_slept} turns across a sleep of ${slept} ms')
	t.check(commands_slept <= 80, 'the SMC was sent ${commands_slept} commands across a sleep of ${slept} ms')
	// Back at once: devices resume before programs do.
	smc_check_word(mut t, smc_battery + 'status', 'Discharging')
	smc_check_word(mut t, smc_battery + 'capacity', '60')
	smc_check_word(mut t, smc_charger + 'online', '0')
	smc_check_word(mut t, zone + 'mode', 'enabled')
	smc_check_word(mut t, zone + 'temp', '38500')
	t.check(smc_count(smc_status, 'fresh') == 1 && smc_count(smc_status, 'parked') == 0, 'after the sleep the status is ${(read_text(smc_status) or {
		''
	}).replace('\n', ', ')}')
	t.check(smc_wait_word('/dev/battery', '60', 2000), '/dev/battery reads "${read_word('/dev/battery')}" after a sleep')
	smc_check_word(mut t, smc_device + 'state', 'bound')
	t.info('sleep: ${slept} ms, ${rounds_slept} turns of the thread and ${commands_slept} commands across it')

	// ── Low, then critical ─────────────────────────────────────────────────
	smc_sim(mut t, 'scene low')
	smc_expect(mut t, smc_battery + 'capacity', '8', 5000)
	smc_expect(mut t, smc_battery + 'capacity_level', 'Low', 3000)
	smc_expect(mut t, smc_battery + 'charge_now', '336000', 3000)
	smc_expect(mut t, smc_battery + 'time_to_empty_now', '1020', 8000)
	t.check(!smc_power_off_asked, 'a low battery asked for a power off')
	smc_sim(mut t, 'scene critical')
	smc_expect(mut t, smc_battery + 'capacity', '2', 5000)
	smc_expect(mut t, smc_battery + 'capacity_level', 'Critical', 3000)
	// The class waits for five seconds of agreement before it asks.
	mut waited := 0
	for !smc_power_off_asked && waited < 15000 {
		sleep_ms(100)
		waited += 100
	}
	t.check(smc_power_off_asked, 'a critical battery did not ask init to power off within 15 s')
	t.check(waited >= 3000, 'a critical battery asked for a power off after only ${waited} ms')
	smc_check_word(mut t, smc_battery + 'status', 'Discharging')
	t.info('critical: asked for a power off ${waited} ms after the battery read 2%')

	// ── The SMC stops answering ────────────────────────────────────────────
	smc_sim(mut t, 'fault silent')
	t.check(smc_wait_word(smc_battery + 'status', 'Unknown', 6000), 'status is ${read_word(smc_battery + 'status')} with an SMC that does not answer')
	// No figure that was true a while ago, and nothing claimed.
	for file in ['capacity', 'charge_now', 'charge_full', 'current_now', 'voltage_now', 'time_to_empty_now',
		'cycle_count'] {
		smc_check_word(mut t, smc_battery + file, '0')
	}
	smc_check_word(mut t, smc_battery + 'capacity_level', 'Unknown')
	smc_check_word(mut t, smc_battery + 'present', '1')
	smc_check_word(mut t, smc_charger + 'online', '0')
	// What the battery is, and what it was set to, are not readings.
	smc_check_word(mut t, smc_battery + 'model_name', 'bq40z651')
	smc_check_word(mut t, smc_battery + 'charge_full_design', '4380000')
	smc_check_word(mut t, smc_limit, '100')
	unanswered := smc_set_limit('100')
	t.check(unanswered == C.EIO, 'a limit given to an SMC that does not answer came to errno ${unanswered}')
	if stale := read_text('/dev/battery') {
		t.check(false, '/dev/battery still reads "${stale.trim_space()}"')
	} else {
		t.check(err.code() == C.EIO, '/dev/battery failed with errno ${err.code()}')
	}
	t.check((read_text('/dev/battery-power') or { '' }) == '', '/dev/battery-power still reads')
	smc_check_word(mut t, zone + 'temp', '')
	smc_check_word(mut t, hwmon + 'temp3_input', '')
	smc_check_word(mut t, hwmon + 'fan1_input', '')
	t.check(smc_line(smc_status, 'transport') != 'ok' && smc_count(smc_status, 'fresh') == 0, 'the status is ${(read_text(smc_status) or {
		''
	}).replace('\n', ', ')}')
	// A zone whose sensor is gone is switched off, and nothing else happens.
	t.check(smc_wait_word(zone + 'mode', 'disabled', 9000), 'the zone is ${read_word(zone + 'mode')} with no readings')
	smc_check_word(mut t, '/sys/class/thermal/critical_count', '0')
	smc_check_word(mut t, '/sys/class/thermal/thermal_limit', '100')
	t.check(smc_count(smc_state, 'violations') == 0 && smc_count(smc_state, 'unknown') == 0, 'the SMC saw ${smc_count(smc_state,
		'violations')} breaches of the protocol and ${smc_count(smc_state, 'unknown')} unknown commands')
	t.info('silent: transport "${smc_line(smc_status, 'transport')}"; in all ${smc_count(smc_state, 'commands')} commands, ${smc_count(smc_state,
		'reads')} reads, ${smc_count(smc_state, 'infos')} descriptions, ${smc_count(smc_state, 'writes')} writes, violations ${smc_count(smc_state,
		'violations')}')
}

// A laptop with no fan and no charge limit, whose firmware stores the
// remaining charge the newer way round.
fn scenario_apple_smc_selftest_bare(mut t Test) {
	if !t.check(os.exists(smc_control), 'no ${smc_control}: this kernel has no simulated SMC') {
		return
	}
	smc_check_device(mut t)
	smc_check_nodes(mut t, '62')
	t.check(smc_count(smc_status, 'fans') == 0 && smc_count(smc_status, 'charge_limit') == 0, 'status says fans ${smc_count(smc_status,
		'fans')}, charge_limit ${smc_count(smc_status, 'charge_limit')}')
	smc_check_charging(mut t)
	// What the SMC has not got has no file.
	t.check(!os.exists(smc_limit), 'there is a charge limit file with no key behind it')
	zone, hwmon := smc_zone()
	if !t.check(zone != '', 'no thermal zone of type macsmc') {
		return
	}
	smc_check_temperatures(mut t, zone, hwmon)
	for file in ['fan1_input', 'fan1_label', 'fan1_min', 'fan1_max', 'pwm1'] {
		t.check(!os.exists(hwmon + file), 'a machine with no fan has ${file}')
	}
	keys := read_text(smc_keys) or { '' }
	t.check(keys.contains('BCF0 ui8  1 0x80\n') && !keys.contains('CHWA') && !keys.contains('F0Ac'), 'keys is ${keys.replace('\n',
		', ')}')
	// One byte long on this firmware, and still not believed at one look.
	smc_sim(mut t, 'scene unplugged')
	smc_expect(mut t, smc_battery + 'status', 'Discharging', 4000)
	smc_expect(mut t, smc_battery + 'charge_now', '2520000', 4000)
	smc_sim(mut t, 'once BCF0 01')
	sleep_ms(3500)
	t.check(smc_count(smc_status, 'critical_unconfirmed') == 1, 'critical_unconfirmed is ${smc_count(smc_status, 'critical_unconfirmed')}')
	smc_sim(mut t, 'scene full')
	smc_expect(mut t, smc_battery + 'status', 'Full', 5000)
	smc_expect(mut t, smc_battery + 'capacity', '100', 5000)
	smc_expect(mut t, smc_battery + 'capacity_level', 'Full', 3000)
	smc_expect(mut t, smc_charger + 'online', '1', 3000)
	smc_expect(mut t, '/sys/class/power_supply/policy/on_battery', '0', 3000)
	t.check(smc_count(smc_state, 'writes') == 0 && smc_count(smc_state, 'violations') == 0, 'the SMC saw ${smc_count(smc_state,
		'writes')} writes and ${smc_count(smc_state, 'violations')} breaches of the protocol')
}

// The whole laptop, with the sensors and the charge limit asked to be left
// alone.
fn scenario_apple_smc_selftest_options(mut t Test) {
	if !t.check(os.exists(smc_control), 'no ${smc_control}: this kernel has no simulated SMC') {
		return
	}
	smc_check_device(mut t)
	smc_check_nodes(mut t, '62')
	smc_check_charging(mut t)
	t.check(smc_count(smc_status, 'temperatures') == 0 && smc_count(smc_status, 'fans') == 0
		&& smc_count(smc_status, 'charge_limit') == 0, 'status is ${(read_text(smc_status) or { '' }).replace('\n',
		', ')}')
	zone, _ := smc_zone()
	t.check(zone == '', 'there is a zone ${zone} with vinix.apple_smc=nosensors')
	t.check(!os.exists(smc_limit), 'there is a charge limit file with vinix.apple_smc=nolimit')
	keys := read_text(smc_keys) or { '' }
	t.check(keys.contains('B0RM ui16 2 0x80\n') && !keys.contains('CHWA') && !keys.contains('TH0x')
		&& !keys.contains('F0Ac'), 'keys is ${keys.replace('\n', ', ')}')
	sleep_ms(6500)
	// Six passes on: sixteen keys of the battery and the charger and its two
	// texts were asked about, and the limit key, the sensors and the fans
	// never were.
	t.check(smc_count(smc_state, 'infos') == 18, 'the SMC was asked about ${smc_count(smc_state, 'infos')} keys')
	t.check(smc_count(smc_state, 'writes') == 0, 'the SMC saw ${smc_count(smc_state, 'writes')} writes')
	smc_check_word(mut t, smc_battery + 'status', 'Charging')
}

// Nothing but the two device nodes, as before any of this.
fn scenario_apple_smc_selftest_legacy(mut t Test) {
	if !t.check(os.exists(smc_control), 'no ${smc_control}: this kernel has no simulated SMC') {
		return
	}
	smc_check_device(mut t)
	smc_check_nodes(mut t, '62')
	t.check(smc_count(smc_status, 'classes') == 0 && smc_count(smc_status, 'battery') == 0
		&& smc_count(smc_status, 'charger') == 0, 'status is ${(read_text(smc_status) or { '' }).replace('\n',
		', ')}')
	supplies := (list_dir('/sys/class/power_supply') or { []string{} }).filter(it != 'policy')
	t.check(supplies.len == 0, 'there are power supplies with vinix.apple_smc=legacy: ${supplies}')
	zone, _ := smc_zone()
	t.check(zone == '', 'there is a zone ${zone} with vinix.apple_smc=legacy')
	// The nodes follow the battery as they always did.
	smc_sim(mut t, 'scene unplugged')
	t.check(smc_wait_word('/dev/battery', '60', 3000), '/dev/battery reads "${read_word('/dev/battery')}"')
	// Across a sleep too, with the thread kept off the SMC meanwhile.
	write_text('/sys/class/rtc/rtc0/wakealarm', '+3') or { t.check(false, 'wakealarm: ${err}') }
	write_text('/sys/power/state', 'freeze') or { t.check(false, 'the sleep was refused: ${err}') }
	t.check(smc_count(smc_status, 'parks') == 1, 'parks is ${smc_count(smc_status, 'parks')} after a sleep')
	t.check(smc_wait_word('/dev/battery', '60', 2000), '/dev/battery reads "${read_word('/dev/battery')}" after a sleep')
	sleep_ms(2000)
	// Only what the nodes are made of was ever sent: the address of the
	// shared memory, and reads.
	t.check(smc_count(smc_state, 'infos') == 0 && smc_count(smc_state, 'writes') == 0
		&& smc_count(smc_state, 'unknown') == 0, 'the SMC saw ${smc_count(smc_state, 'infos')} descriptions, ${smc_count(smc_state,
		'writes')} writes')
	t.check(smc_count(smc_state, 'commands') == smc_count(smc_state, 'reads') + 1, 'the SMC saw ${smc_count(smc_state,
		'commands')} commands of which ${smc_count(smc_state, 'reads')} were reads')
	t.check(smc_count(smc_state, 'violations') == 0, 'the SMC saw ${smc_count(smc_state, 'violations')} breaches of the protocol')
	// Then it stops answering, and the nodes say so instead of going stale.
	smc_sim(mut t, 'fault silent')
	sleep_ms(3500)
	t.check((read_text('/dev/battery') or { '' }) == '', '/dev/battery still reads "${read_word('/dev/battery')}"')
	t.check(smc_line(smc_status, 'transport') != 'ok', 'transport is still ok')
}
