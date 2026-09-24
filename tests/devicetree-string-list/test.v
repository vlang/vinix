// SPDX-License-Identifier: GPL-2.0-or-later
module main

import fdtstrings

fn main() {
	mut blob := [u8(`a`), `p`, `p`, `l`, `e`, 0, `v`, `i`, `n`, `i`, `x`, 0]
	values := fdtstrings.clone_nul_list(blob.data, u32(blob.len)) or {
		panic('valid FDT string list was rejected')
	}

	assert values == ['apple', 'vinix']
	// The decoded values must not retain views into firmware-owned storage.
	blob[0] = `X`
	blob[6] = `Y`
	assert values == ['apple', 'vinix']

	unsafe { values.free() }
	println('device-tree string-list ownership tests passed')
}
