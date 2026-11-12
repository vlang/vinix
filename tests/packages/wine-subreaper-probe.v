// SPDX-License-Identifier: GPL-2.0-or-later
// Native prerequisite only: not a descendant-publication race qualification.
module main

import os
import time

#include <sys/prctl.h>
#include <sys/wait.h>
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>
#include <grp.h>
fn C.setgroups(uint, voidptr) int
fn C.setgid(u32) int
fn C.setuid(u32) int
fn C.dup2(int, int) int
fn C.prctl(i32, ...voidptr) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.pipe(&i32) i32
fn C.read(i32, voidptr, uint) i64
fn C.write(i32, voidptr, uint) i64
fn C.close(i32) i32
fn C.open(&char, i32, ...i32) i32
fn C.flock(i32, i32) i32
fn C.setsid() i32
fn C.getpid() i32
fn C.getppid() i32
fn C.kill(i32, i32) i32
fn C.pause() i32
fn C._exit(int)
fn C.alarm(u32) u32

fn probe(directory string, subreaper bool) ! {
	// Bound even the blocking initial wait and pipe operations. On failure,
	// closing the holder's sole gate writer lets the worker retire on EOF.
	C.alarm(30)
	defer { C.alarm(0) }
	if !directory.starts_with('/') || os.exists(directory) { return error('fresh absolute external state directory required') }
	os.mkdir(directory)!
	os.write_file(directory + '/lease', '')!
	lease := C.open((directory + '/lease').str, C.O_RDONLY | C.O_CLOEXEC)
	if lease < 0 { return error('open lease failed') }
	defer { C.close(lease) }
	if C.flock(lease, C.LOCK_SH | C.LOCK_NB) != 0 { return error('shared lease failed') }
	if os.getpid() == 1 || os.geteuid() != 1000 { return error('probe requires non-init uid 1000') }
	if C.prctl(36, voidptr(if subreaper { 1 } else { 0 }), voidptr(0), voidptr(0), voidptr(0)) != 0 { return error('SET subreaper failed') }
	mut enabled := i32(0)
	if C.prctl(37, &enabled, voidptr(0), voidptr(0), voidptr(0)) != 0 || enabled != if subreaper { 1 } else { 0 } { return error('GET subreaper failed') }
	mut gate := [i32(-1), -1]!
	if C.pipe(&gate[0]) != 0 { return error('gate pipe failed') }
	defer { C.close(gate[0]); C.close(gate[1]) }
	client := C.fork()
	if client < 0 { return error('client fork failed') }
	if client == 0 {
		// The holder owns the lease; descendants must not keep it accidentally.
		C.close(lease)
		C.close(gate[1])
		worker := C.fork()
		if worker < 0 { C._exit(90) }
		if worker > 0 { C._exit(37) }
		if C.setsid() < 0 { C._exit(91) }
		mut byte := u8(0)
		if C.read(gate[0], &byte, 1) != 1 || byte != 42 { C._exit(92) }
		C._exit(23)
	}
	mut status := i32(0)
	if C.waitpid(client, &status, 0) != client || status != 37 << 8 { return error('initial client status differs') }
	// The worker cannot exit until released. ECHILD here would lose adoption.
	if C.waitpid(-1, &status, C.WNOHANG) != 0 { return error('live adopted descendant missing') }
	other := C.open((directory + '/lease').str, C.O_RDONLY | C.O_CLOEXEC)
	if other < 0 { return error('independent lease open failed') }
	defer { C.close(other) }
	if C.flock(other, C.LOCK_EX | C.LOCK_NB) == 0 { return error('lease became free after client exit') }
	byte := u8(42)
	if C.write(gate[1], &byte, 1) != 1 { return error('worker release failed') }
	deadline := time.sys_mono_now() + 10 * time.second
	for {
		retired := C.waitpid(-1, &status, C.WNOHANG)
		if retired > 0 {
			if status != 23 << 8 { return error('adopted worker status differs') }
			break
		}
		if retired < 0 || time.sys_mono_now() > deadline { return error('adopted worker retirement failed') }
		time.sleep(time.millisecond)
	}
	if C.waitpid(-1, &status, C.WNOHANG) != -1 || C.errno != C.ECHILD { return error('descendants remain') }
	if C.flock(lease, C.LOCK_UN) != 0 || C.flock(other, C.LOCK_EX | C.LOCK_NB) != 0 { return error('retired lease release failed') }
	println('WINE SUBREAPER PREREQUISITE PASS client=37 adopted-session-worker=23 live-lease-busy retired-lease-free')
}

fn main() {
	if os.getpid() == 1 {
		console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
		fd := C.open(console.str, C.O_WRONLY)
		if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
		guest() or { eprintln('HWTEST FAIL subreaper: ' + err.msg()) }
		for { time.sleep(time.second) }
	}
	if os.args.len !in [2, 3] { eprintln('usage: wine-subreaper-probe FRESH_EXTERNAL_DIRECTORY [--without-subreaper]'); exit(2) }
	if os.args.len == 3 && os.args[2] != '--without-subreaper' { exit(2) }
	probe(os.args[1], os.args.len == 2) or { eprintln(err); exit(1) }
}

fn guest() ! {
	os.mkdir_all('/tmp')!; os.chmod('/tmp', 0o1777)!
	for disabled in [false, true]! {
		pid := C.fork()
		if pid < 0 { return error('fixture fork failed') }
		if pid == 0 {
			if C.setgroups(0, unsafe { nil }) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { C._exit(80) }
			probe(if disabled { '/tmp/control' } else { '/tmp/positive' }, !disabled) or {
				if disabled && err.msg() == 'live adopted descendant missing' { C._exit(42) }
				eprintln(err); C._exit(81)
			}
			C._exit(0)
		}
		mut status := i32(0)
		if C.waitpid(pid, &status, 0) != pid || status != if disabled { 42 << 8 } else { 0 } { return error('fixture status differs: ' + status.str()) }
	}
	pid := C.fork()
	if pid < 0 { return error('nested fixture fork failed') }
	if pid == 0 {
		if C.setgroups(0, unsafe { nil }) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { C._exit(80) }
		nested() or { eprintln(err); C._exit(81) }
		C._exit(0)
	}
	mut status := i32(0)
	if C.waitpid(pid, &status, 0) != pid || status != 0 { return error('nested fixture failed status=' + status.str()) }
	println('HWTEST PASS subreaper prerequisite positive and disabled control')
}

// Fixed-size pipe handshakes establish both adoption points without sleeps.
fn transfer_byte(fd i32, sending bool, wanted u8) bool {
	mut value := wanted
	for {
		count := if sending { C.write(fd, &value, 1) } else { C.read(fd, &value, 1) }
		if count < 0 && C.errno == C.EINTR { continue }
		return count == 1 && value == wanted
	}
}

fn nested() ! {
	C.alarm(30)
	defer { C.alarm(0) }
	if C.prctl(36, voidptr(1), voidptr(0), voidptr(0), voidptr(0)) != 0 { return error('outer subreaper setup failed') }
	outer := C.getpid()
	mut command := [i32(-1), -1]!
	mut reply := [i32(-1), -1]!
	if C.pipe(&command[0]) != 0 { return error('nested command pipe failed') }
	defer { C.close(command[0]); C.close(command[1]) }
	if C.pipe(&reply[0]) != 0 { return error('nested reply pipe failed') }
	defer { C.close(reply[0]); C.close(reply[1]) }
	inner := C.fork()
	if inner < 0 { return error('inner subreaper fork failed') }
	if inner == 0 {
		C.alarm(20)
		C.close(command[1]); C.close(reply[0])
		if C.prctl(36, voidptr(1), voidptr(0), voidptr(0), voidptr(0)) != 0 { C._exit(90) }
		owner := C.getpid()
		client := C.fork()
		if client < 0 { C._exit(91) }
		if client == 0 {
			worker := C.fork()
			if worker < 0 { C._exit(92) }
			if worker > 0 { C._exit(37) }
			if C.setsid() < 0 { C._exit(93) }
			if !transfer_byte(command[0], false, 11) || C.getppid() != owner
				|| !transfer_byte(reply[1], true, 12) { C._exit(94) }
			if !transfer_byte(command[0], false, 21) || C.getppid() != outer
				|| !transfer_byte(reply[1], true, 22) { C._exit(95) }
			C._exit(23)
		}
		mut status := i32(0)
		if C.waitpid(client, &status, 0) != client || status != 37 << 8 { C._exit(96) }
		if !transfer_byte(reply[1], true, 10) { C._exit(97) }
		// The outer fixture kills this adopter only after its worker confirms PPID.
		for { C.pause() }
	}
	C.close(command[0]); command[0] = -1
	C.close(reply[1]); reply[1] = -1
	if !transfer_byte(reply[0], false, 10) || !transfer_byte(command[1], true, 11)
		|| !transfer_byte(reply[0], false, 12) { return error('nearest subreaper adoption failed') }
	if C.kill(inner, 15) != 0 { return error('inner subreaper termination failed') }
	mut status := i32(0)
	if C.waitpid(inner, &status, 0) != inner || status != 15 { return error('inner subreaper signal status differs') }
	if !transfer_byte(command[1], true, 21) || !transfer_byte(reply[0], false, 22) { return error('outer subreaper transfer failed') }
	worker := C.waitpid(-1, &status, 0)
	if worker <= 0 || status != 23 << 8 { return error('transferred worker status differs') }
	if C.waitpid(-1, &status, C.WNOHANG) != -1 || C.errno != C.ECHILD { return error('nested descendants remain') }
	println('WINE SUBREAPER TRANSFER PASS nearest-adopter confirmed; adopter signal death; outer adoption confirmed; worker=23; ECHILD')
}
