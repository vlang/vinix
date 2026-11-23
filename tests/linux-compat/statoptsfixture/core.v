// SPDX-License-Identifier: GPL-2.0-or-later
module statoptsfixture

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/syscall.h>
#include <unistd.h>

fn C.__errno_location() &i32
fn C._exit(i32)
fn C.chmod(&char, u32) i32
fn C.chown(&char, u32, u32) i32
fn C.fflush(voidptr) i32
fn C.mkdir(&char, u32) i32
fn C.mount(&char, &char, &char, u64, voidptr) i32
fn C.pause() i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.strcmp(&char, &char) i32
fn C.strlen(&char) u64
fn C.syscall(i64, ...) i64

const options_mask = u64(0x80)
const type_mask = u64(0x20)
const header_size = u64(512)
const untouched = u64(0xa5a5a5a5a5a5a5a5)

fn need(condition bool, label &char) {
	if condition { return }
	unsafe {
		C.printf(c'LINUX STATOPTS FAIL: %s errno=%d\n', label, *C.__errno_location())
		C.fflush(nil)
		C._exit(1)
	}
}

fn mount_id(path &char) u64 {
	unsafe {
		mut words := [32]u64{}
		need(C.syscall(i64(C.SYS_statx), i64(C.AT_FDCWD), path, u64(0), u64(0x4000), &words[0]) == 0,
			c'resolve mount ID')
		need(words[0] & 0x4000 != 0 && words[18] != 0, c'unique ID present')
		return words[18]
	}
}

fn query(id u64, mask u64, out &u64, capacity u64) i64 {
	unsafe {
		mut request := [u64(32), id, mask, 0]!
		ret := C.syscall(i64(457), &request[0], out, capacity, u64(0))
		return if ret < 0 { -i64(*C.__errno_location()) } else { ret }
	}
}

fn check_options(id u64, expected &char) {
	unsafe {
		mut words := [96]u64{}
		words[0] = untouched
		need(query(id, options_mask, &words[0], header_size) == -C.EOVERFLOW && words[0] == untouched,
			c'header-only output fails without copying')
		capacity := header_size + 1 + C.strlen(expected) + 1
		need(query(id, options_mask, &words[0], capacity - 1) == -C.EOVERFLOW && words[0] == untouched,
			c'short option output fails without copying')
		need(query(id, options_mask, &words[0], capacity) == 0, c'exact option buffer fits')
		need(words[1] == options_mask && words[0] >> 32 == 1 && u64(u32(words[0])) == capacity,
			c'options mask, offset and total size')
		strings := &u8(&words[64])
		if C.strcmp(&char(strings + 1), expected) != 0 {
			C.printf(c'LINUX STATOPTS DETAIL: expected=%s actual=%s\n', expected, &char(strings + 1))
		}
		need(strings[0] == 0 && C.strcmp(&char(strings + 1), expected) == 0, c'canonical options')
		need(query(id, type_mask | options_mask, &words[0], sizeof(words)) == 0, c'type and options fit together')
		need(words[1] == type_mask | options_mask && words[4] >> 32 == 1 && words[0] >> 32 == 7,
			c'combined output places type before options')
		need(C.strcmp(&char(strings + 1), c'tmpfs') == 0 && C.strcmp(&char(strings + 7), expected) == 0,
			c'combined string contents')
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference := argc > 1 && C.strcmp(argv[1], c'--reference') == 0
		need(C.mkdir(c'/tmp/statopts', 0o755) == 0
			&& C.mkdir(c'/tmp/statopts/config', 0o755) == 0
			&& C.mkdir(c'/tmp/statopts/bind', 0o755) == 0
			&& C.mkdir(c'/tmp/statopts/limits', 0o755) == 0
			&& C.mkdir(c'/tmp/statopts/default', 0o755) == 0, c'prepare mountpoints')
		need(C.mount(c'tmpfs', c'/tmp/statopts/config', c'tmpfs', C.MS_NOEXEC,
			c'gid=2345,mode=07401,uid=1234,inode64') == 0, c'mount configured tmpfs')
		need(C.mkdir(c'/tmp/statopts/config/sub', 0o755) == 0
			&& C.mount(c'/tmp/statopts/config/sub', c'/tmp/statopts/bind', nil, C.MS_BIND, nil) == 0,
			c'bind a subdirectory')
		id := mount_id(c'/tmp/statopts/config')
		alias := mount_id(c'/tmp/statopts/bind')
		need(id != alias, c'bind and source have different mount IDs')
		check_options(id, c'mode=7401,uid=1234,gid=2345,inode64')
		check_options(alias, c'mode=7401,uid=1234,gid=2345,inode64')
		need(C.chown(c'/tmp/statopts/config', 3456, 4567) == 0
			&& C.chmod(c'/tmp/statopts/config', 0o755) == 0, c'change root inode metadata')
		check_options(id, c'mode=7401,uid=1234,gid=2345,inode64')
		check_options(alias, c'mode=7401,uid=1234,gid=2345,inode64')
		need(C.mount(c'tmpfs', c'/tmp/statopts/limits', c'tmpfs', 0,
			c'uid=4294967294,gid=4294967294,mode=07,inode64') == 0, c'mount widest uid and gid')
		check_options(mount_id(c'/tmp/statopts/limits'), c'mode=007,uid=4294967294,gid=4294967294,inode64')
		need(C.mount(c'tmpfs', c'/tmp/statopts/default', c'tmpfs', 0,
			c'mode=1777,uid=0,gid=0,inode64') == 0, c'mount with default owner and mode')
		check_options(mount_id(c'/tmp/statopts/default'), c'inode64')
		C.puts(c'LINUX STATOPTS SUMMARY: options=canonical bind=shared metadata=stable')
		C.puts(if reference { c'LINUX STATOPTS REFERENCE: PASS' } else { c'LINUX STATOPTS: PASS' })
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
