// SPDX-License-Identifier: GPL-2.0-or-later
module appinitfixture

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.open(&char, i32, ...) i32
fn C.read(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.puts(&char) i32
fn C.printf(&char, ...) i32
fn C.fflush(voidptr) i32
fn C.setenv(&char, &char, i32) i32
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
		mut arguments := [8]&char{}
		arguments[0] = c'/usr/bin/linux-compat-workloads'
		arguments[1] = c'--work=/tmp/linux-compat-evidence'
		arguments[2] = &options[0]
		arguments[3] = c'--runtime-probe=/usr/share/linux-compat/runtime'
		// The execution-path option is a second NUL-terminated string.
		mut index := usize(0)
		for index < usize(n) && options[index] != 0 { index++ }
		if index + 1 < usize(n) { arguments[4] = &options[index + 1] }
		child := C.fork()
		if child == 0 {
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
