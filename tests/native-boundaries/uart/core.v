// Independent checks shared by frozen native C headers and production V bodies.
@[has_globals]
module uart

#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "symbols.h"
#include "apple_smc.h"

fn C.assert(bool)
fn C.puts(&char) i32
fn C.strcmp(&char, &char) i32
fn C.memset(voidptr, i32, usize) voidptr
fn C.trace_syscall_nr(usize)
fn C.vinix_call_void_fn(voidptr)
fn C.native_boundary_callback()
fn C.read_current_sp() usize
fn C.vinix_smc_counter() u64

__global output [32]u8
__global output_size usize
__global callback_calls u32

pub fn putc(byte u8) {
	unsafe {
		C.assert(output_size + 1 < 32)
		output[output_size] = byte
		output_size++
	}
}

@[export: 'aarch64__uart__putc']
pub fn original_putc(byte u8) { putc(byte) }

@[export: 'native_boundary_callback']
pub fn callback() { callback_calls++ }

struct TraceCase {
	number   u64
	expected &char
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		cases := [
			TraceCase{0, c'SC:0 '},
			TraceCase{1, c'SC:1 '},
			TraceCase{9, c'SC:9 '},
			TraceCase{10, c'SC:10 '},
			TraceCase{139, c'SC:139 '},
			TraceCase{9999999, c'SC:9999999 '},
			TraceCase{10000000, c'SC:0000000 '},
			TraceCase{10000001, c'SC:0000001 '},
			TraceCase{0xffffffff, c'SC:4967295 '},
			TraceCase{u64(-1), c'SC:9551615 '},
		]!
		for test in cases {
			C.memset(&output[0], 0, 32)
			output_size = 0
			C.trace_syscall_nr(usize(test.number))
			C.assert(C.strcmp(&char(&output[0]), test.expected) == 0)
		}
		for index in 0 .. 256 {
			C.vinix_call_void_fn(voidptr(C.native_boundary_callback))
			C.assert(callback_calls == u32(index + 1))
		}
		$if arm64 {
			stack := C.read_current_sp()
			C.assert(stack != 0 && stack % 16 == 0)
			mut previous := C.vinix_smc_counter()
			for _ in 0 .. 128 {
				next := C.vinix_smc_counter()
				C.assert(next >= previous)
				previous = next
			}
		}
		C.puts(c'NATIVE HEADER BOUNDARIES: PASS (10 UART traces, 256 callbacks, stack/counter)')
		return 0
	}
}
