// SPDX-License-Identifier: GPL-2.0-or-later
module selectorderfixture

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
struct Guard { mut: before u64 words [16]u64 after u64 }
struct MaskArg { mut: mask voidptr size u64 }
struct Targets { mut: source i32 peer i32 }

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
	C.printf(c'LINUX SELECTORDER FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil }); C._exit(90)
}
fn check(mut totals Totals, good bool) {
	totals.checks++
	if !good { totals.failures++ }
}

fn C.recv(i32, voidptr, usize, i32) isize
struct TimeGuard { mut: before u64 value C.timespec after u64 }
struct PackGuard { mut: before u64 value MaskArg after u64 }

fn targets() Targets {
	unsafe {
		mut sockets := [2]i32{}
		if C.socketpair(C.AF_UNIX,C.SOCK_STREAM|C.SOCK_NONBLOCK,0,&sockets[0]) != 0 { fatal(1) }
		if C.dup3(sockets[0],1023,C.O_CLOEXEC) != 1023 || C.write(sockets[1],c'Q',1) != 1 { fatal(2) }
		initial := u64(1)<<14
		if C.syscall(isize(C.SYS_rt_sigprocmask),2,&initial,nil,8) != 0 { fatal(3) }
		return Targets{source:sockets[0],peer:sockets[1]}
	}
}
fn count(profile int) int { return if profile == 0 { -1 } else if profile == 1 { 0 } else { 33 } }
fn install(t &Targets, descriptor int) {
	if C.dup3(t.source,32,C.O_CLOEXEC) != 32 { fatal(4) }
	if descriptor == 4 && C.close(32) != 0 { fatal(5) }
}
fn expected_code(api int, amount int, pack int, timeout int, descriptor int) i32 {
	// Independent Linux contract: argument pack, timeout, mask, count, sets.
	if api == 0 && pack == 5 { return C.EFAULT }
	if timeout == 1 { return C.EFAULT }
	if timeout >= 2 { return C.EINVAL }
	if api == 0 && pack == 3 { return C.EINVAL }
	if api == 0 && pack == 4 { return C.EFAULT }
	if amount == 0 { return C.EINVAL }
	if amount == 2 {
		if descriptor in [1,2,3] { return C.EFAULT }
		if descriptor == 4 { return C.EBADF }
	}
	return 0
}
fn call(api int, nfds int, buffers &Guard, descriptor int, timeout voidptr, pack voidptr) isize {
	unsafe {
		r := if descriptor == 1 { voidptr(1) } else { voidptr(&buffers[0].words[0]) }
		w := if descriptor == 2 { voidptr(1) } else { voidptr(&buffers[1].words[0]) }
		e := if descriptor == 3 { voidptr(1) } else { voidptr(&buffers[2].words[0]) }
		errno_slot := C.__errno_location(); *errno_slot = 0
		if api == 0 { return C.syscall(isize(C.SYS_pselect6),nfds,r,w,e,timeout,pack) }
		$if amd64 { return C.syscall(isize(C.SYS_select),nfds,r,w,e,timeout) }
		$else { fatal(6); return -1 }
	}
}
fn probe(t &Targets, api int, amount int, pack int, timeout int, descriptor int) Totals {
	unsafe {
		nfds := count(amount)
		words := if nfds > 0 { 1 } else { 0 }
		mut input := Guard{before:0xabcddcba12344321,after:0x87654321fedcba98}
		for word in words .. 16 { input.words[word] = 0x1122334455667788 }
		if descriptor >= 4 { input.words[0] |= u64(1)<<32 }
		buffers := &Guard(C.alloca(usize(3*sizeof(Guard))))
		for set in 0 .. 3 { buffers[set] = input }
		mut timer := TimeGuard{before:input.before,after:input.after}
		if timeout == 2 { timer.value.tv_sec = -1 }
		if timeout == 3 { timer.value.tv_nsec = -1 }
		if timeout == 4 {
			if api == 0 { timer.value.tv_nsec = 1_000_000_000 }
			else { timer.value.tv_sec = -2; timer.value.tv_nsec = 1 }
		}
		original_timer := timer
		wanted_mask := u64(1)<<9
		mut pair := PackGuard{before:input.before,after:input.after,
			value:MaskArg{mask:if pack == 1 { nil } else if pack == 4 { voidptr(1) } else { voidptr(&wanted_mask) },size:if pack == 3 { 7 } else if pack == 1 { 0xfeed } else { 8 }}}
		original_pair := pair
		pack_address := if pack == 0 { voidptr(nil) } else if pack == 5 { voidptr(1) } else { voidptr(&pair.value) }
		time_address := if timeout == 1 { voidptr(1) } else { voidptr(&timer.value) }
		code := expected_code(api,amount,pack,timeout,descriptor)
		expected := if code != 0 { isize(-1) } else if amount == 2 && descriptor == 5 { isize(2) } else { isize(0) }
		result := call(api,nfds,buffers,descriptor,time_address,pack_address)
		actual_code := *C.__errno_location()
		mut total := Totals{}
		check(mut total,result == expected)
		check(mut total,actual_code == code)
		for set in 0 .. 3 {
			desired := &Guard(C.alloca(usize(sizeof(Guard))))
			*desired = input
			if code == 0 && words != 0 {
				desired.words[0] = if descriptor == 5 && set != 2 { u64(1)<<32 } else { u64(0) }
			}
			check(mut total,C.memcmp(&buffers[set],desired,sizeof(Guard)) == 0)
		}
		check(mut total,C.memcmp(&timer,&original_timer,sizeof(TimeGuard)) == 0)
		check(mut total,C.memcmp(&pair,&original_pair,sizeof(PackGuard)) == 0)
		mut mask := u64(0)
		queried := C.syscall(isize(C.SYS_rt_sigprocmask),0,nil,&mask,8)
		check(mut total,queried == 0 && mask == u64(1)<<14)
		mut byte := u8(0)
		check(mut total,C.recv(t.source,&byte,1,C.MSG_PEEK|C.MSG_DONTWAIT) == 1 && byte == `Q`)
		return total
	}
}
fn qualify(t &Targets, apis int) Totals {
	mut total := Totals{}
	for api in 0 .. apis { for amount in 0 .. 3 { for pack in 0 .. if api == 0 { 6 } else { 1 } {
		mut group := Totals{}
		for timeout in 0 .. 5 { for descriptor in 0 .. 6 {
			install(t,descriptor)
			result := probe(t,api,amount,pack,timeout,descriptor)
			if group.failures == 0 && result.failures != 0 { C.printf(c'LINUX SELECTORDER FIRST: uid=%u api=%d amount=%d pack=%d timeout=%d descriptor=%d failures=%d\n',C.getuid(),api,amount,pack,timeout,descriptor,result.failures) }
			group.checks += result.checks; group.failures += result.failures
			if descriptor != 4 && C.close(32) != 0 { fatal(7) }
		} }
		C.printf(c'LINUX SELECTORDER CASE: uid=%u gid=%u api=%d amount=%d pack=%d checks=%d failures=%d\n',C.getuid(),C.getgid(),api,amount,pack,group.checks,group.failures)
		total.checks += group.checks; total.failures += group.failures
	} } }
	return total
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		C.alarm(600)
		reference := argc == 2 && C.strcmp(argv[1],c'--reference') == 0
		mut apis := 1
		$if amd64 { apis = 2 }
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
				good := if reference { C.printf(c'LINUX SELECTORDER STORAGE: uid=%u SKIP reference\n',C.getuid()); true } else { storage(&t,apis) }
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
		C.printf(c'LINUX SELECTORDER SUMMARY: checks=%d failures=%d\n',total.checks,total.failures)
		C.printf(c'LINUX SELECTORDER: %s\n',if total.failures == 0 && storage_good { &char(c'PASS') } else { &char(c'FAIL') })
		C.fflush(nil); C.alarm(0)
		for { C.pause() }
	}
	return 0
}
