// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import time

#include <fcntl.h>
#include <unistd.h>
#include <sys/wait.h>
#include <signal.h>

fn C.dup2(int, int) int
fn C.fork() int
fn C.sleep(u32) u32
fn C._exit(int)
fn C.kill(int, int) int
fn wait_for(child int, status &i32, flags int) !int {
	for {
		result := C.waitpid(child, status, flags)
		if result >= 0 { return result }
		if C.errno != C.EINTR { return error('waitpid-error') }
	}
}

fn check() ! {
	mut descriptors := [2]i32{}
	if C.pipe(&descriptors[0]) != 0 { return error('pipe-create') }
	defer { C.close(descriptors[0]); C.close(descriptors[1]) }
	flags := C.fcntl(descriptors[0], C.F_GETFL)
	if flags < 0 || C.fcntl(descriptors[0], C.F_SETFL, flags | C.O_NONBLOCK) < 0 {
		return error('nonblocking-flags')
	}
	readback := C.fcntl(descriptors[0], C.F_GETFL)
	if readback < 0 || readback & C.O_NONBLOCK == 0 { return error('nonblocking-readback') }
	mut byte := u8(0)
	count := C.read(descriptors[0], &byte, 1)
	error_number := C.errno
	println('HWTEST INFO empty pipe read=' + count.str() + ' errno=' + error_number.str())
	if count != -1 || error_number != C.EAGAIN { return error('empty-read-result') }
	child := C.fork()
	if child == 0 { C.sleep(20); C._exit(0) }
	if child < 0 { return error('wait-fork') }
	mut status := i32(0)
	waited := wait_for(child, &status, C.WNOHANG)!
	println('HWTEST INFO raw child WNOHANG=' + waited.str())
	if waited != 0 { return error('wait-nohang') }
	if C.kill(child, C.SIGKILL) != 0 { return error('wait-kill') }
	reaped := wait_for(child, &status, 0)!
	println('HWTEST INFO raw child wait=' + reaped.str() + ' status=' + status.str())
	if reaped != child || status & 0x7f != C.SIGKILL { return error('wait-reap') }
	// Exercise the V process and redirected-pipe path used by Wine diagnostics.
	mut process := os.new_process('/sbin/init')
	mut retired := false
	defer {
		if !retired && process.is_alive() { process.signal_kill(); process.wait() }
		process.close()
	}
	process.set_args(['--probe-child'])
	process.set_redirect_stdio_merged()
	process.run()
	if process.pid <= 0 { return error('process-start') }
	C.close(process.stdio_fd[0])
	process.stdio_fd[0] = -1
	fd := process.stdio_fd[1]
	process_flags := C.fcntl(fd, C.F_GETFL)
	if process_flags < 0 || C.fcntl(fd, C.F_SETFL, process_flags | C.O_NONBLOCK) < 0 {
		return error('process-nonblocking')
	}
	if C.read(fd, &byte, 1) != -1 || C.errno != C.EAGAIN { return error('process-empty-read') }
	mut process_status := i32(0)
	if wait_for(process.pid, &process_status, C.WNOHANG)! != 0 { return error('process-nohang') }
	process.signal_kill()
	if wait_for(process.pid, &process_status, 0)! != process.pid || process_status & 0x7f != C.SIGKILL {
		return error('process-reap')
	}
	retired = true
	process.status = .exited
	println('HWTEST INFO redirected process raw status=' + process_status.str())
	println('HWTEST PASS Wine-process-primitives')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--probe-child' { C.sleep(20); C._exit(0) }
	console := C.open(c'/dev/com1', C.O_WRONLY)
	if console >= 0 { C.dup2(console, 1); C.dup2(console, 2); if console > 2 { C.close(console) } }
	check() or { eprintln('HWTEST FAIL Wine-process-primitives: ' + err.msg()) }
	for { time.sleep(time.second) }
}
