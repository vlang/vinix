// SPDX-License-Identifier: GPL-2.0-or-later
// PID 1 keeps the fixture's SIGALRM effective by running it as an ordinary child.
module main

#include <errno.h>
#include <fcntl.h>
#include <sys/reboot.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.open(&char, i32, ...) i32
fn C.dup2(i32, i32) i32
fn C.close(i32) i32
fn C.getpid() i32
fn C.fork() i32
fn C.execve(&char, &&char, &&char) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) bool
fn C.WEXITSTATUS(i32) i32
fn C.write(i32, voidptr, usize) isize
fn C.sync()
fn C.reboot(i32) i32
fn C._exit(i32)

fn say(line string) {
	mut offset := 0
	for offset < line.len {
		written := unsafe { C.write(2, line.str + offset, usize(line.len - offset)) }
		if written == -1 && C.errno == C.EINTR { continue }
		if written <= 0 { return }
		offset += int(written)
	}
}

fn power_off() {
	C.sync()
	C.reboot(C.RB_POWER_OFF)
	say('PEER-LOGIN INIT FAIL poweroff returned\n')
	C._exit(112)
}

fn fail(reason string) {
	say('PEER-LOGIN INIT FAIL ' + reason + '\n')
	power_off()
}

fn main() {
	if C.getpid() != 1 {
		say('PEER-LOGIN INIT FAIL requires PID 1\n')
		C._exit(111)
		return
	}
	$if amd64 {
		serial := C.open(c'/dev/com1', C.O_WRONLY)
		if serial < 0 { fail('open serial'); return }
		if C.dup2(serial, 1) < 0 || C.dup2(serial, 2) < 0 {
			if serial > 2 { C.close(serial) }
			fail('redirect serial'); return
		}
		if serial > 2 { C.close(serial) }
	}
	// Build both null-terminated vectors before fork; the child calls libc only.
	mut argv := [&char(c'/usr/bin/peer-login'), &char(unsafe { nil })]!
	mut envp := [&char(unsafe { nil })]!
	child := C.fork()
	if child < 0 { fail('fork'); return }
	if child == 0 {
		unsafe { C.execve(c'/usr/bin/peer-login', &argv[0], &envp[0]) }
		message := c'PEER-LOGIN INIT FAIL execve\n'
		C.write(2, message, 28)
		C._exit(127)
		return
	}
	mut status := i32(0)
	for {
		waited := C.waitpid(child, &status, 0)
		if waited == -1 && C.errno == C.EINTR { continue }
		if waited != child { fail('waitpid'); return }
		break
	}
	if !C.WIFEXITED(status) || C.WEXITSTATUS(status) != 0 {
		fail('fixture raw status=' + status.str()); return
	}
	say('PEER-LOGIN INIT EXIT status=0\n')
	power_off()
}
