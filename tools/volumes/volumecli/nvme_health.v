// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

// NVMe strings are byte strings, without ATA's word swap. Keep firmware text
// bounded and neutralize controls, NULs, non-ASCII and terminal escapes.
@[direct_array_access]
fn nvme_text(bytes &u8, start int, count int, output &u8) {
	unsafe {
		for i in 0 .. count {
			value := bytes[start + i]
			output[i] = if value >= 32 && value <= 126 { value } else { `?` }
		}
		mut end := count
		for end > 0 && output[end - 1] == ` ` { end-- }
		output[end] = 0
	}
}

// Standard counters are unsigned 128-bit little-endian values. Print all
// 16 bytes in hex instead of truncating to a machine integer or guessing units.
@[direct_array_access]
fn nvme_counter(bytes &u8, output &u8) {
	hex := &char(c'0123456789abcdef')
	unsafe {
		for i in 0 .. 16 {
			value := bytes[15 - i]
			output[2 * i] = u8(hex[value >> 4])
			output[2 * i + 1] = u8(hex[value & 15])
		}
		output[32] = 0
	}
}

@[direct_array_access]
fn show_nvme_health(report &Health) i32 {
	mut model := [41]u8{}
	mut serial := [21]u8{}
	mut firmware := [9]u8{}
	nvme_text(&report.identify[0], 24, 40, &model[0])
	nvme_text(&report.identify[0], 4, 20, &serial[0])
	nvme_text(&report.identify[0], 64, 8, &firmware[0])
	C.printf(c'protocol=nvme disk=%lu scope=controller model=%s serial=%s firmware=%s\ncritical_warning=0x%02x warning_status=%s\n',
		report.disk_id, &model[0], &serial[0], &firmware[0], u32(report.data[0]),
		if report.data[0] == 0 { &char(c'none') } else { &char(c'active') })
	temperature := u32(report.data[1]) | (u32(report.data[2]) << 8)
	if temperature == 0 { C.printf(c'temperature_kelvin=unavailable\n') }
	else { C.printf(c'temperature_kelvin=%u\n', temperature) }
	C.printf(c'available_spare_percent=%u spare_threshold_percent=%u percentage_used=%u\n',
		u32(report.data[3]), u32(report.data[4]), u32(report.data[5]))
	names := [&char(c'data_units_read'), &char(c'data_units_written'), &char(c'host_read_commands'), &char(c'host_write_commands'),
		&char(c'controller_busy_minutes'), &char(c'power_cycles'), &char(c'power_on_hours'), &char(c'unsafe_shutdowns'),
		&char(c'media_errors'), &char(c'error_log_entries')]!
	mut text := [33]u8{}
	for i in 0 .. 10 {
		nvme_counter(unsafe { &report.data[32 + i * 16] }, &text[0])
		C.printf(c'%s=0x%s\n', names[i], &text[0])
	}
	return health_exit(report)
}
