// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module epollwordsfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

@[typedef]
struct C.sigset_t {}

struct Totals {
mut:
	checks   i32
	failures i32
}

struct Targets {
mut:
	output   &Guard
	empty    i32
	ready    i32
	alias    i32
	ordinary i32
	path     i32
	reader   i32
	writer   i32
}

struct Guard {
mut:
	before u64
	bytes  [32]u8
	after  u64
}

struct Stamp {
mut:
	seconds i64
	nanos   i64
}

struct Slabs {
mut:
	sizes   [32]u64
	live    [32]u64
	rows    int
	large   u64
	tainted u64
}

fn C.alloca(uint) voidptr
fn C.syscall(int, ...) int
fn C.__errno_location() &i32
fn C.printf(&char, ...) i32
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
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.getuid() u32
fn C.epoll_create1(i32) i32
fn C.epoll_ctl(i32, i32, i32, voidptr) i32
fn C.epoll_wait(i32, voidptr, i32, i32) i32
fn C.epoll_pwait(i32, voidptr, i32, i32, &C.sigset_t) i32
fn C.sigemptyset(&C.sigset_t) i32
fn C.mmap(voidptr, uint, i32, i32, i32, i64) voidptr
fn C.munmap(voidptr, uint) i32

@[typedef]
struct C.siginfo_t {}

struct C.sigaction {
mut:
	sa_sigaction fn (i32, &C.siginfo_t, voidptr)
	sa_mask      C.sigset_t
	sa_flags     i32
}

__global (
	calls         &i32
	observed_mask &u64
)

fn C.__atomic_load_n(&i32, i32) i32
fn C.__atomic_store_n(&i32, i32, i32)
fn C.__atomic_fetch_add(&i32, i32, i32) i32
fn C.sigaction(i32, &C.sigaction, &C.sigaction) i32
fn C.snprintf(&char, uint, &char, ...) i32
fn C.kill(i32, i32) i32

fn fatal(stage int) {
	C.printf(c'LINUX EPOLLWORDS FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil })
	C._exit(90)
}

fn mask() u64 {
	mut value := u64(0)
	if C.syscall(int(C.SYS_rt_sigprocmask), 2, unsafe { nil }, &value, uint(8)) != 0 { fatal(1) }
	return value
}

fn setmask(value u64) {
	if C.syscall(int(C.SYS_rt_sigprocmask), 2, &value, unsafe { nil }, uint(8)) != 0 { fatal(2) }
}

fn limit() int {
	$if amd64 {
		return 2147483647 / 12
	} $else {
		return 2147483647 / 16
	}
}

fn count(index int) int {
	return match index {
		0 { -2147483648 }
		1 { -1 }
		2 { 0 }
		3 { 1 }
		4 { 2 }
		5 { limit() }
		6 { limit() + 1 }
		else { 2147483647 }
	}
}

fn word(low int, pattern int) u64 {
	base := u64(u32(low))
	return match pattern {
		0 { u64(i64(i32(low))) }
		1 { base }
		2 { (u64(1) << 32) | base }
		3 { (u64(0x7fffffff) << 32) | base }
		4 { (u64(0x80000000) << 32) | base }
		else { (u64(0xffffffff) << 32) | base }
	}
}

fn rearm(t &Targets) {
	unsafe {
		bytes := &u64(C.alloca(32))
		for i in 0 .. 4 { bytes[i] = 0 }
		(&u32(bytes))[0] = 0x40000001
		$if amd64 {
			(&u32(bytes))[1] = 0x55667788
			(&u32(bytes))[2] = 0x11223344
		} $else {
			bytes[1] = 0x1122334455667788
		}
		if C.epoll_ctl(t.ready, 3, t.reader, voidptr(bytes)) != 0 { fatal(3) }
	}
}

fn targets() Targets {
	unsafe {
		mut pipes := [2]i32{}
		if C.pipe2(&pipes[0], C.O_NONBLOCK | C.O_CLOEXEC) != 0 { fatal(4) }
		empty := C.epoll_create1(C.EPOLL_CLOEXEC)
		ready := C.epoll_create1(C.EPOLL_CLOEXEC)
		ordinary := C.open(c'/dev/null', C.O_RDONLY)
		path := C.open(c'/dev/null', C.O_PATH)
		alias := C.dup(ready)
		if empty < 0 || ready < 0 || ordinary < 0 || path < 0 || alias < 0 { fatal(5) }
		// Leave room for the declared INT_MAX-byte range below the user limit.
		output := C.mmap(voidptr(u64(0x40000000)), 16384, C.PROT_READ | C.PROT_WRITE,
			C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if u64(output) > 0x100000000 { fatal(22) }
		mut event := [4]u64{}
		(&u32(&event[0]))[0] = 1
		if C.epoll_ctl(ready, 1, pipes[0], voidptr(&event[0])) != 0 { fatal(6) }
		return Targets{ output: &Guard(output), empty: empty, ready: ready, alias: alias, ordinary: ordinary, path: path, reader: pipes[0], writer: pipes[1] }
	}
}

fn close_targets(t &Targets) {
	C.close(t.empty)
	C.close(t.ready)
	C.close(t.alias)
	C.close(t.ordinary)
	C.close(t.path)
	C.close(t.reader)
	C.close(t.writer)
	C.munmap(t.output, 16384)
}

fn call(api int, epfd i32, output voidptr, maximum int, stamp voidptr, temporary &u64, kind int, pattern int) int {
	fd_word := if kind == 0 { word(int(epfd), pattern) } else { u64(i64(epfd)) }
	max_word := if kind == 1 { word(maximum, pattern) } else { u64(i64(maximum)) }
	timeout_word := if kind == 2 { word(0, pattern) } else { u64(0) }
	size_word := if kind == 3 { word(8, pattern) } else { u64(8) }
	unsafe {
		if api == 0 {
			return C.syscall(int(C.SYS_epoll_pwait), fd_word, output, max_word, timeout_word, temporary, size_word)
		}
		if api == 1 {
			return C.syscall(int(C.SYS_epoll_pwait2), fd_word, output, max_word, stamp, temporary, size_word)
		}
		$if amd64 {
			return C.syscall(int(C.SYS_epoll_wait), fd_word, output, max_word, timeout_word)
		} $else {
			fatal(8)
			return -1
		}
	}
}

fn record(mut sum Totals, good bool, api int, value int, fd int, kind int, pattern int, stage int, report bool) {
	sum.checks++
	if good { return }
	sum.failures++
	if report {
		C.printf(c'LINUX EPOLLWORDS MISMATCH: uid=%u api=%d value=%d fd=%d kind=%d pattern=%d stage=%d\n', C.getuid(), api, value, fd, kind, pattern, stage)
	}
}

fn event_ok(g &Guard, ready bool) bool {
	unsafe {
		if g.before != 0xabcdef0123456789 || g.after != 0x9876543210fedcba { return false }
		mut length := 0
		if ready {
			mut offset := 8
			length = 16
			$if amd64 {
				offset = 4
				length = 12
			}
			if *&u32(&g.bytes[0]) != 1 || *&u64(&g.bytes[offset]) != 0x1122334455667788 {
				return false
			}
		}
		for i in length .. 32 { if g.bytes[i] != 0xa5 { return false } }
		return true
	}
}

fn guard(g &Guard) {
	unsafe {
		mut destination := &Guard(g)
		*destination = Guard{ before: 0xabcdef0123456789, after: 0x9876543210fedcba }
		for i in 0 .. 32 { destination.bytes[i] = 0xa5 }
	}
}

fn probe(t &Targets, api int, value int, slot int, kind int, pattern int, report bool) Totals {
	unsafe {
		rearm(t)
		byte := u8(0x51)
		if C.write(t.writer, &byte, 1) != 1 { fatal(9) }
		flags := C.fcntl(t.reader, C.F_GETFL)
		g := t.output
		guard(g)
		follow := &Guard(C.alloca(sizeof(Guard)))
		guard(follow)
		fd := [t.empty, t.ready, t.alias, i32(-1), t.ordinary, t.path]![slot]
		maximum := if kind == 1 { count(value) } else { 1 }
		original := u64(1) << 11
		temporary := u64(1) << 12
		setmask(original)
		ts := &Stamp(C.alloca(sizeof(Stamp)))
		*ts = Stamp{}
		err := C.__errno_location()
		*err = 0
		ret := call(api, fd, voidptr(&g.bytes[0]), maximum, ts, &temporary, kind, pattern)
		code := *err
		after := mask()
		refused := maximum <= 0 || maximum > limit() || (kind == 3 && pattern >= 2)
		wanted_errno := if refused {
			C.EINVAL
		} else if slot in [3, 5]! {
			C.EBADF
		} else if slot == 4 {
			C.EINVAL
		} else {
			0
		}
		delivered := wanted_errno == 0 && slot in [1, 2]!
		wanted := if wanted_errno != 0 {
			-1
		} else if delivered {
			1
		} else {
			0
		}
		mut sum := Totals{}
		record(mut sum, ret == wanted && code == wanted_errno, api, value, slot, kind, pattern, 1, report)
		record(mut sum, event_ok(g, delivered), api, value, slot, kind, pattern, 2, report)
		record(mut sum, after == original, api, value, slot, kind, pattern, 3, report)
		record(mut sum, temporary == u64(1) << 12 && ts.seconds == 0 && ts.nanos == 0, api, value, slot, kind, pattern, 4, report)
		next := C.epoll_wait(t.ready, voidptr(&follow.bytes[0]), 1, 0)
		record(mut sum, next == (if delivered { 0 } else { 1 }) && event_ok(follow, !delivered), api, value, slot, kind, pattern, 5, report)
		mut actual := u8(0)
		read_count := C.read(t.reader, &actual, 1)
		empty_count := C.read(t.reader, &actual, 1)
		empty_error := *err
		record(mut sum, read_count == 1 && actual == byte && empty_count == -1 && empty_error == C.EAGAIN && C.fcntl(t.reader, C.F_GETFL) == flags, api, value, slot, kind, pattern, 6, report)
		if report {
			C.printf(c'LINUX EPOLLWORDS CASE: uid=%u api=%d value=%d fd=%d kind=%d pattern=%d checks=%d failures=%d\n', C.getuid(), api, value, slot, kind, pattern, sum.checks, sum.failures)
		}
		return sum
	}
}

fn storage_cycle(t &Targets, apis int) int {
	unsafe {
		peer := &Targets(C.alloca(sizeof(Targets)))
		*peer = *t
		peer.alias = C.dup(t.ready)
		if peer.alias < 0 { fatal(10) }
		mut failures := 0
		for api in 0 .. apis {
			for kind in [0, 1, 3]! {
				if api == 2 && kind == 3 { continue }
				for pattern in [2, 4]! {
					for slot in [0, 1, 2, 3]! {
						failures += int(probe(peer, api, if kind == 1 { 3 } else { 0 }, slot, kind, pattern, false).failures)
					}
				}
			}
		}
		if C.close(peer.alias) != 0 { fatal(11) }
		return failures
	}
}

fn storage(t &Targets, apis int) bool {
	unsafe {
		fd := C.open(c'/proc/slabinfo', C.O_RDONLY)
		if fd < 0 { fatal(12) }
		for _ in 0 .. 16 { if storage_cycle(t, apis) != 0 { fatal(13) } }
		C.usleep(13_000_000)
		before := &Slabs(C.alloca(sizeof(Slabs)))
		after := &Slabs(C.alloca(sizeof(Slabs)))
		if !snapshot(fd, before) { fatal(14) }
		mut failures := 0
		for _ in 0 .. 200 { failures += storage_cycle(t, apis) }
		C.usleep(13_000_000)
		if !snapshot(fd, after) { fatal(15) }
		mut good := failures == 0 && before.rows == after.rows && before.large == after.large && before.tainted == 0 && after.tainted == 0
		for row in 0 .. before.rows {
			if before.sizes[row] != after.sizes[row] || before.live[row] != after.live[row] {
				good = false
			}
			C.printf(c'LINUX EPOLLWORDS SLAB: uid=%u size=%lu live=%lu/%lu\n', C.getuid(), before.sizes[row], before.live[row], after.live[row])
		}
		C.printf(c'LINUX EPOLLWORDS STORAGE: uid=%u cycles=200 big_pages=%lu/%lu tainted=%lu/%lu %s\n', C.getuid(), before.large, after.large, before.tainted, after.tainted, if good {
			&char(c'PASS')
		} else {
			&char(c'FAIL')
		})
		C.close(fd)
		return good
	}
}

fn handler(_ i32, _ &C.siginfo_t, _ voidptr) {
	unsafe {
		C.syscall(int(C.SYS_rt_sigprocmask), 2, nil, observed_mask, uint(8))
		C.__atomic_fetch_add(calls, 1, 0)
	}
}

fn observer(parent i32) {
	unsafe {
		mut path := [96]char{}
		if C.snprintf(&path[0], sizeof(path), c'/proc/%d/stat', parent) <= 0 { C._exit(91) }
		fd := C.open(&path[0], C.O_RDONLY)
		if fd < 0 { C._exit(92) }
		C.usleep(1000)
		for _ in 0 .. 2000 {
			mut text := [4096]u8{}
			length := C.pread(fd, &text[0], 4095, 0)
			mut end := -1
			for i in 0 .. int(length) { if text[i] == `)` { end = i } }
			if end >= 0 && end + 2 < int(length) && text[end + 2] == `S` {
				C.close(fd)
				if C.kill(parent, C.SIGUSR1) != 0 { C._exit(93) }
				C._exit(0)
			}
			C.usleep(1000)
		}
		C.kill(parent, C.SIGUSR1)
		C._exit(95)
	}
}

fn timeout_probe(t &Targets, api int, pattern int) Totals {
	unsafe {
		original := u64(1) << 11
		temporary := u64(1) << 12
		setmask(original)
		C.__atomic_store_n(calls, 0, 0)
		*observed_mask = 0
		mut action := C.sigaction{ sa_sigaction: handler, sa_flags: C.SA_SIGINFO }
		if C.sigemptyset(&action.sa_mask) != 0 || C.sigaction(C.SIGUSR1, &action, nil) != 0 {
			fatal(25)
		}
		g := &Guard(C.alloca(sizeof(Guard)))
		guard(g)
		parent := i32(C.syscall(int(C.SYS_getpid)))
		child := C.fork()
		if child < 0 { fatal(26) }
		if child == 0 { observer(parent) }
		err := C.__errno_location()
		*err = 0
		ret := call(api, t.empty, voidptr(&g.bytes[0]), 1, nil, &temporary, 2, pattern)
		code := *err
		seen := C.__atomic_load_n(calls, 0)
		after := mask()
		mut sum := Totals{}
		record(mut sum, ret == 0 && code == 0, api, 0, 0, 2, pattern, 1, true)
		record(mut sum, event_ok(g, false), api, 0, 0, 2, pattern, 2, true)
		record(mut sum, seen == 0, api, 0, 0, 2, pattern, 3, true)
		record(mut sum, after == original && temporary == u64(1) << 12, api, 0, 0, 2, pattern, 4, true)
		mut status := i32(0)
		for {
			waited := C.waitpid(child, &status, 0)
			if waited == child { break }
			if waited != -1 || *err != C.EINTR { fatal(27) }
		}
		for _ in 0 .. 2000 {
			if C.__atomic_load_n(calls, 0) == 1 { break }
			C.usleep(1000)
		}
		record(mut sum, status == 0 && C.__atomic_load_n(calls, 0) == 1, api, 0, 0, 2, pattern, 5, true)
		record(mut sum, *observed_mask == (original | (u64(1) << 9)) && mask() == original, api, 0, 0, 2, pattern, 6, true)
		C.printf(c'LINUX EPOLLWORDS CASE: uid=%u api=%d value=0 fd=0 kind=2 pattern=%d checks=%d failures=%d\n', C.getuid(), api, pattern, sum.checks, sum.failures)
		return sum
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		C.alarm(600)
		reference := argc == 2 && C.strcmp(argv[1], c'--reference') == 0
		mut apis := 2
		$if amd64 {
			apis = 3
		}
		mut total := Totals{}
		for ordinary in [false, true]! {
			mut pipes := [2]i32{}
			if C.pipe2(&pipes[0], 0) != 0 { fatal(16) }
			C.fflush(nil)
			child := C.fork()
			if child < 0 { fatal(17) }
			if child == 0 {
				C.close(pipes[0])
				if ordinary && (C.setgid(2000) != 0 || C.setuid(1000) != 0) { fatal(18) }
				calls = &i32(C.alloca(sizeof(i32)))
				observed_mask = &u64(C.alloca(sizeof(u64)))
				t := &Targets(C.alloca(sizeof(Targets)))
				*t = targets()
				initial := mask()
				mut sum := Totals{}
				for api in 0 .. apis {
					for kind in [0, 1, 3]! {
						if kind == 3 && api == 2 { continue }
						for value in 0 .. if kind == 1 { 8 } else { 1 } {
							for slot in 0 .. 6 {
								for pattern in 0 .. 6 {
									result := probe(t, api, value, slot, kind, pattern, true)
									sum.checks += result.checks
									sum.failures += result.failures
								}
							}
						}
					}
				}
				for api in 0 .. apis {
					if api == 1 { continue }
					for pattern in 0 .. 6 {
						result := timeout_probe(t, api, pattern)
						sum.checks += result.checks
						sum.failures += result.failures
					}
				}
				if !reference && sum.failures == 0 && !storage(t, apis) { sum.failures++ }
				if reference {
					C.printf(c'LINUX EPOLLWORDS STORAGE: uid=%u SKIP reference\n', C.getuid())
				}
				setmask(initial)
				close_targets(t)
				if C.write(pipes[1], &sum, sizeof(sum)) != sizeof(sum) { fatal(19) }
				C.fflush(nil)
				C._exit(0)
			}
			C.close(pipes[1])
			mut sum := Totals{}
			if C.read(pipes[0], &sum, sizeof(sum)) != sizeof(sum) { fatal(20) }
			C.close(pipes[0])
			mut status := i32(0)
			if C.waitpid(child, &status, 0) != child || status != 0 { fatal(21) }
			total.checks += sum.checks
			total.failures += sum.failures
		}
		C.printf(c'LINUX EPOLLWORDS SUMMARY: checks=%d failures=%d\n', total.checks, total.failures)
		C.printf(c'LINUX EPOLLWORDS: %s\n', if total.failures == 0 {
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
