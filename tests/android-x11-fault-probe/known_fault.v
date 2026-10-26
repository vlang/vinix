// SPDX-License-Identifier: GPL-2.0-or-later
// Actual native signal installation/query/restoration and a controlled fault.
module main

#include <signal.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <dlfcn.h>

@[typedef]
struct C.sigset_t {}
struct C.sigaction {
mut:
	sa_sigaction fn (i32, voidptr, voidptr)
	sa_mask C.sigset_t
	sa_flags i32
}
fn C.sigaction(i32, &C.sigaction, &C.sigaction) i32
fn C.sigemptyset(&C.sigset_t) i32
fn C.sigaddset(&C.sigset_t, i32) i32
fn C.sigismember(&C.sigset_t, i32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.memset(voidptr, i32, usize) voidptr
fn C.write(i32, voidptr, usize) isize
fn C._exit(i32)
fn C.dlsym(voidptr, &char) voidptr

fn original(_signal i32, _info voidptr, _context voidptr) {
	unsafe { C._exit(74) }
}

fn chained(_signal i32, _info voidptr, _context voidptr) {
	unsafe {
		C.write(2, c'X11-KNOWN-FAULT-CHAINED\n', 24)
		C._exit(73)
	}
}

fn run() ! {
	unsafe {
		if C.dlsym(nil, c'vinix_x11_fault_probe_version') == nil {
			return error('diagnostic shim was not preloaded')
		}
		mut old := C.sigaction{}
		mut first := C.sigaction{sa_sigaction: original, sa_flags: C.SA_SIGINFO | C.SA_RESTART}
		C.sigemptyset(&first.sa_mask)
		C.sigaddset(&first.sa_mask, C.SIGUSR1)
		if C.sigaction(C.SIGSEGV, &first, &old) != 0 { return error('install first handler') }
		mut queried := C.sigaction{}
		if C.sigaction(C.SIGSEGV, nil, &queried) != 0
			|| usize(queried.sa_sigaction) != usize(original)
			|| queried.sa_flags != first.sa_flags
			|| C.sigismember(&queried.sa_mask, C.SIGUSR1) != 1 {
			return error('query did not preserve original disposition')
		}
		if C.sigaction(C.SIGSEGV, &old, nil) != 0 { return error('restore native disposition') }
		if C.sigaction(C.SIGSEGV, &first, &queried) != 0
			|| usize(queried.sa_sigaction) != usize(old.sa_sigaction) {
			return error('restoration did not preserve previous handler')
		}
		if C.sigaction(C.SIGSEGV, &old, nil) != 0 { return error('restore native disposition twice') }
		child := C.fork()
		if child < 0 { return error('fork controlled fault') }
		if child == 0 {
			mut action := C.sigaction{sa_sigaction: chained, sa_flags: C.SA_SIGINFO}
			C.sigemptyset(&action.sa_mask)
			if C.sigaction(C.SIGSEGV, &action, nil) != 0 { C._exit(90) }
			page := C.mmap(nil, 4096, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
			if page == voidptr(-1) { C._exit(91) }
			eprintln('X11-KNOWN-FAULT-EXPECTED address=0x${u64(page):016x}')
			C.memset(page, 0x5a, 4096)
			C._exit(92)
		}
		mut status := i32(0)
		if C.waitpid(child, &status, 0) != child || status != 73 << 8 {
			return error('controlled fault did not chain: status=${status}')
		}
		println('X11-KNOWN-FAULT-PASS query=preserved restoration=preserved chain=preserved')
	}
}

fn main() {
	run() or { eprintln(err); exit(1) }
}
