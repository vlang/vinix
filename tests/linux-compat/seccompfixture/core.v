// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module seccompfixture

#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

@[typedef]
struct C.sigset_t {}
@[typedef]
struct C.siginfo_t { si_signo i32 si_errno i32 si_code i32 si_call_addr voidptr si_syscall i32 si_arch u32 }
struct C.sigaction {
mut:
	sa_sigaction fn(i32, &C.siginfo_t, voidptr)
	sa_handler voidptr
	sa_mask C.sigset_t
	sa_flags i32
}
struct SockFilter { code u16 jt u8 jf u8 k u32 }
struct SockFprog { len u16 filter &SockFilter }

fn C.sigaction(i32, &C.sigaction, &C.sigaction) i32
fn C.sigemptyset(&C.sigset_t) i32
fn C.sigaddset(&C.sigset_t, i32) i32
fn C.sigprocmask(i32, &C.sigset_t, &C.sigset_t) i32
fn C.raise(i32) i32
fn C.prctl(i32, ...) i32
fn C.syscall(isize, ...) isize
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) bool
fn C.WEXITSTATUS(i32) i32
fn C.WIFSIGNALED(i32) bool
fn C.WTERMSIG(i32) i32
fn C._exit(i32)
fn C.__errno_location() &i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

__global ( seen i32 ordinary i32 bad i32 )

fn handler(signum i32, info &C.siginfo_t, context voidptr) {
	unsafe {
		if info.si_code <= 0 { ordinary++; return }
		mut pc := u64(0)
		mut original := u64(0)
		mut expected := u64(0)
		mut arch := u32(0)
		$if arm64 {
			pc = *&u64(u64(context) + 440)
			original = *&u64(u64(context) + 184)
			expected = 0x1357
			arch = 0xc00000b7
			*&u64(u64(context) + 184) = 4242
		} $else {
			pc = *&u64(u64(context) + 168)
			original = *&u64(u64(context) + 144)
			expected = u64(C.SYS_getpid)
			arch = 0xc000003e
			*&u64(u64(context) + 144) = 4242
		}
		if signum != C.SIGSYS || info.si_signo != C.SIGSYS || info.si_code != 1
			|| info.si_errno != 42 || info.si_syscall != C.SYS_getpid || info.si_arch != arch
			|| u64(info.si_call_addr) != pc || pc == 0 || original != expected {
			bad++
			C.printf(c'LINUX SECCOMP FAIL: signum=%d code=%d data=%d nr=%d arch=%x address=%lx pc=%lx original=%lx expected=%lx\n',
				signum, info.si_code, info.si_errno, info.si_syscall, info.si_arch, u64(info.si_call_addr), pc, original, expected)
		}
		seen++
	}
}

fn install() bool {
	unsafe {
		mut instructions := [SockFilter{code: 0x20, k: 0},
			SockFilter{code: 0x15, jt: 0, jf: 1, k: u32(C.SYS_getpid)},
			SockFilter{code: 0x06, k: 0x0003002a},
			SockFilter{code: 0x06, k: 0x7fff0000}]!
		program := SockFprog{len: 4, filter: &instructions[0]}
		return C.prctl(C.PR_SET_NO_NEW_PRIVS, isize(1), isize(0), isize(0), isize(0)) == 0
			&& C.syscall(isize(C.SYS_seccomp), isize(1), isize(0), &program) == 0
	}
}

fn child_test(kind i32) i32 {
	unsafe {
		mut action := C.sigaction{}
		C.sigemptyset(&action.sa_mask)
		action.sa_sigaction = handler
		action.sa_flags = C.SA_SIGINFO
		if kind == 2 { action.sa_handler = voidptr(1) }
		if C.sigaction(C.SIGSYS, &action, nil) != 0 { return 1 }
		if kind == 1 {
			mut mask := C.sigset_t{}
			C.sigemptyset(&mask)
			C.sigaddset(&mask, C.SIGSYS)
			if C.sigprocmask(C.SIG_BLOCK, &mask, nil) != 0 { return 1 }
		}
		if kind == 0 && (C.raise(C.SIGSYS) != 0 || ordinary != 1 || seen != 0) { return 1 }
		if !install() { return 1 }
		for i := 0; i < 20; i++ {
			if C.syscall(isize(C.SYS_getpid), isize(0x1357)) != 4242 || seen != i + 1 || bad != 0 {
				C.printf(c'LINUX SECCOMP FAIL: trap return/metadata seen=%d bad=%d\n', seen, bad)
				return 1
			}
		}
		if C.raise(C.SIGSYS) != 0 || ordinary != 2 || seen != 20 { return 1 }
		return 0
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		for kind := i32(0); kind < 3; kind++ {
			child := C.fork()
			if child == 0 { C._exit(child_test(kind)) }
			mut status := i32(0)
			if child < 0 || C.waitpid(child, &status, 0) != child { return 1 }
			if (kind == 0 && (!C.WIFEXITED(status) || C.WEXITSTATUS(status) != 0))
				|| (kind != 0 && (!C.WIFSIGNALED(status) || C.WTERMSIG(status) != C.SIGSYS)) {
				C.printf(c'LINUX SECCOMP FAIL: disposition kind=%d status=%d\n', kind, status)
				return 1
			}
		}
		C.puts(c'LINUX SECCOMP: PASS')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
