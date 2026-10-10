// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The embedded controller.
//
// No machine QEMU has one, so these scenarios are exact about what stands in
// for it (see the README):
//
//   acpi-ec-selftest, acpi-ec-selftest-dsdt
//       A kernel built with -d acpiec_selftest, in which a simulated
//       controller answers instead of the two ports, and an ACPI table from
//       the host (`ec-bench`) that describes a controller with a battery, a
//       charger and a lid whose methods read its fields. This program sets
//       the controller's memory and queues its events through the self-test
//       file, and looks at what the kernel made of them in /sys.
//   acpi-ec-absent
//       An ordinary kernel and a table that describes a controller at ports
//       where nothing answers: the kernel must give it up, carry on, and
//       answer a read in /sys at once.
//   acpi-ec-off
//       The same table with vinix.ec=off: the driver must stay away.
@[has_globals]
module main

import os
import time

#include <signal.h>
#include <pthread.h>

fn C.pthread_kill(thread voidptr, signal int) int

__global (
	ec_signals_taken = u64(0)
	ec_signals_stop  = false
)

fn ec_on_signal(_ os.Signal) {
	ec_signals_taken++
}

// Sends the thread `target` a signal a few thousand times a second.
fn ec_signal_storm(target voidptr) {
	for !ec_signals_stop {
		C.pthread_kill(target, C.SIGUSR1)
		C.usleep(200)
	}
}

const ec_device = '/sys/bus/acpi/devices/PNP0C09:00/'
const ec = '/sys/bus/acpi/devices/PNP0C09:00/ec/'
const ec_battery = '/sys/class/power_supply/BAT0/'
const ec_charger = '/sys/class/power_supply/ADP0/'
const ec_lid = '/sys/power/lid/'
// A reading in /sys/class/power_supply is asked for again once it is a
// second old.
const ec_stale_ms = 1200

fn ec_count(name string) i64 {
	return read_word(ec + name).i64()
}

fn ec_milliseconds() i64 {
	return i64(time.sys_mono_now() / 1000000)
}

// One command to the simulated controller.
fn ec_sim(mut t Test, command string) {
	write_text(ec + 'selftest', command) or { t.check(false, 'selftest "${command}": ${err}') }
}

// A counter of the simulated controller's.
fn ec_sim_count(name string) i64 {
	text := read_text(ec + 'selftest_state') or { return -1 }
	for line in text.split_into_lines() {
		words := line.fields()
		if words.len == 2 && words[0] == name {
			return words[1].i64()
		}
	}
	return -1
}

// A byte of the simulated controller's memory.
fn ec_sim_ram(address int) int {
	text := read_text(ec + 'selftest_state') or { return -1 }
	mut row := 0
	for line in text.split_into_lines() {
		words := line.fields()
		if words.len != 17 || words[0] != 'ram' {
			continue
		}
		if row == address / 16 {
			return int(('0x' + words[1 + address % 16]).u64())
		}
		row++
	}
	return -1
}

// Sets a sixteen-bit field of the simulated controller, low byte first.
fn ec_sim_word(mut t Test, address int, value int) {
	ec_sim(mut t, 'ram ${address} ${value & 0xff}')
	ec_sim(mut t, 'ram ${address + 1} ${(value >> 8) & 0xff}')
}

fn ec_wait_word(path string, want string, milliseconds int) bool {
	mut waited := 0
	for {
		if read_word(path) == want {
			return true
		}
		if waited >= milliseconds {
			return false
		}
		sleep_ms(20)
		waited += 20
	}
	return false
}

fn ec_wait_count(name string, want i64, milliseconds int) bool {
	mut waited := 0
	for {
		if ec_count(name) >= want {
			return true
		}
		if waited >= milliseconds {
			return false
		}
		sleep_ms(20)
		waited += 20
	}
	return false
}

// Reads `path` and says how long the read took.
fn ec_timed_read(path string) (string, i64) {
	started := ec_milliseconds()
	word := read_word(path)
	return word, ec_milliseconds() - started
}

fn ec_check_word(mut t Test, path string, want string) {
	found := read_word(path)
	t.check(found == want, '${path} is "${found}", not "${want}"')
}

fn scenario_acpi_ec_selftest(mut t Test) {
	booted := ec_milliseconds()
	if !t.check(os.exists(ec + 'selftest'), 'no ${ec}selftest: not a self-test kernel, or no controller found') {
		return
	}
	early := t.scenario == 'acpi-ec-selftest'

	// What the kernel found.
	ec_check_word(mut t, ec + 'data_port', '0x62')
	ec_check_word(mut t, ec + 'command_port', '0x66')
	ec_check_word(mut t, ec + 'source', if early { 'ECDT and namespace' } else { 'namespace' })
	ec_check_word(mut t, ec + 'uid', '7')
	ec_check_word(mut t, ec + 'gpe', '0x2')
	ec_check_word(mut t, ec + 'events', 'gpe')
	ec_check_word(mut t, ec + 'global_lock', '1')
	ec_check_word(mut t, ec + 'failed', '0')
	ec_check_word(mut t, ec + 'failure', 'none')
	ec_check_word(mut t, ec_device + 'state', 'bound')
	t.check(os.is_link(ec_device + 'driver'), 'the controller has no driver link')
	t.check(os.exists('/sys/bus/acpi/drivers/ec'), 'there is no ec driver in /sys/bus/acpi/drivers')

	// What it read through the controller while booting, before this program
	// existed: the simulated controller starts as a laptop on its charger.
	ec_check_word(mut t, ec_battery + 'present', '1')
	ec_check_word(mut t, ec_battery + 'status', 'Charging')
	ec_check_word(mut t, ec_battery + 'energy_now', '40000000')
	ec_check_word(mut t, ec_battery + 'energy_full', '48000000')
	ec_check_word(mut t, ec_battery + 'energy_full_design', '50000000')
	ec_check_word(mut t, ec_battery + 'voltage_now', '11800000')
	ec_check_word(mut t, ec_battery + 'power_now', '15000000')
	ec_check_word(mut t, ec_battery + 'model_name', 'VNXEC')
	// Read from the controller while the table loaded, and in an _INI, when
	// there is an ECDT; at the time otherwise.
	ec_check_word(mut t, ec_battery + 'voltage_min_design', '11400000')
	ec_check_word(mut t, ec_battery + 'cycle_count', '77')
	ec_check_word(mut t, ec_charger + 'online', '1')
	ec_check_word(mut t, ec_lid + 'state', 'open')
	boot_transactions := ec_count('transactions')
	t.check(boot_transactions >= 20, 'only ${boot_transactions} exchanges by the time init runs')
	t.check(ec_count('timeouts') == 0, 'timeouts while booting: ${ec_count('timeouts')}')
	// With vinix.ec=clear the controller is asked once at start whatever its
	// event bit says, and names nothing; without, it is not asked at all.
	t.check(ec_sim_count('empty_queries') == if early { 0 } else { 1 }, '${ec_sim_count('empty_queries')} queries named nothing while booting')
	t.info('boot: init ${booted} ms after the clock started, ${boot_transactions} exchanges, source ${read_word(ec +
		'source')}')

	// A value, with no event: memory -> field -> method -> /sys.
	ec_sim(mut t, 'ram 0 1') // discharging
	ec_sim(mut t, 'ram 1 0') // the charger is gone
	ec_sim_word(mut t, 4, 12000)
	ec_sim_word(mut t, 6, 30000)
	sleep_ms(ec_stale_ms)
	ec_check_word(mut t, ec_battery + 'status', 'Discharging')
	ec_check_word(mut t, ec_battery + 'energy_now', '30000000')
	ec_check_word(mut t, ec_battery + 'power_now', '12000000')
	ec_check_word(mut t, ec_charger + 'online', '0')

	// Events, with the general purpose event raised by QEMU's chipset when
	// the host asks it to. What a battery is, is read once and kept until
	// firmware says it changed: only a Notify moves energy_full.
	gpes := ec_count('gpe_count')
	queries := ec_count('queries')
	methods := ec_count('methods')
	ec_sim_word(mut t, 0x0a, 45000)
	sleep_ms(ec_stale_ms)
	ec_check_word(mut t, ec_battery + 'energy_full', '48000000')
	ec_sim(mut t, 'event 0x23')
	t.step('controller event 1')
	t.check(ec_wait_word(ec_battery + 'energy_full', '45000000', 10000), 'energy_full is ${read_word(ec_battery +
		'energy_full')} after event 0x23: gpe_count ${ec_count('gpe_count')}, queries ${ec_count('queries')}, methods ${ec_count('methods')}')
	t.check(ec_count('gpe_count') == gpes + 1, 'gpe_count went from ${gpes} to ${ec_count('gpe_count')}')
	t.check(ec_count('queries') == queries + 1, 'queries went from ${queries} to ${ec_count('queries')}')
	t.check(ec_count('methods') == methods + 1, 'methods went from ${methods} to ${ec_count('methods')}')
	// _Q23 also wrote to the controller.
	t.check(ec_sim_ram(0x10) == 1, 'the byte _Q23 adds one to is ${ec_sim_ram(0x10)}')

	// The lid, twice: the event is switched on again after each.
	write_text(ec_lid + 'action', 'ignore') or { t.check(false, 'lid action: ${err}') }
	ec_sim(mut t, 'ram 2 0')
	ec_sim(mut t, 'event 0x22')
	t.step('controller event 2')
	t.check(ec_wait_word(ec_lid + 'state', 'closed', 10000), 'the lid is ${read_word(ec_lid + 'state')} after it shut')
	ec_check_word(mut t, ec_lid + 'closes', '1')
	ec_sim(mut t, 'ram 2 1')
	ec_sim(mut t, 'event 0x22')
	t.step('controller event 3')
	t.check(ec_wait_word(ec_lid + 'state', 'open', 10000), 'the lid is ${read_word(ec_lid + 'state')} after it opened')
	t.check(ec_count('gpe_count') == gpes + 3, 'gpe_count went from ${gpes} to ${ec_count('gpe_count')} over three events')
	ec_check_word(mut t, '/sys/power/suspend_stats/success', '0')
	t.info('events raised by the chipset: ${ec_count('gpe_count') - gpes}, queries ${ec_count('queries') - queries}, methods ${ec_count('methods') - methods}')

	// From here on the self-test raises the event itself. Fields wider than
	// a byte, read and written by a method.
	ec_sim_word(mut t, 0x20, 0x1234)
	ec_sim_word(mut t, 0x24, 0xffff)
	ec_sim_word(mut t, 0x26, 0)
	ec_sim(mut t, 'event 0x24')
	ec_sim(mut t, 'raise')
	t.check(ec_wait_count('methods', methods + 4, 5000), '_Q24 did not run')
	sleep_ms(100)
	t.check(ec_sim_ram(0x20) == 0x35 && ec_sim_ram(0x21) == 0x13, 'the word is ${ec_sim_ram(0x21).hex()}${ec_sim_ram(0x20).hex()}, not 1335')
	t.check(ec_sim_ram(0x24) == 0 && ec_sim_ram(0x25) == 0 && ec_sim_ram(0x26) == 1
		&& ec_sim_ram(0x27) == 0, 'the four bytes are ${ec_sim_ram(0x27)} ${ec_sim_ram(0x26)} ${ec_sim_ram(0x25)} ${ec_sim_ram(0x24)}, not 0 1 0 0')

	// Two events behind one raise are both taken; one firmware has no method
	// for is counted and nothing more.
	missing := ec_count('methods_missing')
	ec_sim(mut t, 'event 0x20')
	ec_sim(mut t, 'event 0x30')
	ec_sim(mut t, 'event 0x21')
	ec_sim(mut t, 'raise')
	t.check(ec_wait_count('queries', queries + 7, 5000), 'queries are ${ec_count('queries')}, not ${
		queries + 7}')
	t.check(ec_count('methods') == methods + 6, 'methods are ${ec_count('methods')}, not ${methods + 6}')
	t.check(ec_count('methods_missing') == missing + 1, 'methods_missing went from ${missing} to ${ec_count('methods_missing')}')

	ec_selftest_sleep(mut t)
	// And once more after each of the four sleeps.
	t.check(ec_sim_count('empty_queries') == if early { 0 } else { 5 }, '${ec_sim_count('empty_queries')} queries had named nothing after four sleeps')
	ec_selftest_retention(mut t)
	ec_selftest_signals(mut t)
	// With a controller that works nobody has ever waited a second for the
	// global lock.
	t.check(ec_sim_count('lock_failures') == 0, 'the lock failed ${ec_sim_count('lock_failures')} times')
	ec_selftest_faults(mut t)

	t.check(ec_sim_count('violations') == 0, 'the protocol was broken ${ec_sim_count('violations')} times')
	t.check(ec_sim_count('dropped') == 0, '${ec_sim_count('dropped')} queries could not be queued')
	t.check(ec_sim_count('methods_failed') == 0, '${ec_sim_count('methods_failed')} methods failed')
	t.info('in all: ${ec_count('transactions')} exchanges, ${ec_count('queries')} events, ${ec_count('timeouts')} timeouts, ${ec_count('stale_bytes')} stale bytes, protocol violations ${ec_sim_count('violations')}')
}

// Sleep: what the controller says while the machine is asleep.
fn ec_selftest_sleep(mut t Test) {
	slept_stats := '/sys/power/suspend_stats/'
	alarm := '/sys/class/rtc/rtc0/wakealarm'
	source := '/sys/class/wakeup/wakeup9/'
	ec_check_word(mut t, source + 'name', 'embedded-controller')
	ec_check_word(mut t, source + 'enabled', 'disabled')
	ec_check_word(mut t, ec_device + 'power/wakeup', 'enabled')

	// The lid shuts, the machine sleeps, the lid opens, the machine wakes.
	// This program is frozen in between: the simulated controller is told
	// beforehand to open the lid in two and a half seconds.
	write_text(ec_lid + 'action', 'suspend') or { t.check(false, 'lid action: ${err}') }
	write_text(alarm, '+12') or { t.check(false, 'wakealarm: ${err}') }
	sleep_events := ec_count('sleep_events')
	ec_sim(mut t, 'later 2500 0x22 2 1')
	ec_sim(mut t, 'ram 2 0')
	ec_sim(mut t, 'event 0x22')
	ec_sim(mut t, 'raise')
	t.check(ec_wait_word(slept_stats + 'success', '1', 15000), 'the lid shutting did not put the machine to sleep and back')
	ec_check_word(mut t, slept_stats + 'last_wake', 'lid')
	ec_check_word(mut t, ec_lid + 'state', 'open')
	ec_check_word(mut t, ec_lid + 'closes', '2')
	slept := read_word(slept_stats + 'last_sleep_ms').i64()
	t.check(slept >= 1000 && slept < 5000, 'the machine slept ${slept} ms; the lid opened 2500 ms after it shut')
	t.check(ec_count('sleep_events') > sleep_events, 'no controller event was counted while asleep')
	t.check(read_word(ec_device + 'power/wakeup_count').i64() >= 1, 'the device counted no wakeup')
	write_text(alarm, '0') or {}
	t.info('lid: shut, slept ${slept} ms, woken by ${read_word(slept_stats + 'last_wake')}')
	write_text(ec_lid + 'action', 'ignore') or { t.check(false, 'lid action: ${err}') }

	// An event nothing claims does not end a sleep...
	sleep_ms(300)
	events := read_word(source + 'event_count').i64()
	write_text(alarm, '+3') or { t.check(false, 'wakealarm: ${err}') }
	ec_sim(mut t, 'later 1000 0x30')
	mut took := sleep_now(mut t, 'freeze')
	ec_check_word(mut t, slept_stats + 'last_wake', 'alarm')
	t.check(took >= 2800, 'an unclaimed controller event ended the sleep after ${took} ms')
	t.check(read_word(source + 'event_count').i64() > events, 'the controller event was not counted')
	ec_check_word(mut t, source + 'wakeup_count', '0')
	// ...unless the controller has been allowed to.
	sleep_ms(300)
	write_text(source + 'enabled', 'enabled') or { t.check(false, 'enabling the source: ${err}') }
	write_text(alarm, '+8') or { t.check(false, 'wakealarm: ${err}') }
	ec_sim(mut t, 'later 1000 0x30')
	took = sleep_now(mut t, 'freeze')
	ec_check_word(mut t, slept_stats + 'last_wake', 'embedded-controller')
	t.check(took < 6000, 'the sleep the controller was to end took ${took} ms')
	ec_check_word(mut t, source + 'wakeup_count', '1')
	write_text(source + 'enabled', 'disabled') or { t.check(false, 'disabling the source: ${err}') }
	write_text(alarm, '0') or {}
	t.info('unclaimed event: ignored asleep, then ended a sleep after ${took} ms once allowed')

	// With wakeup disabled for the device its event is off for the sleep,
	// and what it raised is asked for on resume.
	sleep_ms(300)
	write_text(ec_device + 'power/wakeup', 'disabled') or { t.check(false, 'disabling wakeup: ${err}') }
	write_text(alarm, '+3') or { t.check(false, 'wakealarm: ${err}') }
	queries := ec_count('queries')
	ec_sim(mut t, 'later 1000 0x22 2 0')
	took = sleep_now(mut t, 'freeze')
	ec_check_word(mut t, slept_stats + 'last_wake', 'alarm')
	t.check(took >= 2800, 'the controller ended a sleep it was not to end, after ${took} ms')
	t.check(ec_wait_word(ec_lid + 'state', 'closed', 3000), 'the lid that shut during the sleep is ${read_word(ec_lid +
		'state')} after it')
	t.check(ec_count('queries') == queries + 1, 'queries went from ${queries} to ${ec_count('queries')}')
	write_text(ec_device + 'power/wakeup', 'enabled') or { t.check(false, 'enabling wakeup: ${err}') }
	ec_sim(mut t, 'ram 2 1')
	ec_sim(mut t, 'event 0x22')
	ec_sim(mut t, 'raise')
	t.check(ec_wait_word(ec_lid + 'state', 'open', 3000), 'the lid did not open again')
	ec_check_word(mut t, slept_stats + 'fail', '0')
	ec_check_word(mut t, slept_stats + 'success', '4')
}

// One write() of `text` to `path`, with nothing allocated in this program:
// its own heap growing costs the kernel objects too, and would be counted.
fn ec_raw_write(path &char, text &char, length int) bool {
	fd := C.open(path, C.O_WRONLY)
	if fd < 0 {
		return false
	}
	written := C.write(fd, text, usize(length))
	C.close(fd)
	return written == length
}

// Reads `path` to its end into a buffer on the stack and returns how much
// there was.
fn ec_raw_read(path &char) int {
	mut buffer := [1024]u8{}
	fd := C.open(path, C.O_RDONLY)
	if fd < 0 {
		return -1
	}
	mut total := 0
	for {
		count := C.read(fd, &buffer[0], usize(1024))
		if count <= 0 {
			break
		}
		total += int(count)
	}
	C.close(fd)
	return total
}

// `count` times: an event that has the battery read again, raised by the
// self-test, and a read of the battery through /sys.
fn ec_event_rounds(mut t Test, count int) {
	queries := ec_count('queries')
	control := c'/sys/bus/acpi/devices/PNP0C09:00/ec/selftest'
	uevent := c'/sys/class/power_supply/BAT0/uevent'
	mut failed := 0
	for _ in 0 .. count {
		if !ec_raw_write(control, c'event 0x20', 10) || !ec_raw_write(control, c'raise', 5) {
			failed++
		}
		if ec_raw_read(uevent) <= 0 {
			failed++
		}
		C.usleep(10000)
	}
	t.check(failed == 0, '${failed} writes or reads failed in ${count} rounds')
	t.check(ec_wait_count('queries', queries + count, 5000), 'only ${ec_count('queries') - queries} of ${count} events were taken')
}

// Nothing may stay allocated for an exchange, a query, a method or a
// Notify: a laptop does these all day. The kernel's heap is measured over
// three hundred rounds, after enough rounds for what is meant to stay
// allocated to have been.
fn ec_selftest_retention(mut t Test) {
	rounds := 300
	ec_event_rounds(mut t, 60)
	sleep_ms(2000)
	before := heap_usage() or {
		t.check(false, err.msg())
		return
	}
	exchanges := ec_count('transactions')
	ec_event_rounds(mut t, rounds)
	sleep_ms(2000)
	after := heap_usage() or {
		t.check(false, err.msg())
		return
	}
	done := ec_count('transactions') - exchanges
	t.info('${rounds} events and ${done} exchanges: live heap objects ${before.objects} -> ${after.objects}, large pages ${before.large_pages} -> ${after.large_pages}')
	t.check(done >= rounds * 8, 'only ${done} exchanges in ${rounds} rounds')
	t.check(after.objects - before.objects <= heap_noise_objects, '${rounds} events left ${after.objects - before.objects} more heap objects allocated (limit ${heap_noise_objects})')
	t.check(after.large_pages <= before.large_pages, '${rounds} events left ${after.large_pages - before.large_pages} more large-allocation pages')
}

// A read in /sys evaluates a method in the context of whoever reads, and a
// program is sent signals whenever anybody likes. A thread with a signal
// waiting may not sleep, and the locks on the way to the controller are
// ones that sleep: a read that arrives while another thread has the
// controller must wait its turn all the same, not fail. Here this program
// reads the battery while a second thread of it sends the first a signal a
// few thousand times a second, and the controller -- slowed down, so that
// it is usually busy -- is kept at work by events.
fn ec_selftest_signals(mut t Test) {
	os.signal_opt(.usr1, ec_on_signal) or {
		t.check(false, 'could not install a SIGUSR1 handler: ${err}')
		return
	}
	control := c'/sys/bus/acpi/devices/PNP0C09:00/ec/selftest'
	status := c'/sys/class/power_supply/BAT0/status'
	ec_sim(mut t, 'latency 500')
	ec_signals_stop = false
	ec_signals_taken = 0
	storm := spawn ec_signal_storm(voidptr(C.pthread_self()))
	rounds := 150
	mut wrong := 0
	mut read := 0
	mut buffer := [64]u8{}
	for _ in 0 .. rounds {
		ec_raw_write(control, c'event 0x20', 10)
		ec_raw_write(control, c'raise', 5)
		fd := C.open(status, C.O_RDONLY)
		if fd < 0 {
			continue
		}
		count := C.read(fd, &buffer[0], usize(63))
		C.close(fd)
		if count <= 0 {
			// Interrupted before it began: not an answer, right or wrong.
			continue
		}
		read++
		if buffer[0] != `D` {
			wrong++
		}
	}
	ec_signals_stop = true
	storm.wait()
	ec_sim(mut t, 'latency 20')
	// Events were queued faster than a controller this slow gives them up,
	// more than once past the limit of one go: have what is left taken
	// before anything else is counted.
	mut left := ec_sim_count('waiting')
	for _ in 0 .. 50 {
		if left == 0 {
			break
		}
		ec_sim(mut t, 'raise')
		sleep_ms(100)
		left = ec_sim_count('waiting')
	}
	t.check(left == 0, '${left} events were still in the controller after the signals')
	sleep_ms(200)
	t.info('under signals: ${read} reads of the battery, ${wrong} without an answer, ${ec_signals_taken} signals taken')
	t.check(ec_signals_taken >= 10, 'only ${ec_signals_taken} signals were taken')
	t.check(read >= rounds / 2, 'only ${read} of ${rounds} reads returned anything')
	t.check(wrong == 0, '${wrong} of ${read} reads under signals did not say Discharging')
	sleep_ms(ec_stale_ms)
	ec_check_word(mut t, ec_battery + 'status', 'Discharging')
}

// A controller that misbehaves, with the real clock.
fn ec_selftest_faults(mut t Test) {
	// A byte left in the output buffer is not an answer.
	stale := ec_count('stale_bytes')
	ec_sim(mut t, 'stale 0xee')
	sleep_ms(ec_stale_ms)
	ec_check_word(mut t, ec_battery + 'energy_now', '30000000')
	t.check(ec_count('stale_bytes') == stale + 1, 'stale_bytes went from ${stale} to ${ec_count('stale_bytes')}')

	// A controller that never runs out of events is left at the limit.
	sim_queries := ec_sim_count('queries')
	limits := ec_sim_count('drain_limits')
	ec_sim(mut t, 'endless 0x30')
	ec_sim(mut t, 'raise')
	sleep_ms(1500)
	asked := ec_sim_count('queries') - sim_queries
	t.check(asked == 32, 'a controller that always has an event was asked ${asked} times, not 32')
	t.check(ec_sim_count('drain_limits') == limits + 1, 'drain_limits went from ${limits} to ${ec_sim_count('drain_limits')}')
	ec_sim(mut t, 'endless 0')
	// An event bit stuck up with nothing behind it is asked about once, and
	// not again by the exchanges that see it.
	sleep_ms(ec_stale_ms)
	read_word(ec_battery + 'energy_now')
	sim_before := ec_sim_count('queries')
	ec_sim(mut t, 'fault stuck-sci')
	ec_sim(mut t, 'raise')
	for _ in 0 .. 3 {
		sleep_ms(ec_stale_ms)
		read_word(ec_battery + 'energy_now')
	}
	t.check(ec_sim_count('queries') == sim_before + 1, 'a stuck event bit brought ${ec_sim_count('queries') - sim_before} queries')
	ec_sim(mut t, 'fault none')
	sleep_ms(ec_stale_ms)
	read_word(ec_battery + 'energy_now')

	// A line that is stuck is switched off, and the event bit polled.
	ec_sim(mut t, 'storm')
	t.check(ec_wait_word(ec + 'events', 'polled', 2000), 'events are ${read_word(ec + 'events')} after a storm')
	ec_sim(mut t, 'ram 2 0')
	ec_sim(mut t, 'event 0x22')
	t.check(ec_wait_word(ec_lid + 'state', 'closed', 3000), 'polling did not find the lid shut')
	ec_sim(mut t, 'ram 2 1')
	ec_sim(mut t, 'event 0x22')
	t.check(ec_wait_word(ec_lid + 'state', 'open', 3000), 'polling did not find the lid open')

	// A controller that stops answering. Each exchange is waited for its
	// two and a half seconds; the third in a row gives the controller up.
	timeouts := ec_count('timeouts')
	ec_sim(mut t, 'fault silent')
	sleep_ms(ec_stale_ms)
	// The battery's _STA and its _BST: two exchanges.
	mut word, mut took := ec_timed_read(ec_battery + 'status')
	t.check(took >= 4500 && took < 9000, 'reading a silent controller\'s battery took ${took} ms')
	t.check(word == 'Unknown', 'status is "${word}" with a controller that does not answer')
	first_read := took
	// The charger's _PSR: the third.
	_, took = ec_timed_read(ec_charger + 'online')
	t.check(took >= 2300 && took < 5000, 'reading its charger took ${took} ms')
	ec_check_word(mut t, ec + 'failed', '1')
	ec_check_word(mut t, ec + 'failure', 'no answer in time')
	// From now on nobody waits.
	refused := ec_count('refused')
	mut slowest := i64(0)
	for _ in 0 .. 3 {
		sleep_ms(ec_stale_ms)
		for path in [ec_battery + 'status', ec_charger + 'online', ec_battery + 'energy_now'] {
			_, took = ec_timed_read(path)
			if took > slowest {
				slowest = took
			}
		}
	}
	t.check(slowest < 500, 'a read took ${slowest} ms after the controller was given up on')
	t.check(ec_count('refused') > refused, 'no caller was turned away')
	// The device core was told, and has marked the device failed.
	t.check(ec_wait_word(ec_device + 'state', 'failed', 5000), 'the device is ${read_word(ec_device + 'state')}')
	health := read_text(ec_device + 'health') or { '' }
	t.check(health.contains('failures: 1'), 'health is ${health.replace('\n', ', ')}')
	t.check(ec_count('timeouts') == timeouts + 3, 'timeouts went from ${timeouts} to ${ec_count('timeouts')}')
	// While the simulated controller waited, a thread polling its event bit
	// gave up on the global lock after a second, each time, rather than
	// wait for it without limit.
	t.info('the global lock was given up on ${ec_sim_count('lock_failures')} times while the controller was silent')
	t.info('silent: battery read ${first_read} ms, then at most ${slowest} ms a read; device ${read_word(ec_device + 'state')}')

	// It answers again, and is told to try.
	ec_sim(mut t, 'fault none')
	write_text(ec_device + 'reset', '1') or { t.check(false, 'reset: ${err}') }
	t.check(ec_wait_word(ec_device + 'state', 'bound', 5000), 'the device is ${read_word(ec_device + 'state')} after a reset')
	ec_check_word(mut t, ec + 'failed', '0')
	sleep_ms(ec_stale_ms)
	ec_check_word(mut t, ec_battery + 'status', 'Discharging')
	ec_check_word(mut t, ec_battery + 'energy_now', '30000000')
}

fn scenario_acpi_ec_absent(mut t Test) {
	booted := ec_milliseconds()
	if !t.check(os.exists(ec + 'failed'), 'no ${ec}failed: the controller was not found') {
		return
	}
	t.check(!os.exists(ec + 'selftest'), 'this is a self-test kernel: its controller is simulated')
	ec_check_word(mut t, ec + 'data_port', '0x62')
	ec_check_word(mut t, ec + 'command_port', '0x66')
	ec_check_word(mut t, ec + 'source', 'namespace')
	ec_check_word(mut t, ec + 'uid', '9')
	// A package: event 3 of a block this kernel does not drive.
	ec_check_word(mut t, ec + 'gpe', '0x3')
	ec_check_word(mut t, ec + 'events', 'polled')
	ec_check_word(mut t, ec + 'global_lock', '0')
	// Given up on, and by the device core as well.
	ec_check_word(mut t, ec + 'failed', '1')
	ec_check_word(mut t, ec + 'failure', 'output buffer would not empty')
	t.check(ec_wait_word(ec_device + 'state', 'failed', 10000), 'the device is ${read_word(ec_device + 'state')}')
	t.check(ec_count('transactions') == 1, '${ec_count('transactions')} exchanges were tried')
	t.check(ec_count('queries') == 0, 'the controller named ${ec_count('queries')} events')

	// The battery that shows itself without asking the controller is there
	// and cannot be read; the one that asks is not there.
	t.check(os.exists(ec_battery + 'status'), 'BAT0 is not in /sys/class/power_supply')
	t.check(!os.exists('/sys/class/power_supply/BAT1'), 'BAT1 is in /sys/class/power_supply')
	mut slowest := i64(0)
	for _ in 0 .. 3 {
		sleep_ms(ec_stale_ms)
		for path in [ec_battery + 'status', ec_battery + 'present', ec_battery + 'energy_now',
			ec_battery + 'uevent', ec_charger + 'online'] {
			_, took := ec_timed_read(path)
			if took > slowest {
				slowest = took
			}
		}
	}
	t.check(slowest < 500, 'a read took ${slowest} ms')
	ec_check_word(mut t, ec_battery + 'status', 'Unknown')
	ec_check_word(mut t, ec_battery + 'present', '0')
	ec_check_word(mut t, ec_charger + 'online', '0')
	ec_check_word(mut t, ec_lid + 'state', 'unknown')
	t.check(ec_count('refused') > 0, 'no caller was turned away')

	// Asking for another try gets one, and the same answer, quickly.
	transactions := ec_count('transactions')
	started := ec_milliseconds()
	write_text(ec_device + 'reset', '1') or { t.check(false, 'reset: ${err}') }
	sleep_ms(500)
	ec_check_word(mut t, ec_device + 'state', 'failed')
	ec_check_word(mut t, ec + 'failed', '1')
	t.check(ec_count('transactions') == transactions + 1, 'a reset tried ${ec_count('transactions') - transactions} exchanges')
	t.info('init ${booted} ms after the clock started; slowest read ${slowest} ms; ${ec_count('transactions')} exchanges, ${ec_count('timeouts')} failed, ${ec_count('refused')} callers turned away; reset took under ${ec_milliseconds() - started} ms')
}

fn scenario_acpi_ec_off(mut t Test) {
	booted := ec_milliseconds()
	t.check(!os.exists(ec_device), 'the controller is a device although vinix.ec=off')
	t.check(!os.exists('/sys/bus/acpi/drivers/ec'), 'there is an ec driver although vinix.ec=off')
	// No _REG ran, so the battery never showed itself.
	t.check(!os.exists(ec_battery), 'BAT0 is in /sys/class/power_supply')
	ec_check_word(mut t, ec_lid + 'state', 'unknown')
	t.info('init ${booted} ms after the clock started')
}
