// SPDX-License-Identifier: GPL-2.0-or-later
// Native guest check of the real /dev/pointer ABI and QEMU wheel delivery.
@[translated]
module fixture

#include <fcntl.h>
#include <stdio.h>
#include <time.h>
#include <unistd.h>

struct C.timespec {
mut:
	tv_sec i64
	tv_nsec i64
}

fn C.open(&char, i32, ...) i32
fn C.read(i32, voidptr, usize) i64
fn C.printf(&char, ...) i32
fn C.fflush(voidptr) i32
fn C.nanosleep(&C.timespec, voidptr) i32

@[export: 'main']
pub fn main() i32 {
	fd := C.open(c'/dev/pointer', i32(0))
	if fd < 0 { return 1 }
	mut packet := [9]i32{}
	// A legacy reader receives only eight words, even on the extended ABI.
	packet[8] = 12345
	if C.read(fd, &packet[0], usize(32)) != 32 || packet[8] != 12345 { return 2 }
	C.printf(c'POINTER_SCROLL READY\n')
	C.fflush(unsafe { nil })
	mut seen := i32(0)
	delay := C.timespec{tv_nsec: 1000000}
	for seen < 4 {
		if C.read(fd, &packet[0], usize(36)) != 36 { return 3 }
		if packet[7] != 0 || packet[8] != 0 {
			dx := packet[8]
			dy := packet[7]
			// Wheel deltas are consumed once, independently of their sign/axis.
			if C.read(fd, &packet[0], usize(36)) != 36 || packet[7] != 0 || packet[8] != 0 { return 4 }
			C.printf(c'POINTER_SCROLL dx=%d dy=%d\n', dx, dy)
			C.fflush(unsafe { nil })
			seen++
		}
		C.nanosleep(&delay, unsafe { nil })
	}
	C.printf(c'POINTER_SCROLL PASS\n')
	C.fflush(unsafe { nil })
	for { C.nanosleep(&delay, unsafe { nil }) }
	return 0
}
