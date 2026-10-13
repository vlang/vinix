// SPDX-License-Identifier: GPL-2.0-or-later
module duppublishfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

@[typedef]
struct C.pthread_t {}
struct C.stat { st_ino u64 st_mode u32 st_uid u32 st_gid u32 st_size i64 }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows i32 large u64 }
struct State {
mut:
	source i32
	method i32
	wanted i32
	loops i32
	go i32
	done i32
	ack i32
	bad i32
	ret i32
}
fn C.alloca(usize) voidptr
fn C.__errno_location() &i32
fn C.__atomic_store_n(&i32, i32, i32)
fn C.__atomic_load_n(&i32, i32) i32
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.sched_yield() i32
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.fcntl(i32, i32, ...) i32
fn C.dup(i32) i32
fn C.dup2(i32, i32) i32
fn C.dup3(i32, i32, i32) i32
fn C.fstat(i32, &C.stat) i32
fn C.write(i32, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.lseek(i32, i64, i32) i64
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

fn publish(argument voidptr) voidptr {
	unsafe {
		mut state := &State(argument)
		for iteration := i32(1); iteration <= state.loops; iteration++ {
			for C.__atomic_load_n(&state.go, 2) == 0 { C.sched_yield() }
			flags := if state.wanted == 0 { i32(0) } else { i32(C.O_CLOEXEC) }
			ret := match state.method {
				0 { C.dup(state.source) }
				1 { C.dup2(state.source, 63) }
				2, 3 { C.dup3(state.source, 63, flags) }
				4 { C.fcntl(state.source, C.F_DUPFD, i32(63)) }
				else { C.fcntl(state.source, C.F_DUPFD_CLOEXEC, i32(63)) }
			}
			if ret != 63 { state.bad++ }
			C.__atomic_store_n(&state.done, iteration, 3)
			for C.__atomic_load_n(&state.ack, 2) < iteration { C.sched_yield() }
			if state.method == 0 || state.method >= 4 { if C.close(63) != 0 { state.bad++ } }
		}
		return nil
	}
}
fn flags_phase(source i32, seed i32, method i32, ordinary bool) bool {
	unsafe {
		wanted := if method == 3 || method == 5 { i32(C.FD_CLOEXEC) } else { i32(0) }
		dynamic := method == 0 || method >= 4
		if C.fcntl(source, C.F_SETFD, if wanted == 0 { C.FD_CLOEXEC } else { i32(0) }) != 0 { return false }
		if dynamic { C.close(63) } else if C.dup3(seed, 63, if wanted == 0 { i32(0) } else { i32(C.O_CLOEXEC) }) != 63 { return false }
		defer { C.close(63) }
		mut state := &State(C.alloca(usize(sizeof(State)))); *state = State{source: source, method: method, wanted: wanted, loops: 128}
		mut worker := C.pthread_t{}
		if C.pthread_create(&worker, nil, publish, state) != 0 { return false }
		C.__atomic_store_n(&state.go, 1, 3)
		mut ack := i32(0); mut samples := u64(0); mut bad := u64(0); mut forks := i32(0); mut bad_forks := i32(0); mut post_bad := i32(0)
		for ack < 128 {
			error_slot := C.__errno_location(); *error_slot = 0
			value := C.fcntl(63, C.F_GETFD); code := *error_slot; samples++
			if value != wanted && !(dynamic && value == -1 && code == C.EBADF) { bad++ }
			done := C.__atomic_load_n(&state.done, 2)
			if forks < 16 && (samples % 8 == 0 || (done > ack && done % 2 == 0)) {
				child := C.fork()
				if child == 0 {
					*error_slot = 0; inherited := C.fcntl(63, C.F_GETFD); inherited_code := *error_slot
					C._exit(if inherited == wanted || (dynamic && inherited == -1 && inherited_code == C.EBADF) { 0 } else { 1 })
				}
				mut status := i32(-1)
				if child < 0 || C.waitpid(child, &status, 0) != child || status != 0 { bad_forks++ }; forks++
			}
			if done > ack {
				if C.fcntl(63, C.F_GETFD) != wanted { post_bad++ }
				ack = done; C.__atomic_store_n(&state.ack, ack, 3)
			}
			C.sched_yield()
		}
		if C.pthread_join(worker, nil) != 0 { C._exit(1) }
		good := state.bad == 0 && bad == 0 && bad_forks == 0 && post_bad == 0 && forks == 16 && samples >= 128
		C.printf(c'LINUX DUPPUBLISH FLAGS: ordinary=%d method=%d calls=128 samples=%lu bad=%lu forks=%d fork_bad=%d post_bad=%d producer_bad=%d %s\n', i32(ordinary), method, samples, bad, forks, bad_forks, post_bad, state.bad, if good { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil)
		return good
	}
}
fn closing_publish(argument voidptr) voidptr {
	unsafe {
		mut state := &State(argument)
		for iteration := i32(1); iteration <= state.loops; iteration++ {
			for C.__atomic_load_n(&state.go, 2) < iteration { C.sched_yield() }
			state.ret = C.dup3(state.source, 63, 0)
			C.__atomic_store_n(&state.done, iteration, 3)
		}
		return nil
	}
}
fn close_phase(source i32, seed i32, ordinary bool) bool {
	unsafe {
		if C.fcntl(source, C.F_SETFD, C.FD_CLOEXEC) != 0 { return false }
		mut state := &State(C.alloca(usize(sizeof(State)))); *state = State{source: source, loops: 200}
		before := &C.stat(C.alloca(usize(sizeof(C.stat)))); observed := &C.stat(C.alloca(usize(sizeof(C.stat))))
		if C.fstat(source, before) != 0 || C.fstat(seed, observed) != 0 { return false }
		seed_ino := observed.st_ino; seed_mode := observed.st_mode; seed_size := observed.st_size
		mut worker := C.pthread_t{}; if C.pthread_create(&worker, nil, closing_publish, state) != 0 { return false }
		mut bad := i32(0); mut during := i32(0)
		for iteration := i32(1); iteration <= 200; iteration++ {
			if C.dup3(seed, 63, 0) != 63 { bad++ }
			C.__atomic_store_n(&state.go, iteration, 3)
			for {
				if C.fstat(63, observed) == 0 && observed.st_ino == before.st_ino { break }
				if C.__atomic_load_n(&state.done, 2) >= iteration {
					// Completion can race the previous sample. The worker now
					// waits for the next go value, so take a stable final sample.
					if C.fstat(63, observed) != 0 || observed.st_ino != before.st_ino { bad++ }
					break
				}
				C.sched_yield()
			}
			if C.__atomic_load_n(&state.done, 2) < iteration { during++ }
			if C.close(63) != 0 || C.dup3(seed, 64, C.O_CLOEXEC) != 64 { bad++ }
			for C.__atomic_load_n(&state.done, 2) < iteration { C.sched_yield() }
			if state.ret != 63 || C.fcntl(64, C.F_GETFD) != C.FD_CLOEXEC || C.fstat(64, observed) != 0 || observed.st_ino != seed_ino || observed.st_mode != seed_mode || observed.st_size != seed_size || C.lseek(64, 0, C.SEEK_CUR) != 5 { bad++ }
			if C.close(64) != 0 { bad++ }
		}
		if C.pthread_join(worker, nil) != 0 { C._exit(1) }
		good := bad == 0
		C.close(63); C.close(64)
		C.printf(c'LINUX DUPPUBLISH CLOSE: ordinary=%d calls=200 during=%d bad=%d %s\n', i32(ordinary), during, bad, if good { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil)
		return good
	}
}
fn storage_cycle(source i32, seed i32) bool {
	unsafe {
		for method in 0 .. 5 {
			ret := match method { 0 { C.dup(source) } 1 { C.dup2(source, 63) } 2 { C.dup3(source, 63, 0) } 3 { C.fcntl(source, C.F_DUPFD, i32(63)) } else { C.fcntl(source, C.F_DUPFD_CLOEXEC, i32(63)) } }
			if ret != 63 || C.fcntl(63, C.F_GETFD) != if method == 4 { C.FD_CLOEXEC } else { i32(0) } { C.close(63); return false }; if C.close(63) != 0 { return false }
		}
		if C.dup3(seed, 64, C.O_CLOEXEC) != 64 || C.fcntl(64, C.F_GETFD) != C.FD_CLOEXEC { C.close(64); return false }
		return C.close(64) == 0 && C.fcntl(source, C.F_GETFD) == C.FD_CLOEXEC
	}
}

fn snapshot(fd i32, destination &Slabs) bool {
	unsafe {
		mut counts := &Slabs(destination); *counts = Slabs{}; mut data := [4096]char{}
		length := C.pread(fd, &data[0], 4095, 0); if length <= 0 || length >= 4096 { return false }; data[int(length)] = 0
		mut position := 0; mut large := false
		for position < int(length) {
			mut size := u64(0); mut duplicate := u64(0); mut live := u64(0); mut pages := u64(0)
			if C.sscanf(&data[position], c'size-%lu %lu %lu %lu', &size, &duplicate, &live, &pages) == 4 {
				if counts.rows >= 32 || size != duplicate { return false }; counts.sizes[counts.rows] = size; counts.live[counts.rows] = live; counts.rows++
			} else if C.sscanf(&data[position], c'large - - %lu', &counts.large) == 1 { large = true }
			for position < int(length) && data[position] != char(10) { position++ }; position++
		}
		return counts.rows > 0 && large
	}
}
fn storage(dirfd i32, filefd i32, ordinary bool) bool {
	unsafe {
		original := C.open(c'/proc/slabinfo', C.O_RDONLY); if original < 0 { return false }; observer := C.fcntl(original, C.F_DUPFD_CLOEXEC, i32(80)); C.close(original); if observer != 80 { if observer >= 0 { C.close(observer) }; return false }; defer { C.close(observer) }
		for _ in 0 .. 32 { if !storage_cycle(dirfd, filefd) { return false } }; C.usleep(13000000)
		before := &Slabs(C.alloca(usize(sizeof(Slabs)))); after := &Slabs(C.alloca(usize(sizeof(Slabs))))
		if !snapshot(observer, before) { return false }; for _ in 0 .. 200 { if !storage_cycle(dirfd, filefd) { return false } }; C.usleep(13000000)
		if !snapshot(observer, after) { return false }; mut good := before.rows == after.rows && before.large == after.large
		for i in 0 .. int(before.rows) { if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] { good = false }; C.printf(c'LINUX DUPPUBLISH SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[i], before.live[i], after.live[i]) }
		C.printf(c'LINUX DUPPUBLISH STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if good { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil); return good
	}
}
fn qualify(source i32, seed i32, ordinary bool, reference_run bool) bool {
	unsafe {
		C.alarm(600)
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		for fd in 0 .. 63 { if C.fcntl(i32(fd), C.F_GETFD) < 0 && C.dup3(seed, i32(fd), 0) != fd { return false } }
		mut good := true
		for method in 0 .. 6 { if !flags_phase(source, seed, i32(method), ordinary) { good = false } }
		// A failed visibility control ends the cohort without dereferencing a
		// deliberately closed publication on the known-bad baseline kernel.
		if good && !close_phase(source, seed, ordinary) { good = false }
		if good && !reference_run && !storage(source, seed, ordinary) { good = false }
		C.alarm(0); return good
	}
}
@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference_run := argc == 2 && C.strcmp(argv[1], c'--reference') == 0
		source := C.open(c'/tmp/linux-duppublish-source', C.O_RDWR | C.O_CREAT | C.O_EXCL | C.O_CLOEXEC, i32(0o644)); if source < 0 { return 1 }; defer { C.close(source) }
		seed := C.open(c'/tmp/linux-duppublish-seed', C.O_RDWR | C.O_CREAT | C.O_EXCL, i32(0o644)); if seed < 0 { return 1 }; defer { C.close(seed) }
		if C.write(source, c'publish-data-ok!', 16) != 16 || C.lseek(source, 3, C.SEEK_SET) != 3 || C.write(seed, c'publish-seed-ok!', 16) != 16 || C.lseek(seed, 5, C.SEEK_SET) != 5 { return 1 }
		mut good := true
		for ordinary in [true, false]! {
			C.fflush(nil); child := C.fork(); if child < 0 { good = false; break }
			if child == 0 { C._exit(if qualify(source, seed, ordinary, reference_run) { 0 } else { 1 }) }
			mut status := i32(-1); if C.waitpid(child, &status, 0) != child || status != 0 { good = false }
		}
		mut data := [16]char{}
		if C.lseek(source, 0, C.SEEK_CUR) != 3 || C.pread(source, &data[0], 16, 0) != 16 || C.fcntl(source, C.F_GETFD) != C.FD_CLOEXEC { good = false }
		for i in 0 .. 16 { if data[i] != c'publish-data-ok!'[i] { good = false } }
		if C.lseek(seed, 0, C.SEEK_CUR) != 5 || C.pread(seed, &data[0], 16, 0) != 16 || C.fcntl(seed, C.F_GETFD) != 0 { good = false }
		for i in 0 .. 16 { if data[i] != c'publish-seed-ok!'[i] { good = false } }
		if !good { C.puts(c'LINUX DUPPUBLISH FAIL: visibility, fork snapshots, close/reuse or retention'); C.fflush(nil); return 1 }
		if reference_run { C.puts(c'LINUX DUPPUBLISH REFERENCE: PASS') } else { C.puts(c'LINUX DUPPUBLISH: PASS') }; C.fflush(nil); for { C.pause() }
	}
	return 0
}
