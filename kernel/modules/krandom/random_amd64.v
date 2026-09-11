module krandom

import x86.cpu

__global (
	ur_rdrand = false
	ur_rdseed = false
)

fn architecture_seed(mut output [64]u8) bool {
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

	for i := 0; i < output.len; i += 4 {
		mut word := u32(0)
		if ur_rdseed {
			word = cpu.rdseed32()
		} else if ur_rdrand {
			word = cpu.rdrand32()
		} else {
			stamp := cpu.rdtsc()
			word = u32(stamp ^ (stamp >> 32) ^ u64(i))
		}
		unsafe { C.memcpy(&output[i], &word, 4) }
	}
	return ur_rdseed || ur_rdrand
}
