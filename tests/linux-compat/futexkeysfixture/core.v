// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module futexkeysfixture

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <time.h>

@[typedef]
struct C.pthread_t {}
struct C.timespec {
	tv_sec isize
	tv_nsec isize
}
struct Wait {
	address &i32
	operation isize
}
fn C.pthread_create(&C.pthread_t, voidptr, fn(voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.syscall(isize, ...) isize
fn C.mmap(voidptr, usize, i32, i32, i32, isize) voidptr
fn C.munmap(voidptr, usize) i32
fn C.mount(&char, &char, &char, usize, voidptr) i32
fn C.umount2(&char, i32) i32
fn C.open(&char, i32, ...) i32
fn C.unlink(&char) i32
fn C.__errno_location() &i32
fn C.strcmp(&char, &char) i32
fn C.ftruncate(i32, isize) i32
fn C.close(i32) i32
fn C.sysconf(i32) isize
fn C.usleep(u32) i32
fn C.puts(&char) i32
fn C.printf(&char, ...) i32
fn C.fflush(voidptr) i32
fn C.pause() i32
fn C.__atomic_store_n(&i32, i32, i32)
fn C.__atomic_load_n(&i32, i32) i32

__global ( ready i32 completed i32 result i32 )

fn waiter(argument voidptr) voidptr {
	unsafe {
		request := &Wait(argument)
		deadline := C.timespec{tv_sec: 5}
		C.__atomic_store_n(&ready, 1, 5)
		value := C.syscall(isize(C.SYS_futex), request.address, request.operation, isize(0), &deadline, isize(0), isize(0))
		C.__atomic_store_n(&result, i32(value), 5)
		C.__atomic_store_n(&completed, 1, 5)
	}
	return unsafe { nil }
}

fn check(address &i32, wait_op isize, wrong &i32, wrong_op isize, correct &i32, correct_op isize) bool {
	unsafe {
		C.__atomic_store_n(&ready, 0, 5)
		C.__atomic_store_n(&completed, 0, 5)
		C.__atomic_store_n(&result, -2, 5)
		mut worker := C.pthread_t{}
		request := Wait{address, wait_op}
		if C.pthread_create(&worker, nil, waiter, voidptr(&request)) != 0 { return false }
		for i := 0; i < 1000 && C.__atomic_load_n(&ready, 5) == 0; i++ { C.usleep(1000) }
		if C.__atomic_load_n(&ready, 5) != 1 { return false }
		C.usleep(100000)
		other := C.syscall(isize(C.SYS_futex), wrong, wrong_op, isize(1), isize(0), isize(0), isize(0))
		C.usleep(20000)
		if other != 0 || C.__atomic_load_n(&completed, 5) != 0 {
			C.printf(c'LINUX FUTEXKEYS FAIL: wait=%ld wrong-wake=%ld returned=%ld completed=%d\n', wait_op, wrong_op, other, C.__atomic_load_n(&completed, 5))
			return false
		}
		own := C.syscall(isize(C.SYS_futex), correct, correct_op, isize(1), isize(0), isize(0), isize(0))
		if own != 1 || C.pthread_join(worker, nil) != 0 || C.__atomic_load_n(&result, 5) != 0 { return false }
		return true
	}
}

fn shared_wake(address &i32) isize {
	return C.syscall(isize(C.SYS_futex), address, isize(1), isize(1), isize(0), isize(0), isize(0))
}

fn wake_after_regrowth(fd i32, page isize, first &i32, alias &i32, other &i32) bool {
	if C.ftruncate(fd, page) != 0 { return false }
	if shared_wake(first) != -1 || unsafe { *C.__errno_location() } != C.EFAULT {
		C.puts(c'LINUX FUTEXKEYS FAIL: wake on a truncated page did not return EFAULT')
		return false
	}
	// Fault another inode while the original frame is available for reuse.
	unsafe { C.__atomic_store_n(other, 0, 5) }
	if shared_wake(other) != 0 {
		C.puts(c'LINUX FUTEXKEYS FAIL: a different inode woke the waiter')
		return false
	}
	if C.ftruncate(fd, 2 * page) != 0 { return false }
	unsafe {
		if shared_wake(first - int(page / 4)) != 0 || shared_wake(alias + 1) != 0 {
			C.puts(c'LINUX FUTEXKEYS FAIL: the same inode woke the waiter at a different offset')
			return false
		}
	}
	// futex2 WAKE (454) must find the same queue as legacy WAIT and REQUEUE.
	woken := C.syscall(isize(454), alias, isize(0xffffffff), isize(1), isize(2))
	if woken != 1 {
		code := if woken < 0 { unsafe { *C.__errno_location() } } else { i32(0) }
		C.printf(c'LINUX FUTEXKEYS FAIL: alias wake after regrowth returned %ld (errno %d)\n', woken, code)
		return false
	}
	return true
}

fn check_regrowth(fd i32, page isize) bool {
	unsafe {
		other_fd := i32(C.syscall(isize(C.SYS_memfd_create), c'futex-unrelated', isize(0)))
		if other_fd < 0 { return false }
		defer { C.close(other_fd) }
		if C.ftruncate(fd, 2 * page) != 0 || C.ftruncate(other_fd, 2 * page) != 0 { return false }
		first := &i32(C.mmap(nil, usize(2 * page), 3, 1, fd, 0))
		alias := &i32(C.mmap(nil, usize(page), 3, 1, fd, page))
		other := &i32(C.mmap(nil, usize(page), 3, 1, other_fd, page))
		if voidptr(first) == voidptr(-1) || voidptr(alias) == voidptr(-1) || voidptr(other) == voidptr(-1) { return false }
		defer {
			C.munmap(first, usize(2 * page))
			C.munmap(alias, usize(page))
			C.munmap(other, usize(page))
		}
		source := first + int(page / 4) + 2
		target := source + 1
		C.__atomic_store_n(source, 0, 5)
		mut worker := C.pthread_t{}
		request := Wait{source, 0}
		if C.pthread_create(&worker, nil, waiter, voidptr(&request)) != 0 { return false }
		mut queued := isize(0)
		for attempt := 0; attempt < 1000 && queued == 0; attempt++ {
			// Moving one waiter proves it has actually reached the queue.
			queued = C.syscall(isize(C.SYS_futex), source, isize(4), isize(0), isize(1), target, isize(0))
			if queued == 0 { C.usleep(1000) }
		}
		if queued != 1 { C.printf(c'LINUX FUTEXKEYS FAIL: requeue returned %ld\n', queued) }
		matched := queued == 1 && wake_after_regrowth(fd, page, target, alias + 3, other + 3)
		return C.pthread_join(worker, nil) == 0 && matched && C.__atomic_load_n(&result, 5) == 0
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		page := C.sysconf(C._SC_PAGESIZE)
		fd := i32(C.syscall(isize(C.SYS_memfd_create), c'futex-keys', isize(0)))
		if page <= 0 || fd < 0 || C.ftruncate(fd, page) != 0 { return 1 }
		first := &i32(C.mmap(nil, usize(page), 3, 1, fd, 0))
		alias := &i32(C.mmap(nil, usize(page), 3, 1, fd, 0))
		local := &i32(C.mmap(nil, usize(page), 3, 2, fd, 0))
		if voidptr(first) == voidptr(-1) || voidptr(alias) == voidptr(-1) || voidptr(local) == voidptr(-1) { return 1 }
		C.__atomic_store_n(first, 0, 5)
		if C.__atomic_load_n(alias, 5) != 0 || C.__atomic_load_n(local, 5) != 0 { return 1 }
		for iteration := 0; iteration < 4; iteration++ {
			// A private queue is identified by address space and virtual address.
			if !check(first, 128, alias, 129, first, 129) { return 1 }
			// Shared waiters match aliases, but never private calls at that address.
			if !check(first, 0, first, 129, alias, 1) { return 1 }
			if !check(first, 128, first, 1, first, 129) { return 1 }
			// Flags also distinguish queues on an ordinary private mapping.
			if !check(local, 128, local, 1, local, 129) { return 1 }
			if !check(local, 0, local, 129, local, 1) { return 1 }
		}
		if C.munmap(first, usize(page)) != 0 || C.munmap(alias, usize(page)) != 0
			|| C.munmap(local, usize(page)) != 0 { return 1 }
		if !check_regrowth(fd, page) || C.close(fd) != 0 { return 1 }
		if C.mount(c'tmpfs', c'/tmp', c'tmpfs', 0, nil) != 0 { return 1 }
		file := C.open(c'/tmp/futex-regrowth', C.O_CREAT | C.O_EXCL | C.O_RDWR, i32(0o600))
		if file < 0 || C.unlink(c'/tmp/futex-regrowth') != 0 || !check_regrowth(file, page)
			|| C.close(file) != 0 || C.umount2(c'/tmp', 0) != 0 { return 1 }
		C.puts(c'LINUX FUTEXKEYS SUMMARY: 20 alias and flag checks plus 2 truncate and regrowth checks with legacy WAIT and REQUEUE and futex2 WAKE')
		C.puts(if argc > 1 && C.strcmp(argv[1], c'--reference') == 0 {
			c'LINUX FUTEXKEYS REFERENCE: PASS'
		} else {
			c'LINUX FUTEXKEYS: PASS'
		})
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
