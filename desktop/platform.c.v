// SPDX-License-Identifier: GPL-2.0-or-later
// V implementation of the desktop's POSIX boundary. Only declarations and
// constants come from libc headers; there are no custom C function bodies.
// Import vlib's declarations rather than inventing incompatible duplicates.
module main

import os as _
import time as _
import term.termios

#include <dirent.h>

#include <errno.h>

#include <fcntl.h>

#include <sys/ioctl.h>

#include <sys/mman.h>

#include <sys/stat.h>

#include <termios.h>

#include <time.h>

#include <unistd.h>

fn C.fstat(fd int, buf &C.stat) int

fn C.mmap(base voidptr, length usize, prot int, flags int, fd int, offset i64) voidptr

fn C.munmap(base voidptr, length usize) int

// Match vlib/net's declaration if a hosted application also imports it.
fn C.fcntl(fd int, cmd int, arg ...voidptr) int

fn desktop_open_rw(path string) int {
	return C.open(&char(path.str), C.O_RDWR)
}

fn desktop_open_ro_nonblock(path string) int {
	return C.open(&char(path.str), C.O_RDONLY | C.O_NONBLOCK)
}

fn desktop_close(fd int) int {
	return C.close(fd)
}

fn desktop_read(fd int, buffer voidptr, count u64) i64 {
	// vlib's POSIX read declaration returns int. Our bounded device packets
	// are tiny; refuse a count that could make that result truncate.
	if count > 0x7fffffff {
		return -1
	}
	return i64(C.read(fd, buffer, usize(count)))
}

fn desktop_ioctl(fd int, request u64, argument voidptr) int {
	return termios.ioctl(fd, request, argument)
}

fn desktop_mmap_shared(fd int, length u64) voidptr {
	mapping := C.mmap(unsafe { nil }, usize(length), C.PROT_READ | C.PROT_WRITE, C.MAP_SHARED, fd, 0)
	if mapping == C.MAP_FAILED {
		return unsafe { nil }
	}
	return mapping
}

fn desktop_munmap(base voidptr, length u64) int {
	return C.munmap(base, usize(length))
}

struct TerminalState {
mut:
	attributes         termios.Termios
	flags              int = -1
	restore_attributes bool
	restore_flags      bool
}

fn terminal_input_raw(saved termios.Termios) termios.Termios {
	mut raw := saved
	raw.c_lflag &= termios.invert(termios.flag(C.ICANON | C.ECHO | C.ISIG))
	raw.c_cc[C.VMIN] = 0
	raw.c_cc[C.VTIME] = 0
	return raw
}

fn desktop_terminal_raw(fd int) TerminalState {
	mut saved := TerminalState{}
	if termios.tcgetattr(fd, mut saved.attributes) == 0 {
		mut raw := terminal_input_raw(saved.attributes)
		saved.restore_attributes = termios.tcsetattr(fd, C.TCSANOW, mut raw) == 0
	}
	saved.flags = C.fcntl(fd, C.F_GETFL)
	if saved.flags >= 0 {
		// Preserve all existing descriptor flags, and restore them on exit.
		saved.restore_flags = C.fcntl(fd, C.F_SETFL, saved.flags | C.O_NONBLOCK) == 0
	}
	return saved
}

fn desktop_terminal_restore(fd int, mut saved TerminalState) {
	if saved.restore_attributes {
		termios.tcsetattr(fd, C.TCSANOW, mut saved.attributes)
		saved.restore_attributes = false
	}
	if saved.restore_flags {
		C.fcntl(fd, C.F_SETFL, saved.flags)
		saved.restore_flags = false
	}
}

fn desktop_realtime() (i64, i64) {
	mut stamp := C.timespec{}
	if C.clock_gettime(C.CLOCK_REALTIME, &stamp) != 0 {
		return -1, 0
	}
	return stamp.tv_sec, stamp.tv_nsec
}

// UINT64_MAX is an explicit failed-clock sentinel, shared by both clients.
fn desktop_monotonic_ms() u64 {
	mut stamp := C.timespec{}
	if C.clock_gettime(C.CLOCK_MONOTONIC, &stamp) != 0 || stamp.tv_sec < 0
		|| stamp.tv_nsec < 0 || stamp.tv_nsec >= 1_000_000_000
		|| u64(stamp.tv_sec) > (~u64(0) - 999) / 1000 {
		return ~u64(0)
	}
	return u64(stamp.tv_sec) * 1000 + u64(stamp.tv_nsec) / 1_000_000
}

fn desktop_sleep_ms(milliseconds i64) {
	if milliseconds <= 0 {
		return
	}
	mut request := C.timespec{ tv_sec: milliseconds / 1000, tv_nsec: (milliseconds % 1000) * 1_000_000 }
	mut remainder := C.timespec{}
	for _ in 0 .. 4 {
		if C.nanosleep(&request, &remainder) == 0 || C.errno != C.EINTR {
			return
		}
		request = remainder
	}
}

// Read a whole file into a caller-supplied buffer, returning the byte count or
// -1. The desktop only ever does this for a wallpaper, whose size it has
// already asked for with desktop_stat().
fn desktop_read_file(path string, buffer voidptr, max u64) i64 {
	fd := C.open(&char(path.str), C.O_RDONLY)
	if fd < 0 {
		return -1
	}
	mut total := u64(0)
	for total < max {
		got := desktop_read(fd, unsafe { voidptr(&u8(buffer) + total) }, max - total)
		if got < 0 {
			C.close(fd)
			return -1
		}
		if got == 0 {
			break
		}
		total += u64(got)
	}
	C.close(fd)
	return i64(total)
}

fn desktop_opendir(path string) voidptr {
	return C.opendir(&char(path.str))
}

// Keep the file browser's bounded iteration without requiring a copied
// dirent layout. vlib declares d_name; file type is obtained by stat below.
fn desktop_readdir(dir voidptr, mut name []u8) bool {
	if name.len == 0 {
		return false
	}
	entry := C.readdir(dir)
	if entry == unsafe { nil } {
		return false
	}
	mut i := 0
	for i + 1 < name.len && i < 255 && entry.d_name[i] != 0 {
		name[i] = u8(entry.d_name[i])
		i++
	}
	name[i] = 0
	return true
}

fn desktop_closedir(dir voidptr) {
	if dir != unsafe { nil } { C.closedir(dir) }
}

struct DesktopFileInfo {
	size   u64
	is_dir bool
}

fn desktop_stat(path string) ?DesktopFileInfo {
	mut info := C.stat{}
	if unsafe { C.stat(&char(path.str), &info) } != 0 {
		return none
	}
	return DesktopFileInfo{
		size: u64(info.st_size)
		is_dir: (u32(info.st_mode) & u32(C.S_IFMT)) == u32(C.S_IFDIR)
	}
}

struct PosixDeviceIO {}

fn device_errno(value int) DeviceError {
	return match value {
		C.ENOENT, C.ENODEV, C.ENXIO { .unavailable }
		C.EACCES, C.EPERM, C.EROFS { .permission }
		C.EINTR { .interrupted }
		else { .io }
	}
}

fn (mut io PosixDeviceIO) open(path string, writable bool) (int, DeviceError) {
	mode := if writable { C.O_RDWR } else { C.O_RDONLY }
	fd := C.open(&char(path.str), mode | C.O_NONBLOCK | C.O_CLOEXEC)
	if fd < 0 {
		return fd, device_errno(C.errno)
	}
	return fd, DeviceError.none
}

fn (mut io PosixDeviceIO) read(fd int, mut buffer []u8) (int, DeviceError) {
	count := C.read(fd, buffer.data, usize(buffer.len))
	if count < 0 {
		return count, device_errno(C.errno)
	}
	return count, DeviceError.none
}

fn (mut io PosixDeviceIO) write(fd int, buffer []u8) (int, DeviceError) {
	count := C.write(fd, buffer.data, usize(buffer.len))
	if count < 0 {
		return count, device_errno(C.errno)
	}
	return count, DeviceError.none
}

fn (mut io PosixDeviceIO) close(fd int) DeviceError {
	if C.close(fd) < 0 {
		return device_errno(C.errno)
	}
	return .none
}

fn (mut io PosixDeviceIO) is_character(fd int) (bool, DeviceError) {
	mut info := C.stat{}
	if C.fstat(fd, &info) < 0 {
		return false, device_errno(C.errno)
	}
	return (u32(info.st_mode) & u32(C.S_IFMT)) == u32(C.S_IFCHR), DeviceError.none
}
