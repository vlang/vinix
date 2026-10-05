// SPDX-License-Identifier: GPL-2.0-or-later
// Inventory reads metadata only; never open a block device for I/O.
module main

fn disk_utility_capacity(unit u64, blocks u64, free u64, available u64) ?[3]u64 {
	if unit == 0 || blocks == 0 || free > blocks || available > free || blocks > u64(-1) / unit { return none }
	return [blocks * unit, (blocks - free) * unit, available * unit]!
}

fn (mut app DiskUtilityApp) collect_devices(directory string) {
	dir := desktop_opendir(directory)
	if dir == unsafe { nil } { app.devices_unavailable = true; return }
	defer { desktop_closedir(dir) }
	mut name := []u8{len: 256}
	defer { unsafe { name.free() } }
	mut inspected := 0
	for desktop_readdir(dir, mut name) {
		inspected++
		if inspected > disk_utility_entry_limit { app.limited = true; break }
		mut length := 0
		for length < name.len && name[length] != 0 { length++ }
		entry := unsafe { tos(name.data, length) }
		if entry == '.' || entry == '..' { continue }
		path := disk_utility_join_path(directory, entry)
		mut info := C.stat{}
		if unsafe { C.lstat(&char(path.str), &info) } == 0 {
			app.device_metadata(path, u32(info.st_mode), i64(info.st_size))
		}
		unsafe { path.free() }
	}
}

fn (mut app DiskUtilityApp) device_metadata(path string, mode u32, bytes i64) {
	if mode & u32(C.S_IFMT) != u32(C.S_IFBLK) { return }
	if app.devices.len >= disk_utility_row_limit || path.len > disk_utility_text_limit { app.limited = true; return }
	app.devices << DiskUtilityDevice{
		path: path.clone()
		bytes: if bytes > 0 { u64(bytes) } else { u64(0) }
	}
}

fn disk_utility_mount_field(field string) ?string {
	// Linux/Vinix's mount renderer escapes exactly these four byte values.
	// Reject malformed escapes and raw NUL before passing paths to libc.
	mut at := 0
	for at < field.len {
		if field[at] == 0 { return none }
		if field[at] == `\\` {
			if at + 3 >= field.len { return none }
			code := unsafe { tos(field.str + at + 1, 3) }
			if code != '040' && code != '011' && code != '012' && code != '134' { return none }
			at += 4
		} else { at++ }
	}
	return system_information_unescape_mount(field)
}

fn (mut app DiskUtilityApp) collect_mounts(path string) {
	// The procfs mount report is regular, but its length is generated on read.
	// A bounded nonblocking descriptor avoids waiting on substituted FIFOs.
	fd := desktop_open_ro_nonblock(path)
	if fd < 0 { app.mounts_unavailable = true; return }
	defer { C.close(fd) }
	mut info := C.stat{}
	if C.fstat(fd, &info) != 0 || u32(info.st_mode) & u32(C.S_IFMT) != u32(C.S_IFREG) {
		app.mounts_unavailable = true
		return
	}
	mut length := 0
	for length < app.buffer.len {
		got := desktop_read(fd, &app.buffer[length], u64(app.buffer.len - length))
		if got < 0 { app.mounts_unavailable = true; return }
		if got == 0 { break }
		length += int(got)
	}
	app.limited = app.limited || length == app.buffer.len
	app.parse_mounts(unsafe { tos(&app.buffer[0], length) }, length == app.buffer.len)
}

fn (mut app DiskUtilityApp) parse_mounts(data string, truncated bool) {
	mut start := 0
	for end in 0 .. data.len + 1 {
		if end < data.len && data[end] != `\n` { continue }
		// A capped read must not turn a partial row into a published mount.
		if end == data.len && truncated { break }
		line := unsafe { tos(data.str + start, end - start) }
		mut fields := [4]string{}
		mut at := 0
		mut count := 0
		for count < 4 && at < line.len {
			for at < line.len && (line[at] == ` ` || line[at] == `\t`) { at++ }
			begin := at
			for at < line.len && line[at] != ` ` && line[at] != `\t` { at++ }
			if at == begin { break }
			fields[count] = unsafe { tos(line.str + begin, at - begin) }
			count++
		}
		if count == 4 && fields[1].len > 0 && fields[1][0] == `/` {
			if app.mounts.len >= disk_utility_row_limit { app.limited = true; break }
			mut overlong := false
			for value in fields { if value.len > disk_utility_text_limit { overlong = true } }
			if overlong { app.limited = true; start = end + 1; continue }
			source := disk_utility_mount_field(fields[0]) or { app.limited = true; start = end + 1; continue }
			target := disk_utility_mount_field(fields[1]) or { unsafe { source.free() }; app.limited = true; start = end + 1; continue }
			// Preserve the exact path for capacity and identity; presentation
			// sanitizes control characters separately.
			mut capacity := [3]u64{}
			mut valid := false
			mut stats := C.vinix_system_information_statvfs{}
			if unsafe { C.vinix_system_information_statvfs(&char(target.str), &stats) } == 0 {
				unit := if stats.f_frsize > 0 { u64(stats.f_frsize) } else { u64(stats.f_bsize) }
				if values := disk_utility_capacity(unit, stats.f_blocks, stats.f_bfree, stats.f_bavail) { capacity = values; valid = true }
			}
			app.mounts << DiskUtilityMount{source: source, target: target, filesystem: fields[2].clone(),
				options: fields[3].clone(), capacity: capacity, capacity_valid: valid}
		}
		start = end + 1
	}
}
