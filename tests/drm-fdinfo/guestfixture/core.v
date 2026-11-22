// SPDX-License-Identifier: GPL-2.0-or-later
module guestfixture

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/reboot.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.read(i32, voidptr, u64) i64
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

// Zero means fdinfo has no DRM client line. A negative result is a read or
// format error.
fn client_id(fd i32) i64 {
	if fd < 0 { return -1 }
	mut path := [64]u8{}
	C.snprintf(&path[0], sizeof(path), c'/proc/self/fdinfo/%d', fd)
	info := C.open(unsafe { &char(&path[0]) }, C.O_RDONLY)
	if info < 0 { return -1 }
	mut buffer := [512]u8{}
	count := C.read(info, &buffer[0], sizeof(buffer) - 1)
	C.close(info)
	if count <= 0 { return -1 }
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

@[export: 'main']
pub fn run() i32 {
	if test_open_order() {
		C.puts(c'VINIX DRM CLIENT IDS: PASS')
	} else {
		C.puts(c'DRM CLIENT IDS FAIL: expected open-order IDs and shared duplicates')
	}
	C.fflush(unsafe { nil })
	C.reboot(C.RB_POWER_OFF)
	for { C.pause() }
	return 1
}
