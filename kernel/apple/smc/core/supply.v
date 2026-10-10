// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2026 Alexander Medvednikov
//
// What an Apple laptop's SMC says about its battery, its charger, its
// temperatures and its fans: which keys it has (discover), their values now
// (sample), and what those values amount to (judge).
//
// The three are separate so that each can be tried without the others, and
// none of them knows the kernel: the first two talk to the SMC through
// core.v, the third is arithmetic. smc.v, above, owns the thread that calls
// them and hands the result to the kernel's power supply and thermal classes.
//
// The logic is Linux's (drivers/power/supply/macsmc-power.c as of the Asahi
// tree's `asahi` branch, which adds the CHWA charge limit to what mainline
// has; drivers/hwmon/macsmc-hwmon.c for sensors and fans), with three
// differences that are deliberate:
//
//   - Nothing is written here at all. Linux, when it starts, clears the
//     charge inhibit keys (CHTE, CH0C, CH0I, CH0K, CH0B) and switches the
//     SMC's notifications on (NTAP). This kernel reads.
//   - A key is asked for with the size GET_KEY_INFO gave it, and is left
//     alone when that is not the size expected. Linux assumes the size.
//   - Figures are not all believed; see judge().
//
// Not read: CHLS, the charge limit of the firmware that has no CHWA (setting
// it means writing a force-discharge bit as well); CHTE/CH0C/CH0I, the charge
// inhibits; ACSt; the battery's temperature B0AT, which the sensor TB0T
// covers; and the power, voltage and current sensors of macsmc-hwmon, which
// the kernel's hwmon view has no files for.
module core

// One slot for each key the battery and the charger are read through.
pub const slot_b0rm = 0
pub const slot_b0fc = 1
pub const slot_b0dc = 2
pub const slot_b0ct = 3
pub const slot_b0te = 4
pub const slot_b0tf = 5
pub const slot_bitv = 6
pub const slot_bsfc = 7
pub const slot_bcf0 = 8
pub const slot_ch0r = 9
pub const slot_chce = 10
pub const slot_chcc = 11
pub const slot_chnc = 12
pub const slot_chsc = 13
pub const slot_chis = 14
pub const slot_chwa = 15
pub const slot_aci = 16
pub const slot_count = 17

pub fn slot_key(slot int) u32 {
	return match slot {
		slot_b0rm { key_b0rm }
		slot_b0fc { key_b0fc }
		slot_b0dc { key_b0dc }
		slot_b0ct { key_b0ct }
		slot_b0te { key_b0te }
		slot_b0tf { key_b0tf }
		slot_bitv { key_bitv }
		slot_bsfc { key_bsfc }
		slot_bcf0 { key_bcf0 }
		slot_ch0r { key_ch0r }
		slot_chce { key_chce }
		slot_chcc { key_chcc }
		slot_chnc { key_chnc }
		slot_chsc { key_chsc }
		slot_chis { key_chis }
		slot_chwa { key_chwa }
		slot_aci { key_aci }
		else { u32(0) }
	}
}

// The size a key must have to be read as what it is taken for. BCF0 is one
// byte or four, and which says something else; see discover().
fn slot_size(slot int) u8 {
	return match slot {
		slot_bsfc, slot_chce, slot_chcc, slot_chsc, slot_chwa { u8(1) }
		slot_ch0r, slot_chis { u8(4) }
		slot_chnc { u8(8) }
		else { u8(2) }
	}
}

// How often a key is read, in passes: 0 for once.
fn slot_period(slot int) int {
	return match slot {
		// What the battery was made as does not change.
		slot_b0dc, slot_bitv { 0 }
		// These move over minutes, or over the battery's life.
		slot_b0fc, slot_b0ct, slot_b0te, slot_b0tf, slot_chwa { slow_period }
		else { 1 }
	}
}

const slow_period = 5

// A key that failed this many reads in a row is asked again only now and
// then: an error costs an exchange like any answer.
const back_off_after = u8(3)
const back_off_period = u64(30)

pub const max_sensors = 8
pub const max_fans = 4
pub const text_bytes = 32

// The temperatures looked for: Linux's hwmon-common.dtsi and
// hwmon-laptop.dtsi, which is what it gives an M1 MacBook Air and Pro.
const known_sensors = 4

fn sensor_key(index int) u32 {
	return match index {
		0 { key_th0x }
		1 { key_tb0t }
		2 { key_tchp }
		3 { key_tw0p }
		else { u32(0) }
	}
}

// Linux's labels for them.
pub fn sensor_label(index int) string {
	return match index {
		0 { 'NAND Flash Temperature' }
		1 { 'Battery Hotspot' }
		2 { 'Charge Regulator Temp' }
		3 { 'WiFi/BT Module Temp' }
		else { '' }
	}
}

pub struct SlotInfo {
pub mut:
	present bool
	size    u8
	kind    u32
	flags   u8
}

pub struct SensorInfo {
pub mut:
	// Which of the known sensors: sensor_label()'s index.
	known int
	key   u32
	kind  u32
}

pub struct FanInfo {
pub mut:
	// The digit in its keys.
	number      int
	has_minimum bool
	minimum     u64
	has_maximum bool
	maximum     u64
}

// What one SMC turned out to have. Filled in once, by discover().
pub struct Machine {
pub mut:
	slots [slot_count]SlotInfo
	// B0RM can be read, and which way round.
	remaining_usable     bool
	remaining_big_endian bool
	model        [text_bytes]u8
	model_len    int
	serial       [text_bytes]u8
	serial_len   int
	sensors      [max_sensors]SensorInfo
	sensor_count int
	fans         [max_fans]FanInfo
	fan_count    int
	// Keys asked about, and keys taken on.
	asked int
	found int
	// Keys that are there with a size that is not the one expected.
	odd_sized int
}

// The values last read. A slot's value stands until it is read again; one
// whose read failed is not known until a read succeeds.
pub struct Raw {
pub mut:
	passes        u64
	have          [slot_count]bool
	value         [slot_count]u64
	failures      [slot_count]u8
	sensor_have   [max_sensors]bool
	sensor_millis [max_sensors]i64
	sensor_failed [max_sensors]u8
	fan_have      [max_fans]bool
	fan_rpm       [max_fans]u64
	fan_failed    [max_fans]u8
	// Reads the SMC answered with an error.
	key_errors u64
	// Temperatures and speeds that could not be what they claimed.
	implausible u64
}

// No part of a machine that still answers is colder than absolute zero or as
// hot as this: the bounds the ACPI thermal zones are held to as well.
pub const coldest_millis = i64(-273150)
pub const hottest_millis = i64(200000)

pub fn plausible_temperature(millis i64) bool {
	return millis > coldest_millis && millis < hottest_millis
}

// No fan turns backwards, or this fast.
pub const fastest_rpm = i64(100000)

// What the SMC says of a key; `present` is false when it has none.
fn info_of(state voidptr, key u32) SlotInfo {
	mut size := u8(0)
	mut kind := u32(0)
	mut flags := u8(0)
	if vinix_smc_key_info(state, key, &size, &kind, &flags) != 0 {
		return SlotInfo{}
	}
	return SlotInfo{
		present: true
		size:    size
		kind:    kind
		flags:   flags
	}
}

// A key of `size` bytes, at most eight, as a little-endian number.
fn read_number(state voidptr, key u32, size int) (bool, u64) {
	mut bytes := [8]u8{}
	if size < 1 || size > 8 || vinix_smc_read_key(state, key, u32(size), &bytes[0]) != 0 {
		return false, u64(0)
	}
	return true, little_endian(&bytes[0], size)
}

// A key holding text: what is printable of it up to the first NUL, without
// the spaces at its end. Returns the length.
fn read_text(state voidptr, key u32, out &u8) int {
	info := info_of(state, key)
	if !info.present || info.size == 0 || int(info.size) > text_bytes {
		return 0
	}
	mut bytes := [text_bytes]u8{}
	if vinix_smc_read_key(state, key, u32(info.size), &bytes[0]) != 0 {
		return 0
	}
	mut length := 0
	for i in 0 .. int(info.size) {
		c := bytes[i]
		if c == 0 {
			break
		}
		if c < 0x20 || c > 0x7e {
			continue
		}
		unsafe {
			out[length] = c
		}
		length++
	}
	for length > 0 && unsafe { out[length - 1] } == ` ` {
		length--
	}
	return length
}

// A temperature key's bytes as millidegrees Celsius, if they are one.
fn temperature_of(kind u32, value u64) (bool, i64) {
	mut millis := i64(0)
	if kind == type_flt {
		bits := u32(value)
		if !flt_is_number(bits) {
			return false, i64(0)
		}
		millis = flt_scaled(bits, 1000)
	} else if kind == type_ioft {
		scaled := ioft_scaled(value, 1000)
		if scaled > u64(hottest_millis) {
			return false, i64(0)
		}
		millis = i64(scaled)
	} else {
		return false, i64(0)
	}
	return plausible_temperature(millis), millis
}

// A fan speed key's bytes as revolutions a minute, if they are that.
fn speed_of(value u64) (bool, u64) {
	bits := u32(value)
	if !flt_is_number(bits) {
		return false, u64(0)
	}
	rpm := flt_scaled(bits, 1)
	if rpm < 0 || rpm >= fastest_rpm {
		return false, u64(0)
	}
	return true, u64(rpm)
}

fn sensor_type_known(info &SlotInfo) bool {
	return (info.kind == type_flt && info.size == 4) || (info.kind == type_ioft && info.size == 8)
}

// Ask the SMC which of the keys above it has. `machine` is filled in from
// nothing. Returns 0, or the reason the channel was given up, in which case
// what was found so far is of no use.
//
// A key the SMC does not have, or has with another size, is simply not taken
// on: the files that would have shown it are not made.
pub fn discover(state voidptr, mut machine Machine, no_sensors bool, no_limit bool) i32 {
	for slot in 0 .. slot_count {
		machine.slots[slot] = SlotInfo{}
		if slot == slot_chwa && no_limit {
			continue
		}
		machine.asked++
		info := info_of(state, slot_key(slot))
		failure := vinix_smc_failure(state)
		if failure != 0 {
			return failure
		}
		if !info.present {
			continue
		}
		right_size := if slot == slot_bcf0 {
			info.size == 1 || info.size == 4
		} else {
			info.size == slot_size(slot)
		}
		if !right_size {
			machine.odd_sized++
			continue
		}
		machine.slots[slot] = info
		machine.found++
	}
	// Linux's fw_ge_27: where the flag that says the battery is about to give
	// out is one byte, the remaining charge is little-endian like every other
	// figure; where it is four, the remaining charge is big-endian. Where
	// there is no such flag the order is not known and the figure is left.
	if machine.slots[slot_bcf0].present && machine.slots[slot_b0rm].present {
		machine.remaining_usable = true
		machine.remaining_big_endian = machine.slots[slot_bcf0].size == 4
	}
	machine.model_len = read_text(state, key_bmdn, &machine.model[0])
	machine.serial_len = read_text(state, key_bmsn, &machine.serial[0])
	mut failure := vinix_smc_failure(state)
	if failure != 0 {
		return failure
	}
	if no_sensors {
		return 0
	}
	for index in 0 .. known_sensors {
		if machine.sensor_count >= max_sensors {
			break
		}
		machine.asked++
		info := info_of(state, sensor_key(index))
		failure = vinix_smc_failure(state)
		if failure != 0 {
			return failure
		}
		if !info.present {
			continue
		}
		if !sensor_type_known(info) {
			machine.odd_sized++
			continue
		}
		machine.sensors[machine.sensor_count] = SensorInfo{
			known: index
			key:   sensor_key(index)
			kind:  info.kind
		}
		machine.sensor_count++
		machine.found++
	}
	// Fans are there when FNum says how many: an M1 MacBook Air has none.
	machine.asked++
	count_info := info_of(state, key_fnum)
	if count_info.present && count_info.size == 1 {
		machine.found++
		ok, count := read_number(state, key_fnum, 1)
		mut fans := if ok { int(count) } else { 0 }
		if fans > max_fans {
			fans = max_fans
		}
		for number in 0 .. fans {
			machine.asked++
			info := info_of(state, fan_key(number, `A`, `c`))
			if !info.present || info.kind != type_flt || info.size != 4 {
				continue
			}
			machine.found++
			mut fan := FanInfo{
				number: number
			}
			has_minimum, minimum := fan_limit(state, fan_key(number, `M`, `n`))
			fan.has_minimum = has_minimum
			fan.minimum = minimum
			has_maximum, maximum := fan_limit(state, fan_key(number, `M`, `x`))
			fan.has_maximum = has_maximum
			fan.maximum = maximum
			machine.fans[machine.fan_count] = fan
			machine.fan_count++
		}
	}
	return vinix_smc_failure(state)
}

// The slowest or the fastest a fan runs, where the SMC says: read once.
fn fan_limit(state voidptr, key u32) (bool, u64) {
	info := info_of(state, key)
	if !info.present || info.kind != type_flt || info.size != 4 {
		return false, u64(0)
	}
	read, value := read_number(state, key, 4)
	if !read {
		return false, u64(0)
	}
	good, rpm := speed_of(value)
	return good, rpm
}

// Whether a key that keeps failing is due to be asked again on this pass.
fn due(failed u8, pass u64, place u64) bool {
	return failed < back_off_after || (pass + place) % back_off_period == 0
}

// Read what is due on this pass. Returns 0, or the reason the channel was
// given up; an error from one key is that key's alone.
//
// On a MacBook Air this is eleven exchanges a second on average, beside the
// four of the capacity and telemetry keys: eight keys every pass (nine where
// the SMC still has AC-i), each of five more every fifth pass in turn, and
// two of the four temperatures.
pub fn sample(state voidptr, machine &Machine, mut raw Raw) i32 {
	pass := raw.passes
	raw.passes++
	for slot in 0 .. slot_count {
		if !machine.slots[slot].present {
			continue
		}
		// Linux reads CHSC only where there is no CHNC.
		if slot == slot_chsc && machine.slots[slot_chnc].present {
			continue
		}
		period := slot_period(slot)
		if raw.have[slot] {
			if period == 0 {
				continue
			}
			if period > 1 && (pass + u64(slot)) % u64(period) != 0 {
				continue
			}
		} else if !due(raw.failures[slot], pass, u64(slot)) {
			continue
		}
		ok, value := read_number(state, slot_key(slot), int(machine.slots[slot].size))
		failure := vinix_smc_failure(state)
		if failure != 0 {
			return failure
		}
		if ok {
			raw.have[slot] = true
			raw.value[slot] = value
			raw.failures[slot] = 0
			continue
		}
		raw.have[slot] = false
		raw.key_errors++
		if raw.failures[slot] < 255 {
			raw.failures[slot]++
		}
	}
	for index in 0 .. machine.sensor_count {
		// Half of them on each pass: nothing here moves in a second.
		if raw.sensor_have[index] && (pass + u64(index)) % 2 != 0 {
			continue
		}
		if !raw.sensor_have[index] && !due(raw.sensor_failed[index], pass, u64(index)) {
			continue
		}
		sensor := &machine.sensors[index]
		size := if sensor.kind == type_ioft { 8 } else { 4 }
		ok, value := read_number(state, sensor.key, size)
		failure := vinix_smc_failure(state)
		if failure != 0 {
			return failure
		}
		mut good := false
		mut millis := i64(0)
		if ok {
			good, millis = temperature_of(sensor.kind, value)
			if !good {
				raw.implausible++
			}
		} else {
			raw.key_errors++
		}
		raw.sensor_have[index] = good
		if good {
			raw.sensor_millis[index] = millis
			raw.sensor_failed[index] = 0
		} else if raw.sensor_failed[index] < 255 {
			raw.sensor_failed[index]++
		}
	}
	for index in 0 .. machine.fan_count {
		if raw.fan_have[index] && (pass + u64(index)) % 2 != 1 {
			continue
		}
		if !raw.fan_have[index] && !due(raw.fan_failed[index], pass, u64(index)) {
			continue
		}
		ok, value := read_number(state, fan_key(machine.fans[index].number, `A`, `c`), 4)
		failure := vinix_smc_failure(state)
		if failure != 0 {
			return failure
		}
		mut good := false
		mut rpm := u64(0)
		if ok {
			good, rpm = speed_of(value)
			if !good {
				raw.implausible++
			}
		} else {
			raw.key_errors++
		}
		raw.fan_have[index] = good
		if good {
			raw.fan_rpm[index] = rpm
			raw.fan_failed[index] = 0
		} else if raw.fan_failed[index] < 255 {
			raw.fan_failed[index]++
		}
	}
	return 0
}

// ── What the values amount to ───────────────────────────────────────────────

pub enum Charge {
	unknown
	charging
	discharging
	not_charging
	full
}

// CH0R: the low sixteen bits are reasons the charger's power is not taken;
// bit 8 is the battery's own management being busy, which is not one.
const ch0r_lower_flags = u64(0xffff)
const ch0r_bms_busy = u64(1) << 8
// CHNC: reasons the battery is not being charged.
const chnc_battery_full = u64(1) << 0
const chnc_bms_busy = u64(1) << 23
// With CHWA set the battery is held between 75 and 80 percent.
pub const chwa_limit = u64(80)
const chwa_start = 75

// What the battery is doing: Linux's macsmc_battery_get_status(), flag for
// flag. `percent` is the charge shown to the user, or negative for unknown.
pub fn charge_of(raw &Raw, percent int) Charge {
	if raw.have[slot_ch0r] && raw.value[slot_ch0r] & ch0r_lower_flags & ~ch0r_bms_busy != 0 {
		return .discharging
	}
	if !raw.have[slot_chce] {
		return .unknown
	}
	if raw.value[slot_chce] == 0 {
		return .discharging
	}
	if !raw.have[slot_chcc] {
		return .unknown
	}
	if raw.value[slot_chcc] == 0 {
		return .discharging
	}
	// A charger held to under a tenth of an ampere charges nothing.
	if raw.have[slot_aci] && raw.value[slot_aci] < 100 {
		return .discharging
	}
	if !raw.have[slot_bsfc] {
		return .unknown
	}
	if raw.value[slot_bsfc] != 0 {
		return .full
	}
	limited := raw.have[slot_chwa] && raw.value[slot_chwa] != 0 && percent >= chwa_start
	if raw.have[slot_chnc] {
		reasons := raw.value[slot_chnc]
		if reasons & chnc_battery_full != 0 {
			return .full
		}
		// The management being busy shows as a reason, and is none unless
		// the charge limit is what keeps the charger off.
		if reasons == chnc_bms_busy && !limited {
			return .charging
		}
		if reasons != 0 {
			return .not_charging
		}
		return .charging
	}
	if !raw.have[slot_chsc] {
		return .unknown
	}
	if raw.value[slot_chsc] == 0 {
		return .not_charging
	}
	return .charging
}

// A figure that is believed only once it has been seen twice, unless it is
// close to the last one believed.
pub struct Settled {
pub mut:
	has       bool
	value     int
	pending   bool
	candidate int
}

fn distance(a int, b int) int {
	return if a > b { a - b } else { b - a }
}

// Take a reading and return what is believed. Whether the reading itself
// was believed is what the second value says.
pub fn (mut s Settled) take(reading int, tolerance int) (int, bool) {
	if !s.has {
		s.has = true
		s.value = reading
		s.pending = false
		return reading, true
	}
	if distance(reading, s.value) <= tolerance {
		s.value = reading
		s.pending = false
		return reading, true
	}
	if s.pending && distance(reading, s.candidate) <= tolerance {
		s.value = reading
		s.pending = false
		return reading, true
	}
	s.candidate = reading
	s.pending = true
	return s.value, false
}

// What is remembered from one pass to the next, and what had to be
// disbelieved, for whoever asks why a figure did not move.
pub struct Filter {
pub mut:
	percent      Settled
	critical_run u32
	// Percentages not believed when first seen.
	jumps u64
	// "About to give out" flags that were gone at the second look.
	unconfirmed u64
	// Charges and voltages that could not be what they claimed.
	implausible u64
}

// After the machine has been away -- a sleep -- the next reading is the
// first: the charge may truly have moved a long way.
pub fn (mut f Filter) restart() {
	f.percent = Settled{}
	f.critical_run = 0
}

// How far the charge shown may move between two passes and be believed at
// once. A battery does not gain or lose a twentieth of itself in a second.
pub const percent_tolerance = 5

// What the device nodes' two samples said on this pass: the percentage (or
// an error, which is negative) and the telemetry with its validity bits.
pub struct Legacy {
pub mut:
	percent     i32
	power_flags u32
	voltage_mv  i32
	current_ma  i32
}

// The battery and the charger as the power supply class wants them. Amounts
// are microampere-hours, the rate microamperes, voltages microvolts, times
// seconds; zero is "not known" for all but `percent`, where that is -1.
pub struct Supply {
pub mut:
	charge      Charge
	percent     int = -1
	remaining   u64
	full        u64
	design      u64
	current     u64
	voltage     u64
	minimum     u64
	cycles      u64
	to_empty    u64
	to_full     u64
	critical    bool
	// 80 or 100 where the SMC has the key; 0 where it has not, or cannot
	// be read just now.
	limit u64
	// The charger.
	charger_known  bool
	charger_online bool
}

// A sixteen-bit figure, or 0 when it is all ones (the SMC's "none") or was
// not read.
fn figure(raw &Raw, slot int) u64 {
	if !raw.have[slot] {
		return 0
	}
	value := raw.value[slot] & 0xffff
	return if value == 0xffff { u64(0) } else { value }
}

// Make of the values what the power supply class is told.
//
// What follows from these figures is, at the far end, the machine being
// switched off for an empty battery, so not every figure is taken at its
// word:
//
//   - a percentage that jumps by more than five points from one pass to the
//     next is not believed until a second reading bears it out;
//   - the SMC's flag that the battery is about to give out counts only once
//     it has been read set on two passes running;
//   - a remaining charge that is more than the battery holds when full by a
//     tenth, a full charge of nothing, and a voltage of nothing are left out.
//
// The power supply class adds its own caution on top: it acts on a critical
// battery only after five seconds of readings that all say so.
pub fn judge(machine &Machine, raw &Raw, legacy Legacy, mut filter Filter) Supply {
	mut supply := Supply{}
	if legacy.percent >= 0 && legacy.percent <= 100 {
		believed, at_once := filter.percent.take(int(legacy.percent), percent_tolerance)
		if !at_once {
			filter.jumps++
		}
		supply.percent = believed
	}
	supply.design = figure(raw, slot_b0dc) * 1000
	supply.full = figure(raw, slot_b0fc) * 1000
	if supply.design != 0 && supply.full > supply.design + supply.design / 2 {
		// More than half again what it was made to hold is not a capacity.
		filter.implausible++
		supply.full = 0
	}
	mut counted := false
	if machine.remaining_usable && raw.have[slot_b0rm] {
		mut remaining := raw.value[slot_b0rm] & 0xffff
		if machine.remaining_big_endian {
			remaining = swap16(remaining)
		}
		remaining *= 1000
		ceiling := if supply.full != 0 { supply.full } else { supply.design }
		if ceiling == 0 {
			// Nothing to hold it against: left out, like what it is a share of.
		} else if remaining > ceiling + ceiling / 10 {
			filter.implausible++
		} else {
			supply.remaining = remaining
			counted = true
		}
	}
	if !counted && supply.full != 0 && supply.percent >= 0 {
		// The SMC's own count could not be used: the share it shows of what
		// the battery holds stands in, so that the amount and the percentage
		// do not contradict each other. This one figure is worked out, not
		// read.
		supply.remaining = supply.full / 100 * u64(supply.percent)
	}
	if legacy.power_flags & 1 != 0 && legacy.voltage_mv > 0 {
		supply.voltage = u64(legacy.voltage_mv) * 1000
	} else if legacy.power_flags & 1 != 0 {
		filter.implausible++
	}
	if legacy.power_flags & 2 != 0 {
		magnitude := if legacy.current_ma < 0 { -i64(legacy.current_ma) } else { i64(legacy.current_ma) }
		supply.current = u64(magnitude) * 1000
	}
	supply.minimum = figure(raw, slot_bitv) * 1000
	supply.cycles = figure(raw, slot_b0ct)
	supply.charge = charge_of(raw, supply.percent)
	// The SMC keeps both estimates; only the one for the way the charge is
	// moving means anything.
	if supply.charge == .discharging {
		supply.to_empty = figure(raw, slot_b0te) * 60
	}
	if supply.charge == .charging {
		supply.to_full = figure(raw, slot_b0tf) * 60
	}
	if raw.have[slot_bcf0] && raw.value[slot_bcf0] != 0 {
		if filter.critical_run < 2 {
			filter.critical_run++
		}
	} else {
		if filter.critical_run == 1 {
			filter.unconfirmed++
		}
		filter.critical_run = 0
	}
	supply.critical = filter.critical_run >= 2
	if raw.have[slot_chwa] {
		supply.limit = if raw.value[slot_chwa] != 0 { chwa_limit } else { u64(100) }
	}
	if raw.have[slot_chis] {
		supply.charger_known = true
		supply.charger_online = raw.value[slot_chis] != 0
	}
	return supply
}

// ── The charge limit ────────────────────────────────────────────────────────

// Whether `percent` is a limit this SMC can be given: with CHWA it is 80 or
// none at all.
pub fn limit_acceptable(percent u64) bool {
	return percent == chwa_limit || percent == 100
}

// Set the charge limit, and read it back. 0 when the SMC then says what was
// asked; VINIX_SMC_NO_KEY where it has no limit to set, VINIX_SMC_ARGUMENT
// for a limit it cannot be given, VINIX_SMC_RANGE when the write was taken
// and the key reads otherwise afterwards, and the SMC's error else.
//
// This is the one place the kernel writes a key, and it is entered only for
// a write to charge_control_end_threshold.
pub fn set_limit(state voidptr, machine &Machine, mut raw Raw, percent u64) i32 {
	if !machine.slots[slot_chwa].present {
		return vinix_smc_no_key
	}
	if !limit_acceptable(percent) {
		return vinix_smc_argument
	}
	mut wanted := [1]u8{}
	wanted[0] = if percent == chwa_limit { u8(1) } else { u8(0) }
	result := vinix_smc_write_key(state, key_chwa, 1, &wanted[0])
	if result != 0 {
		return result
	}
	ok, value := read_number(state, key_chwa, 1)
	failure := vinix_smc_failure(state)
	if failure != 0 {
		return failure
	}
	if !ok {
		raw.have[slot_chwa] = false
		return vinix_smc_io
	}
	raw.have[slot_chwa] = true
	raw.value[slot_chwa] = value
	raw.failures[slot_chwa] = 0
	stored := if value != 0 { u8(1) } else { u8(0) }
	if stored != wanted[0] {
		return vinix_smc_range
	}
	return 0
}
