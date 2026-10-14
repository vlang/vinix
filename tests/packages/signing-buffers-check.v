// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.hex
import os
import tools.packages.signing

#include "@VMODROOT/../../desktop/tools/tests/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32

fn finish(operation string, before bool) {
	live := C.vinix_heap_end()
	count := C.vinix_heap_count()
	println('${operation}: ${live} retained bytes in ${count} allocations after caller cleanup')
	if before { assert live > 0 && count > 0 }
	else { assert live == 0 && count == 0 }
}

fn main() {
	$if !track_heap ? { panic('compile with -d track_heap -gc none -manualfree') }
	assert os.args.len == 1 || (os.args.len == 2 && os.args[1] == '--before')
	before := os.args.len == 2
	// Public RFC 8032 reference seed; never enroll it as a publisher.
	seed := hex.decode('9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60')!
	key := signing.new_key_from_seed(seed)
	public_key := key.public_key()
	assert public_key.hex() == 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a'
	expected := hex.decode('e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b')!
	defer { unsafe { seed.free(); key.free(); public_key.free(); expected.free() } }
	C.vinix_heap_begin()
	generated := signing.new_key_from_seed(seed)
	assert generated == key
	generated_public := generated.public_key()
	assert generated_public == public_key
	unsafe { generated_public.free(); generated.free() }
	finish('key', before)
	C.vinix_heap_begin()
	signature := signing.sign(key, [])!
	assert signature == expected
	unsafe { signature.free() }
	finish('sign', before)
	C.vinix_heap_begin()
	assert signing.verify(public_key, [], expected)!
	finish('verify', before)
	if !before {
		// SHA-512 padding and block boundaries, including the 32/64-byte prefixes.
		for length in [0, 1, 2, 47, 48, 49, 63, 64, 65, 79, 80, 81, 95, 96, 97,
			111, 112, 113, 127, 128, 129, 1024] {
			message := []u8{len: length, init: u8(index)}
			valid := signing.sign(key, message)!
			mut changed := valid.clone()
			changed[0] ^= 1
			for _ in 0 .. 4 {
				C.vinix_heap_begin()
				produced := signing.sign(key, message)!
				assert produced == valid
				unsafe { produced.free() }
				assert signing.verify(public_key, message, valid)!
				assert !(signing.verify(public_key, message, changed) or { unsafe { err.free() }; false })
				assert !signing.verify(public_key, message, valid[..63])!
				finish('cycle', false)
			}
			unsafe { message.free(); valid.free(); changed.free() }
		}
	}
	println('Signing buffer ownership qualification passed; RFC bytes and caller ownership retained')
}
