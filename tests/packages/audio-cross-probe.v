// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <stdint.h>
#include <stddef.h>

fn main() {
	if sizeof(u32) != 4 { exit(2) }
	println('AUDIO FROZEN SYSROOT PROBE')
}
