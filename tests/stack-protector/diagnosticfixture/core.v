// SPDX-License-Identifier: GPL-2.0-or-later
// Independent original byte/hex oracle; libc snprintf supplies golden bytes.
@[has_globals]
module diagnosticfixture

#include <diagnostic-native-abi.h>
@[typedef]
struct C.vstack_diagnostic_ull {}
fn C.assert(bool)
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.snprintf(&char, usize, &char, ...) i32
fn C.puts(&char) i32
fn C.vinix_stack_guard_message(&char)
fn C.vinix_stack_guard_diagnostic(u64, u64, u64)

__global (
	diag_fixture_captured [1024]char
	diag_fixture_length usize
)

fn capture(value u8) {
	C.assert(diag_fixture_length < 1024)
	unsafe { diag_fixture_captured[diag_fixture_length] = char(value) }
	diag_fixture_length++
}

@[export: 'aarch64__uart__putc']
pub fn arm_out(value u8) { capture(value) }

@[export: 'serial__panic_out']
pub fn x86_out(value u8) { capture(value) }

fn diagnostic(sp u64, pc u64, address u64) {
	unsafe {
		mut expected := [128]char{}
		mut native_sp := C.vstack_diagnostic_ull{}
		mut native_pc := C.vstack_diagnostic_ull{}
		mut native_address := C.vstack_diagnostic_ull{}
		C.memcpy(&native_sp, &sp, sizeof(u64))
		C.memcpy(&native_pc, &pc, sizeof(u64))
		C.memcpy(&native_address, &address, sizeof(u64))
		count := C.snprintf(&expected[0], sizeof(expected), c'STACK-GUARD state sp=0x%016llx pc=0x%016llx address=0x%016llx\n', native_sp, native_pc, native_address)
		C.assert(count > 0 && usize(count) < sizeof(expected))
		diag_fixture_length = 0
		C.vinix_stack_guard_diagnostic(sp, pc, address)
		C.assert(diag_fixture_length == usize(count) && C.memcmp(&diag_fixture_captured[0], &expected[0], diag_fixture_length) == 0)
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		bytes := [char(`a`), char(0x80), char(0xff), char(`\n`), char(0), char(`x`), char(0)]!
		diag_fixture_length = 0
		C.vinix_stack_guard_message(c'')
		C.assert(diag_fixture_length == 0)
		C.vinix_stack_guard_message(&bytes[0])
		C.assert(diag_fixture_length == 4 && C.memcmp(&diag_fixture_captured[0], &bytes[0], 4) == 0)
		diagnostic(0, 0, 0)
		diagnostic(~u64(0), ~u64(0), ~u64(0))
		diagnostic(0x0123456789abcdef, 0xfedcba9876543210, 0x8000000000000000)
		mut random := u64(0x64a30fb4c16ace80)
		for i in u32(0) .. u32(2000) {
			random ^= random << 13
			random ^= random >> 7
			random ^= random << 17
			diagnostic(random, random ^ ~u64(0), random >> (i % 64))
		}
		C.puts(c'STACK DIAGNOSTICS PASS: C ABI, exact serial bytes, 2003 hex fault records')
		return 0
	}
}
