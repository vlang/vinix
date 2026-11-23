// SPDX-License-Identifier: GPL-2.0-or-later
module memfdsealsfixture

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

@[typedef]
struct C.pthread_t {}

fn C.__atomic_load_n(&i32, i32) i32
fn C.__atomic_store_n(&i32, i32, i32)
fn C.__errno_location() &i32
fn C._exit(i32)
fn C.close(i32) i32
fn C.fchmod(i32, u32) i32
fn C.fcntl(i32, i32, ...) i32
fn C.fflush(voidptr) i32
fn C.fork() i32
fn C.ftruncate(i32, i64) i32
fn C.mmap(voidptr, u64, i32, i32, i32, i64) voidptr
fn C.mount(&char, &char, &char, u64, voidptr) i32
fn C.mprotect(voidptr, u64, i32) i32
fn C.mremap(voidptr, u64, u64, i32, ...) voidptr
fn C.munmap(voidptr, u64) i32
fn C.open(&char, i32, ...) i32
fn C.pause() i32
fn C.pipe(&i32) i32
fn C.pread(i32, voidptr, u64, i64) i64
fn C.printf(&char, ...) i32
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.puts(&char) i32
fn C.pwrite(i32, voidptr, u64, i64) i64
fn C.read(i32, voidptr, u64) i64
fn C.sched_yield() i32
fn C.snprintf(&char, u64, &char, ...) i32
fn C.strcmp(&char, &char) i32
fn C.syscall(i64, ...) i64
fn C.sysconf(i32) i64
fn C.waitpid(i32, &i32, i32) i32
fn C.write(i32, voidptr, u64) i64

const mfd_exec_sealable = u64(0x12)
const f_add_seals = 1033
const f_get_seals = 1034
const seal_shrink = 0x02
const seal_grow = 0x04
const seal_write = 0x08
const seal_future_write = 0x10
const seal_exec = 0x20
const failed_map = voidptr(-1)
const race_rounds = 64

fn need(ok bool, label &char) {
	if ok { return }
	unsafe {
		C.printf(c'LINUX MEMFDSEALS FAIL: %s errno=%d\n', label, *C.__errno_location())
		C.fflush(nil)
		C._exit(1)
	}
}

fn memfd(length u64) i32 {
	fd := i32(C.syscall(i64(C.SYS_memfd_create), c'write-seals', mfd_exec_sealable))
	need(fd >= 0 && C.ftruncate(fd, i64(length)) == 0, c'create and size sealable memfd')
	return fd
}

fn mapping(fd i32, length u64, prot i32, flags i32) voidptr {
	return C.mmap(unsafe { nil }, length, prot, flags, fd, 0)
}

fn add_seals(fd i32, seals i32) i32 {
	return C.fcntl(fd, f_add_seals, seals)
}

fn check_reads_and_new_mappings(fd i32, page u64) {
	unsafe {
		need(mapping(fd, page, C.PROT_READ | C.PROT_WRITE, C.MAP_SHARED) == failed_map
			&& *C.__errno_location() == C.EPERM, c'new writable shared mapping denied')
		shared := mapping(fd, page, C.PROT_READ, C.MAP_SHARED)
		need(shared != failed_map, c'new read-only shared mapping admitted')
		need(C.mprotect(shared, page, C.PROT_READ | C.PROT_WRITE) == -1
			&& *C.__errno_location() == C.EACCES, c'new shared mapping cannot upgrade')
		target := mapping(-1, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS)
		need(target != failed_map, c'reserve mremap destination')
		need(C.mremap(shared, page, page, C.MREMAP_MAYMOVE | C.MREMAP_FIXED, target) == target,
			c'move new read-only shared mapping')
		need(C.mprotect(target, page, C.PROT_READ | C.PROT_WRITE) == -1
			&& *C.__errno_location() == C.EACCES, c'mremap preserves shared write ceiling')
		need(C.munmap(target, page) == 0, c'unmap moved mapping')

		private := mapping(fd, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE)
		need(private != failed_map, c'writable private mapping still works')
		mut original := u8(0)
		need(C.pread(fd, &original, 1, 0) == 1, c'read original byte')
		*&u8(private) = original + 1
		mut after := u8(0)
		need(C.pread(fd, &after, 1, 0) == 1 && after == original, c'private writes do not reach file')
		need(C.munmap(private, page) == 0, c'unmap private mapping')
		need(C.pwrite(fd, c'x', 1, 0) == -1 && *C.__errno_location() == C.EPERM,
			c'write syscall refuses sealed inode')
	}
}

fn check_write_seal(page u64) {
	unsafe {
		fd := memfd(3 * page)
		mut path := [48]char{}
		C.snprintf(&path[0], path.len, c'/proc/self/fd/%d', fd)
		readonly := C.open(&path[0], C.O_RDONLY)
		need(readonly >= 0, c'reopen memfd read-only')
		ro_map := mapping(readonly, page, C.PROT_READ, C.MAP_SHARED)
		need(ro_map != failed_map && C.close(readonly) == 0, c'retain read-only shared mapping')
		base := mapping(fd, 3 * page, C.PROT_READ, C.MAP_SHARED)
		need(base != failed_map, c'read-only protection on writable description')
		need(C.mprotect(voidptr(u64(base) + page), page, C.PROT_NONE) == 0, c'split shared mapping')
		need(C.munmap(base, 2 * page) == 0, c'partial unmap preserves the tail')
		need(add_seals(fd, seal_write | seal_grow) == -1 && *C.__errno_location() == C.EBUSY,
			c'surviving writable-capable tail blocks a write seal')
		need(C.fcntl(fd, f_get_seals) == 0, c'busy operation leaves all seals unchanged')

		mut pipe := [2]i32{}
		need(C.pipe(&pipe[0]) == 0, c'create fork synchronization pipe')
		child := C.fork()
		need(child >= 0, c'fork process sharing writable-capable tail')
		tail := voidptr(u64(base) + 2 * page)
		if child == 0 {
			C.close(pipe[1])
			mut token := u8(0)
			need(C.read(pipe[0], &token, 1) == 1, c'wait for parent to unmap its tail')
			need(C.mprotect(tail, page, C.PROT_READ | C.PROT_WRITE) == 0, c'inherited tail can become writable')
			*&u8(tail) = 77
			C._exit(0)
		}
		C.close(pipe[0])
		need(C.munmap(tail, page) == 0, c'parent unmaps its tail')
		need(add_seals(fd, seal_write) == -1 && *C.__errno_location() == C.EBUSY,
			c'inherited mapping still blocks sealing')
		need(C.write(pipe[1], c'x', 1) == 1 && C.close(pipe[1]) == 0, c'release child')
		mut status := i32(0)
		need(C.waitpid(child, &status, 0) == child && status == 0, c'child exits and drops last writable mapping')
		need(C.mmap(ro_map, page, C.PROT_READ | C.PROT_WRITE, C.MAP_SHARED | C.MAP_FIXED_NOREPLACE,
			fd, 0) == failed_map && *C.__errno_location() == C.EEXIST, c'overlapping mapping fails')
		need(add_seals(fd, seal_write) == 0 && C.fcntl(fd, f_get_seals) == seal_write,
			c'failed admission and read-only descriptor mapping do not block seal')
		need(C.mprotect(ro_map, page, C.PROT_READ | C.PROT_WRITE) == -1
			&& *C.__errno_location() == C.EACCES, c'read-only descriptor mapping cannot upgrade')
		check_reads_and_new_mappings(fd, page)
		need(C.ftruncate(fd, i64(4 * page)) == 0, c'write seal alone permits resize')
		need(C.munmap(ro_map, page) == 0 && C.close(fd) == 0, c'close explicit write-seal fixture')
	}
}

fn check_future_write(page u64) {
	unsafe {
		fd := memfd(page)
		old := mapping(fd, page, C.PROT_READ, C.MAP_SHARED)
		need(old != failed_map, c'map writable-capable view before future-write seal')
		need(add_seals(fd, seal_future_write) == 0, c'future-write seal allows existing shared mappings')
		check_reads_and_new_mappings(fd, page)
		need(C.mprotect(old, page, C.PROT_READ | C.PROT_WRITE) == 0,
			c'old mapping retains its original write ceiling')
		*&u8(old) = 31
		mut value := u8(0)
		need(C.pread(fd, &value, 1, 0) == 1 && value == 31, c'old mapping writes still reach file')
		need(add_seals(fd, seal_write) == -1 && *C.__errno_location() == C.EBUSY,
			c'explicit write seal still checks grandfathered mapping')
		need(C.munmap(old, page) == 0 && add_seals(fd, seal_write) == 0, c'add write seal after unmapping')
		need(C.close(fd) == 0, c'close future-write fixture')
	}
}

fn check_exec_implies_write(page u64) {
	unsafe {
		fd := memfd(2 * page)
		old := mapping(fd, page, C.PROT_READ | C.PROT_WRITE, C.MAP_SHARED)
		need(old != failed_map, c'map writable view before execute seal')
		need(add_seals(fd, seal_exec | seal_write) == -1 && *C.__errno_location() == C.EBUSY,
			c'explicit write bit in combined request checks existing mappings')
		need(C.fcntl(fd, f_get_seals) == 0 && add_seals(fd, seal_exec) == 0, c'add execute seal alone')
		need(C.fcntl(fd, f_get_seals) == (seal_exec | seal_write | seal_future_write | seal_shrink | seal_grow),
			c'execute seal implies four seals on executable inode')
		need(C.ftruncate(fd, i64(page)) == -1 && *C.__errno_location() == C.EPERM,
			c'implied shrink seal prevents shortening')
		need(C.ftruncate(fd, i64(3 * page)) == -1 && *C.__errno_location() == C.EPERM,
			c'implied grow seal prevents extension')
		need(C.syscall(i64(C.SYS_fallocate), fd, 0, i64(0), i64(page)) == 0,
			c'fallocate inside file size is allowed')
		need(C.syscall(i64(C.SYS_fallocate), fd, 0, i64(0), i64(3 * page)) == -1
			&& *C.__errno_location() == C.EPERM, c'implied grow seal blocks fallocate extension')
		need(C.fchmod(fd, 0o666) == -1 && *C.__errno_location() == C.EPERM,
			c'execute seal fixes execute bits')
		check_reads_and_new_mappings(fd, page)
		*&u8(old) = 21
		mut value := u8(0)
		need(C.pread(fd, &value, 1, 0) == 1 && value == 21,
			c'implied write seal preserves existing mapping')
		need(C.munmap(old, page) == 0 && C.close(fd) == 0, c'close executable fixture')

		plain := memfd(page)
		need(C.fchmod(plain, 0o666) == 0 && add_seals(plain, seal_exec) == 0
			&& C.fcntl(plain, f_get_seals) == seal_exec, c'non-executable inode gets only execute seal')
		need(C.pwrite(plain, c'x', 1, 0) == 1 && C.close(plain) == 0,
			c'non-executable execute-sealed inode stays writable')
	}
}

struct Race {
	fd i32
	page u64
mut:
	start i32
	view voidptr
	error i32
}

fn map_after_start(arg voidptr) voidptr {
	unsafe {
		mut race := &Race(arg)
		for C.__atomic_load_n(&race.start, 2) == 0 {
			C.sched_yield()
		}
		race.view = mapping(race.fd, race.page, C.PROT_READ | C.PROT_WRITE, C.MAP_SHARED)
		if race.view == failed_map {
			race.error = *C.__errno_location()
		}
		return nil
	}
}

fn check_races(page u64) {
	unsafe {
		for _ in 0 .. race_rounds {
			fd := memfd(page)
			mut race := Race{fd: fd, page: page}
			mut worker := C.pthread_t{}
			need(C.pthread_create(&worker, nil, map_after_start, &race) == 0, c'start competing mmap')
			C.__atomic_store_n(&race.start, 1, 3)
			sealed := add_seals(fd, seal_write)
			seal_error := *C.__errno_location()
			need(C.pthread_join(worker, nil) == 0, c'join competing mmap')
			if sealed == 0 {
				need(race.view == failed_map && race.error == C.EPERM, c'new write seal wins mmap race')
			} else {
				need(sealed == -1 && seal_error == C.EBUSY && race.view != failed_map, c'mapping wins seal race')
				need(C.munmap(race.view, page) == 0 && add_seals(fd, seal_write) == 0,
					c'losing seal can be retried after unmap')
			}
			need(C.close(fd) == 0, c'close race memfd')
		}
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		C.mount(c'proc', c'/proc', c'proc', 0, nil)
		page := C.sysconf(C._SC_PAGESIZE)
		need(page > 0, c'get page size')
		check_write_seal(u64(page))
		check_future_write(u64(page))
		check_exec_implies_write(u64(page))
		check_races(u64(page))
		C.printf(c'LINUX MEMFDSEALS SUMMARY: write=busy future=preserved exec=implied races=%d\n', race_rounds)
		C.puts(if argc > 1 && C.strcmp(argv[1], c'--reference') == 0 {
			c'LINUX MEMFDSEALS REFERENCE: PASS'
		} else {
			c'LINUX MEMFDSEALS: PASS'
		})
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
