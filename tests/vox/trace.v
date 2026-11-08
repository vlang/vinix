// SPDX-License-Identifier: GPL-2.0-or-later
// Optional guest-only fault trace, loaded before the browser through LD_PRELOAD.
module main

#include <signal.h>
#include <ucontext.h>
#include <unistd.h>
#include <dlfcn.h>
#include <execinfo.h>

struct C.sigaction {
mut:
	sa_sigaction fn (i32, &C.siginfo_t, voidptr)
	sa_flags     i32
}

@[typedef]
struct C.siginfo_t {
	si_addr voidptr
}

@[typedef]
struct C.mcontext_t {
	pc   u64
	sp   u64
	regs [31]u64
}

@[typedef]
struct C.ucontext_t {
	uc_mcontext C.mcontext_t
}

@[typedef]
struct C.Dl_info {
mut:
	dli_fname &char
	dli_fbase voidptr
}

fn C.sigaction(i32, &C.sigaction, voidptr) i32
fn C.write(i32, voidptr, uint) i64
fn C.dladdr(voidptr, &C.Dl_info) i32
fn C.strlen(&char) uint
fn C.backtrace(&voidptr, i32) i32
fn C.backtrace_symbols_fd(&voidptr, i32, i32)
fn C._exit(i32)

fn write_hex(value u64) {
	mut buffer := [17]u8{}
	for index in 0 .. 16 {
		buffer[index] = unsafe { c'0123456789abcdef'[int((value >> (60 - index * 4)) & 15)] }
	}
	buffer[16] = `\n`
	C.write(2, &buffer[0], 17)
}

fn write_address(address u64) {
	mut info := C.Dl_info{}
	if C.dladdr(unsafe { voidptr(address) }, &info) != 0 {
		C.write(2, info.dli_fname, C.strlen(info.dli_fname))
		C.write(2, c' offset=', 8)
		write_hex(address - u64(info.dli_fbase))
	} else {
		write_hex(address)
	}
}

fn native_fault(_ i32, info &C.siginfo_t, pointer voidptr) {
	context := unsafe { &C.ucontext_t(pointer) }
	C.write(2, c'VOX-FAULT pc=', 13)
	write_hex(context.uc_mcontext.pc)
	write_address(context.uc_mcontext.pc)
	write_address(context.uc_mcontext.regs[30])
	write_hex(u64(info.si_addr))
	for index in 0 .. 3 { write_hex(context.uc_mcontext.regs[index]) }
	mut frame := context.uc_mcontext.regs[29]
	for _ in 0 .. 24 {
		if frame < context.uc_mcontext.sp || frame > context.uc_mcontext.sp + 8 * 1024 * 1024 || frame % 16 != 0 {
			break
		}
		previous := unsafe { &u64(frame) }
		write_address(unsafe { previous[1] })
		frame = unsafe { previous[0] }
	}
	mut frames := [48]voidptr{}
	count := C.backtrace(&frames[0], 48)
	C.backtrace_symbols_fd(&frames[0], count, 2)
	C._exit(139)
}

fn init() {
	C.write(2, c'VOX-TRACE loaded\n', 17)
	mut action := C.sigaction{ sa_sigaction: native_fault, sa_flags: C.SA_SIGINFO }
	C.sigaction(C.SIGSEGV, &action, unsafe { nil })
	C.sigaction(C.SIGABRT, &action, unsafe { nil })
}
