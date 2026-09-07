module random

__global (
	arm64_random_state = u64(0x9e3779b97f4a7c15)
)

fn read_counter() u64 {
	mut counter := u64(0)
	asm volatile aarch64 {
		mrs counter, CNTVCT_EL0
		; =r (counter)
	}
	return counter
}

fn next_seed_word() u64 {
	arm64_random_state += 0x9e3779b97f4a7c15
	mut word := arm64_random_state ^ read_counter()
	word = (word ^ (word >> 30)) * 0xbf58476d1ce4e5b9
	word = (word ^ (word >> 27)) * 0x94d049bb133111eb
	return word ^ (word >> 31)
}

fn architecture_reseed(mut rng URandom) {
	for i in 0 .. rng.key.len {
		rng.key[i] ^= u32(next_seed_word())
	}
}

fn architecture_seed(mut rng URandom) {
	arm64_random_state ^= read_counter()
	for i in 0 .. rng.buffer.len {
		rng.buffer[i] = u32(next_seed_word())
		rng.key[i] = u32(next_seed_word())
	}
}
