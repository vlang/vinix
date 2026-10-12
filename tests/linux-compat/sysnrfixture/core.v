// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module sysnrfixture

#include <errno.h>
#include <grp.h>
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
__global ( seen i32 bad i32 expected_nr i32 expected_original u64 restart_seen i32 )

fn C.sigaction(i32, &C.sigaction, &C.sigaction) i32
fn C.sigemptyset(&C.sigset_t) i32
fn C.syscall(isize, ...) isize
fn C.prctl(i32, ...) i32
fn C.__errno_location() &i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.pipe(&i32) i32
fn C.kill(i32, i32) i32
fn C.write(i32, voidptr, usize) isize
fn C.usleep(u32) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

fn call(number u64, wanted isize, error_code i32) bool {
	unsafe {
		e := C.__errno_location(); *e = 0
		actual := C.syscall(isize(number), usize(0x1357))
		code := *e
		if actual != wanted || code != error_code {
			C.printf(c'LINUX SYSNR DETAIL: nr=%lx actual=%ld/%d expected=%ld/%d\n', number, actual, code, wanted, error_code)
			C.fflush(nil)
			return false
		}
		return true
	}
}
fn install(number u32, action u32) bool {
	unsafe {
		mut instructions := [SockFilter{code: 0x20}, SockFilter{code: 0x15, jf: 1, k: number},
			SockFilter{code: 0x06, k: action}, SockFilter{code: 0x06, k: 0x7fff0000}]!
		program := SockFprog{len: 4, filter: &instructions[0]}
		return C.prctl(C.PR_SET_NO_NEW_PRIVS, usize(1), usize(0), usize(0), usize(0)) == 0
			&& C.syscall(isize(C.SYS_seccomp), isize(1), isize(0), &program) == 0
	}
}
fn handler(signum i32, info &C.siginfo_t, context voidptr) {
	unsafe {
		mut original := u64(0); mut pc := u64(0); mut arch := u32(0)
		$if arm64 {
			original = *&u64(u64(context) + 184); pc = *&u64(u64(context) + 440); arch = 0xc00000b7
			*&u64(u64(context) + 184) = 4242
		} $else {
			original = *&u64(u64(context) + 144); pc = *&u64(u64(context) + 168); arch = 0xc000003e
			*&u64(u64(context) + 144) = 4242
		}
		if signum != C.SIGSYS || info.si_code != 1 || info.si_errno != 42 || info.si_syscall != expected_nr
			|| info.si_arch != arch || u64(info.si_call_addr) != pc || original != expected_original { bad++ }
		seen++
	}
}
fn restart_handler(signum i32, _info &C.siginfo_t, context voidptr) {
	unsafe {
		mut original := u64(0)
		$if arm64 { original = *&u64(u64(context) + 248) }
		$else { original = *&u64(u64(context) + 144) }
		if signum != C.SIGUSR1 || original != expected_original { bad++ }
		restart_seen++
	}
}
fn probe(kind i32) bool {
	unsafe {
		prefixes := [u64(0), u64(1) << 32, 0x1234567800000000, 0xffffffff00000000]!
		if kind == 0 {
			for number in [u64(511), 512, 0xffffffff, 0x80000000, 0x40000000]! {
				for prefix in prefixes { if !call(prefix | number, -1, C.ENOSYS) { return false } }
			}
		} else if kind == 1 {
			for number in [u64(C.SYS_getpid), u64(C.SYS_gettid), u64(C.SYS_getuid), u64(C.SYS_getgid)]! {
				wanted := C.syscall(isize(number))
				for prefix in prefixes { if !call(prefix | number, wanted, 0) { return false } }
			}
		} else if kind == 2 {
			if !install(511, 0x0005000d) { return false }
			for prefix in prefixes { if !call(prefix | 511, -1, C.EACCES) { return false } }
			if !install(511, 0x00050000) { return false }
			for prefix in prefixes { if !call(prefix | 511, 0, 0) { return false } }
			if !call(512, -1, C.ENOSYS) { return false }
		} else if kind == 3 {
			if !install(u32(C.SYS_getpid), 0x0005000d) { return false }
			for prefix in prefixes {
				if !call(prefix | u64(C.SYS_getpid), -1, C.EACCES) || !call(prefix | 511, -1, C.ENOSYS) { return false }
			}
		} else if kind == 4 {
			mut action := C.sigaction{sa_sigaction: handler, sa_flags: C.SA_SIGINFO}
			if C.sigemptyset(&action.sa_mask) != 0 || C.sigaction(C.SIGSYS, &action, nil) != 0 { return false }
			for number in [u32(C.SYS_getpid), 511]! {
				if !install(number, 0x0003002a) { return false }
				for prefix in prefixes {
					raw := prefix | u64(number)
					expected_nr = i32(number)
					$if arm64 { expected_original = 0x1357 } $else { expected_original = raw }
					if !call(raw, 4242, 0) || bad != 0 { return false }
				}
			}
			if seen != 8 { return false }
		} else if kind == 5 {
			mut pipes := [2]i32{}
			mut primed := u8(0x5a)
			if C.pipe(&pipes[0]) != 0 || C.write(pipes[1], &primed, 1) != 1
				|| C.syscall(isize(C.SYS_seccomp), isize(0), isize(0), voidptr(nil)) != 0 { return false }
			for prefix in prefixes {
				if C.syscall(isize(prefix | u64(C.SYS_read)), isize(pipes[0]), usize(1), usize(0)) != 0
					|| C.syscall(isize(prefix | u64(C.SYS_write)), isize(pipes[1]), usize(1), usize(0)) != 0 { C.syscall(isize(C.SYS_exit), isize(1)) }
			}
			C.syscall(isize((u64(1) << 32) | u64(C.SYS_exit)), isize(77))
			return false
		} else {
			mut pipes := [2]i32{}
			mut action := C.sigaction{sa_sigaction: restart_handler, sa_flags: C.SA_SIGINFO | C.SA_RESTART}
			if C.pipe(&pipes[0]) != 0 || C.sigemptyset(&action.sa_mask) != 0 || C.sigaction(C.SIGUSR1, &action, nil) != 0 { return false }
			parent := i32(C.syscall(isize(C.SYS_getpid)))
			child := C.fork()
			if child < 0 { return false }
			if child == 0 {
				mut byte := u8(0x5a)
				C.usleep(50000)
				if C.kill(parent, C.SIGUSR1) != 0 { C._exit(1) }
				C.usleep(50000)
				C._exit(if C.write(pipes[1], &byte, 1) == 1 { 0 } else { 1 })
			}
			expected_original = 0x1234567800000000 | u64(C.SYS_read)
			mut byte := u8(0)
			if C.syscall(isize(expected_original), isize(pipes[0]), &byte, usize(1)) != 1
				|| byte != 0x5a || bad != 0 || restart_seen != 1 { return false }
			mut outcome := i32(-1)
			if C.waitpid(child, &outcome, 0) != child || outcome != 0 { return false }
		}
		return true
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		if C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { return 1 }
		for kind in 0 .. 7 {
			C.fflush(nil)
			pid := C.fork()
			if pid < 0 { return 1 }
			if pid == 0 { C._exit(if probe(i32(kind)) { 0 } else { 1 }) }
			mut outcome := i32(-1)
			if C.waitpid(pid, &outcome, 0) != pid || outcome != if kind == 5 { 77 << 8 } else { 0 } {
				C.printf(c'LINUX SYSNR DETAIL: kind=%d outcome=%d\n', i32(kind), outcome)
				C.fflush(nil)
				C.puts(c'LINUX SYSNR FAIL: selector, private slot, trap rollback or strict whitelist')
				C.fflush(nil)
				return 1
			}
			C.printf(c'LINUX SYSNR CASE: kind=%d PASS\n', i32(kind))
		}
		C.puts(c'LINUX SYSNR PASS: signed C-int numbers, private slot refusal, filtered unknown calls, stale verdict refusal, full-register trap/restart state and strict whitelist')
		C.puts(c'LINUX SYSNR: PASS')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
