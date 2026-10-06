// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// Independent process inspection/thread-attachment lock regression.
@[translated; has_globals]
module lockfixture

#include <lock-native-abi.h>

@[typedef] struct C.FILE {}
@[typedef] struct C.pthread_t {}
@[typedef] struct C.vtl_ulong {}
struct C.timespec { mut: tv_sec i64 tv_nsec i64 }
type ThreadCallback = fn (voidptr) voidptr
@[c_extern] __global C.stdout &C.FILE
@[c_extern] __global C.errno i32
__global pl_stop_readers i32
__global pl_readers_ready i32
__global pl_failures i32
__global pl_inspected_child i32
__global pl_observed_child i32
__global pl_snapshots usize
__global pl_process_clocks usize
__global pl_owner_pid i32

fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.setvbuf(&C.FILE, &char, i32, usize) i32
fn C.open(&char, i32, ...) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.snprintf(&char, usize, &char, ...) i32
fn C.strcmp(&char, &char) i32
fn C.strstr(&char, &char) &char
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.pthread_create(&C.pthread_t, voidptr, ThreadCallback, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.vtl_reader(voidptr) voidptr
fn C.vtl_short_thread(voidptr) voidptr
fn C.__atomic_add_fetch(voidptr, i32, i32) i32
fn C.__atomic_load_n(voidptr, i32) i32
fn C.__atomic_store_n(voidptr, i32, i32)
fn C.clock_getcpuclockid(i32, &i32) i32
fn C.clock_gettime(i32, &C.timespec) i32
fn C.nanosleep(&C.timespec, &C.timespec) i32
fn C.sched_yield() i32
fn C.getpid() i32
fn C.alarm(u32) u32
fn C.prctl(i32, ...) i32
fn C.pipe(&i32) i32
fn C.fork() i32
fn C._exit(i32)
fn C.execl(&char, &char, ...) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) bool
fn C.WEXITSTATUS(i32) i32
fn C.sync()
fn C.reboot(i32) i32
fn C.pause() i32

fn native_ulong(value usize) C.vtl_ulong {
	unsafe { word := C.vtl_ulong{}; C.memcpy(&word, &value, 8); return word }
}

fn fail(message &char) {
	unsafe {
		C.printf(c'FAIL: proc thread lock: %s (errno=%d)\n', message, C.errno)
		C.__atomic_add_fetch(&pl_failures, 1, C.__ATOMIC_RELAXED)
	}
}

fn has_failed() bool {
	unsafe { return C.__atomic_load_n(&pl_failures, C.__ATOMIC_RELAXED) != 0 }
}

fn read_proc(pid i32, suffix &char, required bool) bool {
	unsafe {
		path := [96]char{}; text := [2048]char{}
		C.snprintf(&path[0], sizeof(path), c'/proc/%d/%s', pid, suffix)
		fd := C.open(&path[0], C.O_RDONLY)
		if fd < 0 {
			if required { fail(c'open own process information') }
			return false
		}
		count := C.read(fd, &text[0], sizeof(text) - 1)
		read_error := C.errno
		C.close(fd)
		if count <= 0 {
			if required { C.errno = read_error; fail(c'read own process information') }
			return false
		}
		text[count] = 0
		if required && C.strcmp(suffix, c'status') == 0 && C.strstr(&text[0], c'State:\t') == nil {
			fail(c'own status keeps its state field during thread creation')
		}
		C.__atomic_add_fetch(&pl_snapshots, 1, C.__ATOMIC_RELAXED)
		return true
	}
}

@[export: 'vtl_reader']
pub fn reader(unused voidptr) voidptr {
	_ = unused
	unsafe {
		comm := [64]char{}
		C.snprintf(&comm[0], sizeof(comm), c'task/%d/comm', pl_owner_pid)
		process_clock := i32(0)
		if C.clock_getcpuclockid(pl_owner_pid, &process_clock) != 0 {
			fail(c'obtain explicit process CPU clock')
			return nil
		}
		C.__atomic_add_fetch(&pl_readers_ready, 1, C.__ATOMIC_RELEASE)
		for C.__atomic_load_n(&pl_stop_readers, C.__ATOMIC_ACQUIRE) == 0 {
			read_proc(pl_owner_pid, c'stat', true)
			read_proc(pl_owner_pid, c'status', true)
			read_proc(pl_owner_pid, &comm[0], true)
			stamp := C.timespec{}
			if C.clock_gettime(process_clock, &stamp) != 0 { fail(c'read process CPU clock') }
			else { C.__atomic_add_fetch(&pl_process_clocks, 1, C.__ATOMIC_RELAXED) }
			child := C.__atomic_load_n(&pl_inspected_child, C.__ATOMIC_ACQUIRE)
			if child > 0 {
				got_stat := read_proc(child, c'stat', false)
				got_status := read_proc(child, c'status', false)
				if got_stat && got_status { C.__atomic_store_n(&pl_observed_child, child, C.__ATOMIC_RELEASE) }
			}
			$if amd64 {
				pause := C.timespec{tv_nsec: 1000000}; C.nanosleep(&pause, nil)
			} $else { C.sched_yield() }
		}
		return nil
	}
}

@[export: 'vtl_short_thread']
pub fn short_thread(unused voidptr) voidptr { _ = unused; return unsafe { nil } }

@[export: 'main']
pub fn entry(argc i32, argv &&char) i32 {
	unsafe {
		if argc == 2 && C.strcmp(argv[1], c'--child') == 0 { return 0 }
		C.setvbuf(C.stdout, nil, C._IONBF, 0)
		C.alarm(120); pl_owner_pid = C.getpid()
		if C.prctl(C.PR_SET_NAME, c'proc-lock-test') != 0 { fail(c'name the inspected main thread') }
		C.puts(c'proc thread lock: starting concurrent inspection and thread churn')
		readers := [2]C.pthread_t{}; started := i32(0)
		for started < 2 {
			error := C.pthread_create(&readers[started], nil, C.vtl_reader, nil)
			if error != 0 { C.errno = error; fail(c'start process inspector'); break }
			started++
		}
		for C.__atomic_load_n(&pl_readers_ready, C.__ATOMIC_ACQUIRE) < started && !has_failed() { C.sched_yield() }
		for i := i32(0); i < 128 && !has_failed(); i++ {
			worker := C.pthread_t{}
			error := C.pthread_create(&worker, nil, C.vtl_short_thread, nil)
			if error == 0 { error = C.pthread_join(worker, nil) }
			if error != 0 { C.errno = error; fail(c'create and reap a thread during process inspection') }
		}
		if !has_failed() { C.puts(c'PASS: process inspection completes during sibling thread churn') }
		for i := i32(0); i < 32 && !has_failed(); i++ {
			gate := [2]i32{}
			if C.pipe(&gate[0]) != 0 { fail(c'create child exec gate'); break }
			child := C.fork()
			if child == 0 {
				C.close(gate[1]); command := char(0)
				if C.read(gate[0], &command, 1) != 1 { C._exit(126) }
				C.close(gate[0]); C.execl(c'/sbin/init', c'init', c'--child', &char(nil)); C._exit(127)
			}
			C.close(gate[0])
			if child < 0 { C.close(gate[1]); fail(c'fork child during process inspection'); break }
			C.__atomic_store_n(&pl_inspected_child, child, C.__ATOMIC_RELEASE)
			for C.__atomic_load_n(&pl_observed_child, C.__ATOMIC_ACQUIRE) != child && !has_failed() { C.sched_yield() }
			if !has_failed() && C.write(gate[1], c'X', 1) != 1 { fail(c'release child exec gate') }
			C.close(gate[1])
			status := i32(0)
			if C.waitpid(child, &status, 0) != child || !C.WIFEXITED(status) || C.WEXITSTATUS(status) != 0 {
				fail(c'fork, exec and reap during child process inspection')
			}
			C.__atomic_store_n(&pl_inspected_child, 0, C.__ATOMIC_RELEASE)
		}
		C.__atomic_store_n(&pl_stop_readers, 1, C.__ATOMIC_RELEASE)
		for i := i32(0); i < started; i++ { if C.pthread_join(readers[i], nil) != 0 { fail(c'join process inspector') } }
		if pl_snapshots < 100 || pl_process_clocks < 10 { fail(c'inspectors made concurrent progress') }
		C.printf(c'proc thread lock: %lu snapshots, %lu process CPU clocks\n', native_ulong(pl_snapshots), native_ulong(pl_process_clocks))
		if pl_failures == 0 { C.puts(c'VINIX PROC THREAD LOCK: PASS') }
		if pl_owner_pid != 1 { return if pl_failures != 0 { 1 } else { 0 } }
		C.sync(); C.reboot(C.RB_POWER_OFF); for { C.pause() }
		return 0
	}
}
