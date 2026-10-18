// SPDX-License-Identifier: GPL-2.0-or-later
// A deterministic stdout producer for the private HTTPS output qualification.
module main

import os
import time

#include <unistd.h>
#include <signal.h>
fn C.raise(int) int
fn C.write(int, voidptr, usize) isize
fn C.fstat(int, &C.stat) int

fn emit(data []u8) ! {
	mut sent := 0
	for sent < data.len {
		count := C.write(1, unsafe { &u8(data.data) + sent }, usize(data.len - sent))
		if count < 0 && C.errno == C.EINTR { continue }
		if count <= 0 { return error('fixture output closed') }
		sent += int(count)
	}
}

fn run() !int {
	assert os.args[1] == '--disable'
	assert os.args[os.args.index('--output') + 1] == '-'
	assert os.args[os.args.index('--retry') + 1] == '0'
	mode := os.args.last().all_after_last('/')
	mut offset := 0
	if '--continue-at' in os.args { offset = os.args[os.args.index('--continue-at') + 1].int() }
	mut record := os.open_append(os.getenv('VINIX_OUTPUT_CALLS'))!
	record.writeln(mode + ' ' + offset.str())!; record.close()
	// No destination or package-lock descriptor may survive the exec boundary.
	for path in [os.getenv('VINIX_OUTPUT_TARGET'), os.getenv('VINIX_OUTPUT_LOCK')] {
		if path == '' { continue }
		info := os.stat(path)!
		for fd in 3 .. 128 {
			mut opened := C.stat{}
			if C.fstat(fd, &opened) == 0 { assert u64(opened.st_dev) != info.dev || u64(opened.st_ino) != info.inode }
		}
	}
	if mode == 'failure' { return 60 }
	if mode.starts_with('exit-') { return mode[5..].int() }
	if mode == 'terminated' { C.raise(C.SIGTERM); return 1 }
	if mode == 'no-range' && offset > 0 { return 33 }
	if mode == 'empty' { return 0 }
	data := os.read_bytes(os.getenv('VINIX_OUTPUT_SOURCE'))!
	assert offset >= 0 && offset <= data.len
	if mode == 'partial' { emit(data[offset..offset + 1024])!; return 18 }
	mut at := offset
	for at < data.len {
		end := if at + 4096 < data.len { at + 4096 } else { data.len }
		emit(data[at..end])!
		at = end
		if mode == 'slow' { time.sleep(10 * time.millisecond) }
	}
	if mode == 'oversized' { emit([u8(0)])! }
	return 0
}

fn main() { code := run() or { eprintln(err); exit(42) }; exit(code) }
