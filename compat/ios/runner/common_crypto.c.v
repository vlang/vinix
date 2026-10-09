// SPDX-License-Identifier: GPL-2.0-or-later
// CommonCrypto ABI over V's cryptographic primitives. No host Apple library
// supplies guest cryptography. Unsupported algorithms fail explicitly.
module main

import crypto.aes
import crypto.sha1
import crypto.sha256
import crypto.sha512

fn cc_random_generate(bytes &u8, count u64) int {
	if count == 0 { return 0 }
	if bytes == unsafe { nil } || count > ~u64(0) - u64(bytes) { return -4300 }
	// Native getentropy accepts at most 256 bytes per call. Fill the caller's
	// buffer directly, without imposing SecRandomCopyBytes' separate size limit
	// or allocating temporary storage. An entropy failure is kCCRNGFailure.
	mut offset := u64(0)
	for offset < count {
		chunk := if count - offset > 256 { u64(256) } else { count - offset }
		if C.getentropy(unsafe { bytes + offset }, usize(chunk)) != 0 { return -4307 }
		offset += chunk
	}
	return 0
}

fn common_hash[D](factory fn () D, bytes &u8, count u32, output &u8) &u8 {
	if output == unsafe { nil } || (bytes == unsafe { nil } && count != 0) { return unsafe { nil } }
	mut digest := factory()
	defer {
		unsafe {
			digest.free()
			C.free(digest)
		}
	}
	digest.write(unsafe { bytes.vbytes(int(count)) }) or { panic('iOS: digest input failed') }
	mut destination := unsafe { output.vbytes(digest.size()) }
	digest.checksum_into(mut destination)
	return output
}

fn cc_sha1(bytes &u8, count u32, output &u8) &u8 {
	return common_hash(sha1.new, bytes, count, output)
}

fn cc_sha224(bytes &u8, count u32, output &u8) &u8 {
	return common_hash(sha256.new224, bytes, count, output)
}

fn cc_sha256(bytes &u8, count u32, output &u8) &u8 {
	return common_hash(sha256.new, bytes, count, output)
}

fn cc_sha384(bytes &u8, count u32, output &u8) &u8 {
	return common_hash(sha512.new384, bytes, count, output)
}

fn cc_sha512(bytes &u8, count u32, output &u8) &u8 {
	return common_hash(sha512.new, bytes, count, output)
}

fn common_hmac[D](factory fn () D, key &u8, key_count u64, bytes &u8, count u64, output &u8) {
	mut digest := factory()
	defer {
		unsafe {
			digest.free()
			C.free(digest)
		}
	}
	block_size := digest.block_size()
	mut key_pad := [128]u8{}
	mut pad := unsafe { (&key_pad[0]).vbytes(block_size) }
	if key_count > u64(block_size) {
		digest.write(unsafe { key.vbytes(int(key_count)) }) or { panic('iOS: HMAC key input failed') }
		digest.checksum_into(mut pad)
		digest.reset()
	} else {
		for i in 0 .. int(key_count) { key_pad[i] = unsafe { key[i] } }
	}
	for i in 0 .. block_size { key_pad[i] ^= 0x36 }
	digest.write(pad) or { panic('iOS: HMAC inner pad failed') }
	digest.write(unsafe { bytes.vbytes(int(count)) }) or { panic('iOS: HMAC input failed') }
	mut hash := [64]u8{}
	mut inner := unsafe { (&hash[0]).vbytes(digest.size()) }
	digest.checksum_into(mut inner)
	digest.reset()
	for i in 0 .. block_size { key_pad[i] ^= 0x36 ^ 0x5c }
	digest.write(pad) or { panic('iOS: HMAC outer pad failed') }
	digest.write(inner) or { panic('iOS: HMAC inner digest failed') }
	mut destination := unsafe { output.vbytes(digest.size()) }
	digest.checksum_into(mut destination)
}

fn cc_hmac(algorithm u32, key &u8, key_count u64, bytes &u8, count u64, output &u8) {
	if key_count > 0xffffffff || count > 0xffffffff || output == unsafe { nil }
		|| (key == unsafe { nil } && key_count != 0) || (bytes == unsafe { nil } && count != 0) {
		panic('iOS: invalid CCHmac buffer')
	}
	match algorithm {
		0 { common_hmac(sha1.new, key, key_count, bytes, count, output) }
		2 { common_hmac(sha256.new, key, key_count, bytes, count, output) }
		3 { common_hmac(sha512.new384, key, key_count, bytes, count, output) }
		4 { common_hmac(sha512.new, key, key_count, bytes, count, output) }
		5 { common_hmac(sha256.new224, key, key_count, bytes, count, output) }
		else { panic('iOS: CCHmac algorithm is not implemented') }
	}
}

// All three arguments beyond x7 are 64-bit pointers/sizes in Darwin, so the
// native stack layout agrees with AAPCS64 without a packed-argument adapter.
fn cc_crypt(operation u32, algorithm u32, options u32, key &u8, key_count u64, iv &u8,
	input &u8, count u64, output &u8, capacity u64, moved &u64) int {
	if algorithm != 0 || options & ~u32(3) != 0 { return -4305 } // kCCUnimplemented
	if operation > 1 || key == unsafe { nil } || count > 0xffffffff
		|| (input == unsafe { nil } && count != 0) {
		return -4300
	}
	if key_count !in [u64(16), 24, 32] { return -4310 } // kCCKeySizeError
	if moved != unsafe { nil } { unsafe { *moved = 0 } }
	padded := options & 1 != 0
	ecb := options & 2 != 0
	// Padded decryption supports complete AES blocks. For an unpadded partial
	// block, Apple's Update writes the complete prefix and Final reports alignment.
	if operation == 1 && padded && count % 16 != 0 { return -4303 }
	misaligned := !padded && count % 16 != 0
	required := if operation == 0 && padded { count - count % 16 + 16 } else { count - count % 16 }
	if capacity < required {
		if moved != unsafe { nil } { unsafe { *moved = required } }
		return -4301
	}
	if required == 0 { return if misaligned { -4303 } else { 0 } }
	if output == unsafe { nil } { return -4300 }
	// The documented in-place case is supported. Partial overlap is rejected
	// before writing, rather than allowing output to overwrite unread input.
	if input != output && count != 0 {
		a := u64(input)
		b := u64(output)
		if (a < b && b - a < count) || (b < a && a - b < required) { return -4300 }
	}
	mut cipher := aes.new_cipher(unsafe { key.vbytes(int(key_count)) }) or { return -4300 }
	defer {
		if mut cipher is aes.AesCipher {
			unsafe {
				cipher.free()
				C.free(cipher)
			}
		}
	}
	mut chain := [16]u8{}
	if !ecb && iv != unsafe { nil } { unsafe { C.memcpy(&chain[0], iv, 16) } }
	mut written := u64(0)
	for offset := u64(0); offset < required; offset += 16 {
		mut source := [16]u8{}
		mut destination := [16]u8{}
		mut src := unsafe { (&source[0]).vbytes(16) }
		mut dst := unsafe { (&destination[0]).vbytes(16) }
		if operation == 0 {
			for i in 0 .. 16 {
				position := offset + u64(i)
				source[i] = if position < count {
					unsafe { input[position] }
				} else {
					u8(required - count)
				}
				if !ecb { source[i] ^= chain[i] }
			}
			cipher.encrypt(mut dst, src)
			chain = destination
		} else {
			unsafe { C.memcpy(&source[0], input + offset, 16) }
			cipher.decrypt(mut dst, src)
			if !ecb {
				for i in 0 .. 16 { destination[i] ^= chain[i] }
			}
			chain = source
		}
		mut length := u64(16)
		if operation == 1 && padded && offset + 16 == required {
			// The measured legacy CCCrypt path uses only the final length byte:
			// 1..16 are stripped even if preceding pad bytes differ; other values
			// leave the block intact. This is compatibility, not authentication.
			pad := destination[15]
			if pad >= 1 && pad <= 16 { length -= pad }
		}
		if length != 0 { unsafe { C.memcpy(output + written, &destination[0], usize(length)) } }
		written += length
	}
	if moved != unsafe { nil } { unsafe { *moved = written } }
	return if misaligned { -4303 } else { 0 }
}

fn common_crypto_symbol(symbol string) ?u64 {
	return match symbol {
		'_CC_SHA1' { u64(unsafe { voidptr(cc_sha1) }) }
		'_CC_SHA224' { u64(unsafe { voidptr(cc_sha224) }) }
		'_CC_SHA256' { u64(unsafe { voidptr(cc_sha256) }) }
		'_CC_SHA384' { u64(unsafe { voidptr(cc_sha384) }) }
		'_CC_SHA512' { u64(unsafe { voidptr(cc_sha512) }) }
		'_CCHmac' { u64(unsafe { voidptr(cc_hmac) }) }
		'_CCCrypt' { u64(unsafe { voidptr(cc_crypt) }) }
		'_CCRandomGenerateBytes' { u64(unsafe { voidptr(cc_random_generate) }) }
		else { return none }
	}
}
