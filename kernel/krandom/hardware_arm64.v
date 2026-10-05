// SPDX-License-Identifier: GPL-2.0-or-later
module krandom

// RNDR is optional (QEMU's max CPU has it; the M1 does not).
@[export: 'vinix_hw_random64']
fn hardware_random64(out &u64) i32 {
	mut isar0 := u64(0)
	asm volatile aarch64 {
		mrs isar0, ID_AA64ISAR0_EL1
		; =r (isar0)
	}
	if (isar0 >> 60) & 0xf == 0 {
		return 0
	}
	for _ in 0 .. 32 {
		mut value := u64(0)
		mut ok := u64(0)
		asm volatile aarch64 {
			mrs value, S3_3_C2_C4_0
			cset ok, ne
			; =r (value)
			  =r (ok)
			; ; cc
		}
		if ok != 0 {
			unsafe { *out = value }
			return 1
		}
	}
	return 0
}
