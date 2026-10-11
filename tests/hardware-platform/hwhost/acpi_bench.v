// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The ACPI tables scenarios can give a machine.
//
// `power-bench` is a battery, a charger and a lid that act out a script. The
// battery counts how often it has been asked for its state (_BST), and what it
// answers depends on the count, so a test gets a whole afternoon of a laptop's
// life in the seconds it takes to ask twenty times:
//
//   asks 1-3    on the charger, charging: 42, 44, 46 Wh of 48
//   ask 4       the charger is pulled (Notify to it); from here discharging
//               at 12 W, 4 Wh less with every ask
//   ask 5       the battery says something changed (Notify to it), and to
//   ask 6       whoever asks next it says, once, that it is critical -- with
//               38 Wh left. A gauge has bad moments, and one must not
//               cost the machine its session.
//   ask 7       the lid closes (Notify to it)
//   ask 9       the lid opens
//   ask 15      2 Wh left, 4%: low
//   ask 16 on   1 Wh left, 2%, and the battery says critical
//
// The static figures are a 50 Wh design, 48 Wh last full, 11.4 V, 123 cycles,
// a lithium-ion pack called VNXBAT made by Vinix with serial 0042.
module hwhost

pub const bench_design_mwh = 50000
pub const bench_full_mwh = 48000
pub const bench_rate_mw = 12000
pub const bench_step_mwh = 4000

fn power_bench() []u8 {
	tick := aml_name('TICK')
	state := aml_name('BSTP')
	unknown := aml_integer(0xffffffff)
	lid_open := aml_name('\\_SB.LID0.LIDS')
	changed := aml_integer(0x80)
	return aml_table('SSDT', 'HWTEST', [
		aml_scope('\\_SB', [
			aml_device('LID0', [
				aml_named('_HID', aml_string('PNP0C0D')),
				aml_named('LIDS', aml_integer(1)),
				aml_method('_LID', [aml_return(aml_name('LIDS'))]),
			]),
			aml_device('ADP0', [
				aml_named('_HID', aml_string('ACPI0003')),
				aml_method('_PSR', [
					aml_if(aml_less(aml_name('\\_SB.BAT0.TICK'), aml_integer(4)), [
						aml_return(aml_integer(1)),
					]),
					aml_return(aml_integer(0)),
				]),
			]),
			aml_device('BAT0', [
				aml_named('_HID', aml_string('PNP0C0A')),
				aml_named('_UID', aml_integer(0)),
				aml_named('TICK', aml_integer(0)),
				// State, present rate in mW, remaining in mWh, voltage in mV.
				aml_named('BSTP', aml_package([aml_integer(0), aml_integer(bench_rate_mw),
					aml_integer(0), aml_integer(11100)])),
				aml_method('_STA', [aml_return(aml_integer(0x1f))]),
				aml_method('_BIX', [
					aml_return(aml_package([
						aml_integer(0), // revision
						aml_integer(0), // counted in mWh
						aml_integer(bench_design_mwh),
						aml_integer(bench_full_mwh),
						aml_integer(1), // rechargeable
						aml_integer(11400),
						aml_integer(4800),
						aml_integer(2400),
						aml_integer(123), // cycles
						aml_integer(95000),
						unknown,
						unknown,
						aml_integer(1000),
						aml_integer(500),
						aml_integer(10),
						aml_integer(10),
						aml_string('VNXBAT'),
						aml_string('0042'),
						aml_string('LION'),
						aml_string('Vinix'),
					])),
				]),
				aml_method('_BST', [
					aml_increment(tick),
					aml_if(aml_less(tick, aml_integer(4)), [
						aml_store(aml_integer(2), aml_index(state, aml_integer(0))),
						aml_store(aml_add(aml_integer(40000), aml_multiply(tick, aml_integer(2000))),
							aml_index(state, aml_integer(2))),
						aml_return(state),
					]),
					aml_if(aml_equal(tick, aml_integer(4)), [
						aml_notify(aml_name('\\_SB.ADP0'), changed),
					]),
					aml_if(aml_equal(tick, aml_integer(5)), [
						aml_notify(aml_name('\\_SB.BAT0'), changed),
					]),
					aml_if(aml_equal(tick, aml_integer(7)), [
						aml_store(aml_integer(0), lid_open),
						aml_notify(aml_name('\\_SB.LID0'), changed),
					]),
					aml_if(aml_equal(tick, aml_integer(9)), [
						aml_store(aml_integer(1), lid_open),
						aml_notify(aml_name('\\_SB.LID0'), changed),
					]),
					aml_store(aml_integer(1), aml_index(state, aml_integer(0))),
					aml_store(aml_multiply(aml_subtract(tick, aml_integer(4)), aml_integer(bench_step_mwh)),
						aml_local(0)),
					aml_if(aml_greater(aml_local(0), aml_integer(45000)), [
						aml_store(aml_integer(45000), aml_local(0)),
						// Discharging, and critical.
						aml_store(aml_integer(5), aml_index(state, aml_integer(0))),
					]),
					aml_store(aml_subtract(aml_integer(46000), aml_local(0)), aml_index(state,
						aml_integer(2))),
					aml_if(aml_equal(tick, aml_integer(6)), [
						// Once: critical, with most of the charge left.
						aml_store(aml_integer(5), aml_index(state, aml_integer(0))),
					]),
					aml_return(state),
				]),
			]),
		]),
	])
}

// The embedded controller benches.
//
// A laptop's battery, charger and lid are not scripted in AML the way
// `power-bench` scripts them: their methods read bytes of the embedded
// controller, and the controller says when one changed. `ec-bench` is that
// arrangement. A PNP0C09 device at the usual ports, 0x62 and 0x66, has an
// EmbeddedControl region with these fields, and nothing in the table knows a
// value by itself:
//
//	0x00 BSTS  8   battery state, as _BST gives it
//	0x01 ACPR  8   the charger is supplying power
//	0x02 LIDS  8   the lid is open
//	0x03 BPRS  8   a battery is in the bay
//	0x04 BRAT 16   present rate, mW       0x0a BFUL 16   last full, mWh
//	0x06 BREM 16   remaining, mWh         0x0c BDES 16   design, mWh
//	0x08 BVOL 16   present voltage, mV    0x0e BCYC 16   cycles
//	0x10 SCRT  8   a counter the table writes
//	0x12 BDVL 16   design voltage, mV
//	0x14 TEMP 16   a temperature, in tenths of a kelvin
//	0x20 WIDE 16   reached a word at a time
//	0x24 QUAD 32   reached four bytes at a time
//
// The controller's events are named by these methods:
//
//	_Q20   Notify the battery: its state changed
//	_Q21   Notify the charger
//	_Q22   Notify the lid
//	_Q23   add one to SCRT, then Notify the battery: what it is changed
//	_Q24   add 0x0101 to WIDE and 1 to QUAD
//
// The byte fields are declared Lock and the device's _GLK is 1, so every
// access holds the ACPI global lock, one way or the other.
//
// A battery only shows itself once _REG has said the region may be used.
// With `early`, the table also does what firmware with an ECDT may do: it
// reads the controller while it loads (BDVL, kept in \_SB.EARL) and in an
// _INI (BCYC, kept in EC0.INIV), and _BIX reports those two copies. Without
// it _BIX reads both at the time.
//
// No machine QEMU has an embedded controller. Against a kernel built with
// -d acpiec_selftest the ports are never touched and a simulated controller
// answers; against any other, nothing answers at 0x62 and 0x66 and every
// read is 0xff, which is what `ec-absent` is for.
pub const bench_ec_data = u16(0x62)
pub const bench_ec_command = u16(0x66)
pub const bench_ec_uid = 7
// The general purpose event QEMU's chipset raises when a processor is added
// to the running machine: one a test can have raised from outside at a
// moment of its choosing. The controller's handler takes the place of the
// method firmware has for it, so the new processor goes unnoticed.
pub const bench_ec_gpe = 2
pub const bench_ec_path = '\\_SB.EC0'

fn ec_field(name string) []u8 {
	return aml_name('\\_SB.EC0.' + name)
}

// The value of a field: reading it, where its name alone might be taken for
// the field itself.
fn ec_value(name string) []u8 {
	return aml_add(ec_field(name), aml_integer(0))
}

fn ec_region() [][]u8 {
	return [
		aml_region('ERAM', aml_embedded_control, 0, 0x100),
		aml_field('ERAM', aml_byte_access | aml_field_lock, [
			aml_field_unit('BSTS', 8),
			aml_field_unit('ACPR', 8),
			aml_field_unit('LIDS', 8),
			aml_field_unit('BPRS', 8),
			aml_field_unit('BRAT', 16),
			aml_field_unit('BREM', 16),
			aml_field_unit('BVOL', 16),
			aml_field_unit('BFUL', 16),
			aml_field_unit('BDES', 16),
			aml_field_unit('BCYC', 16),
			aml_field_unit('SCRT', 8),
			aml_field_gap(8),
			aml_field_unit('BDVL', 16),
			aml_field_unit('TEMP', 16),
		]),
		aml_field('ERAM', aml_word_access, [
			aml_field_gap(0x20 * 8),
			aml_field_unit('WIDE', 16),
		]),
		aml_field('ERAM', aml_dword_access, [
			aml_field_gap(0x24 * 8),
			aml_field_unit('QUAD', 32),
		]),
	]
}

// _REG (space, connected): firmware's note that the region may be used.
fn ec_reg() []u8 {
	return aml_method_taking('_REG', 2, [
		aml_if(aml_equal(aml_argument(0), aml_integer(u64(aml_embedded_control))), [
			aml_store(aml_argument(1), aml_name('ECOK')),
		]),
	])
}

// The battery, charger and lid whose methods read the controller. `sta` is
// the battery's _STA.
fn ec_power_devices(early bool, sta []u8) [][]u8 {
	unknown := aml_integer(0xffffffff)
	info := aml_name('BIXP')
	state := aml_name('BSTP')
	design_voltage := if early { aml_name('\\_SB.EARL') } else { ec_value('BDVL') }
	cycles := if early { aml_name('\\_SB.EC0.INIV') } else { ec_value('BCYC') }
	return [
		aml_device('LID0', [
			aml_named('_HID', aml_string('PNP0C0D')),
			aml_method('_LID', [aml_return(ec_value('LIDS'))]),
		]),
		aml_device('ADP0', [
			aml_named('_HID', aml_string('ACPI0003')),
			aml_method('_PSR', [aml_return(ec_value('ACPR'))]),
		]),
		aml_device('BAT0', [
			aml_named('_HID', aml_string('PNP0C0A')),
			aml_named('_UID', aml_integer(0)),
			aml_named('BSTP', aml_package([aml_integer(0), aml_integer(0), aml_integer(0),
				aml_integer(0)])),
			aml_named('BIXP', aml_package([
				aml_integer(0), // revision
				aml_integer(0), // counted in mWh
				aml_integer(0), // design: from the controller
				aml_integer(0), // last full: from the controller
				aml_integer(1), // rechargeable
				aml_integer(0), // design voltage: from the controller
				aml_integer(4800),
				aml_integer(2400),
				aml_integer(0), // cycles: from the controller
				aml_integer(95000),
				unknown,
				unknown,
				aml_integer(1000),
				aml_integer(500),
				aml_integer(10),
				aml_integer(10),
				aml_string('VNXEC'),
				aml_string('0062'),
				aml_string('LION'),
				aml_string('Vinix'),
			])),
			sta,
			aml_method('_BIX', [
				aml_store(ec_value('BDES'), aml_index(info, aml_integer(2))),
				aml_store(ec_value('BFUL'), aml_index(info, aml_integer(3))),
				aml_store(aml_add(design_voltage, aml_integer(0)), aml_index(info, aml_integer(5))),
				aml_store(aml_add(cycles, aml_integer(0)), aml_index(info, aml_integer(8))),
				aml_return(info),
			]),
			aml_method('_BST', [
				aml_store(ec_value('BSTS'), aml_index(state, aml_integer(0))),
				aml_store(ec_value('BRAT'), aml_index(state, aml_integer(1))),
				aml_store(ec_value('BREM'), aml_index(state, aml_integer(2))),
				aml_store(ec_value('BVOL'), aml_index(state, aml_integer(3))),
				aml_return(state),
			]),
		]),
	]
}

fn ec_bench(early bool) []u8 {
	battery := aml_name('\\_SB.BAT0')
	mut controller := [
		aml_named('_HID', aml_string('PNP0C09')),
		aml_named('_UID', aml_integer(bench_ec_uid)),
		aml_named('_GPE', aml_integer(bench_ec_gpe)),
		aml_named('_GLK', aml_integer(1)),
		aml_named('_CRS', aml_resources([aml_io_port(bench_ec_data), aml_io_port(bench_ec_command)])),
		aml_named('ECOK', aml_integer(0)),
		aml_named('INIV', aml_integer(0)),
		ec_reg(),
	]
	controller << ec_region()
	if early {
		controller << aml_method('_INI', [aml_store(ec_value('BCYC'), aml_name('INIV'))])
	}
	queries := [
		aml_method('_Q20', [aml_notify(battery, aml_integer(0x80))]),
		aml_method('_Q21', [aml_notify(aml_name('\\_SB.ADP0'), aml_integer(0x80))]),
		aml_method('_Q22', [aml_notify(aml_name('\\_SB.LID0'), aml_integer(0x80))]),
		aml_method('_Q23', [
			aml_store(aml_add(ec_field('SCRT'), aml_integer(1)), ec_field('SCRT')),
			aml_notify(battery, aml_integer(0x81)),
		]),
		aml_method('_Q24', [
			aml_store(aml_add(ec_field('WIDE'), aml_integer(0x0101)), ec_field('WIDE')),
			aml_store(aml_add(ec_field('QUAD'), aml_integer(1)), ec_field('QUAD')),
		]),
	]
	controller << queries
	// The battery is there once _REG has run and the controller says a
	// battery is in the bay.
	sta := aml_method('_STA', [
		aml_if(aml_name('\\_SB.EC0.ECOK'), [
			aml_if(ec_value('BPRS'), [aml_return(aml_integer(0x1f))]),
			aml_return(aml_integer(0x0f)),
		]),
		aml_return(aml_integer(0)),
	])
	mut scope := [aml_named('EARL', aml_integer(0)), aml_device('EC0', controller)]
	scope << ec_power_devices(early, sta)
	mut table := [aml_scope('\\_SB', scope)]
	if early {
		// Executed while the table loads, before any _REG or _INI.
		table << aml_store(ec_value('BDVL'), aml_name('\\_SB.EARL'))
	}
	return aml_table('SSDT', 'HWTESTEC', table)
}

// `ec-absent`: the same devices described to a kernel with no simulated
// controller, so that nothing answers. It differs where that lets one boot
// show more:
//
//   - no ECDT comes with it, and _GPE is a package naming a block of events
//     (\_SB.GPEB) that no kernel here drives;
//   - BAT0 shows itself as soon as _REG has run, without asking the
//     controller, so the kernel takes it on and then cannot read it;
//   - BAT1 asks the controller whether it is there, cannot be answered, and
//     is never taken on;
//   - a thermal zone, \_TZ.TZEC, reads its temperature from the controller,
//     as a laptop's does, cannot be answered either, and is not taken on.
fn ec_absent() []u8 {
	mut controller := [
		aml_named('_HID', aml_string('PNP0C09')),
		aml_named('_UID', aml_integer(9)),
		aml_named('_GPE', aml_package([aml_name('\\_SB.GPEB'), aml_integer(3)])),
		aml_named('_CRS', aml_resources([aml_io_port(bench_ec_data), aml_io_port(bench_ec_command)])),
		aml_named('ECOK', aml_integer(0)),
		ec_reg(),
	]
	controller << ec_region()
	sta := aml_method('_STA', [
		aml_if(aml_name('\\_SB.EC0.ECOK'), [aml_return(aml_integer(0x1f))]),
		aml_return(aml_integer(0)),
	])
	mut scope := [
		aml_device('GPEB', [aml_named('_HID', aml_string('ACPI0006'))]),
		aml_device('EC0', controller),
		aml_device('BAT1', [
			aml_named('_HID', aml_string('PNP0C0A')),
			aml_named('_UID', aml_integer(1)),
			aml_method('_STA', [
				aml_if(ec_value('BPRS'), [aml_return(aml_integer(0x1f))]),
				aml_return(aml_integer(0x0f)),
			]),
		]),
	]
	scope << ec_power_devices(false, sta)
	return aml_table('SSDT', 'HWTESTEC', [
		aml_scope('\\_SB', scope),
		aml_scope('\\_TZ', [
			aml_thermal_zone('TZEC', [
				aml_method('_TMP', [aml_return(ec_value('TEMP'))]),
				// 105 degrees Celsius.
				aml_method('_CRT', [aml_return(aml_integer(3782))]),
			]),
		]),
	])
}

// suspend-deep-wake: three devices that say they can wake the machine, and a
// way for the host to hear what firmware was told.
//
//   LID0   a lid, by event 0x10, from S3 at the deepest; told through _PSW
//          It is shut when the machine starts, and open from the moment it
//          is told it need not wake the machine any more -- opened during
//          the sleep, with no notification, as firmware sometimes does it
//   BTNP   a power button, by event 0x12, from S1 at the deepest: it cannot
//          end a suspend to RAM, and must not be armed for one
//   BTNS   a sleep button, by event 0x11, from S4; told through _DSW
//
// _PSW and _DSW write what they were called with to port 0x505, which QEMU's
// debug console device records in a file: `L` and `l` for the lid being told
// to wake the machine and told not to, `S` then the sleep state and the
// device state as digits, and `s`, for the sleep button.
// Not 0x402, where the firmware QEMU ships writes its own account of itself.
pub const wake_bench_port = u16(0x505)
pub const wake_bench_lid_gpe = 0x10
pub const wake_bench_sleep_gpe = 0x11
pub const wake_bench_power_gpe = 0x12

fn wake_bench() []u8 {
	said := aml_name('\\_SB.SAID')
	return aml_table('SSDT', 'HWTEST', [
		aml_scope('\\_SB', [
			aml_region('DBGR', 1, u64(wake_bench_port), 1),
			aml_field('DBGR', aml_byte_access, [aml_field_unit('SAID', 8)]),
			aml_device('LID0', [
				aml_named('_HID', aml_string('PNP0C0D')),
				aml_named('LIDS', aml_integer(0)),
				aml_method('_LID', [aml_return(aml_name('LIDS'))]),
				aml_named('_PRW', aml_package([aml_integer(wake_bench_lid_gpe), aml_integer(3)])),
				aml_method_taking('_PSW', 1, [
					aml_if(aml_equal(aml_argument(0), aml_integer(1)), [aml_store(aml_integer(u64(`L`)), said)]),
					aml_if(aml_equal(aml_argument(0), aml_integer(0)), [
						aml_store(aml_integer(u64(`l`)), said),
						// Opened while the machine was down, and nothing said.
						aml_store(aml_integer(1), aml_name('LIDS')),
					]),
				]),
			]),
			aml_device('BTNP', [
				aml_named('_HID', aml_string('PNP0C0C')),
				aml_named('_PRW', aml_package([aml_integer(wake_bench_power_gpe), aml_integer(1)])),
				aml_method_taking('_PSW', 1, [aml_store(aml_integer(u64(`!`)), said)]),
			]),
			aml_device('BTNS', [
				aml_named('_HID', aml_string('PNP0C0E')),
				aml_named('_PRW', aml_package([aml_integer(wake_bench_sleep_gpe), aml_integer(4)])),
				aml_method_taking('_DSW', 3, [
					aml_if(aml_equal(aml_argument(0), aml_integer(1)), [
						aml_store(aml_integer(u64(`S`)), said),
						aml_store(aml_add(aml_integer(u64(`0`)), aml_argument(1)), said),
						aml_store(aml_add(aml_integer(u64(`0`)), aml_argument(2)), said),
					]),
					aml_if(aml_equal(aml_argument(0), aml_integer(0)), [aml_store(aml_integer(u64(`s`)), said)]),
				]),
			]),
		]),
	])
}

// acpi-backlight: a panel whose backlight firmware sets.
//
// The display bus GFX0 has one output, LCD0, with five levels. The levels are
// the character codes of 1, 3, 5, 7 and 9, so that what _BCM is given can be
// written as it is to the port QEMU records and read off the record. _BCL
// gives them as firmware does: the level for the charger and the level for
// the battery first (9 and 5), then the list in no order (7, 3, 9, 1, 5).
// The panel starts at 7 and says so through _BQC.
//
// Two of the levels stand for a brightness key being pressed, which nothing
// outside the machine can do: set to 3 the panel sends "brighter", and set
// to 9 it sends "dimmer". _DOS on the bus writes D and the digit it was
// given.
//
// A second output, LCD1, is a panel as careless firmware describes one: three
// levels (2, 4, 6) with the two preferred ones left out of the front of the
// list, and no way to ask where it is.
pub const backlight_bench_levels = '13579'

fn backlight_bench() []u8 {
	said := aml_name('\\_SB.BLSD')
	level := aml_name('LVL')
	lcd := aml_name('\\_SB.GFX0.LCD0')
	return aml_table('SSDT', 'HWTEST', [
		aml_scope('\\_SB', [
			aml_region('BLDR', 1, u64(wake_bench_port), 1),
			aml_field('BLDR', aml_byte_access, [aml_field_unit('BLSD', 8)]),
			aml_device('GFX0', [
				aml_named('_ADR', aml_integer(0x001e0000)),
				aml_method_taking('_DOS', 1, [
					aml_store(aml_integer(u64(`D`)), said),
					aml_store(aml_add(aml_integer(u64(`0`)), aml_argument(0)), said),
				]),
				aml_device('LCD0', [
					aml_named('_ADR', aml_integer(0x0400)),
					aml_named('LVL', aml_integer(u64(`7`))),
					aml_method('_BCL', [
						aml_return(aml_package([aml_integer(u64(`9`)), aml_integer(u64(`5`)),
							aml_integer(u64(`7`)), aml_integer(u64(`3`)), aml_integer(u64(`9`)),
							aml_integer(u64(`1`)), aml_integer(u64(`5`))])),
					]),
					aml_method_taking('_BCM', 1, [
						aml_store(aml_argument(0), level),
						aml_store(aml_argument(0), said),
						aml_if(aml_equal(aml_argument(0), aml_integer(u64(`3`))), [
							aml_notify(lcd, aml_integer(0x86)),
						]),
						aml_if(aml_equal(aml_argument(0), aml_integer(u64(`9`))), [
							aml_notify(lcd, aml_integer(0x87)),
						]),
					]),
					aml_method('_BQC', [aml_return(level)]),
				]),
				aml_device('LCD1', [
					aml_named('_ADR', aml_integer(0x0100)),
					aml_method('_BCL', [
						aml_return(aml_package([aml_integer(u64(`2`)), aml_integer(u64(`4`)),
							aml_integer(u64(`6`))])),
					]),
					aml_method_taking('_BCM', 1, [aml_store(aml_argument(0), said)]),
				]),
			]),
		]),
	])
}

// The table called `name`, or an error for a name no scenario should use.
pub fn acpi_table(name string) ![]u8 {
	return match name {
		'thermal-bench' { thermal_bench() }
		'power-bench' { power_bench() }
		'ec-bench' { ec_bench(true) }
		'ec-bench-dsdt' { ec_bench(false) }
		'ec-ecdt' { ecdt_table(bench_ec_command, bench_ec_data, bench_ec_uid, bench_ec_gpe, bench_ec_path) }
		'ec-absent' { ec_absent() }
		'wake-bench' { wake_bench() }
		'backlight-bench' { backlight_bench() }
		else { error('no ACPI table called ${name}') }
	}
}
