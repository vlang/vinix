// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <sys/statvfs.h>
#define vinix_system_information_statvfs statvfs

// A distinct V name avoids os's private, partial C.statvfs declaration while
// the C macro still selects the platform header's complete native structure.
struct C.vinix_system_information_statvfs {
	f_bsize usize
	f_frsize usize
	f_blocks u64
	f_bfree u64
	f_bavail u64
}

fn C.vinix_system_information_statvfs(&char, &C.vinix_system_information_statvfs) int

fn system_information_capacity(unit u64, blocks u64, free u64, available u64) ?[3]u64 {
	// Generic Vinix resources currently return zero blocks. That is missing
	// capacity information, not a full or zero-sized volume.
	if unit == 0 || blocks == 0 || free > blocks || available > blocks || blocks > u64(-1) / unit { return none }
	return [blocks * unit, (blocks - free) * unit, available * unit]!
}

fn system_information_unescape_mount(text string) string {
	mut out := []u8{cap: text.len}
	unsafe { out.flags |= .noslices }
	mut at := 0
	for at < text.len {
		if text[at] == `\\` && at + 3 < text.len {
			code := unsafe { tos(text.str + at + 1, 3) }
			ch := match code { '040' { u8(` `) } '011' { u8(`\t`) } '012' { u8(`\n`) } '134' { u8(`\\`) } else { u8(0) } }
			if ch != 0 { out << ch; at += 4; continue }
		}
		out << text[at]
		at++
	}
	result := if out.len > 0 { unsafe { tos(out.data, out.len).clone() } } else { '' }
	unsafe { out.free() }
	return result
}

fn (mut app SystemInformationApp) collect_mounts(path string) {
	app.sections[2].add('system_information.source', path.clone(), true)
	data := app.read(path) or { app.sections[2].add('system_information.unavailable', '', false); return }
	app.sections[2].limited = app.read_limited
	mut start := 0
	for end in 0 .. data.len + 1 {
		if end < data.len && data[end] != `\n` { continue }
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
		if count == 4 {
			source := system_information_unescape_mount(fields[0])
			target := system_information_unescape_mount(fields[1])
			mount := '${target} (${fields[2]}; ${source}; ${fields[3]})'
			app.value(2, 'system_information.mount', mount)
			unsafe { source.free(); mount.free() }
			mut stats := C.vinix_system_information_statvfs{}
			if unsafe { C.vinix_system_information_statvfs(&char(target.str), &stats) } == 0 {
				unit := if stats.f_frsize > 0 { u64(stats.f_frsize) } else { u64(stats.f_bsize) }
				if capacity := system_information_capacity(unit, stats.f_blocks, stats.f_bfree, stats.f_bavail) {
					total := capacity[0].str()
					used := capacity[1].str()
					available := capacity[2].str()
					app.sections[2].add('system_information.capacity', '${total} / ${used} / ${available}', false)
					unsafe { total.free(); used.free(); available.free() }
				} else { app.sections[2].add('system_information.capacity_unavailable', '', false) }
			} else { app.sections[2].add('system_information.capacity_unavailable', '', false) }
			unsafe { target.free() }
		}
		start = end + 1
	}
	if app.sections[2].rows.len == 1 { app.sections[2].add('system_information.unavailable', '', false) }
}

struct SystemInformationPackageParser {
mut:
	name string
	version string
	count int
}

fn (mut parser SystemInformationPackageParser) finish(mut section SystemInformationSection) {
	if parser.name.len > 0 {
		if parser.version.len > 0 { section.add('', '${parser.name} ${parser.version}', false) }
		else { section.add('system_information.package_version_unavailable', parser.name.clone(), false) }
		parser.count++
	}
	unsafe { parser.name.free(); parser.version.free() }
	parser.name = ''
	parser.version = ''
}

fn (mut parser SystemInformationPackageParser) line(mut section SystemInformationSection, line string) {
	if line.len == 0 { parser.finish(mut section); return }
	if line.starts_with('P:') {
		if parser.name.len > 0 { parser.finish(mut section) }
		if line.len - 2 > system_information_text_limit { section.limited = true }
		parser.name = system_information_text(unsafe { tos(line.str + 2, line.len - 2) })
	} else if line.starts_with('V:') && parser.name.len > 0 {
		if line.len - 2 > system_information_text_limit { section.limited = true }
		unsafe { parser.version.free() }
		parser.version = system_information_text(unsafe { tos(line.str + 2, line.len - 2) })
	}
}

fn (mut app SystemInformationApp) collect_packages(path string) {
	app.sections[3].add('system_information.source', path.clone(), true)
	fd := desktop_open_ro_nonblock(path)
	if fd < 0 { app.sections[3].add('system_information.unavailable', '', false); return }
	defer { C.close(fd) }
	mut parser := SystemInformationPackageParser{}
	mut line := [1024]u8{}
	mut length := 0
	mut overlong := false
	mut total := 0
	mut eof := false
	// File ownership records can dwarf package metadata. Stream them rather
	// than retaining the whole database; cap one refresh at eight MiB.
	for total < 8 * 1024 * 1024 && !app.sections[3].limited {
		got := desktop_read(fd, &app.buffer[0], u64(app.buffer.len - 1))
		if got < 0 { app.sections[3].add('system_information.read_failed', '', false); break }
		if got == 0 { eof = true; break }
		total += int(got)
		for at in 0 .. int(got) {
			ch := app.buffer[at]
			if ch == `\n` {
				if overlong && length >= 2 && (line[0] == `P` || line[0] == `V`) && line[1] == `:` { app.sections[3].limited = true }
				parser.line(mut app.sections[3], unsafe { tos(&line[0], length) })
				length = 0
				overlong = false
			} else if length < line.len { line[length] = ch; length++ }
			else { overlong = true }
		}
	}
	if eof {
		if length > 0 { parser.line(mut app.sections[3], unsafe { tos(&line[0], length) }) }
		parser.finish(mut app.sections[3])
	} else {
		app.sections[3].limited = true
		unsafe { parser.name.free(); parser.version.free() }
	}
	if parser.count == 0 && eof { app.sections[3].add('system_information.packages_empty', '', false) }
}
