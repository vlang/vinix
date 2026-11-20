// SPDX-License-Identifier: GPL-2.0-or-later
// fchmodat2(2): plain, relative and followed changes; AT_SYMLINK_NOFOLLOW's
// EOPNOTSUPP for links; AT_EMPTY_PATH on ordinary, O_PATH and working
// directory targets; flag, mode and descriptor words; error order; and
// unprivileged ownership after the symlink check.
// The same ELF runs as Vinix's init and, given --reference, under Linux.
module fchmodat2fixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <stdio.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.stat {
	st_mode u32
}

fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.symlink(&char, &char) i32
fn C.mkdir(&char, u32) i32
fn C.chdir(&char) i32
fn C.chown(&char, u32, u32) i32
fn C.alloca(usize) voidptr
fn C.lstat(&char, &C.stat) i32
fn C.strcmp(&char, &char) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32

const cwd = i64(-100)
const nofollow = u64(0x100)
const empty_path = u64(0x1000)

struct State {
mut:
	checks   int
	failures int
}

struct Result {
	value isize
	err   int
}

fn chmod2(dirfd i64, path voidptr, mode u64, flags u64) Result {
	unsafe {
		errno_ptr := C.__errno_location()
		*errno_ptr = 0
		value := C.syscall(isize(452), dirfd, path, mode, flags)
		return Result{value, if value < 0 { *errno_ptr } else { 0 }}
	}
}

fn mode_of(path &char) u32 {
	unsafe {
		st := &C.stat(C.alloca(256))
		return if C.lstat(path, st) == 0 { st.st_mode } else { u32(0xffffffff) }
	}
}

fn check(mut s State, label &char, ok bool, got Result) {
	s.checks++
	if !ok {
		s.failures++
		C.printf(c'LINUX FCHMODAT2 FAIL: %s value=%ld errno=%d\n', label, got.value, got.err)
	}
}

// A call succeeds and leaves `path` with permission bits `want`.
fn changes(mut s State, label &char, got Result, path &char, want u32) {
	check(mut s, label, got.value == 0 && mode_of(path) & 0o7777 == want, got)
}

fn fails(mut s State, label &char, got Result, err int) {
	check(mut s, label, got.value == -1 && got.err == err, got)
}

fn cases(mut s State) {
	unsafe {
		C.mkdir(c'/tmp', 0o1777)
		C.mkdir(c'/tmp/fchmodat2', 0o755)
		file := &char(c'/tmp/fchmodat2/file')
		link := &char(c'/tmp/fchmodat2/link')
		f := C.open(file, C.O_CREAT | C.O_RDWR, 0o644)
		C.symlink(file, link)
		C.symlink(c'/tmp/fchmodat2/missing', c'/tmp/fchmodat2/dangling')
		dir := C.open(c'/tmp/fchmodat2', C.O_RDONLY | C.O_DIRECTORY)
		link_mode := mode_of(link)
		changes(mut s, c'absolute', chmod2(cwd, file, 0o600, 0), file, 0o600)
		changes(mut s, c'relative', chmod2(dir, c'file', 0o640, 0), file, 0o640)
		changes(mut s, c'follows link', chmod2(cwd, link, 0o604, 0), file, 0o604)
		check(mut s, c'link unchanged', mode_of(link) == link_mode, Result{0, 0})
		fails(mut s, c'nofollow link', chmod2(cwd, link, 0o600, nofollow), C.EOPNOTSUPP)
		check(mut s, c'nofollow target unchanged', mode_of(file) & 0o7777 == 0o604, Result{0, 0})
		changes(mut s, c'nofollow file', chmod2(cwd, file, 0o600, nofollow), file, 0o600)
		fails(mut s, c'nofollow dangling', chmod2(cwd, c'/tmp/fchmodat2/dangling', 0o600, nofollow),
			C.EOPNOTSUPP)
		fails(mut s, c'dangling', chmod2(cwd, c'/tmp/fchmodat2/dangling', 0o600, 0), C.ENOENT)
		changes(mut s, c'all bits', chmod2(cwd, file, 0o107777, 0), file, 0o7777)
		check(mut s, c'type kept', mode_of(file) & 0o170000 == 0o100000, Result{0, 0})
		for flag in [u64(0x200), 0x400, 0x800, 0x80000000, 0x1001]! {
			fails(mut s, c'unknown flag', chmod2(cwd, file, 0o644, flag & ~u64(0x1000) | 0x200), C.EINVAL)
		}
		// Flags are checked before the path.
		fails(mut s, c'flag before path', chmod2(cwd, c'/tmp/fchmodat2/none', 0o644, 0x200), C.EINVAL)
		changes(mut s, c'empty path', chmod2(f, c'', 0o611, empty_path), file, 0o611)
		fails(mut s, c'empty without flag', chmod2(f, c'', 0o611, 0), C.ENOENT)
		fails(mut s, c'null path', chmod2(f, nil, 0o611, empty_path), C.EFAULT)
		path_fd := C.open(file, C.O_PATH)
		changes(mut s, c'o_path', chmod2(path_fd, c'', 0o622, empty_path), file, 0o622)
		link_fd := C.open(link, C.O_PATH | C.O_NOFOLLOW)
		fails(mut s, c'o_path link', chmod2(link_fd, c'', 0o633, empty_path), C.EOPNOTSUPP)
		fails(mut s, c'o_path link nofollow', chmod2(link_fd, c'', 0o633, empty_path | nofollow),
			C.EOPNOTSUPP)
		fails(mut s, c'missing', chmod2(cwd, c'/tmp/fchmodat2/none', 0o600, 0), C.ENOENT)
		fails(mut s, c'empty at cwd', chmod2(cwd, c'', 0o600, 0), C.ENOENT)
		fails(mut s, c'null at cwd', chmod2(cwd, nil, 0o600, 0), C.EFAULT)
		// mode is a 16-bit umode_t; dirfd and flags are C ints.
		changes(mut s, c'mode word', chmod2(cwd, file, (u64(1) << 32) | 0o644, 0), file, 0o644)
		changes(mut s, c'dirfd word', chmod2((i64(1) << 32) | i64(dir), c'file', 0o640, 0), file, 0o640)
		changes(mut s, c'flags word', chmod2(cwd, file, 0o644, u64(1) << 32), file, 0o644)
		fails(mut s, c'bad dirfd', chmod2(999, c'file', 0o640, 0), C.EBADF)
		fails(mut s, c'file as dirfd', chmod2(f, c'file', 0o640, 0), C.ENOTDIR)
		// An empty path at AT_FDCWD names the working directory.
		C.chdir(c'/tmp/fchmodat2')
		changes(mut s, c'working directory', chmod2(cwd, c'', 0o750, empty_path), c'/tmp/fchmodat2', 0o750)
		chmod2(cwd, c'', 0o755, empty_path)
		C.chdir(c'/')
		// An unprivileged caller: links are refused before ownership is checked.
		C.chown(c'/tmp/fchmodat2', 1000, 1000)
		child := C.fork()
		if child == 0 {
			C.setgroups(0, nil)
			C.setgid(1000)
			C.setuid(1000)
			mut local := State{}
			fails(mut local, c'root file', chmod2(cwd, file, 0o600, 0), C.EPERM)
			fails(mut local, c'root link', chmod2(cwd, link, 0o600, nofollow), C.EOPNOTSUPP)
			own := &char(c'/tmp/fchmodat2/own')
			C.close(C.open(own, C.O_CREAT | C.O_RDWR, 0o644))
			changes(mut local, c'own file', chmod2(cwd, own, 0o600, nofollow), own, 0o600)
			C.printf(c'LINUX FCHMODAT2 CHILD: checks=%d failures=%d\n', local.checks, local.failures)
			C.fflush(nil)
			C._exit(if local.failures == 0 { 0 } else { 1 })
		}
		mut status := i32(0)
		C.waitpid(child, &status, 0)
		check(mut s, c'unprivileged child', status == 0, Result{isize(status), 0})
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference := argc > 1 && C.strcmp(argv[1], c'--reference') == 0
		mut s := State{}
		cases(mut s)
		C.printf(c'LINUX FCHMODAT2 SUMMARY: checks=%d failures=%d\n', s.checks, s.failures)
		if s.failures == 0 {
			C.puts(if reference { c'LINUX FCHMODAT2 REFERENCE: PASS' } else { c'LINUX FCHMODAT2: PASS' })
		}
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
