// SPDX-License-Identifier: GPL-2.0-or-later
// Independent POSIX timer fixture; original predicates and diagnostics retained.
@[translated]
@[has_globals]
module timerfixture

#include <timer-fixture-native-abi.h>

@[typedef] struct C.FILE {}
@[typedef] struct C.pthread_t {}
@[typedef] struct C.timer_t {}
@[typedef] struct C.sigset_t {}
@[typedef] struct C.vpt_native_ull {}
@[typedef] struct C.vpt_sigval { mut: sival_int i32 }
@[typedef] struct C.siginfo_t { mut: si_code i32 si_value C.vpt_sigval si_overrun i32 }
struct C.timespec { mut: tv_sec i64 tv_nsec i64 }
struct C.itimerspec { mut: it_interval C.timespec it_value C.timespec }
struct C.sigevent { mut:
	sigev_notify i32
	sigev_notify_function fn (C.vpt_sigval)
	sigev_value C.vpt_sigval
	sigev_signo i32
}
struct C.vpt_kernel_event { mut: value u64 signo i32 notify i32 tid i32 }
struct C.vpt_thread_state { mut: tid i32 result i32 code i32 value i32 timed i32 elapsed u64 }
@[c_extern] __global C.stdout &C.FILE
@[c_extern] __global C.errno i32
const posix_timer_mask = u64(1) << 31
__global posix_timer_callbacks i32

fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.setvbuf(&C.FILE, &char, i32, usize) i32
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C._exit(i32)
fn C.clock_gettime(i32, &C.timespec) i32
fn C.nanosleep(&C.timespec, &C.timespec) i32
fn C.__atomic_add_fetch(&i32, i32, i32) i32
fn C.__atomic_store_n(&i32, i32, i32)
fn C.__atomic_load_n(&i32, i32) i32
fn C.timer_create(i32, &C.sigevent, &C.timer_t) i32
fn C.timer_settime(C.timer_t, i32, &C.itimerspec, &C.itimerspec) i32
fn C.timer_gettime(C.timer_t, &C.itimerspec) i32
fn C.timer_getoverrun(C.timer_t) i32
fn C.timer_delete(C.timer_t) i32
fn C.syscall(isize, ...) isize
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.pthread_sigmask(i32, &C.sigset_t, &C.sigset_t) i32
fn C.sched_yield() i32
fn C.sigemptyset(&C.sigset_t) i32
fn C.sigaddset(&C.sigset_t, i32) i32
fn C.sigtimedwait(&C.sigset_t, &C.siginfo_t, &C.timespec) i32
fn C.getpid() i32
fn C.pipe(&i32) i32
fn C.fork() i32
fn C.close(i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) bool
fn C.WEXITSTATUS(i32) i32
fn C.open(&char, i32, ...) i32
fn C.dup2(i32, i32) i32
fn C.pause() i32
fn C.vpt_timer_callback(C.vpt_sigval)
fn C.vpt_timer_receiver(voidptr) voidptr

fn check(ok bool, line i32, expression &char) {
	unsafe {
		if !ok {
			C.printf(c'POSIX TIMER FAIL line=%d %s errno=%d\n', line, expression, C.errno)
			C._exit(1)
		}
	}
}

fn monotonic_ns() u64 {
	unsafe {
		mut t := C.timespec{}
		check(C.clock_gettime(C.CLOCK_MONOTONIC, &t) == 0, 29, c'clock_gettime(CLOCK_MONOTONIC, &t) == 0')
		return u64(t.tv_sec) * u64(1000000000) + u64(t.tv_nsec)
	}
}

fn pause_ms(ms i32) {
	unsafe {
		mut t := C.timespec{tv_sec: ms / 1000, tv_nsec: (ms % 1000) * 1000000}
		for C.nanosleep(&t, &t) < 0 { check(C.errno == C.EINTR, 36, c'errno == EINTR') }
	}
}

@[export: 'vpt_timer_callback']
pub fn callback(value C.vpt_sigval) {
	unsafe { if value.sival_int == 0x5649 { C.__atomic_add_fetch(&posix_timer_callbacks, 1, 3) } }
}

fn thread_test() {
	unsafe {
		for round := i32(0); round < 20; round++ {
			mut timer := C.timer_t{}
			mut ev := C.sigevent{sigev_notify: C.SIGEV_THREAD, sigev_notify_function: C.vpt_timer_callback,
				sigev_value: C.vpt_sigval{sival_int: 0x5649}}
			C.__atomic_store_n(&posix_timer_callbacks, 0, 3)
			check(C.timer_create(C.CLOCK_MONOTONIC, &ev, &timer) == 0, 53, c'timer_create(CLOCK_MONOTONIC, &ev, &timer) == 0')
			mut set := C.itimerspec{it_value: C.timespec{tv_nsec: 20000000}}
			check(C.timer_settime(timer, 0, &set, nil) == 0, 55, c'timer_settime(timer, 0, &set, NULL) == 0')
			for i := i32(0); i < 100 && C.__atomic_load_n(&posix_timer_callbacks, 2) == 0; i++ { pause_ms(10) }
			mut now := C.itimerspec{}
			check(C.timer_gettime(timer, &now) == 0, 59, c'timer_gettime(timer, &now) == 0')
			C.printf(c'POSIX TIMER THREAD round=%d callbacks=%d remaining=%ld.%09ld\n',
				round, posix_timer_callbacks, now.it_value.tv_sec, now.it_value.tv_nsec)
			check(C.__atomic_load_n(&posix_timer_callbacks, 2) == 1, 62, c'__atomic_load_n(&callbacks, __ATOMIC_ACQUIRE) == 1')
			check(now.it_value.tv_sec == 0 && now.it_value.tv_nsec == 0, 63, c'now.it_value.tv_sec == 0 && now.it_value.tv_nsec == 0')
			check(C.timer_getoverrun(timer) == 0, 64, c'timer_getoverrun(timer) == 0')
			check(C.timer_delete(timer) == 0, 65, c'timer_delete(timer) == 0')
			pause_ms(5)
		}
		mut timer := C.timer_t{}
		mut ev := C.sigevent{sigev_notify: C.SIGEV_THREAD, sigev_notify_function: C.vpt_timer_callback,
			sigev_value: C.vpt_sigval{sival_int: 0x5649}}
		check(C.timer_create(C.CLOCK_MONOTONIC, &ev, &timer) == 0, 73, c'timer_create(CLOCK_MONOTONIC, &ev, &timer) == 0')
		mut set := C.itimerspec{it_value: C.timespec{tv_nsec: 200000000}}
		check(C.timer_settime(timer, 0, &set, nil) == 0, 75, c'timer_settime(timer, 0, &set, NULL) == 0')
		check(C.timer_delete(timer) == 0, 76, c'timer_delete(timer) == 0')
		pause_ms(250)
		check(C.__atomic_load_n(&posix_timer_callbacks, 2) == 1, 78, c'__atomic_load_n(&callbacks, __ATOMIC_ACQUIRE) == 1')
		C.puts(c'POSIX TIMER PASS: musl callback')
	}
}

@[export: 'vpt_timer_receiver']
pub fn receiver(argument voidptr) voidptr {
	unsafe {
		s := &C.vpt_thread_state(argument)
		check(C.syscall(C.SYS_rt_sigprocmask, C.SIG_BLOCK, voidptr(&posix_timer_mask), nil, 8) == 0, 86, c'syscall(SYS_rt_sigprocmask, SIG_BLOCK, &timer_mask, NULL, 8) == 0')
		C.__atomic_store_n(&s.tid, i32(C.syscall(C.SYS_gettid)), 3)
		mut si := C.siginfo_t{}
		mut timeout := C.timespec{tv_sec: 2}
		start := monotonic_ns()
		s.result = i32(C.syscall(C.SYS_rt_sigtimedwait, voidptr(&posix_timer_mask), &si,
			if s.timed != 0 { &timeout } else { &C.timespec(nil) }, 8))
		s.elapsed = monotonic_ns() - start
		s.code = si.si_code
		s.value = si.si_value.sival_int
		return nil
	}
}

fn thread_id_test() {
	unsafe {
		for timed := i32(0); timed <= 1; timed++ {
			mut s := C.vpt_thread_state{timed: timed}
			mut native_thread := C.pthread_t{}
			check(C.pthread_create(&native_thread, nil, C.vpt_timer_receiver, &s) == 0, 104, c'pthread_create(&t, NULL, receiver, &s) == 0')
			for C.__atomic_load_n(&s.tid, 2) == 0 { C.sched_yield() }
			mut ev := C.vpt_kernel_event{value: 0x12345, signo: 32, notify: C.SIGEV_THREAD_ID, tid: s.tid}
			mut id := i32(0)
			check(C.syscall(C.SYS_timer_create, C.CLOCK_MONOTONIC, &ev, &id) == 0, 109, c'syscall(SYS_timer_create, CLOCK_MONOTONIC, &ev, &id) == 0')
			mut set := C.itimerspec{it_value: C.timespec{tv_nsec: 20000000}}
			check(C.syscall(C.SYS_timer_settime, id, 0, &set, nil) == 0, 111, c'syscall(SYS_timer_settime, id, 0, &set, NULL) == 0')
			check(C.pthread_join(native_thread, nil) == 0, 112, c'pthread_join(t, NULL) == 0')
			mut elapsed := C.vpt_native_ull{}
			C.memcpy(&elapsed, &s.elapsed, sizeof(C.vpt_native_ull))
			C.printf(c'POSIX TIMER THREAD-ID timed=%d result=%d code=%d value=%d elapsed_ns=%llu\n',
				timed, s.result, s.code, s.value, elapsed)
			check(s.result == 32 && s.code == C.SI_TIMER && s.value == 0x12345, 115, c's.result == 32 && s.code == SI_TIMER && s.value == 0x12345')
			check(s.elapsed < 1000000000, 116, c's.elapsed < 1000000000')
			check(C.syscall(C.SYS_timer_delete, id) == 0, 117, c'syscall(SYS_timer_delete, id) == 0')
		}
		C.puts(c'POSIX TIMER PASS: thread-id')
	}
}

fn synchronous_test() {
	unsafe {
		signo := i32(C.SIGRTMIN)
		mut set := C.sigset_t{}
		C.sigemptyset(&set)
		C.sigaddset(&set, signo)
		check(C.pthread_sigmask(C.SIG_BLOCK, &set, nil) == 0, 127, c'pthread_sigmask(SIG_BLOCK, &set, NULL) == 0')
		mut timer := C.timer_t{}
		mut ev := C.sigevent{sigev_notify: C.SIGEV_SIGNAL, sigev_signo: signo, sigev_value: C.vpt_sigval{sival_int: 0x7788}}
		check(C.timer_create(C.CLOCK_MONOTONIC, &ev, &timer) == 0, 131, c'timer_create(CLOCK_MONOTONIC, &ev, &timer) == 0')
		mut setting := C.itimerspec{it_value: C.timespec{tv_nsec: 20000000}}
		check(C.timer_settime(timer, 0, &setting, nil) == 0, 133, c'timer_settime(timer, 0, &setting, NULL) == 0')
		mut si := C.siginfo_t{}
		start := monotonic_ns()
		mut two_seconds := C.timespec{tv_sec: 2}
		check(C.sigtimedwait(&set, &si, &two_seconds) == signo, 136, c'sigtimedwait(&set, &si, &(struct timespec){.tv_sec = 2}) == signo')
		check(monotonic_ns() - start < 1000000000, 137, c'monotonic_ns() - start < 1000000000')
		check(si.si_code == C.SI_TIMER && si.si_value.sival_int == 0x7788, 138, c'si.si_code == SI_TIMER && si.si_value.sival_int == 0x7788')
		check(C.timer_settime(timer, 0, &setting, nil) == 0, 141, c'timer_settime(timer, 0, &setting, NULL) == 0')
		pause_ms(40)
		mut mask := u64(1) << (signo - 1)
		mut zero := C.timespec{}
		check(C.syscall(C.SYS_rt_sigtimedwait, &mask, voidptr(1), &zero, 8) == -1 && C.errno == C.EFAULT, 145, c'syscall(SYS_rt_sigtimedwait, &mask, (void *)1, &zero, 8) == -1 && errno == EFAULT')
		check(C.syscall(C.SYS_rt_sigtimedwait, &mask, &si, &zero, 8) == signo, 146, c'syscall(SYS_rt_sigtimedwait, &mask, &si, &zero, 8) == signo')
		check(si.si_code == C.SI_TIMER && si.si_value.sival_int == 0x7788, 147, c'si.si_code == SI_TIMER && si.si_value.sival_int == 0x7788')
		check(C.syscall(C.SYS_rt_sigtimedwait, &mask, &si, &zero, 8) == -1 && C.errno == C.EAGAIN, 148, c'syscall(SYS_rt_sigtimedwait, &mask, &si, &zero, 8) == -1 && errno == EAGAIN')
		check(C.timer_delete(timer) == 0, 149, c'timer_delete(timer) == 0')
		check(C.timer_create(C.CLOCK_MONOTONIC, &ev, &timer) == 0, 152, c'timer_create(CLOCK_MONOTONIC, &ev, &timer) == 0')
		setting.it_interval.tv_nsec = 10000000
		setting.it_value.tv_nsec = 10000000
		check(C.timer_settime(timer, 0, &setting, nil) == 0, 155, c'timer_settime(timer, 0, &setting, NULL) == 0')
		pause_ms(70)
		check(C.syscall(C.SYS_rt_sigtimedwait, &mask, &si, &zero, 8) == signo, 157, c'syscall(SYS_rt_sigtimedwait, &mask, &si, &zero, 8) == signo')
		check(si.si_code == C.SI_TIMER && si.si_value.sival_int == 0x7788 && si.si_overrun >= 1, 158, c'si.si_code == SI_TIMER && si.si_value.sival_int == 0x7788 && si.si_overrun >= 1')
		check(C.timer_delete(timer) == 0, 159, c'timer_delete(timer) == 0')
		C.puts(c'POSIX TIMER PASS: synchronous')
	}
}

fn ordinary_and_filtered_signals() {
	unsafe {
		mut blocked := posix_timer_mask | (u64(1) << (C.SIGUSR1 - 1))
		check(C.syscall(C.SYS_rt_sigprocmask, C.SIG_BLOCK, &blocked, nil, 8) == 0, 166, c'syscall(SYS_rt_sigprocmask, SIG_BLOCK, &blocked, NULL, 8) == 0')
		check(C.syscall(C.SYS_tgkill, C.getpid(), C.syscall(C.SYS_gettid), C.SIGUSR1) == 0, 168, c'syscall(SYS_tgkill, getpid(), syscall(SYS_gettid), SIGUSR1) == 0')
		mut si := C.siginfo_t{}
		mut timeout := C.timespec{tv_nsec: 40000000}
		start := monotonic_ns()
		check(C.syscall(C.SYS_rt_sigtimedwait, voidptr(&posix_timer_mask), &si, &timeout, 8) == -1 && C.errno == C.EAGAIN, 172, c'syscall(SYS_rt_sigtimedwait, &timer_mask, &si, &timeout, 8) == -1 && errno == EAGAIN')
		elapsed := monotonic_ns() - start
		check(elapsed >= 30000000 && elapsed < 1000000000, 174, c'elapsed >= 30000000 && elapsed < 1000000000')
		mut usr_mask := u64(1) << (C.SIGUSR1 - 1)
		mut zero := C.timespec{}
		check(C.syscall(C.SYS_rt_sigtimedwait, &usr_mask, &si, &zero, 8) == C.SIGUSR1, 177, c'syscall(SYS_rt_sigtimedwait, &usr_mask, &si, &zero, 8) == SIGUSR1')
		check(si.si_code == C.SI_USER, 178, c'si.si_code == SI_USER')
		mut s := C.vpt_thread_state{}
		mut native_thread := C.pthread_t{}
		check(C.pthread_create(&native_thread, nil, C.vpt_timer_receiver, &s) == 0, 182, c'pthread_create(&t, NULL, receiver, &s) == 0')
		for C.__atomic_load_n(&s.tid, 2) == 0 { C.sched_yield() }
		pause_ms(20)
		check(C.syscall(C.SYS_tgkill, C.getpid(), s.tid, 32) == 0, 185, c'syscall(SYS_tgkill, getpid(), s.tid, 32) == 0')
		check(C.pthread_join(native_thread, nil) == 0, 186, c'pthread_join(t, NULL) == 0')
		check(s.result == 32 && s.code == C.SI_USER && s.value == 0 && s.elapsed < 1000000000, 187, c's.result == 32 && s.code == SI_USER && s.value == 0 && s.elapsed < 1000000000')
		C.puts(c'POSIX TIMER PASS: ordinary signals')
	}
}

fn ownership_test() {
	unsafe {
		mut ev := C.vpt_kernel_event{notify: C.SIGEV_THREAD_ID, signo: 32, tid: i32(C.syscall(C.SYS_gettid))}
		mut id := i32(0)
		check(C.syscall(C.SYS_timer_create, C.CLOCK_MONOTONIC, &ev, &id) == 0, 196, c'syscall(SYS_timer_create, CLOCK_MONOTONIC, &ev, &id) == 0')
		mut pipefd := [2]i32{}
		check(C.pipe(&pipefd[0]) == 0, 198, c'pipe(pipefd) == 0')
		child := C.fork()
		check(child >= 0, 200, c'child >= 0')
		if child == 0 {
			C.close(pipefd[1])
			mut now := C.itimerspec{}
			check(C.syscall(C.SYS_timer_gettime, id, &now) == -1 && C.errno == C.EINVAL, 204, c'syscall(SYS_timer_gettime, id, &now) == -1 && errno == EINVAL')
			check(C.syscall(C.SYS_timer_delete, id) == -1 && C.errno == C.EINVAL, 205, c'syscall(SYS_timer_delete, id) == -1 && errno == EINVAL')
			mut byte := u8(0)
			check(C.read(pipefd[0], &byte, 1) == 1, 206, c'read(pipefd[0], &c, 1) == 1')
			C._exit(0)
		}
		C.close(pipefd[0])
		ev.tid = child
		mut foreign := i32(0)
		check(C.syscall(C.SYS_timer_create, C.CLOCK_MONOTONIC, &ev, &foreign) == -1 && C.errno == C.EINVAL, 211, c'syscall(SYS_timer_create, CLOCK_MONOTONIC, &ev, &foreign) == -1 && errno == EINVAL')
		check(C.write(pipefd[1], c'x', 1) == 1 && C.close(pipefd[1]) == 0, 212, c'write(pipefd[1], "x", 1) == 1 && close(pipefd[1]) == 0')
		mut status := i32(0)
		check(C.waitpid(child, &status, 0) == child && C.WIFEXITED(status) && C.WEXITSTATUS(status) == 0, 213, c'waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0')
		check(C.syscall(C.SYS_timer_delete, id) == 0, 214, c'syscall(SYS_timer_delete, id) == 0')
		C.puts(c'POSIX TIMER PASS: ownership')
	}
}

@[export: 'main']
pub fn main_entry() i32 {
	unsafe {
		$if amd64 {
			console := C.open(c'/dev/com1', C.O_WRONLY | C.O_NOCTTY)
			check(console >= 0 && C.dup2(console, 1) == 1 && C.dup2(console, 2) == 2 && C.close(console) == 0, 222, c'console >= 0 && dup2(console, 1) == 1 && dup2(console, 2) == 2 && close(console) == 0')
		}
		C.setvbuf(C.stdout, nil, C._IONBF, 0)
		C.puts(c'POSIX TIMER BEGIN')
		thread_test()
		thread_id_test()
		synchronous_test()
		ordinary_and_filtered_signals()
		ownership_test()
		C.puts(c'POSIX TIMER GUEST: PASS')
		for { C.pause() }
		return 0
	}
}
