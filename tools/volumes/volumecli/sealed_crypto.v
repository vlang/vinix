// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

#include <sys/mman.h>
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.munmap(voidptr, usize) i32

const sealed_bytes = 192

struct SealedCrypto {
mut:
	bytes [192]u8
	message [192]u8
	key [64]u8
	tag [32]u8
}

// A single, bounded, private anonymous mapping holds the memory-hard vector.
// Never publish a candidate derived key until erasure and unmapping succeed.
fn sealed_derive(password &u8, size int, salt &u8, output &u8) bool {
	if size <= 0 || size > 1024 || password == unsafe { nil } || salt == unsafe { nil } || output == unsafe { nil } { return false }
	mut key := [64]u8{}
	defer { erase_key(unsafe { &key[0] }, sizeof(key)) }
	memory := C.mmap(unsafe { nil }, sealed_scrypt_memory, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if memory == unsafe { voidptr(C.MAP_FAILED) } { C.perror(c'vinix-volume: allocate scrypt workspace'); return false }
	valid := scrypt_core(password, size, salt, 16, sealed_scrypt_n, sealed_scrypt_r, sealed_scrypt_p,
		unsafe { &u32(memory) }, sealed_scrypt_memory, unsafe { &key[0] })
	erase_key(memory, sealed_scrypt_memory)
	for {
		if C.munmap(memory, sealed_scrypt_memory) == 0 { break }
		if unsafe { C.errno == C.EINTR } { continue }
		C.perror(c'vinix-volume: release erased scrypt workspace'); return false
	}
	if !valid { return false }
	unsafe { C.memcpy(output, &key[0], 64) }
	return true
}

fn sealed_header(bytes &u8, size int) bool {
	if size != sealed_bytes { return false }
	unsafe { for i in 0 .. 8 { if bytes[i] != u8(c'VINIXKP1'[i]) { return false } } }
	if get_le(bytes, 8, 4) != 1 || get_le(bytes, 12, 4) != 1 || get_le(bytes, 16, 4) != sealed_bytes
		|| get_le(bytes, 20, 4) != 64 || get_le(bytes, 24, 8) != sealed_scrypt_n
		|| get_le(bytes, 32, 4) != sealed_scrypt_r || get_le(bytes, 36, 4) != sealed_scrypt_p { return false }
	unsafe { for i in 68 .. 96 { if bytes[i] != 0 { return false } } }
	return true
}

fn sealed_tag(key &u8, bytes &u8, output &[32]u8) bool {
	mut work := unsafe { &SealedCrypto(C.alloca(sizeof(SealedCrypto))) }
	unsafe { *work = SealedCrypto{} }
	defer { erase_key(work, sizeof(SealedCrypto)) }
	unsafe { C.memcpy(&work.message[0], key, 32); C.memcpy(&work.message[32], bytes, 160) }
	return recovery_hmac(unsafe { key + 32 }, &work.message[0], 192, output)
}

@[direct_array_access]
fn encode_sealed_key(key &u8, wrapping &u8, random &u8, output &u8) bool {
	if recovery_equal(key, unsafe { key + 32 }, 32) || recovery_equal(wrapping, unsafe { wrapping + 32 }, 32)
		|| recovery_equal(key, wrapping, 64) { return false }
	mut work := unsafe { &SealedCrypto(C.alloca(sizeof(SealedCrypto))) }
	unsafe { *work = SealedCrypto{} }
	defer { erase_key(work, sizeof(SealedCrypto)) }
	unsafe { C.memcpy(&work.bytes[0], c'VINIXKP1', 8) }
	put_le(&work.bytes[0], 8, 4, 1); put_le(&work.bytes[0], 12, 4, 1)
	put_le(&work.bytes[0], 16, 4, sealed_bytes); put_le(&work.bytes[0], 20, 4, 64)
	put_le(&work.bytes[0], 24, 8, sealed_scrypt_n); put_le(&work.bytes[0], 32, 4, sealed_scrypt_r); put_le(&work.bytes[0], 36, 4, sealed_scrypt_p)
	unsafe { C.memcpy(&work.bytes[40], random, 28); C.memcpy(&work.bytes[96], key, 64) }
	recovery_chacha(wrapping, &work.bytes[56], &work.bytes[96])
	if !sealed_tag(wrapping, &work.bytes[0], unsafe { &work.tag }) { return false }
	unsafe { C.memcpy(&work.bytes[160], &work.tag[0], 32); C.memcpy(output, &work.bytes[0], sealed_bytes) }
	return true
}

@[direct_array_access]
fn decode_sealed_key(bytes &u8, size int, wrapping &u8, output &u8) bool {
	if !sealed_header(bytes, size) || recovery_equal(wrapping, unsafe { wrapping + 32 }, 32) { return false }
	mut work := unsafe { &SealedCrypto(C.alloca(sizeof(SealedCrypto))) }
	unsafe { *work = SealedCrypto{} }
	defer { erase_key(work, sizeof(SealedCrypto)) }
	if !sealed_tag(wrapping, bytes, unsafe { &work.tag }) || !recovery_equal(&work.tag[0], unsafe { bytes + 160 }, 32) { return false }
	unsafe { C.memcpy(&work.key[0], bytes + 96, 64) }
	recovery_chacha(wrapping, unsafe { bytes + 56 }, &work.key[0])
	if recovery_equal(&work.key[0], &work.key[32], 32) || recovery_equal(&work.key[0], wrapping, 64) { return false }
	unsafe { C.memcpy(output, &work.key[0], 64) }
	return true
}
