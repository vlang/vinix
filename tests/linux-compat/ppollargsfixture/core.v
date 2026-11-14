// SPDX-License-Identifier: GPL-2.0-or-later
module ppollargsfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.timespec { mut: tv_sec i64 tv_nsec i64 }
struct C.timeval { mut: tv_sec i64 tv_usec i64 }
struct Totals { mut: checks int failures int }
struct Poll { mut: fd i32 events i16 revents i16 }
struct Guard { mut: before u64 poll Poll after u64 }
struct MaskArg { mut: mask voidptr size u64 }
struct Targets { source i32 peer i32 page voidptr page_size usize }

fn C.alloca(usize) voidptr
fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.dup3(i32, i32, i32) i32
fn C.chmod(&char, u32) i32
fn C.socketpair(i32, i32, i32, &i32) i32
fn C.write(i32, voidptr, usize) isize
fn C.read(i32, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.mprotect(voidptr, usize, i32) i32
fn C.sysconf(i32) isize
fn C.strcmp(&char, &char) i32
fn C.sscanf(&char, &char, ...) i32
fn C.printf(&char, ...) i32
fn C.fflush(voidptr) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.getuid() u32
fn C.getgid() u32
fn C.alarm(u32) u32
fn C.pause() i32
fn C.usleep(u32) i32
fn C.pipe(&i32) i32

fn fatal(stage int) {
	C.printf(c'LINUX PPOLLARGS FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil }); C._exit(90)
}
fn check(mut totals Totals, good bool) {
	totals.checks++
	if !good { totals.failures++ }
}

fn C.recv(i32, voidptr, usize, i32) isize
struct TimeGuard { mut: before u64 value C.timespec after u64 }
struct PackGuard { mut: before u64 value MaskArg after u64 }

struct MaskValue { mut: before u64 value u64 after u64 }
fn count(profile int) u64 {
	return match profile {
		0 { u64(0) } 1 { u64(1) } 2 { ~u64(0) }
		3 { u64(0x100000000) } 4 { u64(0x100000001) }
		5 { u64(0xffffffff00000001) } else { u64(0x8000000000000000) }
	}
}
fn size(profile int) u64 {
	return match profile { 0,3 { u64(0) } 1 { ~u64(0) } 4 { u64(16) } 6 { u64(7) } 7 { u64(0x100000008) } else { u64(8) } }
}
fn targets() Targets {
	unsafe {
		mut pair := [2]i32{}
		if C.socketpair(C.AF_UNIX,C.SOCK_STREAM|C.SOCK_NONBLOCK,0,&pair[0]) != 0 { fatal(1) }
		if C.dup3(pair[0],1023,C.O_CLOEXEC) != 1023 || C.write(pair[1],c'Q',1) != 1 { fatal(2) }
		initial := u64(1)<<14
		if C.syscall(isize(C.SYS_rt_sigprocmask),2,&initial,nil,8) != 0 { fatal(3) }
		length := usize(C.sysconf(C._SC_PAGESIZE))
		page := C.mmap(nil,length,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0)
		if page == voidptr(-1) { fatal(4) }
		return Targets{pair[0],pair[1],page,length}
	}
}
fn expected_code(amount int, mask int, timeout int, descriptor int) i32 {
	if timeout == 1 { return C.EFAULT }
	if timeout >= 2 || mask in [3,4,6,7] { return C.EINVAL }
	if mask == 5 { return C.EFAULT }
	if amount == 2 { return C.EINVAL }
	if amount in [1,4,5] && descriptor in [3,4] { return C.EFAULT }
	return 0
}
fn probe(t &Targets, amount int, mask int, timeout int, descriptor int) Totals {
	unsafe {
		if C.dup3(t.source,32,C.O_CLOEXEC) != 32 { fatal(5) }
		if descriptor == 2 && C.close(32) != 0 { fatal(6) }
		if C.mprotect(t.page,t.page_size,C.PROT_READ|C.PROT_WRITE) != 0 { fatal(7) }
		mut buffer := &Guard(t.page)
		*buffer = Guard{before:0xabcddcba12344321,after:0x87654321fedcba98,poll:Poll{fd:if descriptor in [1,2] { 32 } else { -1 },events:5,revents:0x1234}}
		original := *buffer
		if descriptor == 4 && C.mprotect(t.page,t.page_size,C.PROT_READ) != 0 { fatal(8) }
		mut timer := &TimeGuard(C.alloca(usize(sizeof(TimeGuard))))
		*timer = TimeGuard{before:buffer.before,after:buffer.after}
		if timeout == 2 { timer.value.tv_sec = -1 }
		if timeout == 3 { timer.value.tv_nsec = -1 }
		if timeout == 4 { timer.value.tv_nsec = 1_000_000_000 }
		original_timer := *timer
		wanted := &MaskValue(C.alloca(usize(sizeof(MaskValue))))
		*wanted = MaskValue{before:buffer.before,value:u64(1)<<9,after:buffer.after}
		original_wanted := *wanted
		pair := &PackGuard(C.alloca(usize(sizeof(PackGuard))))
		*pair = PackGuard{before:buffer.before,after:buffer.after,value:MaskArg{mask:if mask in [0,1] { nil } else if mask in [5,6] { voidptr(1) } else { voidptr(&wanted.value) },size:size(mask)}}
		original_pair := *pair
		code := expected_code(amount,mask,timeout,descriptor)
		expected := if code != 0 { isize(-1) } else if amount in [1,4,5] && descriptor in [1,2] { isize(1) } else { isize(0) }
		errno_slot := C.__errno_location(); *errno_slot = 0
		result := C.syscall(isize(C.SYS_ppoll),if descriptor == 3 { voidptr(1) } else { voidptr(&buffer.poll) },count(amount),if timeout == 1 { voidptr(1) } else { voidptr(&timer.value) },pair.value.mask,pair.value.size)
		actual_code := *C.__errno_location()
		mut total := Totals{}
		check(mut total,result == expected)
		check(mut total,actual_code == code)
		desired := &Guard(C.alloca(usize(sizeof(Guard))))
		*desired = original
		if code == 0 && amount in [1,4,5] && descriptor < 3 {
			desired.poll.revents = if descriptor == 0 { i16(0) } else if descriptor == 1 { i16(5) } else { i16(32) }
		}
		check(mut total,C.memcmp(buffer,desired,sizeof(Guard)) == 0)
		check(mut total,C.memcmp(timer,&original_timer,sizeof(TimeGuard)) == 0)
		check(mut total,C.memcmp(pair,&original_pair,sizeof(PackGuard)) == 0 && C.memcmp(wanted,&original_wanted,sizeof(MaskValue)) == 0)
		mut current := u64(0)
		queried := C.syscall(isize(C.SYS_rt_sigprocmask),0,nil,&current,8)
		check(mut total,queried == 0 && current == u64(1)<<14)
		mut byte := u8(0)
		check(mut total,C.recv(t.source,&byte,1,C.MSG_PEEK|C.MSG_DONTWAIT) == 1 && byte == `Q`)
		if descriptor != 2 && C.close(32) != 0 { fatal(9) }
		return total
	}
}
fn qualify(t &Targets, _apis int) Totals {
	mut total := Totals{}
	for amount in 0 .. 7 { for mask in 0 .. 8 {
		mut group := Totals{}
		for timeout in 0 .. 5 { for descriptor in 0 .. 5 {
			result := probe(t,amount,mask,timeout,descriptor)
			group.checks += result.checks; group.failures += result.failures
		} }
		C.printf(c'LINUX PPOLLARGS CASE: uid=%u gid=%u amount=%d mask=%d checks=%d failures=%d\n',C.getuid(),C.getgid(),amount,mask,group.checks,group.failures)
		total.checks += group.checks; total.failures += group.failures
	} }
	return total
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		C.alarm(600)
		reference := argc == 2 && C.strcmp(argv[1],c'--reference') == 0
		apis := 1
		mut total := Totals{}
		mut storage_good := true
		for ordinary in [false,true]! {
			mut channel := [2]i32{}
			if C.pipe(&channel[0]) != 0 { fatal(8) }
			C.fflush(nil); pid := C.fork()
			if pid < 0 { fatal(9) }
			if pid == 0 {
				C.close(channel[0])
				if ordinary && (C.setgid(2000) != 0 || C.setuid(1000) != 0) { fatal(10) }
				t := targets()
				sum := qualify(&t,apis)
				good := if reference { C.printf(c'LINUX PPOLLARGS STORAGE: uid=%u SKIP reference\n',C.getuid()); true } else { storage(&t,apis) }
				mut answer := [3]int{}
				answer[0] = sum.checks; answer[1] = sum.failures; answer[2] = if good { 0 } else { 1 }
				if C.write(channel[1],&answer[0],sizeof(answer)) != isize(sizeof(answer)) { fatal(11) }
				C.fflush(nil); C._exit(0)
			}
			C.close(channel[1]); mut answer := [3]int{}
			if C.read(channel[0],&answer[0],sizeof(answer)) != isize(sizeof(answer)) { fatal(12) }
			C.close(channel[0]); mut status := i32(0)
			if C.waitpid(pid,&status,0) != pid || status != 0 { fatal(13) }
			total.checks += answer[0]; total.failures += answer[1]
			if answer[2] != 0 { storage_good = false }
		}
		C.printf(c'LINUX PPOLLARGS SUMMARY: checks=%d failures=%d\n',total.checks,total.failures)
		C.printf(c'LINUX PPOLLARGS: %s\n',if total.failures == 0 && storage_good { &char(c'PASS') } else { &char(c'FAIL') })
		C.fflush(nil); C.alarm(0)
		for { C.pause() }
	}
	return 0
}
