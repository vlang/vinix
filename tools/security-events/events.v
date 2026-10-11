// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// vinix-security-events: keeps what the kernel decided. It reads
// /proc/security_events four times a second and appends what is new to
// /var/log/vinix-audit/events.log, synced to the disk before it considers a
// record kept. Gaps -- records the kernel overwrote before they were read --
// are written down as gaps, with their exact numbers.
//
// The log is set aside and a new one begun when it passes a size, and
// set-aside logs are deleted by count and by age: /etc/vinix/audit.conf,
// eventcore/core.v. Nothing else ever deletes a record.
//
//	vinix-security-events            run until stopped
//	vinix-security-events --once     one pass, for a test or a shutdown
//
// --source FILE, --directory DIR and --settings FILE name other places, for
// tests; --interval-ms N another pace.
//
// It must be root: the kernel shows the stream to nobody else, and the log
// is nobody else's to read. A directory or a log that is a link, is not
// root's, or that others can write is refused rather than written into.
module main

import eventcore
import os
import time

#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>

fn C.fsync(fd int) int
fn C.pread(fd int, buffer voidptr, count usize, offset i64) isize
fn C.fstat(fd int, buf &C.stat) int
fn C.fchmod(fd int, mode u32) int
fn C.usleep(microseconds u32) int
fn C.geteuid() u32

struct Collector {
	source    string
	directory string
	retention eventcore.Retention
	owned     bool // whether the log must be root's
mut:
	cursor eventcore.Cursor
}

fn fail(message string) {
	eprintln('vinix-security-events: ${message}')
	exit(1)
}

fn (c &Collector) log_path() string {
	return os.join_path(c.directory, 'events.log')
}

// The directory as it must be, made if it is not there.
fn (c &Collector) check_directory() ! {
	if !os.exists(c.directory) && !os.is_link(c.directory) {
		os.mkdir_all(c.directory, mode: 0o700) or { return error('cannot create ${c.directory}') }
	}
	info := os.lstat(c.directory) or { return error('cannot inspect ${c.directory}') }
	if info.get_filetype() != .directory {
		return error('${c.directory} is not a directory')
	}
	if info.mode & 0o022 != 0 || (c.owned && info.uid != 0) {
		return error('${c.directory} is not root\'s alone')
	}
	os.chmod(c.directory, 0o700) or {}
}

// The log, open for appending: a regular file with one name, root's, that
// nobody else can read.
fn (c &Collector) open_log() !int {
	path := c.log_path()
	fd := C.open(&char(path.str), C.O_WRONLY | C.O_APPEND | C.O_CREAT | C.O_NOFOLLOW | C.O_CLOEXEC,
		0o600)
	if fd < 0 {
		return error('cannot open ${path}')
	}
	mut info := C.stat{}
	if C.fstat(fd, &info) != 0 || u32(info.st_mode) & 0o170000 != 0o100000 || info.st_nlink != 1
		|| (c.owned && info.st_uid != 0) {
		C.close(fd)
		return error('${path} is not a log this collector may write')
	}
	if u32(info.st_mode) & 0o077 != 0 && C.fchmod(fd, 0o600) != 0 {
		C.close(fd)
		return error('cannot protect ${path}')
	}
	// A collector that was stopped in the middle of a write, or a machine
	// that lost power, leaves half a line. What is appended starts on a
	// line of its own.
	if info.st_size > 0 {
		mut last := [1]u8{}
		check := C.open(&char(path.str), C.O_RDONLY | C.O_NOFOLLOW | C.O_CLOEXEC)
		if check >= 0 {
			if C.pread(check, &last[0], 1, i64(info.st_size) - 1) == 1 && last[0] != `\n` {
				C.write(fd, c'\n', 1)
			}
			C.close(check)
		}
	}
	return fd
}

// The end of the log as it is, to pick up from after a restart.
fn (c &Collector) read_tail() string {
	path := c.log_path()
	info := os.lstat(path) or { return '' }
	if info.get_filetype() != .regular || info.size == 0 {
		return ''
	}
	size := info.size
	mut file := os.open(path) or { return '' }
	defer { file.close() }
	wanted := if size > 65536 { u64(65536) } else { size }
	mut buffer := []u8{len: int(wanted)}
	got := file.read_from(size - wanted, mut buffer) or { return '' }
	text := buffer[..got].bytestr()
	// The first line of a window into the middle of a file is half a line.
	return if size > wanted { text.all_after('\n') } else { text }
}

// Set the log aside when it has grown past its size, and delete what the
// settings say is no longer kept.
fn (c &Collector) rotate() {
	path := c.log_path()
	// Only a log this collector would also write to is set aside: anything
	// else under that name stays where open_log() will refuse it.
	info := os.lstat(path) or { os.Stat{} }
	if info.get_filetype() == .regular && i64(info.size) >= c.retention.max_bytes {
		os.rm('${path}.${c.retention.keep_files}') or {}
		for index := c.retention.keep_files - 1; index >= 1; index-- {
			os.rename('${path}.${index}', '${path}.${index + 1}') or {}
		}
		os.rename(path, '${path}.1') or {}
	}
	// Beyond the count: a setting that was lowered.
	for index in c.retention.keep_files + 1 .. 65 {
		os.rm('${path}.${index}') or {}
	}
	if c.retention.max_age_days > 0 {
		oldest := time.now().unix() - i64(c.retention.max_age_days) * 86400
		for index in 1 .. c.retention.keep_files + 1 {
			aside := '${path}.${index}'
			if os.exists(aside) && os.file_last_mod_unix(aside) < oldest {
				os.rm(aside) or {}
			}
		}
	}
}

// One pass: read, append what is new, sync. Returns how many lines went in.
fn (mut c Collector) collect() !int {
	text := os.read_file(c.source) or { return error('cannot read ${c.source}') }
	snapshot := eventcore.parse_snapshot(text) or { return error('${c.source}: ${err.msg()}') }
	lines, next := eventcore.advance(c.cursor, snapshot, time.now().unix())
	if lines.len == 0 {
		c.cursor = next
		return 0
	}
	c.rotate()
	fd := c.open_log()!
	data := lines.join('\n') + '\n'
	mut done := 0
	for done < data.len {
		put := C.write(fd, unsafe { data.str + done }, usize(data.len - done))
		if put <= 0 {
			C.close(fd)
			return error('cannot write ${c.log_path()}')
		}
		done += int(put)
	}
	// Kept means on the disk. Only then does the collector move on; a
	// failure here leaves the cursor where it was and the records are
	// written again, which a reader can see by their numbers.
	if C.fsync(fd) != 0 {
		C.close(fd)
		return error('cannot sync ${c.log_path()}')
	}
	C.close(fd)
	c.cursor = next
	return lines.len
}

fn main() {
	mut source := '/proc/security_events'
	mut directory := '/var/log/vinix-audit'
	mut settings := '/etc/vinix/audit.conf'
	mut once := false
	mut interval := 250
	mut args := os.args[1..].clone()
	for args.len > 0 {
		option := args[0]
		if option == '--once' {
			once = true
			args = args[1..].clone()
			continue
		}
		if args.len < 2 {
			fail('${option} needs a value')
		}
		match option {
			'--source' { source = args[1] }
			'--directory' { directory = args[1] }
			'--settings' { settings = args[1] }
			'--interval-ms' { interval = args[1].int() }
			else { fail('unknown option ${option}') }
		}
		args = args[2..].clone()
	}
	if interval < 10 || interval > 60000 {
		fail('--interval-ms must be between 10 and 60000')
	}
	owned := C.geteuid() == 0
	mut retention := eventcore.Retention{}
	if os.exists(settings) {
		info := os.lstat(settings) or {
			fail('cannot inspect ${settings}')
			return
		}
		if info.get_filetype() != .regular || info.mode & 0o022 != 0 || (owned && info.uid != 0) {
			fail('${settings} is not root\'s alone')
		}
		retention = eventcore.parse_retention(os.read_file(settings) or { '' }) or {
			fail('${settings}: ${err.msg()}')
			return
		}
	}
	mut collector := Collector{
		source:    source
		directory: directory
		retention: retention
		owned:     owned
	}
	collector.check_directory() or { fail(err.msg()) }
	collector.cursor = eventcore.cursor_from_log(collector.read_tail())
	for {
		mut failed := false
		collector.collect() or {
			eprintln('vinix-security-events: ${err.msg()}')
			failed = true
			0
		}
		if once {
			exit(if failed { 1 } else { 0 })
		}
		C.usleep(u32(interval) * 1000)
	}
}
