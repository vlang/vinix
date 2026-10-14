// SPDX-License-Identifier: GPL-2.0-or-later
module schextfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <sched.h>
#include <stdio.h>
#include <string.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.sched_param { mut: sched_priority i32 }
struct Counts { mut: calls [4]u64 failures [4]u64 }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows i32 large u64 }
struct Query { ret isize code i32 }
fn C.alloca(usize) voidptr
fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.sched_get_priority_min(i32) i32
fn C.sched_get_priority_max(i32) i32
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

fn fatal(stage i32) { C.printf(c'LINUX SCHEXT FAIL: setup or child protocol stage=%d errno=%d\n',stage,unsafe { *C.__errno_location() }); C.fflush(unsafe { nil }); C._exit(1) }
fn query(maximum bool, word u64, libc bool) Query {
	unsafe { slot := C.__errno_location(); *slot = 0; mut result := isize(-2)
		if libc { result = if maximum { isize(C.sched_get_priority_max(i32(u32(word)))) } else { isize(C.sched_get_priority_min(i32(u32(word)))) } }
		else if maximum { result = C.syscall(C.SYS_sched_get_priority_max,word,u64(1),u64(-1)) }
		else { result = C.syscall(C.SYS_sched_get_priority_min,word,u64(1),u64(-1)) }
		return Query{result,*slot}
	}
}
fn normal() bool {
	unsafe { data := &C.sched_param(C.alloca(usize(sizeof(C.sched_param)))); data.sched_priority = 42
		return C.syscall(C.SYS_sched_getscheduler,0) == C.SCHED_OTHER && C.syscall(C.SYS_sched_getparam,0,data) == 0 && data.sched_priority == 0
	}
}
fn record(counts &Counts, kind i32, good bool, ordinary bool, maximum bool, word u64, libc bool, result Query, expected i32) {
	unsafe { mut value := &Counts(counts); value.calls[kind]++; if !good { value.failures[kind]++; if value.failures[kind] <= 4 { C.printf(c'LINUX SCHEXT DETAIL: ordinary=%d kind=%d max=%d word=%lx libc=%d call=%lu ret=%ld errno=%d expected=%d\n',i32(ordinary),kind,i32(maximum),word,i32(libc),value.calls[kind],result.ret,result.code,expected); C.fflush(nil) } } }
}
fn checked(counts &Counts, ordinary bool, policy i32, maximum bool, word u64, libc bool) {
	valid := policy in [i32(0),1,2,3,5,6,7]
	code := if valid { i32(0) } else { i32(C.EINVAL) }
	wanted := if !valid { isize(-1) } else if policy in [i32(C.SCHED_FIFO),C.SCHED_RR] { if maximum { isize(99) } else { isize(1) } } else { isize(0) }
	result := query(maximum,word,libc)
	record(counts,if policy == 7 { 1 } else if libc { 2 } else { 0 },result.ret == wanted && result.code == code && normal(),ordinary,maximum,word,libc,result,code)
}
fn matrix(counts &Counts, ordinary bool) {
	// These fixed arrays are traversed within their literal bounds.
	unsafe {
	for policy in [i32(0),1,2,3,5,6,7,4,8,-1,i32(u32(0x80000000)),0x7fffffff,0x40000000,0x40000001,0x40000007,i32(u32(0x80000007))]! {
		for maximum in [false,true]! {
			checked(counts,ordinary,policy,maximum,u64(i64(policy)),false)
			for high in [u64(0x1234567800000000),0xffffffff00000000,0x8000000000000000,0x7fffffff00000000,0xdeadbeef00000000]! { checked(counts,ordinary,policy,maximum,u64(u32(policy)) | high,false) }
			checked(counts,ordinary,policy,maximum,u64(u32(policy)),true)
		}
	}
	}
}
fn cycle() bool {
	unsafe {
	for maximum in [false,true]! {
		for libc in [false,true]! { result := query(maximum,0x1234567800000007,libc); if result.ret != 0 || result.code != 0 { return false } }
		invalid := query(maximum,0xffffffff40000007,false); if invalid.ret != -1 || invalid.code != C.EINVAL { return false }
		fifo := query(maximum,u64(C.SCHED_FIFO),true); if fifo.ret != if maximum { isize(99) } else { isize(1) } || fifo.code != 0 { return false }
	}; return normal()
	}
}
fn snapshot(fd i32, destination &Slabs) bool {
	unsafe { mut counts := &Slabs(destination); *counts = Slabs{}; mut data := [4096]char{}; length := C.pread(fd,&data[0],4095,0); if length <= 0 || length >= 4096 { return false }; data[int(length)] = 0; mut position := 0; mut large := false
		for position < int(length) { mut size := u64(0); mut duplicate := u64(0); mut live := u64(0); mut pages := u64(0)
			if C.sscanf(&data[position],c'size-%lu %lu %lu %lu',&size,&duplicate,&live,&pages) == 4 { if counts.rows >= 32 || size != duplicate { return false }; counts.sizes[counts.rows] = size; counts.live[counts.rows] = live; counts.rows++ }
			else if C.sscanf(&data[position],c'large - - %lu',&counts.large) == 1 { large = true }; for position < int(length) && data[position] != char(10) { position++ }; position++
		}; return counts.rows > 0 && large
	}
}
fn storage(ordinary bool) bool {
	unsafe { observer := C.open(c'/proc/slabinfo',C.O_RDONLY | C.O_CLOEXEC); if observer < 0 { return false }
		for _ in 0 .. 32 { if !cycle() { C.close(observer); return false } }; C.usleep(13000000)
		before := &Slabs(C.alloca(usize(sizeof(Slabs)))); after := &Slabs(C.alloca(usize(sizeof(Slabs)))); if !snapshot(observer,before) { C.close(observer); return false }
		for _ in 0 .. 200 { if !cycle() { C.close(observer); return false } }; C.usleep(13000000); if !snapshot(observer,after) { C.close(observer); return false }; mut good := before.rows == after.rows && before.large == after.large
		for index in 0 .. int(before.rows) { if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] { good = false }; C.printf(c'LINUX SCHEXT SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n',i32(ordinary),before.sizes[index],before.live[index],after.live[index]) }
		C.printf(c'LINUX SCHEXT STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n',i32(ordinary),before.large,after.large,if good { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil); if C.close(observer) != 0 { good = false }; return good
	}
}
fn qualify(counts &Counts, ordinary bool, reference bool) bool {
	unsafe { C.alarm(600); if ordinary && (C.setgroups(0,nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { fatal(1) }
		uid := if ordinary { u32(1000) } else { u32(0) }; if C.getuid() != uid || C.geteuid() != uid || !normal() { fatal(2) }
		matrix(counts,ordinary); mut good := counts.failures[0] == 0 && counts.failures[1] == 0 && counts.failures[2] == 0
		if good && !reference && !storage(ordinary) { good = false }
		record(counts,3,normal(),ordinary,false,0,false,Query{},0)
		for kind in 0 .. 4 { C.printf(c'LINUX SCHEXT CASES: ordinary=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),kind,counts.calls[kind],counts.failures[kind]); if counts.failures[kind] != 0 { good = false } }; C.alarm(0); C.fflush(nil); return good
	}
}
@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe { reference := argc == 2 && C.strcmp(argv[1],c'--reference') == 0; mut good := true
		for ordinary in [false,true]! {
			ends := &i32(C.alloca(usize(2 * sizeof(i32)))); if C.pipe2(ends,C.O_CLOEXEC) != 0 { fatal(3) }; child := C.fork(); if child < 0 { fatal(4) }
			if child == 0 { C.close(ends[0]); counts := &Counts(C.alloca(usize(sizeof(Counts)))); *counts = Counts{}; passed := qualify(counts,ordinary,reference); sent := C.write(ends[1],counts,usize(sizeof(Counts))) == isize(sizeof(Counts)); C.close(ends[1]); C._exit(if passed && sent { 0 } else { 1 }) }
			C.close(ends[1]); counts := &Counts(C.alloca(usize(sizeof(Counts)))); received := C.read(ends[0],counts,usize(sizeof(Counts))) == isize(sizeof(Counts)); C.close(ends[0]); mut status := i32(-1); completed := C.waitpid(child,&status,0) == child && status == 0; if !received || !completed { good = false }
			if received { for kind in 0 .. 4 { C.printf(c'LINUX SCHEXT FINAL: ordinary=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),kind,counts.calls[kind],counts.failures[kind]); if counts.failures[kind] != 0 { good = false } } }; C.fflush(nil)
		}
		if !good { C.puts(c'LINUX SCHEXT FAIL: priority metadata or state'); C.fflush(nil); return 1 }; C.puts(if reference { c'LINUX SCHEXT REFERENCE: PASS' } else { c'LINUX SCHEXT: PASS' }); C.fflush(nil); for { C.pause() }
	}; return 0
}
