// SPDX-License-Identifier: GPL-2.0-or-later
module fcntlabireferenceinit

#include <alloca.h>
#include <stdio.h>
#include <unistd.h>
fn C.alloca(usize) voidptr
fn C.execv(&char, &&char) i32
fn C.puts(&char) i32
@[export: 'main']
pub fn run() i32 {
	unsafe {
		mut argv := &&char(C.alloca(usize(3 * sizeof(voidptr))))
		argv[0] = &char(c'/sbin/probe'); argv[1] = &char(c'--reference'); argv[2] = nil
		C.execv(c'/sbin/probe', argv)
		C.puts(c'LINUX FCNTLABI REFERENCE FAIL: probe exec'); return 1
	}
}
