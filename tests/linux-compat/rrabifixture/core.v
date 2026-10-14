// SPDX-License-Identifier: GPL-2.0-or-later
module rrabifixture

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

struct C.sched_param { mut: sched_priority i32 }
struct C.timespec { mut: tv_sec i64 tv_nsec i64 }
struct Counts { mut: calls [4]u64 failures [4]u64 }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows i32 large u64 }
struct Query { ret isize code i32 }
fn C.alloca(usize) voidptr
fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.sched_rr_get_interval(i32, &C.timespec) i32
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

fn fatal(stage i32) { C.printf(c'LINUX RRABI FAIL: setup or child protocol stage=%d errno=%d\n',stage,unsafe { *C.__errno_location() }); C.fflush(unsafe { nil }); C._exit(1) }
fn query(pid u64, pointer u64, libc bool) Query {
	unsafe { slot := C.__errno_location(); *slot = 0
		ret := if libc { isize(C.sched_rr_get_interval(i32(u32(pid)),&C.timespec(usize(pointer)))) } else { C.syscall(C.SYS_sched_rr_get_interval,pid,pointer,u64(-1)) }
		return Query{ret,*slot}
	}
}
fn state(policy i32, priority i32) bool {
	unsafe { out := &C.sched_param(C.alloca(usize(sizeof(C.sched_param)))); out.sched_priority = 42
		return C.syscall(C.SYS_sched_getscheduler,0) == policy && C.syscall(C.SYS_sched_getparam,0,out) == 0 && out.sched_priority == priority
	}
}
fn install(policy i32, priority i32) { unsafe { value := C.sched_param{sched_priority:priority}; if C.syscall(C.SYS_sched_setscheduler,0,policy,&value) != 0 || !state(policy,priority) { fatal(1) } } }
fn record(counts &Counts, kind i32, good bool, ordinary bool, pid u64, form i32, libc bool, result Query, expected i32) {
	unsafe { mut value := &Counts(counts); value.calls[kind]++; if !good { value.failures[kind]++; if value.failures[kind] <= 4 { C.printf(c'LINUX RRABI DETAIL: ordinary=%d kind=%d pid=%lx form=%d libc=%d call=%lu ret=%ld errno=%d expected=%d\n',i32(ordinary),kind,pid,form,i32(libc),value.calls[kind],result.ret,result.code,expected); C.fflush(nil) } } }
}
fn bytes(data &u8, count i32, except_at i32, except_len i32) bool { unsafe { for index in 0 .. int(count) { if index >= except_at && index < except_at + except_len { continue }; if data[index] != 0xa5 { return false } }; return true } }
fn interval(data voidptr, reference bool, rr bool) bool {
	unsafe { out := C.timespec{}; C.memcpy(&out,data,usize(sizeof(C.timespec)))
		if out.tv_sec < 0 || out.tv_nsec < 0 || out.tv_nsec >= 1000000000 { return false }
		if reference { return !rr || out.tv_sec > 0 || out.tv_nsec > 0 }
		return out.tv_sec == 0 && out.tv_nsec == if rr { i64(5000000) } else { i64(0) }
	}
}
fn checked(counts &Counts, ordinary bool, source i32, live bool, word u64, form i32, libc bool, kind i32, mapping &u8, page usize, reference bool) {
	unsafe {
		scratch := &u8(C.alloca(usize(40))); C.memset(scratch,0xa5,40); C.memset(mapping + page - 32,0xa5,32)
		offset := if form == 1 { i32(9) } else { i32(8) }
		pointer := match form { 2 { u64(mapping + page - 16) } 3 { u64(0) } 4 { u64(1) } 5 { u64(mapping + 2 * page) } 6 { u64(mapping + page) } 7 { u64(mapping + 2 * page - 8) } 8 { u64(scratch + offset) | (u64(1) << 55) } 9 { u64(mapping + page - 8) } else { u64(scratch + offset) } }
		code := if source < 0 { i32(C.EINVAL) } else if !live { i32(C.ESRCH) } else if form >= 3 { i32(C.EFAULT) } else { i32(0) }
		result := query(word,pointer,libc)
		mut good := result.ret == if code == 0 { isize(0) } else { isize(-1) } && result.code == code
		if code == 0 { good = good && interval(voidptr(usize(pointer)),reference,false) }
		good = good && bytes(scratch,40,if code == 0 && form < 2 { offset } else { -1 },if code == 0 && form < 2 { 16 } else { 0 })
		// A valid task's cross-page copy may write its accessible prefix. Task
		// validation errors must leave even that prefix and all guards untouched.
		good = good && bytes(mapping + page - 32,32,if code == 0 && form == 2 { 16 } else if code == C.EFAULT && form == 9 { 24 } else { -1 },if code == 0 && form == 2 { 16 } else if code == C.EFAULT && form == 9 { 8 } else { 0 })
		good = good && bytes(mapping + page,16,-1,0) && state(C.SCHED_OTHER,0)
		record(counts,kind,good,ordinary,word,form,libc,result,code)
	}
}
fn matrix(counts &Counts, ordinary bool, dead i32, mapping &u8, page usize, reference bool) {
	unsafe {
		self := C.getpid()
		for source in [i32(0),self,-1,i32(u32(0x80000000)),0x7fffffff,dead]! {
			live := source == 0 || source == self
			for form in 0 .. 10 {
				checked(counts,ordinary,source,live,u64(i64(source)),i32(form),false,0,mapping,page,reference)
				for high in [u64(0x1234567800000000),0xffffffff00000000,0x8000000000000000,0x7fffffff00000000,0xdeadbeef00000000,0x100000000]! { checked(counts,ordinary,source,live,u64(u32(source)) | high,i32(form),false,1,mapping,page,reference) }
				checked(counts,ordinary,source,live,u64(u32(source)),i32(form),true,2,mapping,page,reference)
			}
		}
	}
}
fn realtime(counts &Counts, ordinary bool, reference bool) {
	unsafe { data := &C.timespec(C.alloca(usize(sizeof(C.timespec))))
		for source in [i32(0),C.getpid()]! {
			for high in [u64(0),0x1234567800000000,0xffffffff00000000,0x8000000000000000,0x7fffffff00000000,0xdeadbeef00000000,0x100000000]! {
				C.memset(data,0xa5,usize(sizeof(C.timespec))); word := u64(u32(source)) | high; result := query(word,u64(data),false)
				record(counts,3,result.ret == 0 && result.code == 0 && interval(data,reference,true) && state(C.SCHED_RR,1),ordinary,word,-1,false,result,0)
			}
			C.memset(data,0xa5,usize(sizeof(C.timespec))); result := query(u64(source),u64(data),true); record(counts,3,result.ret == 0 && result.code == 0 && interval(data,reference,true) && state(C.SCHED_RR,1),ordinary,u64(source),-1,true,result,0)
		}
	}
}
fn cycle() bool {
	unsafe { data := C.timespec{}; libc := query(0,u64(&data),true); if libc.ret != 0 || libc.code != 0 || !interval(&data,false,false) { return false }
		upper := query(0x1234567800000000,u64(&data),false); negative := query(0x7fffffff80000000,0,false); absent := query(0xffffffff7fffffff,0,false); bad := query(0,1,false)
		return upper.ret == 0 && upper.code == 0 && interval(&data,false,false) && negative.ret == -1 && negative.code == C.EINVAL && absent.ret == -1 && absent.code == C.ESRCH && bad.ret == -1 && bad.code == C.EFAULT && state(C.SCHED_OTHER,0)
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
		for index in 0 .. int(before.rows) { if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] { good = false }; C.printf(c'LINUX RRABI SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n',i32(ordinary),before.sizes[index],before.live[index],after.live[index]) }
		C.printf(c'LINUX RRABI STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n',i32(ordinary),before.large,after.large,if good { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil); if C.close(observer) != 0 { good = false }; return good
	}
}
fn qualify(counts &Counts, ordinary bool, reference bool) bool {
	unsafe {
		C.alarm(600); install(C.SCHED_RR,1)
		if ordinary && (C.setgroups(0,nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { fatal(2) }
		uid := if ordinary { u32(1000) } else { u32(0) }; if C.getuid() != uid || C.geteuid() != uid || !state(C.SCHED_RR,1) { fatal(3) }
		realtime(counts,ordinary,reference); install(C.SCHED_OTHER,0)
		child := C.fork(); if child < 0 { fatal(4) }; if child == 0 { C._exit(0) }; mut status := i32(-1); if C.waitpid(child,&status,0) != child || status != 0 { fatal(5) }
		page := usize(C.sysconf(C._SC_PAGESIZE)); if page < 4096 || page > 16384 { fatal(6) }
		mapping := &u8(C.mmap(nil,3 * page,C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0)); if mapping == &u8(usize(-1)) { fatal(7) }; C.memset(mapping,0xa5,3 * page)
		if C.mprotect(mapping + page,page,C.PROT_READ) != 0 || C.mprotect(mapping + 2 * page,page,C.PROT_NONE) != 0 { fatal(8) }
		matrix(counts,ordinary,child,mapping,page,reference)
		mut good := counts.failures[0] == 0 && counts.failures[1] == 0 && counts.failures[2] == 0 && counts.failures[3] == 0
		if good && !reference && !storage(ordinary) { good = false }
		record(counts,3,state(C.SCHED_OTHER,0),ordinary,0,-1,false,Query{},0)
		record(counts,3,bytes(mapping + page,16,-1,0),ordinary,0,-1,false,Query{},0)
		record(counts,3,bytes(mapping + page - 32,32,-1,0),ordinary,0,-1,false,Query{},0)
		if C.munmap(mapping,3 * page) != 0 { fatal(9) }
		for kind in 0 .. 4 { C.printf(c'LINUX RRABI CASES: ordinary=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),kind,counts.calls[kind],counts.failures[kind]); if counts.failures[kind] != 0 { good = false } }
		C.alarm(0); C.fflush(nil); return good
	}
}
@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe { reference := argc == 2 && C.strcmp(argv[1],c'--reference') == 0; mut good := true
		for ordinary in [false,true]! {
			ends := &i32(C.alloca(usize(2 * sizeof(i32)))); if C.pipe2(ends,C.O_CLOEXEC) != 0 { fatal(10) }; child := C.fork(); if child < 0 { fatal(11) }
			if child == 0 { C.close(ends[0]); counts := &Counts(C.alloca(usize(sizeof(Counts)))); *counts = Counts{}; passed := qualify(counts,ordinary,reference); sent := C.write(ends[1],counts,usize(sizeof(Counts))) == isize(sizeof(Counts)); C.close(ends[1]); C._exit(if passed && sent { 0 } else { 1 }) }
			C.close(ends[1]); counts := &Counts(C.alloca(usize(sizeof(Counts)))); received := C.read(ends[0],counts,usize(sizeof(Counts))) == isize(sizeof(Counts)); C.close(ends[0]); mut status := i32(-1); completed := C.waitpid(child,&status,0) == child && status == 0; if !received || !completed { good = false }
			if received { for kind in 0 .. 4 { C.printf(c'LINUX RRABI FINAL: ordinary=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),kind,counts.calls[kind],counts.failures[kind]); if counts.failures[kind] != 0 { good = false } } }; C.fflush(nil)
		}
		if !good { C.puts(c'LINUX RRABI FAIL: interval metadata, error precedence or state'); C.fflush(nil); return 1 }; C.puts(if reference { c'LINUX RRABI REFERENCE: PASS' } else { c'LINUX RRABI: PASS' }); C.fflush(nil); for { C.pause() }
	}; return 0
}
