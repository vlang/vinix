// SPDX-License-Identifier: GPL-2.0-or-later
module appinitfixture

#include <fcntl.h>
#include <grp.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <unistd.h>

fn C.open(&char, i32, ...) i32
fn C.read(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.puts(&char) i32
fn C.printf(&char, ...) i32
fn C.fflush(voidptr) i32
fn C.setenv(&char, &char, i32) i32
fn C.mkdir(&char, u32) i32
fn C.chmod(&char, u32) i32
fn C.chown(&char, u32, u32) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.fork() i32
fn C.execv(&char, &&char) i32
fn C._exit(i32)
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) bool
fn C.WEXITSTATUS(i32) i32
fn C.pause() i32

@[export: 'main']
pub fn run() i32 {
	unsafe {
		C.setenv(c'PATH', c'/bin:/sbin:/usr/bin:/usr/sbin', 1)
		// Match a login session's ordinary application environment. A bare
		// PID 1 inherits neither HOME nor a user runtime directory.
		C.setenv(c'HOME', c'/root', 1)
		C.setenv(c'USER', c'root', 1)
		C.setenv(c'LOGNAME', c'root', 1)
		C.setenv(c'LANG', c'C.UTF-8', 1)
		C.mkdir(c'/run', u32(0o755))
		C.mkdir(c'/run/user', u32(0o755))
		C.mkdir(c'/run/user/0', u32(0o700))
		C.setenv(c'XDG_RUNTIME_DIR', c'/run/user/0', 1)
		mut uid := u32(0)
		credentials_fd := C.open(c'/etc/linux-compat-uid', C.O_RDONLY)
		if credentials_fd >= 0 {
			mut credentials := [8]u8{}
			length := C.read(credentials_fd, &credentials[0], sizeof(credentials))
			C.close(credentials_fd)
			if length == 5 && credentials[0] == `1` && credentials[1] == `0`
				&& credentials[2] == `0` && credentials[3] == `0` && credentials[4] == `\n` {
				uid = 1000
			} else if length != 2 || credentials[0] != `0` || credentials[1] != `\n` {
				C.puts(c'LINUX APPLICATIONS FAIL: invalid credentials')
				return 1
			}
		}
		if uid == 1000 {
			C.mkdir(c'/tmp', u32(0o1777))
			C.mkdir(c'/home', u32(0o755))
			C.mkdir(c'/home/compat', u32(0o700))
			C.mkdir(c'/run/user/1000', u32(0o700))
			if C.chmod(c'/tmp', u32(0o1777)) != 0 || C.chown(c'/home/compat', uid, uid) != 0
				|| C.chown(c'/run/user/1000', uid, uid) != 0 {
				C.puts(c'LINUX APPLICATIONS FAIL: user directories')
				return 1
			}
			C.setenv(c'HOME', c'/home/compat', 1)
			C.setenv(c'USER', c'compat', 1)
			C.setenv(c'LOGNAME', c'compat', 1)
			C.setenv(c'XDG_RUNTIME_DIR', c'/run/user/1000', 1)
		}
		mut options := [1024]char{}
		fd := C.open(c'/etc/linux-compat-options', C.O_RDONLY)
		if fd < 0 {
			C.puts(c'LINUX APPLICATIONS FAIL: missing options')
			return 1
		}
		n := C.read(fd, &options[0], sizeof(options) - 1)
		C.close(fd)
		if n <= 0 {
			C.puts(c'LINUX APPLICATIONS FAIL: empty options')
			return 1
		}
		options[n] = 0
		// Three fixed arguments, up to five controller options (including
		// command timeout and a package data device), then the terminating NULL.
		mut arguments := [9]&char{}
		arguments[0] = c'/usr/bin/linux-compat-workloads'
		arguments[1] = c'--work=/tmp/linux-compat-evidence'
		arguments[2] = c'--runtime-probe=/usr/share/linux-compat/runtime'
		// Consume every bounded NUL-terminated controller option. In
		// particular, retain the libc selection alongside the execution path.
		mut index := usize(0)
		mut argc := 3
		for index < usize(n) {
			if argc >= arguments.len - 1 || options[index] == 0 {
				C.puts(c'LINUX APPLICATIONS FAIL: invalid options')
				return 1
			}
			arguments[argc] = &options[index]
			argc++
			for index < usize(n) && options[index] != 0 { index++ }
			if index == usize(n) {
				C.puts(c'LINUX APPLICATIONS FAIL: unterminated options')
				return 1
			}
			index++
		}
		child := C.fork()
		if child == 0 {
			if uid == 1000 && (C.setgroups(0, nil) != 0 || C.setgid(uid) != 0 || C.setuid(uid) != 0) {
				C.puts(c'LINUX APPLICATIONS FAIL: credential transition')
				C._exit(126)
			}
			C.execv(arguments[0], &arguments[0])
			C._exit(127)
		}
		mut status := i32(0)
		passed := child > 0 && C.waitpid(child, &status, 0) == child && C.WIFEXITED(status) && C.WEXITSTATUS(status) == 0
		report := C.open(c'/tmp/linux-compat-evidence/report.json', C.O_RDONLY)
		if report < 0 {
			C.puts(c'LINUX APPLICATIONS FAIL: missing report')
			return 1
		}
		C.puts(c'LINUX APPLICATION REPORT BEGIN')
		mut buffer := [4096]char{}
		for {
			size := C.read(report, &buffer[0], sizeof(buffer) - 1)
			if size < 0 {
				C.close(report)
				return 1
			}
			if size == 0 { break }
			buffer[size] = 0
			C.printf(c'%s', &buffer[0])
		}
		C.close(report)
		C.puts(c'LINUX APPLICATION REPORT END')
		if !passed {
			C.puts(c'LINUX APPLICATIONS FAIL: workload verdict')
			C.fflush(nil)
			return 1
		}
		C.puts(c'LINUX APPLICATIONS: PASS')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
