// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The idle states as /sys shows them, in Linux's layout, so that powertop,
// cpupower and turbostat find what they look for:
//
//	/sys/devices/system/cpu/cpuidle/
//	    current_driver current_governor
//	/sys/devices/system/cpu/cpuN/cpuidle/stateM/
//	    name desc            what the state is
//	    latency residency    what it costs, in microseconds
//	    usage time           how often this CPU entered it; for how long (us)
//	    above below          how often it turned out too deep; too shallow
//	    rejected             chosen and then not entered
//	    disable              write 1 to keep this CPU out of it
//
// A machine with no driver has current_driver "none" and no state
// directories, as on Linux.
module cpuidle

import errno
import fs
import katomic
import lib
import numa

// The CPU numbers /sys has directories for; see fs/sysfs.v.
const sysfs_cpus = 64

// Which CPU and state a file is about, as its context.
fn file_context(cpu_number int, state int) voidptr {
	return voidptr(u64(cpu_number) << 8 | u64(state))
}

fn context_record(context voidptr) (&CpuRecord, int) {
	word := u64(context)
	return unsafe { &cpuidle_cpus[(word >> 8) % max_cpus] }, int(word & 0xff) % max_states
}

fn show_driver(_ voidptr, mut text lib.Text) {
	text.add(cpuidle_driver_name)
	text.add_byte(`\n`)
}

fn show_usage(context voidptr, mut text lib.Text) {
	record, state := context_record(context)
	text.add_unsigned(record.usage[state])
	text.add_byte(`\n`)
}

fn show_time(context voidptr, mut text lib.Text) {
	record, state := context_record(context)
	text.add_unsigned(ticks_to_us(record.ticks[state], cpuidle_tick_hz))
	text.add_byte(`\n`)
}

fn show_above(context voidptr, mut text lib.Text) {
	record, state := context_record(context)
	text.add_unsigned(record.above[state])
	text.add_byte(`\n`)
}

fn show_below(context voidptr, mut text lib.Text) {
	record, state := context_record(context)
	text.add_unsigned(record.below[state])
	text.add_byte(`\n`)
}

fn show_rejected(context voidptr, mut text lib.Text) {
	record, state := context_record(context)
	text.add_unsigned(record.rejected[state])
	text.add_byte(`\n`)
}

fn show_disable(context voidptr, mut text lib.Text) {
	record, state := context_record(context)
	text.add_unsigned(u64((katomic.load(&record.disabled) >> u32(state)) & 1))
	text.add_byte(`\n`)
}

// 0 or 1, as Linux takes. The CPU keeps a state it is in; the change counts
// from its next idle.
fn store_disable(context voidptr, data &u8, length u64) u64 {
	mut record, state := context_record(context)
	value := fs.sysfs_unsigned(data, length) or { return errno.einval }
	if value > 1 {
		return errno.einval
	}
	bit := u32(1) << u32(state)
	for {
		old := katomic.load(&record.disabled)
		updated := if value == 1 { old | bit } else { old & ~bit }
		if old == updated || katomic.cas(mut &record.disabled, old, updated) {
			break
		}
	}
	return 0
}

// `a`, `n` in decimal, `b`, `m` in decimal, `c`: a path with two numbers in
// it. Built on the stack, as every path in /sys is: a builder made as a local
// value is moved to the heap by the compiler and left there.
fn numbered_path(a string, n int, b string, m int, c string) string {
	mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *text = lib.new_text(a.len + b.len + c.len + 24) }
	text.add(a)
	text.add_unsigned(u64(n))
	text.add(b)
	if m >= 0 {
		text.add_unsigned(u64(m))
	}
	text.add(c)
	return text.str()
}

fn number_line(value u64) string {
	mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *text = lib.new_text(24) }
	text.add_unsigned(value)
	text.add_byte(`\n`)
	return text.str()
}

fn text_line(value string) string {
	mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *text = lib.new_text(value.len + 1) }
	text.add(value)
	text.add_byte(`\n`)
	return text.str()
}

fn publish_text(cpu_number int, state int, name string, value string) {
	path := numbered_path('devices/system/cpu/cpu', cpu_number, '/cpuidle/state', state,
		name)
	fs.sysfs_text(path, value)
	unsafe {
		path.free()
		value.free()
	}
}

fn publish_file(cpu_number int, state int, name string, mode u32, show fs.SysfsShow, store fs.SysfsStore) {
	path := numbered_path('devices/system/cpu/cpu', cpu_number, '/cpuidle/state', state,
		name)
	fs.sysfs_attribute(path, mode, show, store, file_context(cpu_number, state))
	unsafe { path.free() }
}

// Find the machine's idle states, start using them, and show them. Called
// once /sys is mounted; until then every CPU idles as it always has.
pub fn publish() {
	driver_start()
	fs.sysfs_attribute('devices/system/cpu/cpuidle/current_driver', 0o444, show_driver,
		unsafe { nil }, unsafe { nil })
	if !active() {
		fs.sysfs_text('devices/system/cpu/cpuidle/current_governor', 'none\n')
		return
	}
	fs.sysfs_text('devices/system/cpu/cpuidle/current_governor', 'menu\n')
	mut count := numa.cpu_count()
	if count > sysfs_cpus {
		count = sysfs_cpus
	}
	for cpu_number in 0 .. count {
		for state in 0 .. int(cpuidle_state_count) {
			publish_text(cpu_number, state, '/name', text_line(cpuidle_states[state].name))
			publish_text(cpu_number, state, '/desc', text_line(cpuidle_states[state].desc))
			publish_text(cpu_number, state, '/latency', number_line(cpuidle_costs[state].exit_latency_us))
			publish_text(cpu_number, state, '/residency', number_line(cpuidle_costs[state].target_residency_us))
			publish_file(cpu_number, state, '/usage', 0o444, show_usage, unsafe { nil })
			publish_file(cpu_number, state, '/time', 0o444, show_time, unsafe { nil })
			publish_file(cpu_number, state, '/above', 0o444, show_above, unsafe { nil })
			publish_file(cpu_number, state, '/below', 0o444, show_below, unsafe { nil })
			publish_file(cpu_number, state, '/rejected', 0o444, show_rejected, unsafe { nil })
			publish_file(cpu_number, state, '/disable', 0o644, show_disable, store_disable)
		}
	}
}
