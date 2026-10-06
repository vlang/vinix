// Independent console policy, chunk boundary and native variadic fixture.
@[has_globals]
module fixture

#include <fixture-v-abi.h>
@[typedef]
struct C.vprint_ull {}
@[typedef]
struct C.vprint_ll {}
fn C.assert(bool)
fn C.memset(voidptr, i32, usize) voidptr
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.fixture_printf(&char, ...) i32
fn C.fixture_panic(&char, ...) i32
fn C.fixture_kprintf(&char, ...) i32
fn C.fixture_benchmark(&char, ...) i32
fn C.fixture_fprintf(voidptr, &char, ...) i32

__global (
	print_fixture_serial [4096]u8
	print_fixture_terminal [4096]u8
	print_fixture_serial_len usize
	print_fixture_terminal_len usize
	print_fixture_chunks usize
	print_fixture_largest usize
	print_fixture_acquired u32
	print_fixture_released u32
)

@[export: 'fixture_serial']
pub fn serial(byte u8, _panic i32) {
	unsafe {
		C.assert(print_fixture_serial_len < 4096)
		print_fixture_serial[print_fixture_serial_len] = byte
		print_fixture_serial_len++
	}
}

@[export: 'fixture_terminal']
pub fn terminal(text &char, length u64) {
	unsafe {
		C.assert(length <= 4096 - print_fixture_terminal_len)
		C.memcpy(&print_fixture_terminal[print_fixture_terminal_len], text, usize(length))
		print_fixture_terminal_len += usize(length)
	}
}

@[export: 'fixture_kwrite']
pub fn kwrite(text &char, length u64) {
	unsafe {
		C.assert(length > 0 && length <= 256)
		print_fixture_chunks++
		if length > print_fixture_largest { print_fixture_largest = usize(length) }
		terminal(text, length)
	}
}

@[export: 'fixture_acquire']
pub fn acquire() { unsafe { print_fixture_acquired++ } }

@[export: 'fixture_release']
pub fn release() { unsafe { print_fixture_released++ } }

fn reset() {
	unsafe {
		print_fixture_serial_len = 0
		print_fixture_terminal_len = 0
		print_fixture_chunks = 0
		print_fixture_largest = 0
		print_fixture_acquired = 0
		print_fixture_released = 0
	}
}

fn ull(value u64) C.vprint_ull {
	mut result := C.vprint_ull{}
	unsafe { C.memcpy(&result, &value, sizeof(u64)) }
	return result
}

fn ll(value i64) C.vprint_ll {
	mut result := C.vprint_ll{}
	unsafe { C.memcpy(&result, &value, sizeof(i64)) }
	return result
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		mut data := [1026]char{}
		C.memset(&data[0], i32(`x`), 1026)
		data[1025] = 0
		for n in i32(0) .. i32(1026) {
			reset()
			C.assert(C.fixture_kprintf(c'%.*s', n, &data[0]) == n)
			C.assert(print_fixture_terminal_len == usize(n) && print_fixture_serial_len == 0)
			C.assert(C.memcmp(&print_fixture_terminal[0], &data[0], usize(n)) == 0)
			C.assert(print_fixture_chunks == (usize(n) + 255) / 256)
			C.assert(print_fixture_largest == usize(if n > 256 { i32(256) } else { n }))
			C.assert(print_fixture_acquired == 0 && print_fixture_released == 0)
		}
		reset()
		C.assert(C.fixture_kprintf(c'[%llu,%lld,%llx,%c]', ull(~u64(0)), ll(-i64(9223372036854775807) - 1), ull(0xfeed), i32(0)) == 50)
		expected := &char(c'[18446744073709551615,-9223372036854775808,feed,\x00]')
		C.assert(print_fixture_terminal_len == 50)
		C.assert(C.memcmp(&print_fixture_terminal[0], expected, 50) == 0)
		reset()
		ordinary := C.fixture_printf(c'%s:%u', c'serial', u32(17))
		if C.VINIX_PRINT_FIXTURE_PROD == 1 {
			C.assert(ordinary == 0 && print_fixture_serial_len == 0 && print_fixture_acquired == 0 && print_fixture_released == 0)
		} else {
			C.assert(ordinary == 9 && print_fixture_serial_len == 9 && print_fixture_acquired == 1 && print_fixture_released == 1)
			C.assert(C.memcmp(&print_fixture_serial[0], c'serial:17', 9) == 0)
		}
		C.assert(print_fixture_terminal_len == 0)
		reset()
		C.assert(C.fixture_panic(c'%s:%u', c'panic', u32(23)) == 8)
		C.assert(print_fixture_serial_len == 8 && print_fixture_terminal_len == 8)
		C.assert(C.memcmp(&print_fixture_serial[0], c'panic:23', 8) == 0 && C.memcmp(&print_fixture_serial[0], &print_fixture_terminal[0], 8) == 0)
		C.assert(print_fixture_acquired == 0 && print_fixture_released == 0)
		reset()
		C.assert(C.fixture_benchmark(c'%s:%u', c'benchmark', u32(31)) == 12)
		C.assert(print_fixture_serial_len == 12 && print_fixture_terminal_len == 0 && print_fixture_acquired == 0 && print_fixture_released == 0)
		C.assert(C.memcmp(&print_fixture_serial[0], c'benchmark:31', 12) == 0)
		reset()
		C.assert(C.fixture_fprintf(nil, c'%s!\n', c'assert') == 0)
		C.assert(print_fixture_serial_len == 8 && print_fixture_terminal_len == 8)
		C.assert(C.memcmp(&print_fixture_serial[0], c'assert!\n', 8) == 0 && C.memcmp(&print_fixture_serial[0], &print_fixture_terminal[0], 8) == 0)
		reset()
		C.assert(C.fixture_fprintf(nil, c'%.*s!', i32(3), c'assert') == 0)
		C.assert(print_fixture_serial_len == 4 && C.memcmp(&print_fixture_serial[0], c'ass!', 4) == 0)
		C.assert(C.memcmp(&print_fixture_serial[0], &print_fixture_terminal[0], 4) == 0)
		reset()
		C.assert(C.fixture_fprintf(nil, c'%.*s!', i32(-1), c'unused') == 0)
		C.assert(print_fixture_serial_len == 1 && print_fixture_serial[0] == `!`)
		reset()
		C.assert(C.fixture_fprintf(nil, c'literal') == 0)
		C.assert(print_fixture_serial_len == 7 && C.memcmp(&print_fixture_serial[0], c'literal', 7) == 0)
		return 0
	}
}
