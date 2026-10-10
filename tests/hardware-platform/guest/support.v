// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// What every scenario is written with: a line on the serial port, a check
// that is remembered, files read and written whole, and the way out.
//
// The host sees nothing of this program but its lines, so each line is one
// write() of a complete line. The files a scenario reads and writes are
// mostly sysfs attributes, where one write() is one command and its errno is
// the answer; they are opened, used and closed here with the system calls
// themselves, so that nothing buffers a write or turns its error into
// success at close.
module main

import os

#include <fcntl.h>
#include <unistd.h>
#include <sys/reboot.h>

fn C.sync()
fn C.reboot(command i32) i32
fn C.fsync(fd i32) i32
fn C.pread(fd i32, buffer voidptr, count usize, offset i64) isize
fn C.pwrite(fd i32, buffer voidptr, count usize, offset i64) isize

// Where the host listens. On AArch64 the console is the PL011 the kernel
// logs to as well; an x86-64 kernel keeps its own messages off the serial
// port, and the port is a device of its own.
const console_path = $if arm64 {
	'/dev/console'
} $else {
	'/dev/com1'
}

// RB_POWER_OFF, as reboot(2) takes it.
const reboot_power_off = 0x4321fedc
// RB_AUTOBOOT.
const reboot_restart = 0x01234567

struct Test {
mut:
	scenario string
	console  int = 1
	failures int
	stays_up bool
	// End by resetting the machine instead of turning it off.
	restarts bool
}

fn new_test() Test {
	mut t := Test{}
	fd := C.open(&char(console_path.str), C.O_WRONLY)
	if fd >= 0 {
		t.console = fd
	}
	return t
}

// Prints one line.
fn (mut t Test) say(line string) {
	text := line + '\n'
	C.write(t.console, text.str, usize(text.len))
}

// A line the host may be waiting for before it acts on the machine.
fn (mut t Test) step(text string) {
	t.say('HWTEST STEP ${text}')
}

// Something measured that belongs in the host's report beside the verdict.
fn (mut t Test) info(text string) {
	t.say('HWTEST INFO ${text}')
}

// Records a failure unless `condition` holds, and returns it, so a caller
// can skip what makes no sense after a check has failed. The scenario goes
// on either way: one run should report everything that is wrong.
fn (mut t Test) check(condition bool, message string) bool {
	if !condition {
		t.failures++
		t.say('HWTEST FAIL ${t.scenario}: ${message}')
	}
	return condition
}

// The scenario leaves the machine running when it is done: the host ends it.
fn (mut t Test) stay_up() {
	t.stays_up = true
}

fn sleep_ms(milliseconds int) {
	C.usleep(u32(milliseconds) * 1000)
}

// Waits for the rest of time. PID 1 must not return: the kernel panics when
// init exits, and that would be reported as the scenario's failure.
fn idle() {
	for {
		sleep_ms(1000)
	}
}

fn power_off() {
	C.sync()
	C.reboot(reboot_power_off)
	// Still here: the machine did not go off. The host notices that it is
	// still running, which is the right report.
	idle()
}

// Prints the verdict and ends the scenario.
fn (mut t Test) finish() {
	// On AArch64 kernel messages share the port, byte by byte: a driver
	// still reporting what the last write to sysfs did would land in the
	// middle of the verdict, and the host matches whole lines. Let it finish.
	sleep_ms(200)
	if t.failures == 0 {
		t.say('HWTEST PASS ${t.scenario}')
	} else {
		t.say('HWTEST FAIL ${t.scenario}')
	}
	if t.stays_up {
		idle()
	}
	if t.restarts && t.failures == 0 {
		C.sync()
		C.reboot(reboot_restart)
		// Still here: the machine did not reset, and the host sees that it
		// is still running.
		idle()
	}
	power_off()
}

fn errno_error(path string) IError {
	code := C.errno
	return error_with_code('${path}: ${os.posix_get_error_msg(code)}', code)
}

// The whole content of a file.
fn read_text(path string) !string {
	fd := C.open(&char(path.str), C.O_RDONLY)
	if fd < 0 {
		return errno_error(path)
	}
	defer {
		C.close(fd)
	}
	mut content := []u8{}
	mut chunk := []u8{len: 4096}
	for {
		count := C.read(fd, chunk.data, usize(chunk.len))
		if count < 0 {
			return errno_error(path)
		}
		if count == 0 {
			break
		}
		content << chunk[..count]
	}
	return content.bytestr()
}

// A file's content with the white space around it removed, or '' when it
// cannot be read: for attributes that are compared with a word.
fn read_word(path string) string {
	text := read_text(path) or { return '' }
	return text.trim_space()
}

// Writes `text` to an existing file with one write().
fn write_text(path string, text string) ! {
	fd := C.open(&char(path.str), C.O_WRONLY | C.O_TRUNC)
	if fd < 0 {
		return errno_error(path)
	}
	defer {
		C.close(fd)
	}
	count := C.write(fd, text.str, usize(text.len))
	if count < 0 {
		return errno_error(path)
	}
	if count != text.len {
		return error('${path}: wrote ${count} of ${text.len} bytes')
	}
}

// The names in a directory, sorted.
fn list_dir(path string) ![]string {
	mut names := os.ls(path) or { return error('${path}: ${err.msg()}') }
	names.sort()
	return names
}

// Polls `condition` until it holds or the time is up, and says which.
fn wait_until(milliseconds int, condition fn () bool) bool {
	mut waited := 0
	for {
		if condition() {
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

// One field of /proc/meminfo, in kB.
fn meminfo_kb(field string) !int {
	text := read_text('/proc/meminfo')!
	for line in text.split_into_lines() {
		if line.starts_with(field + ':') {
			words := line.all_after(':').fields()
			if words.len > 0 {
				return words[0].int()
			}
		}
	}
	return error('/proc/meminfo has no ${field}')
}

// The bytes of a disk test pattern; the host checks the disk image against
// the same sequence (hwhost.pattern_bytes).
fn pattern_bytes(seed u8, length int) []u8 {
	mut bytes := []u8{len: length}
	for i in 0 .. length {
		bytes[i] = u8(int(seed) + i * 7)
	}
	return bytes
}

// Writes a pattern to a device at `offset`, has the device commit it, and
// reads it back.
fn write_pattern(path string, offset i64, seed u8, length int) ! {
	written := pattern_bytes(seed, length)
	fd := C.open(&char(path.str), C.O_RDWR)
	if fd < 0 {
		return errno_error(path)
	}
	defer {
		C.close(fd)
	}
	if C.pwrite(fd, written.data, usize(length), offset) != length {
		return error('write: ${os.posix_get_error_msg(C.errno)}')
	}
	if C.fsync(fd) != 0 {
		return error('fsync: ${os.posix_get_error_msg(C.errno)}')
	}
	mut found := []u8{len: length}
	if C.pread(fd, found.data, usize(length), offset) != length {
		return error('read back: ${os.posix_get_error_msg(C.errno)}')
	}
	for i in 0 .. length {
		if found[i] != written[i] {
			return error('byte ${i} read back as 0x${found[i].hex()}, written as 0x${written[i].hex()}')
		}
	}
}

// What the kernel heap holds, from /proc/slabinfo: the objects allocated in
// every size class, and the pages behind allocations too big for a class.
struct HeapUsage {
	objects     int
	large_pages int
}

fn heap_usage() !HeapUsage {
	text := read_text('/proc/slabinfo')!
	mut objects := 0
	mut large_pages := -1
	for line in text.split_into_lines() {
		words := line.fields()
		if words.len != 4 || words[0].starts_with('#') {
			continue
		}
		if words[0] == 'large' {
			large_pages = words[3].int()
		} else {
			objects += words[2].int()
		}
	}
	if objects == 0 || large_pages < 0 {
		return error('/proc/slabinfo is not in the form this expects')
	}
	return HeapUsage{
		objects:     objects
		large_pages: large_pages
	}
}

// How many more live heap objects a measured loop may leave without it being
// a leak. Taking the measurement is not free: reading and taking apart
// /proc/slabinfo grows this program's own heap, which nothing here ever
// frees, and each new page of it costs the kernel an object or two. That has
// been a dozen objects at most; a loop of fifty or a hundred rounds that
// loses one object per round is far over this.
const heap_noise_objects = 30
