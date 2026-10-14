// SPDX-License-Identifier: GPL-2.0-or-later
module attrqueryfixture

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

fn fatal(stage i32) { C.printf(c'LINUX ATTRQUERY FAIL: setup or child protocol stage=%d errno=%d\n',stage,unsafe { *C.__errno_location() }); C.fflush(unsafe { nil }); C._exit(1) }
fn query(pid u64, pointer u64, size u64, flags u64) Query { unsafe { slot := C.__errno_location(); *slot = 0; ret := C.syscall(C.SYS_sched_getattr,pid,pointer,size,flags,u64(-1)); return Query{ret,*slot} } }
fn state(policy i32, priority i32) bool { unsafe { out := &C.sched_param(C.alloca(usize(sizeof(C.sched_param)))); out.sched_priority = 42; return C.syscall(C.SYS_sched_getscheduler,0) == policy && C.syscall(C.SYS_sched_getparam,0,out) == 0 && out.sched_priority == priority } }
fn install(policy i32, priority i32) { unsafe { value := C.sched_param{sched_priority:priority}; if C.syscall(C.SYS_sched_setscheduler,0,policy,&value) != 0 || !state(policy,priority) { fatal(1) } } }
fn record(counts &Counts, kind i32, good bool, ordinary bool, pid u64, size u64, flags u64, form i32, result Query, expected i32) { unsafe { mut value := &Counts(counts); value.calls[kind]++; if !good { value.failures[kind]++; if value.failures[kind] <= 4 { C.printf(c'LINUX ATTRQUERY DETAIL: ordinary=%d kind=%d pid=%lx size=%lx flags=%lx form=%d call=%lu ret=%ld errno=%d expected=%d\n',i32(ordinary),kind,pid,size,flags,form,value.calls[kind],result.ret,result.code,expected); C.fflush(nil) } } } }
fn bytes(data &u8, count i32, except_at i32, except_len i32) bool { unsafe { for index in 0 .. int(count) { if index >= except_at && index < except_at + except_len { continue }; if data[index] != 0xa5 { return false } }; return true } }
fn output(data voidptr, size u32, policy i32, priority i32, reference bool) bool {
	unsafe { actual := &Attr(C.alloca(usize(sizeof(Attr)))); C.memset(actual,0,usize(sizeof(Attr))); C.memcpy(actual,data,usize(size))
		expected := &Attr(C.alloca(usize(sizeof(Attr)))); *expected = Attr{size:size,policy:u32(policy),priority:u32(priority),util_max:1024}
		if reference {
			// Fair slice and clamp defaults depend on the reference configuration.
			expected.runtime = actual.runtime
			if size > 52 { expected.util_max = actual.util_max; if expected.util_max != 0 && expected.util_max != 1024 { return false } }
		}
		return C.memcmp(actual,expected,usize(size)) == 0
	}
}
fn checked(counts &Counts, ordinary bool, source i32, live bool, size u32, flags u32, form i32, variant i32, mapping &u8, page usize, reference bool) {
	unsafe {
		scratch := &u8(C.alloca(usize(96))); C.memset(scratch,0xa5,96); C.memset(mapping + page - 64,0xa5,64)
		n := if size < 56 { size } else { u32(56) }; offset := if form == 1 { i32(9) } else { i32(8) }
		pointer := match form { 2 { u64(mapping + page - usize(n)) } 3 { u64(0) } 4 { u64(1) } 5 { u64(mapping + 2 * page) } 6 { u64(mapping + page) } 7 { u64(mapping + 2 * page - 28) } 8 { u64(scratch + offset) | (u64(1) << 55) } 9 { u64(mapping + page - 28) } else { u64(scratch + offset) } }
		pid := if variant == 1 { u64(u32(source)) | 0x1234567800000000 } else if variant == 2 { u64(u32(source)) | 0xffffffff00000000 } else { u64(i64(source)) }
		length := u64(size) | if variant == 3 { u64(0xffffffff00000000) } else { 0 }; word_flags := u64(flags) | if variant == 3 { u64(0x1234567800000000) } else { 0 }
		code := if source < 0 || pointer == 0 || size < 48 || usize(size) > page || flags != 0 { i32(C.EINVAL) } else if !live { i32(C.ESRCH) } else if form >= 3 { i32(C.EFAULT) } else { i32(0) }
		result := query(pid,pointer,length,word_flags)
		mut good := result.ret == if code == 0 { isize(0) } else { isize(-1) } && result.code == code
		if code == 0 { good = good && output(voidptr(usize(pointer)),n,C.SCHED_OTHER,0,reference) }
		good = good && bytes(scratch,96,if code == 0 && form < 2 { offset } else { -1 },if code == 0 && form < 2 { i32(n) } else { 0 })
		good = good && bytes(mapping + page - 64,64,if code == 0 && form == 2 { i32(64 - n) } else if code == C.EFAULT && form == 9 { 36 } else { -1 },if code == 0 && form == 2 { i32(n) } else if code == C.EFAULT && form == 9 { 28 } else { 0 })
		good = good && bytes(mapping + page,64,-1,0) && state(C.SCHED_OTHER,0)
		record(counts,if variant in [i32(1),2] { 1 } else if variant == 3 { 2 } else { 0 },good,ordinary,pid,length,word_flags,form,result,code)
	}
}
fn matrix(counts &Counts, ordinary bool, dead i32, mapping &u8, page usize, reference bool) {
	unsafe { self := C.getpid()
		for source in [i32(0),self,-1,i32(u32(0x80000000)),0x7fffffff,dead]! { live := source == 0 || source == self
			for size in [u32(0),1,47,48,49,50,51,52,53,54,55,56,57,u32(page),u32(page + 1),u32(-1)]! {
				for flags in [u32(0),1]! { for form in 0 .. 10 { for variant in 0 .. 4 { checked(counts,ordinary,source,live,size,flags,i32(form),i32(variant),mapping,page,reference) } } }
			}
		}
	}
}
fn policy_queries(counts &Counts, ordinary bool, policy i32, priority i32, sizes bool, reference bool) {
	unsafe { data := &u8(C.alloca(usize(72))); for pid in [i32(0),C.getpid()]! { for size in [u32(48),49,55,56,57]! {
		if !sizes && size in [u32(49),57] { continue }; C.memset(data,0xa5,72); result := query(u64(pid),u64(data + 8),u64(size),0); n := if size < 56 { size } else { u32(56) }
		record(counts,3,result.ret == 0 && result.code == 0 && output(data + 8,n,policy,priority,reference) && bytes(data,72,8,i32(n)) && state(policy,priority),ordinary,u64(pid),u64(size),0,-1,result,0)
	} } }
}
fn boundary(counts &Counts, ordinary bool, page usize, reference bool) {
	unsafe {
		mut mapping := &u8(usize(-1)); mut limit := u64(0)
		// Select the highest supported native user half without replacing memory.
		for bits in [i32(56),48,47]! { for reserved in [u64(0),u64(page)]! {
			candidate := (u64(1) << u32(bits)) - reserved
			mapping = &u8(C.mmap(voidptr(usize(candidate - u64(page))),page,C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS | 0x100000,-1,0))
			if mapping == &u8(usize(-1)) { continue }; if u64(mapping) != candidate - u64(page) { if C.munmap(mapping,page) != 0 { fatal(16) }; mapping = &u8(usize(-1)); continue }; limit = candidate; break
		}; if limit != 0 { break } }
		if limit == 0 { fatal(12) }; tail := mapping + page - 64
		for size in [u32(56),57,u32(page)]! { C.memset(tail,0xa5,64); pointer := limit - 56; result := query(0,pointer,u64(size),0); code := if size == 56 { i32(0) } else { i32(C.EFAULT) }; good := result.ret == if code == 0 { isize(0) } else { isize(-1) } && result.code == code && bytes(tail,64,if code == 0 { 8 } else { -1 },if code == 0 { 56 } else { 0 }) && (code != 0 || output(tail + 8,56,C.SCHED_OTHER,0,reference)) && state(C.SCHED_OTHER,0); record(counts,3,good,ordinary,0,u64(size),0,-2,result,code) }
		C.memset(tail,0xa5,64); result := query(0x7fffffff,limit - 56,u64(page),0); record(counts,3,result.ret == -1 && result.code == C.ESRCH && bytes(tail,64,-1,0) && state(C.SCHED_OTHER,0),ordinary,0x7fffffff,u64(page),0,-2,result,C.ESRCH)
		C.printf(c'LINUX ATTRQUERY RANGE: ordinary=%d limit=%lx page=%lu\n',i32(ordinary),limit,u64(page)); if C.munmap(mapping,page) != 0 { fatal(13) }
	}
}
fn cycle() bool {
	unsafe { data := &u8(C.alloca(usize(72))); C.memset(data,0xa5,72)
		short := query(0x1234567800000000,u64(data + 8),53,0); if short.ret != 0 || short.code != 0 || !output(data + 8,53,C.SCHED_OTHER,0,false) || !bytes(data,72,8,53) { return false }
		negative := query(0x7fffffff80000000,1,56,0); absent := query(0xffffffff7fffffff,1,56,0); null := query(0,0,56,0); oversized := query(0,u64(data),u64(C.sysconf(C._SC_PAGESIZE)) + 1,0)
		return negative.ret == -1 && negative.code == C.EINVAL && absent.ret == -1 && absent.code == C.ESRCH && null.ret == -1 && null.code == C.EINVAL && oversized.ret == -1 && oversized.code == C.EINVAL && state(C.SCHED_OTHER,0)
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
		for index in 0 .. int(before.rows) { if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] { good = false }; C.printf(c'LINUX ATTRQUERY SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n',i32(ordinary),before.sizes[index],before.live[index],after.live[index]) }
		C.printf(c'LINUX ATTRQUERY STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n',i32(ordinary),before.large,after.large,if good { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil); if C.close(observer) != 0 { good = false }; return good
	}
}
fn qualify(counts &Counts, ordinary bool, reference bool) bool {
	unsafe {
		C.alarm(600); if sizeof(Attr) != 56 { fatal(2) }; install(C.SCHED_RR,1)
		if ordinary && (C.setgroups(0,nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { fatal(3) }
		uid := if ordinary { u32(1000) } else { u32(0) }; if C.getuid() != uid || C.geteuid() != uid || !state(C.SCHED_RR,1) { fatal(4) }
		policy_queries(counts,ordinary,C.SCHED_RR,1,true,reference); install(C.SCHED_BATCH,0); policy_queries(counts,ordinary,C.SCHED_BATCH,0,false,reference); install(C.SCHED_OTHER,0)
		child := C.fork(); if child < 0 { fatal(5) }; if child == 0 { C._exit(0) }; mut status := i32(-1); if C.waitpid(child,&status,0) != child || status != 0 { fatal(6) }
		page := usize(C.sysconf(C._SC_PAGESIZE)); if page < 4096 || page > 16384 { fatal(7) }
		mapping := &u8(C.mmap(nil,3 * page,C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0)); if mapping == &u8(usize(-1)) { fatal(8) }; C.memset(mapping,0xa5,3 * page)
		if C.mprotect(mapping + page,page,C.PROT_READ) != 0 || C.mprotect(mapping + 2 * page,page,C.PROT_NONE) != 0 { fatal(9) }
		matrix(counts,ordinary,child,mapping,page,reference); boundary(counts,ordinary,page,reference)
		mut good := counts.failures[0] == 0 && counts.failures[1] == 0 && counts.failures[2] == 0 && counts.failures[3] == 0
		if good && !reference && !storage(ordinary) { good = false }
		record(counts,3,state(C.SCHED_OTHER,0),ordinary,0,0,0,-1,Query{},0)
		record(counts,3,bytes(mapping + page,64,-1,0),ordinary,0,0,0,-1,Query{},0)
		record(counts,3,bytes(mapping + page - 64,64,-1,0),ordinary,0,0,0,-1,Query{},0)
		if C.munmap(mapping,3 * page) != 0 { fatal(10) }
		for kind in 0 .. 4 { C.printf(c'LINUX ATTRQUERY CASES: ordinary=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),kind,counts.calls[kind],counts.failures[kind]); if counts.failures[kind] != 0 { good = false } }; C.alarm(0); C.fflush(nil); return good
	}
}
@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe { reference := argc == 2 && C.strcmp(argv[1],c'--reference') == 0; mut good := true
		for ordinary in [false,true]! {
			ends := &i32(C.alloca(usize(2 * sizeof(i32)))); if C.pipe2(ends,C.O_CLOEXEC) != 0 { fatal(14) }; child := C.fork(); if child < 0 { fatal(15) }
			if child == 0 { C.close(ends[0]); counts := &Counts(C.alloca(usize(sizeof(Counts)))); *counts = Counts{}; passed := qualify(counts,ordinary,reference); sent := C.write(ends[1],counts,usize(sizeof(Counts))) == isize(sizeof(Counts)); C.close(ends[1]); C._exit(if passed && sent { 0 } else { 1 }) }
			C.close(ends[1]); counts := &Counts(C.alloca(usize(sizeof(Counts)))); received := C.read(ends[0],counts,usize(sizeof(Counts))) == isize(sizeof(Counts)); C.close(ends[0]); mut status := i32(-1); completed := C.waitpid(child,&status,0) == child && status == 0; if !received || !completed { good = false }
			if received { for kind in 0 .. 4 { C.printf(c'LINUX ATTRQUERY FINAL: ordinary=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),kind,counts.calls[kind],counts.failures[kind]); if counts.failures[kind] != 0 { good = false } } }; C.fflush(nil)
		}
		if !good { C.puts(c'LINUX ATTRQUERY FAIL: query layout, arguments or state'); C.fflush(nil); return 1 }; C.puts(if reference { c'LINUX ATTRQUERY REFERENCE: PASS' } else { c'LINUX ATTRQUERY: PASS' }); C.fflush(nil); for { C.pause() }
	}; return 0
}
