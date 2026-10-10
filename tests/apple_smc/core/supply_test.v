// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2026 Alexander Medvednikov
//
// What the SMC has, what it says now, and what that amounts to: discover(),
// sample() and judge() against the simulated SMC, and the charge limit.
module core

const key_buic = u32(0x42554943)

// A started client with what discover() found on its SMC.
@[heap]
struct Rig {
mut:
	bench   &Bench = unsafe { nil }
	machine Machine
	raw     Raw
	filter  Filter
}

fn new_rig(fan bool, limit bool, old_order bool) &Rig {
	mut rig := &Rig{
		bench: started_bench(fan, limit, old_order)
	}
	assert discover(rig.bench.state, mut rig.machine, false, false) == 0
	return rig
}

// A second passes, and everything due is read and weighed, as the kernel's
// thread does it.
fn (mut rig Rig) pass() Supply {
	rig.bench.wait(1000)
	mut legacy := Legacy{}
	legacy.percent = vinix_smc_refresh(rig.bench.state)
	mut power := i32(0)
	vinix_smc_refresh_power(rig.bench.state, &legacy.power_flags, &legacy.voltage_mv, &legacy.current_ma,
		&power)
	assert sample(rig.bench.state, rig.machine, mut rig.raw) == 0
	return judge(rig.machine, rig.raw, legacy, mut rig.filter)
}

fn (mut rig Rig) free() {
	rig.bench.free()
}

// ── What the SMC has ────────────────────────────────────────────────────────

fn test_a_laptop_with_everything() {
	mut rig := new_rig(true, true, true)
	machine := rig.machine
	for slot in [slot_b0rm, slot_b0fc, slot_b0dc, slot_b0ct, slot_b0te, slot_b0tf, slot_bitv, slot_bsfc,
		slot_bcf0, slot_ch0r, slot_chce, slot_chcc, slot_chnc, slot_chsc, slot_chis, slot_chwa] {
		assert machine.slots[slot].present, 'slot ${slot}'
	}
	// macOS 15.4 took this one away; the simulated SMC has none either.
	assert !machine.slots[slot_aci].present
	assert machine.slots[slot_bcf0].size == 4
	assert machine.remaining_usable && machine.remaining_big_endian
	assert unsafe { tos(&machine.model[0], machine.model_len) } == 'bq40z651'
	assert unsafe { tos(&machine.serial[0], machine.serial_len) } == 'F5D0VINIX0SIM0001'
	assert machine.sensor_count == 4
	assert machine.sensors[0].key == key_th0x && machine.sensors[0].kind == type_flt
	assert machine.sensors[2].key == key_tchp && machine.sensors[2].kind == type_ioft
	assert sensor_label(machine.sensors[1].known) == 'Battery Hotspot'
	assert machine.fan_count == 1
	assert machine.fans[0].number == 0
	assert machine.fans[0].has_minimum && machine.fans[0].minimum == 1350
	assert machine.fans[0].has_maximum && machine.fans[0].maximum == 5349
	assert machine.odd_sized == 0
	// Finding out stores nothing.
	assert rig.bench.sim.writes == 0
	assert vinix_smc_key_writes(rig.bench.state) == 0
	assert rig.bench.sim.violations == 0
	rig.free()
}

fn test_a_laptop_without_a_fan_or_a_charge_limit() {
	mut rig := new_rig(false, false, false)
	assert rig.machine.fan_count == 0
	assert !rig.machine.slots[slot_chwa].present
	assert rig.machine.slots[slot_bcf0].size == 1
	assert rig.machine.remaining_usable && !rig.machine.remaining_big_endian
	assert rig.machine.sensor_count == 4
	rig.free()
}

fn test_what_was_asked_to_be_left_alone_is_not_asked_about() {
	mut bench := started_bench(true, true, true)
	mut machine := Machine{}
	assert discover(bench.state, mut machine, true, true) == 0
	assert machine.sensor_count == 0 && machine.fan_count == 0
	assert !machine.slots[slot_chwa].present
	assert machine.slots[slot_b0fc].present
	// The charge limit key and the sensors' were not so much as described.
	assert bench.sim.keys[bench.sim.find(key_chwa)].reads == 0
	assert bench.sim.infos == u64(slot_count - 1) + 2
	bench.free()
}

fn test_a_key_of_another_size_is_left_out() {
	mut bench := started_bench(true, true, true)
	// A charge that is four bytes long is not the figure this reads.
	bench.sim.put(key_b0fc, sim_type_ui32, flag_readable, 4, 4200)
	// A flag for "about to give out" of two bytes says nothing of the order.
	bench.sim.put(key_bcf0, sim_type_ui16, flag_readable, 2, 0)
	// A temperature of a type nobody decodes.
	bench.sim.put(key_tw0p, sim_type_ui16, flag_readable, 2, 47)
	mut machine := Machine{}
	assert discover(bench.state, mut machine, false, false) == 0
	assert !machine.slots[slot_b0fc].present
	assert !machine.slots[slot_bcf0].present
	assert !machine.remaining_usable
	assert machine.sensor_count == 3
	assert machine.odd_sized == 3
	bench.free()
}

fn test_a_desktop_s_smc_has_no_battery_keys() {
	mut bench := started_bench(true, false, false)
	for key in [key_b0rm, key_b0fc, key_b0dc, key_b0ct, key_b0te, key_b0tf, key_bitv, key_bsfc, key_bcf0,
		key_bmdn, key_bmsn, key_chce, key_chcc, key_chnc, key_chsc, key_chis, key_ch0r, key_tb0t,
		key_tchp] {
		bench.sim.remove(key)
	}
	mut machine := Machine{}
	assert discover(bench.state, mut machine, false, false) == 0
	for slot in 0 .. slot_count {
		assert !machine.slots[slot].present
	}
	assert machine.model_len == 0 && machine.serial_len == 0
	assert machine.sensor_count == 2
	assert machine.fan_count == 1
	bench.free()
}

fn test_more_fans_than_there_is_room_for() {
	mut bench := started_bench(true, false, false)
	bench.sim.update(key_fnum, 9)
	bench.sim.put(fan_key(1, `A`, `c`), type_flt, flag_readable, 4, u64(sim_flt_2400))
	mut machine := Machine{}
	assert discover(bench.state, mut machine, false, false) == 0
	// Two have a speed key; the count the SMC gave is not believed past that.
	assert machine.fan_count == 2
	assert machine.fans[1].number == 1
	assert !machine.fans[1].has_minimum && !machine.fans[1].has_maximum
	bench.free()
}

fn test_finding_out_stops_when_the_channel_is_gone() {
	mut bench := started_bench(true, true, true)
	bench.sim.silent = true
	mut machine := Machine{}
	assert discover(bench.state, mut machine, false, false) == vinix_smc_timeout
	bench.free()
	// And finds nothing where there is no way into the shared memory.
	bench = new_bench(true, true, true)
	assert bench.boot(false) == 0
	machine = Machine{}
	assert discover(bench.state, mut machine, false, false) == 0
	assert machine.found == 0 && machine.sensor_count == 0 && machine.fan_count == 0
	assert bench.sim.infos == 0
	bench.free()
}

// ── What it says now ────────────────────────────────────────────────────────

fn test_the_first_pass_reads_everything_and_later_ones_what_is_due() {
	mut rig := new_rig(true, true, true)
	before := rig.bench.sim.reads
	rig.pass()
	// Eight keys of every pass, five of every fifth, two read once, four
	// temperatures and a fan, beside the capacity and three telemetry keys.
	assert rig.bench.sim.reads - before == 8 + 5 + 2 + 4 + 1 + 4
	after_first := rig.bench.sim.reads
	for _ in 0 .. 10 {
		rig.pass()
	}
	// Ten passes: 80, each of the five slow keys twice, each temperature
	// five times, the fan five times; and 40 for the device nodes.
	assert rig.bench.sim.reads - after_first == 80 + 10 + 20 + 5 + 40
	assert rig.raw.passes == 11
	assert rig.raw.key_errors == 0 && rig.raw.implausible == 0
	// What is read once was read once.
	assert rig.bench.sim.keys[rig.bench.sim.find(key_b0dc)].reads == 1
	assert rig.bench.sim.keys[rig.bench.sim.find(key_bitv)].reads == 1
	// CHSC is only for an SMC with no CHNC.
	assert rig.bench.sim.keys[rig.bench.sim.find(key_chsc)].reads == 0
	assert rig.bench.sim.writes == 0
	rig.free()
}

fn test_a_key_that_keeps_failing_is_asked_less_often() {
	mut rig := new_rig(true, true, true)
	rig.pass()
	rig.bench.sim.remove(key_chce)
	rig.bench.sim.remove(key_tw0p)
	for _ in 0 .. 40 {
		rig.pass()
	}
	// Three times running, then once in thirty passes: at most two more.
	assert rig.raw.key_errors >= 6 && rig.raw.key_errors <= 10
	assert !rig.raw.have[slot_chce]
	assert !rig.raw.sensor_have[3]
	// It comes back when the key does.
	rig.bench.sim.put(key_chce, sim_type_ui8, flag_readable, 1, 1)
	for _ in 0 .. 31 {
		rig.pass()
	}
	assert rig.raw.have[slot_chce] && rig.raw.value[slot_chce] == 1
	assert rig.raw.failures[slot_chce] == 0
	rig.free()
}

fn test_a_pass_ends_when_the_channel_is_gone() {
	mut rig := new_rig(true, true, true)
	rig.pass()
	rig.bench.sim.silent = true
	rig.bench.wait(1000)
	assert sample(rig.bench.state, rig.machine, mut rig.raw) == vinix_smc_timeout
	sent := rig.bench.sent
	assert sample(rig.bench.state, rig.machine, mut rig.raw) == vinix_smc_timeout
	assert rig.bench.sent == sent
	rig.free()
}

fn test_temperatures_and_the_fan() {
	mut rig := new_rig(true, true, true)
	rig.pass()
	assert rig.raw.sensor_have[0] && rig.raw.sensor_millis[0] == 38500
	assert rig.raw.sensor_have[1] && rig.raw.sensor_millis[1] == 31250
	assert rig.raw.sensor_have[2] && rig.raw.sensor_millis[2] == 44000
	assert rig.raw.sensor_have[3] && rig.raw.sensor_millis[3] == 47000
	assert rig.raw.fan_have[0] && rig.raw.fan_rpm[0] == 2400
	rig.free()
}

fn test_a_reading_that_cannot_be_a_temperature_is_not_one() {
	mut rig := new_rig(true, true, true)
	rig.pass()
	// All ones, not a number, 300 degrees below freezing and 250 above.
	for garbage in [u64(0xffffffff), 0x7fc00000, 0xc3960000, 0x437a0000] {
		rig.bench.sim.once(key_tb0t, garbage)
		before := rig.raw.implausible
		rig.pass()
		rig.pass()
		assert rig.raw.implausible == before + 1, '${garbage:x}'
		// The pass after it reads the real one again.
		rig.pass()
		assert rig.raw.sensor_have[1] && rig.raw.sensor_millis[1] == 31250
	}
	rig.bench.sim.once(key_tchp, ~u64(0))
	before := rig.raw.implausible
	rig.pass()
	rig.pass()
	assert rig.raw.implausible == before + 1
	rig.pass()
	assert rig.raw.sensor_have[2] && rig.raw.sensor_millis[2] == 44000
	// A fan that claims to turn backwards, or is not a number.
	for garbage in [u64(0xc5160000), 0x7f800000, 0x49742400] {
		rig.bench.sim.once(key_f0ac, garbage)
		seen := rig.raw.implausible
		rig.pass()
		rig.pass()
		assert rig.raw.implausible == seen + 1, '${garbage:x}'
		rig.pass()
		assert rig.raw.fan_have[0] && rig.raw.fan_rpm[0] == 2400
	}
	rig.free()
}

// ── What it amounts to ──────────────────────────────────────────────────────

fn test_charging() {
	for old_order in [true, false] {
		mut rig := new_rig(true, true, old_order)
		supply := rig.pass()
		assert supply.charge == .charging
		assert supply.percent == 62
		assert supply.remaining == 2590000
		assert supply.full == 4200000
		assert supply.design == 4380000
		assert supply.current == 1500000
		assert supply.voltage == 12300000
		assert supply.minimum == 9000000
		assert supply.cycles == 77
		assert supply.to_full == 65 * 60
		assert supply.to_empty == 0
		assert !supply.critical
		assert supply.limit == 100
		assert supply.charger_known && supply.charger_online
		assert rig.filter.jumps == 0 && rig.filter.implausible == 0
		rig.free()
	}
}

fn test_the_charger_pulled_and_the_battery_run_down() {
	mut rig := new_rig(false, false, false)
	rig.pass()
	rig.bench.sim.scene(.unplugged)
	mut supply := rig.pass()
	assert supply.charge == .discharging
	assert supply.percent == 60
	assert supply.remaining == 2533000
	assert supply.current == 1200000
	assert supply.voltage == 11700000
	assert supply.charger_known && !supply.charger_online
	assert supply.limit == 0
	// The estimates are slow keys: within five passes they are the new ones.
	for _ in 0 .. 5 {
		supply = rig.pass()
	}
	assert supply.to_empty == 130 * 60
	assert supply.to_full == 0
	rig.bench.sim.scene(.low)
	// Fifty-two points at once: believed at the second look.
	supply = rig.pass()
	assert supply.percent == 60
	supply = rig.pass()
	assert supply.percent == 8
	assert supply.remaining == 345000
	assert rig.filter.jumps == 1
	// Six points down in a second is one more than is believed at sight.
	rig.bench.sim.scene(.critical)
	supply = rig.pass()
	assert supply.percent == 8
	supply = rig.pass()
	assert supply.percent == 2 && supply.charge == .discharging
	assert !supply.critical
	rig.bench.sim.scene(.full)
	supply = rig.pass()
	assert supply.percent == 2
	supply = rig.pass()
	assert supply.percent == 100 && supply.charge == .full
	assert supply.remaining == 4200000
	assert supply.charger_online
	rig.free()
}

// A table of flags against what Linux's macsmc_battery_get_status() makes of
// them. Every key is given, so each line changes only what it names.
struct StatusCase {
	name    string
	ch0r    u64
	chce    u64 = 1
	chcc    u64 = 1
	bsfc    u64
	chnc    u64
	chwa    u64
	percent int = 50
	wanted  Charge
}

fn test_the_state_follows_the_flags_as_linux_reads_them() {
	cases := [
		StatusCase{
			name:   'nothing in the way'
			wanted: .charging
		},
		StatusCase{
			name:   'no charger'
			chce:   0
			wanted: .discharging
		},
		StatusCase{
			name:   'a charger that cannot charge'
			chcc:   0
			wanted: .discharging
		},
		StatusCase{
			name:   'its power not taken'
			ch0r:   0x10
			wanted: .discharging
		},
		StatusCase{
			name:   'its power not taken, whatever else is said'
			ch0r:   0x1
			bsfc:   1
			wanted: .discharging
		},
		StatusCase{
			name:   'the management busy is no reason not to take it'
			ch0r:   0x100
			wanted: .charging
		},
		StatusCase{
			name:   'a reason above the low sixteen bits is none'
			ch0r:   0x10000
			wanted: .charging
		},
		StatusCase{
			name:   'full by the system flag'
			bsfc:   1
			wanted: .full
		},
		StatusCase{
			name:   'full by the reasons'
			chnc:   0x1
			wanted: .full
		},
		StatusCase{
			name:   'held back for some reason'
			chnc:   0x4000
			wanted: .not_charging
		},
		StatusCase{
			name:   'the management busy counts as charging'
			chnc:   u64(1) << 23
			wanted: .charging
		},
		StatusCase{
			name:   'busy and another reason does not'
			chnc:   (u64(1) << 23) | 0x8000
			wanted: .not_charging
		},
		StatusCase{
			name:    'busy with the limit reached is the limit'
			chnc:    u64(1) << 23
			chwa:    1
			percent: 78
			wanted:  .not_charging
		},
		StatusCase{
			name:    'busy under the limit is charging'
			chnc:    u64(1) << 23
			chwa:    1
			percent: 70
			wanted:  .charging
		},
		StatusCase{
			name:    'the limit with the charge unknown'
			chnc:    u64(1) << 23
			chwa:    1
			percent: -1
			wanted:  .charging
		},
	]
	for c in cases {
		mut raw := Raw{}
		for slot in [slot_ch0r, slot_chce, slot_chcc, slot_bsfc, slot_chnc, slot_chwa] {
			raw.have[slot] = true
		}
		raw.value[slot_ch0r] = c.ch0r
		raw.value[slot_chce] = c.chce
		raw.value[slot_chcc] = c.chcc
		raw.value[slot_bsfc] = c.bsfc
		raw.value[slot_chnc] = c.chnc
		raw.value[slot_chwa] = c.chwa
		assert charge_of(raw, c.percent) == c.wanted, c.name
	}
}

fn test_the_state_is_unknown_when_a_key_it_rests_on_was_not_read() {
	mut raw := Raw{}
	assert charge_of(raw, 50) == .unknown
	raw.have[slot_chce] = true
	raw.value[slot_chce] = 1
	assert charge_of(raw, 50) == .unknown
	raw.have[slot_chcc] = true
	raw.value[slot_chcc] = 1
	assert charge_of(raw, 50) == .unknown
	raw.have[slot_bsfc] = true
	// No reasons key and no flag for charging either.
	assert charge_of(raw, 50) == .unknown
	// The flag of an SMC with no reasons key.
	raw.have[slot_chsc] = true
	raw.value[slot_chsc] = 1
	assert charge_of(raw, 50) == .charging
	raw.value[slot_chsc] = 0
	assert charge_of(raw, 50) == .not_charging
	// A charger held under a tenth of an ampere, where the SMC says so.
	raw.have[slot_aci] = true
	raw.value[slot_aci] = 99
	assert charge_of(raw, 50) == .discharging
	raw.value[slot_aci] = 100
	assert charge_of(raw, 50) == .not_charging
	// A charger that is not there is known without the rest.
	mut bare := Raw{}
	bare.have[slot_chce] = true
	assert charge_of(bare, 50) == .discharging
	mut refused := Raw{}
	refused.have[slot_ch0r] = true
	refused.value[slot_ch0r] = 0x20
	assert charge_of(refused, 50) == .discharging
}

fn test_one_wild_percentage_is_not_believed() {
	mut rig := new_rig(false, false, false)
	rig.pass()
	rig.bench.sim.scene(.unplugged)
	assert rig.pass().percent == 60
	// Nothing, once: the gauge was busy.
	rig.bench.sim.once(key_buic, 0)
	mut supply := rig.pass()
	assert supply.percent == 60
	assert rig.filter.jumps == 1
	supply = rig.pass()
	assert supply.percent == 60
	// One wild reading after another, each different, is none of them.
	for wild in [u64(3), 95, 20, 100] {
		rig.bench.sim.once(key_buic, wild)
		assert rig.pass().percent == 60
	}
	// A real fall is followed a point at a time, at once.
	for percent in [u64(59), 58, 57, 52, 47] {
		rig.bench.sim.update(key_buic, percent)
		assert rig.pass().percent == int(percent)
	}
	// And one that is more than a percentage is no percentage at all.
	rig.bench.sim.once(key_buic, 250)
	supply = rig.pass()
	assert supply.percent == -1
	assert rig.pass().percent == 47
	rig.free()
}

fn test_settling_on_its_own() {
	mut settled := Settled{}
	mut value, mut at_once := settled.take(60, 5)
	assert value == 60 && at_once
	value, at_once = settled.take(65, 5)
	assert value == 65 && at_once
	value, at_once = settled.take(71, 5)
	assert value == 65 && !at_once
	value, at_once = settled.take(65, 5)
	assert value == 65 && at_once
	value, at_once = settled.take(10, 5)
	assert value == 65 && !at_once
	value, at_once = settled.take(12, 5)
	assert value == 12 && at_once
	// After a sleep the first reading stands.
	mut filter := Filter{
		percent: settled
	}
	filter.critical_run = 2
	filter.restart()
	value, at_once = filter.percent.take(90, 5)
	assert value == 90 && at_once
	assert filter.critical_run == 0
}

fn test_about_to_give_out_has_to_be_said_twice() {
	for old_order in [true, false] {
		mut rig := new_rig(false, false, old_order)
		rig.pass()
		rig.bench.sim.scene(.unplugged)
		rig.pass()
		rig.bench.sim.once(key_bcf0, 1)
		assert !rig.pass().critical
		assert !rig.pass().critical
		assert rig.filter.unconfirmed == 1
		rig.bench.sim.update(key_bcf0, 1)
		assert !rig.pass().critical
		assert rig.pass().critical
		assert rig.pass().critical
		rig.bench.sim.update(key_bcf0, 0)
		assert !rig.pass().critical
		assert rig.filter.unconfirmed == 1
		rig.free()
	}
}

fn test_figures_that_cannot_be_what_they_claim_are_left_out() {
	mut rig := new_rig(false, false, false)
	rig.pass()
	// More than the battery holds: the count is left, and the share stands in.
	rig.bench.sim.once(key_b0rm, 60000)
	mut supply := rig.pass()
	assert supply.remaining == 42000 * 62
	assert rig.filter.implausible == 1
	supply = rig.pass()
	assert supply.remaining == 2590000
	// A tenth over is allowed: a gauge that has not relearned what full is.
	rig.bench.sim.update(key_b0rm, 4600)
	assert rig.pass().remaining == 4600000
	rig.bench.sim.update(key_b0rm, 4621)
	assert rig.pass().remaining == 42000 * 62
	// An empty battery is empty, not unknown.
	rig.bench.sim.update(key_b0rm, 0)
	assert rig.pass().remaining == 0
	rig.free()

	// A full charge of nothing, of all ones, or of far more than the design.
	for full in [u64(0), 0xffff, 7000] {
		mut odd := new_rig(false, false, false)
		odd.bench.sim.update(key_b0fc, full)
		supply = odd.pass()
		assert supply.full == 0, '${full}'
		// Held against what it was made to hold instead.
		assert supply.remaining == 2590000
		odd.free()
	}
	// No voltage at all is not a voltage.
	mut flat := new_rig(false, false, false)
	flat.bench.sim.update(0x42304156, 0)
	supply = flat.pass()
	assert supply.voltage == 0
	assert flat.filter.implausible == 1
	flat.free()
}

fn test_a_remaining_charge_whose_order_is_not_known_is_worked_out() {
	mut bench := started_bench(false, false, false)
	bench.sim.remove(key_bcf0)
	mut rig := &Rig{
		bench: bench
	}
	assert discover(bench.state, mut rig.machine, false, false) == 0
	assert !rig.machine.remaining_usable
	supply := rig.pass()
	assert supply.percent == 62
	assert supply.remaining == 42000 * 62
	assert !supply.critical
	// With neither the count nor what it is a share of, there is no amount.
	bench.sim.remove(key_b0fc)
	mut bare := &Rig{
		bench: bench
	}
	assert discover(bench.state, mut bare.machine, false, false) == 0
	nothing := bare.pass()
	assert nothing.remaining == 0 && nothing.full == 0
	assert nothing.percent == 62
	rig.free()
}

fn test_the_percentage_gone_leaves_the_rest() {
	mut rig := new_rig(false, false, false)
	rig.pass()
	rig.bench.sim.remove(key_buic)
	rig.bench.wait(1000)
	supply := rig.pass()
	assert supply.percent == -1
	assert supply.remaining == 2590000 && supply.full == 4200000
	assert supply.charge == .charging
	rig.free()
}

fn test_the_times_are_given_only_for_the_way_the_charge_is_moving() {
	mut rig := new_rig(false, false, false)
	rig.bench.sim.update(key_b0te, 200)
	rig.bench.sim.update(key_b0tf, 65)
	mut supply := rig.pass()
	assert supply.charge == .charging
	assert supply.to_full == 3900 && supply.to_empty == 0
	rig.bench.sim.set_charger(false)
	supply = rig.pass()
	assert supply.charge == .discharging
	assert supply.to_empty == 12000 && supply.to_full == 0
	rig.free()
}

// ── The charge limit ────────────────────────────────────────────────────────

fn test_the_limit_is_set_read_back_and_shown() {
	mut rig := new_rig(true, true, true)
	assert rig.pass().limit == 100
	assert set_limit(rig.bench.state, rig.machine, mut rig.raw, 80) == 0
	assert rig.bench.sim.value_of(key_chwa) == 1
	assert rig.bench.sim.writes == 1
	assert rig.bench.sim.last_written == key_chwa && rig.bench.sim.last_byte == 1
	assert rig.pass().limit == 80
	assert set_limit(rig.bench.state, rig.machine, mut rig.raw, 100) == 0
	assert rig.bench.sim.value_of(key_chwa) == 0
	assert rig.bench.sim.last_byte == 0
	assert rig.pass().limit == 100
	assert rig.bench.sim.writes == 2
	assert vinix_smc_key_writes(rig.bench.state) == 2
	// Nothing but that key was ever written.
	for i in 0 .. sim_key_slots {
		key := rig.bench.sim.keys[i]
		if key.used && key.key != key_chwa {
			assert key.writes == 0
		}
	}
	rig.free()
}

fn test_only_what_the_firmware_takes_is_sent() {
	mut rig := new_rig(true, true, true)
	rig.pass()
	for percent in [u64(0), 1, 50, 60, 79, 81, 90, 95, 99, 101, 255, 256, 65616] {
		assert set_limit(rig.bench.state, rig.machine, mut rig.raw, percent) == vinix_smc_argument, '${percent}'
		assert !limit_acceptable(percent)
	}
	assert limit_acceptable(80) && limit_acceptable(100)
	assert rig.bench.sim.writes == 0
	assert vinix_smc_key_writes(rig.bench.state) == 0
	rig.free()
}

fn test_no_key_no_limit() {
	mut rig := new_rig(true, false, true)
	assert rig.pass().limit == 0
	sent := rig.bench.sent
	assert set_limit(rig.bench.state, rig.machine, mut rig.raw, 80) == vinix_smc_no_key
	assert rig.bench.sent == sent
	rig.free()
	// Nor where the key is there and was asked to be left alone.
	mut bench := started_bench(true, true, true)
	mut left := &Rig{
		bench: bench
	}
	assert discover(bench.state, mut left.machine, false, true) == 0
	assert left.pass().limit == 0
	assert set_limit(bench.state, left.machine, mut left.raw, 80) == vinix_smc_no_key
	assert bench.sim.writes == 0
	assert bench.sim.keys[bench.sim.find(key_chwa)].reads == 0
	left.free()
}

fn test_a_limit_that_did_not_take_is_reported() {
	// The firmware says yes and keeps what it had.
	mut rig := new_rig(true, true, true)
	rig.pass()
	rig.bench.sim.ignore_writes = true
	assert set_limit(rig.bench.state, rig.machine, mut rig.raw, 80) == vinix_smc_range
	assert rig.pass().limit == 100
	rig.free()
	// The key may not be written.
	rig = new_rig(true, true, true)
	rig.bench.sim.put(key_chwa, sim_type_flag, flag_readable, 1, 0)
	assert set_limit(rig.bench.state, rig.machine, mut rig.raw, 80) == vinix_smc_io
	assert vinix_smc_failure(rig.bench.state) == 0
	assert rig.pass().limit == 100
	rig.free()
	// It never answers.
	rig = new_rig(true, true, true)
	rig.bench.sim.silent = true
	assert set_limit(rig.bench.state, rig.machine, mut rig.raw, 80) == vinix_smc_timeout
	assert rig.bench.sim.value_of(key_chwa) == 0
	rig.free()
}
