// SPDX-License-Identifier: GPL-2.0-or-later
module movemountfixture

#include <errno.h>
#include <fcntl.h>
#include <sched.h>
#include <stdio.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.__errno_location() &i32
fn C._exit(i32)
fn C.close(i32) i32
fn C.fflush(voidptr) i32
fn C.fork() i32
fn C.mkdir(&char, u32) i32
fn C.mount(&char, &char, &char, u64, voidptr) i32
fn C.open(&char, i32, ...) i32
fn C.pause() i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.strcmp(&char, &char) i32
fn C.symlink(&char, &char) i32
fn C.syscall(i64, ...) i64
fn C.umount2(&char, i32) i32
fn C.unlink(&char) i32
fn C.unshare(i32) i32
fn C.waitpid(i32, &i32, i32) i32

const cwd = i64(-100)
const from_empty = u64(4)
const to_empty = u64(64)
const both_empty = from_empty | to_empty
const high = u64(0x42) << 32

fn number() i32 { return unsafe { *C.__errno_location() } }

fn need(ok bool, label &char) {
	if ok { return }
	C.printf(c'LINUX MOVEMOUNT FAIL: %s errno=%d\n', label, number())
	C.fflush(unsafe { nil })
	C._exit(1)
}

fn move(from i64, old &char, to i64, dest &char, flags u64) i64 {
	ret := C.syscall(i64(429), from, old, to, dest, flags)
	return if ret < 0 { -i64(number()) } else { ret }
}

fn mount_id(fd i64, path &char, empty bool) u64 {
	unsafe {
		mut words := [32]u64{}
		flags := if empty { u64(0x1000) } else { u64(0) }
		need(C.syscall(i64(C.SYS_statx), fd, path, flags, u64(0x4000), &words[0]) == 0,
			c'statx mount identity')
		need(words[0] & 0x4000 != 0 && words[18] != 0, c'unique ID returned')
		return words[18]
	}
}

fn tmpfs(path &char) {
	need(C.mount(c'tmpfs', path, c'tmpfs', 0, unsafe { nil }) == 0, c'attach tmpfs')
}

fn wait_ok(child i32, label &char) {
	unsafe {
		mut status := i32(0)
		need(C.waitpid(child, &status, 0) == child && status == 0, label)
	}
}

fn check_errors() {
	unsafe {
		need(move(cwd, nil, cwd, nil, 8) == -C.EINVAL, c'unknown flag before path import')
		need(move(cwd, nil, cwd, nil, 0x300) == -C.EINVAL, c'incompatible modes')
		need(move(cwd, nil, cwd, c'/', 0) == -C.EFAULT, c'bad source address')
		need(move(cwd, c'', cwd, nil, 0) == -C.ENOENT, c'empty source requires flag')
		need(move(-1, c'', cwd, nil, from_empty) == -C.EBADF, c'invalid source fd')
		need(move(cwd, c'/tmp/movemount/missing', cwd, nil, 0) == -C.ENOENT, c'source lookup before destination import')
		need(move(cwd, c'/tmp/movemount/source', cwd, nil, 0) == -C.EFAULT, c'bad destination address')
		need(move(cwd, c'/tmp/movemount/source', -1, c'', to_empty) == -C.EBADF, c'invalid destination fd')
		need(move(cwd, c'/tmp/movemount/source', cwd, c'', 0) == -C.ENOENT, c'empty destination requires flag')
		need(move(cwd, c'/', cwd, c'/tmp/movemount/holder/first', 0) == -C.EINVAL, c'namespace root cannot move')
		need(move(cwd, c'/tmp/movemount/source', cwd, c'/tmp/movemount/source/child', 0) == -C.ELOOP, c'reject an attachment cycle')
		child := C.fork()
		need(child >= 0, c'fork capability check')
		if child == 0 {
			need(C.setgid(1000) == 0 && C.setuid(1000) == 0, c'drop capabilities')
			need(move(cwd, nil, cwd, nil, 8) == -C.EPERM, c'permission before flags and paths')
			C._exit(0)
		}
		wait_ok(child, c'capability check passed')
	}
}

fn check_foreign(from i64, saved_target i64) {
	unsafe {
		child := C.fork()
		need(child >= 0, c'fork mount namespace check')
		if child == 0 {
			need(C.unshare(C.CLONE_NEWNS) == 0, c'copy mount namespace')
			need(move(from, c'', cwd, c'/tmp/movemount/holder/first', from_empty) == -C.EINVAL, c'foreign source fd refused')
			need(move(cwd, c'/tmp/movemount/source', saved_target, c'', to_empty) == -C.EINVAL, c'foreign destination fd refused')
			C._exit(0)
		}
		wait_ok(child, c'foreign descriptor checks passed')
	}
}

fn check_unlinked_file() {
	unsafe {
		leaf := c'/tmp/movemount/leaf'
		alias := c'/tmp/movemount/alias'
		stale := c'/tmp/movemount/stale'
		for path in [leaf, alias, stale]! {
			fd := C.open(path, C.O_CREAT | C.O_WRONLY, u32(0o600))
			need(fd >= 0, c'create bind-file fixture')
			C.close(fd)
		}
		need(C.mount(leaf, alias, nil, C.MS_BIND, nil) == 0, c'bind a regular file')
		fd := C.open(stale, C.O_PATH)
		need(fd >= 0 && C.unlink(stale) == 0, c'keep an unlinked destination fd')
		need(move(cwd, alias, i64(fd), c'', to_empty) == -C.ENOENT, c'reject an unlinked file destination')
		C.close(fd)
		fd_again := C.open(stale, C.O_CREAT | C.O_RDONLY, u32(0o600))
		need(fd_again >= 0 && C.mount(leaf, stale, nil, C.MS_BIND, nil) == 0
			&& C.umount2(stale, C.MNT_DETACH) == 0 && C.unlink(stale) == 0,
			c'keep a previously covered file fd')
		need(move(cwd, alias, i64(fd_again), c'', to_empty) == -C.ENOENT,
			c'reject an unlinked file after its covering mount detached')
		C.close(fd_again)
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference := argc > 1 && C.strcmp(argv[1], c'--reference') == 0
		need(C.mkdir(c'/tmp/movemount', 0o755) == 0 && C.mkdir(c'/tmp/movemount/source', 0o755) == 0 && C.mkdir(c'/tmp/movemount/holder', 0o755) == 0,
			c'create mountpoints')
		tmpfs(c'/tmp/movemount/source')
		tmpfs(c'/tmp/movemount/holder')
		need(C.mkdir(c'/tmp/movemount/source/child', 0o755) == 0 && C.mkdir(c'/tmp/movemount/holder/first', 0o755) == 0 && C.mkdir(c'/tmp/movemount/holder/stack', 0o755) == 0,
			c'prepare nested paths')
		tmpfs(c'/tmp/movemount/source/child')
		check_errors()
		check_unlinked_file()
		from := C.syscall(i64(428), cwd, c'/tmp/movemount/source', u64(0))
		to := C.open(c'/tmp/movemount/holder/first', C.O_PATH)
		need(from >= 0 && to >= 0, c'open path descriptors')
		check_foreign(from, i64(to))
		original := mount_id(cwd, c'/tmp/movemount/source', false)
		child_id := mount_id(cwd, c'/tmp/movemount/source/child', false)
		parent_id := mount_id(cwd, c'/tmp/movemount/holder', false)
		need(move(from | i64(high), c'', i64(to) | i64(high), c'', both_empty | high) == 0,
			c'move between empty-path descriptors with high ABI words')
		need(mount_id(cwd, c'/tmp/movemount/holder/first', false) == original && mount_id(from, c'', true) == original,
			c'path and retained fd agree after move')
		need(mount_id(from, c'child', false) == child_id && mount_id(from, c'..', false) == parent_id,
			c'child keeps its mount and relative parent follows the move')
		need(mount_id(cwd, c'/tmp/movemount/source', false) != original, c'old mountpoint exposes the original tree')
		need(C.symlink(c'/tmp/movemount/holder/first', c'/tmp/movemount/from-link') == 0 && C.symlink(c'/tmp/movemount/holder/stack', c'/tmp/movemount/to-link') == 0, c'create endpoint symlinks')
		need(move(cwd, c'/tmp/movemount/from-link', cwd, c'/tmp/movemount/holder/stack', 0) == -C.EINVAL, c'source symlink requires flag')
		need(move(cwd, c'/tmp/movemount/from-link', cwd, c'/tmp/movemount/to-link', 1) == -C.EINVAL, c'destination symlink requires flag')
		need(move(cwd, c'/tmp/movemount/from-link', cwd, c'/tmp/movemount/to-link', 0x11) == 0, c'follow each symlink when requested')
		need(mount_id(cwd, c'/tmp/movemount/holder/stack', false) == original, c'symlink move preserves ID')
		base := C.open(c'/tmp/movemount/holder', C.O_PATH)
		need(base >= 0 && move(i64(base), c'stack', i64(base), c'first', 0) == 0,
			c'relative paths move through the directory fd')
		C.close(base)
		stack_fd := C.open(c'/tmp/movemount/holder/stack', C.O_PATH)
		need(stack_fd >= 0, c'capture destination before overmount')
		tmpfs(c'/tmp/movemount/holder/stack')
		lower := mount_id(cwd, c'/tmp/movemount/holder/stack', false)
		need(move(from, c'', i64(stack_fd), c'', both_empty) == 0, c'resolve destination overmount above its fd')
		need(mount_id(cwd, c'/tmp/movemount/holder/stack', false) == original && C.umount2(c'/tmp/movemount/holder/stack', C.MNT_DETACH) == 0,
			c'moved mount is topmost')
		need(mount_id(cwd, c'/tmp/movemount/holder/stack', false) == lower, c'unmount reveals the existing stack')
		need(move(from, c'', i64(to), c'', both_empty) == -C.EINVAL, c'detached source fd refused')
		C.close(i32(from))
		C.close(to)
		C.close(stack_fd)
		C.puts(c'LINUX MOVEMOUNT SUMMARY: identity=preserved descriptors=checked stack=preserved')
		C.puts(if reference { c'LINUX MOVEMOUNT REFERENCE: PASS' } else { c'LINUX MOVEMOUNT: PASS' })
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
