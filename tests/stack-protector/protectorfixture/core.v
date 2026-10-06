// SPDX-License-Identifier: GPL-2.0-or-later
// Independent original canary/epilogue oracle; compiler emits protected frames.
@[has_globals]
module protectorfixture

#include <protector-native-abi.h>
struct C.vstack_protected_bytes {
mut:
	bytes [64]u8
}
@[c_extern]
__global C.__stack_chk_guard usize
fn C.assert(bool)
fn C.strcmp(&char, &char) i32
fn C._Exit(i32)
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) bool
fn C.WEXITSTATUS(i32) i32
fn C.puts(&char) i32
fn C.vinix_stack_guard_init()

@[noreturn]
@[export: 'vinix_stack_test_panic']
pub fn panic(message &char) {
	C.assert(unsafe { C.strcmp(message, c'stack protector: a stack frame was overwritten past its buffers') == 0 })
	C._Exit(99)
	for { continue }
}

@[noinline]
fn protected_frame(seed u32, tamper i32) u32 {
	unsafe {
		mut frame := C.vstack_protected_bytes{}
		mut total := u32(0)
		for i in u32(0) .. u32(64) { frame.bytes[i] = u8(seed + i) }
		for i in u32(0) .. u32(64) { total += frame.bytes[i] }
		if tamper != 0 { C.__stack_chk_guard ^= usize(0x100) }
		return total
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		C.assert(C.__stack_chk_guard == usize(0x595e9fbd94fda700))
		for i in u32(0) .. u32(1000) {
			old := C.__stack_chk_guard
			C.vinix_stack_guard_init()
			C.assert(C.__stack_chk_guard != 0 && C.__stack_chk_guard != old && (C.__stack_chk_guard & 0xff) == 0)
			mut expected := u32(0)
			for j in u32(0) .. u32(64) { expected += u8(i + j) }
			C.assert(protected_frame(i, 0) == expected)
		}
		parent_guard := C.__stack_chk_guard
		child := C.fork()
		C.assert(child >= 0)
		if child == 0 {
			protected_frame(123, 1)
			C._Exit(1)
		}
		mut status := i32(0)
		C.assert(C.waitpid(child, &status, 0) == child)
		C.assert(C.WIFEXITED(status) && C.WEXITSTATUS(status) == 99)
		C.assert(C.__stack_chk_guard == parent_guard)
		C.puts(c'STACK PROTECTOR PASS: static guard, 1000 unprotected initializations, protected frames and V panic ABI')
		return 0
	}
}
