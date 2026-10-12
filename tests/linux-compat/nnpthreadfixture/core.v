// SPDX-License-Identifier: GPL-2.0-or-later
module nnpthreadfixture

#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

@[typedef]
struct C.pthread_t {}

@[typedef]
struct C.siginfo_t {}

struct Peer {
mut:
	stage i32
	tid isize
	failed i32
	set_self bool
	leader i32
}
struct Child {
mut:
	wanted i32
	failed i32
}
struct DirectExec {
mut:
	stage i32
	wanted i32
}
struct SeccompProgram { len u16 filter voidptr }

fn C.syscall(isize, ...) isize
fn C.prctl(i32, ...) i32
fn C.__errno_location() &i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.__atomic_store_n(&i32, i32, i32)
fn C.__atomic_load_n(&i32, i32) i32
fn C.sched_yield() i32
fn C.fork() i32
fn C.execl(&char, &char, ...) i32
fn C._exit(i32)
fn C.waitpid(i32, &i32, i32) i32
fn C.waitid(i32, u32, &C.siginfo_t, i32) i32
fn C.open(&char, i32, ...) i32
fn C.read(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.snprintf(&char, usize, &char, ...) i32
fn C.strstr(&char, &char) &char
fn C.strcmp(&char, &char) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

fn state() i32 {
	return unsafe { C.prctl(C.PR_GET_NO_NEW_PRIVS, usize(0), usize(0), usize(0), usize(0)) }
}
fn set() bool {
	return unsafe { C.prctl(C.PR_SET_NO_NEW_PRIVS, usize(1), usize(0), usize(0), usize(0)) == 0 }
}
fn status(path &char, wanted i32) bool {
	unsafe {
		fd := C.open(path, C.O_RDONLY)
		if fd < 0 { return false }
		mut data := [4096]char{}
		length := C.read(fd, &data[0], usize(data.len - 1))
		closed := C.close(fd)
		if length <= 0 || closed != 0 { return false }
		data[int(length)] = 0
		return C.strstr(&data[0], if wanted == 0 { c'NoNewPrivs:\t0\n' } else { c'NoNewPrivs:\t1\n' }) != nil
	}
}
fn own_state(wanted i32) bool {
	return state() == wanted && unsafe { status(c'/proc/thread-self/status', wanted) }
}
fn authorization(wanted i32) bool {
	unsafe {
		errno_ptr := C.__errno_location()
		// Header faults precede authorization. A readable header with an
		// unreadable instruction pointer distinguishes each caller's NNP.
		program := SeccompProgram{len: 1, filter: voidptr(1)}
		for method in [i32(0), 1]! {
			for pointer in [voidptr(1), voidptr(&program)]! {
				*errno_ptr = 0
				result := if method == 0 {
					C.syscall(isize(C.SYS_seccomp), isize(1), isize(0), pointer)
				} else { isize(C.prctl(C.PR_SET_SECCOMP, usize(2), pointer, usize(0), usize(0))) }
				if result != -1 || *errno_ptr != if pointer == voidptr(1) || wanted == 1 { C.EFAULT } else { C.EACCES } { return false }
			}
		}
		return true
	}
}
fn child_thread(argument voidptr) voidptr {
	unsafe {
		mut child := &Child(argument)
		if !own_state(child.wanted) || !authorization(child.wanted) { child.failed = 1 }
		return nil
	}
}
fn descendants(wanted i32) bool {
	unsafe {
		mut child := Child{ wanted: wanted }
		mut handle := C.pthread_t{}
		if C.pthread_create(&handle, nil, child_thread, &child) != 0
			|| C.pthread_join(handle, nil) != 0 || child.failed != 0 { return false }
		pid := C.fork()
		if pid < 0 { return false }
		if pid == 0 {
			if !own_state(wanted) || !status(c'/proc/self/status', wanted) { C._exit(21) }
			C.execl(c'/proc/self/exe', c'init', if wanted == 0 { &char(c'--probe0') } else { &char(c'--probe1') }, voidptr(nil))
			C._exit(22)
		}
		mut outcome := i32(0)
		return C.waitpid(pid, &outcome, 0) == pid && outcome == 0
	}
}
fn exec_thread(argument voidptr) voidptr {
	unsafe {
		mut request := &DirectExec(argument)
		if !own_state(0) { C._exit(31) }
		C.__atomic_store_n(&request.stage, 1, 3)
		for C.__atomic_load_n(&request.stage, 2) != 2 { C.sched_yield() }
		if request.wanted == 1 && !set() { C._exit(32) }
		C.execl(c'/proc/self/exe', c'init', if request.wanted == 0 { &char(c'--probe0') } else { &char(c'--probe1') }, voidptr(nil))
		C._exit(33)
		return nil
	}
}
fn direct_exec(wanted i32) bool {
	unsafe {
		pid := C.fork()
		if pid < 0 { return false }
		if pid == 0 {
			C.execl(c'/proc/self/exe', c'init', if wanted == 0 { &char(c'--thread-exec0') } else { &char(c'--thread-exec1') }, voidptr(nil))
			C._exit(34)
		}
		mut outcome := i32(0)
		waited := C.waitpid(pid, &outcome, 0)
		if waited != pid || outcome != 0 { C.printf(c'LINUX NNPTHREAD FAIL: direct=%d wait=%d outcome=%d\n', wanted, waited, outcome); return false }
		return true
	}
}
fn zombie_status(wanted i32) bool {
	unsafe {
		pid := C.fork()
		if pid < 0 { return false }
		if pid == 0 {
			if wanted == 1 && !set() { C._exit(41) }
			C._exit(0)
		}
		mut information := C.siginfo_t{}
		if C.waitid(C.P_PID, u32(pid), &information, C.WEXITED | C.WNOWAIT) != 0 { return false }
		mut path := [128]char{}
		C.snprintf(&path[0], usize(path.len), c'/proc/%d/status', pid)
		valid := status(&path[0], wanted)
		mut outcome := i32(0)
		waited := C.waitpid(pid, &outcome, 0)
		if !valid || waited != pid || outcome != 0 { C.printf(c'LINUX NNPTHREAD FAIL: zombie=%d status=%d wait=%d outcome=%d\n', wanted, i32(valid), waited, outcome); return false }
		return true
	}
}
fn peer_thread(argument voidptr) voidptr {
	unsafe {
		mut peer := &Peer(argument)
		peer.tid = C.syscall(isize(C.SYS_gettid))
		if !own_state(0) { peer.failed = 1 }
		C.__atomic_store_n(&peer.stage, 1, 3)
		for C.__atomic_load_n(&peer.stage, 2) != 2 { C.sched_yield() }
		if peer.set_self && !set() { peer.failed = 1 }
		wanted := if peer.set_self { i32(1) } else { i32(0) }
		if !own_state(wanted) || !status(c'/proc/self/status', peer.leader)
			|| !authorization(wanted) || !descendants(wanted) { peer.failed = 1 }
		C.__atomic_store_n(&peer.stage, 3, 3)
		for C.__atomic_load_n(&peer.stage, 2) != 4 { C.sched_yield() }
		return nil
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		if argc == 2 {
			if C.strcmp(argv[1], c'--thread-exec0') == 0 || C.strcmp(argv[1], c'--thread-exec1') == 0 {
				mut request := DirectExec{ wanted: if C.strcmp(argv[1], c'--thread-exec0') == 0 { i32(0) } else { i32(1) } }
				mut handle := C.pthread_t{}
				if !own_state(0) || C.pthread_create(&handle, nil, exec_thread, &request) != 0 { return 30 }
				for C.__atomic_load_n(&request.stage, 2) != 1 { C.sched_yield() }
				if request.wanted == 0 && !set() { return 35 }
				C.__atomic_store_n(&request.stage, 2, 3)
				for { C.pause() }
			}
			wanted := if C.strcmp(argv[1], c'--probe0') == 0 { i32(0) } else if C.strcmp(argv[1], c'--probe1') == 0 { i32(1) } else { return 2 }
			if !own_state(wanted) || !status(c'/proc/self/status', wanted) || !authorization(wanted) { return 23 }
			C.printf(c'LINUX NNPTHREAD CHILD: fork/exec retained %d\n', wanted)
			return 0
		}
		if C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { return 1 }
		if !zombie_status(0) || !zombie_status(1) { return 1 }
		if !direct_exec(0) || !direct_exec(1) { C.puts(c'LINUX NNPTHREAD FAIL: nonleader exec'); return 1 }
		for round in 0 .. 2 {
			mut peer := Peer{ set_self: round == 0, leader: i32(round) }
			mut handle := C.pthread_t{}
			if !own_state(0) || C.pthread_create(&handle, nil, peer_thread, &peer) != 0 { return 1 }
			for C.__atomic_load_n(&peer.stage, 2) != 1 { C.sched_yield() }
			if round == 1 && !set() { return 1 }
			C.__atomic_store_n(&peer.stage, 2, 3)
			for C.__atomic_load_n(&peer.stage, 2) != 3 { C.sched_yield() }
			mut path := [128]char{}
			C.snprintf(&path[0], usize(path.len), c'/proc/self/task/%ld/status', peer.tid)
			wanted := if peer.set_self { i32(1) } else { i32(0) }
			valid := peer.failed == 0 && own_state(i32(round)) && status(c'/proc/self/status', i32(round))
				&& status(&path[0], wanted) && authorization(i32(round))
			C.__atomic_store_n(&peer.stage, 4, 3)
			if C.pthread_join(handle, nil) != 0 || !valid {
				C.printf(c'LINUX NNPTHREAD FAIL: round=%d peer_failed=%d leader=%d\n', round, peer.failed, state())
				return 1
			}
		}
		if !descendants(1) { C.puts(c'LINUX NNPTHREAD FAIL: leader descendants'); return 1 }
		C.puts(c'LINUX NNPTHREAD PASS: independent siblings, clone/fork/exec inheritance, authorization and procfs')
		C.puts(c'LINUX NNPTHREAD: PASS')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
