// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.hex
import os
import tools.packages.signing

#include "@VMODROOT/../../desktop/tools/tests/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32
fn C.vinix_heap_size_at(u32) u64

fn finish(operation string, before bool) {
	live := C.vinix_heap_end()
	mut large := 0
	for i in u32(0) .. C.vinix_heap_count() { if C.vinix_heap_size_at(i) >= 1024 { large++ } }
	limit := if operation == 'key' { u64(4096) } else { u64(8192) }
	println('${operation}: ${live} live bytes, ${C.vinix_heap_count()} allocations, ${large} allocations of at least 1024 bytes')
	if before { assert live > limit && large > 0 }
	else { assert live <= limit && large == 0 }
}

fn main() {
	$if !track_heap ? { panic('compile with -d track_heap -gc none -manualfree') }
	assert os.args.len == 1 || (os.args.len == 2 && os.args[1] == '--before')
	before := os.args.len == 2
	seed := hex.decode('9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60')!
	defer { unsafe { seed.free() } }
	C.vinix_heap_begin()
	key := signing.new_key_from_seed(seed)
	finish('key', before)
	defer { unsafe { key.free() } }
	public_key := key.public_key()
	defer { unsafe { public_key.free() } }
	assert public_key.hex() == 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a'
	C.vinix_heap_begin()
	signature := signing.sign(key, [])!
	finish('sign', before)
	defer { unsafe { signature.free() } }
	assert signature.hex() == 'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b'
	C.vinix_heap_begin()
	assert signing.verify(public_key, [], signature)!
	finish('verify', before)
	if !before {
		for _ in 0 .. 32 {
			C.vinix_heap_begin()
			assert signing.verify(public_key, [], signature)!
			finish('verify', false)
		}
	}
	println('Signing table ownership qualification passed; reference bytes and live allocation budgets retained')
}
