// SPDX-License-Identifier: GPL-2.0-or-later
module lib

fn stack_boot_entropy() u64 {
	mut low := u32(0)
	mut high := u32(0)
	asm volatile amd64 {
		rdtsc
		; =a (low)
		  =d (high)
	}
	mut entropy := u64(high) << 32 | u64(low)
	mut a := u32(0)
	mut b := u32(0)
	mut c := u32(0)
	mut d := u32(0)
	asm volatile amd64 {
		cpuid
		; =a (a)
		  =b (b)
		  =c (c)
		  =d (d)
		; a (u32(1))
		  c (u32(0))
	}
	if c & (u32(1) << 30) != 0 {
		for _ in 0 .. 16 {
			mut value := u64(0)
			mut ok := u8(0)
			asm volatile amd64 {
				rdrand value
				setc ok
				; =r (value)
				  =qm (ok)
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
