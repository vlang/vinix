// SPDX-License-Identifier: GPL-2.0-only
// Native child for standard-descriptor and binary/text failure qualification.
module main

import os

#include <fcntl.h>

fn C.fcntl(i32, i32, ...i32) i32
fn C.write(i32, voidptr, usize) isize

fn main() {
	mut state := []string{}
	for fd in 0 .. 3 { state << C.fcntl(i32(fd), C.F_GETFD).str() }
	os.write_file(os.args[1], state.join(',') + '\n')!
	mode := os.args[2]
	if mode == 'inherited' { return }
	text := if mode == 'invalid' { '\xff' } else { 'capture\r\nreply\r' }
	C.write(1, text.str, usize(text.len))
	if mode in ['failure', 'invalid'] { exit(37) }
}
