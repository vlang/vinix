// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// `thermal-bench`: a thermal zone and four fans that act out a script.
//
// The zone counts how often it has been asked for its temperature (_TMP), and
// what it answers depends on the count:
//
//   ask 1        40 degrees: nothing to do
//   ask 2        all ones: no temperature at all, as from a sensor that
//                could not be read
//   ask 3        105, once: past _CRT, and gone when asked again (ask 4, 40)
//   asks 4-6     40
//   asks 7-10    55: past _AC1 (50), the gentler fans run at half speed
//   asks 11-14   75: past _AC0 (70), every fan runs flat out
//   asks 15-20   85: past _PSV (80), the processors are to be held back
//   asks 21-28   60: back under _AC0 and _PSV
//   asks 29-40   40: back under _AC1
//   ask 41 on    105: past _CRT (100), the machine must be switched off
//
// The second and third asks are what firmware does on a bad day. A kernel
// that takes either for a temperature switches the machine off at once, and
// the scenario ends there, failed.
//
// with two exceptions that stand for the physics a script does not have. It
// stays at 75 until the two fans that can only be switched are both running,
// and it does not leave the last 40 while either of them still is: a kernel
// that never switches them on, or never off, does not get to the end.
//
// The fans are one of each kind a PC has:
//
//   FAN0   takes any level from 0 to 100 (_FIF says so) and reports it
//   FAN1   is on or off, through its own _PS0 and _PS3
//   FAN2   takes one of the levels _FPS lists -- 0, 30, 60, 100, listed out
//          of order -- and reports it
//   FAN3   is on or off through a power resource
//
// A fan that reports turns 40 times a minute for each point of its level.
module hwhost

// The temperatures of the script, in the tenths of a kelvin ACPI counts in.
pub const bench_ac1_tenths = 3232 // 50 degrees
pub const bench_ac0_tenths = 3432 // 70
pub const bench_psv_tenths = 3532 // 80
pub const bench_crt_tenths = 3732 // 100
pub const bench_rpm_per_level = 40

fn aml_thermal_zone(name string, body [][]u8) []u8 {
	mut inner := aml_name(name)
	inner << aml_join(body)
	return aml_block([u8(0x5b), 0x85], inner)
}

// A power resource of system level 0 and resource order 0.
fn aml_power_resource(name string, body [][]u8) []u8 {
	mut inner := aml_name(name)
	inner << [u8(0), 0, 0]
	inner << aml_join(body)
	return aml_block([u8(0x5b), 0x84], inner)
}

// A method with `arguments` arguments, which its body reads with aml_argument().
fn aml_method_taking(name string, arguments int, body [][]u8) []u8 {
	mut inner := aml_name(name)
	inner << u8(arguments & 7)
	inner << aml_join(body)
	return aml_block([u8(0x14)], inner)
}

fn aml_argument(number int) []u8 {
	return [u8(0x68 + number)]
}

fn aml_and(a []u8, b []u8) []u8 {
	return aml_two(0x90, a, b)
}

fn aml_or(a []u8, b []u8) []u8 {
	return aml_two(0x91, a, b)
}

fn aml_not(a []u8) []u8 {
	mut out := [u8(0x92)]
	out << a
	return out
}

// One performance state of a fan: its level, and four figures nothing here
// reads.
fn fan_state(level u64) []u8 {
	return aml_package([aml_integer(level), aml_integer(0), aml_integer(level * bench_rpm_per_level),
		aml_integer(0), aml_integer(0)])
}

// A fan that takes a level and reports it.
fn level_fan(name string, fine bool, states [][]u8) []u8 {
	mut listed := [aml_integer(0)]
	listed << states
	return aml_device(name, [
		aml_named('_HID', aml_string('PNP0C0B')),
		aml_named('FLVL', aml_integer(0)),
		// Revision, level, revolutions a minute.
		aml_named('FSTP', aml_package([aml_integer(0), aml_integer(0), aml_integer(0)])),
		aml_method('_FIF', [
			aml_return(aml_package([aml_integer(0), aml_integer(if fine { u64(1) } else { u64(0) }),
				aml_integer(1), aml_integer(0)])),
		]),
		aml_method('_FPS', [aml_return(aml_package(listed))]),
		aml_method_taking('_FSL', 1, [aml_store(aml_argument(0), aml_name('FLVL'))]),
		aml_method('_FST', [
			aml_store(aml_name('FLVL'), aml_index(aml_name('FSTP'), aml_integer(1))),
			aml_store(aml_multiply(aml_name('FLVL'), aml_integer(bench_rpm_per_level)), aml_index(aml_name('FSTP'),
				aml_integer(2))),
			aml_return(aml_name('FSTP')),
		]),
	])
}

fn thermal_bench() []u8 {
	tick := aml_name('TICK')
	switched := aml_name('\\_SB.FAN1.FSON')
	powered := aml_name('\\_SB.PWON')
	tenths := fn (celsius int) []u8 {
		return aml_integer(u64(2732 + celsius * 10))
	}
	until := fn [tick, tenths] (ask int, celsius int) []u8 {
		return aml_if(aml_less(tick, aml_integer(u64(ask))), [aml_return(tenths(celsius))])
	}
	return aml_table('SSDT', 'HWTHERM', [
		aml_scope('\\_SB', [
			aml_named('PWON', aml_integer(0)),
			aml_power_resource('PFAN', [
				aml_method('_STA', [aml_return(powered)]),
				aml_method('_ON', [aml_store(aml_integer(1), powered)]),
				aml_method('_OFF', [aml_store(aml_integer(0), powered)]),
			]),
			level_fan('FAN0', true, [fan_state(0), fan_state(100)]),
			aml_device('FAN1', [
				aml_named('_HID', aml_string('PNP0C0B')),
				aml_named('FSON', aml_integer(0)),
				aml_method('_PS0', [aml_store(aml_integer(1), aml_name('FSON'))]),
				aml_method('_PS3', [aml_store(aml_integer(0), aml_name('FSON'))]),
			]),
			level_fan('FAN2', false, [fan_state(100), fan_state(0), fan_state(60), fan_state(30)]),
			aml_device('FAN3', [
				aml_named('_HID', aml_string('PNP0C0B')),
				aml_named('_PR0', aml_package([aml_name('\\_SB.PFAN')])),
			]),
		]),
		aml_scope('\\_TZ', [
			aml_thermal_zone('TZ00', [
				aml_named('TICK', aml_integer(0)),
				aml_method('_TMP', [
					// Hot until the fans that can only be switched both run.
					aml_if(aml_and(aml_equal(tick, aml_integer(14)), aml_not(aml_and(switched,
						powered))), [aml_return(tenths(75))]),
					// And not on to the end while either still does.
					aml_if(aml_and(aml_equal(tick, aml_integer(40)), aml_or(switched, powered)),
						[aml_return(tenths(40))]),
					aml_increment(tick),
					// Firmware on a bad day: no temperature, then a wild one.
					aml_if(aml_equal(tick, aml_integer(2)), [aml_return(aml_integer(0xffffffff))]),
					aml_if(aml_equal(tick, aml_integer(3)), [aml_return(tenths(105))]),
					until(7, 40),
					until(11, 55),
					until(15, 75),
					until(21, 85),
					until(29, 60),
					until(41, 40),
					aml_return(tenths(105)),
				]),
				aml_method('_AC0', [aml_return(aml_integer(bench_ac0_tenths))]),
				aml_method('_AC1', [aml_return(aml_integer(bench_ac1_tenths))]),
				aml_named('_AL0', aml_package([aml_name('\\_SB.FAN0'), aml_name('\\_SB.FAN1'),
					aml_name('\\_SB.FAN2'), aml_name('\\_SB.FAN3')])),
				aml_named('_AL1', aml_package([aml_name('\\_SB.FAN0'), aml_name('\\_SB.FAN2')])),
				aml_method('_PSV', [aml_return(aml_integer(bench_psv_tenths))]),
				aml_method('_CRT', [aml_return(aml_integer(bench_crt_tenths))]),
			]),
		]),
	])
}
