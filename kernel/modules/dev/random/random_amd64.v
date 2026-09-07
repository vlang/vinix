module random

import x86.cpu

__global (
	ur_rdrand = false
	ur_rdseed = false
)

fn architecture_reseed(mut rng URandom) {
	if ur_rdseed {
		for i in 0 .. rng.key.len {
			rng.key[i] ^= cpu.rdseed32()
		}
	} else if ur_rdrand {
		for i in 0 .. rng.key.len {
			rng.key[i] ^= cpu.rdrand32()
		}
	}
}

fn architecture_seed(mut rng URandom) {
	mut success, _, mut b, mut c, _ := cpu.cpuid(1, 0)
	if success && (c & (1 << 30)) != 0 {
		println('urandom: rdrand available')
		ur_rdrand = true
	}

	success, _, b, _, _ = cpu.cpuid(7, 0)
	if success && (b & (1 << 18)) != 0 {
		println('urandom: rdseed available')
		ur_rdseed = true
	}

	mut seed := cpu.rdtsc()
	rng.key[0] = u32(seed)
	rng.key[2] = u32(seed >> 32)
	seed = cpu.rdtsc()
	rng.buffer[0] = u32(seed)
	rng.buffer[2] = u32(seed >> 32)
	rng.reseed()
}
