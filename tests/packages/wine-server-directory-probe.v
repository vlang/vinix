// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import time
import tests.packages.wineserverdirectoryfixture

#include <unistd.h>
#include <fcntl.h>
#include <grp.h>
#include <sys/wait.h>
fn C.getpid() i32
fn C.open(&char, i32, ...i32) i32
fn C.close(i32) i32
fn C.dup2(i32, i32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.setgroups(u64, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.alarm(u32) u32
fn C._exit(i32)

fn main() {
	if C.getpid() != 1 { eprintln('requires fixture PID 1'); exit(2) }
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	os.mkdir_all('/tmp') or { panic(err) }; os.chmod('/tmp', 0o1777) or { panic(err) }
	pid := C.fork()
	if pid == 0 {
		C.alarm(45)
		if C.setgroups(0, unsafe { nil }) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { C._exit(90) }
		wineserverdirectoryfixture.run('/tmp/wine-server-directory') or { eprintln('HWTEST FAIL wine-server-directory: ' + err.msg()); C._exit(91) }
		println('WINE SERVER DIRECTORY PASS private binding; busy lock; endpoint refusal; replacement; 1000 cycles')
		C._exit(0)
	}
	mut status := i32(0)
	mut waited := i32(-1)
	if pid > 0 {
		for {
			waited = C.waitpid(pid, &status, 0)
			if waited < 0 && C.errno == C.EINTR { continue }
			break
		}
	}
	if pid <= 0 || waited != pid || status != 0 { eprintln('HWTEST FAIL wine-server-directory: fixture child status ' + status.str()) }
	else { println('HWTEST PASS wine-server-directory fixture') }
	for { time.sleep(time.second) }
}
