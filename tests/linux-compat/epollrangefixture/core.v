// SPDX-License-Identifier: GPL-2.0-or-later
module epollrangefixture

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
	readonly voidptr
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
fn C.mprotect(voidptr, uint, i32) i32

fn fatal(stage int) {
	C.printf(c'LINUX EPOLLRANGE FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
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
		0 { 0 }
		1 { 1 }
		2 { 2 }
		else { limit() + 1 }
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
		readonly := C.mmap(voidptr(u64(0x50000000)), 16384, C.PROT_READ | C.PROT_WRITE,
			C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if u64(readonly) > 0x100000000 { fatal(23) }
		guard(&Guard(readonly))
		if C.mprotect(readonly, 16384, C.PROT_READ) != 0 { fatal(24) }
		mut event := [4]u64{}
		(&u32(&event[0]))[0] = 1
		if C.epoll_ctl(ready, 1, pipes[0], voidptr(&event[0])) != 0 { fatal(6) }
		return Targets{ output: &Guard(output), readonly: readonly, empty: empty, ready: ready, alias: alias, ordinary: ordinary, path: path, reader: pipes[0], writer: pipes[1] }
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
	C.munmap(t.readonly, 16384)
}

fn call(api int, epfd i32, output voidptr, maximum int, stamp voidptr, temporary &u64) int {
	unsafe {
		match api {
			0 {
				return C.syscall(int(C.SYS_epoll_pwait), epfd, output, maximum, 0, temporary, uint(8))
			}
			1 {
				return C.syscall(int(C.SYS_epoll_pwait2), epfd, output, maximum, stamp, temporary, uint(8))
			}
			2 { return C.epoll_wait(epfd, output, i32(maximum), 0) }
			3 {
				mut value := C.sigset_t{}
				if C.sigemptyset(&value) != 0 { fatal(7) }
				*&u64(&value) = *temporary
				return C.epoll_pwait(epfd, output, i32(maximum), 0, &value)
			}
			else {
				$if amd64 {
					return C.syscall(int(C.SYS_epoll_wait), epfd, output, maximum, 0)
				} $else {
					fatal(8)
					return -1
				}
			}
		}
	}
}

fn record(mut sum Totals, good bool, api int, value int, fd int, output int, timeout int, stage int, report bool) {
	sum.checks++
	if good { return }
	sum.failures++
	if report {
		C.printf(c'LINUX EPOLLRANGE MISMATCH: uid=%u api=%d value=%d fd=%d output=%d timeout=%d stage=%d\n', C.getuid(), api, value, fd, output, timeout, stage)
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

fn probe(t &Targets, api int, value int, slot int, output int, timeout int, report bool) Totals {
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
		maximum := count(value)
		original := u64(1) << 11
		temporary := u64(1) << 12
		setmask(original)
		ts := &Stamp(C.alloca(sizeof(Stamp)))
		*ts = Stamp{
			seconds: if timeout == 2 { -1 } else { 0 }
			nanos:   if timeout == 3 {
				1000000000
			} else {
				0
			}
		}
		address := match output {
			0 { voidptr(&g.bytes[0]) }
			1 { nil }
			2 { voidptr(u64(0x20000000)) }
			3 { t.readonly }
			4 { voidptr(u64(0xffffffffffffffff)) }
			5 { voidptr(u64(0x8000000000000000)) }
			6 { voidptr(u64(0xffff800000000000)) }
			7 { voidptr(u64(0x00fffffffffffff8)) }
			8 { voidptr(u64(0x7fffffffffffffff)) }
			else { voidptr(u64(0xfffffffffffffff0)) }
		}
		err := C.__errno_location()
		*err = 0
		ret := call(api, fd, address, maximum, if timeout == 1 {
			voidptr(u64(0xffffffffffffffff))
		} else {
			voidptr(ts)
		}, &temporary)
		code := *err
		after := mask()
		refused := maximum <= 0 || maximum > limit()
		wanted_errno := if timeout == 1 {
			C.EFAULT
		} else if timeout > 1 || refused {
			C.EINVAL
		} else if output >= 4 {
			C.EFAULT
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
		record(mut sum, ret == wanted && code == wanted_errno, api, value, slot, output, timeout, 1, report)
		record(mut sum, event_ok(g, delivered), api, value, slot, output, timeout, 2, report)
		record(mut sum, after == original, api, value, slot, output, timeout, 3, report)
		record(mut sum, temporary == u64(1) << 12 && ts.seconds == (if timeout == 2 {
			-1
		} else {
			0
		}) && ts.nanos == (if timeout == 3 { 1000000000 } else { 0 }) && event_ok(&Guard(t.readonly), false), api, value, slot, output, timeout, 4, report)
		next := C.epoll_wait(t.ready, voidptr(&follow.bytes[0]), 1, 0)
		record(mut sum, next == (if delivered { 0 } else { 1 }) && event_ok(follow, !delivered), api, value, slot, output, timeout, 5, report)
		mut actual := u8(0)
		read_count := C.read(t.reader, &actual, 1)
		empty_count := C.read(t.reader, &actual, 1)
		empty_error := *err
		record(mut sum, read_count == 1 && actual == byte && empty_count == -1 && empty_error == C.EAGAIN && C.fcntl(t.reader, C.F_GETFL) == flags, api, value, slot, output, timeout, 6, report)
		if report {
			C.printf(c'LINUX EPOLLRANGE CASE: uid=%u api=%d value=%d fd=%d output=%d timeout=%d checks=%d failures=%d\n', C.getuid(), api, value, slot, output, timeout, sum.checks, sum.failures)
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
			for output in [0, 4, 9]! {
				for slot in [0, 1, 2, 3]! {
					failures += int(probe(peer, api, 1, slot, output, 0, false).failures)
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
			C.printf(c'LINUX EPOLLRANGE SLAB: uid=%u size=%lu live=%lu/%lu\n', C.getuid(), before.sizes[row], before.live[row], after.live[row])
		}
		C.printf(c'LINUX EPOLLRANGE STORAGE: uid=%u cycles=200 big_pages=%lu/%lu tainted=%lu/%lu %s\n', C.getuid(), before.large, after.large, before.tainted, after.tainted, if good {
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
		mut apis := 4
		$if amd64 {
			apis = 5
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
				t := &Targets(C.alloca(sizeof(Targets)))
				*t = targets()
				initial := mask()
				mut sum := Totals{}
				for api in 0 .. apis {
					for value in 0 .. 4 {
						for slot in 0 .. 6 {
							for output in 0 .. 10 {
								// Actual page-copy faults are distinct from address-span admission.
								if value in [1, 2]! && output in [1, 2, 3]! && slot in [
									1,
									2,
								]! {
									continue
								}
								result := probe(t, api, value, slot, output, 0, true)
								sum.checks += result.checks
								sum.failures += result.failures
							}
						}
					}
				}
				for value in [0, 1]! {
					for slot in 0 .. 6 {
						for timeout in 1 .. 4 {
							result := probe(t, 1, value, slot, 4, timeout, true)
							sum.checks += result.checks
							sum.failures += result.failures
						}
					}
				}
				if !reference && sum.failures == 0 && !storage(t, apis) { sum.failures++ }
				if reference {
					C.printf(c'LINUX EPOLLRANGE STORAGE: uid=%u SKIP reference\n', C.getuid())
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
		C.printf(c'LINUX EPOLLRANGE SUMMARY: checks=%d failures=%d\n', total.checks, total.failures)
		C.printf(c'LINUX EPOLLRANGE: %s\n', if total.failures == 0 {
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
