// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module mmapfixture

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.syscall(isize, ...) isize
fn C.sysconf(i32) isize
fn C.__errno_location() &i32
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.pwrite(i32, voidptr, usize, i64) isize
fn C.ftruncate(i32, i64) i32
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

fn expect_fault(address usize, writing bool, signal i32, code i32) {
	unsafe {
		child := C.fork()
		need(child >= 0, c'fork a faulting worker')
		if child == 0 {
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

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
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
		}
		need(C.close(memfd) == 0, c'close memfd')
		C.close(file)
		errno_ptr := C.__errno_location()
		*errno_ptr = 0
		if C.syscall(isize(C.SYS_mmap), isize(0), page, isize(C.PROT_READ),
			isize(C.MAP_PRIVATE), isize(0xffffffff), isize(0)) != -1
			|| *C.__errno_location() != C.EBADF { return 1 }
		C.puts(c'LINUX MMAP SUMMARY: file-end=private,shared backings=tmpfs,memfd')
		reference := argc > 1 && C.strcmp(argv[1], c'--reference') == 0
		C.puts(if reference { c'LINUX MMAP REFERENCE: PASS' } else { c'LINUX MMAP: PASS' })
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
