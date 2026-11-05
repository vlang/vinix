// SPDX-License-Identifier: GPL-2.0-or-later
// Deliberately bounded host child for the engine's existing owner controls.
module main

import os

#include <unistd.h>
fn C.fork() i32
fn C.usleep(u32) i32
fn C._exit(i32)

fn bounded_pause() {
	// Stay below the portable single-usleep argument limit.
	for _ in 0 .. 10 { C.usleep(500000) }
}

fn main() {
	mode := os.read_file('fixture-behavior') or { C._exit(120); return }
	if mode == 'clean\n' { return }
	if mode == 'nonzero\n' { C._exit(7); return }
	if mode == 'timeout\n' { bounded_pause(); return }
	if mode == 'held-pipe\n' {
		child := C.fork()
		if child < 0 { C._exit(121); return }
		if child == 0 { bounded_pause(); C._exit(0) }
		return
	}
	C._exit(122)
}
