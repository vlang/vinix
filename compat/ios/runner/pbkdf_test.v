// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.hex

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32
type PBDerive = fn (u32, &u8, u64, &u8, u64, u32, u32, &u8, u64) i32

fn pb_case(native PBDerive, password &u8, plen u64, salt &u8, slen u64, prf u32, rounds u32, count u64) {
	mut output := [260]u8{init: 0xa5}
	darwin_set_errno(13)
	assert cc_key_derivation_pbkdf(2, password, plen, salt, slen, prf, rounds, unsafe { &output[1] }, count) == 0
	assert unsafe { *C.ios_errno_address() } == 13
	assert output[0] == 0xa5 && output[int(count)+1] == 0xa5
	if native != unsafe { nil } {
		mut reference := [260]u8{init: 0xa5}
		assert native(2, password, plen, salt, slen, prf, rounds, unsafe { &reference[1] }, count) == 0
		assert output == reference, 'prf=${prf} rounds=${rounds} count=${count} password=${plen} salt=${slen}'
	}
}

fn pb_vectors() {
	// RFC 6070, including binary password/salt and an incomplete final block.
	for item in [
		['password', 'salt', '1', '20', '0c60c80f961f0e71f3a9b524af6012062fe037a6']!,
		['password', 'salt', '2', '20', 'ea6c014dc72d6f8ccd1ed92ace1d41f0d8de8957']!,
		['password', 'salt', '4096', '20', '4b007901b765489abead49d926f721d065a429c1']!,
		['passwordPASSWORDpassword', 'saltSALTsaltSALTsaltSALTsaltSALTsalt', '4096', '25', '3d2eec4fe41c849b80c8d83662c0e44a8b291a964cf2f07038']!,
		['pass\x00word', 'sa\x00lt', '4096', '16', '56fa6aa75548099dcc37d7f03425e0c3']!,
	]! {
		mut out := [65]u8{init: 0xa5}; length := item[3].int()
		assert cc_key_derivation_pbkdf(2, item[0].str, u64(item[0].len), item[1].str, u64(item[1].len), 1, u32(item[2].int()), unsafe { &out[0] }, u64(length)) == 0
		assert unsafe { (&out[0]).vbytes(length) }.hex() == item[4] && out[length] == 0xa5
	}
	// Installed CommonCrypto reference values, 65 bytes crosses every digest size.
	for index, expected in [
		'ea6c014dc72d6f8ccd1ed92ace1d41f0d8de8957cae93136266537a8d7bf4b76c51094cc1ae010b19923ddc4395cd064acb023ffd1edd5ef4be8ffe61426c28efa',
		'93200ffa96c5776d38fa10abdf8f5bfc0054b9718513df472d2331d2d1e66a3f97b510224f700ce72581ffb10a1c99ec99a8cc1b951851a71f30d9265fccf912bc',
		'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43830651afcb5c862f0b249bd031f7a67520d136470f5ec271ece91c07773253d93e',
		'54f775c6d790f21930459162fc535dbf04a939185127016a04176a0730c6f1f4fb48832ad1261baadd2cedd50814b1c806ad1bbf43ebdc9d047904bf7ceafe1ebe',
		'e1d9c16aa681708a45f5c7c4e215ceb66e011a2e9f0040713f18aefdb866d53cf76cab2868a39b9f7840edce4fef5a82be67335c77a6068e04112754f27ccf4e47',
	]! {
		mut out := [66]u8{init: 0xa5}
		assert cc_key_derivation_pbkdf(2, c'password', 8, c'salt', 4, u32(index+1), 2, unsafe { &out[0] }, 65) == 0
		assert unsafe { (&out[0]).vbytes(65) }.hex() == expected && out[65] == 0xa5
	}
}

fn pb_invalid(native PBDerive) {
	for algorithm in [u32(0), 1, 2, 3, 0xffffffff]! { for prf in [u32(0), 1, 2, 3, 4, 5, 6, 0xffffffff]! {
		if algorithm == 2 && prf >= 1 && prf <= 5 { continue }
		mut out := [32]u8{init: 0xa5}
		assert cc_key_derivation_pbkdf(algorithm, c'password', 8, c'salt', 4, prf, 2, unsafe { &out[0] }, 32) == -4300
		if native != unsafe { nil } { assert native(algorithm, c'password', 8, c'salt', 4, prf, 2, unsafe { &out[0] }, 32) == -4300 }
		for value in out { assert value == 0xa5 }
	} }
	for which in 0 .. 9 {
		mut out := [32]u8{init: 0xa5}
		password := if which < 2 { unsafe { &u8(nil) } } else { c'password' }
		plen := if which == 0 { u64(0) } else if which == 6 { ~u64(0) } else { u64(8) }
		salt := if which == 2 { unsafe { &u8(nil) } } else { c'salt' }
		slen := if which == 7 { ~u64(0) } else { u64(4) }
		output := if which == 3 { unsafe { &u8(nil) } } else { unsafe { &out[0] } }
		n := if which == 4 { u64(0) } else if which == 8 { ~u64(0) } else { u64(32) }
		rounds := if which == 5 { u32(0) } else { u32(2) }
		darwin_set_errno(13)
		assert cc_key_derivation_pbkdf(2, password, plen, salt, slen, 3, rounds, output, n) == -4300
		assert unsafe { *C.ios_errno_address() } == 13
		if native != unsafe { nil } && which != 3 && which < 6 {
			assert native(2, password, plen, salt, slen, 3, rounds, output, n) == -4300
		}
		for value in out { assert value == 0xa5 }
	}
	for prf in u32(1) .. 6 {
		size := match prf { 1 { u64(20) } 2 { u64(28) } 3 { u64(32) } 4 { u64(48) } else { u64(64) } }
		mut out := [1]u8{init: 0xa5}
		assert cc_key_derivation_pbkdf(2, c'p', 1, c's', 1, prf, 1, unsafe { &out[0] }, size*0xffffffff+1) == -4300
		assert out[0] == 0xa5
	}
}

fn pb_guarded(native PBDerive) {
	page := u64(C.getpagesize())
	region := u64(C.mmap(unsafe { nil }, usize(page*6), C.PROT_NONE, C.MAP_PRIVATE|C.MAP_ANONYMOUS, -1, 0)); assert region != u64(-1)
	for offset in [u64(0), 2, 4]! { assert C.mprotect(unsafe { voidptr(region+offset*page) }, usize(page), C.PROT_READ|C.PROT_WRITE) == 0 }
	password := unsafe { &u8(region+page-257) }; salt := unsafe { &u8(region+3*page-129) }
	for i in 0 .. 257 { unsafe { password[i] = u8(i*19) } }
	for i in 0 .. 129 { unsafe { salt[i] = u8(i*37) } }
	for offset in [u64(0), 2]! { assert C.mprotect(unsafe { voidptr(region+offset*page) }, usize(page), C.PROT_READ) == 0 }
	for prf in u32(1) .. 6 { for count in [u64(1), 19, 20, 21, 27, 28, 29, 31, 32, 33, 47, 48, 49, 63, 64, 65, 128, 257]! {
		out := unsafe { &u8(region+5*page-count) }; unsafe { *(out-1)=0xa5 }
		assert cc_key_derivation_pbkdf(2, password, 257, salt, 129, prf, 3, out, count) == 0
		assert unsafe { *(out-1) } == 0xa5
		if native != unsafe { nil } {
			mut reference := [257]u8{}
			assert native(2, password, 257, salt, 129, prf, 3, unsafe { &reference[0] }, count) == 0
			assert C.memcmp(out, unsafe { &reference[0] }, usize(count)) == 0
		}
	} }
	assert C.munmap(unsafe { voidptr(region) }, usize(page*6)) == 0
}

fn pb_worker() {
	expected := hex.decode('ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43830651afcb5c862f0b249bd031f7a67520d136470f5ec271ece91c07773253d93e') or { panic(err) }
	defer { unsafe { expected.free() } }
	for _ in 0 .. 200 {
		mut out := [66]u8{init: 0xa5}
		assert cc_key_derivation_pbkdf(2, c'password', 8, c'salt', 4, 3, 2, unsafe { &out[0] }, 65) == 0
		assert C.memcmp(unsafe { &out[0] }, expected.data, 65) == 0 && out[65] == 0xa5
	}
}

fn test_pbkdf() {
	mut native := PBDerive(unsafe { nil })
	$if macos {
		handle := C.dlopen(c'/usr/lib/libSystem.B.dylib', 2); assert handle != unsafe { nil }
		native = unsafe { PBDerive(C.dlsym(handle, c'CCKeyDerivationPBKDF')) }; assert native != unsafe { nil }
	}
	pb_vectors(); pb_invalid(native); pb_guarded(native)
	// Actual IPA callers use SHA1 with 1,000 rounds/16 output bytes/eight
	// salt bytes, and SHA1 with 10,000 rounds and a runtime output length.
	pb_case(native, c'fixture password', 16, c'12345678', 8, 1, 1000, 16)
	pb_case(native, c'fixture password', 16, c'binary\x00salt', 11, 1, 10000, 65)
	mut password := [257]u8{}; mut salt := [257]u8{}
	for i in 0 .. 257 { password[i] = u8(i*13); salt[i] = u8(i*29) }
	for prf in u32(1) .. 6 { for n in [u64(0), 1, 63, 64, 65, 127, 128, 129, 257]! {
		for rounds in [u32(1), 2, 7]! { pb_case(native, unsafe { &password[0] }, n, unsafe { &salt[0] }, n, prf, rounds, 129) }
		pb_case(native, c'', 0, unsafe { nil }, 0, prf, 3, 65)
	} }
	objc_start()
	entry := runtime_symbol('/usr/lib/libSystem.B.dylib', '_CCKeyDerivationPBKDF') or { panic(err) }
	assert entry == u64(unsafe { voidptr(cc_key_derivation_pbkdf) })
	if _ := runtime_symbol('/usr/lib/libobjc.A.dylib', '_CCKeyDerivationPBKDF') { assert false }
	mut output := [32]u8{}
	assert unsafe { PBDerive(voidptr(entry)) }(2, c'password', 8, c'salt', 4, 3, 2, unsafe { &output[0] }, 32) == 0
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn pb_worker() }; workers.wait(); unsafe { workers.free() }
	objc_stop()
	println('IOS-PBKDF: all five PRFs, RFC 6070 and native vectors, IPA 1000/10000 rounds, binary/empty/long inputs, multiple blocks, guarded read-only buffers, invalid/overflow arguments, unchanged errno, scoped nine-argument C ABI and concurrent callers')
}
