// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The temperatures and fans a PC's firmware describes.
//
// Firmware puts the machine's own idea of its heat in the ACPI namespace as
// thermal zones. A zone has a temperature (_TMP, in tenths of a kelvin) and
// the temperatures at which things are to be done about it:
//
//	_CRT   the machine must be switched off;
//	_HOT   it is close to that;
//	_PSV   it should be slowed down;
//	_ACx   a fan should run: _AC0 is the hottest and the fans of _AL0 the
//	       strongest answer, _AC1 the next below, and so on down.
//
// The first three become trip points of a zone of the thermal module, which
// reads the zone, holds the CPUs back and switches the machine off as it
// does for every other zone. The fans are driven here, each time the zone is
// read: a fan runs for the hottest of the _ACx at or below the temperature
// that lists it -- at full speed for _AC0, at less for each one below, off
// when the temperature has fallen two degrees under the last of them.
//
// A fan is a device with the hardware ID PNP0C0B, and comes in two kinds.
// One takes a level (_FSL) and says what it is doing (_FST): the level is a
// percentage where _FIF says any value will do, and otherwise one of the
// values _FPS lists. The other can only be on or off, through its power
// resources (_PR0) and its _PS0 and _PS3. Both appear among the zone's fans
// in /sys/class/hwmon, the first kind with its speed, and each can be set by
// hand through pwmN until the zone next changes its mind.
//
//	/sys/class/thermal/acpi_fans   every fan, how it is driven, and what it
//	                               was last told
//	/sys/class/thermal/acpi_zones  every zone: its critical trip, and how
//	                               often a reading failed, could not have
//	                               been a temperature, or was critical and
//	                               not borne out by a second look
//
// Firmware's figures are not all believed. A reading at or below absolute
// zero, or of 200 degrees or more, is a failed reading and not a temperature;
// a trip at or below freezing or at 200 degrees or more is not a trip; and a
// reading at or past the critical trip is taken a second time, a twentieth of
// a second later, and the cooler of the two is the one acted on -- what
// follows a critical reading is the machine switching itself off, and one
// wild figure from a controller that was busy must not be enough for that.
// `vinix.acpi_thermal=nocrt` on the command line takes the zones without
// their critical trips, and `=off` leaves zones and fans alone.
//
// The method names, units and package layouts are the specification's (ACPI
// 6.5, chapter 11); what is done with them follows Linux's drivers
// (drivers/acpi/thermal.c, fan_core.c) where the specification leaves room.
//
// Not done: the zone's own passive cooling constants (_TC1, _TC2, _TSP: the
// thermal module's stepping is used instead), the devices a zone says it
// heats (_TZD), a polling period of the zone's choosing (_TZP), and a power
// resource shared between fans, which is switched for each fan regardless of
// the others.
@[has_globals]
module acpipm

import devcore
import fs
import katomic
import lib
import thermal
import uacpi

const max_thermal_zones = 8
const max_fans = 8
const max_active_trips = 10
const max_listed_fans = 4
const max_fan_levels = 16
const max_fan_resources = 4

// 0 degrees Celsius in tenths of a kelvin, as Linux rounds it.
const kelvin_tenths_at_zero = i64(2732)
// How far under an active trip the temperature falls before its fans stop.
const active_hysteresis = i64(2000)
// How far under the other trips it falls before what they did is undone.
const trip_hysteresis = i64(2000)

// No part of a machine that still answers is this hot: 200 degrees.
const implausible_millis = i64(200_000)
// How long after a critical reading the zone is asked again.
const confirm_ms = u64(50)

// _STA of a fan: there and working.
const fan_present = u64(0x3)

const active_trip_names = ['_AC0', '_AC1', '_AC2', '_AC3', '_AC4', '_AC5', '_AC6', '_AC7', '_AC8',
	'_AC9']!
const active_list_names = ['_AL0', '_AL1', '_AL2', '_AL3', '_AL4', '_AL5', '_AL6', '_AL7', '_AL8',
	'_AL9']!

struct FirmwareFan {
mut:
	node     uacpi.Node
	name     [8]u8
	name_len int
	// Takes a level and reports one.
	has_level bool
	// Any level from 0 to 100 will do.
	fine bool
	// Otherwise the levels it takes, slowest first.
	levels      [max_fan_levels]u64
	level_count int
	// On or off: its own methods, and the power it needs.
	has_states     bool
	resources      [max_fan_resources]uacpi.Node
	resource_count int
	// What it was last told, and whether it has been told anything.
	percent  u32
	told     bool
	failures u64
}

struct ActiveTrip {
mut:
	// Millidegrees Celsius.
	temperature i64
	fans        [max_listed_fans]int
	fan_count   int
	engaged     bool
}

struct FirmwareZone {
mut:
	node     uacpi.Node
	name     [8]u8
	name_len int
	// The critical trip, kept here as well: a reading at or past it is read
	// a second time before it is believed.
	has_critical bool
	critical     i64
	// Readings and trips that could not be a temperature, and critical
	// readings that a second look did not bear out.
	implausible u64
	unconfirmed u64
	// The thermal module's handle for the zone.
	handle       u64
	active       [max_active_trips]ActiveTrip
	active_count int
	failures     u64
}

__global (
	acpipm_fans         [max_fans]FirmwareFan
	acpipm_fan_count    int
	acpipm_zones        [max_thermal_zones]FirmwareZone
	acpipm_zone_count   int
	acpipm_thermal_up   bool
	// One thread at a time decides about the fans; a second one that comes
	// by meanwhile leaves it to the first.
	acpipm_cooling_busy u32
	// `vinix.acpi_thermal=nocrt`: firmware's critical trips are not acted on.
	acpipm_thermal_no_critical bool
)

fn celsius_millis(kelvin_tenths u64) i64 {
	// Firmware's figure is taken as the 32 bits it is: all ones, which a
	// method that could not read its sensor may return, must come out as an
	// absurd temperature and not wrap into a believable one.
	return (i64(kelvin_tenths & 0xffffffff) - kelvin_tenths_at_zero) * 100
}

// Whether a reading can be a temperature of a machine that is running.
fn plausible_reading(millis i64) bool {
	return millis > thermal.absolute_zero && millis < implausible_millis
}

// Whether a trip point is one to act on.
fn plausible_trip(millis i64) bool {
	return millis > 0 && millis < implausible_millis
}

// ── Fans ────────────────────────────────────────────────────────────────────

// The level a fan that takes listed levels is given for a percentage.
fn (fan &FirmwareFan) level_for(percent u32) u64 {
	if fan.level_count == 0 {
		return u64(percent)
	}
	index := (int(percent) * (fan.level_count - 1) + 50) / 100
	return fan.levels[index]
}

// Run the fan at `percent`, 0 being off. False if firmware would not.
fn (mut fan FirmwareFan) drive(percent u32) bool {
	mut ok := true
	if fan.has_level {
		level := if fan.fine { u64(percent) } else { fan.level_for(percent) }
		ok = uacpi.execute_integer(fan.node, '_FSL', level)
	} else if percent > 0 {
		// Power first, then the device.
		for i in 0 .. fan.resource_count {
			ok = uacpi.execute(fan.resources[i], '_ON') && ok
		}
		if fan.has_states {
			ok = uacpi.execute(fan.node, '_PS0') && ok
		}
	} else {
		if fan.has_states {
			ok = uacpi.execute(fan.node, '_PS3') && ok
		}
		for i in 0 .. fan.resource_count {
			ok = uacpi.execute(fan.resources[i], '_OFF') && ok
		}
	}
	if !ok {
		fan.failures++
		return false
	}
	fan.percent = percent
	fan.told = true
	return true
}

// What the hwmon files of a fan call.
fn fan_speed(context voidptr) ?u64 {
	fan := unsafe { &FirmwareFan(context) }
	mut status := uacpi.evaluate_package(fan.node, '_FST') or { return none }
	defer {
		status.release()
	}
	// Revision, level, revolutions a minute; all ones for "not known".
	speed := status.integer(2) or { return none }
	if speed == 0xffffffff {
		return none
	}
	return speed
}

fn fan_set(context voidptr, percent u32) bool {
	mut fan := unsafe { &FirmwareFan(context) }
	return fan.drive(if percent > 100 { u32(100) } else { percent })
}

fn fan_found(_ voidptr, node uacpi.Node) {
	if acpipm_fan_count >= max_fans {
		return
	}
	if status := uacpi.evaluate_integer(node, '_STA') {
		if status & fan_present != fan_present {
			return
		}
	}
	mut fan := &acpipm_fans[acpipm_fan_count]
	fan.node = node
	fan.name_len = uacpi.node_name(node, &fan.name[0], 8)
	fan.has_level = uacpi.has_method(node, '_FSL')
	fan.has_states = uacpi.has_method(node, '_PS0') && uacpi.has_method(node, '_PS3')
	if fan.has_level {
		if mut information := uacpi.evaluate_package(node, '_FIF') {
			fan.fine = (information.integer(1) or { 0 }) != 0
			information.release()
		}
		if mut states := uacpi.evaluate_package(node, '_FPS') {
			// A revision, then one package for each level, whose first
			// element is what _FSL takes for it.
			for i in 1 .. states.len() {
				if fan.level_count >= max_fan_levels {
					break
				}
				state := states.package(i) or { continue }
				control := state.integer(0) or { continue }
				// Kept slowest first, whatever order firmware lists them in.
				mut at := fan.level_count
				for at > 0 && fan.levels[at - 1] > control {
					fan.levels[at] = fan.levels[at - 1]
					at--
				}
				fan.levels[at] = control
				fan.level_count++
			}
			states.release()
		}
	} else if mut power := uacpi.evaluate_package(node, '_PR0') {
		for i in 0 .. power.len() {
			if fan.resource_count >= max_fan_resources {
				break
			}
			resource := power.node(i, node) or { continue }
			fan.resources[fan.resource_count] = resource
			fan.resource_count++
		}
		power.release()
	}
	if !fan.has_level && !fan.has_states && fan.resource_count == 0 {
		// A fan nothing can be done with.
		return
	}
	acpipm_fan_count++
}

fn fan_index(node uacpi.Node) int {
	for i in 0 .. acpipm_fan_count {
		if acpipm_fans[i].node == node {
			return i
		}
	}
	return -1
}

// ── Zones ───────────────────────────────────────────────────────────────────

// Read the zone's active trips and the fans each lists.
fn (mut zone FirmwareZone) read_active_trips() {
	zone.active_count = 0
	for x in 0 .. max_active_trips {
		kelvin := uacpi.evaluate_integer(zone.node, active_trip_names[x]) or { break }
		if !plausible_trip(celsius_millis(kelvin)) {
			zone.implausible++
			continue
		}
		mut trip := &zone.active[zone.active_count]
		trip.temperature = celsius_millis(kelvin)
		trip.fan_count = 0
		trip.engaged = false
		if mut listed := uacpi.evaluate_package(zone.node, active_list_names[x]) {
			for i in 0 .. listed.len() {
				if trip.fan_count >= max_listed_fans {
					break
				}
				node := listed.node(i, zone.node) or { continue }
				index := fan_index(node)
				if index < 0 {
					continue
				}
				trip.fans[trip.fan_count] = index
				trip.fan_count++
			}
			listed.release()
		}
		zone.active_count++
	}
}

// What a temperature asks of each fan the zone lists. Trip 0 is the hottest,
// and its fans run flat out; each trip below runs its fans a step slower.
fn (mut zone FirmwareZone) cool(temperature i64) {
	if zone.active_count == 0 {
		return
	}
	if !katomic.cas(mut &acpipm_cooling_busy, u32(0), u32(1)) {
		return
	}
	mut wanted := [max_fans]u32{}
	mut listed := [max_fans]bool{}
	mut changed := false
	for x in 0 .. zone.active_count {
		mut trip := &zone.active[x]
		was := trip.engaged
		if temperature >= trip.temperature {
			trip.engaged = true
		} else if temperature < trip.temperature - active_hysteresis {
			trip.engaged = false
		}
		if trip.engaged != was {
			changed = true
		}
		percent := u32(100 * (zone.active_count - x) / zone.active_count)
		for i in 0 .. trip.fan_count {
			fan := trip.fans[i]
			listed[fan] = true
			if trip.engaged && percent > wanted[fan] {
				wanted[fan] = percent
			}
		}
	}
	for i in 0 .. acpipm_fan_count {
		if !listed[i] {
			continue
		}
		mut fan := &acpipm_fans[i]
		// Told once whatever the temperature, so that a fan firmware left
		// running is not left running for nothing; after that only when
		// the zone changes its mind, which leaves a level set by hand in
		// place until then.
		if !fan.told || (changed && fan.percent != wanted[i]) {
			fan.drive(wanted[i])
		}
	}
	katomic.store(mut &acpipm_cooling_busy, u32(0))
}

// The thermal module's read of the zone.
fn zone_temperature(context voidptr) ?i64 {
	mut zone := unsafe { &FirmwareZone(context) }
	kelvin := uacpi.evaluate_integer(zone.node, '_TMP') or {
		zone.failures++
		return none
	}
	mut temperature := celsius_millis(kelvin)
	// A zone that reports nothing sensible reports absolute zero or below, or
	// a figure no machine that is still running has reached. Neither is a
	// temperature, and the second must not be taken for a reason to switch
	// the machine off.
	if !plausible_reading(temperature) {
		zone.implausible++
		zone.failures++
		return none
	}
	if zone.has_critical && temperature >= zone.critical {
		// What follows a critical reading is the machine being switched off.
		// Firmware has been known to give one wild figure -- on its way out
		// of a sleep, or while its controller is busy -- so the zone is asked
		// again, and the cooler of the two answers is the one believed.
		devcore.sleep_ms(confirm_ms)
		again := uacpi.evaluate_integer(zone.node, '_TMP') or {
			zone.failures++
			return none
		}
		second := celsius_millis(again)
		if !plausible_reading(second) {
			zone.implausible++
			zone.failures++
			return none
		}
		if second < zone.critical {
			zone.unconfirmed++
		}
		if second < temperature {
			temperature = second
		}
	}
	zone.cool(temperature)
	return temperature
}

// Hand the zone to the thermal module with its trips and its fans.
fn (mut zone FirmwareZone) register() {
	zone.read_active_trips()
	mut record := thermal.Zone{
		name:    'acpitz'
		label:   unsafe { tos(&zone.name[0], zone.name_len) }
		read:    zone_temperature
		context: voidptr(zone)
	}
	// A trip at or below freezing, or beyond anything a machine survives, is
	// firmware's way of having none, and is not acted on.
	if kelvin := uacpi.evaluate_integer(zone.node, '_PSV') {
		if plausible_trip(celsius_millis(kelvin)) {
			record.add_trip(.passive, celsius_millis(kelvin), trip_hysteresis)
		} else {
			zone.implausible++
		}
	}
	if kelvin := uacpi.evaluate_integer(zone.node, '_HOT') {
		if plausible_trip(celsius_millis(kelvin)) {
			record.add_trip(.hot, celsius_millis(kelvin), trip_hysteresis)
		} else {
			zone.implausible++
		}
	}
	zone.has_critical = false
	if kelvin := uacpi.evaluate_integer(zone.node, '_CRT') {
		if !plausible_trip(celsius_millis(kelvin)) {
			zone.implausible++
		} else if !acpipm_thermal_no_critical {
			record.add_trip(.critical, celsius_millis(kelvin), 0)
			zone.has_critical = true
			zone.critical = celsius_millis(kelvin)
		}
	}
	// The zone's fans, each once, for hwmon.
	mut fans := [max_fans]thermal.Fan{}
	mut seen := [max_fans]bool{}
	mut count := 0
	for x in 0 .. zone.active_count {
		for i in 0 .. zone.active[x].fan_count {
			index := zone.active[x].fans[i]
			if seen[index] {
				continue
			}
			seen[index] = true
			fan := &acpipm_fans[index]
			fans[count] = thermal.Fan{
				label:       unsafe { tos(&fan.name[0], fan.name_len) }
				set_percent: fan_set
				context:     voidptr(fan)
			}
			if fan.has_level {
				fans[count].read_rpm = fan_speed
			}
			count++
		}
	}
	if count > 0 {
		record.fans = unsafe { &fans[0] }
		record.fan_count = count
	}
	zone.handle = thermal.register_zone(record)
}

// Firmware says something about the zone changed. The temperature is read
// every second in any case; trips and fan lists are read again.
fn zone_notified(context voidptr, _ voidptr, value u64) uacpi.UACPIStatus {
	mut zone := unsafe { &FirmwareZone(context) }
	if value == notify_information_changed || value == 0x82 {
		if zone.handle != 0 {
			thermal.unregister_zone(zone.handle)
			zone.handle = 0
		}
		zone.register()
	}
	return .ok
}

fn zone_found(_ voidptr, node uacpi.Node) {
	if acpipm_zone_count >= max_thermal_zones {
		return
	}
	// A zone without a temperature is not one.
	uacpi.evaluate_integer(node, '_TMP') or { return }
	mut zone := &acpipm_zones[acpipm_zone_count]
	zone.node = node
	zone.name_len = uacpi.node_name(node, &zone.name[0], 8)
	zone.register()
	if zone.handle == 0 {
		return
	}
	uacpi.on_notify(node, zone_notified, voidptr(zone))
	acpipm_zone_count++
}

fn show_fans(_ voidptr, mut text lib.Text) {
	for i in 0 .. acpipm_fan_count {
		fan := &acpipm_fans[i]
		text.add(unsafe { tos(&fan.name[0], fan.name_len) })
		text.add(if fan.has_level { ' level ' } else { ' switch ' })
		if !fan.told {
			text.add('untouched')
		} else if fan.has_level {
			text.add_unsigned(u64(fan.percent))
		} else {
			text.add(if fan.percent > 0 { 'on' } else { 'off' })
		}
		if fan.failures != 0 {
			text.add(' failures ')
			text.add_unsigned(fan.failures)
		}
		text.add_byte(`\n`)
	}
}

// What each zone has had to disbelieve: one line a zone.
fn show_zones(_ voidptr, mut text lib.Text) {
	for i in 0 .. acpipm_zone_count {
		zone := &acpipm_zones[i]
		text.add(unsafe { tos(&zone.name[0], zone.name_len) })
		text.add(if zone.has_critical { ' critical ' } else { ' no-critical ' })
		text.add_decimal(if zone.has_critical { zone.critical } else { i64(0) })
		text.add(' failed ')
		text.add_unsigned(zone.failures)
		text.add(' implausible ')
		text.add_unsigned(zone.implausible)
		text.add(' unconfirmed ')
		text.add_unsigned(zone.unconfirmed)
		text.add_byte(`\n`)
	}
}

// Find the fans and the zones. Called once ACPI events are on and the
// thermal module is published.
pub fn initialise_thermal() {
	if acpipm_thermal_up {
		return
	}
	acpipm_thermal_up = true
	// For the machine whose firmware reports temperatures that are not: `off`
	// leaves its zones and fans alone, `nocrt` takes the zones without the
	// trip that switches the machine off.
	if choice := devcore.boot_option('vinix.acpi_thermal=') {
		if choice == 'off' {
			print('acpipm: thermal zones and fans left alone by vinix.acpi_thermal=off\n')
			return
		}
		if choice == 'nocrt' {
			print('acpipm: critical trips ignored by vinix.acpi_thermal=nocrt\n')
			acpipm_thermal_no_critical = true
		}
	}
	uacpi.for_each_device('PNP0C0B', fan_found, unsafe { nil })
	uacpi.for_each_thermal_zone(zone_found, unsafe { nil })
	if acpipm_fan_count != 0 {
		fs.sysfs_attribute('class/thermal/acpi_fans', 0o444, show_fans, unsafe { nil }, unsafe { nil })
	}
	if acpipm_zone_count != 0 {
		fs.sysfs_attribute('class/thermal/acpi_zones', 0o444, show_zones, unsafe { nil }, unsafe { nil })
	}
	if acpipm_zone_count + acpipm_fan_count != 0 {
		C.kprintf(c'acpipm: %lld thermal zones, %lld fans\n', i64(acpipm_zone_count), i64(acpipm_fan_count))
	}
}
