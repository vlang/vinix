// SPDX-License-Identifier: MIT
// Salsa20/8's round schedule follows V's crypto/scrypt (Kim Shrier, 2023).
// Copyright (c) 2023 Kim Shrier. Copyright (c) 2026 Vinix contributors.
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
module volumecli

// RFC 7914. Portable borrowed-memory implementation: only the caller allocates
// and erases the ROMix vector. All other secret state is a wiped stack workspace.
const sealed_scrypt_n = 32768
const sealed_scrypt_r = 8
const sealed_scrypt_p = 3
const sealed_scrypt_memory = 33554432

struct ScryptMac {
mut:
	inner DataSha256
	outer DataSha256
	context DataSha256
	pad [64]u8
	digest [32]u8
	tag [32]u8
	counter [4]u8
}

@[direct_array_access]
fn scrypt_mac_init(password &u8, size int, mut mac ScryptMac) bool {
	for i in 0 .. 64 { mac.pad[i] = 0x36 }
	if size > 64 {
		data_sha_init(mut mac.context)
		if !data_sha_update(mut mac.context, password, usize(size)) || !data_sha_finish(&mac.context, unsafe { &mac.digest }) { return false }
		for i in 0 .. 32 { mac.pad[i] ^= mac.digest[i] }
	} else { unsafe { for i in 0 .. size { mac.pad[i] ^= password[i] } } }
	data_sha_init(mut mac.inner)
	if !data_sha_update(mut mac.inner, &mac.pad[0], 64) { return false }
	for i in 0 .. 64 { mac.pad[i] ^= 0x36 ^ 0x5c }
	data_sha_init(mut mac.outer)
	return data_sha_update(mut mac.outer, &mac.pad[0], 64)
}

@[direct_array_access]
fn scrypt_pbkdf_once(mut mac ScryptMac, salt &u8, size int, output &u8, length int) bool {
	for at := 0; at < length; at += 32 {
		counter := u32(at / 32 + 1)
		for i in 0 .. 4 { mac.counter[i] = u8(counter >> u32(24 - i * 8)) }
		unsafe { C.memcpy(&mac.context, &mac.inner, sizeof(DataSha256)) }
		if !data_sha_update(mut mac.context, salt, usize(size))
			|| !data_sha_update(mut mac.context, &mac.counter[0], 4)
			|| !data_sha_finish(&mac.context, unsafe { &mac.digest }) { return false }
		unsafe { C.memcpy(&mac.context, &mac.outer, sizeof(DataSha256)) }
		if !data_sha_update(mut mac.context, &mac.digest[0], 32)
			|| !data_sha_finish(&mac.context, unsafe { &mac.tag }) { return false }
		part := if length - at < 32 { length - at } else { 32 }
		unsafe { C.memcpy(output + at, &mac.tag[0], usize(part)) }
	}
	return true
}

struct ScryptWork {
mut:
	mac ScryptMac
	b [16384]u8
	x [256]u32
	y [256]u32
	salsa [16]u32
	words [16]u32
	result [64]u8
}

@[direct_array_access]
fn scrypt_salsa(block &[16]u32, words &[16]u32) {
	unsafe {
		C.memcpy(words, block, 64)
		for _ in 0 .. 4 {
			words[4] ^= recovery_rotate(words[0] + words[12], 7)
			words[8] ^= recovery_rotate(words[4] + words[0], 9)
			words[12] ^= recovery_rotate(words[8] + words[4], 13)
			words[0] ^= recovery_rotate(words[12] + words[8], 18)
			words[9] ^= recovery_rotate(words[5] + words[1], 7)
			words[13] ^= recovery_rotate(words[9] + words[5], 9)
			words[1] ^= recovery_rotate(words[13] + words[9], 13)
			words[5] ^= recovery_rotate(words[1] + words[13], 18)
			words[14] ^= recovery_rotate(words[10] + words[6], 7)
			words[2] ^= recovery_rotate(words[14] + words[10], 9)
			words[6] ^= recovery_rotate(words[2] + words[14], 13)
			words[10] ^= recovery_rotate(words[6] + words[2], 18)
			words[3] ^= recovery_rotate(words[15] + words[11], 7)
			words[7] ^= recovery_rotate(words[3] + words[15], 9)
			words[11] ^= recovery_rotate(words[7] + words[3], 13)
			words[15] ^= recovery_rotate(words[11] + words[7], 18)
			words[1] ^= recovery_rotate(words[0] + words[3], 7)
			words[2] ^= recovery_rotate(words[1] + words[0], 9)
			words[3] ^= recovery_rotate(words[2] + words[1], 13)
			words[0] ^= recovery_rotate(words[3] + words[2], 18)
			words[6] ^= recovery_rotate(words[5] + words[4], 7)
			words[7] ^= recovery_rotate(words[6] + words[5], 9)
			words[4] ^= recovery_rotate(words[7] + words[6], 13)
			words[5] ^= recovery_rotate(words[4] + words[7], 18)
			words[11] ^= recovery_rotate(words[10] + words[9], 7)
			words[8] ^= recovery_rotate(words[11] + words[10], 9)
			words[9] ^= recovery_rotate(words[8] + words[11], 13)
			words[10] ^= recovery_rotate(words[9] + words[8], 18)
			words[12] ^= recovery_rotate(words[15] + words[14], 7)
			words[13] ^= recovery_rotate(words[12] + words[15], 9)
			words[14] ^= recovery_rotate(words[13] + words[12], 13)
			words[15] ^= recovery_rotate(words[14] + words[13], 18)
		}
		for i in 0 .. 16 { block[i] += words[i] }
	}
}

@[direct_array_access]
fn scrypt_block_mix(mut work ScryptWork, r int) {
	unsafe {
		C.memcpy(&work.salsa[0], &work.x[(2 * r - 1) * 16], 64)
		for i in 0 .. 2 * r {
			for j in 0 .. 16 { work.salsa[j] ^= work.x[i * 16 + j] }
			scrypt_salsa(&work.salsa, &work.words)
			at := (i / 2 + if i % 2 == 0 { 0 } else { r }) * 16
			C.memcpy(&work.y[at], &work.salsa[0], 64)
		}
		C.memcpy(&work.x[0], &work.y[0], usize(128 * r))
	}
}

// p<=16 and r<=8 cover the standard vectors. Production always uses the fixed
// N=32768,r=8,p=3 profile; file metadata cannot choose an allocation or work cost.
@[direct_array_access]
fn scrypt_core(password &u8, size int, salt &u8, salt_size int, n int, r int, p int,
	vector &u32, vector_bytes usize, output &u8) bool {
	if size < 0 || size > 1024 || salt_size < 0 || salt_size > 1024 || n < 2 || n > sealed_scrypt_n
		|| n & (n - 1) != 0 || r < 1 || r > 8 || p < 1 || p > 16
		|| vector_bytes < usize(n * 128 * r) || vector == unsafe { nil } || unsafe { usize(vector) } % 4 != 0 || output == unsafe { nil }
		|| (size != 0 && password == unsafe { nil }) || (salt_size != 0 && salt == unsafe { nil }) { return false }
	mut work := unsafe { &ScryptWork(C.alloca(sizeof(ScryptWork))) }
	unsafe { *work = ScryptWork{} }
	defer { erase_key(work, sizeof(ScryptWork)) }
	if !scrypt_mac_init(password, size, mut work.mac)
		|| !scrypt_pbkdf_once(mut work.mac, salt, salt_size, &work.b[0], 128 * r * p) { return false }
	for lane in 0 .. p {
		for i in 0 .. 32 * r { work.x[i] = u32(get_le(&work.b[0], lane * 128 * r + i * 4, 4)) }
		unsafe {
			for i in 0 .. n { C.memcpy(vector + i * 32 * r, &work.x[0], usize(128 * r)); scrypt_block_mix(mut *work, r) }
			for _ in 0 .. n {
				// N<=32768: Integerify's low 32 bits determine the same N-1 mask.
				row := int(work.x[(2 * r - 1) * 16] & u32(n - 1))
				for i in 0 .. 32 * r { work.x[i] ^= vector[row * 32 * r + i] }
				scrypt_block_mix(mut *work, r)
			}
		}
		for i in 0 .. 32 * r { put_le(&work.b[0], lane * 128 * r + i * 4, 4, work.x[i]) }
	}
	if !scrypt_pbkdf_once(mut work.mac, &work.b[0], 128 * r * p, &work.result[0], 64) { return false }
	unsafe { C.memcpy(output, &work.result[0], 64) }
	return true
}
