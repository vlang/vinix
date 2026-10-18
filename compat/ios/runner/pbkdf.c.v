// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha1
import crypto.sha256
import crypto.sha512

// Borrow bounded slices from a size_t input. No caller buffer is copied or
// narrowed to a V array length, including passwords longer than a hash block.
fn pbkdf_write[D](mut digest D, bytes &u8, count u64) {
	mut offset := u64(0)
	for offset < count {
		length := if count - offset > 0x40000000 { u64(0x40000000) } else { count - offset }
		digest.write(unsafe { (bytes + offset).vbytes(int(length)) }) or { panic('iOS: PBKDF digest write failed') }
		offset += length
	}
}

// PBKDF2 uses a single keyed HMAC for all output blocks and rounds. Own all
// three V digest objects explicitly: their constructors allocate state arrays.
// The iteration loop and output use only stack storage and borrowed buffers.
fn pbkdf_derive[D](factory fn () D, password &u8, password_len u64, salt &u8,
	salt_len u64, rounds u32, output &u8, output_len u64) {
	mut inner := factory()
	mut outer := factory()
	mut work := factory()
	defer {
		unsafe {
			inner.free(); C.free(inner)
			outer.free(); C.free(outer)
			work.free(); C.free(work)
		}
	}
	block_size := work.block_size()
	hash_size := work.size()
	mut key_pad := [128]u8{}
	mut u := [64]u8{}
	mut result := [64]u8{}
	mut counter := [4]u8{}
	defer {
		darwin_memset_s(unsafe { &key_pad[0] }, 128, 0, 128)
		darwin_memset_s(unsafe { &u[0] }, 64, 0, 64)
		darwin_memset_s(unsafe { &result[0] }, 64, 0, 64)
	}
	mut pad := unsafe { (&key_pad[0]).vbytes(block_size) }
	mut hash := unsafe { (&u[0]).vbytes(hash_size) }
	if password_len > u64(block_size) {
		pbkdf_write(mut work, password, password_len)
		work.checksum_into(mut pad)
	} else if password_len != 0 {
		unsafe { C.memcpy(&key_pad[0], password, usize(password_len)) }
	}
	for i in 0 .. block_size { key_pad[i] ^= 0x36 }
	inner.write(pad) or { panic('iOS: PBKDF inner key failed') }
	for i in 0 .. block_size { key_pad[i] ^= 0x36 ^ 0x5c }
	outer.write(pad) or { panic('iOS: PBKDF outer key failed') }
	mut written := u64(0)
	mut block := u32(1)
	for written < output_len {
		counter[0] = u8(block >> 24); counter[1] = u8(block >> 16)
		counter[2] = u8(block >> 8); counter[3] = u8(block)
		work.copy_from(inner)
		pbkdf_write(mut work, salt, salt_len)
		work.write(unsafe { (&counter[0]).vbytes(4) }) or { panic('iOS: PBKDF counter failed') }
		work.checksum_into(mut hash)
		work.copy_from(outer)
		work.write(hash) or { panic('iOS: PBKDF inner hash failed') }
		work.checksum_into(mut hash)
		for i in 0 .. hash_size { result[i] = u[i] }
		for round := u32(1); round < rounds; round++ {
			work.copy_from(inner)
			work.write(hash) or { panic('iOS: PBKDF round failed') }
			work.checksum_into(mut hash)
			work.copy_from(outer)
			work.write(hash) or { panic('iOS: PBKDF inner hash failed') }
			work.checksum_into(mut hash)
			for i in 0 .. hash_size { result[i] ^= u[i] }
		}
		length := if output_len - written < u64(hash_size) { output_len - written } else { u64(hash_size) }
		unsafe { C.memcpy(output + written, &result[0], usize(length)) }
		written += length
		block++
	}
}

// CommonCrypto's PRF numbers are 1..5 (SHA1,224,256,384,512), unlike CCHmac.
// The ninth argument is a size_t on the stack in both Darwin and AAPCS64.
fn cc_key_derivation_pbkdf(algorithm u32, password &u8, password_len u64,
	salt &u8, salt_len u64, prf u32, rounds u32, output &u8, output_len u64) i32 {
	if algorithm != 2 || prf < 1 || prf > 5 || rounds == 0 || output_len == 0
		|| password == unsafe { nil } || output == unsafe { nil }
		|| (salt == unsafe { nil } && salt_len != 0)
		|| password_len > ~u64(0) - u64(password)
		|| salt_len > ~u64(0) - u64(salt)
		|| output_len > ~u64(0) - u64(output) { return -4300 }
	hash_size := match prf { 1 { u64(20) } 2 { u64(28) } 3 { u64(32) } 4 { u64(48) } else { u64(64) } }
	// RFC 8018's four-byte block counter must never wrap and reuse block 0.
	if output_len > u64(0xffffffff) * hash_size { return -4300 }
	match prf {
		1 { pbkdf_derive(sha1.new, password, password_len, salt, salt_len, rounds, output, output_len) }
		2 { pbkdf_derive(sha256.new224, password, password_len, salt, salt_len, rounds, output, output_len) }
		3 { pbkdf_derive(sha256.new, password, password_len, salt, salt_len, rounds, output, output_len) }
		4 { pbkdf_derive(sha512.new384, password, password_len, salt, salt_len, rounds, output, output_len) }
		else { pbkdf_derive(sha512.new, password, password_len, salt, salt_len, rounds, output, output_len) }
	}
	return 0
}
