// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import tools.packages.pkgcore

#include <sys/wait.h>
#include <unistd.h>
fn C.fork() int
fn C.waitpid(int, &int, int) int
fn C._exit(int)
fn C.alarm(u32) u32
fn C.mkfifo(&char, u32) int
fn C.link(&char, &char) int

fn check() ! {
	if os.args.len !in [2, 3] || (os.args.len == 3 && os.args[2] != '--before') {
		return error('usage: copy-file-check NEW_WORK_DIRECTORY [--before]')
	}
	work := os.abs_path(os.args[1])
	before := os.args.len == 3
	if os.exists(work) || os.is_link(work) { return error('copy qualification directory must be new') }
	os.mkdir(work)!
	for kind in ['source-alias', 'target-alias', 'same-path', 'same-inode', 'source-fifo', 'target-fifo',
		'oversized-source', 'wrong-resume-offset', 'offline-oversized-source'] {
		directory := work + '/' + kind
		os.mkdir(directory)!
		source := directory + '/source'
		destination := if kind == 'same-path' { source } else { directory + '/destination' }
		outside := directory + '/outside'
		os.write_file(source, 'payload')!
		os.write_file(outside, 'preserved')!
		if destination != source { os.write_file(destination, 'keep')! }
		match kind {
			'source-alias' { os.rm(source)!; os.symlink(outside, source)! }
			'target-alias' { os.rm(destination)!; os.symlink(outside, destination)! }
			'same-inode' { os.rm(destination)!; assert C.link(source.str, destination.str) == 0 }
			'source-fifo' { os.rm(source)!; assert C.mkfifo(source.str, 0o600) == 0 }
			'target-fifo' { os.rm(destination)!; assert C.mkfifo(destination.str, 0o600) == 0 }
			else {}
		}
		child := C.fork()
		assert child >= 0
		if child == 0 {
			C.alarm(2)
			if kind == 'offline-oversized-source' {
				pkgcore.fetch('file://' + source, destination, 3, true, true) or { C._exit(1) }
			} else {
				pkgcore.copy_file(source, destination, if kind == 'wrong-resume-offset' { u64(1) } else { u64(0) },
					if kind == 'oversized-source' { u64(3) } else { u64(64) }) or { C._exit(1) }
			}
			C._exit(0)
		}
		mut status := 0
		assert C.waitpid(child, &status, 0) == child
		expected := if !before || kind in ['oversized-source', 'offline-oversized-source'] { 256 }
			else if kind in ['source-fifo', 'target-fifo'] { 14 } else { 0 }
		assert status == expected, '${kind}: wait status ${status}, expected ${expected}'
		if !before {
			assert os.read_file(outside)! == 'preserved'
			if kind !in ['source-alias', 'source-fifo'] { assert os.read_file(source)! == 'payload' }
			if kind == 'same-inode' { assert os.read_file(destination)! == 'payload' }
			else if kind !in ['target-alias', 'target-fifo', 'same-path'] { assert os.read_file(destination)! == 'keep' }
		} else {
			match kind {
				'source-alias' { assert os.read_file(destination)! == 'preserved' }
				'target-alias' { assert os.read_file(outside)! == 'payload' }
				'same-path', 'same-inode', 'oversized-source' { assert os.read_file(destination)! == '' }
				'wrong-resume-offset' { assert os.read_file(destination)! == 'keepayload' }
				'offline-oversized-source' { assert !os.exists(destination) }
				else {}
			}
		}
		println('${kind}: wait status ${status}; ${if before { 'previous behavior reproduced' } else { 'refused with source, destination and external files preserved' }}')
	}
	println('Copy file qualification passed')
}

fn main() { check() or { eprintln(err); exit(1) } }
