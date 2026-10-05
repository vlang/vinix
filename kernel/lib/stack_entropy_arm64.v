// SPDX-License-Identifier: GPL-2.0-or-later
module lib

fn stack_boot_entropy() u64 {
	mut entropy := u64(0)
	asm volatile arm64 {
		mrs entropy, cntvct_el0
		; =r (entropy)
	}
	mut isar0 := u64(0)
	asm volatile arm64 {
		mrs isar0, id_aa64isar0_el1
		; =r (isar0)
	}
	if isar0 >> 60 & 0xf != 0 {
		for _ in 0 .. 16 {
			mut value := u64(0)
			mut ok := u64(0)
			asm volatile arm64 {
				mrs value, s3_3_c2_c4_0
				cset ok, ne
				; =r (value)
				  =r (ok)
				; ; cc
			}
			if ok != 0 {
				entropy = stack_mix64(entropy) ^ value
				break
			}
		}
	}
	return entropy
}
