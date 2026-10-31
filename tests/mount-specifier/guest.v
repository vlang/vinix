// SPDX-License-Identifier: GPL-2.0-or-later
// PID 1 regression for the legacy mount paths. Run only in disposable QEMU.
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
fn C.dup2(int, int) int
fn C.close(int) int
fn C.write(int, voidptr, usize) isize

fn say(message string) {
	text := 'M16A-DISPATCH:${message}\n'
	unsafe { C.write(1, text.str, usize(text.len)) }
}

fn mount_at(source string, target string, kind string, options string) ! {
	os.mkdir_all(target)!
	if unsafe { C.mount(source.str, target.str, kind.str, 0, options.str) } != 0 {
		return error('mount ${kind} at ${target} errno=${C.errno}')
	}
}

fn unmount_at(target string) ! {
	if unsafe { C.umount(target.str) } != 0 {
		return error('umount ${target} errno=${C.errno}')
	}
}

fn regression() ! {
	mount_at('none', '/m16a-tmp', 'tmpfs', 'mode=1777,uid=0,gid=0')!
	os.write_file('/m16a-tmp/check', 'tmpfs-regression\n')!
	assert os.read_file('/m16a-tmp/check')! == 'tmpfs-regression\n'
	mode := os.stat('/m16a-tmp')!
	assert mode.mode & 0o7777 == 0o1777
	say('tmpfs PASS mode=1777 write-read')
	unmount_at('/m16a-tmp')!
	mount_at('none', '/m16a-proc', 'proc', '')!
	meminfo := os.read_file('/m16a-proc/meminfo')!
	assert meminfo.contains('MemTotal:')
	say('proc PASS meminfo')
	unmount_at('/m16a-proc')!
	mount_at('/dev/sd0', '/m16a-ext2', 'ext2', '')!
	assert os.read_file('/m16a-ext2/fixture.txt')! == 'm16a-ext2-fixture\n'
	os.write_file('/m16a-ext2/guest.txt', 'm16a-ext2-write\n')!
	assert os.read_file('/m16a-ext2/guest.txt')! == 'm16a-ext2-write\n'
	say('ext2 PASS fixture write-read')
	unmount_at('/m16a-ext2')!
	os.mkdir_all('/lower')!
	os.mkdir_all('/upper')!
	os.mkdir_all('/work')!
	os.write_file('/lower/lower.txt', 'overlay-lower\n')!
	mount_at('overlay', '/m16a-overlay', 'overlay', 'lowerdir=/lower,upperdir=/upper,workdir=/work')!
	assert os.read_file('/m16a-overlay/lower.txt')! == 'overlay-lower\n'
	os.write_file('/m16a-overlay/new.txt', 'overlay-upper\n')!
	assert os.read_file('/upper/new.txt')! == 'overlay-upper\n'
	say('overlay PASS lower read upper write')
	unmount_at('/m16a-overlay')!
}

fn main() {
	serial := C.open(c'/dev/com1', C.O_WRONLY)
	if serial >= 0 {
		C.dup2(serial, 1)
		C.dup2(serial, 2)
		if serial > 2 { C.close(serial) }
	}
	say('START')
	mut outcome := 'PASS'
	regression() or {
		say('FAIL ${err.msg()}')
		outcome = 'FAIL'
	}
	say('OUTCOME ${outcome}')
	for { time.sleep(time.second) }
}
