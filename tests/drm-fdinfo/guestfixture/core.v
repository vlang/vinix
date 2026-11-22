// SPDX-License-Identifier: GPL-2.0-or-later
module guestfixture

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/reboot.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.read(i32, voidptr, u64) i64
fn C.ioctl(i32, i32, ...) i32
fn C.__errno_location() &i32
fn C.dup(i32) i32
fn C.fork() i32
fn C._exit(i32)
fn C.waitpid(i32, &i32, i32) i32
fn C.snprintf(voidptr, u64, &char, ...) i32
fn C.strstr(voidptr, &char) &char
fn C.strlen(&char) u64
fn C.strtoull(&char, &&char, i32) u64
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.reboot(i32) i32
fn C.pause() i32

fn read_fdinfo(fd i32, buffer voidptr, capacity u64) bool {
	if fd < 0 { return false }
	mut path := [64]u8{}
	C.snprintf(&path[0], sizeof(path), c'/proc/self/fdinfo/%d', fd)
	info := C.open(unsafe { &char(&path[0]) }, C.O_RDONLY)
	if info < 0 { return false }
	count := C.read(info, buffer, capacity - 1)
	C.close(info)
	return count > 0
}

// Zero means fdinfo has no DRM client line. A negative result is a read or
// format error.
fn client_id(fd i32) i64 {
	mut buffer := [512]u8{}
	if !read_fdinfo(fd, &buffer[0], sizeof(buffer)) { return -1 }
	key := c'\ndrm-client-id:\t'
	line := C.strstr(&buffer[0], key)
	if line == unsafe { nil } { return 0 }
	value := unsafe { line + C.strlen(key) }
	mut end := &char(unsafe { nil })
	id := C.strtoull(value, &end, 10)
	if end == value || unsafe { *end } != char(10) { return -1 }
	return i64(id)
}

fn test_open_order() bool {
	card := c'/dev/dri/card0'
	first := C.open(card, C.O_RDWR)
	path := C.open(card, C.O_PATH)
	ordinary := C.open(c'/dev/null', C.O_RDONLY)
	second := C.open(card, C.O_RDWR)
	if first < 0 || second < 0 || path < 0 || ordinary < 0 { return false }

	newer := client_id(second)
	older := client_id(first)
	C.printf(c'DRM client IDs in open order: %ld %ld\n', older, newer)
	if older <= 0 || newer != older + 1 { return false }
	if client_id(path) != 0 || client_id(ordinary) != 0 { return false }
	dup := C.dup(first)
	if dup < 0 { return false }
	C.close(first)
	if client_id(dup) != older { return false }

	child := C.fork()
	if child == 0 { C._exit(if client_id(dup) == older { 0 } else { 1 }) }
	mut status := i32(0)
	if child < 0 || C.waitpid(child, &status, 0) != child || status != 0 { return false }

	reopened := C.open(card, C.O_RDWR)
	passed := reopened == first && client_id(reopened) == newer + 1 && client_id(second) == newer
	C.close(reopened)
	C.close(dup)
	C.close(second)
	C.close(ordinary)
	C.close(path)
	return passed
}

struct ClientNameRequest {
	length u64
	address u64
}

fn set_name(fd i32, address u64, length u64) i32 {
	request := ClientNameRequest{length: length, address: address}
	result := C.ioctl(fd, i32(u32(0xc01064d1)), &request)
	return if result == -1 { unsafe { *C.__errno_location() } } else { result }
}

fn has_name(fd i32, name &char) bool {
	mut buffer := [512]u8{}
	if !read_fdinfo(fd, &buffer[0], sizeof(buffer)) { return false }
	if name == unsafe { nil } {
		return C.strstr(&buffer[0], c'\ndrm-client-name:\t') == unsafe { nil }
	}
	mut expected := [96]u8{}
	C.snprintf(&expected[0], sizeof(expected), c'\ndrm-client-name:\t%s\n', name)
	return C.strstr(&buffer[0], unsafe { &char(&expected[0]) }) != unsafe { nil }
}

fn test_client_names() bool {
	card := c'/dev/dri/card0'
	fd := C.open(card, C.O_RDWR)
	other := C.open(card, C.O_RDWR)
	path := C.open(card, C.O_PATH)
	alias := C.dup(fd)
	if fd < 0 || other < 0 || path < 0 || alias < 0 { return false }
	defer {
		C.close(alias)
		C.close(path)
		C.close(other)
		C.close(fd)
	}
	if !has_name(fd, unsafe { nil }) { return false }
	name := c'Mesa-worker_0'
	if set_name(alias, u64(name), C.strlen(name)) != 0
		|| !has_name(fd, name) || !has_name(other, unsafe { nil }) { return false }
	if set_name(path, u64(name), C.strlen(name)) != C.EBADF { return false }

	long_name := c'0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-~'
	if C.strlen(long_name) != 64 || set_name(fd, u64(long_name), 64) != 0
		|| !has_name(alias, long_name) { return false }
	invalid := [u8(0), 0x09, 0x20, 0x7f, 0x80]!
	for i in 0 .. invalid.len {
		if set_name(fd, u64(unsafe { &invalid[i] }), 1) != C.EINVAL { return false }
	}
	if set_name(fd, 0, 65) != C.EINVAL || set_name(fd, 0, 1) != C.EFAULT
		|| set_name(fd, ~u64(0), 2) != C.EFAULT || !has_name(alias, long_name) { return false }

	if set_name(alias, ~u64(0), 0) != 0 || !has_name(fd, unsafe { nil }) { return false }
	if set_name(fd, u64(name), C.strlen(name)) != 0 { return false }
	// A short read/write request supplies only the zero length.
	mut zero_length := u64(0)
	if C.ioctl(fd, i32(u32(0xc00864d1)), &zero_length) != 0
		|| !has_name(alias, unsafe { nil }) { return false }
	return true
}

@[export: 'main']
pub fn run() i32 {
	if test_open_order() {
		C.puts(c'VINIX DRM CLIENT IDS: PASS')
	} else {
		C.puts(c'DRM CLIENT IDS FAIL: expected open-order IDs and shared duplicates')
	}
	if test_client_names() {
		C.puts(c'VINIX DRM CLIENT NAMES: PASS')
	} else {
		C.puts(c'DRM CLIENT NAMES FAIL: expected validated names shared by duplicate descriptors')
	}
	C.fflush(unsafe { nil })
	C.reboot(C.RB_POWER_OFF)
	for { C.pause() }
	return 1
}
