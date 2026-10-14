// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import tools.packages.pkgcore

#include <stdio.h>
#include <sys/wait.h>
#include <signal.h>
#include <unistd.h>
$if linux {
	#include <sys/syscall.h>
}
fn C.fork() int
fn C._exit(int)
fn C.alarm(u32) u32
fn C.waitpid(int, &int, int) int
fn C.kill(int, int) int
fn C.mkfifo(&char, u32) int
fn C.renamex_np(&char, &char, u32) int
fn C.syscall(i64, ...voidptr) i64

fn exchange(a string, b string) int {
	$if macos {
		return C.renamex_np(a.str, b.str, u32(2))
	} $else $if linux {
		return int(C.syscall(i64(C.SYS_renameat2), int(-100), a.str, int(-100), b.str, u32(2)))
	} $else {
		return -1
	}
}

fn check() ! {
	if os.args.len !in [2, 3] || (os.args.len == 3 && os.args[2] != '--before') {
		return error('usage: metadata-race-check NEW_WORK_DIRECTORY [--before]')
	}
	work := os.abs_path(os.args[1])
	if os.exists(work) || os.is_link(work) { return error('metadata race work directory must be new') }
	os.mkdir(work)!
	for kind in ['fifo', 'symlink'] {
		directory := work + '/' + kind
		os.mkdir(directory)!
		path := directory + '/metadata'
		alternate := directory + '/alternate'
		os.write_file(path, 'captured ordinary metadata')!
		outside := directory + '/outside'
		os.write_file(outside, 'forbidden alias target')!
		os.chmod(outside, 0o600)!
		if kind == 'fifo' { assert C.mkfifo(alternate.str, 0o600) == 0 }
		else { os.symlink(outside, alternate)! }
		// Check atomic exchange support before starting either child.
		assert exchange(path, alternate) == 0 && exchange(path, alternate) == 0
		mutator := C.fork()
		assert mutator >= 0
		if mutator == 0 {
			C.alarm(4)
			for _ in 0 .. 1000000 { if exchange(path, alternate) != 0 { C._exit(44) } }
			C._exit(0)
		}
		reader := C.fork()
		if reader < 0 {
			C.kill(mutator, 9)
			mut status := 0
			C.waitpid(mutator, &status, 0)
			return error('cannot start bounded metadata reader')
		}
		if reader == 0 {
			C.alarm(2)
			for _ in 0 .. 10000 {
				text := pkgcore.read_metadata(path) or {
					message := err.msg()
					unsafe { message.free(); err.free() }
					continue
				}
				if text != 'captured ordinary metadata' { C._exit(42) }
				unsafe { text.free() }
			}
			C._exit(0)
		}
		mut status := 0
		waited := C.waitpid(reader, &status, 0)
		C.kill(mutator, 9)
		mut mutator_status := 0
		assert C.waitpid(mutator, &mutator_status, 0) == mutator
		assert waited == reader
		println('${kind}: reader wait status ${status} (0=bounded captured reads, 14=alarm, 10752=alias bytes read)')
		assert status == if os.args.len == 3 { if kind == 'fifo' { 14 } else { 10752 } } else { 0 }
		assert os.read_file(outside)! == 'forbidden alias target' && os.lstat(outside)!.mode & 0o777 == 0o600
	}
	println('Metadata race qualification passed')
}

fn main() { check() or { eprintln(err); exit(1) } }
