// Standalone disposable guest probe, also usable as /init. No frozen harness
// files are changed. Export two empty directories as tag-a and tag-b.
module main

import os
import time

#include <errno.h>
#include <fcntl.h>
#include <sys/mount.h>
#include <unistd.h>

fn C.mount(&char, &char, &char, usize, voidptr) int
fn C.umount(&char) int
fn C.open(&char, int, ...) int
fn C.close(int) int
fn C.read(int, voidptr, usize) isize
fn C.write(int, voidptr, usize) isize
fn C.lseek(int, i64, int) i64
fn C.dup2(int, int) int

const options = 'trans=virtio,version=9p2000.L,cache=none,msize=65536'

fn require(ok bool, operation string) ! {
	if !ok { return error('${operation}: errno=${C.errno}') }
}

fn log(message string) {
	line := 'G3-MULTITAG:${message}\n'
	unsafe { C.write(1, line.str, usize(line.len)) }
}

fn mount_tag(tag string, target string) ! {
	rc := unsafe { C.mount(&char(tag.str), &char(target.str), c'9p', 0, voidptr(options.str)) }
	require(rc == 0, 'mount ${tag}')!
}

fn reject_unknown() ! {
	rc := unsafe { C.mount(c'not-exported', c'/g3-unknown', c'9p', 0, voidptr(options.str)) }
	require(rc == -1 && C.errno == C.ENODEV, 'unknown tag must return ENODEV')!
}

fn open_value(path string) !int {
	fd := unsafe { C.open(&char(path.str), C.O_CREAT | C.O_EXCL | C.O_RDWR, 0o644) }
	require(fd >= 0, 'create ${path}')!
	return fd
}

fn write_value(fd int, text string) ! {
	require(C.lseek(fd, 0, 0) == 0, 'rewind write')!
	n := unsafe { C.write(fd, text.str, usize(text.len)) }
	require(n == text.len, 'write')!
}

fn read_value(fd int, expected string) ! {
	require(C.lseek(fd, 0, 0) == 0, 'rewind read')!
	mut bytes := [64]u8{}
	n := unsafe { C.read(fd, &bytes[0], 64) }
	require(n == expected.len, 'read length')!
	require(unsafe { tos(&bytes[0], int(n)) } == expected, 'read content')!
}

fn qualify() ! {
	for path in ['/g3-a', '/g3-b', '/g3-unknown'] { os.mkdir_all(path)! }
	reject_unknown()!
	mount_tag('tag-a', '/g3-a')!
	mount_tag('tag-b', '/g3-b')!
	log('two-mounts PASS')
	a := open_value('/g3-a/value')!
	b := open_value('/g3-b/value')!
	defer { C.close(b) }
	write_value(a, 'AAA\n')!
	write_value(b, 'BBB\n')!
	read_value(a, 'AAA\n')!
	read_value(b, 'BBB\n')!
	log('independent-io PASS')
	reject_unknown()!
	read_value(a, 'AAA\n')!
	read_value(b, 'BBB\n')!
	log('unknown-enodev PASS')
	require(C.close(a) == 0, 'close a')!
	require(C.umount(c'/g3-a') == 0, 'unmount a')!
	read_value(b, 'BBB\n')!
	write_value(b, 'CCC\n')!
	read_value(b, 'CCC\n')!
	log('unmount-isolation PASS')
	mount_tag('tag-a', '/g3-a')!
	a2 := C.open(c'/g3-a/value', C.O_RDONLY)
	require(a2 >= 0, 'reopen a')!
	read_value(a2, 'AAA\n')!
	require(C.close(a2) == 0, 'close remount')!
	require(C.umount(c'/g3-a') == 0, 'unmount remount')!
	log('same-tag-remount PASS')
}

fn main() {
	if os.getpid() == 1 {
		fd := C.open(c'/dev/com1', C.O_RDWR)
		if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	}
	mut status := 0
	qualify() or { log('FAIL ${err}'); status = 1 }
	log('OUTCOME ${if status == 0 { 'PASS' } else { 'FAIL' }} status=${status}')
	if os.getpid() == 1 { for { time.sleep(time.second) } }
	exit(status)
}
