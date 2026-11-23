// SPDX-License-Identifier: GPL-2.0-or-later
module taskpolicyfixture

#include <errno.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

@[typedef]
struct C.pthread_t {}

fn C.__atomic_load_n(&i32, i32) i32
fn C.__atomic_store_n(&i32, i32, i32)
fn C.__errno_location() &i32
fn C._exit(i32)
fn C.execl(&char, &char, ...) i32
fn C.fflush(voidptr) i32
fn C.fork() i32
fn C.madvise(voidptr, u64, i32) i32
fn C.mincore(voidptr, u64, &u8) i32
fn C.mmap(voidptr, u64, i32, i32, i32, i64) voidptr
fn C.munmap(voidptr, u64) i32
fn C.pause() i32
fn C.printf(&char, ...) i32
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.puts(&char) i32
fn C.sched_yield() i32
fn C.strcmp(&char, &char) i32
fn C.syscall(i64, ...) i64
fn C.sysconf(i32) i64
fn C.waitpid(i32, &i32, i32) i32

const default_mode = i64(0)
const preferred = i64(1)
const bind_mode = i64(2)
const interleave = i64(3)
const local_mode = i64(4)
const query_node_address = u64(3)
const query_allowed = u64(4)

struct Worker {
	page u64
	other bool
	exec_image bool
	reference bool
mut:
	stage i32
}

fn need(ok bool, label &char) {
	if ok { return }
	unsafe {
		C.printf(c'LINUX TASKPOLICY FAIL: %s errno=%d\n', label, *C.__errno_location())
		C.fflush(nil)
		C._exit(1)
	}
}

fn set_policy(mode i64, mask voidptr, maxnode u64) i64 {
	unsafe {
		ret := C.syscall(i64(C.SYS_set_mempolicy), mode, mask, maxnode)
		return if ret < 0 { -i64(*C.__errno_location()) } else { ret }
	}
}

fn set_mask(mode i64, mask u64) {
	need(set_policy(mode, unsafe { &mask }, 64) == 0, c'set memory policy')
}

fn get_policy(address u64, flags u64) (i64, u64) {
	unsafe {
		mut mode := i32(-1)
		mut mask := ~u64(0)
		need(C.syscall(i64(C.SYS_get_mempolicy), &mode, &mask, u64(64), address, flags) == 0,
			c'get memory policy')
		return i64(mode), mask
	}
}

fn has_policy(mode i64, mask u64) bool {
	current, nodes := get_policy(0, 0)
	return current == mode && nodes == mask
}

fn worker_mode(other bool) (i64, u64) {
	if other { return bind_mode, 2 }
	return local_mode, 0
}

fn page_node(address u64) i64 {
	node, _ := get_policy(address, query_node_address)
	return node
}

fn wait_stage(stage &i32, value i32) {
	for C.__atomic_load_n(stage, C.__ATOMIC_ACQUIRE) != value { C.sched_yield() }
}

fn worker(arg voidptr) voidptr {
	unsafe {
		mut state := &Worker(arg)
		need(has_policy(bind_mode, 1), c'pthread inherits creator policy')
		mode, mask := worker_mode(state.other)
		set_mask(mode, mask)
		if state.exec_image {
			if state.reference {
				C.execl(c'/sbin/probe', c'probe', c'--task-policy-exec', voidptr(nil))
			} else {
				C.execl(c'/sbin/init', c'init', c'--task-policy-exec', voidptr(nil))
			}
			need(false, c'nonleader exec returns only on failure')
		}
		*(&u8(state.page)) = 43
		need(page_node(state.page) == if state.other { i64(1) } else { i64(0) },
			c'worker allocates using its own policy')
		C.__atomic_store_n(&state.stage, 1, C.__ATOMIC_RELEASE)
		wait_stage(&state.stage, 2)

		child := C.fork()
		need(child >= 0, c'fork from the worker')
		if child == 0 {
			need(has_policy(mode, mask), c'fork inherits worker policy')
			set_mask(default_mode, 0)
			C._exit(0)
		}
		mut status := i32(-1)
		need(C.waitpid(child, &status, 0) == child && status == 0, c'wait for worker child')
		need(has_policy(mode, mask), c'worker keeps its policy after child changes it')
		return nil
	}
}

fn empty_region(length u64, page u64) u64 {
	unsafe {
		base := C.mmap(nil, length, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		need(base != voidptr(-1), c'map test pages')
		need(C.madvise(base, length, C.MADV_DONTNEED) == 0, c'discard eagerly populated pages')
		for offset := u64(0); offset < length; offset += page {
			mut resident := u8(255)
			need(C.mincore(voidptr(u64(base) + offset), page, &resident) == 0 && resident & 1 == 0,
				c'test pages start unpopulated')
		}
		return u64(base)
	}
}

fn check_set(allowed u64) {
	unsafe {
		set_mask(preferred, 0)
		need(has_policy(local_mode, 0), c'empty preferred mask becomes local')
		set_mask(preferred, allowed)
		need(has_policy(preferred, 1), c'preferred policy selects the first eligible node')
		set_mask(bind_mode | (i64(1) << 32), 1)
		need(has_policy(bind_mode, 1), c'policy mode is an int')
		mut node0 := u64(1)
		need(set_policy(default_mode, &node0, 64) == -C.EINVAL, c'default rejects a nonempty mask')
		need(set_policy(local_mode, &node0, 64) == -C.EINVAL, c'local rejects a nonempty mask')
		need(set_policy(bind_mode, nil, 0) == -C.EINVAL, c'bind rejects an empty mask')
		need(set_policy(bind_mode, voidptr(1), 64) == -C.EFAULT, c'bad mask pointer is a copy fault')
		need(set_policy(bind_mode, voidptr(1), 1) == -C.EINVAL, c'maxnode one names no bits')
		need(set_policy(-1, voidptr(1), 64) == -C.EINVAL, c'invalid mode precedes mask import')
		need(has_policy(bind_mode, 1), c'failed operations preserve current policy')
	}
}

fn check_tasks(page u64, other bool, reference bool) {
	unsafe {
		base := empty_region(2 * page, page)
		mut state := Worker{page: base + page, other: other}
		mut task := C.pthread_t{}
		need(C.pthread_create(&task, nil, worker, &state) == 0, c'create worker')
		wait_stage(&state.stage, 1)
		need(has_policy(bind_mode, 1), c'worker policy change leaves creator policy alone')
		*(&u8(base)) = 42
		need(page_node(base) == 0, c'creator still allocates on node zero')
		C.__atomic_store_n(&state.stage, 2, C.__ATOMIC_RELEASE)
		need(C.pthread_join(task, nil) == 0 && *(&u8(base + page)) == 43, c'join worker with shared mapping')
		need(C.munmap(voidptr(base), 2 * page) == 0, c'release shared-address-space test pages')

		child := C.fork()
		need(child >= 0, c'fork exec test process')
		if child == 0 {
			mut exec_state := Worker{other: other, exec_image: true, reference: reference}
			mut exec_task := C.pthread_t{}
			need(C.pthread_create(&exec_task, nil, worker, &exec_state) == 0, c'create exec worker')
			for { C.pause() }
		}
		mut status := i32(-1)
		need(C.waitpid(child, &status, 0) == child && status == 0, c'exec inherits nonleader policy')
	}
}

fn check_interleave(page u64, other bool) {
	unsafe {
		set_mask(interleave, if other { u64(3) } else { u64(1) })
		base := empty_region(3 * page, page)
		for index in [u64(2), u64(0), u64(1)]! {
			address := base + index * page
			*(&u8(address)) = 5
			need(page_node(address) == if other { i64((address / page) & 1) } else { i64(0) },
				c'task interleave follows the anonymous page index')
		}
		need(C.munmap(voidptr(base), 3 * page) == 0, c'release interleaved pages')
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		_, allowed := get_policy(0, query_allowed)
		need(allowed & 1 != 0, c'node zero is available')
		other := allowed & 2 != 0
		if argc > 1 && C.strcmp(argv[1], c'--task-policy-exec') == 0 {
			mode, mask := worker_mode(other)
			need(has_policy(mode, mask), c'replacement preserves the caller policy')
			C._exit(0)
		}
		reference := argc > 1 && C.strcmp(argv[1], c'--reference') == 0
		page_size := C.sysconf(C._SC_PAGESIZE)
		need(page_size >= 4096, c'get native page size')
		need(has_policy(default_mode, 0), c'fresh task starts in default mode')
		set_mask(bind_mode, 1)
		check_tasks(u64(page_size), other, reference)
		check_set(allowed)
		check_interleave(u64(page_size), other)
		if other { C.puts(c'LINUX TASKPOLICY NUMA: PASS') }
		C.puts(c'LINUX TASKPOLICY SUMMARY: validation=checked threads=isolated exec=checked')
		C.puts(if reference { c'LINUX TASKPOLICY REFERENCE: PASS' } else { c'LINUX TASKPOLICY: PASS' })
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
