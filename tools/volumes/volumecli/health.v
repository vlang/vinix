// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

struct Health {
mut:
	version u64
	protocol u64
	flags u64
	disk_id u64
	reserved [4]u64
	identify [512]u8
	data [512]u8
}

@[direct_array_access]
fn health_valid(report &Health) bool {
	if report.version != 1 || report.protocol != 1 || report.disk_id == 0
		|| report.flags & ~u64(31) != 0 { return false }
	for value in report.reserved { if value != 0 { return false } }
	if report.flags & 2 != 0 && report.flags & 1 == 0 { return false }
	if report.flags & 12 != 0 && report.flags & 3 != 3 { return false }
	if report.flags & 16 != 0 && report.flags & 8 == 0 { return false }
	if report.flags & 4 != 0 {
		mut sum := u32(0)
		for value in report.data { sum += value }
		if sum & 255 != 0 { return false }
	}
	return true
}

// ATA strings have swapped bytes within words. Bound every field and replace
// controls/non-ASCII, including terminal escapes supplied by device firmware.
@[direct_array_access]
fn ata_text(bytes &u8, start int, count int, output &u8) {
	unsafe {
		for i in 0 .. count {
			value := bytes[start + (i ^ 1)]
			output[i] = if value >= 32 && value <= 126 { value } else { `?` }
		}
		mut end := count
		for end > 0 && output[end - 1] == ` ` { end-- }
		output[end] = 0
	}
}

@[direct_array_access]
fn attribute_raw(bytes &u8) u64 {
	mut value := u64(0)
	unsafe { for i in 0 .. 6 { value |= u64(bytes[i]) << (8 * i) } }
	return value
}

fn health_exit(report &Health) i32 {
	if report.flags & 16 != 0 { return 3 }
	if report.flags & 8 == 0 { return 4 }
	return 0
}

@[direct_array_access]
fn show_health(report &Health) i32 {
	if !health_valid(report) {
		C.printf(c'vinix-volume: invalid health report\n')
		return 1
	}
	mut model := [41]u8{}
	mut serial := [21]u8{}
	mut firmware := [9]u8{}
	ata_text(&report.identify[0], 54, 40, &model[0])
	ata_text(&report.identify[0], 20, 20, &serial[0])
	ata_text(&report.identify[0], 46, 8, &firmware[0])
	C.printf(c'protocol=ata disk=%lu model=%s serial=%s firmware=%s\nsmart_supported=%lu smart_enabled=%lu\n',
		report.disk_id, &model[0], &serial[0], &firmware[0], report.flags & 1, (report.flags >> 1) & 1)
	if report.flags & 8 == 0 { C.printf(c'threshold_status=unavailable\n') }
	else if report.flags & 16 != 0 { C.printf(c'threshold_status=exceeded\n') }
	else { C.printf(c'threshold_status=not-exceeded\n') }
	if report.flags & 4 != 0 {
		revision := u16(report.data[0]) | (u16(report.data[1]) << 8)
		C.printf(c'attribute_revision=%u raw_format=vendor-specific\n', u32(revision))
		for index in 0 .. 30 {
			position := 2 + index * 12
			id := report.data[position]
			if id == 0 { continue }
			flags := u16(report.data[position + 1]) | (u16(report.data[position + 2]) << 8)
			raw := attribute_raw(unsafe { &report.data[position + 5] })
			C.printf(c'attribute=%u flags=0x%04x current=%u worst=%u raw=0x%012lx\n',
				u32(id), u32(flags), u32(report.data[position + 3]), u32(report.data[position + 4]), raw)
		}
	}
	return health_exit(report)
}

fn query_health(path &char) i32 {
	fd := C.open(path, C.O_RDONLY | C.O_CLOEXEC)
	if fd < 0 { C.perror(c'vinix-volume: open health device'); return 1 }
	defer { C.close(fd) }
	mut report := Health{}
	if C.ioctl(fd, u64(0x56560005), unsafe { &report }) != 0 {
		C.perror(c'vinix-volume: health'); return 1
	}
	return show_health(unsafe { &report })
}
