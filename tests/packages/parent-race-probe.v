// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import time

#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>
#include <fcntl.h>
#include <grp.h>
fn C.prctl(i32, ...voidptr) i32
fn C.fork() i32
fn C.getpid() i32
fn C.getppid() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.pipe(&i32) i32
fn C.read(i32, voidptr, u64) i64
fn C.write(i32, voidptr, u64) i64
fn C.close(i32) i32
fn C.open(&char, i32, ...i32) i32
fn C.dup2(i32, i32) i32
fn C.kill(i32, i32) i32
fn C.pause() i32
fn C.alarm(u32) u32
fn C.setgroups(u64, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.syscall(i64, ...) i64
fn C._exit(i32)

fn word(fd i32, sending bool, value &i32) bool {
	for {
		count := if sending { C.write(fd, value, 4) } else { C.read(fd, value, 4) }
		if count < 0 && C.errno == C.EINTR { continue }
		return count == 4
	}
}
fn send(fd i32, value i32) bool { mut payload := value; return word(fd, true, unsafe { &payload }) }
fn receive(fd i32) !i32 { mut value := i32(0); if !word(fd, false, unsafe { &value }) { return error('pipe receive failed') }; return value }
fn control(operation i32, target i32, mode i32) i32 {
	return C.prctl(0x56585041, voidptr(operation), voidptr(target), voidptr(mode), voidptr(0))
}
fn wait_exact(pid i32, wanted i32) bool {
	mut status := i32(0)
	for {
		answer := C.waitpid(pid, &status, 0)
		if answer < 0 && C.errno == C.EINTR { continue }
		return answer == pid && status == wanted
	}
}

fn scenario(mode i32) ! {
	mut command := [i32(-1), -1]!
	mut reply := [i32(-1), -1]!
	mut worker_gate := [i32(-1), -1]!
	if C.pipe(&command[0]) != 0 { return error('command pipe failed') }
	defer { C.close(command[0]); C.close(command[1]) }
	if C.pipe(&reply[0]) != 0 { return error('reply pipe failed') }
	defer { C.close(reply[0]); C.close(reply[1]) }
	if C.pipe(&worker_gate[0]) != 0 { return error('worker pipe failed') }
	defer { C.close(worker_gate[0]); C.close(worker_gate[1]) }
	parent := C.fork()
	if parent < 0 { return error('parent fork failed') }
	if parent == 0 {
		C.close(command[1]); C.close(reply[0])
		C.close(worker_gate[1])
		C.alarm(25)
		if C.setgroups(0, unsafe { nil }) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0
			|| C.prctl(36, voidptr(1), voidptr(0), voidptr(0), voidptr(0)) != 0 { C._exit(80) }
		target := C.fork()
		if target < 0 { C._exit(81) }
		if target == 0 {
			C.alarm(25)
			if control(2, C.getpid(), mode) != -1 || C.errno != C.EPERM { C._exit(98) }
			if !send(reply[1], C.getpid()) { C._exit(82) }
			if mode == 1 {
				mut start := i32(0)
				if !word(command[0], false, unsafe { &start }) || start != 11 { C._exit(83) }
				child := i32(C.syscall(C.SYS_clone, u64(0x8011), u64(0), u64(0), u64(0), u64(0)))
				if child < 0 { C._exit(84) }
				if child == 0 { C._exit(if C.getppid() == 1 { 23 } else { 91 }) }
				if !send(reply[1], child) { C._exit(85) }
				C._exit(37)
			}
			child := C.fork()
			if child < 0 { C._exit(86) }
			if child == 0 {
				mut release := i32(0)
				if !word(worker_gate[0], false, unsafe { &release }) || release != 22 { C._exit(87) }
				C._exit(if C.getppid() == 1 { 23 } else { 92 })
			}
			if !send(reply[1], child) { C._exit(88) }
			mut start := i32(0)
			if !word(command[0], false, unsafe { &start }) || start != 11 { C._exit(89) }
			C._exit(37)
		}
		C.close(command[0]); C.close(reply[1])
		C.close(worker_gate[0])
		for { C.pause() }
	}
	C.close(command[0]); command[0] = -1
	C.close(reply[1]); reply[1] = -1
	C.close(worker_gate[0]); worker_gate[0] = -1
	target := receive(reply[0])!
	mut child := i32(0)
	if mode == 2 { child = receive(reply[0])! }
	if control(1, target, mode) != 0 || !send(command[1], 11) { return error('gate arm failed') }
	deadline := time.sys_mono_now() + 10 * time.second
	for {
		phase := control(2, target, mode)
		if phase == 1 { break }
		if phase != 0 || time.sys_mono_now() > deadline { return error('gate did not pause publication') }
		time.sleep(time.millisecond)
	}
	// The selected parent is completely retired before publication resumes.
	if C.kill(parent, 15) != 0 || !wait_exact(parent, 15) { return error('selected parent retirement failed') }
	if control(3, target, mode) != 0 { return error('gate release failed') }
	if mode == 1 { child = receive(reply[0])! }
	if !wait_exact(target, 37 << 8) { return error('target exit status differs') }
	if mode == 2 && !send(worker_gate[1], 22) { return error('worker release failed') }
	if !wait_exact(child, 23 << 8) { return error(if mode == 1 { 'clone child wait ownership' } else { 'adopt child wait ownership' }) }
	mut status := i32(0)
	if C.waitpid(-1, &status, C.WNOHANG) != -1 || C.errno != C.ECHILD { return error('unexpected remaining child') }
	println(if mode == 1 { 'PARENT RACE PASS clone: parent retired before publication; exact PPID/status/wait ownership' }
		else { 'PARENT RACE PASS adopt: adopter retired before publication; exact PPID/status/wait ownership' })
}
fn main() {
	if C.getpid() != 1 { eprintln('requires fixture PID 1'); exit(2) }
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	for mode in [i32(1), 2]! {
		scenario(mode) or { eprintln('HWTEST FAIL parent-race: ' + err.msg()); for { time.sleep(time.second) } }
	}
	println('HWTEST PASS parent-race deterministic clone and adoption')
	for { time.sleep(time.second) }
}
