// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.hex
import tools.packages.signing

#include "@VMODROOT/../../desktop/tools/tests/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32

fn main() {
	$if !track_heap ? { panic('compile with -d track_heap -gc none -manualfree') }
	// RFC 8032 keys and the independent libsodium core_ed25519 point fixtures:
	// https://github.com/jedisct1/libsodium/blob/fbd637d8db5689e7a98a6a6a2e43b35a61e2025c/test/default/core_ed25519.c
	cases := {
		'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a': true
		'3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c': true
		'fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025': true
		'e4' + 'ff'.repeat(30) + '7f': true
		'95' + '99'.repeat(31): false // mixed-order point
		'f6' + 'ff'.repeat(30) + '7f': false // noncanonical curve point
		'f5' + 'ff'.repeat(30) + '7f': false // noncanonical invalid point
		'02' + '00'.repeat(31): false // invalid curve point
		'00'.repeat(32): false // order four
		'01' + '00'.repeat(31): false // identity
		'ec' + 'ff'.repeat(30) + '7f': false // order two
		'ee' + 'ff'.repeat(30) + '7f': false // noncanonical identity
		'01' + '00'.repeat(30) + '80': false // identity with a noncanonical sign
		'00'.repeat(31): false
		'00'.repeat(33): false
	}
	for encoded, expected in cases {
		key := hex.decode(encoded)!
		for _ in 0 .. 16 {
			C.vinix_heap_begin()
			accepted := signing.publisher_key_valid(signing.PublicKey(key))
			live := C.vinix_heap_end()
			assert accepted == expected, encoded
			assert live == 0 && C.vinix_heap_count() == 0, '${encoded}: ${live} retained bytes'
		}
		unsafe { key.free() }
	}
	println('Publisher key memory: 15 independent key cases, 240 validations, zero retained bytes PASS')
}
