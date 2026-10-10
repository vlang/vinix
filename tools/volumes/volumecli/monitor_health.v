// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

#include <string.h>

fn C.fputs(&char, voidptr) i32
fn C.memcpy(voidptr, voidptr, usize) voidptr

struct MonitorHealthCounters {
mut:
	valid  bool
	values [160]u8
}

struct MonitorHealthDelta {
mut:
	available    bool
	baseline     bool
	reset        bool
	media_errors bool
	values       [160]u8
}

// Compare and subtract the complete unsigned little-endian 128-bit counters.
// Their high half must never be lost to a machine-integer conversion.
@[direct_array_access]
fn monitor_counter_less(left &u8, right &u8) bool {
	unsafe {
		for i := 15; i >= 0; i-- {
			if left[i] != right[i] { return left[i] < right[i] }
		}
	}
	return false
}

@[direct_array_access]
fn monitor_counter_subtract(current &u8, previous &u8, output &u8) {
	mut borrow := u16(0)
	unsafe {
		for i in 0 .. 16 {
			sub := u16(previous[i]) + borrow
			value := u16(current[i])
			output[i] = u8(value - sub)
			borrow = if value < sub { u16(1) } else { u16(0) }
		}
	}
}

// Failed queries retain the last successful baseline, so the next successful
// sample covers the gap. A successful different protocol clears that baseline.
// Any decreasing hardware counter begins a fresh epoch with zero deltas.
@[direct_array_access]
fn monitor_health_delta(mut previous MonitorHealthCounters, report &Health,
	queried bool) MonitorHealthDelta {
	if !queried { return MonitorHealthDelta{} }
	if report.protocol != 2 {
		previous.valid = false
		return MonitorHealthDelta{}
	}
	mut delta := MonitorHealthDelta{
		available: true
		baseline:  !previous.valid
	}
	if previous.valid {
		for i in 0 .. 10 {
			if monitor_counter_less(unsafe { &report.data[32 + i * 16] },
				unsafe { &previous.values[i * 16] })
			{
				delta.baseline = true
				delta.reset = true
				break
			}
		}
	}
	if !delta.baseline {
		for i in 0 .. 10 {
			monitor_counter_subtract(unsafe { &report.data[32 + i * 16] },
				unsafe { &previous.values[i * 16] }, unsafe { &delta.values[i * 16] })
		}
		for i in 128 .. 144 {
			if delta.values[i] != 0 { delta.media_errors = true }
		}
	}
	unsafe { C.memcpy(&previous.values[0], &report.data[32], 160) }
	previous.valid = true
	return delta
}

// Produce a bounded suffix for the same sample line. Standard NVMe/ANS fields
// are controller-wide; ATA vendor attributes are deliberately not interpreted.
@[direct_array_access]
fn monitor_health_format(report &Health, delta &MonitorHealthDelta, output &char,
	capacity usize) i32 {
	if !delta.available {
		written := C.snprintf(output, capacity, c' telemetry=unavailable\n')
		return if written < 0 || usize(written) >= capacity { i32(-1) } else { written }
	}
	temperature := u32(report.data[1]) | (u32(report.data[2]) << 8)
	mut thermal := [12]char{}
	thermal_length := C.snprintf(unsafe { &thermal[0] }, 12, if temperature == 0 {
		c'unavailable'
	} else {
		c'%u'
	}, temperature)
	if thermal_length < 0 || thermal_length >= 12 { return -1 }
	mut written := C.snprintf(output, capacity,
		c' telemetry=nvme scope=controller health_baseline=%u health_counters_reset=%u temperature_kelvin=%s available_spare_percent=%u spare_threshold_percent=%u percentage_used=%u',
		u32(delta.baseline), u32(delta.reset), unsafe { &thermal[0] }, u32(report.data[3]),
		u32(report.data[4]), u32(report.data[5]))
	if written < 0 || usize(written) >= capacity { return -1 }
	names := [&char(c'data_units_read'), &char(c'data_units_written'), &char(c'host_read_commands'),
		&char(c'host_write_commands'), &char(c'controller_busy_minutes'), &char(c'power_cycles'),
		&char(c'power_on_hours'), &char(c'unsafe_shutdowns'), &char(c'media_errors'),
		&char(c'error_log_entries')]!
	mut current := [33]u8{}
	mut difference := [33]u8{}
	for i in 0 .. 10 {
		nvme_counter(unsafe { &report.data[32 + i * 16] }, unsafe { &current[0] })
		nvme_counter(unsafe { &delta.values[i * 16] }, unsafe { &difference[0] })
		next := C.snprintf(unsafe { output + written }, capacity - usize(written),
			c' %s=0x%s %s_delta=0x%s', names[i], unsafe { &current[0] }, names[i],
			unsafe { &difference[0] })
		if next < 0 || usize(next) >= capacity - usize(written) { return -1 }
		written += next
	}
	if capacity - usize(written) < 2 { return -1 }
	unsafe {
		output[written] = char(`\n`)
		output[written + 1] = 0
	}
	return written + 1
}

fn monitor_health_show(report &Health, delta &MonitorHealthDelta) bool {
	mut text := [2048]char{}
	return monitor_health_format(report, delta, unsafe { &text[0] }, 2048) >= 0
		&& C.fputs(unsafe { &text[0] }, C.stdout) >= 0
}
