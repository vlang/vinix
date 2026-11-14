// SPDX-License-Identifier: GPL-2.0-or-later
module selecttimevalfixture

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
	C.printf(c'LINUX SELECTTIMEVAL FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil }); C._exit(90)
}
fn check(mut totals Totals, good bool) {
	totals.checks++
	if !good { totals.failures++ }
}

fn C.recv(i32, voidptr, usize, i32) isize
struct TimeGuard { mut: before u64 value C.timespec after u64 }
struct PackGuard { mut: before u64 value MaskArg after u64 }

fn C.clock_gettime(i32, &C.timespec) i32
#include <time.h>

struct Sample { seconds i64 sub i64 valid bool normalized_seconds i64 nanos i64 }
fn sample(index int) Sample {
	max := i64(0x7fffffffffffffff)
	min := -max-1
	// Explicit Linux cases: do not derive expected carries with kernel arithmetic.
	return match index {
		0 { Sample{0,0,true,0,0} }
		1 { Sample{0,1,true,0,1000} }
		2 { Sample{0,999999,true,0,999999000} }
		3 { Sample{0,1000000,true,1,0} }
		4 { Sample{0,1000001,true,1,1000} }
		5 { Sample{0,1999999,true,1,999999000} }
		6 { Sample{0,2000000,true,2,0} }
		7 { Sample{1,-1,false,0,0} }
		8 { Sample{1,-999999,false,0,0} }
		9 { Sample{1,-1000000,true,0,0} }
		10 { Sample{2,-2000000,true,0,0} }
		11 { Sample{2,-2000001,false,0,0} }
		12 { Sample{-1,1000000,true,0,0} }
		13 { Sample{-1,1000001,true,0,1000} }
		14 { Sample{-2,3000000,true,1,0} }
		15 { Sample{-1,999999,false,0,0} }
		16 { Sample{-1,-1000000,false,0,0} }
		17 { Sample{0,-1000000,false,0,0} }
		18 { Sample{max,0,true,max,0} }
		19 { Sample{max,999999,true,max,999999000} }
		20 { Sample{max,1000000,false,0,0} }
		21 { Sample{max,max,false,0,0} }
		22 { Sample{min,-2000000,true,max-1,0} }
		23 { Sample{min,-1000000,true,max,0} }
		24 { Sample{min,1000000,false,0,0} }
		25 { Sample{-1,max,true,9223372036853,775807000} }
		26 { Sample{0,max,true,9223372036854,775807000} }
		27 { Sample{0,min,false,0,0} }
		28 { Sample{10,-1000001,false,0,0} }
		29 { Sample{-1,2000000,true,1,0} }
		30 { Sample{1,1000000000,true,1001,0} }
		31 { Sample{-1,1000000000,true,999,0} }
		32 { Sample{0,1000000001,true,1000,1000} }
		33 { Sample{min,0,false,0,0} }
		34 { Sample{max,-1000000,true,max-1,0} }
		35 { Sample{min,min,false,0,0} }
		else { fatal(1); Sample{} }
	}
}
fn stamp() C.timespec {
	mut ts := C.timespec{}
	if C.clock_gettime(C.CLOCK_MONOTONIC,&ts) != 0 { fatal(2) }
	return ts
}
fn before(a C.timespec, b C.timespec) bool {
	return a.tv_sec < b.tv_sec || (a.tv_sec == b.tv_sec && a.tv_nsec < b.tv_nsec)
}
fn add(a C.timespec, b C.timespec) C.timespec {
	nanos := a.tv_nsec+b.tv_nsec
	seconds := u64(a.tv_sec)+u64(b.tv_sec)+u64(nanos/1_000_000_000)
	if seconds > u64(0x7fffffffffffffff) { return C.timespec{i64(0x7fffffffffffffff),0} }
	return C.timespec{i64(seconds),nanos%1_000_000_000}
}
fn subtract(a C.timespec, b C.timespec) C.timespec {
	if before(a,b) { return C.timespec{} }
	borrow := if a.tv_nsec < b.tv_nsec { i64(1) } else { i64(0) }
	return C.timespec{a.tv_sec-b.tv_sec-borrow,a.tv_nsec-b.tv_nsec+borrow*1_000_000_000}
}
fn timer_ok(value C.timespec, original C.timespec, duration C.timespec, valid bool, readonly int, api int, started C.timespec, stopped C.timespec) bool {
	if readonly == 1 || !valid || (duration.tv_sec == 0 && duration.tv_nsec == 0) {
		return value.tv_sec == original.tv_sec && value.tv_nsec == original.tv_nsec
	}
	limit := if api == 1 { i64(1_000_000) } else { i64(1_000_000_000) }
	if value.tv_sec < 0 || value.tv_nsec < 0 || value.tv_nsec >= limit { return false }
	mut actual := C.timespec{value.tv_sec,value.tv_nsec*if api == 1 { 1000 } else { 1 }}
	mut lower := subtract(add(duration,started),stopped)
	upper := subtract(add(duration,stopped),started)
	if api == 1 { lower.tv_nsec = lower.tv_nsec/1000*1000 }
	return !before(actual,lower) && !before(upper,actual) && !before(duration,actual)
}
fn targets() Targets {
	unsafe {
		mut pair := [2]i32{}
		if C.socketpair(C.AF_UNIX,C.SOCK_STREAM|C.SOCK_NONBLOCK,0,&pair[0]) != 0 { fatal(3) }
		if C.dup3(pair[0],1023,C.O_CLOEXEC) != 1023 || C.write(pair[1],c'Q',1) != 1 { fatal(4) }
		initial := u64(1)<<14
		if C.syscall(isize(C.SYS_rt_sigprocmask),2,&initial,nil,8) != 0 { fatal(5) }
		size := usize(C.sysconf(C._SC_PAGESIZE))
		page := C.mmap(nil,size,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0)
		if page == voidptr(-1) { fatal(6) }
		return Targets{pair[0],pair[1],page,size}
	}
}
fn call(api int, nfds int, buffers &Guard, target int, timeout &C.timespec, pack &MaskArg) isize {
	unsafe {
		r := if target == 3 { voidptr(1) } else { voidptr(&buffers[0].words[0]) }
		w := voidptr(&buffers[1].words[0]); e := voidptr(&buffers[2].words[0])
		errno_slot := C.__errno_location(); *errno_slot = 0
		if api == 0 { return C.syscall(isize(C.SYS_pselect6),nfds,r,w,e,timeout,pack) }
		$if amd64 { return C.syscall(isize(C.SYS_select),nfds,r,w,e,timeout) }
		$else { fatal(7); return -1 }
	}
}
fn probe(t &Targets, api int, index int, target int, readonly int) Totals {
	unsafe {
		input := sample(index)
		valid := if api == 1 { input.valid } else { input.seconds >= 0 && input.sub >= 0 && input.sub < 1_000_000_000 }
		duration := if api == 1 { C.timespec{input.normalized_seconds,input.nanos} } else { C.timespec{input.seconds,input.sub} }
		if C.dup3(t.source,32,C.O_CLOEXEC) != 32 { fatal(8) }
		if target == 1 && C.close(32) != 0 { fatal(9) }
		nfds := if target == 2 { -1 } else { 33 }
		original := &Guard(C.alloca(usize(sizeof(Guard))))
		*original = Guard{before:0xabcddcba12344321,after:0x87654321fedcba98}
		original.words[0] = u64(1)<<32
		for word in 1 .. 16 { original.words[word] = 0x1122334455667788 }
		buffers := &Guard(C.alloca(usize(3*sizeof(Guard))))
		for set in 0 .. 3 { buffers[set] = *original }
		if C.mprotect(t.page,t.page_size,C.PROT_READ|C.PROT_WRITE) != 0 { fatal(10) }
		mut timer := &TimeGuard(t.page)
		*timer = TimeGuard{before:original.before,after:original.after,value:C.timespec{input.seconds,input.sub}}
		old_time := timer.value
		if readonly == 1 && C.mprotect(t.page,t.page_size,C.PROT_READ) != 0 { fatal(11) }
		wanted_mask := u64(1)<<9
		mut pair := PackGuard{before:original.before,after:original.after,value:MaskArg{&wanted_mask,8}}
		old_pair := pair
		code := if !valid || target == 2 { C.EINVAL } else if target == 1 { C.EBADF } else if target == 3 { C.EFAULT } else { 0 }
		expected := if code == 0 { isize(2) } else { isize(-1) }
		started := stamp()
		result := call(api,nfds,buffers,target,&timer.value,&pair.value)
		actual_code := *C.__errno_location()
		stopped := stamp()
		mut total := Totals{}
		check(mut total,result == expected)
		check(mut total,actual_code == code)
		for set in 0 .. 3 {
			desired := &Guard(C.alloca(usize(sizeof(Guard))))
			*desired = *original
			if code == 0 && set == 2 { desired.words[0] = 0 }
			check(mut total,C.memcmp(&buffers[set],desired,sizeof(Guard)) == 0)
		}
		check(mut total,timer.before == original.before && timer.after == original.after
			&& timer_ok(timer.value,old_time,duration,valid,readonly,api,started,stopped))
		check(mut total,C.memcmp(&pair,&old_pair,sizeof(PackGuard)) == 0)
		mut mask := u64(0)
		queried := C.syscall(isize(C.SYS_rt_sigprocmask),0,nil,&mask,8)
		check(mut total,queried == 0 && mask == u64(1)<<14)
		mut byte := u8(0)
		check(mut total,C.recv(t.source,&byte,1,C.MSG_PEEK|C.MSG_DONTWAIT) == 1 && byte == `Q`)
		if target != 1 && C.close(32) != 0 { fatal(12) }
		return total
	}
}
fn qualify(t &Targets, apis int) Totals {
	mut total := Totals{}
	for api in 0 .. apis { for index in 0 .. 36 {
		mut group := Totals{}
		for target in 0 .. 4 { for readonly in 0 .. 2 {
			result := probe(t,api,index,target,readonly)
			group.checks += result.checks; group.failures += result.failures
		} }
		C.printf(c'LINUX SELECTTIMEVAL CASE: uid=%u gid=%u api=%d sample=%d checks=%d failures=%d\n',C.getuid(),C.getgid(),api,index,group.checks,group.failures)
		total.checks += group.checks; total.failures += group.failures
	} }
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
				good := if reference { C.printf(c'LINUX SELECTTIMEVAL STORAGE: uid=%u SKIP reference\n',C.getuid()); true } else { storage(&t,apis) }
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
		C.printf(c'LINUX SELECTTIMEVAL SUMMARY: checks=%d failures=%d\n',total.checks,total.failures)
		C.printf(c'LINUX SELECTTIMEVAL: %s\n',if total.failures == 0 && storage_good { &char(c'PASS') } else { &char(c'FAIL') })
		C.fflush(nil); C.alarm(0)
		for { C.pause() }
	}
	return 0
}
