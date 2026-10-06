// SPDX-License-Identifier: GPL-2.0-or-later
// Independent Linux clock-control fixture; original predicates and tags retained.
@[translated]
module clockfixture

#include <clock-fixture-native-abi.h>

@[typedef]
struct C.FILE {}
@[typedef]
struct C.timer_t {}
@[typedef]
struct C.vcc_native_ull {}
struct C.timespec { mut: tv_sec i64 tv_nsec i64 }
struct C.timeval { mut: tv_sec i64 tv_usec i64 }
struct C.timex { mut: modes u32 offset isize freq isize status i32 }
struct C.itimerspec { mut: it_interval C.timespec it_value C.timespec }
struct C.pollfd { mut: fd i32 events i16 revents i16 }
struct C.sigevent { mut: sigev_notify i32 }
@[c_extern]
__global C.stdout &C.FILE
@[c_extern]
__global C.errno i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.setvbuf(&C.FILE, &char, i32, usize) i32
fn C.open(&char, i32, ...) i32
fn C.write(i32, voidptr, usize) isize
fn C.read(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.strlen(&char) usize
fn C.memset(voidptr, i32, usize) voidptr
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.clock_gettime(i32, &C.timespec) i32
fn C.clock_settime(i32, &C.timespec) i32
fn C.settimeofday(&C.timeval, voidptr) i32
fn C.gettimeofday(&C.timeval, voidptr) i32
fn C.syscall(isize, ...) isize
fn C.adjtimex(&C.timex) i32
fn C.clock_adjtime(i32, &C.timex) i32
fn C.fork() i32
fn C.setuid(u32) i32
fn C._exit(i32)
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) bool
fn C.WEXITSTATUS(i32) i32
fn C.timerfd_create(i32, i32) i32
fn C.timerfd_settime(i32, i32, &C.itimerspec, &C.itimerspec) i32
fn C.timerfd_gettime(i32, &C.itimerspec) i32
fn C.poll(&C.pollfd, usize, i32) i32
fn C.timer_create(i32, &C.sigevent, &C.timer_t) i32
fn C.timer_settime(C.timer_t, i32, &C.itimerspec, &C.itimerspec) i32
fn C.timer_gettime(C.timer_t, &C.itimerspec) i32
fn C.timer_delete(C.timer_t) i32
fn C.pipe(&i32) i32
fn C.clock_nanosleep(i32, i32, &C.timespec, &C.timespec) i32
fn C.nanosleep(&C.timespec, &C.timespec) i32
fn C.pause() i32

fn check(ok bool, line i32, expression &char) bool {
	if !ok { unsafe { C.printf(c'CLOCK CONTROL FAIL line %d: %s errno=%d\n', line, expression, C.errno) } }
	return ok
}

fn set_level(value &char) i32 {
	unsafe {
		fd := C.open(c'/proc/sys/kernel/securelevel', C.O_WRONLY)
		if fd < 0 { return -1 }
		result := C.write(fd, value, C.strlen(value))
		C.close(fd)
		return if result == isize(C.strlen(value)) { i32(0) } else { i32(-1) }
	}
}

fn tests() i32 {
	unsafe {
		mut mono := C.timespec{}
		mut after := C.timespec{}
		mut wall := C.timespec{tv_sec: 1800000000, tv_nsec: 123000000}
		if !check(C.clock_gettime(C.CLOCK_MONOTONIC, &mono) == 0, 35, c'clock_gettime(CLOCK_MONOTONIC, &mono) == 0') { return 1 }
		if !check(mono.tv_sec >= 0 && mono.tv_sec < 300, 36, c'mono.tv_sec >= 0 && mono.tv_sec < 300') { return 1 }
		if !check(C.clock_settime(C.CLOCK_REALTIME, &wall) == 0, 37, c'clock_settime(CLOCK_REALTIME, &wall) == 0') { return 1 }
		if !check(C.clock_gettime(C.CLOCK_REALTIME, &after) == 0, 38, c'clock_gettime(CLOCK_REALTIME, &after) == 0') { return 1 }
		if !check(after.tv_sec == wall.tv_sec, 39, c'after.tv_sec == wall.tv_sec') { return 1 }
		if !check(C.clock_gettime(C.CLOCK_MONOTONIC, &after) == 0, 40, c'clock_gettime(CLOCK_MONOTONIC, &after) == 0') { return 1 }
		if !check(after.tv_sec >= mono.tv_sec && after.tv_sec < mono.tv_sec + 2, 41, c'after.tv_sec >= mono.tv_sec && after.tv_sec < mono.tv_sec + 2') { return 1 }
		mut tv := C.timeval{tv_sec: 1800000001, tv_usec: 500000}
		if !check(C.settimeofday(&tv, nil) == 0, 43, c'settimeofday(&tv, NULL) == 0') { return 1 }
		if !check(C.gettimeofday(&tv, nil) == 0 && tv.tv_sec == 1800000001, 44, c'gettimeofday(&tv, NULL) == 0 && tv.tv_sec == 1800000001') { return 1 }
		C.puts(c'CLOCK CONTROL PASS: wall steps preserve uptime')

		wall.tv_nsec = 1000000000
		if !check(C.clock_settime(C.CLOCK_REALTIME, &wall) == -1 && C.errno == C.EINVAL, 48, c'clock_settime(CLOCK_REALTIME, &wall) == -1 && errno == EINVAL') { return 1 }
		if !check(C.syscall(C.SYS_clock_settime, C.CLOCK_REALTIME, voidptr(1)) == -1 && C.errno == C.EFAULT, 49, c'syscall(SYS_clock_settime, CLOCK_REALTIME, (void *)1) == -1 && errno == EFAULT') { return 1 }
		wall.tv_nsec = 0
		if !check(C.clock_settime(C.CLOCK_MONOTONIC, &wall) == -1 && C.errno == C.EINVAL, 51, c'clock_settime(CLOCK_MONOTONIC, &wall) == -1 && errno == EINVAL') { return 1 }
		mut tx := C.timex{modes: C.ADJ_FREQUENCY, freq: 500 * 65536}
		if !check(C.adjtimex(&tx) == C.TIME_ERROR && tx.freq == 500 * 65536, 53, c'adjtimex(&tx) == TIME_ERROR && tx.freq == 500 * 65536') { return 1 }
		if !check(tx.status == C.STA_UNSYNC, 54, c'tx.status == STA_UNSYNC') { return 1 }
		C.memset(&tx, 0, sizeof(C.timex))
		if !check(C.clock_adjtime(C.CLOCK_REALTIME, &tx) == C.TIME_ERROR && tx.freq == 500 * 65536, 56, c'clock_adjtime(CLOCK_REALTIME, &tx) == TIME_ERROR && tx.freq == 500 * 65536') { return 1 }
		tx.modes = C.ADJ_FREQUENCY
		tx.freq++
		if !check(C.adjtimex(&tx) == -1 && C.errno == C.EINVAL, 58, c'adjtimex(&tx) == -1 && errno == EINVAL') { return 1 }
		tx.modes = C.ADJ_OFFSET
		if !check(C.adjtimex(&tx) == -1 && C.errno == C.EOPNOTSUPP, 60, c'adjtimex(&tx) == -1 && errno == EOPNOTSUPP') { return 1 }
		C.memset(&tx, 0, sizeof(C.timex))
		tx.modes = C.ADJ_OFFSET_SINGLESHOT
		tx.offset = 2000000
		if !check(C.adjtimex(&tx) == C.TIME_ERROR, 63, c'adjtimex(&tx) == TIME_ERROR') { return 1 }
		C.memset(&tx, 0, sizeof(C.timex))
		tx.modes = C.ADJ_OFFSET_SS_READ
		if !check(C.adjtimex(&tx) == C.TIME_ERROR && tx.offset > 1000000 && tx.offset <= 2000000, 65, c'adjtimex(&tx) == TIME_ERROR && tx.offset > 1000000 && tx.offset <= 2000000') { return 1 }
		C.memset(&tx, 0, sizeof(C.timex))
		tx.modes = C.ADJ_OFFSET_SINGLESHOT
		if !check(C.adjtimex(&tx) == C.TIME_ERROR, 67, c'adjtimex(&tx) == TIME_ERROR') { return 1 }
		C.memset(&tx, 0, sizeof(C.timex))
		tx.modes = C.ADJ_FREQUENCY
		if !check(C.adjtimex(&tx) == C.TIME_ERROR, 69, c'adjtimex(&tx) == TIME_ERROR') { return 1 }
		C.puts(c'CLOCK CONTROL PASS: discipline ABI validates modes and bounds')

		mut child := C.fork()
		if !check(child >= 0, 73, c'child >= 0') { return 1 }
		if child == 0 {
			if C.setuid(1000) != 0 { C._exit(2) }
			if C.clock_settime(C.CLOCK_REALTIME, &wall) != -1 || C.errno != C.EPERM { C._exit(3) }
			mut request := C.timex{modes: C.ADJ_FREQUENCY}
			if C.adjtimex(&request) != -1 || C.errno != C.EPERM { C._exit(4) }
			C.memset(&request, 0, sizeof(C.timex))
			if C.adjtimex(&request) != C.TIME_ERROR { C._exit(5) }
			C._exit(0)
		}
		mut status := i32(0)
		if !check(C.waitpid(child, &status, 0) == child && C.WIFEXITED(status) && C.WEXITSTATUS(status) == 0, 84, c'waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0') { return 1 }
		if !check(set_level(c'2\n') == 0, 85, c'set_level("2\\n") == 0') { return 1 }
		wall.tv_sec = 1700000000
		if !check(C.clock_settime(C.CLOCK_REALTIME, &wall) == -1 && C.errno == C.EPERM, 87, c'clock_settime(CLOCK_REALTIME, &wall) == -1 && errno == EPERM') { return 1 }
		wall.tv_sec = 1900000000
		if !check(C.clock_settime(C.CLOCK_REALTIME, &wall) == 0, 89, c'clock_settime(CLOCK_REALTIME, &wall) == 0') { return 1 }
		if !check(set_level(c'0\n') == 0, 90, c'set_level("0\\n") == 0') { return 1 }
		C.puts(c'CLOCK CONTROL PASS: privilege and securelevel guard changes')

		fd := C.timerfd_create(C.CLOCK_REALTIME, C.TFD_NONBLOCK)
		if !check(fd >= 0, 94, c'fd >= 0') { return 1 }
		wall.tv_sec = 1800000000
		if !check(C.clock_settime(C.CLOCK_REALTIME, &wall) == 0, 96, c'clock_settime(CLOCK_REALTIME, &wall) == 0') { return 1 }
		mut deadline := C.itimerspec{it_value: C.timespec{tv_sec: 1800000100, tv_nsec: 0}}
		if !check(C.timerfd_settime(fd, C.TFD_TIMER_ABSTIME, &deadline, nil) == 0, 98, c'timerfd_settime(fd, TFD_TIMER_ABSTIME, &deadline, NULL) == 0') { return 1 }
		wall.tv_sec = 1800000200
		if !check(C.clock_settime(C.CLOCK_REALTIME, &wall) == 0, 100, c'clock_settime(CLOCK_REALTIME, &wall) == 0') { return 1 }
		mut pfd := C.pollfd{fd: fd, events: C.POLLIN}
		if !check(C.poll(&pfd, 1, 500) == 1, 102, c'poll(&pfd, 1, 500) == 1') { return 1 }
		mut count := C.vcc_native_ull{}
		mut count_bits := u64(0)
		count_read := C.read(fd, &count, sizeof(C.vcc_native_ull))
		if count_read == isize(sizeof(C.vcc_native_ull)) { C.memcpy(&count_bits, &count, sizeof(C.vcc_native_ull)) }
		if !check(count_read == isize(sizeof(C.vcc_native_ull)) && count_bits == 1, 104, c'read(fd, &count, sizeof(count)) == sizeof(count) && count == 1') { return 1 }
		deadline.it_value.tv_sec = 1800000210
		if !check(C.timerfd_settime(fd, C.TFD_TIMER_ABSTIME, &deadline, nil) == 0, 106, c'timerfd_settime(fd, TFD_TIMER_ABSTIME, &deadline, NULL) == 0') { return 1 }
		wall.tv_sec = 1800000100
		if !check(C.clock_settime(C.CLOCK_REALTIME, &wall) == 0, 108, c'clock_settime(CLOCK_REALTIME, &wall) == 0') { return 1 }
		mut remaining := C.itimerspec{}
		if !check(C.timerfd_gettime(fd, &remaining) == 0 && remaining.it_value.tv_sec >= 109, 110, c'timerfd_gettime(fd, &remaining) == 0 && remaining.it_value.tv_sec >= 109') { return 1 }
		if !check(C.timerfd_settime(fd, C.TFD_TIMER_ABSTIME | C.TFD_TIMER_CANCEL_ON_SET, &deadline, nil) == 0, 111, c'timerfd_settime(fd, TFD_TIMER_ABSTIME | TFD_TIMER_CANCEL_ON_SET, &deadline, NULL) == 0') { return 1 }
		wall.tv_sec++
		if !check(C.clock_settime(C.CLOCK_REALTIME, &wall) == 0, 113, c'clock_settime(CLOCK_REALTIME, &wall) == 0') { return 1 }
		if !check(C.read(fd, &count, sizeof(C.vcc_native_ull)) == -1 && C.errno == C.ECANCELED, 114, c'read(fd, &count, sizeof(count)) == -1 && errno == ECANCELED') { return 1 }
		if !check(C.close(fd) == 0, 115, c'close(fd) == 0') { return 1 }

		mut timer := C.timer_t{}
		mut ev := C.sigevent{sigev_notify: C.SIGEV_NONE}
		if !check(C.timer_create(C.CLOCK_REALTIME, &ev, &timer) == 0, 119, c'timer_create(CLOCK_REALTIME, &ev, &timer) == 0') { return 1 }
		if !check(C.timer_settime(timer, C.TIMER_ABSTIME, &deadline, nil) == 0, 120, c'timer_settime(timer, TIMER_ABSTIME, &deadline, NULL) == 0') { return 1 }
		wall.tv_sec -= 100
		if !check(C.clock_settime(C.CLOCK_REALTIME, &wall) == 0, 122, c'clock_settime(CLOCK_REALTIME, &wall) == 0') { return 1 }
		if !check(C.timer_gettime(timer, &remaining) == 0 && remaining.it_value.tv_sec >= 200, 123, c'timer_gettime(timer, &remaining) == 0 && remaining.it_value.tv_sec >= 200') { return 1 }
		wall.tv_sec = 1800000300
		if !check(C.clock_settime(C.CLOCK_REALTIME, &wall) == 0, 125, c'clock_settime(CLOCK_REALTIME, &wall) == 0') { return 1 }
		if !check(C.timer_gettime(timer, &remaining) == 0 && remaining.it_value.tv_sec == 0, 126, c'timer_gettime(timer, &remaining) == 0 && remaining.it_value.tv_sec == 0') { return 1 }
		if !check(C.timer_delete(timer) == 0, 127, c'timer_delete(timer) == 0') { return 1 }

		mut ready := [2]i32{}
		if !check(C.pipe(&ready[0]) == 0, 130, c'pipe(ready) == 0') { return 1 }
		child = C.fork()
		if !check(child >= 0, 132, c'child >= 0') { return 1 }
		if child == 0 {
			C.close(ready[0])
			mut until := C.timespec{tv_sec: 1800003900, tv_nsec: 0}
			if C.write(ready[1], c'x', 1) != 1 { C._exit(10) }
			C._exit(if C.clock_nanosleep(C.CLOCK_REALTIME, C.TIMER_ABSTIME, &until, nil) == 0 { i32(0) } else { i32(11) })
		}
		C.close(ready[1])
		mut byte := u8(0)
		if !check(C.read(ready[0], &byte, 1) == 1, 141, c'read(ready[0], &byte, 1) == 1') { return 1 }
		C.close(ready[0])
		mut settle := C.timespec{tv_sec: 0, tv_nsec: 50000000}
		if !check(C.nanosleep(&settle, nil) == 0, 144, c'nanosleep(&settle, NULL) == 0') { return 1 }
		wall.tv_sec = 1800004000
		if !check(C.clock_settime(C.CLOCK_REALTIME, &wall) == 0, 146, c'clock_settime(CLOCK_REALTIME, &wall) == 0') { return 1 }
		mut waited := i32(0)
		for i := i32(0); i < 100 && waited == 0; i++ {
			waited = C.waitpid(child, &status, C.WNOHANG)
			if waited == 0 { C.nanosleep(&settle, nil) }
		}
		if !check(waited == child && C.WIFEXITED(status) && C.WEXITSTATUS(status) == 0, 152, c'waited == child && WIFEXITED(status) && WEXITSTATUS(status) == 0') { return 1 }
		C.puts(c'CLOCK CONTROL PASS: realtime steps adjust sleeps and absolute timers')
		return 0
	}
}

@[export: 'main']
pub fn main_entry() i32 {
	unsafe {
		C.setvbuf(C.stdout, nil, C._IONBF, 0)
		result := tests()
		C.puts(if result != 0 { c'VINIX CLOCK CONTROL: FAIL' } else { c'VINIX CLOCK CONTROL: PASS' })
		for { C.pause() }
		return 0
	}
}
