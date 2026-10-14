// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.hex
import os
import tools.packages.signing

// Allocation hooks must not allocate while the signing operation is measured.
// Count requests rather than retained heap: table/digest ownership is separate.
__global (
	signing_tracking = false
	signing_allocations u64
	signing_bytes u64
	signing_field_allocations u64
)

@[export: 'vheap_alloc']
fn signing_record_allocation(_ voidptr, size u64) {
	if signing_tracking {
		signing_allocations++
		signing_bytes += size
		if size == 40 { signing_field_allocations++ }
	}
}

@[export: 'vheap_free']
fn signing_record_free(_ voidptr) {}

fn begin() {
	signing_allocations = 0; signing_bytes = 0; signing_field_allocations = 0
	signing_tracking = true
}

fn finish(operation string, before bool) {
	signing_tracking = false
	println('${operation}: ${signing_allocations} allocations, ${signing_bytes} requested bytes, ${signing_field_allocations} 40-byte requests')
	if before {
		assert signing_field_allocations > 70000 && signing_bytes > 2900000
	} else {
		assert signing_field_allocations == 0
		assert signing_allocations < 1000 && signing_bytes < 150000
	}
}

fn main() {
	$if !track_heap ? { panic('compile with -d track_heap -enable-globals -gc none -manualfree') }
	assert os.args.len == 1 || (os.args.len == 2 && os.args[1] == '--before')
	before := os.args.len == 2
	seed := hex.decode('9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60')!
	defer { unsafe { seed.free() } }
	begin()
	key := signing.new_key_from_seed(seed)
	finish('key', before)
	defer { unsafe { key.free() } }
	public_key := key.public_key()
	defer { unsafe { public_key.free() } }
	assert public_key.hex() == 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a'
	begin()
	signature := signing.sign(key, [])!
	finish('sign', before)
	defer { unsafe { signature.free() } }
	assert signature.hex() == 'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b'
	assert signing.verify(public_key, [], signature)!
	println('Signing allocation qualification passed; RFC8032 bytes retained')
}
