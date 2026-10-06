// Independent memory primitive oracle. Original domains and check names remain.
@[has_globals]
module runtimefixture

#include <memory-runtime-native-abi.h>
@[typedef]
struct C.FILE {}
@[c_extern]
__global C.stderr &C.FILE
__global memory_runtime_cases usize

fn C.vinix_memcpy(voidptr, voidptr, usize) voidptr
fn C.vinix_memset(voidptr, i32, usize) voidptr
fn C.vinix_memmove(voidptr, voidptr, usize) voidptr
fn C.vinix_memcmp(voidptr, voidptr, usize) i32
fn C.vinix_atoi(&char) i32
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.fprintf(&C.FILE, &char, ...) i32
fn C.printf(&char, ...) i32
fn C.exit(i32)
fn C.mmap(voidptr, usize, i32, i32, i32, isize) voidptr
fn C.mprotect(voidptr, usize, i32) i32
fn C.munmap(voidptr, usize) i32
fn C.sysconf(i32) isize

fn check(ok bool, where &char, n usize, a usize, b usize) {
	if !ok { unsafe { C.fprintf(C.stderr, c'FAIL %s n=%zu a=%zu b=%zu\n', where, n, a, b) }; C.exit(1) }
}
fn pattern(i usize) u8 { return u8(i * 131 + (i >> 4) * 17 + 23) }

fn copy_case(dst &u8, src &u8, whole usize, d usize, s usize, n usize) {
	unsafe {
		for i := usize(0); i < whole; i++ { dst[i] = 0xa5 }
		check(C.vinix_memcpy(dst + d, src + s, n) == dst + d, c'memcpy return', n, d, s)
		for i := usize(0); i < whole; i++ {
			check(dst[i] == if i >= d && i - d < n { src[s + i - d] } else { u8(0xa5) }, c'memcpy content/bounds', n, d, s)
		}
		memory_runtime_cases++
	}
}
fn set_case(dst &u8, whole usize, d usize, n usize, value i32) {
	unsafe {
		for i := usize(0); i < whole; i++ { dst[i] = 0xa5 }
		check(C.vinix_memset(dst + d, value, n) == dst + d, c'memset return', n, d, usize(value))
		for i := usize(0); i < whole; i++ {
			check(dst[i] == if i >= d && i - d < n { u8(value) } else { u8(0xa5) }, c'memset content/bounds', n, d, usize(value))
		}
		memory_runtime_cases++
	}
}
fn move_case(dst &u8, whole usize, d usize, s usize, n usize) {
	unsafe {
		for i := usize(0); i < whole; i++ { dst[i] = pattern(i) }
		check(C.vinix_memmove(dst + d, dst + s, n) == dst + d, c'memmove return', n, d, s)
		for i := usize(0); i < whole; i++ {
			check(dst[i] == pattern(if i >= d && i - d < n { s + i - d } else { i }), c'memmove content/bounds', n, d, s)
		}
		memory_runtime_cases++
	}
}
fn sign(value i32) i32 { return if value > 0 { i32(1) } else if value < 0 { i32(-1) } else { i32(0) } }
fn compare_case(a &u8, b &u8, n usize) {
	expected := C.memcmp(a, b, n)
	actual := C.vinix_memcmp(a, b, n)
	check(sign(actual) == sign(expected), c'memcmp sign', n, 0, 0)
	memory_runtime_cases++
}
fn atoi_cases() {
	unsafe {
		values := [&char(c''), c' \t\n\r\f\v', c'+', c'-', c'word', c'0', c'00042', c'-42', c'+42tail',
			c' \t\n\r\f\v-123rest', c'+ 42', c'2147483647', c'-2147483648']!
		expected := [i32(0), 0, 0, 0, 0, 0, 42, -42, 42, -123, 0, 2147483647, -2147483647 - 1]!
		for i := usize(0); i < values.len; i++ {
			check(C.vinix_atoi(values[i]) == expected[i], c'atoi', i, 0, 0)
			memory_runtime_cases++
		}
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		page := usize(C.sysconf(C._SC_PAGESIZE))
		sm := &u8(C.mmap(nil, page * 3, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
		dm := &u8(C.mmap(nil, page * 3, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
		check(voidptr(sm) != voidptr(C.MAP_FAILED) && voidptr(dm) != voidptr(C.MAP_FAILED), c'mmap', 0, 0, 0)
		src := sm + page
		dst := dm + page
		check(C.mprotect(src, page, C.PROT_READ | C.PROT_WRITE) == 0 && C.mprotect(dst, page, C.PROT_READ | C.PROT_WRITE) == 0, c'mprotect', 0, 0, 0)
		for i := usize(0); i < page; i++ { src[i] = pattern(i) }
		check(C.mprotect(src, page, C.PROT_READ) == 0, c'source read-only', 0, 0, 0)
		for d in usize(0) .. usize(16) { for s in usize(0) .. usize(16) { for n in usize(0) .. usize(258) { copy_case(dst, src, 512, d, s, n) } } }
		for d in usize(0) .. usize(16) { for s in usize(0) .. usize(16) { for n in usize(0) .. usize(258) { move_case(dst, 512, d, s, n) } } }
		values := [i32(0), 1, 127, 128, 255, -1, -256, 0x1234]!
		for d in usize(0) .. usize(16) { for n in usize(0) .. usize(258) { for c in usize(0) .. usize(values.len) { set_case(dst, 512, d, n, values[c]) } } }
		mut n := usize(0)
		for n <= page {
			for i := usize(0); i < page; i++ { dst[i] = pattern(i) }
			compare_case(src + page - n, dst + page - n, n)
			if n != 0 { dst[page - 1] ^= 0xff; compare_case(src + page - n, dst + page - n, n); compare_case(dst + page - n, src + page - n, n) }
			copy_case(dst, src, page, page - n, page - n, n)
			if n <= page - 7 { copy_case(dst, src, page, page - n, 7, n) }
			set_case(dst, page, page - n, n, -1)
			set_case(dst, page, 0, n, 0)
			distances := [usize(1), 7, 8, 64]!
			for j := usize(0); j < distances.len; j++ {
				distance := distances[j]
				if n <= page - distance { move_case(dst, page, distance, 0, n); move_case(dst, page, 0, distance, n) }
			}
			n++
		}
		check(C.vinix_memcpy(dm, sm, 0) == dm, c'zero memcpy', 0, 0, 0)
		check(C.vinix_memset(dm, 0, 0) == dm, c'zero memset', 0, 0, 0)
		check(C.vinix_memmove(dm, sm, 0) == dm, c'zero memmove', 0, 0, 0)
		check(C.vinix_memcmp(dm, sm, 0) == 0, c'zero memcmp', 0, 0, 0)
		atoi_cases()
		check(C.munmap(sm, page * 3) == 0 && C.munmap(dm, page * 3) == 0, c'munmap', 0, 0, 0)
		C.printf(c'KERNEL MEMORY CHECK: PASS cases=%zu page=%zu\n', memory_runtime_cases, page)
	}
	return 0
}
