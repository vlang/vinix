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
fn C.prctl(int, ...voidptr) int
fn C.fork() int
fn C.waitpid(int, &i32, int) int
fn C.pipe(&int) int
fn C.read(int, voidptr, usize) isize
fn C.write(int, voidptr, usize) isize
fn C.close(int) int
fn C.open(&char, int, ...int) int
fn C.flock(int, int) int
fn C.setsid() int
fn C._exit(int)
fn C.alarm(u32) u32

fn probe(directory string) ! {
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
	if C.prctl(36, voidptr(1), voidptr(0), voidptr(0), voidptr(0)) != 0 { return error('SET subreaper failed') }
	mut enabled := i32(0)
	if C.prctl(37, &enabled, voidptr(0), voidptr(0), voidptr(0)) != 0 || enabled != 1 { return error('GET subreaper failed') }
	mut gate := [int(-1), -1]!
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
	if os.args.len != 2 { eprintln('usage: wine-subreaper-probe FRESH_EXTERNAL_DIRECTORY'); exit(2) }
	probe(os.args[1]) or { eprintln(err); exit(1) }
}
