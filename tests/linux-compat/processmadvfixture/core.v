// SPDX-License-Identifier: GPL-2.0-or-later
module processmadvfixture

#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.__errno_location() &i32
fn C._exit(i32)
fn C.close(i32) i32
fn C.fflush(voidptr) i32
fn C.fork() i32
fn C.getpid() i32
fn C.mincore(voidptr, u64, &u8) i32
fn C.mlock(voidptr, u64) i32
fn C.mmap(voidptr, u64, i32, i32, i32, i64) voidptr
fn C.munlock(voidptr, u64) i32
fn C.munmap(voidptr, u64) i32
fn C.pause() i32
fn C.pipe(&i32) i32
fn C.prctl(i32, ...) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.read(i32, voidptr, u64) i64
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.strcmp(&char, &char) i32
fn C.syscall(i64, ...) i64
fn C.sysconf(i32) i64
fn C.waitpid(i32, &i32, i32) i32
fn C.write(i32, voidptr, u64) i64

const willneed = u64(3)
const cold = u64(20)
const pageout = u64(21)
const cap_ptrace = u32(1) << 19
const cap_nice = u32(1) << 23

struct Iovec {
	base u64
	length u64
}

struct CapHeader {
	version u32 = 0x20080522
	pid i32
}

struct CapWord {
mut:
	effective u32
	permitted u32
	inheritable u32
}

fn need(ok bool, label &char) {
	if ok { return }
	unsafe {
		C.printf(c'LINUX PROCESSMADV FAIL: %s errno=%d\n', label, *C.__errno_location())
		C.fflush(nil)
		C._exit(1)
	}
}

fn advise(fd u64, vec voidptr, count u64, advice u64, flags u64) i64 {
	unsafe {
		result := C.syscall(i64(C.SYS_process_madvise), fd, vec, count, advice, flags)
		return if result < 0 { -i64(*C.__errno_location()) } else { result }
	}
}

fn mapped_len(fd i32, base u64, length u64, advice u64) i64 {
	vec := Iovec{base: base, length: length}
	return advise(u64(fd), &vec, 1, advice, 0)
}

fn pidfd(pid i32) i32 {
	fd := i32(C.syscall(i64(C.SYS_pidfd_open), pid, u64(0)))
	need(fd >= 0, c'open pidfd')
	return fd
}

fn region(length u64) voidptr {
	mapped := C.mmap(unsafe { nil }, length, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	need(mapped != voidptr(-1), c'map anonymous test range')
	return mapped
}

fn resident(base voidptr, page u64) bool {
	mut byte := u8(0)
	need(C.mincore(base, page, &byte) == 0, c'query page residency')
	return byte & 1 != 0
}

fn check_abi(fd i32, base u64, page u64) {
	unsafe {
		need(advise(u64(-1), nil, 1, cold, 1) == -C.EINVAL, c'flags precede vector and pidfd checks')
		need(advise(u64(-1), nil, 1025, cold, 0) == -C.EINVAL, c'oversized vector precedes pidfd lookup')
		need(advise(u64(-1), nil, 1, cold, 0) == -C.EFAULT, c'vector copyin precedes pidfd lookup')
		need(advise(u64(-1), nil, 0, 4, 0) == -C.EBADF, c'pidfd lookup precedes advice validation')
		need(advise(u64(fd), nil, 0, 4, 0) == -C.EINVAL, c'destructive advice is rejected')
		need(advise(u64(fd), nil, 0, cold, 0) == 0, c'empty vector has no ranges')
		need(advise(u64(fd), nil, 0, 25, 0) == 0, c'empty collapse vector accepts recognized advice')
		mut pipes := [2]i32{}
		need(C.pipe(&pipes[0]) == 0, c'open non-pidfd')
		need(advise(u64(pipes[0]), nil, 0, cold, 0) == -C.EBADF, c'pipe is not a pidfd')
		C.close(pipes[0])
		C.close(pipes[1])
		bad_length := Iovec{base: base, length: u64(1) << 63}
		need(advise(u64(-1), &bad_length, 1, cold, 0) == -C.EINVAL, c'reject lengths above ssize max')
		vec := Iovec{base: base, length: 1}
		need(advise(u64(fd) | (u64(5) << 32), &vec, 1, cold | (u64(6) << 32), u64(7) << 32) == 1,
			c'low argument words and original byte count')
		entries := [Iovec{base: base, length: 1}, Iovec{base: base + 1, length: 1}]!
		need(advise(u64(fd), &entries[0], 2, cold, 0) == 1, c'partial success on later unaligned entry')
		need(advise(u64(fd), &entries[1], 1, cold, 0) == -C.EINVAL, c'first unaligned entry fails')
		mut many := [9]Iovec{}
		for i in 0 .. many.len {
			many[i] = Iovec{base: base, length: page}
		}
		need(advise(u64(fd), &many[0], u64(many.len), cold, 0) == i64(page * u64(many.len)),
			c'vector above the stack threshold')
	}
}

fn check_paging(page u64, reference bool) {
	unsafe {
		fd := pidfd(C.getpid())
		mapped := region(3 * page)
		base := u64(mapped)
		first := &u8(mapped)
		last := &u8(voidptr(base + 2 * page))
		*first = 61
		*last = 72
		check_abi(fd, base, page)
		need(mapped_len(fd, base, page, cold) == i64(page) && *first == 61,
			c'cold preserves readable data')
		need(C.mlock(mapped, page) == 0, c'lock the first page')
		need(mapped_len(fd, base, page, cold) == -C.EINVAL, c'locked range rejects cold')
		need(mapped_len(fd, base, page, pageout) == -C.EINVAL, c'locked range rejects pageout')
		need(C.munlock(mapped, page) == 0, c'unlock the first page')
		need(C.munmap(voidptr(base + page), page) == 0, c'create a VMA hole')
		need(mapped_len(fd, base, page * 3, pageout) == -C.ENOMEM, c'pageout reports the intervening hole')
		if !reference {
			need(!resident(mapped, page) && !resident(last, page), c'pageout visits mappings on both sides of hole')
		}
		need(mapped_len(fd, base, page, willneed) == i64(page), c'prefetch swapped page')
		need(resident(mapped, page) && *first == 61 && *last == 72, c'willneed and late fault restore data')
		need(C.munmap(mapped, 3 * page) == 0, c'close split test range')
		sparse := region(64 * u64(1024) * 1024)
		need(mapped_len(fd, u64(sparse), page, willneed) == i64(page) && !resident(sparse, page),
			c'willneed keeps untouched anonymous pages sparse')
		need(C.munmap(sparse, 64 * u64(1024) * 1024) == 0, c'close sparse region')
		C.close(fd)
	}
}

fn check_remote(page u64, reference bool) {
	unsafe {
		shared := C.mmap(nil, page, C.PROT_READ | C.PROT_WRITE, C.MAP_SHARED | C.MAP_ANONYMOUS, -1, 0)
		need(shared != voidptr(-1), c'map shared anonymous page')
		shared_byte := &u8(shared)
		*shared_byte = 91
		mut report := [2]i32{}
		mut gate := [2]i32{}
		need(C.pipe(&report[0]) == 0 && C.pipe(&gate[0]) == 0, c'open remote synchronization pipes')
		child := C.fork()
		need(child >= 0, c'fork remote target')
		if child == 0 {
			C.close(report[0])
			C.close(gate[1])
			need(C.setgid(1000) == 0 && C.setuid(1000) == 0, c'set target real, effective and saved IDs')
			need(C.prctl(C.PR_SET_DUMPABLE, i64(1), i64(0), i64(0), i64(0)) == 0, c'make target dumpable')
			mapped := region(page)
			address := u64(mapped)
			byte := &u8(mapped)
			*byte = 83
			need(*shared_byte == 91, c'fault in the shared alias')
			need(C.write(report[1], &address, sizeof(u64)) == sizeof(u64), c'publish target address')
			mut done := u8(0)
			need(C.read(gate[0], &done, 1) == 1 && done == 1, c'wait for remote advice')
			if !reference {
				need(!resident(mapped, page), c'remote pageout stores the target page')
			}
			need(resident(shared, page) && *shared_byte == 91, c'pageout keeps the target shared alias resident')
			need(*byte == 83, c'remote pageout preserves target bytes')
			C._exit(0)
		}
		C.close(report[1])
		C.close(gate[0])
		mut address := u64(0)
		need(C.read(report[0], &address, sizeof(u64)) == sizeof(u64), c'read target address')
		C.close(report[0])
		fd := pidfd(child)
		header := CapHeader{}
		mut saved := [2]CapWord{}
		need(C.syscall(i64(C.SYS_capget), &header, &saved[0]) == 0, c'read caller capabilities')
		need(saved[0].effective & (cap_ptrace | cap_nice) == (cap_ptrace | cap_nice),
			c'start with ptrace and nice capabilities')
		mut changed := saved
		changed[0].effective &= ~(cap_ptrace | cap_nice)
		need(C.syscall(i64(C.SYS_capset), &header, &changed[0]) == 0, c'drop ptrace and nice from effective mask')
		need(mapped_len(fd, address, 1, cold) == -C.EACCES, c'deny a filesystem credential mismatch')
		C.syscall(i64(C.SYS_setfsuid), i64(1000))
		C.syscall(i64(C.SYS_setfsgid), i64(1000))
		need(C.syscall(i64(C.SYS_setfsuid), i64(-1)) == 1000
			&& C.syscall(i64(C.SYS_setfsgid), i64(-1)) == 1000, c'match target using filesystem credentials')
		need(mapped_len(fd, address, 1, cold) == -C.EPERM, c'remote advice also needs CAP_SYS_NICE')
		changed[0].effective |= cap_nice
		need(C.syscall(i64(C.SYS_capset), &header, &changed[0]) == 0, c'restore effective CAP_SYS_NICE')
		need(mapped_len(fd, address, 1, pageout) == 1, c'page out remote page with matching fscreds')
		need(mapped_len(fd, u64(shared), 1, pageout) == 1, c'advise a multiply mapped remote page')
		need(resident(shared, page) && *shared_byte == 91, c'pageout keeps the caller shared alias resident')
		C.syscall(i64(C.SYS_setfsuid), i64(0))
		C.syscall(i64(C.SYS_setfsgid), i64(0))
		need(C.syscall(i64(C.SYS_capset), &header, &saved[0]) == 0, c'restore caller capabilities')
		done := u8(1)
		need(C.write(gate[1], &done, 1) == 1, c'release target')
		C.close(gate[1])
		mut status := i32(0)
		need(C.waitpid(child, &status, 0) == child && status == 0, c'reap successful target')
		need(mapped_len(fd, address, 1, cold) == -C.ESRCH, c'reaped target is gone')
		need(mapped_len(fd, address, 1, 4) == -C.ESRCH, c'reaped pidfd takes precedence over unsupported advice')
		C.close(fd)
		need(C.munmap(shared, page) == 0, c'close shared region')
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference := argc > 1 && C.strcmp(argv[1], c'--reference') == 0
		page := C.sysconf(C._SC_PAGESIZE)
		need(page > 0, c'get page size')
		check_paging(u64(page), reference)
		check_remote(u64(page), reference)
		C.puts(c'LINUX PROCESSMADV SUMMARY: vector=partial fscreds=checked pager=preserved')
		C.puts(if reference { c'LINUX PROCESSMADV REFERENCE: PASS' } else { c'LINUX PROCESSMADV: PASS' })
		C.fflush(nil)
		for {
			C.pause()
		}
	}
	return 0
}
