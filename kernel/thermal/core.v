// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Thermal zones: the temperatures the machine reports, and what is done when
// one of them is too high.
//
// A driver that can read a temperature registers a zone: a name, a function
// that reads millidegrees Celsius, and trip points. One kernel thread reads
// every zone -- once a second, four times a second while any of them is
// holding the CPUs back, and not at all while there are none -- and puts each
// reading through the policy in policy.v. What comes out is one number, the
// deepest step any zone asks for, which is handed to the frequency drivers
// through cpufreq.set_thermal_limit(), and the two things that are not a
// number: a line in the log at a hot trip, and the critical handler at a
// critical one.
//
// A zone may carry more temperatures than the one it is steered by, and fans:
// a package and its cores. Those are only shown, in /sys/class/hwmon.
//
// Lifetimes. A zone's record is made by register_zone() and freed by
// unregister_zone(), which first removes the zone's files -- sysfs does not
// return while one of them is being read -- and then waits for the polling
// thread to be done with the zone. So a driver may free what its `context`
// points at once unregister_zone() has returned, and must not call it from
// its own read function or from a file of the zone.
//
// Locking. thermal_lock guards the table and each zone's state, and is never
// held across a sensor read or a call into sysfs. Registering, unregistering
// and publishing happen one at a time, behind the gate.
@[has_globals]
module thermal

import cpufreq
import devcore
import event
import event.eventstruct
import katomic
import klock
import memory
import sched

// Zones the machine may have at once.
pub const max_zones = 16

const slow_period_ms = u64(1000)
const fast_period_ms = u64(250)

// Reads a temperature in millidegrees Celsius. None when the sensor did not
// answer: a failed reading is not a temperature and must not be made one.
pub type ReadTemperature = fn (context voidptr) ?i64

// Whether the hardware itself says the temperature is critical.
pub type ReadAlarm = fn (context voidptr) ?bool

pub type ReadRpm = fn (context voidptr) ?u64

// Run a fan at `percent` of its speed. False if it would not.
pub type SetPercent = fn (context voidptr, percent u32) bool

// Called when `zone` reaches its critical trip.
pub type CriticalHandler = fn (zone string, millicelsius i64)

// One more temperature of a zone, for the hwmon view: a core of a package.
pub struct Sensor {
pub mut:
	label   string
	read    ReadTemperature = unsafe { nil }
	alarm   ReadAlarm       = unsafe { nil }
	context voidptr
	// tempN_max and tempN_crit, where the sensor has them.
	has_maximum  bool
	maximum      i64
	has_critical bool
	critical     i64
}

// A fan of a zone, for the hwmon view.
pub struct Fan {
pub mut:
	label       string
	read_rpm    ReadRpm    = unsafe { nil }
	set_percent SetPercent = unsafe { nil }
	context     voidptr
	// fanN_min and fanN_max, in revolutions a minute, where the fan's maker
	// says how slow and how fast it runs.
	has_minimum bool
	minimum     u64
	has_maximum bool
	maximum     u64
mut:
	// What pwmN was last set to, for reading it back.
	percent     u32
	percent_set bool
}

// What a driver registers. Everything is copied: the strings and the two
// arrays need only last for the call.
pub struct Zone {
pub mut:
	// The zone's `type`, as Linux names it: x86_pkg_temp, acpitz.
	name string
	// The hwmon device's `name`, when it is not the zone's: coretemp.
	hwmon_name string
	// temp1_label, if the zone's own temperature has one.
	label   string
	read    ReadTemperature = unsafe { nil }
	alarm   ReadAlarm       = unsafe { nil }
	context voidptr
	trips      [max_trips]Trip
	trip_count int
	// temp2 onwards.
	sensors      &Sensor = unsafe { nil }
	sensor_count int
	fans      &Fan = unsafe { nil }
	fan_count int
}

// Add a trip point. False when the zone has max_trips already.
pub fn (mut zone Zone) add_trip(kind TripKind, temperature i64, hysteresis i64) bool {
	if zone.trip_count < 0 || zone.trip_count >= max_trips {
		return false
	}
	zone.trips[zone.trip_count] = Trip{
		kind:        kind
		temperature: temperature
		hysteresis:  hysteresis
	}
	zone.trip_count++
	return true
}

struct ZoneRecord {
mut:
	handle u64
	slot   int
	// The driver's description, with strings and arrays of the record's own.
	zone   Zone
	limits Thresholds
	state  ZoneState
	// `mode`: whether the zone is read at all.
	enabled bool
	// unregister_zone() has begun: the poller starts nothing new on it.
	removing  bool
	published bool
	// The poller is reading it.
	busy u32
	// Every reading that failed, for read_failures.
	failed_reads u64
}

__global (
	thermal_lock        klock.Lock
	thermal_zones       [max_zones]&ZoneRecord
	thermal_zone_count  u32
	thermal_next_handle u64
	// One registration, removal or publication at a time.
	thermal_gate_held u32
	// /sys is mounted and the class directories are there.
	thermal_published      bool
	thermal_poller_started u32
	thermal_wake           eventstruct.Event
	// The deepest step any zone asks for: cooling_device0/cur_state.
	thermal_cooling_state u32
	// Set once a zone has asked for a step, so that a machine whose zones
	// never do leaves the limit to whoever else may set it.
	thermal_limit_set bool
	thermal_critical_handler voidptr
	// Times the critical handler was called, and passes of the poller.
	thermal_critical_count u64
	thermal_poll_count     u64
)

// Registration sleeps -- in sysfs, and waiting for the poller -- so what
// keeps two of them apart cannot be a spinlock.
fn gate_enter() {
	for !katomic.cas(mut &thermal_gate_held, u32(0), u32(1)) {
		devcore.sleep_ms(1)
	}
}

fn gate_leave() {
	katomic.store(mut &thermal_gate_held, u32(0))
}

fn free_record(record &ZoneRecord) {
	mut zone := unsafe { &record.zone }
	unsafe {
		for i in 0 .. zone.sensor_count {
			zone.sensors[i].label.free()
		}
		for i in 0 .. zone.fan_count {
			zone.fans[i].label.free()
		}
		memory.free(voidptr(zone.sensors))
		memory.free(voidptr(zone.fans))
		zone.name.free()
		zone.hwmon_name.free()
		zone.label.free()
		free(record)
	}
}

// Register a zone. The handle is for unregister_zone(); 0 when the zone is not
// one -- no name, no read function, too many trips -- or the table is full.
pub fn register_zone(zone Zone) u64 {
	if zone.read == unsafe { nil } || zone.name.len == 0 || zone.trip_count < 0
		|| zone.trip_count > max_trips || zone.sensor_count < 0 || zone.fan_count < 0 {
		return 0
	}
	if (zone.sensor_count != 0 && zone.sensors == unsafe { nil })
		|| (zone.fan_count != 0 && zone.fans == unsafe { nil }) {
		return 0
	}
	gate_enter()
	defer {
		gate_leave()
	}
	// Freed by unregister_zone(), or below when the table is full.
	mut record := &ZoneRecord{} @[freed]
	record.zone = zone
	record.zone.name = zone.name.clone()
	record.zone.hwmon_name = if zone.hwmon_name.len != 0 {
		zone.hwmon_name.clone()
	} else {
		zone.name.clone()
	}
	record.zone.label = zone.label.clone()
	record.zone.sensors = unsafe { nil }
	record.zone.fans = unsafe { nil }
	if zone.sensor_count != 0 {
		size := u64(zone.sensor_count) * sizeof(Sensor)
		record.zone.sensors = unsafe { &Sensor(memory.malloc(size)) }
		unsafe {
			C.memcpy(voidptr(record.zone.sensors), voidptr(zone.sensors), size)
			for i in 0 .. zone.sensor_count {
				record.zone.sensors[i].label = zone.sensors[i].label.clone()
			}
		}
	}
	if zone.fan_count != 0 {
		size := u64(zone.fan_count) * sizeof(Fan)
		record.zone.fans = unsafe { &Fan(memory.malloc(size)) }
		unsafe {
			C.memcpy(voidptr(record.zone.fans), voidptr(zone.fans), size)
			for i in 0 .. zone.fan_count {
				record.zone.fans[i].label = zone.fans[i].label.clone()
				record.zone.fans[i].percent = 0
				record.zone.fans[i].percent_set = false
			}
		}
	}
	record.limits = thresholds_of(unsafe { &record.zone.trips[0] }, zone.trip_count)
	record.enabled = true

	thermal_lock.acquire()
	mut slot := -1
	for i in 0 .. max_zones {
		if thermal_zones[i] == unsafe { nil } {
			slot = i
			break
		}
	}
	if slot < 0 {
		thermal_lock.release()
		C.kprintf(c'thermal: zone table full, %.*s not registered\n', i32(zone.name.len),
			zone.name.str)
		free_record(record)
		return 0
	}
	thermal_next_handle++
	handle := thermal_next_handle
	record.handle = handle
	record.slot = slot
	thermal_zones[slot] = record
	katomic.inc(mut &thermal_zone_count)
	thermal_lock.release()

	if thermal_published {
		publish_zone(mut record)
		start_poller()
	}
	// Nothing to leave pending for a poller that is not waiting: it looks at
	// the table before it waits, from the generation it read before that.
	event.trigger(mut thermal_wake, true)
	return handle
}

// Take a zone away again. It returns once nothing is reading the zone: see
// the top of this file. False if `handle` is not a registered zone's.
pub fn unregister_zone(handle u64) bool {
	if handle == 0 {
		return false
	}
	gate_enter()
	defer {
		gate_leave()
	}
	thermal_lock.acquire()
	mut record := &ZoneRecord(unsafe { nil })
	for i in 0 .. max_zones {
		if thermal_zones[i] != unsafe { nil } && thermal_zones[i].handle == handle {
			record = thermal_zones[i]
			break
		}
	}
	if record == unsafe { nil } {
		thermal_lock.release()
		return false
	}
	record.removing = true
	thermal_lock.release()

	if record.published {
		unpublish_zone(mut record)
	}
	for katomic.load(&record.busy) != 0 {
		devcore.sleep_ms(1)
	}

	thermal_lock.acquire()
	thermal_zones[record.slot] = unsafe { nil }
	katomic.dec(mut &thermal_zone_count)
	// What the zone held the limit down by goes with it.
	update_limit()
	thermal_lock.release()
	free_record(record)
	return true
}

// What is called when a zone reaches its critical trip: once for each time it
// does, however long it stays there. Nil for the default, which can only say
// so; power management installs the one that switches the machine off.
//
// The handler runs on the polling thread, with the zone still being read: it
// must not unregister the zone, and no zone is read again until it returns,
// so one that has much to do hands the work to a thread of its own. `zone`
// is the zone's own name and is only good until the handler returns: one
// that keeps it copies it.
pub fn set_critical_handler(handler CriticalHandler) {
	thermal_critical_handler = voidptr(handler)
}

fn raise_critical(zone string, millicelsius i64) {
	katomic.inc(mut &thermal_critical_count)
	// Read once: the handler may be changed while this runs.
	installed := thermal_critical_handler
	if installed == unsafe { nil } {
		C.kprintf(c'thermal: CRITICAL: %.*s is at %lld mC and nothing is installed to switch the machine off\n',
			i32(zone.len), zone.str, millicelsius)
		return
	}
	handler := unsafe { CriticalHandler(installed) }
	handler(zone, millicelsius)
}

// The deepest step any zone holds, handed to the frequency drivers. A zone
// that is switched off keeps what it held: nothing says it has cooled.
// thermal_lock is held.
fn update_limit() {
	mut deepest := u32(0)
	for i in 0 .. max_zones {
		if thermal_zones[i] != unsafe { nil } && thermal_zones[i].state.steps > deepest {
			deepest = thermal_zones[i].state.steps
		}
	}
	thermal_cooling_state = deepest
	if deepest != 0 {
		thermal_limit_set = true
	}
	if thermal_limit_set {
		cpufreq.set_thermal_limit(limit_of_state(deepest))
	}
}

// Read every zone once. Whether any of them wants reading again soon.
fn poll_pass() bool {
	mut fast := false
	for slot in 0 .. max_zones {
		thermal_lock.acquire()
		mut record := thermal_zones[slot]
		if record == unsafe { nil } || record.removing || !record.enabled || record.state.faulted {
			thermal_lock.release()
			continue
		}
		katomic.store(mut &record.busy, u32(1))
		thermal_lock.release()

		mut temperature := i64(0)
		mut good := false
		if value := record.zone.read(record.zone.context) {
			if value > absolute_zero {
				temperature = value
				good = true
			}
		}

		thermal_lock.acquire()
		verdict := if good {
			judge_reading(record.state, record.limits, temperature)
		} else {
			judge_failure(record.state)
		}
		record.state = verdict.state
		if !good {
			record.failed_reads++
		}
		update_limit()
		thermal_lock.release()

		name := record.zone.name
		if verdict.log_hot {
			C.kprintf(c'thermal: %.*s is hot at %lld mC: CPUs held to %u%%\n', i32(name.len),
				name.str, temperature, limit_of_state(verdict.state.steps))
		}
		if verdict.fault {
			C.kprintf(c'thermal: %.*s failed %u readings in a row and is disabled\n',
				i32(name.len), name.str, verdict.state.failures)
		}
		if verdict.fire_critical {
			raise_critical(name, temperature)
		}
		if wants_fast_polling(verdict.state) {
			fast = true
		}
		katomic.store(mut &record.busy, u32(0))
	}
	return fast
}

fn poller() {
	for {
		generation := event.generation(mut thermal_wake)
		if katomic.load(&thermal_zone_count) == 0 && !platform_polls() {
			event.await_one_from_generation(mut thermal_wake, true, generation) or {}
			continue
		}
		fast := poll_pass()
		platform_poll()
		katomic.inc(mut &thermal_poll_count)
		devcore.sleep_ms(if fast { fast_period_ms } else { slow_period_ms })
	}
}

// The polling thread is made when there is first something to poll, so a
// machine with no sensors has no thread.
fn start_poller() {
	if katomic.load(&thermal_zone_count) == 0 && !platform_polls() {
		return
	}
	if !katomic.cas(mut &thermal_poller_started, u32(0), u32(1)) {
		return
	}
	sched.new_kernel_thread(voidptr(poller), unsafe { nil }, true)
}

// Publish what there is, look for the machine's own sensors, and from now on
// publish every zone as it is registered. Called once /sys is mounted.
pub fn publish() {
	gate_enter()
	if thermal_published {
		gate_leave()
		return
	}
	publish_class()
	for i in 0 .. max_zones {
		mut record := thermal_zones[i]
		if record != unsafe { nil } {
			publish_zone(mut record)
		}
	}
	thermal_published = true
	gate_leave()

	platform_start()
	$if thermal_selftest ? {
		selftest_start()
	}
	start_poller()
}
