// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module guestfixture

#include <fcntl.h>
#include <sched.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.access(&char, i32) i32
fn C.pipe(&i32) i32
fn C.fork() i32
fn C.dup2(i32, i32) i32
fn C.close(i32) i32
fn C.execv(&char, &&char) i32
fn C._exit(i32)
fn C.read(i32, voidptr, usize) isize
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) bool
fn C.WEXITSTATUS(i32) i32
fn C.strncmp(&char, &char, usize) i32
fn C.strstr(&char, &char) &char
fn C.strlen(&char) usize
fn C.printf(&char, ...) i32
fn C.fflush(voidptr) i32
fn C.puts(&char) i32
fn C.pause() i32
fn C.unshare(i32) i32
fn C.alarm(u32) u32

fn command(label &char, args [8]&char, expected &char, contains bool, audit bool) i32 {
	unsafe {
		mut pipe := [2]i32{}
		if C.pipe(&pipe[0]) != 0 { return 1 }
		pid := C.fork()
		if pid == 0 {
			C.close(pipe[0])
			C.dup2(pipe[1], 1)
			C.dup2(pipe[1], 2)
			C.close(pipe[1])
			C.execv(args[0], &args[0])
			C._exit(127)
		}
		C.close(pipe[1])
		if pid < 0 { C.close(pipe[0]); return 1 }
		mut output := [4096]u8{}
		mut length := 0
		for length < output.len - 1 {
			n := C.read(pipe[0], &output[length], usize(output.len - length - 1))
			if n <= 0 { break }
			length += int(n)
		}
		C.close(pipe[0])
		mut status := [1]i32{}
		C.waitpid(pid, &status[0], 0)
		C.printf(c'IDENTITY %s: %.*s\n', label, length, &char(&output[0]))
		C.fflush(nil)
		text := &char(&output[0])
		matches := if contains { C.strstr(text, expected) != nil } else { C.strncmp(text, expected, C.strlen(expected)) == 0 }
		if !C.WIFEXITED(status[0]) || C.WEXITSTATUS(status[0]) != 0 || !matches {
			if !audit { C.printf(c'IDENTITY MISMATCH: %s\n', label); C.fflush(nil) }
			return 1
		}
		return 0
	}
}

fn check_host(audit bool) i32 {
	mut failures := i32(0)
	unsafe {
		failures += command(c'uname -s', [c'/bin/uname', c'-s', nil, nil, nil, nil, nil, nil]!, c'Vinix\n', false, audit)
		failures += command(c'uname -o', [c'/bin/uname', c'-o', nil, nil, nil, nil, nil, nil]!, c'Vinix\n', false, audit)
		failures += command(c'uname -r', [c'/bin/uname', c'-r', nil, nil, nil, nil, nil, nil]!, c'0.1.0\n', false, audit)
		failures += command(c'uname -a', [c'/usr/bin/uname', c'-a', nil, nil, nil, nil, nil, nil]!, c'Vinix ', false, audit)
		failures += command(c'BusyBox uname -s', [c'/bin/busybox', c'uname', c'-s', nil, nil, nil, nil, nil]!, c'Vinix\n', false, audit)
		// The imported applet's -o describes its build platform. The ordinary
		// uname command above supplies Vinix's host operating-system label.
		failures += command(c'BusyBox build label (-o)', [c'/bin/busybox', c'uname', c'-o', nil, nil, nil, nil, nil]!, c'Linux\n', false, audit)
		failures += command(c'sysctl kernel.ostype', [c'/bin/busybox', c'sysctl', c'-n', c'kernel.ostype', nil, nil, nil, nil]!, c'Vinix\n', false, audit)
		failures += command(c'sysctl kernel.osrelease', [c'/bin/busybox', c'sysctl', c'-n', c'kernel.osrelease', nil, nil, nil, nil]!, c'0.1.0\n', false, audit)
		failures += command(c'/proc/version', [c'/bin/busybox', c'cat', c'/proc/version', nil, nil, nil, nil, nil]!, c'Vinix version 0.1.0 ', false, audit)
		for path in [&char(c'/etc/os-release'), &char(c'/usr/lib/os-release')]! {
			failures += command(path, [c'/bin/busybox', c'cat', path, nil, nil, nil, nil, nil]!, c'ID=vinix\n', true, audit)
		}
		failures += command(c'/etc/lsb-release', [c'/bin/busybox', c'cat', c'/etc/lsb-release', nil, nil, nil, nil, nil]!, c'DISTRIB_ID=Vinix\n', false, audit)
		failures += command(c'login issue', [c'/bin/busybox', c'cat', c'/etc/issue', nil, nil, nil, nil, nil]!, c'Welcome to Vinix\n', false, audit)
		failures += command(c'login motd', [c'/bin/busybox', c'cat', c'/etc/motd', nil, nil, nil, nil, nil]!, c'Welcome to Vinix!\n', false, audit)
		machine := $if arm64 { &char(c'aarch64\n') } $else { &char(c'x86_64\n') }
		failures += command(c'arch', [c'/bin/busybox', c'arch', nil, nil, nil, nil, nil, nil]!, machine, false, audit)
		failures += command(c'hostname', [c'/bin/busybox', c'hostname', nil, nil, nil, nil, nil, nil]!, c'vinix\n', false, audit)
	}
	return failures
}

fn check_container() i32 {
	unsafe {
		pid := C.fork()
		if pid == 0 {
			C.alarm(10)
			if C.unshare(C.CLONE_NEWUTS) != 0 { C._exit(1) }
			mut failed := i32(0)
			failed += command(c'container uname -s', [c'/bin/uname', c'-s', nil, nil, nil, nil, nil, nil]!, c'Linux\n', false, false)
			failed += command(c'container uname -o', [c'/bin/uname', c'-o', nil, nil, nil, nil, nil, nil]!, c'Linux\n', false, false)
			failed += command(c'container uname -r', [c'/bin/uname', c'-r', nil, nil, nil, nil, nil, nil]!, c'5.15.0-vinix\n', false, false)
			failed += command(c'container sysctl ostype', [c'/bin/busybox', c'sysctl', c'-n', c'kernel.ostype', nil, nil, nil, nil]!, c'Linux\n', false, false)
			failed += command(c'container sysctl osrelease', [c'/bin/busybox', c'sysctl', c'-n', c'kernel.osrelease', nil, nil, nil, nil]!, c'5.15.0-vinix\n', false, false)
			failed += command(c'container /proc/version', [c'/bin/busybox', c'cat', c'/proc/version', nil, nil, nil, nil, nil]!, c'Linux version 5.15.0-vinix ', false, false)
			C._exit(if failed == 0 { 0 } else { 1 })
		}
		if pid < 0 { return 1 }
		mut status := [1]i32{}
		C.waitpid(pid, &status[0], 0)
		return if C.WIFEXITED(status[0]) && C.WEXITSTATUS(status[0]) == 0 { 0 } else { 1 }
	}
}

@[export: 'main']
pub fn run() i32 {
	audit := C.access(c'/etc/identity-audit', 0) == 0
	mut failed := check_host(audit)
	if audit {
		C.puts(c'USERLAND IDENTITY AUDIT DONE')
	} else {
		if failed == 0 { C.puts(c'USERLAND HOST IDENTITY PASS'); C.fflush(unsafe { nil }) }
		failed += check_container()
		C.puts(if failed == 0 { c'USERLAND IDENTITY PASS' } else { c'USERLAND IDENTITY FAIL' })
	}
	C.fflush(unsafe { nil })
	for { C.pause() }
	return 0
}
