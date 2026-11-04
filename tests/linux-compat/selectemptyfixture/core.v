// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module selectemptyfixture

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <sys/select.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

@[typedef]
struct C.pthread_t {}
@[typedef]
struct C.sigset_t {}
@[typedef]
struct C.fd_set {}
struct C.timespec { mut: tv_sec i64 tv_nsec i64 }
struct C.timeval { mut: tv_sec i64 tv_usec i64 }
struct C.sigaction {
mut:
	sa_handler fn (i32)
	sa_mask C.sigset_t
	sa_flags i32
}
struct Totals { mut: checks int failures int }
struct State {
	tid int
	pid int
	api int
	nfds int
	buffer int
	mode int
	restart int
mut:
	entered int
	done int
	sleeps int
	ignored int
	sent int
	calls int
	observed u64
}
__global ( active &State )
fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.printf(&char, ...) i32
fn C.snprintf(&char, usize, &char, ...) i32
fn C.fflush(voidptr) i32
fn C.alarm(u32) u32
fn C.pause() i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.pipe(&i32) i32
fn C.open(&char, i32, ...) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.pread(i32, voidptr, usize, i64) isize
fn C.sscanf(&char, &char, ...) i32
fn C.usleep(u32) i32
fn C.strcmp(&char, &char) i32
fn C.alloca(usize) voidptr
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.getuid() u32
fn C.getgid() u32
fn C._exit(i32)
fn C.sigaction(i32, &C.sigaction, &C.sigaction) i32
fn C.sigemptyset(&C.sigset_t) i32
fn C.sigaddset(&C.sigset_t, i32) i32
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.__atomic_load_n(&int, int) int
fn C.__atomic_store_n(&int, int, int)
fn C.clock_gettime(i32, &C.timespec) i32
fn C.pselect(i32, &C.fd_set, &C.fd_set, &C.fd_set, &C.timespec, &C.sigset_t) i32
fn C.select(i32, &C.fd_set, &C.fd_set, &C.fd_set, &C.timeval) i32

fn fatal(stage int) {
	C.printf(c'LINUX SELECTEMPTY FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil }); C._exit(90)
}
fn check(mut t Totals, good bool, stage int) {
	t.checks++
	if !good {
		t.failures++
		unsafe { C.printf(c'LINUX SELECTEMPTY MISMATCH: api=%d nfds=%d buffer=%d mode=%d restart=%d stage=%d\n', active.api, active.nfds, active.buffer, active.mode, active.restart, stage) }
	}
}
fn now() i64 {
	mut ts := C.timespec{}
	if C.clock_gettime(C.CLOCK_MONOTONIC, &ts) != 0 { fatal(1) }
	return ts.tv_sec * 1_000_000_000 + ts.tv_nsec
}
fn mask() u64 {
	mut value := u64(0)
	if C.syscall(isize(C.SYS_rt_sigprocmask), 2, unsafe { nil }, &value, usize(8)) != 0 { fatal(2) }
	return value
}
fn setmask(value u64) {
	if C.syscall(isize(C.SYS_rt_sigprocmask), 2, &value, unsafe { nil }, usize(8)) != 0 { fatal(3) }
}
fn send_to(s &State, signal int) isize { return C.syscall(isize(C.SYS_tgkill), s.pid, s.tid, signal) }
fn handler(_signal i32) {
	unsafe { active.calls++; active.observed = mask() }
}
fn sleeping(tid int) bool {
	mut path := [96]u8{}
	if C.snprintf(unsafe { &char(&path[0]) }, sizeof(path), c'/proc/self/task/%d/stat', tid) <= 0 { fatal(4) }
	fd := C.open(unsafe { &char(&path[0]) }, C.O_RDONLY)
	if fd < 0 { fatal(5) }
	mut text := [1024]u8{}
	n := int(C.read(fd, &text[0], sizeof(text)))
	C.close(fd)
	if n < 4 { fatal(6) }
	for i := n - 3; i >= 0; i-- {
		if unsafe { (&u8(&text[0]))[i] } == `)` { return unsafe { (&u8(&text[0]))[i + 2] } == `S` }
	}
	fatal(7); return false
}
fn observer(argument voidptr) voidptr {
	unsafe {
		mut s := &State(argument)
		// The child's alarm bounds the whole handshake. Do not replace a
		// missing observation with a signal merely because sampling ran late.
		for {
			if C.__atomic_load_n(&s.done, 5) != 0 { return nil }
			if C.__atomic_load_n(&s.entered, 5) == 0 || !sleeping(s.tid) {
				C.syscall(isize(C.SYS_sched_yield)); continue
			}
			if C.__atomic_load_n(&s.done, 5) != 0 { return nil }
			if s.sleeps == 0 {
				s.sleeps = 1
				s.ignored = int(send_to(s, C.SIGWINCH))
				// The ignored signal must leave the indefinite wait sleeping.
				continue
			}
			s.sleeps = 2
			s.sent = int(send_to(s, C.SIGUSR1))
			return nil
		}
	}
}
fn wait_call(api int, nfds int, fds &u64, timeout &C.timespec, temporary &u64) isize {
	unsafe {
		writes := if fds == nil { &u64(nil) } else { fds + 16 }
		excepts := if fds == nil { &u64(nil) } else { fds + 32 }
		match api {
			0 {
				pair := [u64(temporary), u64(8)]!
				return C.syscall(isize(C.SYS_pselect6), nfds, fds, writes, excepts, timeout, &pair[0])
			}
			1 { return C.pselect(nfds, &C.fd_set(fds), &C.fd_set(writes), &C.fd_set(excepts), timeout, &C.sigset_t(temporary)) }
			2 { return C.select(nfds, &C.fd_set(fds), &C.fd_set(writes), &C.fd_set(excepts), &C.timeval(timeout)) }
			else {
				$if amd64 { return C.syscall(isize(C.SYS_select), nfds, fds, writes, excepts, timeout) }
				$else { fatal(8); return -1 }
			}
		}
	}
}
fn suite(api int, nfds int, buffer int, mode int, restart int) Totals {
	unsafe {
		C.alarm(30)
		mut s := State{tid: int(C.syscall(isize(C.SYS_gettid))), pid: int(C.syscall(isize(C.SYS_getpid))), api: api, nfds: nfds, buffer: buffer, mode: mode, restart: restart, sent: -99, ignored: -99}
		active = &s
		mut totals := Totals{}
		mut action := C.sigaction{sa_handler: handler, sa_flags: if restart == 1 { C.SA_RESTART } else { 0 }}
		if C.sigemptyset(&action.sa_mask) != 0 || C.sigaddset(&action.sa_mask, C.SIGTERM) != 0 || C.sigaction(C.SIGUSR1, &action, nil) != 0 { fatal(9) }
		original := u64(1) << u64(C.SIGINT - 1) | if mode == 0 { u64(1) << u64(C.SIGUSR1 - 1) } else { u64(0) }
		temporary := u64(1) << u64(C.SIGPIPE - 1)
		setmask(original)
		mut bits := [50]u64{}
		bits[0] = u64(0xabcddcba12344321); bits[49] = bits[0]
		fds := if buffer == 0 { &u64(nil) } else { &bits[1] }
		mut worker_id := C.pthread_t{}
		if mode == 0 {
			check(mut totals, send_to(&s, C.SIGUSR1) == 0 && s.calls == 0, 10)
		} else if mode == 1 {
			if C.pthread_create(&worker_id, nil, observer, &s) != 0 { fatal(10) }
		}
		mut timeout := C.timespec{}
		if mode == 3 {
			// select's timeval uses microseconds; pselect uses nanoseconds.
			timeout.tv_nsec = if api >= 2 { 1000 } else { 1_000_000 }
		}
		started := now()
		C.__atomic_store_n(&s.entered, 1, 5)
		ret := wait_call(api, nfds, fds, if mode <= 1 { &C.timespec(nil) } else { &timeout }, if api < 2 { &temporary } else { &u64(nil) })
		call_errno := *C.__errno_location()
		C.__atomic_store_n(&s.done, 1, 5)
		elapsed := now() - started
		if mode == 1 && C.pthread_join(worker_id, nil) != 0 { fatal(11) }
		check(mut totals, if mode <= 1 { ret == -1 && call_errno == C.EINTR } else { ret == 0 }, 11)
		check(mut totals, s.calls == if mode <= 1 { 1 } else { 0 }, 12)
		if mode <= 1 {
			expected := (if api < 2 { temporary } else { original }) | (u64(1) << u64(C.SIGUSR1 - 1)) | (u64(1) << u64(C.SIGTERM - 1))
			check(mut totals, s.observed == expected, 13)
		}
		check(mut totals, mask() == original, 14)
		check(mut totals, bits[0] == u64(0xabcddcba12344321) && bits[49] == bits[0], 15)
		mut empty := true
		for i in 1 .. 49 { if bits[i] != 0 { empty = false } }
		check(mut totals, empty, 16)
		if mode == 1 {
			check(mut totals, s.sleeps == 2 && s.ignored == 0 && s.sent == 0, 17)
		}
		if mode == 3 { check(mut totals, elapsed >= 1_000_000, 18) }
		return totals
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		C.alarm(600)
		reference := argc == 2 && C.strcmp(argv[1], c'--reference') == 0
		mut total := Totals{}
		mut apis := 3
		$if amd64 { apis = 4 }
		for ordinary in [false, true]! { for api in 0 .. apis { for nfds in [0, 1, 65, 1024]! { for buffer in 0 .. 2 { for mode in 0 .. 4 { for restart in 0 .. 2 {
			if api >= 2 && mode == 0 { continue }
			mut fds := [2]i32{}
			if C.pipe(&fds[0]) != 0 { fatal(12) }
			C.fflush(nil)
			pid := C.fork()
			if pid < 0 { fatal(13) }
			if pid == 0 {
				C.close(fds[0])
				if ordinary && (C.setgid(2000) != 0 || C.setuid(1000) != 0) { fatal(14) }
				t := suite(api, nfds, buffer, mode, restart)
				C.printf(c'LINUX SELECTEMPTY CASE: uid=%u gid=%u api=%d nfds=%d buffer=%d mode=%d restart=%d checks=%d failures=%d\n', C.getuid(), C.getgid(), api, nfds, buffer, mode, restart, t.checks, t.failures)
				if C.write(fds[1], &t, sizeof(t)) != sizeof(t) { fatal(15) }
				C.fflush(nil); C._exit(0)
			}
			C.close(fds[1])
			mut t := Totals{}
			if C.read(fds[0], &t, sizeof(t)) != sizeof(t) { fatal(16) }
			mut status := i32(0)
			if C.waitpid(pid, &status, 0) != pid || status != 0 { fatal(17) }
			C.close(fds[0]); total.checks += t.checks; total.failures += t.failures
		} } } } } }
		mut storage_good := true
		for ordinary in [false, true]! {
			C.fflush(nil)
			pid := C.fork()
			if pid < 0 { fatal(18) }
			if pid == 0 {
				if ordinary && (C.setgid(2000) != 0 || C.setuid(1000) != 0) { fatal(19) }
				if reference {
					C.printf(c'LINUX SELECTEMPTY STORAGE: uid=%u SKIP reference\n', C.getuid())
					C.fflush(nil); C._exit(0)
				}
				good := storage()
				C.fflush(nil); C._exit(if good { 0 } else { 1 })
			}
			mut status := i32(0)
			if C.waitpid(pid, &status, 0) != pid { fatal(20) }
			if status != 0 { storage_good = false }
		}
		C.printf(c'LINUX SELECTEMPTY SUMMARY: checks=%d failures=%d\n', total.checks, total.failures)
		if total.failures == 0 && storage_good { C.printf(c'LINUX SELECTEMPTY: PASS\n') } else { C.printf(c'LINUX SELECTEMPTY: FAIL\n') }
		C.fflush(nil); C.alarm(0)
		for { C.pause() }
	}
	return 0
}
