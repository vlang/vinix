// SPDX-License-Identifier: GPL-2.0-or-later
module seccompthreadfixture

#include <errno.h>
#include <dirent.h>
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
struct SockFilter { code u16 jt u8 jf u8 k u32 }
struct SockFprog { len u16 filter &SockFilter }
struct Peer {
mut:
	stage i32
	tid isize
	failed i32
	kind i32
}
struct Probe { count i32 error i32 nnp i32 }

fn C.syscall(isize, ...) isize
fn C.prctl(i32, ...) i32
fn C.__errno_location() &i32
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
fn C.pread(i32, voidptr, usize, i64) isize
fn C.read(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.snprintf(&char, usize, &char, ...) i32
fn C.strstr(&char, &char) &char
fn C.strcmp(&char, &char) i32
fn C.sscanf(&char, &char, ...) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.usleep(u32) i32
fn C.opendir(&char) voidptr
fn C.readdir(voidptr) voidptr
fn C.closedir(voidptr) i32

fn nnp() i32 { return unsafe { C.prctl(C.PR_GET_NO_NEW_PRIVS, usize(0), usize(0), usize(0), usize(0)) } }
fn set_nnp() bool { return unsafe { C.prctl(C.PR_SET_NO_NEW_PRIVS, usize(1), usize(0), usize(0), usize(0)) == 0 } }
fn mode() i32 { return unsafe { C.prctl(C.PR_GET_SECCOMP, usize(0), usize(0), usize(0), usize(0)) } }
fn install(error_code i32, flags u32) isize {
	unsafe {
		mut instructions := [SockFilter{code: 0x20}, SockFilter{code: 0x15, jf: 1, k: u32(C.SYS_getpid)},
			SockFilter{code: 0x06, k: u32(0x00050000) | u32(error_code)}, SockFilter{code: 0x06, k: 0x7fff0000}]!
		program := SockFprog{len: 4, filter: &instructions[0]}
		return C.syscall(isize(C.SYS_seccomp), isize(1), isize(flags), &program)
	}
}
fn status(path &char, count i32, expected_nnp i32) bool {
	unsafe {
		fd := C.open(path, C.O_RDONLY)
		if fd < 0 { return false }
		mut data := [4096]char{}
		length := C.pread(fd, &data[0], usize(data.len - 1), 0)
		closed := C.close(fd)
		if length <= 0 || closed != 0 { return false }
		data[int(length)] = 0
		mut wanted := [64]char{}
		C.snprintf(&wanted[0], usize(wanted.len), c'Seccomp_filters:\t%d\n', count)
		return C.strstr(&data[0], &wanted[0]) != nil
			&& C.strstr(&data[0], if count == 0 { c'Seccomp:\t0\n' } else { c'Seccomp:\t2\n' }) != nil
			&& C.strstr(&data[0], if expected_nnp == 0 { c'NoNewPrivs:\t0\n' } else { c'NoNewPrivs:\t1\n' }) != nil
	}
}
fn check(count i32, error_code i32, expected_nnp i32) bool {
	unsafe {
		e := C.__errno_location()
		*e = 0
		result := C.syscall(isize(C.SYS_getpid))
		valid := if error_code == 0 { result > 0 } else { result == -1 && *e == error_code }
		actual_error := *e
		valid_state := mode() == if count == 0 { 0 } else { 2 }
			&& nnp() == expected_nnp && status(c'/proc/thread-self/status', count, expected_nnp)
		if !valid || !valid_state { C.printf(c'LINUX SECCOMPTHREAD FAIL: count=%d error=%d nnp=%d actual=%ld/%d mode=%d nnp=%d\n', count, error_code, expected_nnp, result, actual_error, mode(), nnp()) }
		return valid && valid_state
	}
}
fn raw_check(error_code i32, expected_nnp i32) bool {
	unsafe {
		e := C.__errno_location(); *e = 0
		result := C.syscall(isize(C.SYS_getpid))
		return (if error_code == 0 { result > 0 } else { result == -1 && *e == error_code })
			&& mode() == if error_code == 0 { 0 } else { 2 } && nnp() == expected_nnp
	}
}
fn probe_thread(arg voidptr) voidptr {
	unsafe {
		p := &Probe(arg)
		return voidptr(usize(if check(p.count, p.error, p.nnp) { 0 } else { 1 }))
	}
}
fn descendants(count i32, error_code i32, expected_nnp i32) bool {
	unsafe {
		mut probe := Probe{count: count, error: error_code, nnp: expected_nnp}
		mut handle := C.pthread_t{}
		mut answer := voidptr(nil)
		if C.pthread_create(&handle, nil, probe_thread, &probe) != 0
			|| C.pthread_join(handle, &answer) != 0 || answer != nil { return false }
		child := C.fork()
		if child < 0 { return false }
		if child == 0 {
			if !check(count, error_code, expected_nnp) || !status(c'/proc/self/status', count, expected_nnp) { C._exit(20) }
			mut option := [80]char{}
			C.snprintf(&option[0], usize(option.len), c'--probe-%d-%d-%d', count, error_code, expected_nnp)
			C.execl(c'/proc/self/exe', c'init', &option[0], voidptr(nil))
			C._exit(21)
		}
		mut outcome := i32(0)
		return C.waitpid(child, &outcome, 0) == child && outcome == 0
	}
}
fn peer_thread(argument voidptr) voidptr {
	unsafe {
		mut peer := &Peer(argument)
		peer.tid = C.syscall(isize(C.SYS_gettid))
		if peer.kind in [0, 4]! {
			if peer.kind == 0 && !set_nnp() { peer.failed = 1 }
			if install(13, 0) != 0 { peer.failed = 1 }
		} else if peer.kind == 3 {
			if !check(1, 13, 1) || install(22, 0) != 0 { peer.failed = 1 }
		} else if peer.kind == 5 {
			if !set_nnp() { peer.failed = 1 }
		} else if peer.kind == 6 {
			if !set_nnp() || install(13, 0) != 0 { C._exit(22) }
		}
		C.__atomic_store_n(&peer.stage, 1, 3)
		for C.__atomic_load_n(&peer.stage, 2) != 2 { C.sched_yield() }
		mut count := i32(1)
		mut error_code := i32(13)
		mut expected_nnp := i32(1)
		match peer.kind {
			0 {}
			1 { count = 0; error_code = 0; expected_nnp = 0 }
			2 {}
			3 {
				if !check(2, 22, 1) || install(33, 1) != 0 { peer.failed = 1 }
				count = 3; error_code = 33
			}
			4 { expected_nnp = 0 }
			5 {}
			6 {
				if !check(1, 13, 1) { C._exit(23) }
				C.execl(c'/proc/self/exe', c'init', c'--probe-1-13-1', voidptr(nil))
				C._exit(24)
			}
			else { peer.failed = 1 }
		}
		if !check(count, error_code, expected_nnp) || !descendants(count, error_code, expected_nnp) { peer.failed = 1 }
		C.__atomic_store_n(&peer.stage, 3, 3)
		for C.__atomic_load_n(&peer.stage, 2) != 4 { C.sched_yield() }
		return nil
	}
}
fn threaded(kind i32) bool {
	unsafe {
		if kind in [0, 1, 2, 3, 6]! {
			if C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { return false }
		}
		if kind == 3 && (!set_nnp() || install(13, 0) != 0) { return false }
		mut peer := Peer{kind: kind}
		mut handle := C.pthread_t{}
		if C.pthread_create(&handle, nil, peer_thread, &peer) != 0 { return false }
		for C.__atomic_load_n(&peer.stage, 2) != 1 { C.sched_yield() }
		mut count := i32(1)
		mut error_code := i32(13)
		mut expected_nnp := i32(1)
		match kind {
			0 { if !check(0, 0, 0) || !set_nnp() || install(1, 0) != 0 { return false }; error_code = 1 }
			1 { if !set_nnp() || install(13, 0) != 0 { return false } }
			2 { if !set_nnp() || install(13, 1) != 0 { return false } }
			3, 4 {
				if kind == 4 && (!set_nnp() || install(13, 0) != 0) { return false }
				for flags in [u32(1), 17]! {
					e := C.__errno_location(); *e = 0
					result := install(99, flags)
					if result != if flags == 1 { peer.tid } else { isize(-1) }
						|| *e != if flags == 1 { 0 } else { C.ESRCH }
						|| !check(1, 13, 1) { C.puts(c'LINUX SECCOMPTHREAD FAIL: TSYNC refusal/state'); return false }
				}
				if kind == 3 { count = 3; error_code = 33 }
			}
			5 { if install(13, 1) != 0 { return false }; expected_nnp = 0 }
			6 { if !set_nnp() || install(22, 0) != 0 { C._exit(25) } }
			else { return false }
		}
		C.__atomic_store_n(&peer.stage, 2, 3)
		// Stay in userspace: exec must take the stopped-sibling path rather
		// than depending on the leader to unwind a blocking syscall.
		if kind == 6 { for { C.__atomic_load_n(&peer.stage, 2) } }
		for C.__atomic_load_n(&peer.stage, 2) != 3 { C.sched_yield() }
		mut path := [128]char{}
		C.snprintf(&path[0], usize(path.len), c'/proc/self/task/%ld/status', peer.tid)
		peer_count := if kind == 1 { i32(0) } else { count }
		peer_nnp := if kind in [1, 4]! { i32(0) } else { i32(1) }
		valid := peer.failed == 0 && check(count, error_code, expected_nnp)
			&& status(c'/proc/self/status', count, expected_nnp) && status(&path[0], peer_count, peer_nnp)
		C.__atomic_store_n(&peer.stage, 4, 3)
		if C.pthread_join(handle, nil) != 0 || !valid { return false }
		if kind == 4 && (install(22, 1) != 0 || !check(2, 22, 1)) { return false }
		return descendants(if kind == 4 { i32(2) } else { count }, if kind == 4 { i32(22) } else { error_code }, expected_nnp)
	}
}
fn limit_case() bool {
	unsafe {
		if !set_nnp() { return false }
		mut instructions := [4096]SockFilter{}
		instructions[4095] = SockFilter{code: 0x06, k: 0x7fff0000}
		mut program := SockFprog{len: 4096, filter: &instructions[0]}
		for _ in 0 .. 7 {
			if C.syscall(isize(C.SYS_seccomp), isize(1), isize(0), &program) != 0 { return false }
		}
		instructions[4067] = SockFilter{code: 0x06, k: 0x7fff0000}
		program.len = 4068
		if C.syscall(isize(C.SYS_seccomp), isize(1), isize(0), &program) != 0 || !check(8, 0, 1) { return false }
		program.len = 1
		instructions[0] = SockFilter{code: 0x06, k: 0x7fff0000}
		e := C.__errno_location(); *e = 0
		return C.syscall(isize(C.SYS_seccomp), isize(1), isize(1), &program) == -1 && *e == C.ENOMEM && check(8, 0, 1)
	}
}
fn churn_thread(_ voidptr) voidptr {
	unsafe {
		if !set_nnp() { return voidptr(usize(1)) }
		for _ in 0 .. 4 { if install(13, 0) != 0 { return voidptr(usize(1)) } }
		return voidptr(usize(if raw_check(13, 1) { 0 } else { 1 }))
	}
}
fn churn_exec_thread(argument voidptr) voidptr {
	unsafe {
		mut peer := &Peer(argument)
		if !set_nnp() { C._exit(40) }
		for _ in 0 .. 4 { if install(13, 0) != 0 { C._exit(41) } }
		C.__atomic_store_n(&peer.stage, 1, 3)
		for C.__atomic_load_n(&peer.stage, 2) != 2 { C.sched_yield() }
		if !raw_check(13, 1) { C._exit(42) }
		C.execl(c'/sbin/init', c'init', c'--churn-probe', voidptr(nil))
		C._exit(43)
		return nil
	}
}
fn forced_exec() bool {
	unsafe {
		child := C.fork()
		if child < 0 { return false }
		if child == 0 {
			if C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { C._exit(44) }
			mut peer := Peer{}; mut handle := C.pthread_t{}
			if C.pthread_create(&handle, nil, churn_exec_thread, &peer) != 0 { C._exit(45) }
			for C.__atomic_load_n(&peer.stage, 2) != 1 { C.sched_yield() }
			if !set_nnp() { C._exit(46) }
			for _ in 0 .. 4 { if install(22, 0) != 0 { C._exit(47) } }
			C.__atomic_store_n(&peer.stage, 2, 3)
			for { C.__atomic_load_n(&peer.stage, 2) }
		}
		mut outcome := i32(0)
		return C.waitpid(child, &outcome, 0) == child && outcome == 0
	}
}
fn concurrent_probe(_ voidptr) voidptr {
	unsafe {
		e := C.__errno_location(); *e = 0
		valid := C.syscall(isize(C.SYS_getpid)) == -1 && *e == 13 && mode() == 2 && nnp() == 1
		return voidptr(usize(if valid { 0 } else { 1 }))
	}
}
fn cloning_peer(argument voidptr) voidptr {
	unsafe {
		mut peer := &Peer(argument)
		C.__atomic_store_n(&peer.stage, 1, 3)
		for C.__atomic_load_n(&peer.stage, 2) != 2 { C.sched_yield() }
		for _ in 0 .. 100 {
			mut handle := C.pthread_t{}; mut answer := voidptr(nil)
			if C.pthread_create(&handle, nil, concurrent_probe, nil) != 0 || C.pthread_join(handle, &answer) != 0 || answer != nil { peer.failed = 1 }
		}
		C.__atomic_store_n(&peer.stage, 3, 3)
		return nil
	}
}
fn concurrent_case() bool {
	unsafe {
		if !set_nnp() || install(13, 1) != 0 { return false }
		mut peer := Peer{}; mut handle := C.pthread_t{}
		if C.pthread_create(&handle, nil, cloning_peer, &peer) != 0 { return false }
		for C.__atomic_load_n(&peer.stage, 2) != 1 { C.sched_yield() }
		C.__atomic_store_n(&peer.stage, 2, 3)
		for _ in 0 .. 100 { if install(13, 1) != 0 { return false }; C.sched_yield() }
		return C.pthread_join(handle, nil) == 0 && peer.failed == 0 && check(101, 13, 1)
	}
}
fn zombie_case() bool {
	unsafe {
		child := C.fork()
		if child < 0 { return false }
		if child == 0 {
			if !set_nnp() || install(13, 0) != 0 { C._exit(30) }
			C._exit(0)
		}
		mut information := C.siginfo_t{}
		if C.waitid(C.P_PID, u32(child), &information, C.WEXITED | C.WNOWAIT) != 0 { return false }
		// Let the leader's Thread be reclaimed; the zombie owns only scalars.
		C.usleep(13000000)
		mut path := [128]char{}
		C.snprintf(&path[0], usize(path.len), c'/proc/%d/status', child)
		valid := status(&path[0], 1, 1)
		mut outcome := i32(0)
		return C.waitpid(child, &outcome, 0) == child && outcome == 0 && valid
	}
}
fn slab(fd i32, size u64) ?u64 {
	unsafe {
		mut buffer := [4096]char{}
		length := C.pread(fd, &buffer[0], usize(buffer.len - 1), 0)
		if length <= 0 { C.printf(c'LINUX SECCOMPTHREAD FAIL: slab read length=%ld errno=%d\n', length, *C.__errno_location()); return none }
		buffer[int(length)] = 0
		mut prefix := [32]char{}
		C.snprintf(&prefix[0], usize(prefix.len), c'size-%lu ', size)
		row := C.strstr(&buffer[0], &prefix[0])
		if row == nil { C.puts(&buffer[0]); return none }
		mut parsed_size := u64(0); mut objects := u64(0); mut pages := u64(0)
		if C.sscanf(row, c'size-%*u %lu %lu %lu', &parsed_size, &objects, &pages) != 3 || parsed_size != size { C.puts(row); return none }
		return objects
	}
}
fn tracking(path &char, show bool) {
	unsafe {
		fd := C.open(path, C.O_RDONLY)
		if fd < 0 { return }
		mut data := [32768]char{}
		length := C.read(fd, &data[0], usize(data.len - 1))
		if length > 0 && show { data[int(length)] = 0; C.puts(&data[0]) }
		C.close(fd)
	}
}
fn prune_procfs() bool {
	unsafe {
		for path in [&char(c'/proc/self/task'), &char(c'/proc')]! {
			directory := C.opendir(path)
			if directory == nil { return false }
			for C.readdir(directory) != nil {}
			if C.closedir(directory) != 0 { return false }
		}
		return true
	}
}
fn churn() bool {
	unsafe {
		fd := C.open(c'/proc/slabinfo', C.O_RDONLY)
		if fd < 0 { return false }
		// Warm libc and exec before measuring filter storage. These cohorts
		// use raw queries: procfs's separately retained per-task trees would
		// obscure the filter/instruction classes. Earlier cases verify procfs.
		for _ in 0 .. 20 {
			mut handle := C.pthread_t{}
			if C.pthread_create(&handle, nil, churn_thread, nil) != 0 || C.pthread_join(handle, nil) != 0 { return false }
		}
		for _ in 0 .. 10 { if !forced_exec() { return false } }
		if !prune_procfs() { return false }
		// Procfs directory retirement cascades after task/PID reclamation.
		// Use the same grace window as the kernel retention harness.
		C.usleep(13000000)
		mut previous := [4]u64{}
		for i, size in [u64(32), 64, 96, 128]! { previous[i] = slab(fd, size) or { return false } }
		tracking(c'/proc/allocstart', false)
		for cycle in 0 .. 2 {
			for _ in 0 .. 200 {
				mut handle := C.pthread_t{}
				mut answer := voidptr(nil)
				if C.pthread_create(&handle, nil, churn_thread, nil) != 0
					|| C.pthread_join(handle, &answer) != 0 || answer != nil || !raw_check(0, 0) { return false }
			}
			for _ in 0 .. 100 { if !forced_exec() { return false } }
			if !prune_procfs() { return false }
			C.usleep(13000000)
			for i, size in [u64(32), 64, 96, 128]! {
				after := slab(fd, size) or { return false }
				C.printf(c'LINUX SECCOMPTHREAD SLAB: cycle=%d size=%lu before=%lu after=%lu delta=%ld\n', i32(cycle), size, previous[i], after, i64(after) - i64(previous[i]))
				if after > previous[i] { tracking(c'/proc/allocsites', true); C.puts(c'LINUX SECCOMPTHREAD FAIL: retained filter storage'); return false }
				previous[i] = after
			}
			C.printf(c'LINUX SECCOMPTHREAD CHURN: cycle=%d threads=200 filters=800 forced_exec=100\n', i32(cycle))
		}
		C.close(fd)
		return true
	}
}
@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		if argc == 2 {
			if C.strcmp(argv[1], c'--churn-probe') == 0 { return if raw_check(13, 1) { 0 } else { 48 } }
			mut count := i32(0); mut error_code := i32(0); mut expected_nnp := i32(0)
			// The parent's controlled options are deliberately parsed without V allocation.
			for p in [Probe{0, 0, 0}, Probe{1, 13, 1}, Probe{1, 1, 1}, Probe{1, 13, 0}, Probe{3, 33, 1}, Probe{2, 22, 1}]! {
				mut option := [80]char{}
				C.snprintf(&option[0], usize(option.len), c'--probe-%d-%d-%d', p.count, p.error, p.nnp)
				if C.strcmp(argv[1], &option[0]) == 0 { count = p.count; error_code = p.error; expected_nnp = p.nnp; break }
			}
			if !check(count, error_code, expected_nnp) || !status(c'/proc/self/status', count, expected_nnp) { return 26 }
			C.printf(c'LINUX SECCOMPTHREAD EXEC: count=%d error=%d nnp=%d\n', count, error_code, expected_nnp)
			return 0
		}
		for kind in 0 .. 11 {
			child := C.fork()
			if child < 0 { return 1 }
			if child == 0 {
				valid := if kind == 7 { limit_case() } else if kind == 8 { churn() }
					else if kind == 9 { concurrent_case() } else if kind == 10 { zombie_case() } else { threaded(i32(kind)) }
				C.fflush(nil)
				C._exit(if valid { 0 } else { 1 })
			}
			mut outcome := i32(0)
			if C.waitpid(child, &outcome, 0) != child || outcome != 0 || !check(0, 0, 0) {
				C.printf(c'LINUX SECCOMPTHREAD FAIL: kind=%d outcome=%d\n', i32(kind), outcome)
				return 1
			}
			C.printf(c'LINUX SECCOMPTHREAD CASE: %d PASS\n', i32(kind))
		}
		C.puts(c'LINUX SECCOMPTHREAD PASS: task ownership, clone/fork/exec, TSYNC ancestry/refusals, NNP and procfs')
		C.puts(c'LINUX SECCOMPTHREAD: PASS')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
