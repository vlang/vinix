// SPDX-License-Identifier: GPL-2.0-or-later
module opentreefixture

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mount.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.__errno_location() &i32
fn C._exit(i32)
fn C.close(i32) i32
fn C.fcntl(i32, i32, ...) i32
fn C.fflush(voidptr) i32
fn C.fork() i32
fn C.ioctl(i32, u64, ...) i32
fn C.mkdir(&char, u32) i32
fn C.mkfifo(&char, u32) i32
fn C.mount(&char, &char, &char, u64, voidptr) i32
fn C.open(&char, i32, ...) i32
fn C.pause() i32
fn C.pipe(&i32) i32
fn C.poll(&C.pollfd, u64, i32) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.read(i32, voidptr, u64) i64
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.snprintf(&char, u64, &char, ...) i32
fn C.strcmp(&char, &char) i32
fn C.symlink(&char, &char) i32
fn C.syscall(i64, ...) i64
fn C.umount2(&char, i32) i32
fn C.unlink(&char) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.write(i32, voidptr, u64) i64

const cwd = i64(-100)
const empty = u64(0x1000)
const nofollow = u64(0x100)
const noautomount = u64(0x800)
const clone = u64(1)
const recursive = u64(0x8000)
const cloexec = u64(0x80000)
const high = u64(0x42) << 32
const stat_mask = u64(0x4101)

struct C.pollfd {
mut:
	fd i32
	events i16
	revents i16
}

struct Identity {
	inode u64
	mount_id u64
	kind u32
}

fn number() i32 {
	return unsafe { *C.__errno_location() }
}

fn need(ok bool, label &char) {
	if ok { return }
	C.printf(c'LINUX OPENTREE FAIL: %s errno=%d\n', label, number())
	C.fflush(nil)
	C._exit(1)
}

fn tree(dirfd i64, pathname &char, flags u64) i64 {
	ret := C.syscall(i64(428), dirfd, pathname, flags)
	return if ret < 0 { -i64(number()) } else { ret }
}

fn identity(fd i64, pathname &char, flags u64) Identity {
	unsafe {
		mut words := [32]u64{}
		need(C.syscall(i64(C.SYS_statx), fd, pathname, flags, stat_mask, &words[0]) == 0, c'read target identity')
		return Identity{inode: words[4], mount_id: words[18], kind: u32(words[3] >> 32) & 0xf000}
	}
}

fn check_fd(fd i64, expected Identity, exec_flag i32) {
	need(fd >= 0, c'open_tree returned a descriptor')
	need(C.fcntl(i32(fd), C.F_GETFL) == C.O_PATH, c'description is O_PATH only')
	need(C.fcntl(i32(fd), C.F_GETFD) == exec_flag, c'close-on-exec setting')
	actual := identity(fd, c'', empty)
	need(actual.inode == expected.inode && actual.mount_id == expected.mount_id && actual.kind == expected.kind,
		c'descriptor keeps target inode, type and mount ID')
}

fn check_pipe() {
	unsafe {
		mut ends := [2]i32{}
		need(C.pipe(&ends[0]) == 0, c'create anonymous pipe')
		actual := identity(i64(ends[0]), c'', empty)
		fd := tree(i64(ends[0]), c'', empty)
		check_fd(fd, actual, 0)
		need(C.close(i32(fd)) == 0, c'close path-only pipe reference')
		mut pathname := [64]char{}
		C.snprintf(&pathname[0], sizeof(pathname), c'/proc/self/fd/%d', ends[0])
		magic := tree(cwd, &pathname[0], 0)
		check_fd(magic, actual, 0)
		C.close(i32(magic))
		mut byte := u8(0)
		need(C.write(ends[1], c'x', 1) == 1 && C.read(ends[0], &byte, 1) == 1 && byte == `x`,
			c'path-only closes preserve the original pipe endpoints')
		C.close(ends[0])
		C.close(ends[1])
	}
}

fn check_pty(reference bool) {
	unsafe {
		if reference {
			need(C.mkdir(c'/dev/pts', 0o755) == 0
				&& C.mount(c'devpts', c'/dev/pts', c'devpts', 0, c'ptmxmode=0666,mode=0600') == 0,
				c'prepare reference devpts')
		}
		master := C.open(if reference { c'/dev/pts/ptmx' } else { c'/dev/ptmx' }, C.O_RDWR | C.O_NOCTTY)
		mut id := u32(0)
		mut unlocked := i32(0)
		need(master >= 0 && C.ioctl(master, u64(C.TIOCGPTN), &id) == 0
			&& C.ioctl(master, u64(C.TIOCSPTLCK), &unlocked) == 0, c'allocate PTY')
		mut pathname := [40]char{}
		C.snprintf(&pathname[0], sizeof(pathname), c'/dev/pts/%u', id)
		slave := C.open(&pathname[0], C.O_RDWR | C.O_NOCTTY)
		need(slave >= 0, c'open live PTY slave')
		fd := tree(cwd, &pathname[0], 0)
		check_fd(fd, identity(i64(slave), c'', empty), 0)
		C.close(i32(fd))
		mut pollfd := C.pollfd{fd: master}
		need(C.poll(&pollfd, 1, 0) == 0, c'path-only close leaves the PTY connected')
		C.close(slave)
		need(C.poll(&pollfd, 1, 0) == 1 && pollfd.revents & C.POLLHUP != 0,
			c'final live endpoint closes the PTY')
		C.close(master)
	}
}

fn check_permissions() {
	unsafe {
		child := C.fork()
		need(child >= 0, c'fork permission control')
		if child == 0 {
			need(C.setgid(1000) == 0 && C.setuid(1000) == 0, c'drop privileges')
			need(tree(cwd, nil, clone) == -C.EPERM, c'clone capability precedes path import')
			need(tree(cwd, c'/tmp/opentree/private/child', 0) == -C.EACCES, c'path traversal checks search access')
			fd := tree(cwd, c'/tmp/opentree/private', 0)
			need(fd >= 0, c'leaf access needs metadata permission only')
			C.close(i32(fd))
			C._exit(0)
		}
		mut status := i32(0)
		need(C.waitpid(child, &status, 0) == child && status == 0, c'permission control passed')
	}
}

fn check_full() {
	unsafe {
		child := C.fork()
		need(child >= 0, c'fork descriptor limit control')
		if child == 0 {
			mut limit := [u64(16), 16]!
			need(C.syscall(i64(C.SYS_prlimit64), 0, C.RLIMIT_NOFILE, &limit[0], nil) == 0, c'lower descriptor limit')
			mut last := i64(-1)
			for _ in 0 .. 16 {
				fd := tree(cwd, c'/', 0)
				if fd < 0 { need(fd == -C.EMFILE, c'reached descriptor limit'); break }
				last = fd
			}
			need(last >= 0 && tree(cwd, nil, 0) == -C.EMFILE, c'full table precedes pathname import')
			need(tree(cwd, nil, recursive) == -C.EINVAL, c'invalid flags precede full table')
			C.close(i32(last))
			need(tree(cwd, nil, 0) == -C.EFAULT, c'pathname fault after a reservation')
			need(tree(cwd, c'/', 0) == last, c'fault released reserved slot')
			C._exit(0)
		}
		mut status := i32(0)
		need(C.waitpid(child, &status, 0) == child && status == 0, c'descriptor limit control passed')
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference := argc > 1 && C.strcmp(argv[1], c'--reference') == 0
		need(tree(cwd, nil, recursive) == -C.EINVAL && tree(cwd, nil, 2) == -C.EINVAL, c'validate flags before lookup')
		need(tree(cwd, nil, empty) == -C.EFAULT && tree(cwd, c'', 0) == -C.ENOENT, c'null and empty filename errors')
		start := tree(cwd, c'', empty)
		check_fd(start, identity(cwd, c'.', 0), 0)
		C.close(i32(start))
		need(C.mkdir(c'/tmp/opentree', 0o755) == 0 && C.mkdir(c'/tmp/opentree/private', 0o700) == 0
			&& C.mkdir(c'/tmp/opentree/alias', 0o755) == 0 && C.mkdir(c'/tmp/opentree/source', 0o755) == 0,
			c'prepare fixture directories')
		need(C.mount(c'tmpfs', c'/tmp/opentree/source', c'tmpfs', 0, nil) == 0, c'attach source mount')
		file := C.open(c'/tmp/opentree/source/data', C.O_RDWR | C.O_CREAT, u32(0o600))
		need(file >= 0 && C.symlink(c'data', c'/tmp/opentree/source/link') == 0
			&& C.mkfifo(c'/tmp/opentree/source/fifo', 0o600) == 0, c'create targets')
		need(C.mount(c'/tmp/opentree/source', c'/tmp/opentree/alias', nil, C.MS_BIND, nil) == 0, c'attach bind alias')
		alias := tree(-1, c'/tmp/opentree/alias', cloexec | noautomount | high)
		expected := identity(cwd, c'/tmp/opentree/alias', 0)
		check_fd(alias, expected, C.FD_CLOEXEC)
		need(expected.mount_id != identity(cwd, c'/tmp/opentree/source', 0).mount_id, c'separate attachment IDs')
		link := tree(alias | i64(high), c'link', nofollow)
		check_fd(link, identity(alias, c'link', nofollow), 0)
		C.close(i32(link))
		regular := tree(alias, c'link', 0)
		check_fd(regular, identity(alias, c'data', 0), 0)
		need(tree(regular, c'.', 0) == -C.ENOTDIR && tree(-1, c'.', 0) == -C.EBADF, c'relative descriptor errors')
		need(tree(alias, c'link/', nofollow) == -C.ENOTDIR, c'trailing slash requires a directory')
		fifo := tree(alias, c'fifo', 0)
		check_fd(fifo, identity(alias, c'fifo', 0), 0)
		C.close(i32(fifo))
		need(C.umount2(c'/tmp/opentree/alias', C.MNT_DETACH) == 0, c'lazy detach alias')
		reopened := tree(alias, c'', empty)
		check_fd(reopened, expected, 0)
		need(C.unlink(c'/tmp/opentree/source/data') == 0, c'unlink original file')
		unlinked := tree(i64(file), c'', empty)
		check_fd(unlinked, identity(i64(file), c'', empty), 0)
		for fd in [alias, regular, reopened, unlinked, i64(file)]! { C.close(i32(fd)) }
		check_pipe()
		check_pty(reference)
		check_permissions()
		check_full()
		C.puts(c'LINUX OPENTREE SUMMARY: identity=preserved endpoints=preserved reservation=released')
		C.puts(if reference { c'LINUX OPENTREE REFERENCE: PASS' } else { c'LINUX OPENTREE: PASS' })
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
