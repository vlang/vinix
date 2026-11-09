// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module epollnegativefixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

@[typedef]
struct C.sigset_t {}

@[typedef]
struct C.siginfo_t {}

struct C.sigaction {
mut:
	sa_sigaction fn (i32, &C.siginfo_t, voidptr)
	sa_mask      C.sigset_t
	sa_flags     i32
}

struct Totals {
mut:
	checks   i32
	failures i32
}

struct Targets {
mut:
	epfd   i32
	reader i32
	writer i32
}

struct Guard {
mut:
	before u64
	bytes  [32]u8
	after  u64
}

struct Slabs {
mut:
	sizes   [32]u64
	live    [32]u64
	rows    int
	large   u64
	tainted u64
}

__global (
	calls         &i32
	observed_mask &u64
)

fn C.alloca(uint) voidptr
fn C.syscall(int, ...) int
fn C.__errno_location() &i32
fn C.__atomic_load_n(&i32, i32) i32
fn C.__atomic_store_n(&i32, i32, i32)
fn C.__atomic_fetch_add(&i32, i32, i32) i32
fn C.printf(&char, ...) i32
fn C.snprintf(&char, uint, &char, ...) i32
fn C.sscanf(&char, &char, ...) i32
fn C.strcmp(&char, &char) i32
fn C.fflush(voidptr) i32
fn C.alarm(u32) u32
fn C.pause() i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.pipe2(&i32, i32) i32
fn C.read(i32, voidptr, uint) int
fn C.pread(i32, voidptr, uint, i64) int
fn C.write(i32, voidptr, uint) int
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.dup(i32) i32
fn C.fcntl(i32, i32, ...) i32
fn C.usleep(u32) i32
fn C.kill(i32, i32) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.getuid() u32
fn C.epoll_create1(i32) i32
fn C.epoll_ctl(i32, i32, i32, voidptr) i32
fn C.epoll_wait(i32, voidptr, i32, i32) i32
fn C.epoll_pwait(i32, voidptr, i32, i32, &C.sigset_t) i32
fn C.sigemptyset(&C.sigset_t) i32
fn C.sigaction(i32, &C.sigaction, &C.sigaction) i32

fn bit(signal i32) u64 { return u64(1) << u64(signal - 1) }

fn fatal(stage int) {
	C.printf(c'LINUX EPOLLNEGATIVE FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil })
	C._exit(90)
}

fn handler(_ i32, _ &C.siginfo_t, _ voidptr) {
	unsafe {
		C.syscall(int(C.SYS_rt_sigprocmask), 2, nil, observed_mask, uint(8))
		C.__atomic_fetch_add(calls, 1, 0)
	}
}

fn mask() u64 {
	mut value := u64(0)
	if C.syscall(int(C.SYS_rt_sigprocmask), 2, unsafe { nil }, &value, uint(8)) != 0 { fatal(1) }
	return value
}

fn setmask(value u64) {
	if C.syscall(int(C.SYS_rt_sigprocmask), 2, &value, unsafe { nil }, uint(8)) != 0 { fatal(2) }
}

fn targets() Targets {
	unsafe {
		mut pipes := [2]i32{}
		if C.pipe2(&pipes[0], C.O_NONBLOCK | C.O_CLOEXEC) != 0 { fatal(3) }
		epfd := C.epoll_create1(C.EPOLL_CLOEXEC)
		if epfd < 0 { fatal(4) }
		bytes := &u64(C.alloca(32))
		for i in 0 .. 4 { bytes[i] = 0 }
		(&u32(bytes))[0] = 1
		$if amd64 {
			(&u32(bytes))[1] = 0x55667788
			(&u32(bytes))[2] = 0x11223344
		} $else {
			bytes[1] = 0x1122334455667788
		}
		if C.epoll_ctl(epfd, 1, pipes[0], voidptr(bytes)) != 0 { fatal(5) }
		return Targets{ epfd: epfd, reader: pipes[0], writer: pipes[1] }
	}
}

fn close_targets(t &Targets) {
	C.close(t.epfd)
	C.close(t.reader)
	C.close(t.writer)
}

fn call(api int, epfd i32, output voidptr, timeout i64, temporary &u64) int {
	unsafe {
		match api {
			0 {
				return C.syscall(int(C.SYS_epoll_pwait), epfd, output, 1, timeout, temporary, uint(8))
			}
			1 { return C.epoll_wait(epfd, output, 1, i32(timeout)) }
			2 {
				mut value := C.sigset_t{}
				if C.sigemptyset(&value) != 0 { fatal(6) }
				*&u64(&value) = *temporary
				return C.epoll_pwait(epfd, output, 1, i32(timeout), &value)
			}
			else {
				$if amd64 {
					return C.syscall(int(C.SYS_epoll_wait), epfd, output, 1, timeout)
				} $else {
					fatal(7)
					return -1
				}
			}
		}
	}
}

// Observe a real sleeping parent before providing its I/O or handled signal.
fn observer(parent i32, t &Targets, mode int) {
	unsafe {
		mut path := [96]char{}
		if C.snprintf(&path[0], sizeof(path), c'/proc/%d/stat', parent) <= 0 { C._exit(91) }
		fd := C.open(&path[0], C.O_RDONLY)
		if fd < 0 { C._exit(92) }
		for _ in 0 .. 2000 {
			mut text := [4096]u8{}
			length := C.pread(fd, &text[0], 4095, 0)
			mut end := -1
			for i in 0 .. int(length) { if text[i] == `)` { end = i } }
			if end >= 0 && end + 2 < int(length) && text[end + 2] == `S` {
				C.close(fd)
				if mode == 1 {
					byte := u8(0x51)
					if C.write(t.writer, &byte, 1) != 1 { C._exit(93) }
				} else if C.kill(parent, C.SIGUSR1) != 0 {
					C._exit(94)
				}
				C._exit(0)
			}
			C.usleep(1000)
		}
		C.kill(parent, C.SIGUSR1)
		C._exit(95)
	}
}

fn record(mut total Totals, good bool, api int, value int, mode int, restart bool, stage int, report bool) {
	total.checks++
	if good { return }
	total.failures++
	if report {
		C.printf(c'LINUX EPOLLNEGATIVE MISMATCH: uid=%u api=%d value=%d mode=%d restart=%d stage=%d\n', C.getuid(), api, value, mode, i32(restart), stage)
	}
}

fn probe(t &Targets, api int, value int, mode int, restart bool, report bool) Totals {
	unsafe {
		timeout := [i64(-1), -2, -3, -999, -1000, -1000000, -2147483647, -2147483648, 0, 5]![value]
		original := bit(C.SIGUSR2)
		temporary := bit(C.SIGPIPE)
		setmask(original)
		C.__atomic_store_n(calls, 0, 0)
		*observed_mask = 0
		mut action := C.sigaction{
			sa_sigaction: handler
			sa_flags:     C.SA_SIGINFO | if restart {
				C.SA_RESTART
			} else {
				0
			}
		}
		if C.sigemptyset(&action.sa_mask) != 0 || C.sigaction(C.SIGUSR1, &action, nil) != 0 {
			fatal(8)
		}
		flags := C.fcntl(t.reader, C.F_GETFL)
		g := &Guard(C.alloca(sizeof(Guard)))
		*g = Guard{ before: 0xabcdef0123456789, after: 0x9876543210fedcba }
		for i in 0 .. 32 { g.bytes[i] = 0xa5 }
		mut child := i32(0)
		if mode == 0 {
			byte := u8(0x51)
			if C.write(t.writer, &byte, 1) != 1 { fatal(9) }
		} else if mode in [1, 2]! {
			parent := i32(C.syscall(int(C.SYS_getpid)))
			child = C.fork()
			if child < 0 { fatal(10) }
			if child == 0 { observer(parent, t, mode) }
		}
		err := C.__errno_location()
		*err = 0
		ret := call(api, if mode == 4 { -1 } else { t.epfd }, voidptr(&g.bytes[0]), timeout, &temporary)
		code := *err
		seen := C.__atomic_load_n(calls, 0)
		handled_mask := *observed_mask
		after_mask := mask()
		mut byte := u8(0)
		read_count := C.read(t.reader, &byte, 1)
		read_error := *err
		mut total := Totals{}
		wanted := if mode == 2 || mode == 4 {
			-1
		} else if mode == 3 {
			0
		} else {
			1
		}
		wanted_errno := if mode == 2 {
			C.EINTR
		} else if mode == 4 {
			C.EBADF
		} else {
			0
		}
		record(mut total, ret == wanted && code == wanted_errno, api, value, mode, restart, 1, report)
		mut good := g.before == 0xabcdef0123456789 && g.after == 0x9876543210fedcba
		if mode in [0, 1]! {
			mut offset := 8
			mut length := 16
			$if amd64 {
				offset = 4
				length = 12
			}
			good = good && *&u32(&g.bytes[0]) == 1 && *&u64(&g.bytes[offset]) == 0x1122334455667788
			for i in length .. 32 { if g.bytes[i] != 0xa5 { good = false } }
		} else {
			for i in 0 .. 32 { if g.bytes[i] != 0xa5 { good = false } }
		}
		record(mut total, good, api, value, mode, restart, 2, report)
		record(mut total, seen == if mode == 2 { 1 } else { 0 }, api, value, mode, restart, 3, report)
		record(mut total, after_mask == original, api, value, mode, restart, 4, report)
		expected_mask := if mode == 2 {
			(if api in [0, 2]! { temporary } else { original }) | bit(C.SIGUSR1)
		} else {
			0
		}
		record(mut total, handled_mask == expected_mask, api, value, mode, restart, 5, report)
		record(mut total, if mode in [0, 1]! {
			read_count == 1 && byte == 0x51
		} else {
			read_count == -1 && read_error == C.EAGAIN
		}, api, value, mode, restart, 6, report)
		mut status := i32(0)
		if child != 0 {
			for {
				waited := C.waitpid(child, &status, 0)
				if waited == child { break }
				if waited != -1 || *err != C.EINTR { fatal(11) }
			}
		}
		record(mut total, status == 0, api, value, mode, restart, 7, report)
		left := C.read(t.reader, &byte, 1)
		left_error := *err
		for C.read(t.reader, &byte, 1) > 0 {
		}
		mut output := [4]u64{}
		record(mut total, left == -1 && left_error == C.EAGAIN && C.epoll_wait(t.epfd, voidptr(&output[0]), 1, 0) == 0 && C.fcntl(t.reader, C.F_GETFL) == flags, api, value, mode, restart, 8, report)
		if report {
			C.printf(c'LINUX EPOLLNEGATIVE CASE: uid=%u api=%d value=%d mode=%d restart=%d checks=%d failures=%d\n', C.getuid(), api, value, mode, i32(restart), total.checks, total.failures)
		}
		return total
	}
}

fn snapshot(fd i32, destination &Slabs) bool {
	unsafe {
		mut counts := &Slabs(destination)
		*counts = Slabs{}
		mut data := [4096]char{}
		length := C.pread(fd, &data[0], 4095, 0)
		if length <= 0 || length >= 4096 { return false }
		data[int(length)] = 0
		mut position := 0
		mut large := false
		mut guarded := false
		for position < int(length) {
			mut size := u64(0)
			mut duplicate := u64(0)
			mut live := u64(0)
			mut pages := u64(0)
			if C.sscanf(&data[position], c'size-%lu %lu %lu %lu', &size, &duplicate, &live, &pages) == 4 {
				if counts.rows >= 32 || size != duplicate { return false }
				counts.sizes[counts.rows] = size
				counts.live[counts.rows] = live
				counts.rows++
			} else if C.sscanf(&data[position], c'large - - %lu', &counts.large) == 1 {
				large = true
			} else if C.sscanf(&data[position], c'# written after free %lu', &counts.tainted) == 1 {
				guarded = true
			}
			for position < int(length) && data[position] != char(10) { position++ }
			position++
		}
		return counts.rows > 0 && large && guarded
	}
}

fn storage_cycle(t &Targets, apis int) int {
	unsafe {
		mut failures := 0
		for api in 0 .. apis {
			for value in 0 .. 8 {
				failures += int(probe(t, api, value, 0, false, false).failures)
				failures += int(probe(t, api, value, 4, false, false).failures)
			}
		}
		alias := C.dup(t.epfd)
		if alias < 0 { fatal(12) }
		peer := &Targets(C.alloca(sizeof(Targets)))
		*peer = *t
		peer.epfd = alias
		failures += int(probe(peer, 0, 7, 0, false, false).failures)
		if C.close(alias) != 0 { fatal(13) }
		return failures
	}
}

fn storage(t &Targets, apis int) bool {
	unsafe {
		fd := C.open(c'/proc/slabinfo', C.O_RDONLY)
		if fd < 0 { fatal(14) }
		for _ in 0 .. 16 { if storage_cycle(t, apis) != 0 { fatal(15) } }
		C.usleep(13_000_000)
		before := &Slabs(C.alloca(sizeof(Slabs)))
		after := &Slabs(C.alloca(sizeof(Slabs)))
		if !snapshot(fd, before) { fatal(16) }
		mut failures := 0
		for _ in 0 .. 200 { failures += storage_cycle(t, apis) }
		C.usleep(13_000_000)
		if !snapshot(fd, after) { fatal(17) }
		mut good := failures == 0 && before.rows == after.rows && before.large == after.large && before.tainted == 0 && after.tainted == 0
		for row in 0 .. before.rows {
			if before.sizes[row] != after.sizes[row] || before.live[row] != after.live[row] {
				good = false
			}
			C.printf(c'LINUX EPOLLNEGATIVE SLAB: uid=%u size=%lu live=%lu/%lu\n', C.getuid(), before.sizes[row], before.live[row], after.live[row])
		}
		C.printf(c'LINUX EPOLLNEGATIVE STORAGE: uid=%u cycles=200 big_pages=%lu/%lu tainted=%lu/%lu %s\n', C.getuid(), before.large, after.large, before.tainted, after.tainted, if good {
			&char(c'PASS')
		} else {
			&char(c'FAIL')
		})
		C.close(fd)
		return good
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		C.alarm(600)
		reference := argc == 2 && C.strcmp(argv[1], c'--reference') == 0
		mut apis := 3
		$if amd64 {
			apis = 4
		}
		mut total := Totals{}
		for ordinary in [false, true]! {
			mut pipes := [2]i32{}
			if C.pipe2(&pipes[0], 0) != 0 { fatal(18) }
			C.fflush(nil)
			child := C.fork()
			if child < 0 { fatal(19) }
			if child == 0 {
				C.close(pipes[0])
				if ordinary && (C.setgid(2000) != 0 || C.setuid(1000) != 0) { fatal(20) }
				calls = &i32(C.alloca(sizeof(i32)))
				observed_mask = &u64(C.alloca(sizeof(u64)))
				t := &Targets(C.alloca(sizeof(Targets)))
				*t = targets()
				initial := mask()
				mut sum := Totals{}
				for api in 0 .. apis {
					for value in 0 .. 10 {
						for restart in [false, true]! {
							for mode in if value < 8 { [0, 1, 2, 4]! } else { [3, -1, -1, -1]! } {
								if mode < 0 { continue }
								result := probe(t, api, value, mode, restart, true)
								sum.checks += result.checks
								sum.failures += result.failures
							}
						}
					}
				}
				if !reference && sum.failures == 0 && !storage(t, apis) { sum.failures++ }
				if reference {
					C.printf(c'LINUX EPOLLNEGATIVE STORAGE: uid=%u SKIP reference\n', C.getuid())
				}
				setmask(initial)
				close_targets(t)
				if C.write(pipes[1], &sum, sizeof(sum)) != sizeof(sum) { fatal(21) }
				C.fflush(nil)
				C._exit(0)
			}
			C.close(pipes[1])
			mut sum := Totals{}
			if C.read(pipes[0], &sum, sizeof(sum)) != sizeof(sum) { fatal(22) }
			C.close(pipes[0])
			mut status := i32(0)
			if C.waitpid(child, &status, 0) != child || status != 0 { fatal(23) }
			total.checks += sum.checks
			total.failures += sum.failures
		}
		C.printf(c'LINUX EPOLLNEGATIVE SUMMARY: checks=%d failures=%d\n', total.checks, total.failures)
		C.printf(c'LINUX EPOLLNEGATIVE: %s\n', if total.failures == 0 {
			&char(c'PASS')
		} else {
			&char(c'FAIL')
		})
		C.fflush(nil)
		C.alarm(0)
		for { C.pause() }
	}
	return 0
}
