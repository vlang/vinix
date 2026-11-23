// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module mmapfixture

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.syscall(isize, ...) isize
fn C.sysconf(i32) isize
fn C.__errno_location() &i32
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.write(i32, voidptr, usize) isize
fn C.pwrite(i32, voidptr, usize, i64) isize
fn C.ftruncate(i32, i64) i32
fn C.fstat(i32, &C.stat) i32
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.mprotect(voidptr, usize, i32) i32
fn C.munmap(voidptr, usize) i32
fn C.pipe(&i32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) bool
fn C.WEXITSTATUS(i32) i32
fn C.WIFSIGNALED(i32) bool
fn C.WTERMSIG(i32) i32
fn C._exit(i32)
fn C.puts(&char) i32
fn C.printf(&char, ...) i32
fn C.sscanf(&char, &char, ...) i32
fn C.fflush(voidptr) i32
fn C.pause() i32
fn C.strcmp(&char, &char) i32
fn C.sigaction(i32, &C.sigaction, &C.sigaction) i32
fn C.sigemptyset(&C.sigset_t) i32

@[typedef]
struct C.sigset_t {}

@[typedef]
struct C.siginfo_t {
	si_signo i32
	si_errno i32
	si_code i32
	si_addr voidptr
}

struct C.sigaction {
mut:
	sa_sigaction fn (i32, &C.siginfo_t, voidptr)
	sa_mask C.sigset_t
	sa_flags i32
}

struct C.stat {
	st_blocks i64
	st_size i64
}

__global (
	expected_signal i32
	expected_code i32
	expected_address usize
)

fn need(ok bool, label &char) {
	if !ok {
		C.printf(c'LINUX MMAP FAIL: %s errno=%d\n', label, unsafe { *C.__errno_location() })
		C.fflush(unsafe { nil })
		C._exit(1)
	}
}

fn fault_info(signal i32, info &C.siginfo_t, _context voidptr) {
	if signal == expected_signal && info.si_signo == signal && info.si_errno == 0
		&& info.si_code == expected_code && usize(info.si_addr) == expected_address {
		C._exit(0)
	}
	C._exit(2)
}

fn trigger_fault(address usize, writing bool, signal i32, code i32) {
	unsafe {
		if code != 0 {
			expected_signal = signal
			expected_code = code
			expected_address = address
			mut action := C.sigaction{sa_sigaction: fault_info, sa_flags: C.SA_SIGINFO}
			if C.sigemptyset(&action.sa_mask) != 0
				|| C.sigaction(C.SIGBUS, &action, nil) != 0
				|| C.sigaction(C.SIGSEGV, &action, nil) != 0 { C._exit(3) }
		}
		if writing { *(&u8(address)) = 99 }
		C._exit(if *(&u8(address)) == 0 { 4 } else { 5 })
	}
}

fn expect_fault(address usize, writing bool, signal i32, code i32) {
	unsafe {
		child := C.fork()
		need(child >= 0, c'fork a faulting worker')
		if child == 0 { trigger_fault(address, writing, signal, code) }
		mut status := i32(-1)
		need(C.waitpid(child, &status, 0) == child, c'wait for faulting worker')
		ok := if code == 0 { C.WIFSIGNALED(status) && C.WTERMSIG(status) == signal }
			else { C.WIFEXITED(status) && C.WEXITSTATUS(status) == 0 }
		if !ok {
			C.printf(c'LINUX MMAP FAIL: fault signal=%d code=%d address=%lx write=%d status=%x\n',
				signal, code, address, i32(writing), status)
			C.fflush(nil)
			C._exit(1)
		}
	}
}

fn check_file_end(fd i32, page usize, flags i32) {
	unsafe {
		need(C.ftruncate(fd, i64(page + 17)) == 0 && C.pwrite(fd, c'x', 1, i64(page + 16)) == 1,
			c'create a partial last page')
		base := usize(C.mmap(nil, 4 * page, C.PROT_READ | C.PROT_WRITE, flags, fd, i64(page)))
		need(base != usize(-1), c'map a file span with a nonzero offset across EOF')
		need(*(&u8(base + 16)) == `x` && *(&u8(base + 17)) == 0 && *(&u8(base + page - 1)) == 0,
			c'keep data and zero padding in the partial last page')

		beyond := base + page
		expect_fault(beyond + 19, false, C.SIGBUS, C.BUS_ADRERR)
		expect_fault(beyond + 43, true, C.SIGBUS, C.BUS_ADRERR)
		expect_fault(beyond + 51, false, C.SIGBUS, 0)
		need(C.mprotect(voidptr(beyond), page, C.PROT_NONE) == 0, c'protect a page past EOF')
		expect_fault(beyond + 21, false, C.SIGSEGV, C.SEGV_ACCERR)
		need(C.mprotect(voidptr(beyond), page, C.PROT_READ) == 0, c'enable reads past EOF')
		expect_fault(beyond + 23, true, C.SIGSEGV, C.SEGV_ACCERR)
		expect_fault(beyond + 25, false, C.SIGBUS, C.BUS_ADRERR)

		mut pipe := [2]i32{}
		mut byte := u8(0)
		need(C.pipe(&pipe[0]) == 0, c'open pipe for guarded user copy')
		need(C.write(pipe[1], voidptr(beyond), 1) == -1 && *C.__errno_location() == C.EFAULT,
			c'checked user copy reports EFAULT on a missing file page')
		need(C.write(pipe[1], c'z', 1) == 1 && C.read(pipe[0], &byte, 1) == 1 && byte == `z`
			&& C.close(pipe[0]) == 0 && C.close(pipe[1]) == 0, c'user copy refusal leaves the pipe usable')

		need(C.ftruncate(fd, i64(4 * page)) == 0 && C.pwrite(fd, c'g', 1, i64(2 * page + 14)) == 1,
			c'grow the backing into a previously faulting page')
		need(*(&u8(beyond + 14)) == `g` && *(&u8(beyond + page - 1)) == 0,
			c'fault after growth reads the new extent')
		need(C.ftruncate(fd, i64(page + 17)) == 0, c'shrink below a still-unfaulted page')
		expect_fault(base + 2 * page + 17, false, C.SIGBUS, C.BUS_ADRERR)
		need(C.munmap(voidptr(base), 4 * page) == 0, c'unmap the file span')
	}
}

fn map_file(fd i32, length usize, offset usize, flags i32) usize {
	address := usize(C.mmap(unsafe { nil }, length, C.PROT_READ | C.PROT_WRITE, flags, fd, i64(offset)))
	need(address != usize(-1), c'map truncation alias')
	return address
}

fn check_truncate_aliases(fd i32, page usize) {
	unsafe {
		need(C.ftruncate(fd, 0) == 0 && C.ftruncate(fd, i64(4 * page)) == 0
			&& C.pwrite(fd, c'a', 1, i64(page + 5)) == 1
			&& C.pwrite(fd, c'b', 1, i64(page + 29)) == 1
			&& C.pwrite(fd, c'c', 1, i64(2 * page + 7)) == 1
			&& C.pwrite(fd, c'd', 1, i64(3 * page + 9)) == 1, c'seed three file pages')
		view := map_file(fd, 3 * page, page, C.MAP_SHARED)
		tail := map_file(fd, 2 * page, 2 * page, C.MAP_SHARED)
		clean := map_file(fd, 3 * page, page, C.MAP_PRIVATE)
		dirty := map_file(fd, 3 * page, page, C.MAP_PRIVATE)
		need(*(&u8(view + page + 7)) == `c` && *(&u8(tail + page + 9)) == `d`
			&& *(&u8(clean + page + 7)) == `c` && *(&u8(clean + 29)) == `b`,
			c'make the shared and clean private pages resident')
		mut ready := [2]i32{}
		need(C.pipe(&ready[0]) == 0 && C.write(ready[1], c'x', 1) == 1
			&& C.read(ready[0], voidptr(dirty + 29), 1) == 1 && *(&u8(dirty + 29)) == `x`,
			c'checked copy can fill and privatize a cold file page')
		*(&u8(dirty + page + 7)) = `y`
		*(&u8(dirty + 2 * page + 9)) = `z`
		need(C.mprotect(voidptr(dirty + 2 * page), page, C.PROT_READ) == 0,
			c'split the resident private mapping')
		mut seen := [2]i32{}
		need(C.pipe(&seen[0]) == 0, c'acknowledge resident pages in the child')
		child := C.fork()
		need(child >= 0, c'fork resident aliases')
		if child == 0 {
			C.close(ready[1])
			C.close(seen[0])
			mut byte := u8(0)
			need(*(&u8(dirty + page + 7)) == `y` && C.write(seen[1], c's', 1) == 1
				&& C.close(seen[1]) == 0 && C.read(ready[0], &byte, 1) == 1,
				c'wait for truncation in the parent')
			expect_fault(tail + page + 9, false, C.SIGBUS, C.BUS_ADRERR)
			need(*(&u8(clean + 29)) == 0 && *(&u8(dirty + 29)) == `x`,
				c'child keeps the retained partial page')
			C.close(ready[0])
			trigger_fault(dirty + page + 7, true, C.SIGBUS, C.BUS_ADRERR)
		}
		C.close(ready[0])
		C.close(seen[1])
		mut byte := u8(0)
		need(C.read(seen[0], &byte, 1) == 1 && C.close(seen[0]) == 0, c'child inherited a resident COW page')
		need(C.ftruncate(fd, i64(page + 17)) == 0, c'shrink past two resident pages')
		expect_fault(view + page + 7, false, C.SIGBUS, C.BUS_ADRERR)
		expect_fault(tail + page + 9, true, C.SIGBUS, C.BUS_ADRERR)
		expect_fault(clean + page + 7, false, C.SIGBUS, C.BUS_ADRERR)
		expect_fault(dirty + page + 7, true, C.SIGBUS, C.BUS_ADRERR)
		expect_fault(dirty + 2 * page + 9, false, C.SIGBUS, C.BUS_ADRERR)
		need(C.write(ready[1], c'r', 1) == 1 && C.close(ready[1]) == 0, c'let the child check its aliases')
		mut status := i32(-1)
		need(C.waitpid(child, &status, 0) == child && status == 0, c'child observes the truncated extent')
		need(*(&u8(view + 5)) == `a` && *(&u8(view + 29)) == 0 && *(&u8(clean + 29)) == 0
			&& *(&u8(dirty + 29)) == `x`, c'shrink zeros the cached partial tail and preserves private writes')
		mut info := C.stat{}
		need(C.fstat(fd, &info) == 0 && info.st_size == i64(page + 17) && info.st_blocks * 512 == i64(page),
			c'release complete cache pages and update the inode block count')
		need(C.ftruncate(fd, i64(4 * page)) == 0 && *(&u8(view + page + 7)) == 0
			&& *(&u8(tail + page + 9)) == 0 && *(&u8(clean + page + 7)) == 0
			&& *(&u8(dirty + page + 7)) == 0 && *(&u8(dirty + 2 * page + 9)) == 0,
			c'regrowth refaults zeroed shared pages and private copies')
		need(C.munmap(voidptr(view), 3 * page) == 0 && C.munmap(voidptr(tail), 2 * page) == 0
			&& C.munmap(voidptr(clean), 3 * page) == 0 && C.munmap(voidptr(dirty), 3 * page) == 0,
			c'unmap truncated aliases')
	}
}

fn truncate_free_kib(fd i32) u64 {
	unsafe {
		mut data := [1024]char{}
		need(C.pread(fd, &data[0], data.len - 1, 0) > 0, c'read the free-memory counter')
		mut total := u64(0)
		mut free := u64(0)
		need(C.sscanf(&data[0], c'MemTotal: %lu kB\nMemFree: %lu kB', &total, &free) == 2,
			c'parse the free-memory counter')
		return free
	}
}

fn check_truncate_storage(fd i32, page usize) {
	unsafe {
		observer := C.open(c'/proc/meminfo', C.O_RDONLY, 0)
		need(observer >= 0 && C.ftruncate(fd, 0) == 0, c'open the truncate storage controls')
		view := map_file(fd, 2 * page, 0, C.MAP_SHARED)
		shadow := map_file(fd, 2 * page, 0, C.MAP_PRIVATE)
		mut before := truncate_free_kib(observer)
		for round in 0 .. 160 {
			need(C.ftruncate(fd, i64(2 * page)) == 0 && *(&u8(view + page)) == 0,
				c'regrow and fault a zeroed cache page')
			*(&u8(view + page)) = 51
			*(&u8(shadow + page)) = 82
			need(*(&u8(view + page)) == 51 && C.ftruncate(fd, 0) == 0, c'revoke cache and COW frames')
			if round == 31 { before = truncate_free_kib(observer) }
		}
		after := truncate_free_kib(observer)
		C.printf(c'LINUX MMAP TRUNCATE STORAGE: rounds=128 before_kib=%lu after_kib=%lu\n', before, after)
		need(before <= after + 8 * u64(page) / 1024, c'whole-page truncation does not retain physical frames')
		need(C.close(observer) == 0 && C.munmap(voidptr(view), 2 * page) == 0
			&& C.munmap(voidptr(shadow), 2 * page) == 0, c'release the truncate storage controls')
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference := argc > 1 && C.strcmp(argv[1], c'--reference') == 0
		page := C.sysconf(C._SC_PAGESIZE)
		if page < 4096 { return 1 }
		for descriptor in [i64(-1), 123456, 0, 0xffffffff, 0x123400000001]! {
			address := C.syscall(isize(C.SYS_mmap), isize(0), page,
				isize(C.PROT_READ | C.PROT_WRITE), isize(C.MAP_PRIVATE | C.MAP_ANONYMOUS),
				isize(descriptor), isize(0))
			if address == -1 {
				C.printf(c'LINUX MMAP FAIL: anonymous fd=%ld errno=%d\n', isize(descriptor), *C.__errno_location())
				return 1
			}
			mut memory := &u8(voidptr(address))
			memory[0] = 42
			memory[page - 1] = 19
			if memory[0] != 42 || memory[page - 1] != 19
				|| C.munmap(voidptr(address), usize(page)) != 0 { return 1 }
		}
		file := C.open(c'/tmp/linux-mmap-file', C.O_CREAT | C.O_EXCL | C.O_RDWR, u32(0o600))
		if file < 0 || C.write(file, c'data', 4) != 4 { return 1 }
		// Only the low C-int descriptor belongs to the ABI argument.
		wide_descriptor := i64(file) | (i64(0x1234) << 32)
		address := C.syscall(isize(C.SYS_mmap), isize(0), page, isize(C.PROT_READ),
			isize(C.MAP_PRIVATE), isize(wide_descriptor), isize(0))
		if address == -1 || (&u8(voidptr(address)))[0] != `d`
			|| (&u8(voidptr(address)))[3] != `a` { C.puts(c'LINUX MMAP FAIL: file descriptor width'); return 1 }
		if C.munmap(voidptr(address), usize(page)) != 0 { return 1 }
		memfd := i32(C.syscall(isize(C.SYS_memfd_create), c'mmap-file-end', isize(0)))
		need(memfd >= 0, c'create memfd for EOF checks')
		for fd in [file, memfd]! {
			check_file_end(fd, usize(page), C.MAP_PRIVATE)
			check_file_end(fd, usize(page), C.MAP_SHARED)
			check_truncate_aliases(fd, usize(page))
		}
		if !reference { check_truncate_storage(memfd, usize(page)) }
		need(C.close(memfd) == 0, c'close memfd')
		C.close(file)
		errno_ptr := C.__errno_location()
		*errno_ptr = 0
		if C.syscall(isize(C.SYS_mmap), isize(0), page, isize(C.PROT_READ),
			isize(C.MAP_PRIVATE), isize(0xffffffff), isize(0)) != -1
			|| *C.__errno_location() != C.EBADF { return 1 }
		C.puts(c'LINUX MMAP SUMMARY: file-end=private,shared backings=tmpfs,memfd truncate=resident,fork')
		C.puts(if reference { c'LINUX MMAP REFERENCE: PASS' } else { c'LINUX MMAP: PASS' })
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
