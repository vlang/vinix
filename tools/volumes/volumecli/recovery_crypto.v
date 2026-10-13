// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

// Version 1: 64-byte canonical header, 64-byte ChaCha20 ciphertext and a full
// HMAC-SHA256 tag. Independent 32-byte keys come from a private 64-byte file.
// Authenticate the header and ciphertext before decrypting any key material.
const recovery_bytes = 160

struct RecoveryChaCha {
mut:
	state [16]u32
	words [16]u32
}

@[inline]
fn recovery_rotate(value u32, bits u32) u32 { return value << bits | value >> (32 - bits) }

@[inline]
fn recovery_quarter(a &u32, b &u32, c &u32, d &u32) {
	unsafe {
		*a += *b; *d ^= *a; *d = recovery_rotate(*d, 16)
		*c += *d; *b ^= *c; *b = recovery_rotate(*b, 12)
		*a += *b; *d ^= *a; *d = recovery_rotate(*d, 8)
		*c += *d; *b ^= *c; *b = recovery_rotate(*b, 7)
	}
}

// RFC 8439, counter 1, exactly one 64-byte block; never reused within a backup.
@[direct_array_access]
fn recovery_chacha(key &u8, nonce &u8, data &u8) {
	mut work := unsafe { &RecoveryChaCha(C.alloca(sizeof(RecoveryChaCha))) }
	unsafe { *work = RecoveryChaCha{} }
	defer { erase_key(work, sizeof(RecoveryChaCha)) }
	work.state[0] = 0x61707865; work.state[1] = 0x3320646e
	work.state[2] = 0x79622d32; work.state[3] = 0x6b206574
	for i in 0 .. 8 { work.state[4 + i] = u32(get_le(key, i * 4, 4)) }
	work.state[12] = 1
	for i in 0 .. 3 { work.state[13 + i] = u32(get_le(nonce, i * 4, 4)) }
	unsafe { C.memcpy(&work.words[0], &work.state[0], 64) }
	for _ in 0 .. 10 {
		unsafe {
			recovery_quarter(&work.words[0], &work.words[4], &work.words[8], &work.words[12])
			recovery_quarter(&work.words[1], &work.words[5], &work.words[9], &work.words[13])
			recovery_quarter(&work.words[2], &work.words[6], &work.words[10], &work.words[14])
			recovery_quarter(&work.words[3], &work.words[7], &work.words[11], &work.words[15])
			recovery_quarter(&work.words[0], &work.words[5], &work.words[10], &work.words[15])
			recovery_quarter(&work.words[1], &work.words[6], &work.words[11], &work.words[12])
			recovery_quarter(&work.words[2], &work.words[7], &work.words[8], &work.words[13])
			recovery_quarter(&work.words[3], &work.words[4], &work.words[9], &work.words[14])
		}
	}
	for i in 0 .. 16 {
		work.words[i] += work.state[i]
		unsafe { for byte in 0 .. 4 { data[i * 4 + byte] ^= u8(work.words[i] >> u32(byte * 8)) } }
	}
}

struct RecoveryHmac {
mut:
	context DataSha256
	pad [64]u8
	inner [32]u8
}

// RFC 2104 HMAC with an exact 32-byte key and a full SHA-256 tag.
@[direct_array_access]
fn recovery_hmac(key &u8, data &u8, size usize, output &[32]u8) bool {
	mut work := unsafe { &RecoveryHmac(C.alloca(sizeof(RecoveryHmac))) }
	unsafe { *work = RecoveryHmac{} }
	defer { erase_key(work, sizeof(RecoveryHmac)) }
	for i in 0 .. 64 { work.pad[i] = 0x36 }
	unsafe { for i in 0 .. 32 { work.pad[i] ^= key[i] } }
	data_sha_init(mut work.context)
	if !data_sha_update(mut work.context, &work.pad[0], 64)
		|| !data_sha_update(mut work.context, data, size)
		|| !data_sha_finish(&work.context, unsafe { &work.inner }) { return false }
	for i in 0 .. 64 { work.pad[i] = 0x5c }
	unsafe { for i in 0 .. 32 { work.pad[i] ^= key[i] } }
	data_sha_init(mut work.context)
	return data_sha_update(mut work.context, &work.pad[0], 64)
		&& data_sha_update(mut work.context, &work.inner[0], 32)
		&& data_sha_finish(&work.context, output)
}

fn recovery_equal(left &u8, right &u8, size int) bool {
	mut difference := u8(0)
	unsafe { for i in 0 .. size { difference |= left[i] ^ right[i] } }
	return difference == 0
}

struct RecoveryEnvelope {
mut:
	bytes [160]u8
	key [64]u8
	tag [32]u8
}

struct RecoveryTag {
mut:
	message [160]u8
}

// Bind both halves of the recovery key: changing only the stream key must fail
// authentication too, before any candidate plaintext is copied to the caller.
fn recovery_tag(recovery &u8, bytes &u8, output &[32]u8) bool {
	mut work := unsafe { &RecoveryTag(C.alloca(sizeof(RecoveryTag))) }
	unsafe { *work = RecoveryTag{} }
	defer { erase_key(work, sizeof(RecoveryTag)) }
	unsafe { C.memcpy(&work.message[0], recovery, 32); C.memcpy(&work.message[32], bytes, 128) }
	return recovery_hmac(unsafe { recovery + 32 }, &work.message[0], 160, output)
}

@[direct_array_access]
fn encode_recovery(key &u8, recovery &u8, nonce &u8, output &u8) bool {
	if recovery_equal(key, recovery, 64) || recovery_equal(key, unsafe { key + 32 }, 32)
		|| recovery_equal(recovery, unsafe { recovery + 32 }, 32) { return false }
	mut work := unsafe { &RecoveryEnvelope(C.alloca(sizeof(RecoveryEnvelope))) }
	unsafe { *work = RecoveryEnvelope{} }
	defer { erase_key(work, sizeof(RecoveryEnvelope)) }
	unsafe { C.memcpy(&work.bytes[0], c'VINIXKR1', 8) }
	put_le(&work.bytes[0], 8, 4, 1); put_le(&work.bytes[0], 12, 4, 1)
	put_le(&work.bytes[0], 16, 4, recovery_bytes); put_le(&work.bytes[0], 20, 4, 64)
	unsafe { C.memcpy(&work.bytes[24], nonce, 12); C.memcpy(&work.bytes[64], key, 64) }
	recovery_chacha(recovery, &work.bytes[24], &work.bytes[64])
	if !recovery_tag(recovery, &work.bytes[0], unsafe { &work.tag }) { return false }
	unsafe { C.memcpy(&work.bytes[128], &work.tag[0], 32); C.memcpy(output, &work.bytes[0], recovery_bytes) }
	return true
}

@[direct_array_access]
fn decode_recovery(bytes &u8, size int, recovery &u8, output &u8) bool {
	if size != recovery_bytes || recovery_equal(recovery, unsafe { recovery + 32 }, 32) { return false }
	unsafe { for i in 0 .. 8 { if bytes[i] != u8(c'VINIXKR1'[i]) { return false } } }
	if get_le(bytes, 8, 4) != 1 || get_le(bytes, 12, 4) != 1
		|| get_le(bytes, 16, 4) != recovery_bytes || get_le(bytes, 20, 4) != 64 { return false }
	unsafe { for i in 36 .. 64 { if bytes[i] != 0 { return false } } }
	mut work := unsafe { &RecoveryEnvelope(C.alloca(sizeof(RecoveryEnvelope))) }
	unsafe { *work = RecoveryEnvelope{} }
	defer { erase_key(work, sizeof(RecoveryEnvelope)) }
	if !recovery_tag(recovery, bytes, unsafe { &work.tag })
		|| !recovery_equal(&work.tag[0], unsafe { bytes + 128 }, 32) { return false }
	unsafe { C.memcpy(&work.key[0], bytes + 64, 64) }
	recovery_chacha(recovery, unsafe { bytes + 24 }, &work.key[0])
	if recovery_equal(&work.key[0], &work.key[32], 32)
		|| recovery_equal(&work.key[0], recovery, 64) { return false }
	unsafe { C.memcpy(output, &work.key[0], 64) }
	return true
}
