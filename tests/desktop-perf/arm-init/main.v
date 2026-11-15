// SPDX-License-Identifier: GPL-2.0-or-later
module perfinitarm

#include <alloca.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>

fn C.alloca(usize) voidptr
fn C.mount(&char, &char, &char, u64, voidptr) i32
fn C.execv(&char, &&char) i32
fn C.open(&char, i32) i32
fn C.dup2(i32, i32) i32
fn C.close(i32) i32
fn C.mkdir(&char, u32) i32
fn C.access(&char, i32) i32
fn C.__errno_location() &i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32

// The module entry uses native C-width calls and stack argv storage. It needs
// no V runtime, allocator or compiler-generated diagnostic formatting helper.
@[export: 'main']
pub fn run() i32 {
	unsafe {
		fd := C.open(c'/dev/console', C.O_WRONLY)
		if fd < 0 { return 1 }
		if C.dup2(fd, 1) < 0 || C.dup2(fd, 2) < 0 { return 1 }
		if fd > 2 { C.close(fd) }
		if C.mkdir(c'/root', 0o755) != 0 && *C.__errno_location() != C.EEXIST {
			C.printf(c'PERF-ERROR arm mkdir /root failed errno=%d\n', *C.__errno_location())
			C.fflush(nil)
			return 1
		}
		if C.mount(c'/dev/vda', c'/root', c'ext2', 0, nil) != 0 {
			mount_errno := *C.__errno_location()
			present := C.access(c'/dev/vda', C.F_OK) == 0
			C.printf(c'PERF-ERROR arm ext2 /root mount failed errno=%d device_present=%s\n', mount_errno, if present {
				&char(c'true')
			} else {
				&char(c'false')
			})
			C.fflush(nil)
			return 1
		}
		C.puts(c'PERF-ARM root=/dev/vda filesystem=ext2 resolution=2048x1536')
		C.fflush(nil)
		argv := &&char(C.alloca(usize(3 * sizeof(voidptr))))
		argv[0] = &char(c'/bin/sh')
		argv[1] = &char(c'/opt/vinix-perf/perf-init.sh')
		argv[2] = nil
		C.execv(c'/bin/sh', argv)
		C.puts(c'PERF-ERROR arm perf-init exec failed')
		C.fflush(nil)
		return 1
	}
}
