module krandom

import devicetree
import crypto.sha256

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

fn architecture_seed(mut output [64]u8) bool {
	arm64_random_state ^= read_counter()
	for i := 0; i < output.len; i += 8 {
		word := next_seed_word()
		unsafe { C.memcpy(&output[i], &word, 8) }
	}

	chosen := devicetree.find_node('/chosen') or { return false }
	seed := devicetree.get_property(chosen, 'rng-seed') or { return false }
	if seed.len < 32 || seed.len > 4096 {
		return false
	}
	domain := 'Vinix kernel CSPRNG v1'
	mut input := []u8{len: domain.len + int(seed.len) + 1}
	unsafe {
		C.memcpy(input.data, domain.str, domain.len)
		C.memcpy(&input[domain.len], seed.data, seed.len)
	}
	for i in 0 .. 2 {
		input[input.len - 1] = u8(i)
		digest := sha256.sum(input)
		unsafe {
			C.memcpy(&output[i * 32], digest.data, 32)
			C.memset(digest.data, 0, digest.len)
			digest.free()
		}
	}
	unsafe {
		C.memset(input.data, 0, input.len)
		input.free()
	}
	return true
}
