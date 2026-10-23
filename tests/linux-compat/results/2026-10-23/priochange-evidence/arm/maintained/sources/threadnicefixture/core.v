// SPDX-License-Identifier: GPL-2.0-or-later
module threadnicefixture

#include <errno.h>
#include <grp.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

@[typedef]
struct C.pthread_t {}

struct Peer {
mut:
	stage i32
	tid i32
	failed i32
}

struct Attr {
mut:
	size u32
	policy u32
	flags u64
	nice i32
	priority u32
	runtime u64
	deadline u64
	period u64
}

fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.getpriority(i32, u32) i32
fn C.setpriority(i32, u32, i32) i32
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.__atomic_store_n(&i32, i32, i32)
fn C.__atomic_load_n(&i32, i32) i32
fn C.sched_yield() i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.execl(&char, &char, ...) i32
fn C._exit(i32)
fn C.getpid() i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.strcmp(&char, &char) i32
fn C.puts(&char) i32
fn C.printf(&char, ...) i32
fn C.fflush(voidptr) i32
fn C.pause() i32
fn C.alarm(u32) u32

fn priority(tid i32, wanted i32) bool {
	unsafe {
		err := C.__errno_location()
		*err = 0
		got := C.getpriority(C.PRIO_PROCESS, u32(tid))
		code := *err
		if got != wanted || code != 0 {
			C.printf(c'THREADNICE priority: tid=%d wanted=%d got=%d errno=%d\n', tid, wanted, got, code)
			C.fflush(nil)
		}
		return got == wanted && code == 0
	}
}

fn attr_priority(tid i32, wanted i32) bool {
	mut attr := Attr{}
	result := unsafe { C.syscall(C.SYS_sched_getattr, tid, &attr, u32(sizeof(Attr)), u32(0)) }
	if result != 0 || attr.nice != wanted {
		unsafe { C.printf(c'THREADNICE attr: tid=%d wanted=%d got=%d ret=%ld errno=%d\n', tid, wanted, attr.nice, result, *C.__errno_location()); C.fflush(nil) }
	}
	return result == 0 && attr.nice == wanted
}

fn worker(argument voidptr) voidptr {
	unsafe {
		mut peer := &Peer(argument)
		peer.tid = i32(C.syscall(C.SYS_gettid))
		if !priority(0, 5) || !priority(peer.tid, 5)
			|| C.setpriority(C.PRIO_PROCESS, 0, 7) != 0 { peer.failed = 1 }
		C.__atomic_store_n(&peer.stage, 1, 3)
		for C.__atomic_load_n(&peer.stage, 2) != 2 { C.sched_yield() }
		if !priority(0, 11) || !attr_priority(0, 11) { peer.failed = 1 }
		// A fork from a worker must use that worker's weight, including exec.
		pid := C.fork()
		if pid < 0 { peer.failed = 1 }
		if pid == 0 {
			if !priority(0, 11) { C._exit(31) }
			C.execl(c'/proc/self/exe', c'init', c'--nice11', voidptr(nil))
			C._exit(32)
		}
		mut status := i32(-1)
		if pid > 0 && (C.waitpid(pid, &status, 0) != pid || status != 0) { peer.failed = 1 }
		return nil
	}
}

fn exec_worker(_ voidptr) voidptr {
	unsafe {
		if C.setpriority(C.PRIO_PROCESS, 0, 11) != 0 { C._exit(33) }
		C.execl(c'/proc/self/exe', c'init', c'--nice11', voidptr(nil))
		C._exit(34)
		return nil
	}
}

fn ordinary(parent i32) bool {
	unsafe {
		err := C.__errno_location()
		if C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { return false }
		if !priority(0, 5) || C.setpriority(C.PRIO_PROCESS, 0, 7) != 0 || !priority(0, 7) { return false }
		*err = 0
		if C.setpriority(C.PRIO_PROCESS, 0, 5) != -1 || *C.__errno_location() != C.EACCES { return false }
		*err = 0
		if C.setpriority(C.PRIO_PROCESS, u32(parent), 7) != -1 || *C.__errno_location() != C.EPERM { return false }
		return priority(0, 7)
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		C.alarm(90)
		if argc == 2 && C.strcmp(argv[1], c'--nice11') == 0 {
			C._exit(if priority(0, 11) && attr_priority(0, 11) { 0 } else { 35 })
		}
		mut good := C.setpriority(C.PRIO_PROCESS, 0, -1) == 0
		good = priority(0, -1) && attr_priority(0, -1) && good
		good = C.setpriority(C.PRIO_PROCESS, 0, 5) == 0 && good
		mut peer := Peer{}
		mut handle := C.pthread_t{}
		if C.pthread_create(&handle, nil, worker, &peer) != 0 { return 1 }
		for C.__atomic_load_n(&peer.stage, 2) != 1 { C.sched_yield() }
		good = good && peer.failed == 0 && peer.tid != C.getpid()
			&& priority(0, 5) && priority(peer.tid, 7) && attr_priority(peer.tid, 7)
		mut attr := Attr{size: u32(sizeof(Attr)), nice: 11}
		good = C.syscall(C.SYS_sched_setattr, peer.tid, &attr, u32(0)) == 0 && good
		good = priority(peer.tid, 11) && attr_priority(peer.tid, 11) && priority(0, 5) && good
		C.__atomic_store_n(&peer.stage, 2, 3)
		good = C.pthread_join(handle, nil) == 0 && peer.failed == 0 && good
		C.printf(c'THREADNICE join: good=%d worker=%d\n', i32(good), peer.failed)
		err := C.__errno_location()
		*err = 0
		good = C.getpriority(C.PRIO_PROCESS, u32(peer.tid)) == -1 && *C.__errno_location() == C.ESRCH && good
		C.printf(c'THREADNICE reaped: good=%d errno=%d\n', i32(good), *err)
		parent := C.getpid()
		for kind in 0 .. 2 {
			child := C.fork()
			if child < 0 { return 1 }
			if child == 0 {
				if kind == 0 { C._exit(if ordinary(parent) { 0 } else { 36 }) }
				// exec by a nonleader keeps its nice when it takes over the pid.
				mut exec_handle := C.pthread_t{}
				if C.pthread_create(&exec_handle, nil, exec_worker, nil) != 0 { C._exit(37) }
				for { C.pause() }
			}
			mut status := i32(-1)
			good = C.waitpid(child, &status, 0) == child && status == 0 && good
			C.printf(c'THREADNICE child: kind=%d status=%d good=%d\n', kind, status, i32(good))
		}
		if !good {
			C.puts(c'LINUX THREADNICE FAIL: task lookup, isolation, inheritance, exec or permissions')
			C.fflush(nil)
			return 1
		}
		C.puts(c'LINUX THREADNICE: PASS')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
