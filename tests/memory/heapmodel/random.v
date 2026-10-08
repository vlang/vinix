// Seeded MT19937 fixture generator with CPython's integer seeding and draws.
// This keeps the original specification's random operation plan unchanged.
module heapmodel

pub struct Random {
mut:
	words [624]u32
	index int = 624
}

pub fn random(seed u64) Random {
	mut result := Random{}
	result.words[0] = 19650218
	for i in 1 .. 624 {
		previous := result.words[i - 1]
		result.words[i] = u32(1812433253) * (previous ^ (previous >> 30)) + u32(i)
	}
	mut keys := [u32(seed)]
	if seed >> 32 != 0 { keys << u32(seed >> 32) }
	mut i := 1
	mut j := 0
	for _ in 0 .. 624 {
		previous := result.words[i - 1]
		result.words[i] = (result.words[i] ^ ((previous ^ (previous >> 30)) * u32(1664525))) + keys[j] + u32(j)
		i++
		j++
		if i >= 624 {
			result.words[0] = result.words[623]
			i = 1
		}
		if j >= keys.len { j = 0 }
	}
	for _ in 0 .. 623 {
		previous := result.words[i - 1]
		result.words[i] = (result.words[i] ^ ((previous ^ (previous >> 30)) * u32(1566083941))) - u32(i)
		i++
		if i >= 624 {
			result.words[0] = result.words[623]
			i = 1
		}
	}
	result.words[0] = 0x80000000
	return result
}

pub fn (mut rng Random) word() u32 {
	if rng.index >= 624 {
		for i in 0 .. 624 {
			joined := (rng.words[i] & 0x80000000) | (rng.words[(i + 1) % 624] & 0x7fffffff)
			rng.words[i] = rng.words[(i + 397) % 624] ^ (joined >> 1) ^ (if joined & 1 != 0 {
				u32(0x9908b0df)
			} else {
				u32(0)
			})
		}
		rng.index = 0
	}
	mut value := rng.words[rng.index]
	rng.index++
	value ^= value >> 11
	value ^= (value << 7) & 0x9d2c5680
	value ^= (value << 15) & 0xefc60000
	return value ^ (value >> 18)
}

pub fn (mut rng Random) bits(width int) u64 {
	assert width >= 0 && width <= 64
	if width == 0 { return 0 }
	if width <= 32 { return u64(rng.word() >> u32(32 - width)) }
	low := u64(rng.word())
	high := u64(rng.word() >> u32(64 - width))
	return low | (high << 32)
}

pub fn (mut rng Random) fraction() f64 {
	a := u64(rng.word() >> 5)
	b := u64(rng.word() >> 6)
	return f64(a * u64(67108864) + b) / 9007199254740992.0
}

pub fn (mut rng Random) below(limit int) int {
	assert limit > 0
	mut width := 0
	mut remaining := limit
	for remaining > 0 {
		width++
		remaining >>= 1
	}
	for {
		candidate := rng.bits(width)
		if candidate < u64(limit) { return int(candidate) }
	}
	return 0
}
