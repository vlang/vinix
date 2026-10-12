// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module seccompkillfixture

#define _GNU_SOURCE 1
#include <errno.h>
#include <grp.h>
#include <sched.h>
#include <signal.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct SockFilter { code u16 jt u8 jf u8 k u32 }
struct SockFprog { len u16 filter &SockFilter }
struct Task {
mut:
	ready i32
	release i32
	tid i32
	kind i32
	in_fd i32
	out_fd i32
}
__global ( caught_sys i32 caught_usr i32 )

fn C.syscall(isize, ...) isize
fn C.prctl(i32, ...) i32
fn C.__errno_location() &i32
// musl's public clone wrapper refuses CLONE_THREAD/CLEARTID. Its unchanged
// architecture trampoline supplies the raw syscall and a separate stack.
@[c_extern]
fn C.__clone(fn(voidptr) i32, voidptr, i32, voidptr, voidptr, voidptr, &i32) i32
fn C.__atomic_store_n(&i32, i32, i32)
fn C.__atomic_load_n(&i32, i32) i32
fn C.__atomic_add_fetch(&i32, i32, i32) i32
fn C.sched_yield() i32
fn C.signal(i32, fn(i32)) voidptr
fn C.fork() i32
fn C._exit(i32)
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFSIGNALED(i32) bool
fn C.WTERMSIG(i32) i32
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.munmap(voidptr, usize) i32
fn C.pipe(&i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.usleep(u32) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

fn handler(signum i32) {
	unsafe {
		if signum == C.SIGSYS { C.__atomic_add_fetch(&caught_sys, 1, 5) }
		else { C.__atomic_add_fetch(&caught_usr, 1, 5) }
	}
}
fn filter(action u32, flags u32) isize {
	unsafe {
		mut instructions := [SockFilter{code: 0x20}, SockFilter{code: 0x15, jf: 1, k: u32(C.SYS_getpid)},
			SockFilter{code: 0x06, k: action}, SockFilter{code: 0x06, k: 0x7fff0000}]!
		program := SockFprog{len: 4, filter: &instructions[0]}
		return C.syscall(isize(C.SYS_seccomp), isize(1), isize(flags), &program)
	}
}
fn nnp() bool { return unsafe { C.prctl(C.PR_SET_NO_NEW_PRIVS, usize(1), usize(0), usize(0), usize(0)) == 0 } }
fn strict() bool { return unsafe { C.syscall(isize(C.SYS_seccomp), isize(0), isize(0), voidptr(nil)) == 0 } }
fn failed(stage i32, task &Task, tid i32) bool {
	unsafe {
		C.printf(c'LINUX SECCOMPKILL DETAIL: stage=%d kind=%d clone=%d tid=%d ready=%d errno=%d\n', stage, task.kind, tid,
			C.__atomic_load_n(&task.tid, 2), C.__atomic_load_n(&task.ready, 2), *C.__errno_location())
		C.fflush(nil)
		// Keep the caller's Task frame live until exit_group quiesces a
		// successfully cloned task and any pending clear_child_tid write.
		if tid > 0 { C._exit(1) }
	}
	return false
}
fn task_body(argument voidptr) i32 {
	unsafe {
		mut task := &Task(argument)
		if task.kind in [2, 3, 4, 10, 12]! {
			if !strict() { C.__atomic_store_n(&task.ready, -1, 3); return 31 }
		} else {
			if !nnp() { C.__atomic_store_n(&task.ready, -1, 3); return 32 }
			action := match task.kind { 0 { u32(0) } 1 { u32(0xabcd) } 5 { u32(0x80000000) } else { u32(0x1234abcd) } }
			if filter(action, 0) != 0 { C.__atomic_store_n(&task.ready, -1, 3); return 33 }
		}
		C.__atomic_store_n(&task.ready, 1, 3)
		for C.__atomic_load_n(&task.release, 2) != 1 {}
		if task.kind == 12 { for C.__atomic_load_n(&caught_usr, 2) == 0 {} }
		if task.kind in [4, 12]! {
			mut byte := u8(0)
			if C.syscall(isize(C.SYS_read), isize(task.in_fd), &byte, usize(1)) != 1 || byte != 0x5a
				|| C.syscall(isize(C.SYS_write), isize(task.out_fd), &byte, usize(1)) != 1 {
				C.syscall(isize(C.SYS_exit), isize(34))
			}
			C.__atomic_store_n(&task.ready, 2, 3)
			C.syscall(isize(C.SYS_exit), isize(77))
		} else if task.kind == 3 {
			C.syscall(isize(C.SYS_exit_group), isize(0))
		} else {
			C.syscall(isize(C.SYS_getpid))
		}
		C.__atomic_store_n(&task.ready, -2, 3)
		return 35
	}
}
fn group_case(kind i32) bool {
	unsafe {
		C.signal(C.SIGSYS, handler)
		C.signal(C.SIGUSR1, handler)
		mut pipe := [2]i32{}
		if C.pipe(&pipe[0]) != 0 { return false }
		mut byte := u8(0x5a)
		if C.write(pipe[1], &byte, 1) != 1 { return false }
		length := usize(1024 * 1024)
		stack := C.mmap(nil, length, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if stack == voidptr(C.MAP_FAILED) { return false }
		mut task := Task{tid: -1, kind: kind, in_fd: pipe[0], out_fd: pipe[1]}
		flags := C.CLONE_VM | C.CLONE_FS | C.CLONE_FILES | C.CLONE_SIGHAND | C.CLONE_THREAD | C.CLONE_CHILD_SETTID | C.CLONE_CHILD_CLEARTID
		tid := C.__clone(task_body, voidptr(usize(stack) + length), i32(flags), &task, voidptr(nil), voidptr(nil), &task.tid)
		if tid <= 0 { return failed(1, &task, tid) }
		for C.__atomic_load_n(&task.ready, 2) == 0 { C.sched_yield() }
		if C.__atomic_load_n(&task.ready, 2) != 1 || C.__atomic_load_n(&task.tid, 2) != tid { return failed(2, &task, tid) }
		if C.prctl(C.PR_GET_SECCOMP, usize(0), usize(0), usize(0), usize(0)) != 0 { return failed(3, &task, tid) }
		if kind == 10 {
			if !nnp() { return failed(6, &task, tid) }
			for sync_flags in [u32(1), 17]! {
				e := C.__errno_location(); *e = 0
				result := filter(0x00050001, sync_flags)
				if result != if sync_flags == 1 { isize(tid) } else { isize(-1) }
					|| *e != if sync_flags == 1 { 0 } else { C.ESRCH }
					|| C.prctl(C.PR_GET_SECCOMP, usize(0), usize(0), usize(0), usize(0)) != 0 { return failed(7, &task, tid) }
			}
		}
		C.__atomic_store_n(&task.release, 1, 3)
		if kind == 12 && C.syscall(isize(C.SYS_tgkill), C.syscall(isize(C.SYS_getpid)), isize(tid), isize(C.SIGUSR1)) != 0 { return failed(8, &task, tid) }
		for _ in 0 .. 5000 {
			if C.__atomic_load_n(&task.tid, 2) == 0 { break }
			C.usleep(1000)
		}
		if C.__atomic_load_n(&task.tid, 2) != 0 || C.__atomic_load_n(&task.ready, 2) != if kind in [4, 12]! { 2 } else { 1 }
			|| C.__atomic_load_n(&caught_sys, 2) != 0 || C.syscall(isize(C.SYS_getpid)) <= 0 { return failed(4, &task, tid) }
		if kind in [4, 12]! && (C.read(pipe[0], &byte, 1) != 1 || byte != 0x5a) { return failed(9, &task, tid) }
		if kind == 12 && C.__atomic_load_n(&caught_usr, 2) != 1 { return failed(10, &task, tid) }
		// clear_child_tid permits userspace stack retirement; the exited task
		// uses only its separate kernel stack after publishing that zero.
		C.usleep(10000)
		e := C.__errno_location(); *e = 0
		if C.syscall(isize(C.SYS_tgkill), C.syscall(isize(C.SYS_getpid)), isize(tid), isize(0)) != -1 || *e != C.ESRCH { return failed(5, &task, tid) }
		return C.munmap(stack, length) == 0 && C.close(pipe[0]) == 0 && C.close(pipe[1]) == 0
	}
}
fn single_case(kind i32) bool {
	unsafe {
		C.signal(C.SIGSYS, handler)
		if kind == 7 { if !nnp() || filter(0, 0) != 0 { return false } }
		else { if !strict() { return false } }
		C.syscall(isize(C.SYS_getpid))
		return false
	}
}
@[export: 'main']
pub fn run() i32 {
	unsafe {
		if C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { return 1 }
		for kind in [i32(0), 1, 2, 3, 4, 5, 6, 7, 8, 10, 12]! {
			C.fflush(nil)
			child := C.fork()
			if child < 0 { return 1 }
			if child == 0 { C._exit(if kind in [7, 8]! { if single_case(kind) { 0 } else { 1 } } else { if group_case(kind) { 0 } else { 1 } }) }
			mut outcome := i32(0)
			wanted_signal := if kind in [5, 6, 7]! { i32(C.SIGSYS) } else if kind == 8 { i32(C.SIGKILL) } else { i32(0) }
			if C.waitpid(child, &outcome, 0) != child || if wanted_signal == 0 { outcome != 0 } else { !C.WIFSIGNALED(outcome) || C.WTERMSIG(outcome) != wanted_signal } {
				C.printf(c'LINUX SECCOMPKILL FAIL: kind=%d outcome=%d signal=%d\n', kind, outcome, wanted_signal)
				return 1
			}
			C.printf(c'LINUX SECCOMPKILL CASE: kind=%d signal=%d PASS\n', kind, wanted_signal)
		}
		C.puts(c'LINUX SECCOMPKILL PASS: task-only SIGSYS/SIGKILL, process kills, last-task signals, strict read/write/exit/sigreturn, TSYNC strict refusal and TID cleanup')
		C.puts(c'LINUX SECCOMPKILL: PASS')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
