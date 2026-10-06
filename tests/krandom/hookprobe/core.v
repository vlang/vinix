// SPDX-License-Identifier: GPL-2.0-or-later
// ABI oracle linked separately to the immutable C and production V models.
@[has_globals]
module hookprobe

#include <host-native-abi.h>
@[typedef]
struct C.vkrandom_host_ld {}
@[typedef]
struct C.vkrandom_host_ull {}
fn C.strtold(&char, &&char) C.vkrandom_host_ld
fn C.kprintf(&char, ...) i32
fn C.printf(&char, ...) i32
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.vinix_hw_random64(&u64) i32
fn C.vinix_test_set_hardware(i32)

@[export: 'main']
pub fn run() i32 {
	unsafe {
		mut word := u64(0x12345678)
		if C.vinix_hw_random64(&word) != 0 || word != 0x12345678 { return 1 }
		C.vinix_test_set_hardware(-7)
		for _ in 0 .. 512 {
			if C.vinix_hw_random64(&word) != 1 { return 2 }
			mut native := C.vkrandom_host_ull{}
			C.memcpy(&native, &word, sizeof(u64))
			C.printf(c'HW %016llx\n', native)
		}
		C.vinix_test_set_hardware(0)
		old := word
		if C.vinix_hw_random64(&word) != 0 || old != word { return 3 }
		C.vinix_test_set_hardware(2)
		if C.vinix_hw_random64(&word) != 1 { return 4 }
		mut final := C.vkrandom_host_ull{}
		C.memcpy(&final, &word, sizeof(u64))
		C.printf(c'RESUME %016llx\n', final)
		mut count := i32(-1)
		r1 := C.kprintf(c'plain\n')
		r2 := C.kprintf(c'int %d %d %d %d %d %d %d %d %d %d\n', i32(1), i32(-2), i32(3), i32(-4), i32(5), i32(-6), i32(7), i32(-8), i32(9), i32(-10))
		r3 := C.kprintf(c'fp %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f\n', f64(1.25), f64(-2.5), f64(3.75), f64(-4.125), f64(5.25), f64(-6.5), f64(7.75), f64(-8.125), f64(9.25), f64(-10.5))
		ld := C.strtold(c'1.25', nil)
		r4 := C.kprintf(c'mixed %d %s %.3f %d %s %.3f %d %s %.3f %d %s %.3f %d %s %.3Lf\n', i32(10), c'a', f64(0.5), i32(20), c'b', f64(-0.25), i32(30), c'c', f64(4.5), i32(40), c'd', f64(-8.25), i32(50), c'e', ld)
		r5 := C.kprintf(c'count%n %.*s %.3Lf %a\n', &count, i32(3), c'abcdef', ld, f64(0.125))
		if r1 != 6 || r2 <= 0 || r3 <= 0 || r4 <= 0 || r5 <= 0 || count != 5 { return 5 }
		C.printf(c'COUNTS %d %d %d %d %d\n', r1, r2, r3, r4, r5)
		C.printf(c'KRANDOM HOST HOOK PASS\n')
		return 0
	}
}
