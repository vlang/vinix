// SPDX-License-Identifier: GPL-2.0-or-later
module epollopcopyfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct Totals {
mut:
	checks   i32
	failures i32
}

struct Targets {
mut:
	epfd      i32
	alias     i32
	reader    i32
	writer    i32
	duplicate i32
	normal    i32
	path      i32
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
fn C.memfd_create(&char, u32) i32
fn C.lseek(i32, i64, i32) i64
fn C.epoll_create1(i32) i32
fn C.epoll_ctl(i32, i32, i32, voidptr) i32
fn C.epoll_wait(i32, voidptr, i32, i32) i32

fn fatal(stage int) {
	C.printf(c'LINUX EPOLLOPCOPY FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil })
	C._exit(90)
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

fn operation(index int) int {
	return match index {
		0 { 1 }
		1 { 3 }
		2 { 2 }
		3 { 0 }
		4 { -1 }
		5 { -2147483648 }
		6 { 2147483647 }
		else { 7 }
	}
}

fn creation_value(kind int, index int) int {
	if kind == 4 {
		return match index {
			0 { 0 }
			1 { int(C.EPOLL_CLOEXEC) }
			2 { 1 }
			3 { -1 }
			4 { int(C.EPOLL_CLOEXEC) | 1 }
			5 { -2147483648 }
			else { 2147483647 }
		}
	}
	return match index {
		0 { -2147483648 }
		1 { -1 }
		2 { 0 }
		3 { 1 }
		4 { 2 }
		else { 2147483647 }
	}
}

fn guard(g &Guard) {
	unsafe {
		mut destination := &Guard(g)
		*destination = Guard{ before: 0xabcdef0123456789, after: 0x9876543210fedcba }
		for i in 0 .. 32 { destination.bytes[i] = 0xa5 }
	}
}

fn event(g &Guard, mask u32, data u64) {
	unsafe {
		guard(g)
		*&u32(&g.bytes[0]) = mask
		$if amd64 {
			(&u32(&g.bytes[0]))[1] = u32(data)
			(&u32(&g.bytes[0]))[2] = u32(data >> 32)
		} $else {
			*&u64(&g.bytes[8]) = data
		}
	}
}

fn unchanged(g &Guard, saved &Guard) bool {
	unsafe {
		if g.before != saved.before || g.after != saved.after { return false }
		for i in 0 .. 32 { if g.bytes[i] != saved.bytes[i] { return false } }
		return true
	}
}

fn output_ok(g &Guard, ready bool, data u64) bool {
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
			if *&u32(&g.bytes[0]) != 1 || *&u64(&g.bytes[offset]) != data { return false }
		}
		for i in length .. 32 { if g.bytes[i] != 0xa5 { return false } }
		return true
	}
}

fn targets() Targets {
	unsafe {
		mut pipes := [2]i32{}
		if C.pipe2(&pipes[0], C.O_NONBLOCK | C.O_CLOEXEC) != 0 { fatal(1) }
		epfd := C.epoll_create1(C.EPOLL_CLOEXEC)
		alias := C.dup(epfd)
		duplicate := C.fcntl(pipes[0], C.F_DUPFD_CLOEXEC, 70)
		normal := C.memfd_create(c'epollopcopy', 0)
		path := C.open(c'/dev/null', C.O_PATH)
		if epfd < 0 || alias < 0 || duplicate < 0 || normal < 0 || path < 0 { fatal(2) }
		return Targets{ epfd: epfd, alias: alias, reader: pipes[0], writer: pipes[1], duplicate: duplicate, normal: normal, path: path }
	}
}

fn close_targets(t &Targets) {
	C.close(t.epfd)
	C.close(t.alias)
	C.close(t.reader)
	C.close(t.writer)
	C.close(t.duplicate)
	C.close(t.normal)
	C.close(t.path)
}

fn record(mut sum Totals, good bool, kind int, op int, target int, bad int, pattern int, stage int, report bool) {
	sum.checks++
	if good { return }
	sum.failures++
	if report {
		C.printf(c'LINUX EPOLLOPCOPY MISMATCH: uid=%u kind=%d op=%d target=%d bad=%d pattern=%d stage=%d\n', C.getuid(), kind, op, target, bad, pattern, stage)
	}
}

fn line(sum &Totals, kind int, op int, target int, bad int, pattern int) {
	C.printf(c'LINUX EPOLLOPCOPY CASE: uid=%u kind=%d op=%d target=%d bad=%d pattern=%d checks=%d failures=%d\n', C.getuid(), kind, op, target, bad, pattern, sum.checks, sum.failures)
}

fn ctl(t &Targets, kind int, index int, slot int, bad int, pattern int, report bool) Totals {
	unsafe {
		op := operation(index)
		epfd := if pattern % 2 == 0 { t.epfd } else { t.alias }
		target := match slot {
			0 { t.reader }
			1 { t.duplicate }
			2 { t.path }
			3 { t.normal }
			4 { epfd }
			else { i32(-1) }
		}
		valid := slot in [0, 1]!
		old := valid && op in [2, 3]!
		input := &Guard(C.alloca(sizeof(Guard)))
		event(input, 0x40000001, 0x1122334455667788)
		saved := &Guard(C.alloca(sizeof(Guard)))
		*saved = *input
		out := &Guard(C.alloca(sizeof(Guard)))
		guard(out)
		if old {
			event(input, 0x40000001, 0x8877665544332211)
			if C.epoll_ctl(t.epfd, 1, target, voidptr(&input.bytes[0])) != 0 { fatal(3) }
			*input = *saved
		}
		byte := u8(0x51)
		if C.write(t.writer, &byte, 1) != 1 { fatal(4) }
		flags := C.fcntl(t.reader, C.F_GETFL)
		fdflags := C.fcntl(epfd, C.F_GETFD)
		targetflags := C.fcntl(target, C.F_GETFD)
		position := C.lseek(t.normal, 0, C.SEEK_CUR)
		expected := if bad == 1 && op != 2 {
			C.EFAULT
		} else if slot in [2, 5]! {
			C.EBADF
		} else if slot == 3 {
			C.EPERM
		} else if slot == 4 || op !in [1, 2, 3]! {
			C.EINVAL
		} else {
			0
		}
		err := C.__errno_location()
		*err = 0
		ret := C.syscall(int(C.SYS_epoll_ctl), if kind == 0 {
			word(int(epfd), pattern)
		} else {
			u64(epfd)
		}, if kind == 1 { word(op, pattern) } else { u64(i64(op)) }, if kind == 2 {
			word(int(target), pattern)
		} else {
			u64(i64(target))
		}, if bad == 1 { voidptr(u64(0xffffffffffffffff)) } else { voidptr(&input.bytes[0]) })
		code := *err
		mut sum := Totals{}
		record(mut sum, ret == (if expected == 0 { 0 } else { -1 }) && code == expected, kind, index, slot, bad, pattern, 1, report)
		record(mut sum, unchanged(input, saved), kind, index, slot, bad, pattern, 2, report)
		wanted := if expected != 0 {
			if old { 1 } else { 0 }
		} else if op == 2 {
			0
		} else {
			2
		}
		found := C.epoll_wait(t.epfd, voidptr(&out.bytes[0]), 1, 0)
		record(mut sum, found == (if wanted == 0 { 0 } else { 1 }) && output_ok(out, wanted != 0, if wanted == 1 {
			u64(0x8877665544332211)
		} else {
			u64(0x1122334455667788)
		}), kind, index, slot, bad, pattern, 3, report)
		mut actual := u8(0)
		first := C.read(t.reader, &actual, 1)
		empty := C.read(t.reader, &actual, 1)
		empty_error := *err
		record(mut sum, first == 1 && actual == byte && empty == -1 && empty_error == C.EAGAIN && C.fcntl(t.reader, C.F_GETFL) == flags, kind, index, slot, bad, pattern, 4, report)
		record(mut sum, C.fcntl(epfd, C.F_GETFD) == fdflags && C.fcntl(target, C.F_GETFD) == targetflags && C.lseek(t.normal, 0, C.SEEK_CUR) == position, kind, index, slot, bad, pattern, 5, report)
		mut cleaned := true
		if valid {
			cleanup := C.epoll_ctl(t.epfd, 2, target, nil)
			cleaned = cleanup == 0 || (cleanup == -1 && *err == C.ENOENT)
		}
		guard(out)
		record(mut sum, cleaned && C.epoll_wait(t.epfd, voidptr(&out.bytes[0]), 1, 0) == 0 && output_ok(out, false, 0), kind, index, slot, bad, pattern, 6, report)
		if report { line(&sum, kind, index, slot, bad, pattern) }
		return sum
	}
}

fn create(t &Targets, kind int, index int, pattern int, report bool) Totals {
	unsafe {
		value := creation_value(kind, index)
		expected := if kind == 4 { value == 0 || value == int(C.EPOLL_CLOEXEC) } else { value > 0 }
		byte := u8(0x51)
		if C.write(t.writer, &byte, 1) != 1 { fatal(5) }
		flags := C.fcntl(t.reader, C.F_GETFL)
		input := &Guard(C.alloca(sizeof(Guard)))
		event(input, 0x40000001, 0x1122334455667788)
		out := &Guard(C.alloca(sizeof(Guard)))
		guard(out)
		err := C.__errno_location()
		*err = 0
		mut ret := int(-1)
		if kind == 4 {
			ret = C.syscall(int(C.SYS_epoll_create1), word(value, pattern))
		} else {
			$if amd64 {
				ret = C.syscall(int(C.SYS_epoll_create), word(value, pattern))
			} $else {
				fatal(6)
			}
		}
		code := *err
		mut sum := Totals{}
		record(mut sum, if expected { ret >= 0 && code == 0 } else { ret == -1 && code == C.EINVAL }, kind, index, 0, 0, pattern, 1, report)
		mut flags_ok := !expected
		mut empty_ok := !expected
		mut data_ok := !expected
		mut close_ok := !expected
		if ret >= 0 {
			fd := i32(ret)
			flags_ok = C.fcntl(fd, C.F_GETFD) == (if kind == 4 && value & int(C.EPOLL_CLOEXEC) != 0 {
				1
			} else {
				0
			}) && C.fcntl(fd, C.F_GETFL) & C.O_ACCMODE == C.O_RDWR
			empty_ok = C.epoll_wait(fd, voidptr(&out.bytes[0]), 1, 0) == 0 && output_ok(out, false, 0)
			data_ok = C.epoll_ctl(fd, 1, t.reader, voidptr(&input.bytes[0])) == 0 && C.epoll_wait(fd, voidptr(&out.bytes[0]), 1, 0) == 1 && output_ok(out, true, 0x1122334455667788)
			close_ok = C.epoll_ctl(fd, 2, t.reader, nil) == 0
			guard(out)
			close_ok = close_ok && C.epoll_wait(fd, voidptr(&out.bytes[0]), 1, 0) == 0 && output_ok(out, false, 0)
			close_ok = C.close(fd) == 0 && close_ok
			close_ok = C.fcntl(fd, C.F_GETFD) == -1 && *err == C.EBADF && close_ok
		}
		record(mut sum, flags_ok, kind, index, 0, 0, pattern, 2, report)
		record(mut sum, empty_ok, kind, index, 0, 0, pattern, 3, report)
		record(mut sum, data_ok, kind, index, 0, 0, pattern, 4, report)
		record(mut sum, close_ok, kind, index, 0, 0, pattern, 5, report)
		mut actual := u8(0)
		first := C.read(t.reader, &actual, 1)
		empty := C.read(t.reader, &actual, 1)
		empty_error := *err
		record(mut sum, first == 1 && actual == byte && empty == -1 && empty_error == C.EAGAIN && C.fcntl(t.reader, C.F_GETFL) == flags, kind, index, 0, 0, pattern, 6, report)
		if report { line(&sum, kind, index, 0, 0, pattern) }
		return sum
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
			C.printf(c'LINUX EPOLLOPCOPY SLAB: uid=%u size=%lu live=%lu/%lu\n', C.getuid(), before.sizes[row], before.live[row], after.live[row])
		}
		C.printf(c'LINUX EPOLLOPCOPY STORAGE: uid=%u cycles=200 big_pages=%lu/%lu tainted=%lu/%lu %s\n', C.getuid(), before.large, after.large, before.tainted, after.tainted, if good {
			&char(c'PASS')
		} else {
			&char(c'FAIL')
		})
		C.close(fd)
		return good
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

fn storage_cycle(t &Targets, _ int) int {
	unsafe {
		peer := &Targets(C.alloca(sizeof(Targets)))
		*peer = *t
		peer.alias = C.dup(t.epfd)
		if peer.alias < 0 { fatal(7) }
		mut failures := 0
		for kind in 0 .. 3 {
			for pattern in [2, 4]! {
				for index in 0 .. 3 {
					for slot in [0, 1, 2, 5]! {
						failures += int(ctl(peer, kind, index, slot, if pattern == 4 {
							1
						} else {
							0
						}, pattern, false).failures)
					}
				}
			}
		}
		for index in 3 .. 8 {
			for slot in [0, 1, 2, 5]! {
				for pattern in [2, 4]! {
					failures += int(ctl(peer, 1, index, slot, 1, pattern, false).failures)
				}
			}
		}
		for pattern in [2, 4]! {
			failures += int(create(peer, 4, if pattern == 2 { 0 } else { 1 }, pattern, false).failures)
			$if amd64 {
				failures += int(create(peer, 5, 3, pattern, false).failures)
			}
		}
		if C.close(peer.alias) != 0 { fatal(8) }
		return failures
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		C.alarm(600)
		reference := argc == 2 && C.strcmp(argv[1], c'--reference') == 0
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
				mut sum := Totals{}
				for kind in 0 .. 3 {
					for index in 0 .. if kind == 1 { 8 } else { 3 } {
						for slot in 0 .. 6 {
							for bad in 0 .. 2 {
								for pattern in 0 .. 6 {
									result := ctl(t, kind, index, slot, bad, pattern, true)
									sum.checks += result.checks
									sum.failures += result.failures
								}
							}
						}
					}
				}
				for index in 0 .. 7 {
					for pattern in 0 .. 6 {
						result := create(t, 4, index, pattern, true)
						sum.checks += result.checks
						sum.failures += result.failures
					}
				}
				$if amd64 {
					for index in 0 .. 6 {
						for pattern in 0 .. 6 {
							result := create(t, 5, index, pattern, true)
							sum.checks += result.checks
							sum.failures += result.failures
						}
					}
				}
				if !reference && sum.failures == 0 && !storage(t, 0) { sum.failures++ }
				if reference {
					C.printf(c'LINUX EPOLLOPCOPY STORAGE: uid=%u SKIP reference\n', C.getuid())
				}
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
		C.printf(c'LINUX EPOLLOPCOPY SUMMARY: checks=%d failures=%d\n', total.checks, total.failures)
		C.printf(c'LINUX EPOLLOPCOPY: %s\n', if total.failures == 0 {
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
