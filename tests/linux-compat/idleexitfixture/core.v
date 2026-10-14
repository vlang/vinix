// SPDX-License-Identifier: GPL-2.0-or-later
module idleexitfixture

#define __EXPORTED_HEADERS__
#include <linux/capability.h>
#include <sys/resource.h>
#include <alloca.h>
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
	C.printf(c'LINUX IDLEEXIT FAIL: setup or parent/child protocol stage=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil })
	C._exit(1)
}

fn record(counts &Counts, kind i32, good bool, ordinary bool, pid u64, size u64, flags u64, form i32, result Query, expected i32) {
	unsafe {
		mut value := &Counts(counts)
		value.calls[kind]++
		if !good {
			value.failures[kind]++
			if value.failures[kind] <= 4 {
				C.printf(c'LINUX IDLEEXIT DETAIL: ordinary=%d kind=%d pid=%lx nice=%lx flags=%lx form=%d call=%lu ret=%ld errno=%d expected=%d\n', i32(ordinary), kind, pid, size, flags, form, value.calls[kind], result.ret, result.code, expected)
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

struct Limit {
mut:
	cur u64
	max u64
}

struct Message {
mut:
	action i32
	first  i32
	second i32
	value  i32
}

struct Fixture {
mut:
	request  i32
	reply    i32
	same     i32
	same_fd  i32
	cross    i32
	cross_fd i32
	initial  [2]C.__user_cap_data_struct
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

fn C.getgid() u32
fn C.getegid() u32
fn C.getpriority(i32, u32) i32

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
		if C.syscall(C.SYS_capset, header, data) != 0 || C.syscall(C.SYS_capget, header, data) != 0 || (data[0].effective & (u32(1) << 23) != 0) != on {
			fatal(21)
		}
	}
}

fn cap_snapshot(destination &C.__user_cap_data_struct) {
	unsafe {
		header := &C.__user_cap_header_struct(C.alloca(usize(sizeof(C.__user_cap_header_struct))))
		*header = C.__user_cap_header_struct{ version: 0x20080522 }
		if C.syscall(C.SYS_capget, header, destination) != 0 { fatal(22) }
	}
}

fn cap_match(fixture &Fixture) bool {
	unsafe {
		data := &C.__user_cap_data_struct(C.alloca(usize(2 * sizeof(C.__user_cap_data_struct))))
		cap_snapshot(data)
		return C.memcmp(data, &fixture.initial[0], usize(2 * sizeof(C.__user_cap_data_struct))) == 0
	}
}

fn limits(resource i32, current u64, maximum u64) {
	unsafe {
		value := &Limit(C.alloca(usize(sizeof(Limit))))
		*value = Limit{current, maximum}
		if C.syscall(C.SYS_prlimit64, 0, resource, value, 0) != 0 { fatal(23) }
		*value = Limit{}
		if C.syscall(C.SYS_prlimit64, 0, resource, 0, value) != 0 || value.cur != current || value.max != maximum {
			fatal(24)
		}
	}
}

fn limit_state(resource i32, current u64, maximum u64) bool {
	unsafe {
		value := &Limit(C.alloca(usize(sizeof(Limit))))
		*value = Limit{}
		return C.syscall(C.SYS_prlimit64, 0, resource, 0, value) == 0 && value.cur == current && value.max == maximum
	}
}

fn state(pid i32, policy i32, priority i32, nice i32) bool {
	unsafe {
		out := &C.sched_param(C.alloca(usize(sizeof(C.sched_param))))
		out.sched_priority = 42
		if C.syscall(C.SYS_sched_getscheduler, pid) != policy || C.syscall(C.SYS_sched_getparam, pid, out) != 0 || out.sched_priority != priority || C.syscall(C.SYS_getpriority, 0, pid) != 20 - nice {
			return false
		}
		slot := C.__errno_location()
		*slot = 0
		actual := C.getpriority(C.PRIO_PROCESS, u32(pid))
		if actual != nice || *slot != 0 { return false }
		data := &u8(C.alloca(usize(80)))
		C.memset(data, 0xa5, 80)
		attr := &Attr(data + 8)
		// RT sched_attr nice is a separate getter gap; raw/musl getpriority
		// above still verify the actual retained nice for every policy.
		check_nice := policy != C.SCHED_FIFO && policy != C.SCHED_RR
		if C.syscall(C.SYS_sched_getattr, pid, attr, 56, 0) != 0 || attr.size != 56 || attr.policy != u32(policy) || attr.priority != u32(priority) || (check_nice && attr.nice != nice) || attr.flags != 0 || !bytes(data, 80, 8, 56) {
			return false
		}
		return true
	}
}

fn command(fixture &Fixture, action i32, first i32, second i32, detail i32) {
	unsafe {
		value := &Message(C.alloca(usize(sizeof(Message))))
		*value = Message{ action: action, first: first, second: second, value: detail }
		if C.write(fixture.request, value, sizeof(Message)) != isize(sizeof(Message)) { fatal(25) }
		mut reply := i32(-1)
		if C.read(fixture.reply, &reply, sizeof(i32)) != isize(sizeof(i32)) || reply != 0x4e494345 {
			fatal(26)
		}
	}
}

fn restore(fixture &Fixture, pid i32) {
	actual := if pid == 0 { C.getpid() } else { pid }
	command(fixture, 1, actual, 0, 0)
	if !state(actual, C.SCHED_OTHER, 0, 0) { fatal(27) }
}

fn peer_start(uid u32, soft u64, request i32, reply i32) (i32, i32) {
	unsafe {
		command_fd := &i32(C.alloca(usize(2 * sizeof(i32))))
		ready := &i32(C.alloca(usize(2 * sizeof(i32))))
		if C.pipe2(command_fd, C.O_CLOEXEC) != 0 || C.pipe2(ready, C.O_CLOEXEC) != 0 { fatal(28) }
		child := C.fork()
		if child < 0 { fatal(29) }
		if child == 0 {
			C.close(request)
			C.close(reply)
			C.close(command_fd[1])
			C.close(ready[0])
			C.alarm(600)
			limits(C.RLIMIT_RTPRIO, 1, 99)
			limits(C.RLIMIT_NICE, soft, 40)
			if C.setgroups(0, nil) != 0 || C.setgid(uid) != 0 || C.setuid(uid) != 0 || C.getuid() != uid || C.geteuid() != uid || C.getgid() != uid || C.getegid() != uid {
				fatal(30)
			}
			mut byte := u8(0xaf)
			if C.write(ready[1], &byte, 1) != 1 { fatal(31) }
			C.close(ready[1])
			good := C.read(command_fd[0], &byte, 1) == 1 && byte == 0xd1
			C.close(command_fd[0])
			C._exit(if good { 0 } else { 1 })
		}
		C.close(command_fd[0])
		C.close(ready[1])
		mut byte := u8(0)
		if C.read(ready[0], &byte, 1) != 1 || byte != 0xaf { fatal(32) }
		C.close(ready[0])
		return child, command_fd[1]
	}
}

fn attribute(op i32) bool { return op == 3 || op == 4 || op == 5 || op == 9 || op == 10 }

fn requested(op i32, old i32) i32 {
	return match op {
		0, 3 { i32(C.SCHED_OTHER) }
		1, 4 { i32(C.SCHED_BATCH) }
		2, 5 { i32(C.SCHED_IDLE) }
		7, 9 { i32(C.SCHED_FIFO) }
		8, 10 { i32(C.SCHED_RR) }
		else { old }
	}
}

fn query(op i32, pid u64, pointer u64, policy u64, flags u64) Query {
	unsafe {
		slot := C.__errno_location()
		*slot = 0
		ret := if op == 6 {
			C.syscall(C.SYS_sched_setparam, pid, pointer, policy, u64(-1))
		} else if attribute(op) {
			C.syscall(C.SYS_sched_setattr, pid, pointer, flags, u64(-1))
		} else {
			C.syscall(C.SYS_sched_setscheduler, pid, policy, pointer, u64(-1))
		}
		return Query{ret, *slot}
	}
}

fn checked(counts &Counts, ordinary bool, fixture &Fixture, source i32, live bool, cross bool, nice_limit u64, rt_limit u64, cap bool, op i32, old_policy i32, old_nice i32, wanted i32, priority i32, form i32, variant i32, kind i32, invalid_flags bool, mapping &u8, page usize) {
	unsafe {
		if live {
			command(fixture, 4, if source == 0 { C.getpid() } else { source }, old_policy, old_nice)
			if !state(source, old_policy, 0, old_nice) { fatal(33) }
		}
		if C.mprotect(mapping + page, page, C.PROT_READ | C.PROT_WRITE) != 0 { fatal(34) }
		C.memset(mapping, 0, 2 * page)
		pointer := match form {
			1 { mapping + page + 8 }
			2 { mapping + page + 9 }
			3 { mapping + 2 * page }
			4 { &u8(usize(0)) }
			else { mapping + 8 }
		}
		policy := requested(op, old_policy)
		value := &Attr(C.alloca(usize(sizeof(Attr))))
		*value = Attr{ size: 56, policy: u32(policy), nice: wanted, priority: u32(priority) }
		parameter := &i32(C.alloca(usize(sizeof(i32))))
		*parameter = priority
		before := &u8(C.alloca(usize(56)))
		accessible := form < 3
		if accessible {
			if attribute(op) {
				C.memcpy(pointer, value, 56)
			} else {
				C.memcpy(pointer, parameter, 4)
			}
			C.memset(pointer - 8, 0xa5, 8)
			C.memset(pointer + 56, 0xa5, 8)
			C.memcpy(before, pointer, 56)
		}
		if C.mprotect(mapping + page, page, C.PROT_READ) != 0 { fatal(35) }
		pid := if variant == 1 {
			u64(u32(source)) | 0x1234567800000000
		} else if variant == 2 {
			u64(u32(source)) | 0xffffffff00000000
		} else {
			u64(i64(source))
		}
		policy_word := u64(u32(policy)) | if variant == 3 {
			u64(0xffffffff00000000)
		} else {
			u64(0)
		}
		flags := (if invalid_flags { u64(1) } else { u64(0) }) | if variant == 3 {
			u64(0xffffffff00000000)
		} else {
			u64(0)
		}
		limit := if source == fixture.same {
			u64(20)
		} else if cross {
			u64(40)
		} else {
			nice_limit
		}
		rtp := if source == fixture.same || cross { u64(1) } else { rt_limit }
		clamped := if wanted < -20 {
			i32(-20)
		} else if wanted > 19 {
			i32(19)
		} else {
			wanted
		}
		rt := policy == C.SCHED_FIFO || policy == C.SCHED_RR
		fair := policy == C.SCHED_OTHER || policy == C.SCHED_BATCH
		code := if source < 0 || form == 4 || (attribute(op) && invalid_flags) {
			i32(C.EINVAL)
		} else if form == 3 {
			i32(C.EFAULT)
		} else if !live {
			i32(C.ESRCH)
		} else if (rt && (priority < 1 || priority > 99)) || (!rt && priority != 0) {
			i32(C.EINVAL)
		} else if !cap && (cross || (old_policy == C.SCHED_IDLE && policy != C.SCHED_IDLE && u64(20 - old_nice) > limit) || (rt && rtp == 0) || (attribute(op) && fair && clamped < old_nice && u64(20 - clamped) > limit)) {
			i32(C.EPERM)
		} else {
			i32(0)
		}
		result := query(op, pid, u64(pointer), policy_word, flags)
		mut good := result.ret == if code == 0 { isize(0) } else { isize(-1) } && result.code == code
		if live {
			good = good && state(source, if code == 0 { policy } else { old_policy }, if code == 0 {
				priority
			} else {
				i32(0)
			}, if code == 0 && attribute(op) && fair { clamped } else { old_nice })
		}
		if source != 0 && source != C.getpid() { good = good && state(0, C.SCHED_OTHER, 0, 0) }
		if accessible {
			good = good && C.memcmp(pointer, before, 56) == 0 && bytes(pointer - 8, 8, -1, 0) && bytes(pointer + 56, 8, -1, 0)
		}
		record(counts, kind, good, ordinary, pid, u64(i64(wanted)), u64(op) | (flags << 8), form, result, code)
		if live { restore(fixture, source) }
	}
}

fn matrix(counts &Counts, ordinary bool, fixture &Fixture, dead i32, mapping &u8, page usize) {
	unsafe {
		self := C.getpid()
		limits(C.RLIMIT_RTPRIO, 0, 99)
		for soft in [u64(0), 1, 20, 39, 40]! {
			limits(C.RLIMIT_NICE, soft, 40)
			for cap in [false, true]! {
				capability(cap)
				for source in [i32(0), self, fixture.same, fixture.cross, 0x7fffffff, dead]! {
					live := source in [i32(0), self, fixture.same, fixture.cross]!
					for old_policy in [i32(C.SCHED_IDLE), C.SCHED_OTHER, C.SCHED_BATCH]! {
						for old_nice in [i32(-20), 0, 19]! {
							for op in 0 .. 7 {
								checked(counts, ordinary, fixture, source, live, source == fixture.cross, soft, 0, cap, i32(op), old_policy, old_nice, old_nice, 0, 0, 0, 0, false, mapping, page)
							}
						}
					}
				}
			}
		}
		for soft in [u64(0), 40]! {
			limits(C.RLIMIT_NICE, soft, 40)
			for cap in [false, true]! {
				capability(cap)
				for source in [i32(0), fixture.same, fixture.cross, 0x7fffffff]! {
					live := source != 0x7fffffff
					for old_policy in [i32(C.SCHED_IDLE), C.SCHED_OTHER]! {
						for old_nice in [i32(-20), 19]! {
							for op in 0 .. 7 {
								for variant in [i32(1), 2]! {
									checked(counts, ordinary, fixture, source, live, source == fixture.cross, soft, 0, cap, i32(op), old_policy, old_nice, old_nice, 0, 0, variant, 1, false, mapping, page)
								}
								for form in 1 .. 5 {
									for variant in [i32(0), 3]! {
										checked(counts, ordinary, fixture, source, live, source == fixture.cross, soft, 0, cap, i32(op), old_policy, old_nice, old_nice, 0, i32(form), variant, 2, false, mapping, page)
									}
								}
							}
						}
					}
				}
			}
		}
		for soft in [u64(0), 1, 20, 39, 40]! {
			limits(C.RLIMIT_NICE, soft, 40)
			for rt in [u64(0), 1]! {
				limits(C.RLIMIT_RTPRIO, rt, 99)
				for cap in [false, true]! {
					capability(cap)
					for source in [i32(0), fixture.same, fixture.cross, 0x7fffffff]! {
						for old_nice in [i32(-20), 0, 19]! {
							for op in [i32(7), 8, 9, 10]! {
								checked(counts, ordinary, fixture, source, source != 0x7fffffff, source == fixture.cross, soft, rt, cap, op, C.SCHED_IDLE, old_nice, old_nice, 1, 0, 0, 3, false, mapping, page)
							}
						}
					}
				}
			}
		}
		limits(C.RLIMIT_NICE, 0, 40)
		limits(C.RLIMIT_RTPRIO, 0, 99)
		capability(false)
		for source in [i32(0), self, fixture.same, fixture.cross, 0x7fffffff, dead, -1,
			i32(u32(0x80000000))]! {
			live := source in [i32(0), self, fixture.same, fixture.cross]!
			for priority in [i32(0), 1]! {
				for op in 0 .. 7 {
					for form in [i32(0), 3, 4]! {
						for variant in [i32(0), 1]! {
							checked(counts, ordinary, fixture, source, live, source == fixture.cross, 0, 0, false, i32(op), C.SCHED_IDLE, 0, 0, priority, form, variant, 3, false, mapping, page)
						}
					}
				}
			}
		}
		for source in [i32(0), self, fixture.same, fixture.cross, 0x7fffffff, dead]! {
			live := source in [i32(0), self, fixture.same, fixture.cross]!
			for op in [i32(3), 4, 5]! {
				for form in [i32(0), 3, 4]! {
					for variant in [i32(0), 1]! {
						checked(counts, ordinary, fixture, source, live, source == fixture.cross, 0, 0, false, op, C.SCHED_IDLE, 0, 0, 0, form, variant, 3, true, mapping, page)
					}
				}
			}
		}
		for cap in [false, true]! {
			capability(cap)
			for source in [i32(0), self, fixture.same, fixture.cross, 0x7fffffff, dead]! {
				live := source in [i32(0), self, fixture.same, fixture.cross]!
				for priority in [i32(-1), 0x7fffffff]! {
					for op in 0 .. 7 {
						for variant in [i32(0), 3]! {
							checked(counts, ordinary, fixture, source, live, source == fixture.cross, 0, 0, cap, i32(op), C.SCHED_IDLE, 0, 0, priority, 0, variant, 3, false, mapping, page)
						}
					}
				}
			}
		}
		for soft in [u64(0), 20, 40]! {
			limits(C.RLIMIT_NICE, soft, 40)
			for cap in [false, true]! {
				capability(cap)
				for source in [i32(0), fixture.same, fixture.cross, 0x7fffffff]! {
					for old_policy in [i32(C.SCHED_IDLE), C.SCHED_OTHER]! {
						for old_nice in [i32(-20), 0, 19]! {
							for wanted in [i32(u32(0x80000000)), -20, 0, 19, 0x7fffffff]! {
								for op in [i32(3), 4, 5]! {
									checked(counts, ordinary, fixture, source, source != 0x7fffffff, source == fixture.cross, soft, 0, cap, op, old_policy, old_nice, wanted, 0, 0, 0, 3, false, mapping, page)
								}
							}
						}
					}
				}
			}
		}
		capability(false)
	}
}

fn cycle(fixture &Fixture) bool {
	unsafe {
		value := &Attr(C.alloca(usize(sizeof(Attr))))
		*value = Attr{ size: 56, policy: u32(C.SCHED_OTHER), nice: 19 }
		capability(false)
		limits(C.RLIMIT_NICE, 39, 40)
		limits(C.RLIMIT_RTPRIO, 0, 99)
		command(fixture, 4, C.getpid(), C.SCHED_IDLE, -20)
		denied := query(3, 0, u64(value), 0, 0)
		if denied.ret != -1 || denied.code != C.EPERM || !state(0, C.SCHED_IDLE, 0, -20) {
			return false
		}
		restore(fixture, 0)
		limits(C.RLIMIT_NICE, 40, 40)
		command(fixture, 4, C.getpid(), C.SCHED_IDLE, -20)
		accepted := query(3, 0, u64(value), 0, 0)
		if accepted.ret != 0 || accepted.code != 0 || !state(0, C.SCHED_OTHER, 0, 19) {
			return false
		}
		restore(fixture, 0)
		limits(C.RLIMIT_NICE, 0, 40)
		command(fixture, 4, fixture.same, C.SCHED_IDLE, 0)
		parameter := &i32(C.alloca(usize(sizeof(i32))))
		*parameter = 0
		peer := query(0, u64(fixture.same), u64(parameter), C.SCHED_OTHER, 0)
		if peer.ret != 0 || peer.code != 0 || !state(fixture.same, C.SCHED_OTHER, 0, 0) {
			return false
		}
		restore(fixture, fixture.same)
		command(fixture, 4, C.getpid(), C.SCHED_IDLE, 0)
		same := query(6, 0, u64(parameter), 0, 0)
		if same.ret != 0 || same.code != 0 || !state(0, C.SCHED_IDLE, 0, 0) { return false }
		restore(fixture, 0)
		capability(true)
		command(fixture, 4, fixture.cross, C.SCHED_IDLE, -20)
		*value = Attr{ size: 56, policy: u32(C.SCHED_RR), priority: 1 }
		foreign := query(10, u64(fixture.cross), u64(value), 0, 0)
		if foreign.ret != 0 || foreign.code != 0 || !state(fixture.cross, C.SCHED_RR, 1, -20) {
			return false
		}
		restore(fixture, fixture.cross)
		capability(false)
		return true
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
			C.printf(c'LINUX IDLEEXIT SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[index], before.live[index], after.live[index])
		}
		C.printf(c'LINUX IDLEEXIT STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if good {
			&char(c'PASS')
		} else {
			&char(c'FAIL')
		})
		C.fflush(nil)
		if C.close(observer) != 0 { good = false }
		return good
	}
}

fn qualify(counts &Counts, ordinary bool, reference bool, request i32, reply i32) bool {
	unsafe {
		C.alarm(600)
		if sizeof(Attr) != 56 || sizeof(Limit) != 16 || sizeof(Message) != 16 { fatal(1) }
		fixture := &Fixture(C.alloca(usize(sizeof(Fixture))))
		*fixture = Fixture{ request: request, reply: reply }
		record(counts, 3, limit_state(C.RLIMIT_RTPRIO, 0, 0), ordinary, 0, 0, 0, -1, Query{}, 0)
		record(counts, 3, limit_state(C.RLIMIT_NICE, 0, 0), ordinary, 0, 0, 0, -1, Query{}, 0)
		limits(C.RLIMIT_RTPRIO, 0, 99)
		limits(C.RLIMIT_NICE, 0, 40)
		uid := if ordinary { u32(1000) } else { u32(0) }
		fixture.same, fixture.same_fd = peer_start(uid, 20, request, reply)
		fixture.cross, fixture.cross_fd = peer_start(1001, 40, request, reply)
		command(fixture, 2, fixture.same, fixture.cross, 0)
		if C.syscall(C.SYS_prctl, 8, 1, 0, 0, 0) != 0 { fatal(2) }
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) {
			fatal(3)
		}
		if C.getuid() != uid || C.geteuid() != uid || C.getgid() != uid || C.getegid() != uid {
			fatal(4)
		}
		cap_snapshot(&fixture.initial[0])
		child := C.fork()
		if child < 0 { fatal(5) }
		if child == 0 {
			C.close(request)
			C.close(reply)
			C._exit(0)
		}
		mut status := i32(-1)
		if C.waitpid(child, &status, 0) != child || status != 0 { fatal(6) }
		page := usize(C.sysconf(C._SC_PAGESIZE))
		if page < 4096 || page > 16384 { fatal(7) }
		mapping := &u8(C.mmap(nil, 3 * page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
		if mapping == &u8(usize(-1)) || C.mprotect(mapping + 2 * page, page, C.PROT_NONE) != 0 {
			fatal(8)
		}
		C.printf(c'LINUX IDLEEXIT TOPOLOGY: ordinary=%d uid=%u same=%d cross=%d page=%lu\n', i32(ordinary), uid, fixture.same, fixture.cross, u64(page))
		C.fflush(nil)
		matrix(counts, ordinary, fixture, child, mapping, page)
		mut good := counts.failures[0] == 0 && counts.failures[1] == 0 && counts.failures[2] == 0 && counts.failures[3] == 0
		if good && !reference && !storage(ordinary, fixture) { good = false }
		for source in [i32(0), fixture.same, fixture.cross]! {
			record(counts, 3, state(source, C.SCHED_OTHER, 0, 0), ordinary, u64(source), 0, 0, -1, Query{}, 0)
		}
		capability(fixture.initial[0].effective & (u32(1) << 23) != 0)
		record(counts, 3, cap_match(fixture), ordinary, 0, 0, 0, -1, Query{}, 0)
		limits(C.RLIMIT_RTPRIO, 0, 0)
		limits(C.RLIMIT_NICE, 0, 0)
		record(counts, 3, limit_state(C.RLIMIT_NICE, 0, 0), ordinary, 0, 0, 0, -1, Query{}, 0)
		record(counts, 3, limit_state(C.RLIMIT_RTPRIO, 0, 0), ordinary, 0, 0, 0, -1, Query{}, 0)
		mut byte := u8(0xd1)
		for fd in [fixture.same_fd, fixture.cross_fd]! {
			if C.write(fd, &byte, 1) != 1 || C.close(fd) != 0 { fatal(9) }
		}
		for pid in [fixture.same, fixture.cross]! {
			status = -1
			if C.waitpid(pid, &status, 0) != pid || status != 0 { fatal(10) }
		}
		if C.munmap(mapping, 3 * page) != 0 { fatal(11) }
		for kind in 0 .. 4 {
			C.printf(c'LINUX IDLEEXIT CASES: ordinary=%d kind=%d calls=%lu failures=%lu\n', i32(ordinary), kind, counts.calls[kind], counts.failures[kind])
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
			request := &i32(C.alloca(usize(2 * sizeof(i32))))
			reply := &i32(C.alloca(usize(2 * sizeof(i32))))
			if C.pipe2(request, C.O_CLOEXEC) != 0 || C.pipe2(reply, C.O_CLOEXEC) != 0 { fatal(12) }
			child := C.fork()
			if child < 0 { fatal(13) }
			if child == 0 {
				C.close(request[0])
				C.close(reply[1])
				counts := &Counts(C.alloca(usize(sizeof(Counts))))
				*counts = Counts{}
				passed := qualify(counts, ordinary, reference, request[1], reply[0])
				message := &Message(C.alloca(usize(sizeof(Message))))
				*message = Message{ action: 3 }
				sent := C.write(request[1], message, sizeof(Message)) == isize(sizeof(Message)) && C.write(request[1], counts, sizeof(Counts)) == isize(sizeof(Counts))
				C.close(request[1])
				C.close(reply[0])
				C._exit(if passed && sent { 0 } else { 1 })
			}
			C.close(request[1])
			C.close(reply[0])
			message := &Message(C.alloca(usize(sizeof(Message))))
			counts := &Counts(C.alloca(usize(sizeof(Counts))))
			*counts = Counts{}
			parameter := &C.sched_param(C.alloca(usize(sizeof(C.sched_param))))
			parameter.sched_priority = 0
			mut same := i32(0)
			mut cross := i32(0)
			mut received := false
			for {
				if C.read(request[0], message, sizeof(Message)) != isize(sizeof(Message)) {
					good = false
					break
				}
				if message.action == 3 {
					received = C.read(request[0], counts, sizeof(Counts)) == isize(sizeof(Counts))
					break
				}
				if message.action == 2 {
					if same != 0 || cross != 0 || message.first <= 0 || message.second <= 0 || message.first == child || message.second == child || message.first == message.second {
						fatal(14)
					}
					same = message.first
					cross = message.second
				} else if message.action == 1 || message.action == 4 {
					parameter.sched_priority = 0
					if message.first !in [child, same, cross] || message.first <= 0 || C.syscall(C.SYS_sched_setscheduler, message.first, C.SCHED_OTHER, parameter) != 0 || C.syscall(C.SYS_setpriority, C.PRIO_PROCESS, message.first, 0) != 0 || !state(message.first, C.SCHED_OTHER, 0, 0) {
						fatal(15)
					}
					if message.action == 4 {
						if message.second !in [i32(C.SCHED_OTHER), C.SCHED_BATCH, C.SCHED_IDLE,
							C.SCHED_FIFO, C.SCHED_RR]! || message.value < -20 || message.value > 19 {
							fatal(18)
						}
						parameter.sched_priority = if message.second == C.SCHED_FIFO || message.second == C.SCHED_RR {
							1
						} else {
							0
						}
						// Canonical signed setup words avoid the separate native
						// setpriority signed32 argument-normalization gap.
						if C.syscall(C.SYS_setpriority, C.PRIO_PROCESS, message.first, u64(i64(message.value))) != 0 || C.syscall(C.SYS_sched_setscheduler, message.first, message.second, parameter) != 0 || !state(message.first, message.second, parameter.sched_priority, message.value) {
							fatal(19)
						}
					}
				} else {
					fatal(16)
				}
				mut answer := i32(0x4e494345)
				if C.write(reply[1], &answer, sizeof(i32)) != isize(sizeof(i32)) { fatal(17) }
			}
			C.close(request[0])
			C.close(reply[1])
			mut status := i32(-1)
			completed := C.waitpid(child, &status, 0) == child && status == 0
			if !received || !completed { good = false }
			if received {
				for kind in 0 .. 4 {
					C.printf(c'LINUX IDLEEXIT FINAL: ordinary=%d kind=%d calls=%lu failures=%lu\n', i32(ordinary), kind, counts.calls[kind], counts.failures[kind])
					if counts.failures[kind] != 0 { good = false }
				}
			}
			C.fflush(nil)
		}
		if !good {
			C.puts(c'LINUX IDLEEXIT FAIL: idle-exit admission, nice or state')
			C.fflush(nil)
			return 1
		}
		C.puts(if reference { c'LINUX IDLEEXIT REFERENCE: PASS' } else { c'LINUX IDLEEXIT: PASS' })
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
