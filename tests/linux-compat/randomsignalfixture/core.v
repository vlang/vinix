// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module randomsignalfixture

#include <alloca.h>
#include <errno.h>
#include <grp.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/random.h>
#include <sys/syscall.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <unistd.h>

@[typedef]
struct C.sigset_t {}
@[typedef]
struct C.siginfo_t {}
struct C.sigaction {
mut:
	sa_sigaction fn (i32, &C.siginfo_t, voidptr)
	sa_mask C.sigset_t
	sa_flags i32
}
struct C.timeval { tv_sec i64 tv_usec i64 }
struct C.itimerval { it_interval C.timeval it_value C.timeval }
struct Counts { mut: calls [3]u64 failures [3]u64 }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows i32 large u64 }
struct Result { ret isize code i32 }
__global ( alarms i32 alarm_result isize )

fn C.alloca(usize) voidptr
fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.getrandom(voidptr, usize, u32) isize
fn C.sigaction(i32, &C.sigaction, &C.sigaction) i32
fn C.sigemptyset(&C.sigset_t) i32
fn C.sigaddset(&C.sigset_t, i32) i32
fn C.sigismember(&C.sigset_t, i32) i32
fn C.sigprocmask(i32, &C.sigset_t, &C.sigset_t) i32
fn C.sigpending(&C.sigset_t) i32
fn C.raise(i32) i32
fn C.setitimer(i32, &C.itimerval, &C.itimerval) i32
fn C.getpagesize() i32
fn C.getuid() u32
fn C.geteuid() u32
fn C.getgid() u32
fn C.getegid() u32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.mprotect(voidptr, usize, i32) i32
fn C.munmap(voidptr, usize) i32
fn C.memset(voidptr, i32, usize) voidptr
fn C.pipe2(&i32, i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.usleep(u32) i32
fn C.pause() i32
fn C.strcmp(&char, &char) i32
fn C.sscanf(&char, &char, ...) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32

fn fatal(stage i32) {
	C.printf(c'LINUX RANDOMSIGNAL FAIL: setup stage=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil }); C._exit(1)
}

fn handler(signum i32, _info &C.siginfo_t, context voidptr) {
	unsafe {
		if signum != C.SIGALRM { C._exit(2) }
		alarms++
		$if arm64 { alarm_result = *&isize(u64(context) + 184) }
		$else { alarm_result = *&isize(u64(context) + 144) }
	}
}

fn timer(microseconds i64) {
	value := C.itimerval{it_value: C.timeval{tv_usec: microseconds}}
	if C.setitimer(C.ITIMER_REAL, &value, unsafe { nil }) != 0 { fatal(3) }
}

fn mask(block bool) {
	mut set := C.sigset_t{}
	if C.sigemptyset(&set) != 0 || C.sigaddset(&set, C.SIGALRM) != 0
		|| C.sigprocmask(if block { C.SIG_BLOCK } else { C.SIG_UNBLOCK }, &set, unsafe { nil }) != 0 { fatal(4) }
}

fn pending() bool {
	mut set := C.sigset_t{}
	if C.sigpending(&set) != 0 { fatal(5) }
	return C.sigismember(&set, C.SIGALRM) == 1
}

fn invoke(buffer voidptr, count usize, flags u32, form i32) Result {
	unsafe {
		slot := C.__errno_location(); *slot = 0
		ret := if form == 1 { C.getrandom(buffer, count, flags) }
			else { C.syscall(isize(C.SYS_getrandom), buffer, count, u64(flags) | u64(0x9abcdef000000000)) }
		return Result{ret, *slot}
	}
}

// There are no mapping faults in this probe. Only the returned prefix may change.
fn guarded(start &u8, request usize, result isize) bool {
	unsafe {
		if result < 0 || usize(result) > request { return false }
		for index in 0 .. 32 { if *(&u8(u64(start) - 32 + u64(index))) != 0xa5 { return false } }
		for index := usize(result); index < request + 32; index++ { if start[index] != 0xa5 { return false } }
		if result >= 32 {
			mut changed := false
			for index in 0 .. int(result) { if start[index] != 0xa5 { changed = true; break } }
			if !changed { return false }
		}
		return true
	}
}

fn record(counts &Counts, kind i32, good bool) {
	unsafe { counts.calls[kind]++; if !good { counts.failures[kind]++ } }
}

fn matrix(counts &Counts, ordinary bool, start &u8, page usize) {
	unsafe {
		for restart in [false, true]! {
			mut action := C.sigaction{sa_sigaction: handler, sa_flags: C.SA_SIGINFO | if restart { C.SA_RESTART } else { 0 }}
			if C.sigemptyset(&action.sa_mask) != 0 || C.sigaction(C.SIGALRM, &action, nil) != 0 { fatal(6) }
			for flags in [u32(0), 1, 2, 3, 4, 5]! { for form in [i32(0), 1]! {
				// An 8 MiB transfer must still be active when this one-shot fires.
				// The signal frame must contain this very syscall's positive short result.
				request := usize(8 * 1024 * 1024)
				C.memset(voidptr(u64(start) - 32), 0xa5, request + 64)
				alarms = 0; alarm_result = -12345
				timer(1000)
				result := invoke(start, request, flags, form)
				timer(0)
				guards := guarded(start, request, result.ret)
				good := result.ret > 0 && usize(result.ret) < request && usize(result.ret) % page == 0
					&& result.code == 0 && alarms == 1 && alarm_result == result.ret && guards
				record(counts, 0, good)
				C.printf(c'LINUX RANDOMSIGNAL TRANSFER: ordinary=%d restart=%d flags=%u form=%d request=%lu result=%ld errno=%d seen=%d frame=%ld guards=%d\n',
					i32(ordinary), i32(restart), flags, form, request, result.ret, result.code, alarms, alarm_result, i32(guards))
				C.fflush(nil)
				// Already pending but blocked signals cannot shorten a transfer.
				blocked := usize(65536)
				C.memset(voidptr(u64(start) - 32), 0xa5, blocked + 64)
				alarms = 0; mask(true)
				if C.raise(C.SIGALRM) != 0 || !pending() { fatal(7) }
				full := invoke(start, blocked, flags, form)
				blocked_good := full.ret == isize(blocked) && full.code == 0 && alarms == 0 && pending()
					&& guarded(start, blocked, full.ret)
				mask(false)
				record(counts, 1, blocked_good && alarms == 1 && !pending())
				// Short requests remain complete, including across a timer signal.
				for small in [usize(0), 1, 32, 255, 256]! {
					C.memset(voidptr(u64(start) - 32), 0xa5, small + 64)
					alarms = 0; timer(1)
					short := invoke(start, small, flags, form)
					timer(0)
					record(counts, 2, short.ret == isize(small) && short.code == 0 && alarms <= 1 && guarded(start, small, short.ret))
				}
			} }
		}
	}
}

fn snapshot(fd i32, destination &Slabs) bool {
	unsafe {
		mut counts := &Slabs(destination); *counts = Slabs{}
		mut data := [4096]char{}
		length := C.pread(fd, &data[0], 4095, 0)
		if length <= 0 || length >= 4096 { return false }
		data[int(length)] = 0
		mut position := 0; mut large := false
		for position < int(length) {
			mut size := u64(0); mut duplicate := u64(0); mut live := u64(0); mut pages := u64(0)
			if C.sscanf(&data[position], c'size-%lu %lu %lu %lu', &size, &duplicate, &live, &pages) == 4 {
				if counts.rows >= 32 || size != duplicate { return false }
				counts.sizes[counts.rows] = size; counts.live[counts.rows] = live; counts.rows++
			} else if C.sscanf(&data[position], c'large - - %lu', &counts.large) == 1 { large = true }
			for position < int(length) && data[position] != char(10) { position++ }; position++
		}
		return counts.rows > 0 && large
	}
}

fn cycle(start &u8, page usize) bool {
	unsafe {
		for flags in [u32(0), 1, 2, 3, 4, 5]! { for form in [i32(0), 1]! {
			C.memset(voidptr(u64(start) - 32), 0xa5, page + 65)
			result := invoke(start, page + 1, flags, form)
			if result.ret != isize(page + 1) || result.code != 0 || !guarded(start, page + 1, result.ret) { return false }
		} }
		return pending() && alarms == 0
	}
}

fn storage(start &u8, page usize, ordinary bool) bool {
	unsafe {
		observer := C.open(c'/proc/slabinfo', 0)
		if observer < 0 { return false }; defer { C.close(observer) }
		alarms = 0; mask(true); defer { mask(false) }
		if C.raise(C.SIGALRM) != 0 || !pending() { return false }
		for _ in 0 .. 32 { if !cycle(start, page) { return false } }
		C.usleep(13000000)
		before := &Slabs(C.alloca(usize(sizeof(Slabs))))
		after := &Slabs(C.alloca(usize(sizeof(Slabs))))
		if !snapshot(observer, before) { return false }
		for _ in 0 .. 200 { if !cycle(start, page) { return false } }
		C.usleep(13000000)
		if !snapshot(observer, after) { return false }
		mut good := before.rows == after.rows && before.large == after.large
		for index in 0 .. int(before.rows) {
			if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] { good = false }
			C.printf(c'LINUX RANDOMSIGNAL SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[index], before.live[index], after.live[index])
		}
		C.printf(c'LINUX RANDOMSIGNAL STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if good { &char(c'PASS') } else { &char(c'FAIL') })
		C.fflush(nil); return good
	}
}

fn qualify(counts &Counts, ordinary bool, reference bool) bool {
	unsafe {
		uid := if ordinary { u32(1000) } else { u32(0) }
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(uid) != 0 || C.setuid(uid) != 0) { fatal(8) }
		if C.getuid() != uid || C.geteuid() != uid || C.getgid() != uid || C.getegid() != uid { fatal(9) }
		page := usize(C.getpagesize())
		if page != 4096 && page != 16384 { fatal(10) }
		length := usize(8 * 1024 * 1024) + 3 * page
		base := C.mmap(nil, length, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if base == voidptr(-1) { fatal(11) }
		if C.mprotect(voidptr(u64(base) + u64(page)), length - 2 * page, C.PROT_READ | C.PROT_WRITE) != 0 { fatal(12) }
		start := &u8(u64(base) + u64(page) + 49)
		mut ready := false
		for _ in 0 .. 100 {
			result := invoke(start, 32, 1, 0)
			if result.ret == 32 && result.code == 0 { ready = true; break }
			if result.ret != -1 || result.code != C.EAGAIN { fatal(13) }; C.usleep(10000)
		}
		if !ready { fatal(14) }
		C.printf(c'LINUX RANDOMSIGNAL TOPOLOGY: ordinary=%d uid=%u page=%lu readiness=seeded\n', i32(ordinary), uid, page)
		matrix(counts, ordinary, start, page)
		mut good := counts.failures[0] == 0 && counts.failures[1] == 0 && counts.failures[2] == 0
		if good && !reference && !storage(start, page, ordinary) { good = false }
		if C.munmap(base, length) != 0 { fatal(15) }
		for kind in 0 .. 3 {
			C.printf(c'LINUX RANDOMSIGNAL CASES: ordinary=%d kind=%d calls=%lu failures=%lu\n', i32(ordinary), kind, counts.calls[kind], counts.failures[kind])
			if counts.failures[kind] != 0 { good = false }
		}
		C.fflush(nil); return good
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		if sizeof(Counts) != 48 { fatal(16) }
		reference := argc == 2 && C.strcmp(argv[1], c'--reference') == 0
		mut good := true
		for ordinary in [false, true]! {
			mut pipe := [i32(-1), i32(-1)]!
			if C.pipe2(&pipe[0], 0) != 0 { fatal(17) }
			child := C.fork(); if child < 0 { fatal(18) }
			if child == 0 {
				C.close(pipe[0]); counts := &Counts(C.alloca(usize(sizeof(Counts)))); *counts = Counts{}
				passed := qualify(counts, ordinary, reference)
				sent := C.write(pipe[1], counts, sizeof(Counts)) == isize(sizeof(Counts)); C.close(pipe[1])
				C._exit(if passed && sent { 0 } else { 1 })
			}
			C.close(pipe[1]); counts := &Counts(C.alloca(usize(sizeof(Counts)))); *counts = Counts{}
			received := C.read(pipe[0], counts, sizeof(Counts)) == isize(sizeof(Counts)); C.close(pipe[0])
			mut status := i32(-1)
			completed := C.waitpid(child, &status, 0) == child && status == 0
			if !received || !completed { good = false }
			if received { for kind in 0 .. 3 {
				C.printf(c'LINUX RANDOMSIGNAL FINAL: ordinary=%d kind=%d calls=%lu failures=%lu\n', i32(ordinary), kind, counts.calls[kind], counts.failures[kind])
				if counts.failures[kind] != 0 { good = false }
			} }; C.fflush(nil)
		}
		if !good { C.puts(c'LINUX RANDOMSIGNAL FAIL: interruption, masks, short requests or guards'); C.fflush(nil); return 1 }
		C.puts(if reference { c'LINUX RANDOMSIGNAL REFERENCE: PASS' } else { c'LINUX RANDOMSIGNAL: PASS' }); C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
