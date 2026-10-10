// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2026 Alexander Medvednikov
//
// The SMC's battery, charger, temperatures and fans in the kernel's own
// classes, beside the two device nodes of smc.v:
//
//	/sys/class/power_supply/macsmc-battery   status, capacity, charge_now,
//	                                         charge_full, charge_full_design,
//	                                         current_now, voltage_now,
//	                                         voltage_min_design, cycle_count,
//	                                         time_to_empty_now,
//	                                         time_to_full_now, model_name,
//	                                         serial_number, and
//	                                         charge_control_end_threshold
//	                                         where the SMC has a charge limit
//	/sys/class/power_supply/macsmc-ac        online
//	/sys/class/thermal/thermal_zoneN         type macsmc: the first
//	                                         temperature found, no trips
//	/sys/class/hwmon/hwmonN                  name macsmc_hwmon: every
//	                                         temperature with Linux's label,
//	                                         and fanM_input, _label, _min
//	                                         and _max where FNum counts fans
//	/sys/devices/platform/apple-smc/smc/     status, keys: what was found and
//	                                         what had to be disbelieved
//
// The names are Linux's (macsmc-power, macsmc-hwmon), and so is what each
// figure is read from: core/supply.v.
//
// Who does what. The thread of smc.v is the only one that talks to the SMC.
// Once a second it reads what is due (core.sample), weighs it (core.judge)
// and publishes the result here under a spinlock held for a copy. The power
// supply class's read functions, the thermal class's, and the files in /sys
// copy it back out under the same lock and never wait for the SMC. What they
// are given is no more than three seconds old, or it is not given: a battery
// whose SMC has stopped answering reads `Unknown` with no figures, its
// charger reads offline, and a temperature reads as nothing.
//
// Nothing here decides anything. The zone has no trip points -- the SMC
// gives no limit for these sensors, and one made up here could switch a
// machine off for a figure that was never a temperature -- and the fans are
// the SMC's to run: they are shown, not driven. What a low battery leads to
// is the power supply class's business, which waits for five seconds of
// agreement before it acts.
//
// Writing. One key is ever written, CHWA, and only when a program writes
// charge_control_end_threshold: 80 or 100, the two values that key has. The
// request is handed to the thread, which writes, reads the key back and
// reports whether it took.
//
// Sleep. The driver is on the device list (platform, `apple-smc`, driver
// `macsmc`) so that it is told of a sleep: the thread then leaves the SMC
// alone until the machine is back, and what it last published stands
// meanwhile, since nothing of the kernel's should take a sleep for a sensor
// that failed. Nothing of the SMC's can end a sleep here: its notifications
// are not switched on.
//
// `vinix.apple_smc=` on the command line takes words, with commas between:
// `legacy` leaves all of this out and the two device nodes as they always
// were; `nosensors` leaves out temperatures and fans; `nolimit` leaves the
// charge limit key alone, unread and unwritten.
@[has_globals]
module smc

import aarch64.kio
import apple.smc.core as smccore
import devcore
import errno
import fs
import katomic
import klock
import lib
import memory
import psupply
import thermal

// As much of the SMC's shared memory as is mapped: a key's value is at most
// 255 bytes long, and Linux maps one page of it knowing no more.
const shmem_bytes = u32(0x1000)

// How old what is published may be and still be given out, in seconds.
const stale_seconds = u64(3)

// How long a sleep waits for the thread to leave the SMC alone, and a wake
// for its first reading. A pass is some twenty exchanges of well under a
// millisecond each; either wait ends early when the thread is done.
const park_wait_ms = u64(2000)
const resume_wait_ms = u64(1500)

// How long a write of the charge limit waits for the thread: its next turn is
// a tenth of a second away, and the write and the reading back are held to
// half a second each by the protocol.
const limit_wait_ms = u64(5000)

const limit_idle = u32(0)
const limit_asked = u32(1)
const limit_taken = u32(2)
const limit_done = u32(3)

// What is shown of the driver's own doings, copied out with the readings.
struct Counters {
mut:
	passes      u64
	key_errors  u64
	implausible u64
	jumps       u64
	unconfirmed u64
	key_writes  u64
}

struct Class {
mut:
	// Off altogether (`legacy`), or by parts.
	enabled    bool
	no_sensors bool
	no_limit   bool
	simulated  bool
	frequency  u64
	// Where the SMC's shared memory is mapped, or 0.
	shmem u64

	// The thread's alone: what the SMC has, its values, what is remembered
	// between passes, and when the last pass was.
	machine   smccore.Machine
	raw       smccore.Raw
	filter    smccore.Filter
	passed    bool
	passed_at u64

	// Everybody's, under `l`.
	l            klock.Lock
	supply       smccore.Supply
	sensor_have  [smccore.max_sensors]bool
	sensor_value [smccore.max_sensors]i64
	fan_have     [smccore.max_fans]bool
	fan_value    [smccore.max_fans]u64
	counters     Counters
	// The counter when it was published; `published` says there is anything.
	published    bool
	published_at u64
	// The SMC stopped answering, and why.
	failed  bool
	failure i32

	// Read with katomic from anywhere.
	//
	// A sleep asks the thread to leave the SMC alone (park), and the thread
	// says when it has (parked); a round is one turn of the thread in which
	// it was not parked. The thread has ended (ended).
	park       u32
	parked     u32
	ended      u32
	rounds     u64
	parks      u64
	late_parks u64
	// One write of the charge limit at a time: who holds `limit_busy` may
	// ask, and the thread answers in `limit_result`.
	limit_busy   u32
	limit_state  u32
	limit_wanted u64
	limit_result i32

	// What was registered, once.
	has_battery bool
	battery     &psupply.Supply = unsafe { nil }
	charger     &psupply.Supply = unsafe { nil }
	zone        u64
	device      &devcore.Device = unsafe { nil }
}

__global (
	smc_class = &Class(unsafe { nil })
)

// ── The shared memory ───────────────────────────────────────────────────────

// The core's way into the SMC's shared memory: the firmware's own SRAM,
// mapped as device memory and read and written a byte at a time, as Linux's
// memcpy_fromio() and memcpy_toio() do.
fn shmem_io(_ voidptr, write i32, offset u32, buffer &u8, length u32) i32 {
	class := smc_class
	if class == unsafe { nil } || class.shmem == 0 || offset > shmem_bytes
		|| length > shmem_bytes - offset {
		return 0
	}
	for i in u32(0) .. length {
		address := unsafe { &u8(class.shmem + u64(offset) + u64(i)) }
		if write != 0 {
			kio.mmout(address, unsafe { buffer[i] })
		} else {
			value := kio.mmin(address)
			unsafe {
				buffer[i] = value
			}
		}
	}
	return 1
}

// ── Options ─────────────────────────────────────────────────────────────────

// Whether `word` is one of the comma-separated words of `value`.
fn has_word(value string, word string) bool {
	mut start := 0
	for index := 0; index <= value.len; index++ {
		if index != value.len && value[index] != `,` {
			continue
		}
		if index - start == word.len {
			mut same := true
			for i in 0 .. word.len {
				if value[start + i] != word[i] {
					same = false
					break
				}
			}
			if same {
				return true
			}
		}
		start = index + 1
	}
	return false
}

// ── Starting ────────────────────────────────────────────────────────────────

// Find out what the SMC has and read it once. Called from start(), before
// the thread exists, so this is the one other caller of the protocol core.
fn class_probe(mut dev Battery, simulated bool, capacity i32) {
	// Made once and kept for the life of the machine.
	mut class := &Class{}
	class.simulated = simulated
	class.frequency = dev.frequency
	class.enabled = true
	if choice := devcore.boot_option('vinix.apple_smc=') {
		if has_word(choice, 'legacy') {
			class.enabled = false
			print('apple-smc: power supplies, sensors and fans left out by vinix.apple_smc=legacy\n')
		}
		class.no_sensors = has_word(choice, 'nosensors')
		class.no_limit = has_word(choice, 'nolimit')
	}
	smc_class = class
	if !class.enabled {
		return
	}
	mut wired := false
	$if applesmc_selftest ? {
		wired = selftest_shmem(dev.state)
	} $else {
		address := smccore.vinix_smc_shmem_address(dev.state)
		if address != 0 {
			class.shmem = memory.map_mmio(address, u64(shmem_bytes))
			wired = class.shmem != 0 && smccore.vinix_smc_set_shmem(dev.state, shmem_io) == 0
		}
	}
	if !wired {
		class.enabled = false
		print('apple-smc: no way into the shared memory; power supplies, sensors and fans left out\n')
		return
	}
	failure := smccore.discover(dev.state, mut class.machine, class.no_sensors, class.no_limit)
	if failure != 0 {
		// The channel is gone, and the device nodes with it: the thread will
		// say so. vinix.apple_smc=legacy starts without any of this.
		class.enabled = false
		C.kprintf(c'apple-smc: asking for keys failed: %s\n', smccore.vinix_smc_error(failure))
		return
	}
	mut flags := u32(0)
	mut voltage := i32(0)
	mut current := i32(0)
	mut watts := i32(0)
	if capacity != smccore.vinix_smc_no_key
		&& smccore.vinix_smc_refresh_power(dev.state, &flags, &voltage, &current, &watts) < 0 {
		flags = 0
	}
	first := class.pass(dev.state, capacity, flags, voltage, current)
	if first != 0 {
		C.kprintf(c'apple-smc: the first reading failed: %s\n', smccore.vinix_smc_error(first))
	}
}

fn battery_text(destination &u8, source string) int {
	for i in 0 .. source.len {
		unsafe {
			destination[i] = source[i]
		}
	}
	return source.len
}

// `count` bytes of the battery's own text into a reading's, which is as long.
fn battery_bytes(destination &u8, source &u8, count int) int {
	if count < 0 || count > psupply.text_bytes || count > smccore.text_bytes {
		return 0
	}
	for i in 0 .. count {
		unsafe {
			destination[i] = source[i]
		}
	}
	return count
}

// Put the driver on the device list and hand what was found to the classes.
// Called from start() once the device nodes are made, still before the
// thread. `capacity_key` says the SMC has the percentage the nodes show.
fn class_register(capacity_key bool) {
	mut class := smc_class
	mut driver := devcore.register_driver(devcore.Driver{
		name:    'macsmc'
		bus:     .platform
		suspend: smc_suspend
		resume:  smc_resume
	}) or { return }
	mut device := devcore.new_device(.platform, 'apple-smc')
	device.compatible = if class.simulated { 'vinix,simulated-smc' } else { 'apple,t8103-smc' }
	if devcore.add(mut device) {
		devcore.claim(mut device, mut driver)
		class.device = device
	} else {
		unsafe {
			device.name.free()
			free(device)
		}
	}
	if !class.enabled {
		publish_status()
		return
	}
	machine := &class.machine
	// A battery is one the nodes show a percentage of and that says what it
	// holds when full: without the second a program could not tell an empty
	// battery from an unread one, and the percentage alone is in /dev.
	if capacity_key && machine.slots[smccore.slot_b0fc].present {
		class.has_battery = true
		mut supply := psupply.Supply{
			name:    'macsmc-battery'
			kind:    .battery
			read:    battery_read
			context: voidptr(class)
		}
		if machine.slots[smccore.slot_chwa].present {
			supply.set_charge_limit = battery_set_limit
		}
		if registered := psupply.register(supply) {
			class.battery = registered
		}
	}
	if machine.slots[smccore.slot_chis].present {
		charger := psupply.Supply{
			name:    'macsmc-ac'
			kind:    .mains
			read:    charger_read
			context: voidptr(class)
		}
		if registered := psupply.register(charger) {
			class.charger = registered
		}
	}
	if machine.sensor_count > 0 {
		// The zone's own temperature is the first found; the rest, and the
		// fans, are its other sensors. The context of each is its number.
		mut sensors := [smccore.max_sensors]thermal.Sensor{}
		for i in 1 .. machine.sensor_count {
			sensors[i - 1] = thermal.Sensor{
				label:   smccore.sensor_label(machine.sensors[i].known)
				read:    temperature_read
				context: voidptr(u64(i))
			}
		}
		mut fans := [smccore.max_fans]thermal.Fan{}
		for i in 0 .. machine.fan_count {
			fans[i] = thermal.Fan{
				label:       fan_label(machine.fans[i].number, machine.fan_count)
				read_rpm:    fan_read
				context:     voidptr(u64(i))
				has_minimum: machine.fans[i].has_minimum
				minimum:     machine.fans[i].minimum
				has_maximum: machine.fans[i].has_maximum
				maximum:     machine.fans[i].maximum
			}
		}
		mut zone := thermal.Zone{
			name:         'macsmc'
			hwmon_name:   'macsmc_hwmon'
			label:        smccore.sensor_label(machine.sensors[0].known)
			read:         temperature_read
			context:      unsafe { nil }
			sensor_count: machine.sensor_count - 1
			fan_count:    machine.fan_count
		}
		if zone.sensor_count > 0 {
			zone.sensors = unsafe { &sensors[0] }
		}
		if zone.fan_count > 0 {
			zone.fans = unsafe { &fans[0] }
		}
		class.zone = thermal.register_zone(zone)
	}
	publish_status()
	limit := if machine.slots[smccore.slot_chwa].present { c'CHWA' } else { c'none' }
	C.kprintf(c'apple-smc: battery %s, charger %s, %lld temperatures, %lld fans, charge limit %s; %lld of %lld keys\n',
		yes_no(class.battery != unsafe { nil }), yes_no(class.charger != unsafe { nil }),
		i64(machine.sensor_count), i64(machine.fan_count), limit, i64(machine.found), i64(machine.asked))
}

fn yes_no(yes bool) &char {
	return if yes { c'yes' } else { c'no' }
}

// Linux's labels: "Fan" where there is one, "Fan 1" and "Fan 2" where two.
fn fan_label(number int, count int) string {
	if count == 1 {
		return 'Fan'
	}
	return match number {
		0 { 'Fan 1' }
		1 { 'Fan 2' }
		2 { 'Fan 3' }
		else { 'Fan 4' }
	}
}

// ── The thread's side ───────────────────────────────────────────────────────

// Read what is due, weigh it and publish it. 0, or why the channel was given
// up. The thread's, and class_probe()'s before there is a thread.
fn (mut class Class) pass(state voidptr, capacity i32, flags u32, voltage i32, current i32) i32 {
	now := C.vinix_smc_counter()
	failure := smccore.sample(state, &class.machine, mut class.raw)
	if failure != 0 {
		return failure
	}
	legacy := smccore.Legacy{
		percent:     capacity
		power_flags: flags
		voltage_mv:  voltage
		current_ma:  current
	}
	supply := smccore.judge(&class.machine, &class.raw, legacy, mut class.filter)
	// Whether anything the power supply class acts on has moved: it looks
	// again by itself only every thirty seconds.
	moved := supply.charge != class.supply.charge || supply.percent != class.supply.percent
		|| supply.critical != class.supply.critical
		|| supply.charger_online != class.supply.charger_online
		|| supply.charger_known != class.supply.charger_known || supply.limit != class.supply.limit
	writes := smccore.vinix_smc_key_writes(state)
	class.l.acquire()
	class.supply = supply
	for i in 0 .. smccore.max_sensors {
		class.sensor_have[i] = class.raw.sensor_have[i]
		class.sensor_value[i] = class.raw.sensor_millis[i]
	}
	for i in 0 .. smccore.max_fans {
		class.fan_have[i] = class.raw.fan_have[i]
		class.fan_value[i] = class.raw.fan_rpm[i]
	}
	class.counters.passes = class.raw.passes
	class.counters.key_errors = class.raw.key_errors
	class.counters.implausible = class.raw.implausible + class.filter.implausible
	class.counters.jumps = class.filter.jumps
	class.counters.unconfirmed = class.filter.unconfirmed
	class.counters.key_writes = writes
	class.published = true
	class.published_at = now
	class.l.release()
	class.passed = true
	class.passed_at = now
	if moved {
		class.tell_supplies()
	}
	return 0
}

fn (mut class Class) tell_supplies() {
	if class.battery != unsafe { nil } {
		mut battery := class.battery
		psupply.changed(mut battery)
	}
	if class.charger != unsafe { nil } {
		mut charger := class.charger
		psupply.changed(mut charger)
	}
}

// Whether the thread is to leave the SMC alone on this turn.
fn (mut class Class) stay_parked() bool {
	if katomic.load(&class.park) != 0 {
		katomic.store(mut &class.parked, u32(1))
		return true
	}
	return false
}

// One turn of the thread, after the device nodes' own samples: a charge
// limit somebody asked for, and once a second a pass. 0, or why the channel
// was given up.
fn (mut class Class) round(state voidptr, capacity i32, flags u32, voltage i32, current i32) i32 {
	back := katomic.load(&class.parked) != 0
	mut failure := i32(0)
	if class.enabled {
		if katomic.cas(mut &class.limit_state, limit_asked, limit_taken) {
			result := smccore.set_limit(state, &class.machine, mut class.raw, class.limit_wanted)
			failure = smccore.vinix_smc_failure(state)
			class.limit_result = result
			if failure == 0 {
				// What the key reads now is known: no need to wait a pass.
				mut limit := u64(0)
				if class.raw.have[smccore.slot_chwa] {
					limit = if class.raw.value[smccore.slot_chwa] != 0 {
						smccore.chwa_limit
					} else {
						u64(100)
					}
				}
				writes := smccore.vinix_smc_key_writes(state)
				class.l.acquire()
				class.supply.limit = limit
				class.counters.key_writes = writes
				class.l.release()
			}
			katomic.store(mut &class.limit_state, limit_done)
		}
		if failure == 0 {
			now := C.vinix_smc_counter()
			if back {
				// The machine was away: the first reading stands as it is.
				class.filter.restart()
			}
			if back || !class.passed || now - class.passed_at >= class.frequency {
				failure = class.pass(state, capacity, flags, voltage, current)
			}
		}
	}
	if failure == 0 {
		// Only now is what is published fresh again.
		katomic.store(mut &class.parked, u32(0))
		katomic.inc(mut &class.rounds)
	}
	return failure
}

// The thread is ending: the SMC stopped answering.
fn (mut class Class) gone() {
	failure := smccore.vinix_smc_failure(battery_device.state)
	class.l.acquire()
	class.failed = true
	class.failure = failure
	class.l.release()
	katomic.store(mut &class.ended, u32(1))
	class.tell_supplies()
}

// ── Everybody else's side ───────────────────────────────────────────────────

// Whether what was published at `at` may be given out. While the machine's
// devices are suspended it may, whatever its age: see the top of this file.
fn (class &Class) usable(published bool, failed bool, at u64) bool {
	if !published || failed {
		return false
	}
	if katomic.load(&class.parked) != 0 {
		return true
	}
	return C.vinix_smc_counter() - at < stale_seconds * class.frequency
}

fn battery_read(context voidptr, mut reading psupply.Reading) bool {
	mut class := unsafe { &Class(context) }
	class.l.acquire()
	supply := class.supply
	published := class.published
	failed := class.failed
	at := class.published_at
	class.l.release()
	machine := &class.machine
	// What the battery is does not go stale.
	reading.present = true
	reading.in_charge = true
	reading.technology_len = battery_text(&reading.technology[0], 'Unknown')
	reading.model_len = battery_bytes(&reading.model[0], &machine.model[0], machine.model_len)
	reading.serial_len = battery_bytes(&reading.serial[0], &machine.serial[0], machine.serial_len)
	reading.design = supply.design
	reading.design_voltage_uv = supply.minimum
	// Nor does a setting: it is the SMC's until somebody changes it.
	reading.charge_limit = supply.limit
	if !class.usable(published, failed, at) {
		// Not known: no state, and no figure that was true a while ago.
		reading.status = .unknown
		return true
	}
	reading.status = match supply.charge {
		.unknown { psupply.Status.unknown }
		.charging { psupply.Status.charging }
		.discharging { psupply.Status.discharging }
		.not_charging { psupply.Status.not_charging }
		.full { psupply.Status.full }
	}
	reading.amount = supply.remaining
	reading.full = supply.full
	reading.rate = supply.current
	reading.voltage_uv = supply.voltage
	reading.cycles = supply.cycles
	reading.critical = supply.critical
	reading.firmware_to_empty_s = supply.to_empty
	reading.firmware_to_full_s = supply.to_full
	if supply.percent >= 0 {
		reading.has_percent = true
		reading.percent = supply.percent
	}
	return true
}

fn charger_read(context voidptr, mut reading psupply.Reading) bool {
	mut class := unsafe { &Class(context) }
	class.l.acquire()
	known := class.supply.charger_known
	online := class.supply.charger_online
	published := class.published
	failed := class.failed
	at := class.published_at
	class.l.release()
	if !class.usable(published, failed, at) {
		// Not known: not claimed to be supplying anything.
		reading.present = false
		reading.online = false
		return true
	}
	if !known {
		// This once the key was not read: what was last read stands.
		return false
	}
	reading.present = true
	reading.online = online
	return true
}

// errno for what the thread said of a charge limit.
fn limit_errno(result i32) u64 {
	return match result {
		0 { u64(0) }
		smccore.vinix_smc_argument { u64(errno.einval) }
		smccore.vinix_smc_no_key { u64(errno.enodev) }
		else { u64(errno.eio) }
	}
}

// The power supply class's set_charge_limit: hand the write to the thread
// and wait for what came of it.
fn battery_set_limit(context voidptr, percent u64) u64 {
	mut class := unsafe { &Class(context) }
	if !smccore.limit_acceptable(percent) {
		return errno.einval
	}
	if katomic.load(&class.ended) != 0 {
		return errno.eio
	}
	if !katomic.cas(mut &class.limit_busy, u32(0), u32(1)) {
		return errno.ebusy
	}
	class.limit_wanted = percent
	katomic.store(mut &class.limit_state, limit_asked)
	mut waited := u64(0)
	for katomic.load(&class.limit_state) != limit_done && waited < limit_wait_ms
		&& katomic.load(&class.ended) == 0 {
		devcore.sleep_ms(5)
		waited += 5
	}
	if katomic.load(&class.limit_state) != limit_done
		&& katomic.cas(mut &class.limit_state, limit_asked, limit_idle) {
		// Never taken up: the thread is parked for a sleep, or has ended.
		katomic.store(mut &class.limit_busy, u32(0))
		return errno.eio
	}
	// Taken up. An exchange ends within half a second, answered or not.
	waited = 0
	for katomic.load(&class.limit_state) != limit_done && waited < limit_wait_ms {
		devcore.sleep_ms(5)
		waited += 5
	}
	if katomic.load(&class.limit_state) != limit_done {
		// The thread is stuck inside the write. Nobody else is let in: the
		// answer it may yet give must not be taken for theirs.
		return errno.eio
	}
	result := class.limit_result
	katomic.store(mut &class.limit_state, limit_idle)
	katomic.store(mut &class.limit_busy, u32(0))
	return limit_errno(result)
}

// The thermal class's read of a temperature; `context` is its number.
fn temperature_read(context voidptr) ?i64 {
	mut class := smc_class
	index := int(u64(context))
	if class == unsafe { nil } || index < 0 || index >= smccore.max_sensors {
		return none
	}
	class.l.acquire()
	have := class.sensor_have[index]
	value := class.sensor_value[index]
	published := class.published
	failed := class.failed
	at := class.published_at
	class.l.release()
	if !have || !class.usable(published, failed, at) {
		return none
	}
	return value
}

fn fan_read(context voidptr) ?u64 {
	mut class := smc_class
	index := int(u64(context))
	if class == unsafe { nil } || index < 0 || index >= smccore.max_fans {
		return none
	}
	class.l.acquire()
	have := class.fan_have[index]
	value := class.fan_value[index]
	published := class.published
	failed := class.failed
	at := class.published_at
	class.l.release()
	if !have || !class.usable(published, failed, at) {
		return none
	}
	return value
}

// ── Sleep ───────────────────────────────────────────────────────────────────

fn smc_suspend(mut device devcore.Device) bool {
	mut class := smc_class
	katomic.store(mut &class.park, u32(1))
	mut waited := u64(0)
	for katomic.load(&class.parked) == 0 && katomic.load(&class.ended) == 0 {
		if waited >= park_wait_ms {
			// It is in the middle of a pass against an SMC that answers
			// slowly, and will stop when the pass is over. A sleep is not
			// refused for that.
			katomic.inc(mut &class.late_parks)
			break
		}
		devcore.sleep_ms(10)
		waited += 10
	}
	if katomic.load(&class.parked) != 0 {
		katomic.inc(mut &class.parks)
	}
	return true
}

fn smc_resume(mut device devcore.Device) bool {
	mut class := smc_class
	before := katomic.load(&class.rounds)
	katomic.store(mut &class.park, u32(0))
	// Programs thaw after devices are back: let them find a reading.
	mut waited := u64(0)
	for katomic.load(&class.rounds) == before && katomic.load(&class.ended) == 0
		&& waited < resume_wait_ms {
		devcore.sleep_ms(10)
		waited += 10
	}
	return true
}

// ── /sys/devices/platform/apple-smc/smc ─────────────────────────────────────

fn status_path(name string) string {
	mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *text = lib.new_text(96) }
	text.add(smc_class.device.sysfs_path)
	text.add('/smc/')
	text.add(name)
	return text.str()
}

fn publish_status() {
	class := smc_class
	if class.device == unsafe { nil } || class.device.sysfs_path.len == 0 {
		return
	}
	status := status_path('status')
	fs.sysfs_attribute(status, 0o444, show_status, unsafe { nil }, unsafe { nil })
	unsafe { status.free() }
	keys := status_path('keys')
	fs.sysfs_attribute(keys, 0o444, show_keys, unsafe { nil }, unsafe { nil })
	unsafe { keys.free() }
	$if applesmc_selftest ? {
		selftest_publish()
	}
}

// A NUL-terminated text of the core's, a byte at a time: nothing is made.
fn add_c_text(mut text lib.Text, words &char) {
	mut at := unsafe { &u8(words) }
	for unsafe { *at } != 0 {
		text.add_byte(unsafe { *at })
		unsafe {
			at++
		}
	}
}

fn status_line(mut text lib.Text, name string, value u64) {
	text.add(name)
	text.add_byte(` `)
	text.add_unsigned(value)
	text.add_byte(`\n`)
}

fn flag(yes bool) u64 {
	return if yes { u64(1) } else { u64(0) }
}

// One `name value` line for each thing worth knowing about the driver.
fn show_status(_ voidptr, mut text lib.Text) {
	mut class := smc_class
	class.l.acquire()
	counters := class.counters
	published := class.published
	failed := class.failed
	failure := class.failure
	at := class.published_at
	class.l.release()
	text.add('transport ')
	if failed {
		add_c_text(mut text, smccore.vinix_smc_error(failure))
	} else {
		text.add('ok')
	}
	text.add_byte(`\n`)
	status_line(mut text, 'simulated', flag(class.simulated))
	status_line(mut text, 'classes', flag(class.enabled))
	status_line(mut text, 'battery', flag(class.battery != unsafe { nil }))
	status_line(mut text, 'charger', flag(class.charger != unsafe { nil }))
	status_line(mut text, 'temperatures', u64(class.machine.sensor_count))
	status_line(mut text, 'fans', u64(class.machine.fan_count))
	status_line(mut text, 'charge_limit', flag(class.machine.slots[smccore.slot_chwa].present))
	status_line(mut text, 'keys_asked', u64(class.machine.asked))
	status_line(mut text, 'keys_found', u64(class.machine.found))
	status_line(mut text, 'keys_odd_sized', u64(class.machine.odd_sized))
	status_line(mut text, 'fresh', flag(class.usable(published, failed, at)))
	status_line(mut text, 'passes', counters.passes)
	status_line(mut text, 'rounds', katomic.load(&class.rounds))
	status_line(mut text, 'key_errors', counters.key_errors)
	status_line(mut text, 'key_writes', counters.key_writes)
	status_line(mut text, 'implausible', counters.implausible)
	status_line(mut text, 'percent_jumps', counters.jumps)
	status_line(mut text, 'critical_unconfirmed', counters.unconfirmed)
	status_line(mut text, 'parked', u64(katomic.load(&class.parked)))
	status_line(mut text, 'parks', katomic.load(&class.parks))
	status_line(mut text, 'late_parks', katomic.load(&class.late_parks))
}

fn add_code(mut text lib.Text, code u32) {
	mut characters := [4]u8{}
	smccore.key_text(code, &characters[0])
	for i in 0 .. 4 {
		text.add_byte(characters[i])
	}
}

fn key_line(mut text lib.Text, key u32, kind u32, size u8, flags u8) {
	add_code(mut text, key)
	text.add_byte(` `)
	add_code(mut text, kind)
	text.add_byte(` `)
	text.add_unsigned(u64(size))
	text.add(' 0x')
	text.add_radix(u64(flags), 16, 2)
	text.add_byte(`\n`)
}

// The keys taken on, as the SMC described them: key, type, size, attributes.
// What a machine never tried before is checked against.
fn show_keys(_ voidptr, mut text lib.Text) {
	class := smc_class
	machine := &class.machine
	for slot in 0 .. smccore.slot_count {
		info := &machine.slots[slot]
		if info.present {
			key_line(mut text, smccore.slot_key(slot), info.kind, info.size, info.flags)
		}
	}
	for i in 0 .. machine.sensor_count {
		sensor := &machine.sensors[i]
		size := if sensor.kind == smccore.type_ioft { u8(8) } else { u8(4) }
		key_line(mut text, sensor.key, sensor.kind, size, smccore.flag_readable)
	}
	for i in 0 .. machine.fan_count {
		key_line(mut text, smccore.fan_key(machine.fans[i].number, `A`, `c`), smccore.type_flt,
			4, smccore.flag_readable)
	}
}
