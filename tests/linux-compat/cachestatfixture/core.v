// SPDX-License-Identifier: GPL-2.0-or-later
module cachestatfixture

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.__errno_location() &i32
fn C._exit(i32)
fn C.close(i32) i32
fn C.fchmod(i32, u32) i32
fn C.fflush(voidptr) i32
fn C.fork() i32
fn C.ftruncate(i32, i64) i32
fn C.lseek(i32, i64, i32) i64
fn C.mmap(voidptr, u64, i32, i32, i32, i64) voidptr
fn C.mount(&char, &char, &char, u64, voidptr) i32
fn C.munmap(voidptr, u64) i32
fn C.open(&char, i32, ...) i32
fn C.pause() i32
fn C.pipe(&i32) i32
fn C.pread(i32, voidptr, u64, i64) i64
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.pwrite(i32, voidptr, u64, i64) i64
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.strcmp(&char, &char) i32
fn C.syscall(i64, ...) i64
fn C.sysconf(i32) i64
fn C.waitpid(i32, &i32, i32) i32
fn C.write(i32, voidptr, u64) i64

const sys_cachestat = i64(451)
const repeats = 128
const canary = u64(0xdeadbeef0badcafe)

struct CacheRange {
	offset u64
	length u64
}

struct CacheStat {
	cached u64
	dirty u64
	writeback u64
	evicted u64
	recently_evicted u64
}

struct GuardedStat {
	first u64
	stats CacheStat
	last  u64
}

fn need(ok bool, label &char) {
	if ok { return }
	unsafe {
		C.printf(c'LINUX CACHESTAT FAIL: %s errno=%d\n', label, *C.__errno_location())
		C.fflush(nil)
		C._exit(1)
	}
}

fn check_count(fd i32, offset u64, length u64, expected u64, label &char) {
	query := CacheRange{offset: offset, length: length}
	stats := GuardedStat{ first: canary, last: canary, stats: CacheStat{cached: canary} }
	result := C.syscall(sys_cachestat, u64(u32(fd)) | (u64(5) << 32), &query, &stats.stats, u64(6) << 32)
	if result != 0 || stats.stats.cached != expected {
		C.printf(c'LINUX CACHESTAT count expected=%lu actual=%lu syscall=%ld\n',
			expected, stats.stats.cached, result)
	}
	need(result == 0 && stats.stats.cached == expected
		&& stats.stats.dirty == 0 && stats.stats.writeback == 0
		&& stats.stats.evicted == 0 && stats.stats.recently_evicted == 0
		&& stats.first == canary && stats.last == canary, label)
}

fn temp_file(path &char, mode u32) i32 {
	fd := C.open(path, C.O_CREAT | C.O_EXCL | C.O_RDWR, mode)
	need(fd >= 0, c'create tmpfs file')
	need(C.fchmod(fd, mode) == 0, c'set exact test permissions')
	return fd
}

fn check_errors(fd i32, page u64) {
	unsafe {
		query := CacheRange{}
		stats := CacheStat{cached:canary, dirty:canary, writeback:canary, evicted:canary, recently_evicted:canary}
		need(C.syscall(sys_cachestat, u64(-1), nil, nil, u64(1)) == -1
			&& *C.__errno_location() == C.EBADF, c'bad descriptor precedes bad pointers and flags')
		path := C.open(c'/tmp/cachestat-private', C.O_PATH)
		need(path >= 0, c'open O_PATH descriptor')
		need(C.syscall(sys_cachestat, path, nil, nil, u64(1)) == -1
			&& *C.__errno_location() == C.EBADF, c'O_PATH is excluded before copyin')
		C.close(path)
		need(C.syscall(sys_cachestat, fd, nil, &stats, u64(1)) == -1
			&& *C.__errno_location() == C.EFAULT, c'bad range pointer precedes flags')
		need(C.syscall(sys_cachestat, fd, &query, nil, u64(1)) == -1
			&& *C.__errno_location() == C.EINVAL, c'nonzero flags precede result copyout')
		need(C.syscall(sys_cachestat, fd, &query, &stats, u64(1)) == -1 && stats.cached == canary
			&& stats.dirty == canary && stats.writeback == canary && stats.evicted == canary
			&& stats.recently_evicted == canary, c'invalid flags leave output untouched')
		readonly := C.mmap(nil, page, C.PROT_READ, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		need(readonly != voidptr(-1), c'map read-only result buffer')
		need(C.syscall(sys_cachestat, fd, &query, readonly, u64(0)) == -1
			&& *C.__errno_location() == C.EFAULT, c'read-only result buffer faults')
		need(C.munmap(readonly, page) == 0, c'unmap result fault buffer')
	}
}

fn check_sparse_file(fd i32, page u64) {
	unsafe {
		need(C.ftruncate(fd, i64(8 * page)) == 0, c'extend sparse tmpfs file')
		check_count(fd, 0, 0, 0, c'holes are absent from cache')
		mut byte := u8(85)
		need(C.pread(fd, &byte, 1, i64(2 * page)) == 1 && byte == 0, c'read sparse hole')
		check_count(fd, 2 * page, 1, 0, c'reading a hole does not materialize it')
		need(C.pwrite(fd, c'x', 1, i64(page + 8)) == 1, c'write in second page')
		need(C.pwrite(fd, c'pq', 2, i64(4 * page - 1)) == 2, c'write across page boundary')
		check_count(fd, 0, 0, 3, c'count three resident pages')
		check_count(fd, 0, page, 0, c'exclusive end of first page')
		check_count(fd, page - 1, 2, 1, c'unaligned range crosses into resident page')
		check_count(fd, 4 * page - 1, 1, 1, c'one byte at page end counts once')
		check_count(fd, 4 * page - 1, 2, 2, c'two bytes cover both resident pages')
		check_count(fd, 3 * page, 0, 2, c'zero length extends from offset to end')
		check_count(fd, 8 * page, 0, 0, c'offset at EOF')
		check_count(fd, u64(-1), 2, 0, c'wrapped range has no in-file pages')
		need(C.lseek(fd, 37, C.SEEK_SET) == 37, c'set descriptor cursor')
		check_count(fd, 0, 0, 3, c'query ignores descriptor cursor')
		need(C.lseek(fd, 0, C.SEEK_CUR) == 37, c'query preserves descriptor cursor')
		mapped := C.mmap(nil, page, C.PROT_READ | C.PROT_WRITE, C.MAP_SHARED, fd, i64(5 * page))
		need(mapped != voidptr(-1), c'map a hole shared')
		check_count(fd, 5 * page, 1, 0, c'unfaulted mapping is not resident')
		*&u8(mapped) = 23
		need(C.pread(fd, &byte, 1, i64(5 * page)) == 1 && byte == 23, c'fault shared file page')
		check_count(fd, 5 * page, 1, 1, c'shared fault populates the file cache')
		need(C.munmap(mapped, page) == 0, c'unmap shared page')
		check_count(fd, 0, 0, 4, c'file still holds shared page after unmap')
		need(C.ftruncate(fd, i64(3 * page)) == 0, c'truncate across cached pages')
		check_count(fd, 0, 0, 1, c'pages beyond EOF are excluded after truncate')
		check_count(fd, 3 * page, 8 * page, 0, c'explicit range beyond EOF is empty')
	}
}

fn check_permissions(fd i32) {
	unsafe {
		readonly := C.open(c'/tmp/cachestat-private', C.O_RDONLY)
		writeonly := C.open(c'/tmp/cachestat-private', C.O_WRONLY)
		writable := temp_file(c'/tmp/cachestat-public', 0o666)
		need(readonly >= 0 && writeonly >= 0, c'open access-mode controls')
		need(C.pwrite(writable, c'a', 1, 0) == 1, c'write a public cache page')
		public_read := C.open(c'/tmp/cachestat-public', C.O_RDONLY)
		need(public_read >= 0, c'open public file read-only')
		check_count(readonly, 0, 0, 1, c'owner can query read-only descriptor')
		child := C.fork()
		need(child >= 0, c'fork permission probe')
		if child == 0 {
			need(C.setgid(1000) == 0 && C.setuid(1000) == 0, c'drop privileges')
			query := CacheRange{}
			stats := CacheStat{cached: canary}
			need(C.syscall(sys_cachestat, readonly, &query, &stats, u64(1)) == -1
				&& *C.__errno_location() == C.EPERM && stats.cached == canary,
				c'foreign read-only descriptor denied before flags and copyout')
			check_count(fd, 0, 0, 1, c'inherited writable open description authorizes query')
			check_count(writeonly, 0, 0, 1, c'write-only open description authorizes query')
			check_count(public_read, 0, 0, 1, c'current inode write permission authorizes query')
			C._exit(0)
		}
		mut status := i32(0)
		need(C.waitpid(child, &status, 0) == child && status == 0, c'credential checks passed')
		C.close(readonly)
		C.close(writeonly)
		C.close(writable)
		C.close(public_read)
	}
}

fn check_cacheless() {
	unsafe {
		for path in [c'/proc/version', c'/proc', c'/dev/null']! {
			fd := C.open(path, C.O_RDONLY)
			need(fd >= 0, c'open cacheless inode')
			check_count(fd, 0, 0, 0, c'kernel-generated and char-device data have no cache')
			C.close(fd)
		}
		mut pipe := [2]i32{}
		need(C.pipe(&pipe[0]) == 0 && C.write(pipe[1], c'pipe contents', 13) == 13,
			c'create a pipe containing data')
		check_count(pipe[0], 0, 0, 0, c'pipe buffer is independent of page cache')
		C.close(pipe[0])
		C.close(pipe[1])
	}
}

fn check_memfd(page u64) {
	unsafe {
		fd := i32(C.syscall(i64(C.SYS_memfd_create), c'cache-probe', u64(0)))
		need(fd >= 0, c'create memfd')
		check_count(fd, 0, 0, 0, c'empty memfd has no cached pages')
		need(C.pwrite(fd, c'a', 1, 0) == 1, c'write small inline memfd')
		check_count(fd, 0, 0, 1, c'inline memfd backing is resident')
		far := 2048 * page
		need(C.pwrite(fd, c'b', 1, i64(far)) == 1, c'write beyond a large sparse span')
		for _ in 0 .. repeats {
			check_count(fd, 0, 0, 2, c'whole sparse memfd spans multiple scan batches')
		}
		check_count(fd, page, far - page, 0, c'skip the large hole')
		check_count(fd, far, 8, 1, c'include the last partial page')
		C.close(fd)
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		C.mount(c'proc', c'/proc', c'proc', 0, nil)
		C.mount(c'devtmpfs', c'/dev', c'devtmpfs', 0, nil)
		need(C.mount(c'tmpfs', c'/tmp', c'tmpfs', 0, nil) == 0, c'mount tmpfs')
		page := C.sysconf(C._SC_PAGESIZE)
		need(page > 0, c'get native page size')
		fd := temp_file(c'/tmp/cachestat-private', 0o644)
		check_errors(fd, u64(page))
		check_sparse_file(fd, u64(page))
		check_permissions(fd)
		C.close(fd)
		check_cacheless()
		check_memfd(u64(page))
		C.printf(c'LINUX CACHESTAT SUMMARY: sparse=exact permissions=checked repeats=%d\n', repeats)
		C.puts(if argc > 1 && C.strcmp(argv[1], c'--reference') == 0 {
			c'LINUX CACHESTAT REFERENCE: PASS'
		} else {
			c'LINUX CACHESTAT: PASS'
		})
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
