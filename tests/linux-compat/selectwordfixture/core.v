// SPDX-License-Identifier: GPL-2.0-or-later
module selectwordfixture

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
struct Targets { mut: source i32 path i32 peer i32 page voidptr length usize }

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
	C.printf(c'LINUX SELECTWORD FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil }); C._exit(90)
}
fn check(mut totals Totals, good bool) {
	totals.checks++
	if !good { totals.failures++ }
}
fn high_word(index int) u64 {
	return match index { 0 { u64(0) } 1 { u64(1)<<32 } 2 { u64(0x7fffffff)<<32 }
		3 { u64(0x80000000)<<32 } else { u64(0xffffffff)<<32 } }
}
fn low_word(index int) int {
	return match index { 0 { 0 } 1 { 32 } 2 { 33 } 3 { 64 } 4 { 65 }
		5 { 1023 } 6 { 1024 } 7 { -1 } else { -2147483648 } }
}
fn targets() Targets {
	unsafe {
		mut t := Targets{}
		t.path = C.open(c'/tmp/selectword-file', C.O_PATH)
		mut sockets := [2]i32{}
		if t.path < 0 || C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &sockets[0]) != 0 { fatal(1) }
		t.source = sockets[0]; t.peer = sockets[1]
		// Match Linux's fd-table capacity to Vinix's initial 1024 slots.
		if C.dup3(t.source,1023,C.O_CLOEXEC) != 1023 || C.write(t.peer,c'Q',1) != 1 { fatal(2) }
		t.length = usize(C.sysconf(C._SC_PAGESIZE))
		t.page = C.mmap(nil,t.length,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0)
		if t.page == voidptr(isize(-1)) { fatal(16) }
		initial := u64(1)<<14
		if C.syscall(isize(C.SYS_rt_sigprocmask),2,&initial,nil,8) != 0 { fatal(3) }
		return t
	}
}
fn install(t &Targets, kind int, target i32) {
	if C.dup3(if kind == 3 { t.path } else { t.source },target,C.O_CLOEXEC) != target { fatal(4) }
	if kind == 2 && C.close(target) != 0 { fatal(5) }
}
fn call(api int, word u64, buffers &Guard, sets int) isize {
	unsafe {
		r := if sets&1 != 0 { voidptr(&buffers[0].words[0]) } else { nil }
		w := if sets&2 != 0 { voidptr(&buffers[1].words[0]) } else { nil }
		e := if sets&4 != 0 { voidptr(&buffers[2].words[0]) } else { nil }
		mut ts := C.timespec{}
		mask := u64(1)<<9
		pair := MaskArg{mask: &mask, size: 8}
		errno_slot := C.__errno_location(); *errno_slot = 0
		if api == 0 { return C.syscall(isize(C.SYS_pselect6),word,r,w,e,&ts,&pair) }
		$if amd64 {
			mut tv := C.timeval{}
			return C.syscall(isize(C.SYS_select),word,r,w,e,&tv)
		}
		$else { fatal(6); return -1 }
	}
}
fn probe(t &Targets, api int, high int, low int, kind int, target int, sets int, readonly bool) Totals {
	unsafe {
		nfds := low_word(low)
		words := if nfds < 0 { 0 } else { (nfds+63)/64 }
		input := &Guard(C.alloca(usize(sizeof(Guard))))
		*input = Guard{before: 0xabcddcba12344321, after: 0x87654321fedcba98}
		for word in words .. 16 { input.words[word] = 0x1122334455667788 }
		if kind != 0 { input.words[target/64] |= u64(1)<<u64(target%64) }
		local := &Guard(C.alloca(usize(3*sizeof(Guard))))
		buffers := if readonly { &Guard(t.page) } else { local }
		for index in 0 .. 3 { buffers[index] = *input }
		selected := kind != 0 && nfds > target
		code := if nfds < 0 { i32(C.EINVAL) } else if kind == 2 && selected { i32(C.EBADF) }
			else if readonly && words > 0 { i32(C.EFAULT) } else { i32(0) }
		mut expected := isize(0)
		if code != 0 { expected = -1 }
		else if selected {
			for set in 0 .. 3 { if sets&(1<<set) != 0 && (kind == 3 || set != 2) { expected++ } }
		}
		if readonly && C.mprotect(t.page,t.length,C.PROT_READ) != 0 { fatal(17) }
		result := call(api,high_word(high)|u64(u32(nfds)),buffers,sets)
		actual_code := *C.__errno_location()
		if readonly && C.mprotect(t.page,t.length,C.PROT_READ|C.PROT_WRITE) != 0 { fatal(18) }
		mut totals := Totals{}
		check(mut totals,result == expected)
		check(mut totals,actual_code == code)
		for set in 0 .. 3 {
			wanted := &Guard(C.alloca(usize(sizeof(Guard))))
			*wanted = *input
			if code == 0 && sets&(1<<set) != 0 {
				for word in 0 .. words { wanted.words[word] = 0 }
				if selected && (kind == 3 || set != 2) { wanted.words[target/64] |= u64(1)<<u64(target%64) }
			}
			check(mut totals,C.memcmp(&buffers[set],wanted,sizeof(Guard)) == 0)
		}
		mut mask := u64(0)
		queried := C.syscall(isize(C.SYS_rt_sigprocmask),0,nil,&mask,8)
		check(mut totals,queried == 0 && mask == u64(1)<<14)
		return totals
	}
}
fn qualify(t &Targets, apis int) Totals {
	mut total := Totals{}
	for api in 0 .. apis { for high in 0 .. 5 {
		mut group := Totals{}
		for low in 0 .. 9 { for kind in 0 .. 4 { for layout in 0 .. 3 {
			target := if layout == 0 { 32 } else if layout == 1 { 64 } else { 1022 }
			install(t,kind,i32(target))
			for sets in 1 .. 8 {
				result := probe(t,api,high,low,kind,target,sets,false)
				if group.failures == 0 && result.failures != 0 {
					C.printf(c'LINUX SELECTWORD FIRST: uid=%u api=%d high=%d low=%d kind=%d target=%d sets=%d failures=%d\n',C.getuid(),api,high,low,kind,target,sets,result.failures)
				}
				group.checks += result.checks; group.failures += result.failures
			}
			if kind != 2 && C.close(i32(target)) != 0 { fatal(7) }
		} } }
		install(t,1,32)
		for sets in 1 .. 8 {
			result := probe(t,api,high,1,1,32,sets,true)
			group.checks += result.checks; group.failures += result.failures
		}
		if C.close(32) != 0 { fatal(19) }
		C.printf(c'LINUX SELECTWORD CASE: uid=%u gid=%u api=%d high=%d checks=%d failures=%d\n',C.getuid(),C.getgid(),api,high,group.checks,group.failures)
		total.checks += group.checks; total.failures += group.failures
	} }
	return total
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		C.alarm(600)
		reference := argc == 2 && C.strcmp(argv[1],c'--reference') == 0
		if C.chmod(c'/tmp',0o1777) != 0 { fatal(8) }
		file := C.open(c'/tmp/selectword-file',C.O_CREAT|C.O_EXCL|C.O_RDWR,u32(0o666))
		if file < 0 || C.close(file) != 0 || C.chmod(c'/tmp/selectword-file',0o666) != 0 { fatal(9) }
		mut apis := 1
		$if amd64 { apis = 2 }
		mut total := Totals{}
		mut storage_good := true
		for ordinary in [false,true]! {
			mut channel := [2]i32{}
			if C.pipe(&channel[0]) != 0 { fatal(10) }
			C.fflush(nil)
			pid := C.fork()
			if pid < 0 { fatal(11) }
			if pid == 0 {
				C.close(channel[0])
				if ordinary && (C.setgid(2000) != 0 || C.setuid(1000) != 0) { fatal(12) }
				t := targets()
				sum := qualify(&t,apis)
				good := if reference { C.printf(c'LINUX SELECTWORD STORAGE: uid=%u SKIP reference\n',C.getuid()); true } else { storage(&t,apis) }
				mut answer := [3]int{}
				answer[0] = sum.checks; answer[1] = sum.failures; answer[2] = if good { 0 } else { 1 }
				if C.write(channel[1],&answer[0],sizeof(answer)) != isize(sizeof(answer)) { fatal(13) }
				C.fflush(nil); C._exit(0)
			}
			C.close(channel[1]); mut answer := [3]int{}
			if C.read(channel[0],&answer[0],sizeof(answer)) != isize(sizeof(answer)) { fatal(14) }
			C.close(channel[0]); mut status := i32(0)
			if C.waitpid(pid,&status,0) != pid || status != 0 { fatal(15) }
			total.checks += answer[0]; total.failures += answer[1]
			if answer[2] != 0 { storage_good = false }
		}
		C.printf(c'LINUX SELECTWORD SUMMARY: checks=%d failures=%d\n',total.checks,total.failures)
		C.printf(c'LINUX SELECTWORD: %s\n',if total.failures == 0 && storage_good { &char(c'PASS') } else { &char(c'FAIL') })
		C.fflush(nil); C.alarm(0)
		for { C.pause() }
	}
	return 0
}
