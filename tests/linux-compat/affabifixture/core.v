// SPDX-License-Identifier: GPL-2.0-or-later
module affabifixture

#define __EXPORTED_HEADERS__
#include <alloca.h>
#include <linux/capability.h>
#include <pthread.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <sched.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

struct C.sched_param {
mut:
	sched_priority i32
}

struct Attr {
mut:
	size     u32
	policy   u32
	flags    u64
	nice     i32
	priority u32
	runtime  u64
	deadline u64
	period   u64
	util_min u32
	util_max u32
}

struct Counts {
mut:
	calls    [4]u64
	failures [4]u64
}

struct Slabs {
mut:
	sizes [32]u64
	live  [32]u64
	rows  i32
	large u64
}

struct Query {
	ret  isize
	code i32
}

fn C.alloca(usize) voidptr
fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.memset(voidptr, i32, usize) voidptr
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.mprotect(voidptr, usize, i32) i32
fn C.munmap(voidptr, usize) i32
fn C.sysconf(i32) i64
fn C.getpid() i32
fn C.getuid() u32
fn C.geteuid() u32
fn C.pipe2(&i32, i32) i32
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.pread(i32, voidptr, usize, i64) isize
fn C.write(i32, voidptr, usize) isize
fn C.read(i32, voidptr, usize) isize
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.strcmp(&char, &char) i32
fn C.sscanf(&char, &char, ...) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.usleep(u32) i32
fn C.alarm(u32) u32
fn C.pause() i32
fn C._exit(i32)

fn fatal(stage i32) {
	C.printf(c'LINUX AFFABI FAIL: setup or child protocol stage=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil })
	C._exit(1)
}

@[typedef]
struct C.pthread_t {}

@[typedef]
struct C.cpu_set_t {}

struct C.__user_cap_header_struct {
mut:
	version u32
	pid     i32
}

struct C.__user_cap_data_struct {
mut:
	effective   u32
	permitted   u32
	inheritable u32
}

struct Fixture {
mut:
	all        u64
	low        u64
	mask_bytes u32
	peer       i32
	peer_fd    i32
	worker     i32
	initial    [2]C.__user_cap_data_struct
}

struct Worker {
mut:
	ready   i32
	command i32
	failed  i32
}

fn C.getgid() u32
fn C.getegid() u32
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.sched_getaffinity(i32, usize, &C.cpu_set_t) i32
fn C.sched_setaffinity(i32, usize, &C.cpu_set_t) i32

fn query(set bool, pid u64, length u64, pointer u64) Query {
	unsafe {
		slot := C.__errno_location()
		*slot = 0
		ret := C.syscall(if set {
			isize(C.SYS_sched_setaffinity)
		} else {
			isize(C.SYS_sched_getaffinity)
		}, pid, length, pointer, u64(-1))
		return Query{ret, *slot}
	}
}

fn capability(on bool) {
	unsafe {
		header := &C.__user_cap_header_struct(C.alloca(usize(sizeof(C.__user_cap_header_struct))))
		*header = C.__user_cap_header_struct{ version: 0x20080522 }
		data := &C.__user_cap_data_struct(C.alloca(usize(2 * sizeof(C.__user_cap_data_struct))))
		C.memset(data, 0, usize(2 * sizeof(C.__user_cap_data_struct)))
		if C.syscall(C.SYS_capget, header, data) != 0 || data[0].permitted & (u32(1) << 23) == 0 {
			fatal(20)
		}
		if on { data[0].effective |= u32(1) << 23 } else { data[0].effective &= ~(u32(1) << 23) }
		if C.syscall(C.SYS_capset, header, data) != 0 { fatal(21) }
		if C.syscall(C.SYS_capget, header, data) != 0 || (data[0].effective & (u32(1) << 23) != 0) != on {
			fatal(22)
		}
	}
}

fn cap_snapshot(destination &C.__user_cap_data_struct) {
	unsafe {
		header := &C.__user_cap_header_struct(C.alloca(usize(sizeof(C.__user_cap_header_struct))))
		*header = C.__user_cap_header_struct{ version: 0x20080522 }
		if C.syscall(C.SYS_capget, header, destination) != 0 { fatal(23) }
	}
}

fn cap_match(fixture &Fixture) bool {
	unsafe {
		data := &C.__user_cap_data_struct(C.alloca(usize(2 * sizeof(C.__user_cap_data_struct))))
		cap_snapshot(data)
		return C.memcmp(data, &fixture.initial[0], usize(2 * sizeof(C.__user_cap_data_struct))) == 0
	}
}

fn observed(pid i32, expected u64) bool {
	unsafe {
		mut bits := u64(0)
		result := query(false, u64(i64(pid)), 8, u64(&bits))
		return result.ret == 8 && result.code == 0 && bits == expected
	}
}

fn restore(pid i32, all u64, cap bool) {
	unsafe {
		capability(true)
		value := all
		result := query(true, u64(i64(pid)), 8, u64(&value))
		if result.ret != 0 || result.code != 0 || !observed(pid, all) { fatal(24) }
		capability(cap)
	}
}

fn peer_start(fixture &Fixture, result_fd i32) {
	unsafe {
		command := &i32(C.alloca(usize(2 * sizeof(i32))))
		ready := &i32(C.alloca(usize(2 * sizeof(i32))))
		if C.pipe2(command, C.O_CLOEXEC) != 0 || C.pipe2(ready, C.O_CLOEXEC) != 0 { fatal(25) }
		child := C.fork()
		if child < 0 { fatal(26) }
		if child == 0 {
			C.close(result_fd)
			C.close(command[1])
			C.close(ready[0])
			C.alarm(600)
			if C.setgroups(0, nil) != 0 || C.setgid(1001) != 0 || C.setuid(1001) != 0 || C.getuid() != 1001 || C.geteuid() != 1001 || C.getgid() != 1001 || C.getegid() != 1001 {
				fatal(27)
			}
			mut byte := u8(0xaf)
			if C.write(ready[1], &byte, 1) != 1 { fatal(28) }
			C.close(ready[1])
			good := C.read(command[0], &byte, 1) == 1 && byte == 0xd1
			C.close(command[0])
			C._exit(if good { 0 } else { 1 })
		}
		C.close(command[0])
		C.close(ready[1])
		mut byte := u8(0)
		if C.read(ready[0], &byte, 1) != 1 || byte != 0xaf { fatal(29) }
		C.close(ready[0])
		mut value := &Fixture(fixture)
		value.peer = child
		value.peer_fd = command[1]
	}
}

fn worker(argument voidptr) voidptr {
	unsafe {
		mut value := &Worker(argument)
		mut tid := i32(C.syscall(C.SYS_gettid))
		if tid <= 0 || C.write(value.ready, &tid, sizeof(i32)) != isize(sizeof(i32)) {
			value.failed = 1
			return nil
		}
		mut byte := u8(0)
		if C.read(value.command, &byte, 1) != 1 || byte != 0xd1 { value.failed = 1 }
		return nil
	}
}

fn record(counts &Counts, kind i32, good bool, ordinary bool, pid u64, size u64, flags u64, form i32, result Query, expected i32) {
	unsafe {
		mut value := &Counts(counts)
		value.calls[kind]++
		if !good {
			value.failures[kind]++
			if value.failures[kind] <= 4 {
				C.printf(c'LINUX AFFABI DETAIL: ordinary=%d kind=%d pid=%lx size=%lx flags=%lx form=%d call=%lu ret=%ld errno=%d expected=%d\n', i32(ordinary), kind, pid, size, flags, form, value.calls[kind], result.ret, result.code, expected)
				C.fflush(nil)
			}
		}
	}
}

fn bytes(data &u8, count i32, except_at i32, except_len i32) bool {
	unsafe {
		for index in 0 .. int(count) {
			if index >= except_at && index < except_at + except_len { continue }
			if data[index] != 0xa5 { return false }
		}
		return true
	}
}

fn checked(counts &Counts, ordinary bool, fixture &Fixture, source i32, live bool, peer bool, set bool, length u32, form i32, variant i32, mask_bits u64, cap bool, mapping &u8, page usize, override i32) {
	unsafe {
		if C.mprotect(mapping + page, page, C.PROT_READ | C.PROT_WRITE) != 0 { fatal(30) }
		scratch_size := fixture.mask_bytes + 16
		scratch := &u8(C.alloca(usize(scratch_size)))
		C.memset(scratch, 0xa5, usize(scratch_size))
		for pointer in [mapping + page - 64, mapping + page, mapping + 2 * page - 64]! {
			C.memset(pointer, 0xa5, 64)
		}
		offset := if form == 1 { usize(9) } else { usize(8) }
		pointer := match form {
			2 {
				if set { mapping + 2 * page - 8 } else { mapping + page - 8 }
			}
			3 { &u8(usize(0)) }
			4 { &u8(usize(1)) }
			5 { mapping + 2 * page }
			6 { mapping + page }
			7 { mapping + 2 * page - 4 }
			8 { &u8(u64(scratch + offset) | (u64(1) << 55)) }
			9 { mapping + page - 4 }
			else { scratch + offset }
		}
		accessible := form !in [i32(3), 4, 5, 8]
		known := if form == 7 { usize(4) } else { usize(8) }
		if set && accessible {
			value := mask_bits
			C.memcpy(pointer, &value, known)
		}
		if C.mprotect(mapping + page, page, C.PROT_READ) != 0 { fatal(31) }
		pid := if variant == 1 {
			u64(u32(source)) | 0x1234567800000000
		} else if variant == 2 {
			u64(u32(source)) | 0xffffffff00000000
		} else {
			u64(i64(source))
		}
		word_length := u64(length) | if variant == 3 { u64(0xffffffff00000000) } else { u64(0) }
		n := if length < 8 { length } else { u32(8) }
		effective := if n == 0 {
			u64(0)
		} else if n == 8 {
			mask_bits
		} else {
			mask_bits & ((u64(1) << (n * 8)) - 1)
		}
		bad_length := u32(length * u32(8)) == 0 || length % 8 != 0
		copied := if length < fixture.mask_bytes { length } else { fixture.mask_bytes }
		input_fault := copied != 0 && (!accessible || (form == 7 && copied > 4) || (form == 2 && copied > 8))
		code := if !set {
			if bad_length {
				i32(C.EINVAL)
			} else if !live {
				i32(C.ESRCH)
			} else if form >= 3 || (form == 2 && copied > 8) {
				i32(C.EFAULT)
			} else {
				i32(0)
			}
		} else {
			if input_fault {
				i32(C.EFAULT)
			} else if !live {
				i32(C.ESRCH)
			} else if peer && !cap {
				i32(C.EPERM)
			} else if effective & fixture.all == 0 {
				i32(C.EINVAL)
			} else {
				i32(0)
			}
		}
		before := &u8(C.alloca(usize(8)))
		if accessible { C.memcpy(before, pointer, known) }
		result := query(set, pid, word_length, u64(pointer))
		wanted := if code != 0 {
			isize(-1)
		} else if set {
			isize(0)
		} else {
			isize(copied)
		}
		mut good := result.ret == wanted && result.code == code
		if live {
			good = good && observed(source, if set && code == 0 {
				effective & fixture.all
			} else {
				fixture.all
			})
		}
		if set {
			if accessible { good = good && C.memcmp(pointer, before, known) == 0 }
			good = good && bytes(scratch, i32(scratch_size), if form < 2 { i32(offset) } else { -1 }, if form < 2 {
				8
			} else {
				0
			})
		} else {
			if code == 0 {
				actual := u64(0)
				mut bits := actual
				C.memcpy(&bits, pointer, 8)
				good = good && bits == fixture.all
				for index in 8 .. int(copied) { if pointer[index] != 0 { good = false } }
			}
			good = good && bytes(scratch, i32(scratch_size), if code == 0 && form < 2 {
				i32(offset)
			} else {
				-1
			}, if code == 0 && form < 2 {
				i32(copied)
			} else {
				0
			})
		}
		good = good && bytes(mapping + page - 64, 64, if set && form == 9 {
			60
		} else if !set && live && !bad_length && form == 2 {
			56
		} else if !set && code == C.EFAULT && live && !bad_length && form == 9 {
			60
		} else {
			-1
		}, if set && form == 9 {
			4
		} else if !set && live && !bad_length && form == 2 {
			8
		} else if !set && code == C.EFAULT && live && !bad_length && form == 9 {
			4
		} else {
			0
		})
		good = good && bytes(mapping + page, 64, if set && form == 6 {
			0
		} else if set && form == 9 {
			0
		} else {
			-1
		}, if set && form == 6 {
			8
		} else if set && form == 9 {
			4
		} else {
			0
		})
		good = good && bytes(mapping + 2 * page - 64, 64, if set && form == 2 {
			56
		} else if set && form == 7 {
			60
		} else {
			-1
		}, if set && form == 2 {
			8
		} else if set && form == 7 {
			4
		} else {
			0
		})
		record(counts, if override >= 0 {
			override
		} else if variant in [i32(1), 2] {
			1
		} else if variant == 3 {
			2
		} else {
			0
		}, good, ordinary, pid, word_length, u64(set), form, result, code)
		if set && live { restore(source, fixture.all, cap) }
	}
}

fn libc_control(counts &Counts, ordinary bool, fixture &Fixture, source i32, live bool, peer bool, set bool, length u32, cap bool) {
	unsafe {
		data := &u8(C.alloca(usize(144)))
		C.memset(data, 0xa5, 144)
		if set {
			value := fixture.low
			C.memcpy(data + 8, &value, 8)
		}
		slot := C.__errno_location()
		*slot = 0
		ret := if set {
			C.sched_setaffinity(source, usize(length), &C.cpu_set_t(data + 8))
		} else {
			C.sched_getaffinity(source, usize(length), &C.cpu_set_t(data + 8))
		}
		code := *slot
		expected := if !live {
			i32(C.ESRCH)
		} else if set && peer && !cap {
			i32(C.EPERM)
		} else {
			i32(0)
		}
		mut good := ret == if expected == 0 { i32(0) } else { i32(-1) } && code == expected
		if live {
			good = good && observed(source, if set && expected == 0 {
				fixture.low
			} else {
				fixture.all
			})
		}
		if set {
			mut actual := u64(0)
			C.memcpy(&actual, data + 8, 8)
			good = good && actual == fixture.low && bytes(data, 144, 8, 8)
		} else if expected == 0 {
			mut actual := u64(0)
			C.memcpy(&actual, data + 8, 8)
			good = good && actual == fixture.all && bytes(data, 144, 8, i32(length))
			for index in 8 .. int(length) { if data[8 + index] != 0 { good = false } }
		} else {
			good = good && bytes(data, 144, -1, 0)
		}
		record(counts, 3, good, ordinary, u64(i64(source)), u64(length), u64(set), -1, Query{isize(ret), code}, expected)
		if set && live { restore(source, fixture.all, cap) }
	}
}

fn matrix(counts &Counts, ordinary bool, fixture &Fixture, dead i32, mapping &u8, page usize) {
	unsafe {
		self := C.getpid()
		capability(false)
		for source in [i32(0), self, fixture.worker, -1, i32(u32(0x80000000)), 0x7fffffff, dead,
			fixture.peer]! {
			live := source == 0 || source == self || source == fixture.worker || source == fixture.peer
			peer := source == fixture.peer
			for length in [u32(0), 1, 2, 3, 4, 5, 6, 7, 8, 9, 16, 128, u32(0x1fffffff),
				u32(0x20000000), u32(0x20000008), u32(0x40000000), u32(0x80000000), u32(0xfffffff8),
				u32(-1)]! {
				for form in 0 .. 10 {
					for variant in 0 .. 4 {
						checked(counts, ordinary, fixture, source, live, peer, false, length, i32(form), i32(variant), 0, false, mapping, page, -1)
						for mask in [u64(0), fixture.low, fixture.low | (u64(1) << 63)]! {
							checked(counts, ordinary, fixture, source, live, peer, true, length, i32(form), i32(variant), mask, false, mapping, page, -1)
						}
					}
				}
			}
		}
		for cap in [false, true]! {
			capability(cap)
			for source in [i32(0), self, fixture.worker, -1, i32(u32(0x80000000)), 0x7fffffff,
				dead, fixture.peer]! {
				live := source == 0 || source == self || source == fixture.worker || source == fixture.peer
				peer := source == fixture.peer
				for length in [u32(0), 1, 8]! {
					for mask in [u64(0), fixture.low, u64(1) << 63]! {
						for variant in [i32(0), 1]! {
							checked(counts, ordinary, fixture, source, live, peer, true, length, 0, variant, mask, cap, mapping, page, 3)
						}
					}
				}
				for length in [u32(8), 16, 128]! {
					for set in [false, true]! {
						libc_control(counts, ordinary, fixture, source, live, peer, set, length, cap)
					}
				}
			}
		}
		capability(false)
	}
}

fn cycle(fixture &Fixture) bool {
	unsafe {
		capability(false)
		mut bits := fixture.low
		short := query(true, u64(u32(fixture.worker)) | 0x1234567800000000, 0xffffffff00000001, u64(&bits))
		if short.ret != 0 || short.code != 0 || !observed(fixture.worker, fixture.low) {
			return false
		}
		restore(fixture.worker, fixture.all, false)
		denied := query(true, u64(fixture.peer), 1, u64(&bits))
		if denied.ret != -1 || denied.code != C.EPERM || !observed(fixture.peer, fixture.all) {
			return false
		}
		capability(true)
		allowed := query(true, u64(fixture.peer), 1, u64(&bits))
		if allowed.ret != 0 || allowed.code != 0 || !observed(fixture.peer, fixture.low) {
			return false
		}
		restore(fixture.peer, fixture.all, false)
		zero := query(true, 0, 0, 0)
		missing := query(true, 0x7fffffff, 0, 0)
		negative := query(false, 0xffffffff, 8, 0)
		overflow := query(false, 0, 0x20000000, 0)
		bits = 0
		get := query(false, 0x1234567800000000, 0xffffffff00000008, u64(&bits))
		return zero.ret == -1 && zero.code == C.EINVAL && missing.ret == -1 && missing.code == C.ESRCH && negative.ret == -1 && negative.code == C.ESRCH && overflow.ret == -1 && overflow.code == C.EINVAL && get.ret == 8 && get.code == 0 && bits == fixture.all
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
			}
			for position < int(length) && data[position] != char(10) { position++ }
			position++
		}
		return counts.rows > 0 && large
	}
}

fn storage(ordinary bool, fixture &Fixture) bool {
	unsafe {
		observer := C.open(c'/proc/slabinfo', C.O_RDONLY | C.O_CLOEXEC)
		if observer < 0 { return false }
		for _ in 0 .. 32 {
			if !cycle(fixture) {
				C.close(observer)
				return false
			}
		}
		C.usleep(13000000)
		before := &Slabs(C.alloca(usize(sizeof(Slabs))))
		after := &Slabs(C.alloca(usize(sizeof(Slabs))))
		if !snapshot(observer, before) {
			C.close(observer)
			return false
		}
		for _ in 0 .. 200 {
			if !cycle(fixture) {
				C.close(observer)
				return false
			}
		}
		C.usleep(13000000)
		if !snapshot(observer, after) {
			C.close(observer)
			return false
		}
		mut good := before.rows == after.rows && before.large == after.large
		for index in 0 .. int(before.rows) {
			if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] {
				good = false
			}
			C.printf(c'LINUX AFFABI SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[index], before.live[index], after.live[index])
		}
		C.printf(c'LINUX AFFABI STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if good {
			&char(c'PASS')
		} else {
			&char(c'FAIL')
		})
		C.fflush(nil)
		if C.close(observer) != 0 { good = false }
		return good
	}
}

fn qualify(counts &Counts, ordinary bool, reference bool, result_fd i32) bool {
	unsafe {
		C.alarm(600)
		fixture := &Fixture(C.alloca(usize(sizeof(Fixture))))
		*fixture = Fixture{}
		mut bits := u64(0)
		initial := query(false, 0, 8, u64(&bits))
		if initial.ret != 8 || initial.code != 0 || bits == 0 || bits & (u64(1) << 63) != 0 {
			fatal(1)
		}
		fixture.all = bits
		fixture.low = bits & (~bits + 1)
		// Linux's configured bitmap may exceed its online CPUs. Measure its ABI
		// width before checking clipped copies; the native bitmap remains 8 bytes.
		wide := &u8(C.alloca(usize(4096)))
		C.memset(wide, 0xa5, 4096)
		width := query(false, 0, 4096, u64(wide))
		if width.code != 0 || width.ret < 8 || width.ret > 4096 || width.ret % 8 != 0 { fatal(32) }
		fixture.mask_bytes = u32(width.ret)
		if !reference && fixture.mask_bytes != 8 { fatal(35) }
		mut first := u64(0)
		C.memcpy(&first, wide, 8)
		if first != fixture.all || !bytes(wide, 4096, 0, i32(width.ret)) { fatal(33) }
		for index in 8 .. int(width.ret) { if wide[index] != 0 { fatal(34) } }
		peer_start(fixture, result_fd)
		if C.syscall(C.SYS_prctl, 8, 1, 0, 0, 0) != 0 { fatal(2) }
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) {
			fatal(3)
		}
		uid := if ordinary { u32(1000) } else { u32(0) }
		if C.getuid() != uid || C.geteuid() != uid || C.getgid() != uid || C.getegid() != uid {
			fatal(4)
		}
		cap_snapshot(&fixture.initial[0])
		command := &i32(C.alloca(usize(2 * sizeof(i32))))
		ready := &i32(C.alloca(usize(2 * sizeof(i32))))
		if C.pipe2(command, C.O_CLOEXEC) != 0 || C.pipe2(ready, C.O_CLOEXEC) != 0 { fatal(5) }
		context := &Worker(C.alloca(usize(sizeof(Worker))))
		*context = Worker{ ready: ready[1], command: command[0] }
		thread_handle := &C.pthread_t(C.alloca(usize(sizeof(C.pthread_t))))
		if C.pthread_create(thread_handle, nil, worker, context) != 0 { fatal(6) }
		if C.read(ready[0], &fixture.worker, sizeof(i32)) != isize(sizeof(i32)) || fixture.worker == C.getpid() || fixture.worker <= 0 {
			fatal(7)
		}
		C.close(ready[0])
		C.close(ready[1])
		child := C.fork()
		if child < 0 { fatal(8) }
		if child == 0 { C._exit(0) }
		mut status := i32(-1)
		if C.waitpid(child, &status, 0) != child || status != 0 { fatal(9) }
		page := usize(C.sysconf(C._SC_PAGESIZE))
		if page < 4096 || page > 16384 { fatal(10) }
		mapping := &u8(C.mmap(nil, 3 * page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
		if mapping == &u8(usize(-1)) { fatal(11) }
		if C.mprotect(mapping + 2 * page, page, C.PROT_NONE) != 0 { fatal(12) }
		C.printf(c'LINUX AFFABI TOPOLOGY: ordinary=%d mask=%lx worker=%d peer=%d page=%lu mask_bytes=%u\n', i32(ordinary), fixture.all, fixture.worker, fixture.peer, u64(page), fixture.mask_bytes)
		C.fflush(nil)
		matrix(counts, ordinary, fixture, child, mapping, page)
		mut good := counts.failures[0] == 0 && counts.failures[1] == 0 && counts.failures[2] == 0 && counts.failures[3] == 0
		if good && !reference && !storage(ordinary, fixture) { good = false }
		capability(fixture.initial[0].effective & (u32(1) << 23) != 0)
		for source in [i32(0), fixture.worker, fixture.peer]! {
			record(counts, 3, observed(source, fixture.all), ordinary, u64(source), 0, 0, -1, Query{}, 0)
		}
		record(counts, 3, cap_match(fixture), ordinary, 0, 0, 0, -1, Query{}, 0)
		mut byte := u8(0xd1)
		if C.write(command[1], &byte, 1) != 1 || C.pthread_join(*thread_handle, nil) != 0 || context.failed != 0 {
			fatal(13)
		}
		C.close(command[0])
		C.close(command[1])
		if C.write(fixture.peer_fd, &byte, 1) != 1 { fatal(14) }
		C.close(fixture.peer_fd)
		status = -1
		if C.waitpid(fixture.peer, &status, 0) != fixture.peer || status != 0 { fatal(15) }
		if C.munmap(mapping, 3 * page) != 0 { fatal(16) }
		for kind in 0 .. 4 {
			C.printf(c'LINUX AFFABI CASES: ordinary=%d kind=%d calls=%lu failures=%lu\n', i32(ordinary), kind, counts.calls[kind], counts.failures[kind])
			if counts.failures[kind] != 0 { good = false }
		}
		C.alarm(0)
		C.fflush(nil)
		return good
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference := argc == 2 && C.strcmp(argv[1], c'--reference') == 0
		mut good := true
		for ordinary in [false, true]! {
			ends := &i32(C.alloca(usize(2 * sizeof(i32))))
			if C.pipe2(ends, C.O_CLOEXEC) != 0 { fatal(14) }
			child := C.fork()
			if child < 0 { fatal(15) }
			if child == 0 {
				C.close(ends[0])
				counts := &Counts(C.alloca(usize(sizeof(Counts))))
				*counts = Counts{}
				passed := qualify(counts, ordinary, reference, ends[1])
				sent := C.write(ends[1], counts, usize(sizeof(Counts))) == isize(sizeof(Counts))
				C.close(ends[1])
				C._exit(if passed && sent { 0 } else { 1 })
			}
			C.close(ends[1])
			counts := &Counts(C.alloca(usize(sizeof(Counts))))
			received := C.read(ends[0], counts, usize(sizeof(Counts))) == isize(sizeof(Counts))
			C.close(ends[0])
			mut status := i32(-1)
			completed := C.waitpid(child, &status, 0) == child && status == 0
			if !received || !completed { good = false }
			if received {
				for kind in 0 .. 4 {
					C.printf(c'LINUX AFFABI FINAL: ordinary=%d kind=%d calls=%lu failures=%lu\n', i32(ordinary), kind, counts.calls[kind], counts.failures[kind])
					if counts.failures[kind] != 0 { good = false }
				}
			}
			C.fflush(nil)
		}
		if !good {
			C.puts(c'LINUX AFFABI FAIL: query layout, arguments or state')
			C.fflush(nil)
			return 1
		}
		C.puts(if reference { c'LINUX AFFABI REFERENCE: PASS' } else { c'LINUX AFFABI: PASS' })
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
