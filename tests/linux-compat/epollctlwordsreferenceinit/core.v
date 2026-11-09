// SPDX-License-Identifier: GPL-2.0-or-later
module epollctlwordsreferenceinit

#include <alloca.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/mount.h>
#include <unistd.h>

fn C.alloca(usize) voidptr
fn C.mount(&char, &char, &char, u64, voidptr) i32
fn C.execv(&char, &&char) i32
fn C.puts(&char) i32
fn C.open(&char, i32, ...) i32
fn C.read(i32, voidptr, uint) int
fn C.close(i32) i32

@[export: 'main']
pub fn run() i32 {
	unsafe {
		if C.mount(c'proc', c'/proc', c'proc', 0, nil) != 0 {
			C.puts(c'LINUX EPOLLCTLWORDS REFERENCE FAIL: proc mount')
			return 1
		}
		// Keep the kernel identity even when console boot chatter is suppressed.
		fd := C.open(c'/proc/version', C.O_RDONLY)
		mut version := [4096]char{}
		length := C.read(fd, &version[0], 4095)
		C.close(fd)
		if fd < 0 || length <= 0 || length >= 4096 {
			C.puts(c'LINUX EPOLLCTLWORDS REFERENCE FAIL: kernel version')
			return 1
		}
		version[int(length)] = 0
		C.puts(&version[0])
		mut argv := &&char(C.alloca(usize(3 * sizeof(voidptr))))
		argv[0] = &char(c'/sbin/probe')
		argv[1] = &char(c'--reference')
		argv[2] = nil
		C.execv(c'/sbin/probe', argv)
		C.puts(c'LINUX EPOLLCTLWORDS REFERENCE FAIL: probe exec')
		return 1
	}
}
