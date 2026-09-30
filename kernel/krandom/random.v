@[has_globals]
module krandom

import crypto.sha256
import klock

fn C.vinix_explicit_bzero(buf voidptr, len u64)
fn C.vinix_hw_random64(out &u64) int

// OpenBSD's explicit_bzero(3): clear memory that held a secret, with stores
// the compiler may not drop as dead, which it may do to a memset() of a buffer
// about to go out of scope.
pub fn explicit_bzero(buf voidptr, len u64) {
	C.vinix_explicit_bzero(buf, len)
}

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
	// Timings of events -- scheduler ticks, keystrokes -- folded together by
	// add_event() until stir() draws on them, as OpenBSD's random(4) pools
	// device interrupt timings for arc4random's reseeding.
	entropy_pool   [8]u64
	entropy_events u64
	// Whether stir() has run: the first reseed is logged.
	reseeded bool
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
	// Both working copies hold the key.
	explicit_bzero(&x[0], sizeof(x))
	explicit_bzero(&state[0], sizeof(state))
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
	explicit_bzero(&block[0], sizeof(block))
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
	explicit_bzero(&block[0], sizeof(block))
	// Fast key erasure, as arc4random does it: the key that produced this
	// request is replaced before anyone else can ask, from a block no caller
	// ever sees. Whoever reads the generator's state afterwards cannot work
	// back to what it has already handed out. An empty request changes
	// nothing, and one that ended exactly on a rekey needs no other.
	if count != 0 && this.output_ctr != 0 {
		this.rekey()
	}
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
	}
	explicit_bzero(&seed[0], sizeof(seed))
	generator = rng
}

// Fold an event into the pool: its value and the cycle counter at which it
// happened. Called on paths that must stay cheap, so it takes no lock; two
// CPUs racing lose a sample, nothing more.
pub fn add_event(value u64) {
	n := entropy_events
	entropy_events = n + 1
	i := n & 7
	v := entropy_pool[i]
	entropy_pool[i] = ((v << 7) | (v >> 57)) ^ cycle_counter() ^ (value * 0x9e3779b97f4a7c15)
}

// Reseed: hash the key together with the pooled event timings and whatever
// the CPU's own generator offers, and make that the new key. Without it the
// generator ran for the machine's whole life on its boot seed, so a state
// read out once predicted everything it would produce after; OpenBSD reseeds
// arc4random from the entropy pool every few minutes for the same reason.
// Called from a kernel thread: it allocates, so not from an interrupt.
pub fn stir() {
	if generator == unsafe { nil } {
		return
	}
	mut fresh := [4]u64{}
	mut fresh_words := 0
	for fresh_words < fresh.len && C.vinix_hw_random64(&fresh[fresh_words]) != 0 {
		fresh_words++
	}
	domain := 'Vinix kernel CSPRNG reseed v1'
	mut input := []u8{len: domain.len + 32 + 64 + 32 + 8} @[freed]
	mut at := domain.len
	unsafe { C.memcpy(input.data, domain.str, domain.len) }
	generator.lock.acquire()
	unsafe { C.memcpy(&input[at], &generator.key[0], 32) }
	generator.lock.release()
	at += 32
	unsafe {
		C.memcpy(&input[at], &entropy_pool[0], 64)
		C.memcpy(&input[at + 64], &fresh[0], 32)
		C.memcpy(&input[at + 96], &entropy_events, 8)
	}
	events := entropy_events
	explicit_bzero(&entropy_pool[0], 8 * sizeof(u64))
	explicit_bzero(&fresh[0], sizeof(fresh))
	digest := sha256.sum(input)

	generator.lock.acquire()
	// XORed in rather than put in place, so output taken since the key was
	// read above still counts towards the new one.
	for i := 0; i < 8; i++ {
		mut word := u32(0)
		unsafe { C.memcpy(&word, &digest[i * 4], 4) }
		generator.key[i] ^= word
	}
	generator.rekey()
	// A generator seeded from nothing better than the clock at boot becomes
	// trustworthy once the CPU has given it real entropy.
	if fresh_words == fresh.len {
		generator.secure = true
	}
	generator.lock.release()

	if !reseeded {
		reseeded = true
		C.kprintf(c'random: reseeded from %llu events, %d hardware words\n', events,
			fresh_words)
	}
	unsafe {
		explicit_bzero(digest.data, u64(digest.len))
		digest.free()
		explicit_bzero(input.data, u64(input.len))
		input.free()
	}
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

// Timing jitter, the entropy source of last resort. Apple Silicon has no
// FEAT_RNG, QEMU's default x86 CPU has no RDRAND, VirtualBox offers no VirtIO
// RNG and QEMU has one only when it is asked for, so a release image booted in
// any of them had no seed at all: getrandom() and /dev/urandom refused every
// caller, which is creating the first user and every TLS connection pkg makes. How long a data-dependent
// walk through memory takes varies with cache, TLB and host scheduling state.
// Sample that variation many times and fold the samples through SHA-256, as
// Linux's jitterentropy does. Refuse the result when the timings are too
// predictable: if the commonest timing turns up in 15 of every 16 samples,
// 16384 samples still carry over a thousand bits of min-entropy.
const jitter_samples = 16384
const jitter_walk = 256

__global (
	jitter_pool [65536]u8
)

fn jitter_entropy_seed(mut output [64]u8) bool {
	mut state := u64(0x2545f4914f6cdd1d) ^ cycle_counter()
	mut samples := []u8{len: jitter_samples * 2} @[freed]
	mut counts := [256]u32{}
	for i := 0; i <= jitter_samples; i++ {
		start := cycle_counter()
		for _ in 0 .. jitter_walk {
			state ^= state << 13
			state ^= state >> 7
			state ^= state << 17
			index := state % u64(jitter_pool.len)
			jitter_pool[index] += u8(state >> 32)
		}
		delta := cycle_counter() - start
		// The first walk warms the caches; its timing says little.
		if i > 0 {
			counts[delta & 0xff]++
			samples[(i - 1) * 2] = u8(delta)
			samples[(i - 1) * 2 + 1] = u8(delta >> 8)
		}
	}
	mut distinct := 0
	mut commonest := u32(0)
	for count in counts {
		if count != 0 {
			distinct++
		}
		if count > commonest {
			commonest = count
		}
	}
	healthy := distinct >= 4 && u64(commonest) * 16 < u64(jitter_samples) * 15
	if healthy {
		domain := 'Vinix kernel CSPRNG jitter v1'
		mut input := []u8{len: domain.len + samples.len + 1} @[freed]
		unsafe {
			C.memcpy(input.data, domain.str, domain.len)
			C.memcpy(&input[domain.len], samples.data, samples.len)
		}
		for i in 0 .. 2 {
			input[input.len - 1] = u8(i)
			digest := sha256.sum(input)
			unsafe {
				C.memcpy(&output[i * 32], digest.data, 32)
				explicit_bzero(digest.data, u64(digest.len))
				digest.free()
			}
		}
		unsafe {
			explicit_bzero(input.data, u64(input.len))
			input.free()
		}
	}
	outcome := if healthy { c'seeded the generator' } else { c'failed its health check' }
	share := u64(commonest) * 100 / u64(jitter_samples)
	C.kprintf(c'random: CPU timing jitter %s (%lld distinct timings, commonest %llu%%)\n',
		outcome, i64(distinct), u64(share))
	unsafe {
		explicit_bzero(samples.data, u64(samples.len))
		samples.free()
	}
	return healthy
}
