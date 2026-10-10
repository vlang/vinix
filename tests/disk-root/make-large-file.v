// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn main() {
	if os.args.len != 2 {
		eprintln('usage: make-large-file PATH')
		exit(1)
	}
	mut data := []u8{len: 3 * 1024 * 1024}
	for offset in 0 .. data.len {
		// Use wide arithmetic: the guest recomputes this exact byte from the
		// offset when checking indirect ext2 blocks and their persisted data.
		data[offset] = u8((u64(offset) * 1103515245 + 12345) >> 16)
	}
	os.write_file_array(os.args[1], data) or {
		eprintln(err)
		exit(1)
	}
}
