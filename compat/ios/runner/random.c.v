// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn darwin_arc4random_buf(buffer voidptr, count usize) {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	// Share CommonCrypto's allocation-free, chunked OS entropy reader. No
	// userspace seed, cached bytes or lock survive a fork. The void Darwin ABI
	// cannot report failure: never return success with uninitialized bytes.
	if cc_random_generate(unsafe { &u8(buffer) }, u64(count)) != 0 {
		panic('iOS: random source failed')
	}
}

fn darwin_arc4random() u32 {
	mut value := u32(0)
	darwin_arc4random_buf(unsafe { &value }, sizeof(value))
	return value
}

fn darwin_random_uniform(bound u32) u32 {
	if bound < 2 { return 0 }
	// Reject the incomplete residue interval before reducing modulo bound.
	threshold := (u32(0) - bound) % bound
	for {
		value := darwin_arc4random()
		if value >= threshold { return value % bound }
	}
}

fn random_symbol(symbol string) ?u64 {
	address := match symbol {
		'_arc4random' { unsafe { voidptr(darwin_arc4random) } }
		'_arc4random_buf' { unsafe { voidptr(darwin_arc4random_buf) } }
		'_arc4random_uniform' { unsafe { voidptr(darwin_random_uniform) } }
		else { return none }
	}
	return u64(address)
}
