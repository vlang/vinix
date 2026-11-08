// SPDX-License-Identifier: GPL-2.0-or-later
// ChaCha20 core and SHA-256 adapted from kernel/krandom. Explicit byte order
// keeps the stream identical on PPC and the host. The single CPU serializes it.
module entropy

pub struct Generator {
pub mut:
	ready bool
mut:
	key [8]u32
	counter u64
}

fn rotl(a u32, n u32) u32 { return a << n | a >> (32 - n) }
fn qr(a &u32, b &u32, c &u32, d &u32) {
	unsafe {
		*a += *b; *d = rotl(*d ^ *a, 16)
		*c += *d; *b = rotl(*b ^ *c, 12)
		*a += *b; *d = rotl(*d ^ *a, 8)
		*c += *d; *b = rotl(*b ^ *c, 7)
	}
}

fn (mut g Generator) block(output &u8) {
	mut state := [16]u32{}
	state[0] = 0x61707865; state[1] = 0x3320646e
	state[2] = 0x79622d32; state[3] = 0x6b206574
	for i in 0 .. 8 { state[i + 4] = g.key[i] }
	state[12] = u32(g.counter); state[13] = u32(g.counter >> 32)
	g.counter++
	mut x := state
	for _ in 0 .. 10 {
		qr(&x[0], &x[4], &x[8], &x[12]); qr(&x[1], &x[5], &x[9], &x[13])
		qr(&x[2], &x[6], &x[10], &x[14]); qr(&x[3], &x[7], &x[11], &x[15])
		qr(&x[0], &x[5], &x[10], &x[15]); qr(&x[1], &x[6], &x[11], &x[12])
		qr(&x[2], &x[7], &x[8], &x[13]); qr(&x[3], &x[4], &x[9], &x[14])
	}
	for i in 0 .. 16 {
		word := x[i] + state[i]
		for j in 0 .. 4 { unsafe { output[i * 4 + j] = u8(word >> (j * 8)) } }
	}
	explicit_bzero(&x[0], sizeof(x)); explicit_bzero(&state[0], sizeof(state))
}

pub fn (mut g Generator) seed(key &u8) {
	for i in 0 .. 8 {
		unsafe { g.key[i] = u32(key[i * 4]) | u32(key[i * 4 + 1]) << 8 | u32(key[i * 4 + 2]) << 16 | u32(key[i * 4 + 3]) << 24 }
	}
	g.counter = 0
	g.ready = true
}

pub fn (mut g Generator) fill(output &u8, count u32) bool {
	if !g.ready { return false }
	if count == 0 { return true }
	mut block := [64]u8{}
	for at := u32(0); at < count; {
		g.block(unsafe { &block[0] })
		amount := if count - at > 64 { u32(64) } else { count - at }
		for i := u32(0); i < amount; i++ { unsafe { output[at + i] = block[i] } }
		at += amount
	}
	// Fast key erasure: the next key comes from a block never exposed.
	g.block(unsafe { &block[0] })
	g.seed(unsafe { &block[0] })
	explicit_bzero(&block[0], sizeof(block))
	return true
}

// Domain-separated hashes derive the current boot key and the next seed.
// The caller MUST persist and flush next before enabling the current key.
pub fn derive(old &u8, key &[32]u8, next &[32]u8) {
	mut input := [33]u8{}
	for i in 0 .. 32 { input[i + 1] = unsafe { old[i] } }
	input[0] = 0
	sha256_digest(unsafe { &input[0] }, 33, key)
	input[0] = 1
	sha256_digest(unsafe { &input[0] }, 33, next)
	explicit_bzero(&input[0], sizeof(input))
}
