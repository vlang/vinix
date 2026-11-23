// SPDX-License-Identifier: GPL-2.0-or-later
module membsyncfixture

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

fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.puts(&char) i32
fn C.printf(&char, ...) i32
fn C.fflush(voidptr) i32
fn C._exit(i32)
fn C.pause() i32
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.sched_getcpu() i32
fn C.sched_yield() i32
fn C.sysconf(i32) isize
fn C.memfd_create(&char, u32) i32
fn C.ftruncate(i32, i64) i32
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.mprotect(voidptr, usize, i32) i32
fn C.munmap(voidptr, usize) i32
fn C.close(i32) i32
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.__builtin___clear_cache(voidptr, voidptr)
fn C.__atomic_store_n(&i32, i32, i32)
fn C.__atomic_load_n(&i32, i32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.execve(&char, &&char, &&char) i32
fn C.strcmp(&char, &char) i32

const sync_core = u64(1 << 5)
const register_sync_core = u64(1 << 6)
const get_registrations = u64(1 << 9)
const high_word = u64(0x7fffa5a5) << 32
const iterations = 200

type Jit = fn () i32

struct Exchange {
	code Jit
	page usize
mut:
	published i32
	executed i32 = -1
}

fn need(ok bool, label &char) {
	if ok { return }
	unsafe {
		C.printf(c'LINUX MEMBSYNC FAIL: %s errno=%d\n', label, *C.__errno_location())
		C.fflush(nil)
		C._exit(1)
	}
}

fn barrier(command u64, flags u64) i64 {
	unsafe {
		value := C.syscall(isize(C.SYS_membarrier), command, flags, i32(-1))
		return if value < 0 { -i64(*C.__errno_location()) } else { i64(value) }
	}
}

fn pin(number u32) {
	unsafe {
		mask := u64(1) << number
		need(C.syscall(isize(C.SYS_sched_setaffinity), 0, sizeof(u64), &mask) == 0,
			c'set affinity to the requested CPU')
		// Vinix applies the new mask when the scheduler next places the task.
		for _ in 0 .. 10000 {
			if C.sched_getcpu() == i32(number) { return }
			C.sched_yield()
		}
		C.printf(c'LINUX MEMBSYNC affinity requested=%u actual=%d\n', number, C.sched_getcpu())
		need(false, c'run on the requested CPU')
	}
}

fn emit(writer voidptr, reader voidptr, value i32) {
	unsafe {
		$if arm64 {
			code := [u32(0x52800000) | (u32(value) << 5), u32(0xd65f03c0)]!
			C.memcpy(writer, &code[0], sizeof(code))
			C.__builtin___clear_cache(writer, voidptr(usize(writer) + sizeof(code)))
			C.__builtin___clear_cache(reader, voidptr(usize(reader) + sizeof(code)))
		} $else {
			code := [u8(0xb8), u8(value), u8(value >> 8), 0, 0, 0xc3]!
			C.memcpy(writer, &code[0], sizeof(code))
		}
	}
}

fn competing_calls(page usize) {
	unsafe {
		scratch := C.mmap(nil, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		need(isize(scratch) != -1, c'map private TLB test page')
		for value in 0 .. iterations {
			*(&u8(scratch)) = u8(value)
			need(C.mprotect(scratch, page, C.PROT_READ) == 0, c'revoke write access during rendezvous')
			need(barrier(sync_core, 0) == 0, c'concurrent expedited instruction synchronization')
			need(C.mprotect(scratch, page, C.PROT_READ | C.PROT_WRITE) == 0,
				c'restore write access during rendezvous')
		}
		need(C.munmap(scratch, page) == 0, c'unmap private TLB test page')
	}
}

fn receiver(arg voidptr) voidptr {
	unsafe {
		mut shared := &Exchange(arg)
		pin(1)
		need(barrier(sync_core, 0) == 0, c'thread shares the address space registration')
		for generation in 0 .. iterations + 1 {
			for C.__atomic_load_n(&shared.published, 2) != generation {}
			need(shared.code() == generation, c'remote CPU executed the published instructions')
			C.__atomic_store_n(&shared.executed, i32(generation), 3)
		}
		competing_calls(shared.page)
		return nil
	}
}

fn exercise_cores() {
	unsafe {
		page := C.sysconf(C._SC_PAGESIZE)
		need(page > 0, c'get native page size')
		fd := C.memfd_create(c'membsync', 0)
		need(fd >= 0 && C.ftruncate(fd, page) == 0, c'create backing file for alias mappings')
		writer := C.mmap(nil, usize(page), C.PROT_READ | C.PROT_WRITE, C.MAP_SHARED, fd, 0)
		reader := C.mmap(nil, usize(page), C.PROT_READ | C.PROT_EXEC, C.MAP_SHARED, fd, 0)
		need(isize(writer) != -1 && isize(reader) != -1 && writer != reader && C.close(fd) == 0,
			c'map separate writable and executable aliases')
		emit(writer, reader, 0)
		mut shared := Exchange{code: Jit(reader), page: usize(page)}
		mut worker := C.pthread_t{}
		pin(0)
		need(C.pthread_create(&worker, nil, receiver, voidptr(&shared)) == 0, c'start remote CPU thread')
		for generation in 1 .. iterations + 1 {
			for C.__atomic_load_n(&shared.executed, 2) != generation - 1 {}
			emit(writer, reader, i32(generation))
			need(barrier(sync_core, 0) == 0, c'synchronize before publishing edited JIT code')
			C.__atomic_store_n(&shared.published, i32(generation), 3)
		}
		for C.__atomic_load_n(&shared.executed, 2) != iterations {}
		competing_calls(usize(page))
		need(C.pthread_join(worker, nil) == 0, c'join remote CPU thread')
		need(C.munmap(reader, usize(page)) == 0 && C.munmap(writer, usize(page)) == 0, c'unmap JIT aliases')
		C.printf(c'LINUX MEMBSYNC SUMMARY: cpus=0,1 jit=%d concurrent=%d\n', iterations, iterations * 2)
	}
}

fn check_registration_lifetime() {
	unsafe {
		pid := C.fork()
		need(pid >= 0, c'fork registered process')
		if pid == 0 {
			need(barrier(get_registrations, 0) == i64(all_registrations)
				&& barrier(sync_core, 0) == 0 && barrier(private_expedited, 0) == 0,
				c'fork inherits all registrations')
			args := [&char(c'membsync'), &char(c'--exec-check'), &char(nil)]!
			env := [&char(nil)]!
			need(C.execve(c'/tmp/no-membsync-image', &args[0], &env[0]) == -1
				&& *C.__errno_location() == C.ENOENT
				&& barrier(get_registrations, 0) == i64(all_registrations) && barrier(sync_core, 0) == 0,
				c'failed exec retains registration')
			C.execve(c'/proc/self/exe', &args[0], &env[0])
			need(false, c'exec probe image')
		}
		mut status := i32(-1)
		need(C.waitpid(pid, &status, 0) == pid && status == 0, c'exec starts with a fresh registration')
		need(barrier(get_registrations, 0) == i64(all_registrations) && barrier(sync_core, 0) == 0,
			c'parent registration survives child exit')
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		if argc > 1 && C.strcmp(argv[1], c'--exec-check') == 0 {
			need(barrier(get_registrations, 0) == 0 && barrier(sync_core, 0) == -C.EPERM
				&& barrier(private_expedited, 0) == -C.EPERM,
				c'successful exec restores unregistered state')
			return 0
		}
		reference := argc > 1 && C.strcmp(argv[1], c'--reference') == 0
		C.syscall(isize(C.SYS_mount), c'proc', c'/proc', c'proc', 0, nil)
		supported := barrier(0, 0)
		required := global_barrier | global_expedited | private_expedited | sync_core | all_registrations | get_registrations
		need(supported >= 0 && u64(supported) & required == required,
			c'query advertises memory and instruction barriers and registration')
		need(barrier(high_word, high_word) == supported, c'Linux narrows command and flags to 32 bits')
		need(barrier(0, 1) == -C.EINVAL && barrier(sync_core, 1) == -C.EINVAL, c'reject unsupported flags')
		need(barrier(high_word | sync_core, 0) == -C.EPERM, c'invocation requires registration')
		need(barrier(get_registrations, 1) == -C.EINVAL && barrier(global_barrier | private_expedited, 0) == -C.EINVAL,
			c'reject nonzero query flags and combined commands')
		need(barrier(get_registrations, 0) == 0, c'initial address space has no registrations')
		memory_order(global_barrier)
		memory_order(global_expedited)
		need(barrier(get_registrations, 0) == 0, c'global callers need no registration')
		need(barrier(high_word | register_sync_core, 0) == 0 && barrier(register_sync_core, 0) == 0,
			c'register narrowed command and repeat registration')
		need(barrier(sync_core, 0) == 0, c'synchronize the calling CPU')
		need(barrier(get_registrations, 0) == i64(register_private | register_sync_core)
			&& barrier(private_expedited, 0) == -C.EPERM,
			c'sync-core contributes the private query bit but leaves plain private inactive')
		need(barrier(high_word | register_private, 0) == 0, c'register private expedited')
		memory_order(private_expedited)
		need(barrier(register_global, 0) == 0 && barrier(register_global, 0) == 0
			&& barrier(get_registrations, 0) == i64(all_registrations),
			c'query all registrations after repeated registration')
		C.printf(c'LINUX MEMBSYNC MEMORY: commands=3 rounds=%d\n', memory_rounds)
		check_registration_lifetime()
		exercise_cores()
		C.puts(if reference { c'LINUX MEMBSYNC REFERENCE: PASS' } else { c'LINUX MEMBSYNC: PASS' })
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
