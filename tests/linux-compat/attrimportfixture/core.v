// SPDX-License-Identifier: GPL-2.0-or-later
module attrimportfixture

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
struct Attr { mut: size u32 policy u32 flags u64 nice i32 priority u32 runtime u64 deadline u64 period u64 util_min u32 util_max u32 }
struct Counts { mut: calls [4]u64 failures [4]u64 }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows i32 large u64 }
struct Query { ret isize code i32 }
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

fn fatal(stage i32) { C.printf(c'LINUX ATTRIMPORT FAIL: setup or child protocol stage=%d errno=%d\n',stage,unsafe { *C.__errno_location() }); C.fflush(unsafe { nil }); C._exit(1) }
fn query(pid u64, pointer u64, flags u64) Query { unsafe { slot := C.__errno_location(); *slot = 0; ret := C.syscall(C.SYS_sched_setattr,pid,pointer,flags,u64(-1),u64(-1)); return Query{ret,*slot} } }

fn state(policy i32, priority i32) bool { unsafe { out := &C.sched_param(C.alloca(usize(sizeof(C.sched_param)))); out.sched_priority = 42; return C.syscall(C.SYS_sched_getscheduler,0) == policy && C.syscall(C.SYS_sched_getparam,0,out) == 0 && out.sched_priority == priority } }
fn install(policy i32, priority i32) { unsafe { value := C.sched_param{sched_priority:priority}; if C.syscall(C.SYS_sched_setscheduler,0,policy,&value) != 0 || !state(policy,priority) { fatal(1) } } }
fn record(counts &Counts, kind i32, good bool, ordinary bool, pid u64, size u64, flags u64, form i32, result Query, expected i32) { unsafe { mut value := &Counts(counts); value.calls[kind]++; if !good { value.failures[kind]++; if value.failures[kind] <= 4 { C.printf(c'LINUX ATTRIMPORT DETAIL: ordinary=%d kind=%d pid=%lx size=%lx flags=%lx form=%d call=%lu ret=%ld errno=%d expected=%d\n',i32(ordinary),kind,pid,size,flags,form,value.calls[kind],result.ret,result.code,expected); C.fflush(nil) } } } }
fn bytes(data &u8, count i32, except_at i32, except_len i32) bool { unsafe { for index in 0 .. int(count) { if index >= except_at && index < except_at + except_len { continue }; if data[index] != 0xa5 { return false } }; return true } }
fn checked(counts &Counts, ordinary bool, source i32, live bool, size u32, flags u32, form i32, variant i32, mapping &u8, page usize, header i32, kind_override i32) {
	unsafe {
		if C.mprotect(mapping + 2 * page,page,C.PROT_READ | C.PROT_WRITE) != 0 { fatal(18) }
		C.memset(mapping,0,3 * page)
		pointer := match form { 1 { mapping + 9 } 2 { mapping + 2 * page + 8 } 3 { &u8(usize(0)) } 4 { &u8(usize(1)) } 5 { mapping + 3 * page } 6 { mapping + page - 48 } 7 { mapping + 3 * page - 4 } 8 { mapping + 3 * page - 48 } 9 { &u8(u64(mapping + 8) | (u64(1) << 55)) } 11 { mapping + 3 * page - 64 } else { mapping + 8 } }
		accessible := form !in [i32(3),4,5,9]
		readonly := form in [i32(2),7,8,11]
		value := &Attr(C.alloca(usize(sizeof(Attr)))); *value = Attr{size:size,policy:if header == 1 { u32(-1) } else { u32(C.SCHED_BATCH) },flags:if header == 2 { u64(0x20) } else if header == 3 { u64(1) << 63 } else { u64(0) }}
		known := if form == 7 { usize(4) } else if form == 8 { usize(48) } else { usize(56) }
		if accessible { C.memcpy(pointer,value,known); C.memset(pointer - 8,0xa5,8); if form in [i32(10),11] { pointer[56] = 0xa5 } }
		before := &u8(C.alloca(usize(64))); if accessible { C.memcpy(before,pointer,known) }
		if C.mprotect(mapping + 2 * page,page,C.PROT_READ) != 0 { fatal(19) }
		pid := if variant == 1 { u64(u32(source)) | 0x1234567800000000 } else if variant == 2 { u64(u32(source)) | 0xffffffff00000000 } else { u64(i64(source)) }
		word_flags := u64(flags) | if variant == 3 { u64(0xffffffff00000000) } else { u64(0) }
		effective_size := if size == 0 { u32(48) } else { size }
		entry := source < 0 || form == 3 || flags != 0
		bad_size := effective_size < 48 || usize(effective_size) > page
		nonzero_tail := form in [i32(10),11] && effective_size > 56
		fault := form == 7 || (form == 8 && effective_size > 48)
			|| (form == 2 && usize(effective_size) == page)
		code := if entry { i32(C.EINVAL) } else if !accessible { i32(C.EFAULT) } else if bad_size || nonzero_tail { i32(C.E2BIG) } else if fault { i32(C.EFAULT) } else if header in [i32(1),2] { i32(C.EINVAL) } else if !live { i32(C.ESRCH) } else if header == 3 { i32(C.EINVAL) } else { i32(0) }
		install(C.SCHED_OTHER,0)
		result := query(pid,u64(pointer),word_flags)
		mut good := result.ret == if code == 0 { isize(0) } else { isize(-1) } && result.code == code && state(if code == 0 { C.SCHED_BATCH } else { C.SCHED_OTHER },0)
		if accessible {
			if code == C.E2BIG && !readonly { known_size := u32(56); C.memcpy(before,&known_size,4) }
			good = good && C.memcmp(pointer,before,known) == 0 && bytes(pointer - 8,8,-1,0)
			if form in [i32(10),11] { good = good && pointer[56] == 0xa5 }
		}
		record(counts,if kind_override >= 0 { kind_override } else if variant in [i32(1),2] { 1 } else if variant == 3 { 2 } else { 0 },good,ordinary,pid,u64(size),word_flags,form,result,code)
		install(C.SCHED_OTHER,0)
	}
}
fn matrix(counts &Counts, ordinary bool, dead i32, mapping &u8, page usize) {
	unsafe { self := C.getpid()
		for source in [i32(0),self,-1,i32(u32(0x80000000)),0x7fffffff,dead]! { live := source == 0 || source == self
			for size in [u32(0),1,47,48,49,50,51,52,53,54,55,56,57,u32(page),u32(page + 1),u32(-1)]! {
				for flags in [u32(0),1]! { for form in 0 .. 12 { for variant in 0 .. 4 { checked(counts,ordinary,source,live,size,flags,i32(form),i32(variant),mapping,page,0,-1) } } }
			}
			for header in [i32(1),2,3]! { for variant in [i32(0),1]! { checked(counts,ordinary,source,live,48,0,0,variant,mapping,page,header,3) } }
		}
	}
}
fn cycle() bool {
	unsafe {
		data := &u8(C.alloca(usize(80))); C.memset(data,0,80); value := Attr{size:0,policy:u32(C.SCHED_BATCH)}; C.memcpy(data + 8,&value,56)
		set := query(0x1234567800000000,u64(data + 8),0xffffffff00000000); if set.ret != 0 || set.code != 0 || !state(C.SCHED_BATCH,0) { return false }; install(C.SCHED_OTHER,0)
		negative := query(0x7fffffff80000000,1,0); null := query(0,0,0)
		mut size := u32(57); C.memcpy(data + 8,&size,4); data[64] = 1
		tail := query(0xffffffff7fffffff,u64(data + 8),0); C.memcpy(&size,data + 8,4)
		if tail.ret != -1 || tail.code != C.E2BIG || size != 56 || !state(C.SCHED_OTHER,0) { return false }
		absent := query(0xffffffff7fffffff,1,0)
		return negative.ret == -1 && negative.code == C.EINVAL && null.ret == -1 && null.code == C.EINVAL && absent.ret == -1 && absent.code == C.EFAULT
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
		for index in 0 .. int(before.rows) { if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] { good = false }; C.printf(c'LINUX ATTRIMPORT SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n',i32(ordinary),before.sizes[index],before.live[index],after.live[index]) }
		C.printf(c'LINUX ATTRIMPORT STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n',i32(ordinary),before.large,after.large,if good { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil); if C.close(observer) != 0 { good = false }; return good
	}
}
fn qualify(counts &Counts, ordinary bool, reference bool) bool {
	unsafe {
		C.alarm(600); if sizeof(Attr) != 56 { fatal(2) }; install(C.SCHED_OTHER,0)
		if ordinary && (C.setgroups(0,nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { fatal(3) }
		uid := if ordinary { u32(1000) } else { u32(0) }; if C.getuid() != uid || C.geteuid() != uid { fatal(4) }
		child := C.fork(); if child < 0 { fatal(5) }; if child == 0 { C._exit(0) }; mut status := i32(-1); if C.waitpid(child,&status,0) != child || status != 0 { fatal(6) }
		page := usize(C.sysconf(C._SC_PAGESIZE)); if page < 4096 || page > 16384 { fatal(7) }
		mapping := &u8(C.mmap(nil,4 * page,C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0)); if mapping == &u8(usize(-1)) { fatal(8) }
		if C.mprotect(mapping + 3 * page,page,C.PROT_NONE) != 0 { fatal(9) }
		matrix(counts,ordinary,child,mapping,page)
		mut good := counts.failures[0] == 0 && counts.failures[1] == 0 && counts.failures[2] == 0 && counts.failures[3] == 0
		if good && !reference && !storage(ordinary) { good = false }
		record(counts,3,state(C.SCHED_OTHER,0),ordinary,0,0,0,-1,Query{},0)
		record(counts,3,bytes(mapping,8,-1,0),ordinary,0,0,0,-1,Query{},0)
		record(counts,3,*(&u32(mapping + 8)) == 48,ordinary,0,0,0,-1,Query{},0)
		if C.munmap(mapping,4 * page) != 0 { fatal(10) }
		for kind in 0 .. 4 { C.printf(c'LINUX ATTRIMPORT CASES: ordinary=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),kind,counts.calls[kind],counts.failures[kind]); if counts.failures[kind] != 0 { good = false } }; C.alarm(0); C.fflush(nil); return good
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe { reference := argc == 2 && C.strcmp(argv[1],c'--reference') == 0; mut good := true
		for ordinary in [false,true]! {
			ends := &i32(C.alloca(usize(2 * sizeof(i32)))); if C.pipe2(ends,C.O_CLOEXEC) != 0 { fatal(14) }; child := C.fork(); if child < 0 { fatal(15) }
			if child == 0 { C.close(ends[0]); counts := &Counts(C.alloca(usize(sizeof(Counts)))); *counts = Counts{}; passed := qualify(counts,ordinary,reference); sent := C.write(ends[1],counts,usize(sizeof(Counts))) == isize(sizeof(Counts)); C.close(ends[1]); C._exit(if passed && sent { 0 } else { 1 }) }
			C.close(ends[1]); counts := &Counts(C.alloca(usize(sizeof(Counts)))); received := C.read(ends[0],counts,usize(sizeof(Counts))) == isize(sizeof(Counts)); C.close(ends[0]); mut status := i32(-1); completed := C.waitpid(child,&status,0) == child && status == 0; if !received || !completed { good = false }
			if received { for kind in 0 .. 4 { C.printf(c'LINUX ATTRIMPORT FINAL: ordinary=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),kind,counts.calls[kind],counts.failures[kind]); if counts.failures[kind] != 0 { good = false } } }; C.fflush(nil)
		}
		if !good { C.puts(c'LINUX ATTRIMPORT FAIL: query layout, arguments or state'); C.fflush(nil); return 1 }; C.puts(if reference { c'LINUX ATTRIMPORT REFERENCE: PASS' } else { c'LINUX ATTRIMPORT: PASS' }); C.fflush(nil); for { C.pause() }
	}; return 0
}
