// SPDX-License-Identifier: GPL-2.0-or-later
module niceabifixture

#define __EXPORTED_HEADERS__
#include <linux/capability.h>
#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <sched.h>
#include <stdio.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct Counts {
mut:
	calls    [4]u64
	failures [4]u64
}

struct Message {
mut:
	action i32
	first  i32
	second i32
	nice   i32
}

struct Fixture {
	request  i32
	reply    i32
	same     i32
	same_fd  i32
	cross    i32
	cross_fd i32
}

struct Slabs {
mut:
	sizes [32]u64
	live  [32]u64
	rows  i32
	large u64
}

struct Limit {
mut:
	cur u64
	max u64
}

struct C.sched_param {
mut:
	sched_priority i32
}

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

struct Result {
	ret  isize
	code i32
}

fn C.alloca(usize) voidptr
fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.getpriority(i32, u32) i32
fn C.setpriority(i32, u32, i32) i32
fn C.getpid() i32
fn C.getuid() u32
fn C.geteuid() u32
fn C.getgid() u32
fn C.getegid() u32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.pipe2(&i32, i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.open(&char, i32, ...) i32
fn C.pread(i32, voidptr, usize, i64) isize
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.alarm(u32) u32
fn C.usleep(u32) i32
fn C.pause() i32
fn C.strcmp(&char, &char) i32
fn C.memset(voidptr, i32, usize) voidptr
fn C.sscanf(&char, &char, ...) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32

fn fatal(stage i32) {
	C.printf(c'LINUX NICEABI FAIL: setup/protocol stage=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil })
	C._exit(1)
}

fn cap_state(privileged bool) bool {
	unsafe {
		mut header := C.__user_cap_header_struct{ version: 0x20080522 }
		mut data := [2]C.__user_cap_data_struct{}
		return C.syscall(C.SYS_capget, &header, &data[0]) == 0
			&& (data[0].effective & (u32(1) << 23) != 0) == privileged
	}
}

fn limit_state() bool {
	unsafe {
		mut value := Limit{}
		return C.syscall(C.SYS_prlimit64, 0, C.RLIMIT_NICE, 0, &value) == 0 && value.cur == 0 && value.max == 0
	}
}

fn state(pid i32, policy i32, nice i32) bool {
	unsafe {
		mut parameter := C.sched_param{ sched_priority: 42 }
		err := C.__errno_location()
		*err = 0
		raw := C.syscall(C.SYS_getpriority, u64(0), u64(i64(pid)))
		raw_error := *err
		*err = 0
		libc := C.getpriority(C.PRIO_PROCESS, u32(pid))
		libc_error := *err
		return raw == 20 - nice && raw_error == 0 && libc == nice && libc_error == 0
			&& C.syscall(C.SYS_sched_getscheduler, u64(i64(pid))) == policy
			&& C.syscall(C.SYS_sched_getparam, u64(i64(pid)), &parameter) == 0 && parameter.sched_priority == 0
	}
}

fn retained(fixture &Fixture, target i32, policy i32, nice i32) bool {
	unsafe {
		for pid in [i32(0), fixture.same, fixture.cross]! {
			changed := target == pid || (pid == 0 && target == C.getpid())
			if !state(pid, if changed { policy } else { C.SCHED_OTHER }, if changed {
				nice
			} else {
				i32(0)
			}) {
				return false
			}
		}
		return true
	}
}

fn command(fixture &Fixture, action i32, first i32, second i32, nice i32) {
	unsafe {
		mut message := Message{ action: action, first: first, second: second, nice: nice }
		mut answer := i32(-1)
		if C.write(fixture.request, &message, sizeof(Message)) != isize(sizeof(Message))
			|| C.read(fixture.reply, &answer, sizeof(i32)) != isize(sizeof(i32)) || answer != 0x4e494345 {
			fatal(1)
		}
	}
}

fn setup(fixture &Fixture, pid i32, policy i32, nice i32) {
	command(fixture, 1, if pid == 0 { C.getpid() } else { pid }, policy, nice)
	if !retained(fixture, pid, policy, nice) { fatal(2) }
}

fn peer(uid u32, request i32, reply i32) (i32, i32) {
	unsafe {
		mut control := [i32(-1), i32(-1)]!
		mut ready := [i32(-1), i32(-1)]!
		if C.pipe2(&control[0], C.O_CLOEXEC) != 0 || C.pipe2(&ready[0], C.O_CLOEXEC) != 0 {
			fatal(3)
		}
		child := C.fork()
		if child < 0 { fatal(4) }
		if child == 0 {
			C.close(request)
			C.close(reply)
			C.close(control[1])
			C.close(ready[0])
			C.alarm(600)
			if C.setgroups(0, nil) != 0 || C.setgid(uid) != 0 || C.setuid(uid) != 0
				|| C.getuid() != uid || C.geteuid() != uid || C.getgid() != uid || C.getegid() != uid || !limit_state() {
				fatal(5)
			}
			mut byte := u8(0xaf)
			if C.write(ready[1], &byte, 1) != 1 { fatal(6) }
			C.close(ready[1])
			passed := C.read(control[0], &byte, 1) == 1 && byte == 0xd1
			C.close(control[0])
			C._exit(if passed { 0 } else { 1 })
		}
		C.close(control[0])
		C.close(ready[1])
		mut byte := u8(0)
		if C.read(ready[0], &byte, 1) != 1 || byte != 0xaf { fatal(7) }
		C.close(ready[0])
		return child, control[1]
	}
}

fn word(value i32, form i32, position i32) u64 {
	if form == 1 { return u64(u32(value)) }
	if form == 5 || form == position + 2 { return 0x1234567800000000 | u64(u32(value)) }
	if form == 6 { return 0xffffffff00000000 | u64(u32(value)) }
	return u64(i64(value))
}

fn raw(set bool, which i32, who i32, nice i32, form i32) Result {
	unsafe {
		err := C.__errno_location()
		*err = 0
		ret := C.syscall(if set { isize(C.SYS_setpriority) } else { isize(C.SYS_getpriority) }, word(which, form, 0), word(who, form, 1), word(nice, form, 2), u64(-1))
		return Result{ret, *err}
	}
}

fn record(counts &Counts, kind i32, good bool, ordinary bool, which i32, who i32, nice i32, form i32, actual Result, code i32) {
	unsafe {
		mut c := &Counts(counts)
		c.calls[kind]++
		if !good {
			c.failures[kind]++
			if c.failures[kind] <= 4 {
				C.printf(c'LINUX NICEABI DETAIL: ordinary=%d kind=%d which=%d who=%d nice=%d form=%d result=%ld/%d expected_errno=%d\n', i32(ordinary), kind, which, who, nice, form, actual.ret, actual.code, code)
				C.fflush(nil)
			}
		}
	}
}

fn policy(index i32) i32 {
	return if index == 0 {
		i32(C.SCHED_OTHER)
	} else if index == 1 {
		i32(C.SCHED_BATCH)
	} else {
		i32(C.SCHED_IDLE)
	}
}

fn target(index i32, fixture &Fixture, dead i32) i32 {
	return match index {
		0 { i32(0) }
		1 { C.getpid() }
		2 { fixture.same }
		3 { fixture.cross }
		4 { i32(0x7fffffff) }
		5 { dead }
		6 { i32(-1) }
		else { i32(-2147483648) }
	}
}

fn set_error(ordinary bool, index i32, nice i32) i32 {
	return if index >= 4 {
		i32(C.ESRCH)
	} else if ordinary && index == 3 {
		i32(C.EPERM)
	} else if ordinary && nice < 0 {
		i32(C.EACCES)
	} else {
		i32(0)
	}
}

fn clamped(nice i32) i32 {
	return if nice < -20 {
		i32(-20)
	} else if nice > 19 {
		i32(19)
	} else {
		nice
	}
}

fn setter(counts &Counts, fixture &Fixture, ordinary bool, index i32, dead i32, p i32, nice i32, form i32, libc bool) {
	unsafe {
		pid := target(index, fixture, dead)
		live := index < 4
		if live { setup(fixture, pid, p, 0) }
		code := set_error(ordinary, index, nice)
		mut result := Result{}
		if libc {
			err := C.__errno_location()
			*err = 0
			ret := C.setpriority(C.PRIO_PROCESS, u32(pid), nice)
			result = Result{isize(ret), *err}
		} else {
			result = raw(true, 0, pid, nice, form)
		}
		expected_nice := if code == 0 { clamped(nice) } else { i32(0) }
		good := result.ret == if code == 0 { isize(0) } else { isize(-1) } && result.code == code
			&& retained(fixture, if live { pid } else { i32(-1) }, if live {
				p
			} else {
				C.SCHED_OTHER
			}, expected_nice)
		record(counts, if libc { 3 } else { 1 }, good, ordinary, 0, pid, nice, form, result, code)
		if live { setup(fixture, pid, C.SCHED_OTHER, 0) }
	}
}

fn matrix(counts &Counts, ordinary bool, fixture &Fixture, dead i32) {
	unsafe {
		for config in 0 .. 3 {
			p := policy(i32(config))
			for nice in [i32(-20), -1, 0, 1, 19]! {
				for index in 0 .. 8 {
					pid := target(i32(index), fixture, dead)
					live := index < 4
					if live { setup(fixture, pid, p, nice) }
					for form in 0 .. 7 {
						result := raw(false, 0, pid, 0, i32(form))
						code := if live { i32(0) } else { i32(C.ESRCH) }
						good := result.ret == if live { isize(20 - nice) } else { isize(-1) } && result.code == code
							&& retained(fixture, if live { pid } else { i32(-1) }, if live {
								p
							} else {
								C.SCHED_OTHER
							}, if live { nice } else { i32(0) })
						record(counts, 0, good, ordinary, 0, pid, nice, i32(form), result, code)
					}
					if live { setup(fixture, pid, C.SCHED_OTHER, 0) }
				}
			}
			for index in 0 .. 8 {
				for nice in [i32(-2147483648), -21, -20, -1, 0, 1, 19, 20, 2147483647]! {
					for form in 0 .. 7 {
						setter(counts, fixture, ordinary, i32(index), dead, p, nice, i32(form), false)
					}
					setter(counts, fixture, ordinary, i32(index), dead, p, nice, -1, true)
				}
			}
		}
		for which in [i32(-1), 3, -2147483648, 2147483647]! {
			for index in 0 .. 8 {
				pid := target(i32(index), fixture, dead)
				for nice in [i32(-2147483648), -21, -20, -1, 0, 1, 19, 20, 2147483647]! {
					for form in 0 .. 7 {
						for set in [false, true]! {
							result := raw(set, which, pid, nice, i32(form))
							good := result.ret == -1 && result.code == C.EINVAL && retained(fixture, -1, C.SCHED_OTHER, 0)
							record(counts, 2, good, ordinary, which, pid, nice, i32(form), result, C.EINVAL)
						}
					}
				}
			}
		}
	}
}

fn cycle(fixture &Fixture, ordinary bool) bool {
	unsafe {
		for form in 0 .. 7 {
			for index in 0 .. 4 {
				pid := target(i32(index), fixture, 0)
				getter := raw(false, 0, pid, 0, i32(form))
				setter := raw(true, 0, pid, 19, i32(form))
				code := if ordinary && index == 3 { i32(C.EPERM) } else { i32(0) }
				if getter.ret != 1 || getter.code != 0 || setter.ret != if code == 0 {
					isize(0)
				} else {
					isize(-1)
				} || setter.code != code {
					return false
				}
			}
			for pid in [i32(-1), -2147483648, 2147483647]! {
				for set in [false, true]! {
					result := raw(set, 0, pid, -2147483648, i32(form))
					if result.ret != -1 || result.code != C.ESRCH { return false }
				}
			}
			for set in [false, true]! {
				result := raw(set, 3, 0, 19, i32(form))
				if result.ret != -1 || result.code != C.EINVAL { return false }
			}
		}
		return state(0, C.SCHED_OTHER, 19) && state(fixture.same, C.SCHED_OTHER, 19) && state(fixture.cross, C.SCHED_OTHER, 19)
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

fn storage(fixture &Fixture, ordinary bool) bool {
	unsafe {
		observer := C.open(c'/proc/slabinfo', C.O_RDONLY | C.O_CLOEXEC)
		if observer < 0 { return false }
		defer { C.close(observer) }
		for _ in 0 .. 32 { if !cycle(fixture, ordinary) { return false } }
		C.usleep(13000000)
		before := &Slabs(C.alloca(usize(sizeof(Slabs))))
		after := &Slabs(C.alloca(usize(sizeof(Slabs))))
		if !snapshot(observer, before) { return false }
		for _ in 0 .. 200 { if !cycle(fixture, ordinary) { return false } }
		C.usleep(13000000)
		if !snapshot(observer, after) { return false }
		mut good := before.rows == after.rows && before.large == after.large
		for index in 0 .. int(before.rows) {
			if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] {
				good = false
			}
			C.printf(c'LINUX NICEABI SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[index], before.live[index], after.live[index])
		}
		C.printf(c'LINUX NICEABI STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if good {
			&char(c'PASS')
		} else {
			&char(c'FAIL')
		})
		C.fflush(nil)
		return good
	}
}

fn qualify(counts &Counts, ordinary bool, reference bool, request i32, reply i32) bool {
	unsafe {
		C.alarm(600)
		uid := if ordinary { u32(1000) } else { u32(0) }
		same, same_fd := peer(uid, request, reply)
		cross, cross_fd := peer(1001, request, reply)
		mut fixture := Fixture{ request: request, reply: reply, same: same, same_fd: same_fd, cross: cross, cross_fd: cross_fd }
		command(&fixture, 2, same, cross, 0)
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(uid) != 0 || C.setuid(uid) != 0) {
			fatal(8)
		}
		if C.getuid() != uid || C.geteuid() != uid || C.getgid() != uid || C.getegid() != uid {
			fatal(9)
		}
		record(counts, 3, cap_state(!ordinary), ordinary, 0, 0, 0, -1, Result{}, 0)
		record(counts, 3, limit_state(), ordinary, 0, 0, 0, -1, Result{}, 0)
		dead := C.fork()
		if dead < 0 { fatal(10) }
		if dead == 0 {
			C.close(request)
			C.close(reply)
			C._exit(0)
		}
		mut status := i32(-1)
		if C.waitpid(dead, &status, 0) != dead || status != 0 { fatal(11) }
		C.printf(c'LINUX NICEABI TOPOLOGY: ordinary=%d uid=%u self=%d same=%d cross=%d reaped=%d cap_sys_nice=%d\n', i32(ordinary), uid, C.getpid(), same, cross, dead, i32(!ordinary))
		C.fflush(nil)
		matrix(counts, ordinary, &fixture, dead)
		mut good := counts.failures[0] == 0 && counts.failures[1] == 0 && counts.failures[2] == 0 && counts.failures[3] == 0
		if good && !reference {
			for pid in [C.getpid(), same, cross]! { command(&fixture, 1, pid, C.SCHED_OTHER, 19) }
			if !storage(&fixture, ordinary) { good = false }
			for pid in [C.getpid(), same, cross]! { command(&fixture, 1, pid, C.SCHED_OTHER, 0) }
		}
		for pid in [i32(0), same, cross]! {
			record(counts, 3, state(pid, C.SCHED_OTHER, 0), ordinary, 0, pid, 0, -1, Result{}, 0)
		}
		record(counts, 3, cap_state(!ordinary), ordinary, 0, 0, 0, -1, Result{}, 0)
		record(counts, 3, limit_state(), ordinary, 0, 0, 0, -1, Result{}, 0)
		mut byte := u8(0xd1)
		for fd in [same_fd, cross_fd]! {
			if C.write(fd, &byte, 1) != 1 || C.close(fd) != 0 { fatal(12) }
		}
		for pid in [same, cross]! {
			status = -1
			if C.waitpid(pid, &status, 0) != pid || status != 0 { fatal(13) }
		}
		for kind in 0 .. 4 {
			C.printf(c'LINUX NICEABI CASES: ordinary=%d kind=%d calls=%lu failures=%lu\n', i32(ordinary), kind, counts.calls[kind], counts.failures[kind])
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
		if sizeof(Message) != 16 || sizeof(Counts) != 64 { fatal(14) }
		reference := argc == 2 && C.strcmp(argv[1], c'--reference') == 0
		mut good := true
		for ordinary in [false, true]! {
			mut request := [i32(-1), i32(-1)]!
			mut reply := [i32(-1), i32(-1)]!
			if C.pipe2(&request[0], C.O_CLOEXEC) != 0 || C.pipe2(&reply[0], C.O_CLOEXEC) != 0 {
				fatal(15)
			}
			child := C.fork()
			if child < 0 { fatal(16) }
			if child == 0 {
				C.close(request[0])
				C.close(reply[1])
				counts := &Counts(C.alloca(usize(sizeof(Counts))))
				*counts = Counts{}
				passed := qualify(counts, ordinary, reference, request[1], reply[0])
				mut message := Message{ action: 3 }
				sent := C.write(request[1], &message, sizeof(Message)) == isize(sizeof(Message)) && C.write(request[1], counts, sizeof(Counts)) == isize(sizeof(Counts))
				C.close(request[1])
				C.close(reply[0])
				C._exit(if passed && sent { 0 } else { 1 })
			}
			C.close(request[1])
			C.close(reply[0])
			mut message := Message{}
			counts := &Counts(C.alloca(usize(sizeof(Counts))))
			*counts = Counts{}
			mut same := i32(0)
			mut cross := i32(0)
			mut received := false
			for {
				if C.read(request[0], &message, sizeof(Message)) != isize(sizeof(Message)) {
					good = false
					break
				}
				if message.action == 3 {
					received = C.read(request[0], counts, sizeof(Counts)) == isize(sizeof(Counts))
					break
				}
				if message.action == 2 {
					if same != 0 || cross != 0 || message.first <= 0 || message.second <= 0 || message.first == message.second || message.first == child || message.second == child {
						fatal(17)
					}
					same = message.first
					cross = message.second
				} else if message.action == 1 {
					if message.first <= 0 || (message.first != child && message.first != same && message.first != cross)
						|| (message.second != C.SCHED_OTHER && message.second != C.SCHED_BATCH && message.second != C.SCHED_IDLE)
						|| message.nice < -20 || message.nice > 19 {
						fatal(18)
					}
					mut parameter := C.sched_param{}
					// Canonical signed64 setup is independent of the low32 words under test.
					if !cap_state(true) || C.syscall(C.SYS_setpriority, u64(0), u64(i64(message.first)), u64(i64(message.nice))) != 0
						|| C.syscall(C.SYS_sched_setscheduler, u64(i64(message.first)), u64(i64(message.second)), &parameter) != 0 || !state(message.first, message.second, message.nice) {
						fatal(19)
					}
				} else {
					fatal(20)
				}
				mut answer := i32(0x4e494345)
				if C.write(reply[1], &answer, sizeof(i32)) != isize(sizeof(i32)) { fatal(21) }
			}
			C.close(request[0])
			C.close(reply[1])
			mut status := i32(-1)
			if !received || C.waitpid(child, &status, 0) != child || status != 0 { good = false }
			if received {
				for kind in 0 .. 4 {
					C.printf(c'LINUX NICEABI FINAL: ordinary=%d kind=%d calls=%lu failures=%lu\n', i32(ordinary), kind, counts.calls[kind], counts.failures[kind])
					if counts.failures[kind] != 0 { good = false }
				}
			}
			C.fflush(nil)
		}
		if !good {
			C.puts(c'LINUX NICEABI FAIL: priority words, errors or state')
			C.fflush(nil)
			return 1
		}
		C.puts(if reference { c'LINUX NICEABI REFERENCE: PASS' } else { c'LINUX NICEABI: PASS' })
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
