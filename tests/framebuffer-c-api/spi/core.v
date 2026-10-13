// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module spi

#include "core_fixture.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct C.decoder {
mut:
	keys       [6]u8
	modifiers  u8
	caps       u8
	repeat_key u8
	repeat_at  u64
}

fn C.vinix_spi_core_accept_report(&C.decoder, &u8, u64, i32, &u8, usize) usize
fn C.vinix_spi_core_repeat_key(&C.decoder, u64, i32, &u8, usize) usize
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.puts(&char) i32
fn C.exit(i32)

fn check(ok bool) {
	if !ok {
		C.puts(c'SPI physical keyboard FAIL')
		C.exit(1)
	}
}

@[export: 'main']
pub fn entry() i32 {
	mut decoder := C.decoder{}
	mut report := [10]u8{}
	mut out := [512]u8{}
	report[1] = 3 // left Control and Shift
	report[3] = 4 // A
	n := C.vinix_spi_core_accept_report(unsafe { &decoder }, unsafe { &report[0] }, 1000, 2, unsafe { &out[0] }, 512)
	expected := c'\x1b[?224;1h\x1b[?225;1h\x1b[?4;1h'
	check(n == 25 && C.memcmp(unsafe { &out[0] }, expected, n) == 0)
	check(C.vinix_spi_core_accept_report(unsafe { &decoder }, unsafe { &report[0] }, 2000, 2, unsafe { &out[0] }, 512) == 0)
	check(C.vinix_spi_core_repeat_key(unsafe { &decoder }, 501000, 2, unsafe { &out[0] }, 512) == 7)
	check(C.memcmp(unsafe { &out[0] }, c'\x1b[?4;2h', 7) == 0)
	report[1] = 0
	report[3] = 0
	check(C.vinix_spi_core_accept_report(unsafe { &decoder }, unsafe { &report[0] }, 502000, 2, unsafe { &out[0] }, 512) == 25)
	check(C.memcmp(unsafe { &out[0] }, c'\x1b[?224;0h\x1b[?225;0h\x1b[?4;0h', 25) == 0)
	check(decoder.repeat_key == 0 && decoder.repeat_at == 0)
	// Releases still cancel repeat when a caller has no output space.
	report[3] = 4
	check(C.vinix_spi_core_accept_report(unsafe { &decoder }, unsafe { &report[0] }, 600000, 2, unsafe { &out[0] }, 512) == 7)
	report[3] = 0
	check(C.vinix_spi_core_accept_report(unsafe { &decoder }, unsafe { &report[0] }, 600001, 2, unsafe { &out[0] }, 0) == 0 && decoder.repeat_key == 0)
	report[9] = 1
	check(C.vinix_spi_core_accept_report(unsafe { &decoder }, unsafe { &report[0] }, 600002, 2, unsafe { &out[0] }, 512) == 9)
	check(C.memcmp(unsafe { &out[0] }, c'\x1b[?255;1h', 9) == 0)
	report[9] = 0
	check(C.vinix_spi_core_accept_report(unsafe { &decoder }, unsafe { &report[0] }, 600003, 2, unsafe { &out[0] }, 512) == 9)
	check(C.memcmp(unsafe { &out[0] }, c'\x1b[?255;0h', 9) == 0)
	C.puts(c'SPI physical keyboard PASS')
	return 0
}
