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
					aml_return(state),
				]),
			]),
		]),
	])
}

// The table called `name`, or an error for a name no scenario should use.
pub fn acpi_table(name string) ![]u8 {
	if name == 'power-bench' {
		return power_bench()
	}
	return error('no ACPI table called ${name}')
}
