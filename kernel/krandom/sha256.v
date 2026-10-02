// SPDX-License-Identifier: GPL-2.0-or-later
module krandom

// FIPS 180-4 SHA-256, using borrowed input/output and fixed stack workspace.
// The standard-library one-shot helper leaves its Digest and padding allocated
// with -gc none; repeated kernel reseeding must retain none of that workspace.
const sha256_constants = [u32(0x428a2f98), 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
	0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
	0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
	0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
	0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
	0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
	0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
	0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
	0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
	0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2]!

@[inline]
fn sha256_rotr(value u32, shift u32) u32 {
	return (value >> shift) | (value << (32 - shift))
}

fn sha256_compress(state &[8]u32, block &u8) {
	mut words := [64]u32{}
	for i in 0 .. 16 {
		at := i * 4
		unsafe {
			words[i] = u32(block[at]) << 24 | u32(block[at + 1]) << 16
				| u32(block[at + 2]) << 8 | u32(block[at + 3])
		}
	}
	for i in 16 .. 64 {
		left := words[i - 15]
		right := words[i - 2]
		lower := sha256_rotr(left, 7) ^ sha256_rotr(left, 18) ^ (left >> 3)
		upper := sha256_rotr(right, 17) ^ sha256_rotr(right, 19) ^ (right >> 10)
		words[i] = words[i - 16] + lower + words[i - 7] + upper
	}
	mut a := state[0]
	mut b := state[1]
	mut c := state[2]
	mut d := state[3]
	mut e := state[4]
	mut f := state[5]
	mut g := state[6]
	mut h := state[7]
	for i in 0 .. 64 {
		upper := sha256_rotr(e, 6) ^ sha256_rotr(e, 11) ^ sha256_rotr(e, 25)
		choose := (e & f) ^ (~e & g)
		first := h + upper + choose + sha256_constants[i] + words[i]
		lower := sha256_rotr(a, 2) ^ sha256_rotr(a, 13) ^ sha256_rotr(a, 22)
		majority := (a & b) ^ (a & c) ^ (b & c)
		second := lower + majority
		h = g
		g = f
		f = e
		e = d + first
		d = c
		c = b
		b = a
		a = first + second
	}
	unsafe {
		state[0] += a
		state[1] += b
		state[2] += c
		state[3] += d
		state[4] += e
		state[5] += f
		state[6] += g
		state[7] += h
	}
	explicit_bzero(unsafe { &words[0] }, sizeof(words))
}

fn sha256_digest(data &u8, length u64, output &[32]u8) {
	mut state := [u32(0x6a09e667), 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
		0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]!
	mut at := u64(0)
	for length - at >= 64 {
		sha256_compress(unsafe { &state }, unsafe { &data[at] })
		at += 64
	}
	mut padding := [128]u8{}
	remainder := int(length - at)
	if remainder != 0 {
		unsafe { C.memcpy(&padding[0], &data[at], usize(remainder)) }
	}
	padding[remainder] = 0x80
	blocks := if remainder < 56 { 64 } else { 128 }
	bits := length * 8
	for i in 0 .. 8 {
		padding[blocks - 1 - i] = u8(bits >> u64(i * 8))
	}
	sha256_compress(unsafe { &state }, unsafe { &padding[0] })
	if blocks == 128 {
		sha256_compress(unsafe { &state }, unsafe { &padding[64] })
	}
	for i in 0 .. 8 {
		for byte in 0 .. 4 {
			unsafe { output[i * 4 + byte] = u8(state[i] >> u32(24 - byte * 8)) }
		}
	}
	explicit_bzero(unsafe { &state[0] }, sizeof(state))
	explicit_bzero(unsafe { &padding[0] }, sizeof(padding))
}
