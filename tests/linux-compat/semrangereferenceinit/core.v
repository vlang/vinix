// SPDX-License-Identifier: GPL-2.0-or-later
module semrangereferenceinit

#include <alloca.h>
#include <stdio.h>
#include <sys/mount.h>
#include <unistd.h>

fn C.alloca(usize) voidptr
fn C.mount(&char, &char, &char, u64, voidptr) i32
fn C.execv(&char, &&char) i32
fn C.puts(&char) i32

@[export: 'main']
pub fn run() i32 {
	unsafe {
		if C.mount(c'proc', c'/proc', c'proc', 0, nil) != 0 {
			C.puts(c'LINUX SEMRANGE REFERENCE FAIL: proc mount')
			return 1
		}
		mut argv := &&char(C.alloca(usize(3 * sizeof(voidptr))))
		argv[0] = &char(c'/sbin/probe')
		argv[1] = &char(c'--reference')
		argv[2] = nil
		C.execv(c'/sbin/probe', argv)
		C.puts(c'LINUX SEMRANGE REFERENCE FAIL: probe exec')
		return 1
	}
}
