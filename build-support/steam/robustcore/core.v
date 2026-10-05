// SPDX-License-Identifier: GPL-2.0-or-later
// Debian Bookworm glibc 2.36 thread layouts, translated Steam processes only.
@[has_globals]
module robustcore

@[c_extern]
fn C.dlsym(voidptr, &char) voidptr
@[c: 'pthread_self'; c_extern]
fn C.thread_identity() voidptr
// Declarations for the unused freestanding compiler diagnostic scaffold.
@[c_extern]
fn C.fprintf(stream voidptr, format &char, ...values voidptr) i32
@[c_extern]
__global C.stderr voidptr

@[c_extern]
fn C.vinix_steam_forward_syscall(voidptr, isize, isize, isize, isize, isize, isize, isize) isize

// The instruction-only syscall entry forwards the native integer varargs ABI.
@[export: 'vinix_steam_syscall']
pub fn syscall(number isize, a1 isize, a2 isize, a3 isize, a4 isize, a5 isize, a6 isize) isize {
	unsafe {
		$if steam_i386 ? {
			if number == 312 && a1 == 0 && a2 != 0 && a3 != 0 {
				*(&voidptr(a2)) = voidptr(usize(C.thread_identity()) + 0x6c)
				*(&usize(a3)) = 12
				return 0
			}
		} $else {
			if number == 274 && a1 == 0 && a2 != 0 && a3 != 0 {
				*(&voidptr(a2)) = voidptr(usize(C.thread_identity()) + 0x2e0)
				*(&usize(a3)) = 24
				return 0
			}
		}
		next := C.dlsym(voidptr(-1), c'syscall')
		return C.vinix_steam_forward_syscall(next, number, a1, a2, a3, a4, a5, a6)
	}
}
