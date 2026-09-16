@[has_globals]
module krandom

import klock

struct Generator {
mut:
	lock       klock.Lock
	key        [8]u32
	nonce      [2]u32
	counter    u64
	output_ctr u64
	secure     bool
}

__global (
	generator &Generator
)

@[inline]
fn rotl32(a u32, shift u32) u32 {
	return (a << shift) | (a >> (32 - shift))
}

@[inline]
fn qr(a &u32, b &u32, c &u32, d &u32) {
	unsafe {
		*a += *b
		*d = rotl32(*d ^ *a, 16)
		*c += *d
		*b = rotl32(*b ^ *c, 12)
		*a += *b
		*d = rotl32(*d ^ *a, 8)
		*c += *d
		*b = rotl32(*b ^ *c, 7)
	}
}

// Generate one RFC 8439 ChaCha20 block. The caller serialises access.
fn (mut this Generator) block(mut out [16]u32) {
	mut state := [16]u32{}
	state[0] = 0x61707865
	state[1] = 0x3320646e
	state[2] = 0x79622d32
	state[3] = 0x6b206574
	for i := 0; i < 8; i++ {
		state[4 + i] = this.key[i]
	}
	state[12] = u32(this.counter)
	state[13] = u32(this.counter >> 32)
	state[14] = this.nonce[0]
	state[15] = this.nonce[1]
	this.counter++

	mut x := state
	for _ in 0 .. 10 {
		qr(&x[0], &x[4], &x[8], &x[12])
		qr(&x[1], &x[5], &x[9], &x[13])
		qr(&x[2], &x[6], &x[10], &x[14])
		qr(&x[3], &x[7], &x[11], &x[15])
		qr(&x[0], &x[5], &x[10], &x[15])
		qr(&x[1], &x[6], &x[11], &x[12])
		qr(&x[2], &x[7], &x[8], &x[13])
		qr(&x[3], &x[4], &x[9], &x[14])
	}
	for i := 0; i < 16; i++ {
		out[i] = x[i] + state[i]
	}
}

fn (mut this Generator) rekey() {
	mut block := [16]u32{}
	this.block(mut block)
	for i := 0; i < 8; i++ {
		this.key[i] = block[i]
	}
	this.nonce[0] = block[8]
	this.nonce[1] = block[9]
	this.counter = 0
	this.output_ctr = 0
	unsafe { C.memset(&block[0], 0, sizeof(block)) }
}

fn (mut this Generator) fill_locked(buf voidptr, count u64) {
	mut remaining := count
	mut target := buf
	mut block := [16]u32{}
	for remaining != 0 {
		this.block(mut block)
		chunk := if remaining > 64 { u64(64) } else { remaining }
		unsafe { C.memcpy(target, &block[0], chunk) }
		target = voidptr(u64(target) + chunk)
		remaining -= chunk
		this.output_ctr += chunk
		if this.output_ctr >= 1024 * 1024 {
			this.rekey()
		}
	}
	unsafe { C.memset(&block[0], 0, sizeof(block)) }
}

pub fn initialise() {
	if generator != unsafe { nil } {
		return
	}
	mut seed := [64]u8{}
	secure := architecture_seed(mut seed)
	mut rng := &Generator{
		secure: secure
	}
	for i := 0; i < 8; i++ {
		unsafe { C.memcpy(&rng.key[i], &seed[i * 4], 4) }
	}
	unsafe {
		C.memcpy(&rng.nonce[0], &seed[32], 4)
		C.memcpy(&rng.nonce[1], &seed[36], 4)
		C.memcpy(&rng.counter, &seed[40], 8)
		C.memset(&seed[0], 0, sizeof(seed))
	}
	generator = rng
}

pub fn is_ready() bool {
	return generator != unsafe { nil } && generator.secure
}

// fill writes CSPRNG output to a kernel buffer. Timer-only boot state is
// available solely to explicitly insecure callers; getrandom(2) never treats
// it as entropy.
pub fn fill(buf voidptr, count u64, allow_insecure bool) bool {
	if generator == unsafe { nil } || (!generator.secure && !allow_insecure) {
		return false
	}
	generator.lock.acquire()
	generator.fill_locked(buf, count)
	generator.lock.release()
	return true
}
