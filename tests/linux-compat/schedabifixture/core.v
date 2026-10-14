// SPDX-License-Identifier: GPL-2.0-or-later
module schedabifixture

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
#include <unistd.h>

struct C.sched_param { mut: sched_priority i32 }
struct Counts { mut: calls [4]u64 failures [4]u64 }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows i32 large u64 }
struct Query { ret isize code i32 }
fn C.alloca(usize) voidptr
fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.sched_getscheduler(i32) i32
fn C.sched_getparam(i32, &C.sched_param) i32
fn C.sched_setparam(i32, &C.sched_param) i32
fn C.sched_setscheduler(i32, i32, &C.sched_param) i32
fn C.sched_get_priority_min(i32) i32
fn C.sched_get_priority_max(i32) i32
fn C.memset(voidptr, i32, usize) voidptr
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.mprotect(voidptr, usize, i32) i32
fn C.munmap(voidptr, usize) i32
fn C.sysconf(i32) i64
fn C.getpid() i32
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

fn fatal(stage i32) { C.printf(c'LINUX SCHEDABI FAIL: setup or child protocol stage=%d errno=%d\n', stage, unsafe { *C.__errno_location() }); C.fflush(unsafe { nil }); C._exit(1) }
fn query(op i32, pid u64, policy u64, param u64, libc bool) Query {
	unsafe { slot := C.__errno_location(); *slot = 0; mut result := isize(-2)
		if libc {
			match op { 0 { result = C.sched_getscheduler(i32(u32(pid))) } 1 { result = C.sched_getparam(i32(u32(pid)), &C.sched_param(usize(param))) } 2 { result = C.sched_setparam(i32(u32(pid)), &C.sched_param(usize(param))) } 3 { result = C.sched_setscheduler(i32(u32(pid)), i32(u32(policy)), &C.sched_param(usize(param))) } 4 { result = C.sched_get_priority_min(i32(u32(policy))) } 5 { result = C.sched_get_priority_max(i32(u32(policy))) } else {} }
		} else {
			match op { 0 { result = C.syscall(C.SYS_sched_getscheduler, pid) } 1 { result = C.syscall(C.SYS_sched_getparam, pid, param) } 2 { result = C.syscall(C.SYS_sched_setparam, pid, param) } 3 { result = C.syscall(C.SYS_sched_setscheduler, pid, policy, param) } 4 { result = C.syscall(C.SYS_sched_get_priority_min, policy) } 5 { result = C.syscall(C.SYS_sched_get_priority_max, policy) } else {} }
		}; return Query{result,*slot}
	}
}
fn record(counts &Counts, kind i32, good bool, ordinary bool, op i32, pid u64, policy u64, form i32, result Query, expected i32) {
	unsafe { mut value := &Counts(counts); value.calls[kind]++; if !good { value.failures[kind]++; if value.failures[kind] <= 4 { C.printf(c'LINUX SCHEDABI DETAIL: ordinary=%d kind=%d op=%d pid=%lx policy=%lx form=%d call=%lu ret=%ld errno=%d expected=%d\n', i32(ordinary), kind, op, pid, policy, form, value.calls[kind], result.ret, result.code, expected); C.fflush(nil) } } }
}
fn normal() bool {
	unsafe { data := &C.sched_param(C.alloca(usize(sizeof(C.sched_param)))); return C.syscall(C.SYS_sched_getscheduler,0) == C.SCHED_OTHER && C.syscall(C.SYS_sched_getparam,0,data) == 0 && data.sched_priority == 0 }
}
fn restore() { unsafe { value := C.sched_param{sched_priority:0}; if C.syscall(C.SYS_sched_setscheduler,0,C.SCHED_OTHER,&value) != 0 || !normal() { fatal(1) } } }
fn unchanged(data &u8, except_at i32, expected u8) bool { unsafe { for index in 0 .. 32 { if index >= except_at && index < except_at + 4 { continue }; if data[index] != expected { return false } }; return true } }
fn checked(counts &Counts, ordinary bool, op i32, source i32, live bool, policy32 i32, form i32, prefix i32, libc bool, mapping &u8, page usize) {
	unsafe {
		scratch := &u8(C.alloca(usize(32))); C.memset(scratch,0xa5,32)
		zero := i32(0); one := i32(1); offset := if form == 1 { i32(9) } else { i32(8) }
		C.memcpy(scratch + offset, if form == 2 { voidptr(&one) } else { voidptr(&zero) }, 4)
		pointer := match form { 3 { u64(0) } 4 { u64(1) } 5 { u64(mapping + 2 * page) } 6 { u64(mapping + page) } 7 { u64(mapping + 2 * page - 2) } 8 { u64(scratch + offset) | (u64(1) << 55) } else { u64(scratch + offset) } }
		pid := if prefix == 1 || prefix == 4 { u64(u32(source)) | u64(0x1234567800000000) } else if prefix == 2 { u64(u32(source)) | u64(0xffffffff00000000) } else { u64(i64(source)) }
		policy := if prefix == 3 || prefix == 4 { u64(u32(policy32)) | u64(0xffffffff00000000) } else { u64(i64(policy32)) }
		mut code := i32(0)
		if op == 3 && policy32 < 0 { code = C.EINVAL }
		else if op != 0 && (source < 0 || form == 3) { code = C.EINVAL }
		else if source < 0 { code = C.EINVAL }
		else if op in [i32(2),3] && form in [i32(4),5,7,8] { code = C.EFAULT }
		else if !live { code = C.ESRCH }
		else if op == 1 && form in [i32(4),5,6,7,8] { code = C.EFAULT }
		else if op in [i32(2),3] && form == 2 { code = C.EINVAL }
		else if op == 3 && policy32 !in [i32(C.SCHED_OTHER),C.SCHED_BATCH] { code = C.EINVAL }
		// The pinned musl deliberately stubs these obsolete process wrappers.
		// Their ENOSYS refusal is a libc limitation, not a kernel ABI verdict.
		if libc { code = C.ENOSYS }
		result := query(op,pid,policy,pointer,libc)
		mut good := result.ret == if code == 0 { isize(0) } else { -1 } && result.code == code
		// Getters may copy a prefix before a cross-page EFAULT. Only the
		// accessible input fragment and guards outside their output are checked.
		if op == 1 && code == 0 { good = good && C.memcmp(scratch + offset,&zero,4) == 0 && unchanged(scratch,offset,0xa5) }
		else { good = good && unchanged(scratch,offset,0xa5) && C.memcmp(scratch + offset,if form == 2 { voidptr(&one) } else { voidptr(&zero) },4) == 0 }
		good = good && C.memcmp(mapping + page,c'\0\0\0\0',4) == 0
		if code == 0 && op == 3 { good = good && C.syscall(C.SYS_sched_getscheduler,0) == policy32; restore() }
		else { good = good && normal() }
		record(counts, if prefix == 0 { 0 } else { 1 }, good, ordinary, op, pid, policy, form, result, code)
	}
}
fn matrix(counts &Counts, ordinary bool, dead i32, mapping &u8, page usize) {
	unsafe {
		self := C.getpid()
		for source in [i32(0),self,-1,i32(u32(0x80000000)),0x7fffffff,dead]! {
			live := source == 0 || source == self
			for prefix in 0 .. 5 {
				checked(counts,ordinary,0,source,live,0,0,i32(prefix),false,mapping,page)
				for form in 0 .. 9 {
					for op in [i32(1),2]! { checked(counts,ordinary,op,source,live,0,i32(form),i32(prefix),false,mapping,page) }
					for policy in [i32(C.SCHED_OTHER),C.SCHED_BATCH,C.SCHED_DEADLINE,8,-1,i32(u32(0x80000000))]! { checked(counts,ordinary,3,source,live,policy,i32(form),i32(prefix),false,mapping,page) }
				}
			}
			checked(counts,ordinary,0,source,live,0,0,0,true,mapping,page)
			for form in 0 .. 9 { for op in [i32(1),2]! { checked(counts,ordinary,op,source,live,0,i32(form),0,true,mapping,page) }; for policy in [i32(C.SCHED_OTHER),C.SCHED_BATCH,C.SCHED_DEADLINE,8,-1,i32(u32(0x80000000))]! { checked(counts,ordinary,3,source,live,policy,i32(form),0,true,mapping,page) } }
		}
		for policy in [i32(C.SCHED_OTHER),C.SCHED_FIFO,C.SCHED_RR,C.SCHED_BATCH,C.SCHED_IDLE,C.SCHED_DEADLINE,-1,8,i32(u32(0x80000000))]! {
			for op in [i32(4),5]! { for prefix in 0 .. 5 {
				word := u64(u32(policy)) | if prefix == 1 { u64(0x1234567800000000) } else if prefix == 2 || prefix == 4 { u64(0xffffffff00000000) } else if prefix == 3 { u64(0x8000000000000000) } else { 0 }
				code := if policy < 0 || policy == 8 { i32(C.EINVAL) } else { i32(0) }; wanted := if code != 0 { isize(-1) } else if policy in [i32(C.SCHED_FIFO),C.SCHED_RR] { if op == 4 { isize(1) } else { isize(99) } } else { isize(0) }
				result := query(op,0,word,0,false); record(counts,if prefix == 0 { 2 } else { 1 },result.ret == wanted && result.code == code && normal(),ordinary,op,0,word,0,result,code)
			}; result := query(op,0,u64(u32(policy)),0,true); code := if policy < 0 || policy == 8 { i32(C.EINVAL) } else { i32(0) }; wanted := if code != 0 { isize(-1) } else if policy in [i32(C.SCHED_FIFO),C.SCHED_RR] { if op == 4 { isize(1) } else { isize(99) } } else { isize(0) }; record(counts,2,result.ret == wanted && result.code == code && normal(),ordinary,op,0,u64(u32(policy)),0,result,code) }
		}
	}
}
fn cycle() bool {
	unsafe {
		data := C.sched_param{sched_priority:0}; invalid := C.sched_param{sched_priority:1}
		if C.syscall(C.SYS_sched_setscheduler,0,C.SCHED_BATCH,&data) != 0 || C.syscall(C.SYS_sched_getscheduler,0) != C.SCHED_BATCH { return false }
		mut out := C.sched_param{sched_priority:42}; if C.syscall(C.SYS_sched_getparam,0,&out) != 0 || out.sched_priority != 0 || C.syscall(C.SYS_sched_setparam,0,&data) != 0 || C.syscall(C.SYS_sched_setscheduler,0,C.SCHED_OTHER,&data) != 0 { return false }
		for op in [i32(1),2,3]! { result := query(op,0,0,0,false); if result.ret != -1 || result.code != C.EINVAL { return false } }
		for op in [i32(2),3]! { result := query(op,0x7fffffff,0,1,false); if result.ret != -1 || result.code != C.EFAULT { return false } }
		value := query(2,0,0,u64(&invalid),false); return value.ret == -1 && value.code == C.EINVAL && normal()
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
		for index in 0 .. int(before.rows) { if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] { good = false }; C.printf(c'LINUX SCHEDABI SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n',i32(ordinary),before.sizes[index],before.live[index],after.live[index]) }
		C.printf(c'LINUX SCHEDABI STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n',i32(ordinary),before.large,after.large,if good { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil); if C.close(observer) != 0 { good = false }; return good
	}
}
fn qualify(counts &Counts, ordinary bool, reference bool) bool {
	unsafe { C.alarm(600); if ordinary && (C.setgroups(0,nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { fatal(2) }
		if !normal() { fatal(3) }; child := C.fork(); if child < 0 { fatal(4) }; if child == 0 { C._exit(0) }; mut status := i32(-1); if C.waitpid(child,&status,0) != child || status != 0 { fatal(5) }
		page := usize(C.sysconf(C._SC_PAGESIZE)); if page < 4096 || page > 16384 { fatal(6) }
		mapping := &u8(C.mmap(nil,3 * page,C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0)); if mapping == &u8(usize(-1)) { fatal(7) }; C.memset(mapping,0xa5,3 * page); C.memset(mapping + page,0,4)
		if C.mprotect(mapping + page,page,C.PROT_READ) != 0 || C.mprotect(mapping + 2 * page,page,C.PROT_NONE) != 0 { fatal(8) }
		matrix(counts,ordinary,child,mapping,page); mut good := counts.failures[0] == 0 && counts.failures[1] == 0 && counts.failures[2] == 0
		if counts.failures[0] == 0 && counts.failures[2] == 0 && !reference && !storage(ordinary) { good = false }
		record(counts,3,normal(),ordinary,-1,0,0,0,Query{},0); record(counts,3,C.memcmp(mapping + page,c'\0\0\0\0',4) == 0,ordinary,-1,0,0,0,Query{},0)
		if C.munmap(mapping,3 * page) != 0 { fatal(9) }
		for kind in 0 .. 4 { C.printf(c'LINUX SCHEDABI CASES: ordinary=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),kind,counts.calls[kind],counts.failures[kind]); if counts.failures[kind] != 0 { good = false } }; C.alarm(0); C.fflush(nil); return good
	}
}
@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe { reference := argc == 2 && C.strcmp(argv[1],c'--reference') == 0; mut good := true
		for ordinary in [false,true]! {
			ends := &i32(C.alloca(usize(2 * sizeof(i32)))); if C.pipe2(ends,C.O_CLOEXEC) != 0 { fatal(10) }; child := C.fork(); if child < 0 { fatal(11) }
			if child == 0 { C.close(ends[0]); counts := &Counts(C.alloca(usize(sizeof(Counts)))); *counts = Counts{}; passed := qualify(counts,ordinary,reference); sent := C.write(ends[1],counts,usize(sizeof(Counts))) == isize(sizeof(Counts)); C.close(ends[1]); C._exit(if passed && sent { 0 } else { 1 }) }
			C.close(ends[1]); counts := &Counts(C.alloca(usize(sizeof(Counts)))); received := C.read(ends[0],counts,usize(sizeof(Counts))) == isize(sizeof(Counts)); C.close(ends[0]); mut status := i32(-1); completed := C.waitpid(child,&status,0) == child && status == 0; if !received || !completed { good = false }
			if received { for kind in 0 .. 4 { C.printf(c'LINUX SCHEDABI FINAL: ordinary=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),kind,counts.calls[kind],counts.failures[kind]); if counts.failures[kind] != 0 { good = false } } }; C.fflush(nil)
		}
		if !good { C.puts(c'LINUX SCHEDABI FAIL: scheduling words or error precedence'); C.fflush(nil); return 1 }; C.puts(if reference { c'LINUX SCHEDABI REFERENCE: PASS' } else { c'LINUX SCHEDABI: PASS' }); C.fflush(nil); for { C.pause() }
	}; return 0
}
