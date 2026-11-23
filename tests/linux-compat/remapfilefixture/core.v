// SPDX-License-Identifier: GPL-2.0-or-later
module remapfilefixture

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
fn C.fcntl(i32, i32, ...) i32
fn C.fflush(voidptr) i32
fn C.fork() i32
fn C.ftruncate(i32, i64) i32
fn C.mincore(voidptr, u64, &u8) i32
fn C.mmap(voidptr, u64, i32, i32, i32, i64) voidptr
fn C.mount(&char, &char, &char, u64, voidptr) i32
fn C.mprotect(voidptr, u64, i32) i32
fn C.munmap(voidptr, u64) i32
fn C.open(&char, i32, ...) i32
fn C.pause() i32
fn C.pread(i32, voidptr, u64, i64) i64
fn C.printf(&char, ...) i32
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.puts(&char) i32
fn C.pwrite(i32, voidptr, u64, i64) i64
fn C.sched_yield() i32
fn C.snprintf(&char, u64, &char, ...) i32
fn C.strcmp(&char, &char) i32
fn C.syscall(i64, ...) i64
fn C.sysconf(i32) i64
fn C.waitpid(i32, &i32, i32) i32

const no_prefault = u64(0x10000)
const rounds = 128
const f_add_seals = 1033
const f_seal_future_write = 0x10
const failed_map = voidptr(-1)

fn need(ok bool, label &char) {
	if ok { return }
	unsafe {
		C.printf(c'LINUX REMAPFILE FAIL: %s errno=%d\n', label, *C.__errno_location())
		C.fflush(nil)
		C._exit(1)
	}
}

fn remap(address voidptr, size u64, prot u64, file_page u64, flags u64) i32 {
	unsafe {
		result := C.syscall(i64(C.SYS_remap_file_pages), address, size, prot, file_page, flags)
		return if result < 0 { -*C.__errno_location() } else { i32(result) }
	}
}

fn at(base voidptr, offset u64) voidptr {
	return voidptr(u64(base) + offset)
}

fn byte_at(base voidptr, offset u64) u8 {
	mut residency := u8(0)
	need(C.mincore(at(base, offset), 1, &residency) == 0, c'page remains mapped before reading')
	return unsafe { *&u8(at(base, offset)) }
}

fn file_of(page u64, pages int, populate bool) i32 {
	fd := i32(C.syscall(i64(C.SYS_memfd_create), c'remap-file', u64(2)))
	need(fd >= 0 && C.ftruncate(fd, i64(u64(pages) * page)) == 0, c'allocate file size')
	if populate {
		for i in 0 .. pages {
			mut byte := `A` + u8(i)
			need(C.pwrite(fd, &byte, 1, i64(u64(i) * page)) == 1, c'write page marker')
		}
	}
	return fd
}

fn reopen(fd i32, flags i32) i32 {
	mut path := [48]char{}
	C.snprintf(&path[0], path.len, c'/proc/self/fd/%d', fd)
	opened := C.open(&path[0], flags)
	need(opened >= 0, c'reopen through procfs')
	return opened
}

fn region(fd i32, length u64, prot i32, flags i32, offset u64) voidptr {
	ptr := C.mmap(unsafe { nil }, length, prot, flags, fd, i64(offset))
	need(ptr != failed_map, c'map test region')
	return ptr
}

fn check_single(page u64) {
	unsafe {
		fd := file_of(page, 8, true)
		alias := reopen(fd, C.O_RDWR)
		base := region(fd, 4 * page, C.PROT_READ | C.PROT_WRITE, C.MAP_SHARED, 0)
		need(remap(base, page, u64(1) << 32, 1, 0) == -C.EINVAL, c'full-width protection argument must be zero')
		need(remap(base, page - 1, 0, 1, 0) == -C.EINVAL, c'length rounds down, zero is invalid')
		need(remap(voidptr(-1), page, 0, 0, 0) == -C.EINVAL, c'virtual span addition cannot wrap')
		need(remap(base, page, 0, u64(-1), 0) == -C.EINVAL, c'page count addition cannot wrap')
		need(remap(base, page, 0, u64(1) << 63, 0) == -C.EOVERFLOW, c'file offset must fit')
		need(byte_at(base, 0) == `A` && byte_at(base, page) == `B`, c'validation errors preserve the mapping')
		need(C.close(fd) == 0, c'close source descriptor')
		other := file_of(page, 1, false)
		need(other == fd, c'reuse the source descriptor number')
		need(remap(at(base, page + 1), page + 1, 0, 5, no_prefault | u64(0x80000000)) == 0,
			c'round start and length down and ignore unknown flags')
		need(byte_at(base, 0) == `A` && byte_at(base, page) == `F`
			&& byte_at(base, 2 * page) == `C` && byte_at(base, 3 * page) == `D`,
			c'remap middle page while retaining its neighbors')
		*&u8(at(base, page)) = 71
		mut value := u8(0)
		need(C.pread(alias, &value, 1, i64(5 * page)) == 1 && value == 71,
			c'new virtual page aliases the original file')
		need(C.munmap(base, 4 * page) == 0, c'unmap the split result')
		C.close(other)
		C.close(alias)
	}
}

fn check_adjacent(page u64) {
	unsafe {
		fd := file_of(page, 8, true)
		alias := reopen(fd, C.O_RDWR)
		base := region(-1, 3 * page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, 0)
		second := at(base, page)
		shared := C.MAP_SHARED | C.MAP_FIXED
		rw := C.PROT_READ | C.PROT_WRITE
		need(C.mmap(base, page, rw, shared, fd, 0) == base
			&& C.mmap(second, page, rw, shared, fd, i64(4 * page)) == second,
			c'install adjacent ranges of one file description')
		need(remap(base, 2 * page, 0, 2, 0) == 0 && byte_at(base, 0) == `C` && byte_at(base, page) == `D`,
			c'remap adjacent ranges across nonconsecutive old offsets')
		need(C.mmap(second, page, rw, shared, alias, i64(6 * page)) == second,
			c'install second description of the same inode')
		need(remap(base, 2 * page, 0, 0, 0) == -C.EINVAL && byte_at(base, page) == `G`,
			c'another file description rejects the whole replacement')
		need(C.mmap(second, page, C.PROT_READ, shared, fd, i64(7 * page)) == second,
			c'install different protection')
		need(remap(base, 2 * page, 0, 0, 0) == -C.EINVAL && byte_at(base, page) == `H`,
			c'different protections reject the whole replacement')
		need(C.munmap(second, page) == 0, c'open hole in the requested span')
		need(remap(base, 2 * page, 0, 0, 0) == -C.EINVAL && byte_at(base, 0) == `C`,
			c'holes reject the whole replacement')
		need(C.munmap(base, 3 * page) == 0, c'unmap the span and guard')
		C.close(alias)
		C.close(fd)
	}
}

fn check_permissions(page u64, reference bool) {
	unsafe {
		fd := file_of(page, 4, true)
		ro := reopen(fd, C.O_RDONLY)
		readonly := region(ro, page, C.PROT_READ, C.MAP_SHARED, 0)
		private := region(fd, page, C.PROT_READ, C.MAP_PRIVATE, 0)
		need(remap(readonly, page, 0, 1, 0) == -C.EINVAL, c'nonwritable description is ineligible')
		need(remap(private, page, 0, 1, 0) == -C.EINVAL, c'private view is ineligible')
		need(C.munmap(readonly, page) == 0 && C.munmap(private, page) == 0, c'close rejected views')
		C.close(ro)
		writable := region(fd, page, C.PROT_READ | C.PROT_WRITE, C.MAP_SHARED, 0)
		need(C.fcntl(fd, f_add_seals, f_seal_future_write) == 0, c'seal future writers')
		need(remap(writable, page, 0, 1, 0) == -C.EPERM, c'fresh writable mapping is denied by future-write seal')
		mut residency := u8(0)
		if C.mincore(writable, page, &residency) == 0 {
			need(byte_at(writable, 0) == `A`, c'rejected mapping preserves original offset')
			need(C.mprotect(writable, page, C.PROT_READ) == 0, c'make the existing view read-only')
		} else {
			need(reference && *C.__errno_location() == C.ENOMEM, c'Vinix keeps the mapping after rejection')
			C.puts(c'LINUX REMAPFILE REFERENCE: write-seal rejection removed the old VMA')
			need(C.mmap(writable, page, C.PROT_READ, C.MAP_SHARED | C.MAP_FIXED, fd, 0) == writable,
				c'reinstall read-only source after Linux rejection')
		}
		need(remap(writable, page, 0, 1, 0) == 0 && byte_at(writable, 0) == `B`,
			c'remap read-only protection on a writable description')
		need(C.mprotect(writable, page, C.PROT_READ | C.PROT_WRITE) == -1
			&& *C.__errno_location() == C.EACCES, c'new mapping has the write-seal ceiling')
		need(C.munmap(writable, page) == 0, c'unmap read-only replacement')

		child := C.fork()
		need(child >= 0, c'fork mseal child')
		if child == 0 {
			sealed := region(fd, page, C.PROT_READ, C.MAP_SHARED, 0)
			need(C.syscall(i64(462), sealed, page, u64(0)) == 0, c'seal VMA metadata')
			need(remap(sealed, page, 0, 2, 0) == -C.EPERM && byte_at(sealed, 0) == `A`,
				c'VM seal prevents file offset replacement')
			C._exit(0)
		}
		mut status := i32(0)
		need(C.waitpid(child, &status, 0) == child && status == 0, c'complete mseal child probe')
		C.close(fd)
	}
}

fn check_residency(page u64) {
	fd := file_of(page, 3, false)
	base := region(fd, page, C.PROT_READ, C.MAP_SHARED, 0)
	need(remap(base, page, 0, 1, no_prefault) == 0, c'remap sparse page without prefault')
	mut vec := u8(0)
	need(C.mincore(base, page, &vec) == 0 && vec & 1 == 0, c'nonblock leaves sparse page unfaulted')
	need(remap(base, page, 0, 2, 0) == 0, c'remap sparse page with default prefault')
	need(C.mincore(base, page, &vec) == 0 && vec & 1 == 1, c'default remap faults accessible page')
	need(C.munmap(base, page) == 0, c'unmap residency test')
	C.close(fd)
}

struct UnmapRace {
	base voidptr
	page u64
mut:
	start i32
	err i32
}

fn unmap_after_start(arg voidptr) voidptr {
	unsafe {
		mut race := &UnmapRace(arg)
		for C.__atomic_load_n(&race.start, 2) == 0 {
			C.sched_yield()
		}
		race.err = C.munmap(race.base, race.page)
		return nil
	}
}

fn check_races(page u64) {
	unsafe {
		for _ in 0 .. rounds {
			fd := file_of(page, 2, false)
			base := region(fd, page, C.PROT_READ, C.MAP_SHARED, 0)
			need(C.close(fd) == 0, c'leave only the mapping holding the file')
			mut race := UnmapRace{base: base, page: page}
			mut worker := C.pthread_t{}
			need(C.pthread_create(&worker, nil, unmap_after_start, &race) == 0, c'start competing munmap')
			C.__atomic_store_n(&race.start, 1, 3)
			result := remap(base, page, 0, 1, no_prefault)
			need(C.pthread_join(worker, nil) == 0 && race.err == 0, c'join competing munmap')
			need(result == 0 || result == -C.EINVAL, c'competing munmap either wins or removes new view')
			mut vec := u8(0)
			need(C.mincore(base, page, &vec) == -1 && *C.__errno_location() == C.ENOMEM,
				c'remap cannot resurrect a racing unmap')
		}
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		C.mount(c'proc', c'/proc', c'proc', 0, nil)
		reference := argc > 1 && C.strcmp(argv[1], c'--reference') == 0
		page := C.sysconf(C._SC_PAGESIZE)
		need(page > 0, c'get native page size')
		check_single(u64(page))
		check_adjacent(u64(page))
		check_permissions(u64(page), reference)
		check_residency(u64(page))
		check_races(u64(page))
		C.printf(c'LINUX REMAPFILE SUMMARY: alias=shared protections=checked races=%d\n', rounds)
		C.puts(if reference {
			c'LINUX REMAPFILE REFERENCE: PASS'
		} else {
			c'LINUX REMAPFILE: PASS'
		})
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
