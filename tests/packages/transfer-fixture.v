// SPDX-License-Identifier: GPL-2.0-or-later
// Controlled child process for transfer monitoring; no network or curl replacement.
module main

import os
import time

fn main() {
	assert os.args.len == 4
	mut file := os.open_file(os.args[1], 'w', 0o600)!
	file.set_unbuffered()
	chunk := []u8{len: 64 * 1024, init: u8(42)}
	for _ in 0 .. os.args[2].int() {
		assert file.write(chunk)! == chunk.len
		time.sleep(50 * time.millisecond)
	}
	file.close()
	exit(os.args[3].int())
}
