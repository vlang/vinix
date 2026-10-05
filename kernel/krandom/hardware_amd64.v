// SPDX-License-Identifier: GPL-2.0-or-later
module krandom

// Prefer RDSEED to RDRAND, and leave the output untouched on failure.
// Carry must be read in the same asm block as the random instruction.
@[export: 'vinix_hw_random64']
fn hardware_random64(out &u64) i32 {
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
		; a (u32(7))
		  c (u32(0))
	}
	have_rdseed := b & (1 << 18) != 0
	asm volatile amd64 {
		cpuid
		; =a (a)
		  =b (b)
		  =c (c)
		  =d (d)
		; a (u32(1))
		  c (u32(0))
	}
	if !have_rdseed && c & (1 << 30) == 0 {
		return 0
	}
	for _ in 0 .. 32 {
		mut value := u64(0)
		mut ok := u8(0)
		if have_rdseed {
			asm volatile amd64 {
				rdseed value
				setc ok
				; =r (value)
				  =qm (ok)
				; ; cc
			}
		} else {
			asm volatile amd64 {
				rdrand value
				setc ok
				; =r (value)
				  =qm (ok)
				; ; cc
			}
		}
		if ok != 0 {
			unsafe { *out = value }
			return 1
		}
	}
	return 0
}
