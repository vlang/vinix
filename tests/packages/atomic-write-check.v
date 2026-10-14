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
		return error('usage: atomic-write-check NEW_WORK_DIRECTORY [--before]')
	}
	work := os.abs_path(os.args[1])
	before := os.args.len == 3
	if os.exists(work) || os.is_link(work) { return error('atomic write work directory must be new') }
	os.mkdir(work)!
	for kind in ['temporary-alias', 'temporary-hardlink', 'temporary-fifo', 'temporary-directory',
		'destination-directory-alias', 'destination-directory', 'nul-path', 'oversized-metadata'] {
		directory := work + '/' + kind
		os.mkdir(directory)!
		path := directory + '/metadata'
		outside := directory + '/outside'
		os.write_file(path, 'previous metadata')!
		os.write_file(outside, 'preserved')!
		os.chmod(outside, 0o600)!
		match kind {
			'temporary-alias' { os.symlink(outside, path + '.new')! }
			'temporary-hardlink' { assert C.link(outside.str, (path + '.new').str) == 0 }
			'temporary-fifo' { assert C.mkfifo((path + '.new').str, 0o600) == 0 }
			'temporary-directory' { os.mkdir(path + '.new')! }
			'destination-directory-alias' {
				os.mkdir(directory + '/outside-folder')!
				os.rm(path)!; os.symlink(directory + '/outside-folder', path)!
			}
			'destination-directory' { os.rm(path)!; os.mkdir(path)! }
			else {}
		}
		text := if kind == 'oversized-metadata' { 'x'.repeat(8 * 1024 * 1024 + 1) } else { 'complete metadata' }
		child := C.fork()
		assert child >= 0
		if child == 0 {
			C.alarm(2)
			pkgcore.atomic_write(path + if kind == 'nul-path' { '\x00ignored' } else { '' }, text) or { C._exit(1) }
			C._exit(0)
		}
		mut status := 0
		assert C.waitpid(child, &status, 0) == child
		expected := if before {
			if kind == 'temporary-fifo' { 14 } else if kind == 'temporary-directory' { 256 } else { 0 }
		} else if kind in ['destination-directory', 'nul-path', 'oversized-metadata'] { 256 } else { 0 }
		assert status == expected, '${kind}: wait status ${status}, expected ${expected}'
		if before {
			match kind {
				'temporary-alias', 'temporary-hardlink' { assert os.read_file(outside)! == text && os.lstat(outside)!.mode & 0o777 == 0o644 }
				'destination-directory-alias' { assert os.is_link(path) && os.read_file(directory + '/outside-folder/metadata.new')! == text }
				'destination-directory' { assert os.read_file(path + '/metadata.new')! == text }
				'temporary-fifo', 'temporary-directory' { assert os.read_file(path)! == 'previous metadata' }
				else { assert os.read_file(path)! == text }
			}
		} else {
			assert os.read_file(outside)! == 'preserved' && os.lstat(outside)!.mode & 0o777 == 0o600
			if kind == 'destination-directory' { assert os.ls(path)!.len == 0 }
			else {
				assert !os.is_link(path)
				assert os.read_file(path)! == if status == 0 { text } else { 'previous metadata' }
			}
			if kind == 'destination-directory-alias' { assert os.ls(directory + '/outside-folder')!.len == 0 }
			assert os.ls(directory)!.all(!it.starts_with('.package-'))
		}
		println('${kind}: wait status ${status}; ${if before { 'previous behavior reproduced' } else { 'atomic result and external contents preserved' }}')
	}
	println('Atomic write qualification passed')
}

fn main() { check() or { eprintln(err); exit(1) } }
