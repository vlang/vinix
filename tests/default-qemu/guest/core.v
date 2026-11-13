// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module guest

#include <fcntl.h>
#include <stdio.h>
#include <time.h>
#include <unistd.h>

fn C.open(&char, i32, ...) i32
fn C.read(i32, voidptr, usize) i64
fn C.dprintf(i32, &char, ...) i32
fn C.nanosleep(&C.timespec, voidptr) i32

struct C.timespec {
mut:
	tv_sec  i64
	tv_nsec i64
}

@[export: 'main']
pub fn main() i32 {
	serial := C.open(c'/dev/com1', i32(1))
	pointer := C.open(c'/dev/pointer', i32(0))
	keyboard := C.open(c'/dev/console', i32(0x800))
	if serial < 0 || pointer < 0 || keyboard < 0 { return 1 }
	mut previous := [8]i32{}
	mut keys := [64]u8{}
	delay := C.timespec{ tv_nsec: 1000000 }
	C.dprintf(serial, c'INPUT READY\n')
	for {
		mut data := [9]i32{}
		data[8] = 12345
		if C.read(pointer, &data[0], usize(32)) != 32 || data[8] != 12345 {
			C.dprintf(serial, c'INPUT FAIL pointer ABI\n')
			return 2
		}
		if data[0] != previous[0] || data[1] != previous[1] || data[4] != previous[4]
			|| data[5] != 0 || data[6] != 0 || data[7] != 0 {
			C.dprintf(serial, c'POINTER %d %d %d %d %u %u %u %d\n',
				data[0], data[1], data[2], data[3], u32(data[4]), u32(data[5]), u32(data[6]), data[7])
		}
		for i in 0 .. 8 {
			unsafe { previous[i] = data[i] }
		}
		n := C.read(keyboard, &keys[0], usize(64))
		for i := i64(0); i < n; i++ {
			C.dprintf(serial, c'KEY %u\n', u32(unsafe { keys[i] }))
		}
		C.nanosleep(&delay, unsafe { nil })
	}
	return 0
}
