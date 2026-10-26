// SPDX-License-Identifier: GPL-2.0-or-later
// Real account/session/package CLIs; no private audio or launch handlers.
module main

import os

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/reboot.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.open(&char, int, ...int) int
fn C.close(int) int
fn C.dup2(int, int) int
fn C.fork() int
fn C.execve(&char, &&char, &&char) int
fn C._exit(int)
fn C.getuid() int
fn C.geteuid() int
fn C.getgroups(int, &u32) int
fn C.waitpid(int, &i32, int) int
fn C.kill(int, int) int
fn C.usleep(u32) int
fn C.reboot(int) int
fn C.sync()

const data = '/home/alex/.local/share/vinix-apps/tone'

struct Ready {
	pid        int
	worker     int
	socket     string
	device     u64
	inode      u64
	generation u64
	manifest   string
}

fn require(ok bool, message string) ! {
	if !ok { return error(message) }
}

fn text(path string) string { return os.read_file(path) or { '' } }

fn child_start(argv []string, input string, capture string) !int {
	if input != '' { os.write_file('/tmp/command-input', input)! }
	pid := C.fork()
	if pid < 0 { return error('fork failed') }
	if pid == 0 {
		if input != '' {
			fd := C.open(c'/tmp/command-input', C.O_RDONLY)
			if fd < 0 { C._exit(124) }
			C.dup2(fd, 0)
		}
		if capture != '' {
			fd := C.open(capture.str, C.O_WRONLY | C.O_CREAT | C.O_TRUNC, 0o600)
			if fd < 0 { C._exit(124) }
			C.dup2(fd, 1)
			C.dup2(fd, 2)
		}
		for fd in 3 .. 64 { C.close(fd) }
		mut args := []&char{}
		for value in argv { args << value.str }
		args << &char(unsafe { nil })
		mut env := ['PATH=/usr/sbin:/usr/bin:/sbin:/bin',
			'HOME=' + if C.getuid() == 1000 { '/home/alex' } else { '/root' }]
		if os.getenv('XDG_RUNTIME_DIR') != '' {
			env << 'XDG_RUNTIME_DIR=' + os.getenv('XDG_RUNTIME_DIR')
		}
		mut cenv := []&char{}
		for value in env { cenv << value.str }
		cenv << &char(unsafe { nil })
		C.execve(args[0], &args[0], &cenv[0])
		C._exit(127)
	}
	return pid
}

fn wait(pid int) !int {
	for _ in 0 .. 900 {
		mut status := i32(0)
		got := C.waitpid(pid, &status, C.WNOHANG)
		if got == pid {
			return if status & 0x7f == 0 { (status >> 8) & 0xff } else { 128 + (status & 0x7f) }
		}
		if got < 0 && C.errno != C.EINTR { return error('waitpid failed for ${pid}') }
		C.usleep(100_000)
	}
	C.kill(pid, C.SIGKILL)
	mut status := i32(0)
	for {
		got := C.waitpid(pid, &status, 0)
		if got == pid || (got < 0 && C.errno != C.EINTR) { break }
	}
	return error('process ${pid} timed out')
}

fn command(args []string, input string) ! {
	pid := child_start(args, input, '/tmp/command-output')!
	status := wait(pid)!
	require(status == 0, '${args}: exit ${status}: ${text('/tmp/command-output')}')!
}

fn wait_file(path string) !string {
	for _ in 0 .. 600 {
		value := text(path)
		if value != '' { return value }
		C.usleep(100_000)
	}
	return error('timed out waiting for ${path}')
}

fn login() !int {
	require(os.args.len == 6 && C.getuid() == 1000 && C.geteuid() == 1000 && os.getenv('HOME') == '/home/alex', 'outer login identity changed')!
	mut groups := [32]u32{}
	count := C.getgroups(32, &groups[0])
	require(count > 0 && count <= 32 && u32(100) in groups[..count], 'outer login lacks ordinary users group')!
	println('AUDIO LOGIN uid=1000 home=/home/alex supplementary-users PASS')
	mut args := ['/usr/bin/vinix-package', 'run-args', os.args[2], '--', os.args[3], os.args[4]]
	if os.args[3] in ['tone', 'hold'] { args << os.args[5] }
	pid := child_start(args, '', '')!
	os.write_file('/home/alex/Documents/' + os.args[4] + '.outer', pid.str() + '\n')!
	return wait(pid)
}

fn main() {
	if os.args.len == 2 && os.args[1] == 'isolated-forgery' {
		isolated_forgery() or {
			eprintln(err)
			exit(89)
		}
		return
	}
	if os.args.len == 2 && os.args[1] == 'alexhold' {
		if C.getuid() != 1000 || C.getgroups(0, unsafe { nil }) == 0 { exit(89) }
		os.write_file('/home/alex/seat.ready', 'ready\n') or { exit(89) }
		wait_file('/home/alex/seat.go') or { exit(89) }
		return
	}
	if os.args.len > 1 && os.args[1] == 'login' {
		exit(login() or {
			eprintln('AUDIO LOGIN FAIL: ${err}')
			89
		})
	}
	if os.args.len == 2 && os.args[1] == 'samhold' {
		if C.getuid() != 1001 { exit(89) }
		os.write_file('/home/sam/seat.ready', 'ready\n') or { exit(89) }
		wait_file('/home/sam/seat.go') or { exit(89) }
		return
	}
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 {
		C.dup2(fd, 1)
		C.dup2(fd, 2)
		if fd > 2 { C.close(fd) }
	}
	name := text('/etc/hwtest-scenario').trim_space()
	println('HWTEST START ${name}')
	setup() or {
		eprintln('HWTEST FAIL ${name}: ${err}')
		shutdown()
		return
	}
	if name == 'packages-audio-basic' {
		basic() or {
			eprintln('HWTEST FAIL ${name}: ${err}')
			shutdown()
			return
		}
	} else if name == 'packages-audio-lifecycle' {
		lifecycle() or {
			eprintln('HWTEST FAIL ${name}: ${err}')
			shutdown()
			return
		}
	} else if name == 'packages-audio-seat' {
		seat() or {
			eprintln('HWTEST FAIL ${name}: ${err}')
			shutdown()
			return
		}
	} else {
		eprintln('HWTEST FAIL unknown audio scenario')
		shutdown()
		return
	}
	println('HWTEST PASS ${name}')
	shutdown()
}

fn shutdown() {
	C.usleep(300_000)
	C.sync()
	C.reboot(0x4321fedc)
	for { C.usleep(1_000_000) }
}
