// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import os
import tools.packages.pkgcore

#include <stdio.h>
#include <sys/wait.h>
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
		return error('usage: hash-file-check NEW_WORK_DIRECTORY [--before]')
	}
	work := os.abs_path(os.args[1])
	before := os.args.len == 3
	if os.exists(work) || os.is_link(work) { return error('hash qualification directory must be new') }
	os.mkdir(work)!
	for kind in ['hash-fifo', 'hash-alias', 'verify-alias', 'verify-wrong-length'] {
		directory := work + '/' + kind
		os.mkdir(directory)!
		path := directory + '/payload'
		alternate := directory + '/alternate'
		outside := directory + '/outside'
		os.write_file(path, 'safe')!
		os.write_file(outside, 'forbidden replacement bytes')!
		os.chmod(outside, 0o600)!
		if kind == 'hash-fifo' { assert C.mkfifo(alternate.str, 0o600) == 0 }
		else if kind == 'verify-wrong-length' { os.write_file(alternate, 'forbidden replacement bytes')! }
		else { os.symlink(outside, alternate)! }
		assert exchange(path, alternate) == 0 && exchange(path, alternate) == 0
		expected := sha256.hexhash('safe')
		payload := pkgcore.Payload{ bytes: 4, sha256: sha256.hexhash('forbidden replacement bytes') }
		mutator := C.fork()
		assert mutator >= 0
		if mutator == 0 {
			C.alarm(6)
			for _ in 0 .. 1000000 { if exchange(path, alternate) != 0 { C._exit(44) } }
			C._exit(0)
		}
		reader := C.fork()
		if reader < 0 {
			C.kill(mutator, 9)
			mut status := 0
			C.waitpid(mutator, &status, 0)
			return error('cannot start bounded hash reader')
		}
		if reader == 0 {
			C.alarm(4)
			for _ in 0 .. 10000 {
				if kind.starts_with('verify-') {
					if pkgcore.verified_file(path, payload) { C._exit(42) }
				} else {
					digest := pkgcore.hash_file(path) or {
						message := err.msg()
						unsafe { message.free(); err.free() }
						continue
					}
					if digest != expected { C._exit(42) }
					unsafe { digest.free() }
				}
			}
			C._exit(0)
		}
		mut status := 0
		waited := C.waitpid(reader, &status, 0)
		C.kill(mutator, 9)
		mut mutator_status := 0
		assert C.waitpid(mutator, &mutator_status, 0) == mutator && waited == reader
		println('${kind}: reader wait status ${status} (0=safe bounded reads, 14=alarm, 10752=unverified bytes accepted)')
		assert status == if before { if kind == 'hash-fifo' { 14 } else { 10752 } } else { 0 }
		assert os.read_file(outside)! == 'forbidden replacement bytes' && os.lstat(outside)!.mode & 0o777 == 0o600
	}
	println('Hash file qualification passed')
}

fn main() { check() or { eprintln(err); exit(1) } }
