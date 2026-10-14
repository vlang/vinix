// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import tools.packages.pkgcore

#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
fn C.mkfifo(&char, u32) int
fn C.fork() int
fn C.waitpid(int, &i32, int) int
fn C.alarm(u32) u32
fn C._exit(int)

fn check() ! {
	if os.args.len !in [2, 3] || (os.args.len == 3 && os.args[2] != '--before') {
		return error('usage: durability-check NEW_WORK_DIRECTORY [--before]')
	}
	work := os.abs_path(os.args[1]); before := os.args.len == 3
	if os.exists(work) || os.is_link(work) { return error('durability work directory must be new') }
	os.mkdir_all(work)!
	for kind in ['file-alias', 'file-directory', 'file-fifo', 'directory-alias', 'directory-alias-slash', 'file-nul', 'directory-nul', 'directory-file'] {
		directory := work + '/' + kind
		os.mkdir(directory)!
		outside := directory + '/outside'
		os.write_file(outside, 'preserved outside content')!; os.chmod(outside, 0o600)!
		os.mkdir(directory + '/outside-directory')!
		path := directory + '/target'
		match kind {
			'file-alias' { os.symlink(outside, path)! }
			'directory-alias', 'directory-alias-slash' { os.symlink(directory + '/outside-directory', path)! }
			'file-directory', 'directory-nul' { os.mkdir(path)! }
			'file-fifo' { assert C.mkfifo(path.str, 0o600) == 0 }
			else { os.write_file(path, 'ordinary content')! }
		}
		child := C.fork(); assert child >= 0
		if child == 0 {
			C.alarm(3)
			argument := path + if kind.ends_with('nul') { '\x00ignored' } else if kind.ends_with('slash') { '///' } else { '' }
			if kind.starts_with('directory-') { pkgcore.sync_directory(argument) or { C._exit(1) } }
			else { pkgcore.sync_file(argument) or { C._exit(1) } }
			C._exit(0)
		}
		mut status := i32(0)
		assert C.waitpid(child, &status, 0) == child
		expected := if !before || kind == 'directory-file' { 256 } else if kind == 'file-fifo' { 14 } else { 0 }
		assert status == expected, kind + ': wait status ' + status.str() + ', expected ' + expected.str()
		assert os.read_file(outside)! == 'preserved outside content' && os.lstat(outside)!.mode & 0o777 == 0o600
		assert os.ls(directory + '/outside-directory')!.len == 0
		println(kind + ': wait status ' + status.str() + '; ' + if before { 'previous behavior reproduced' } else { 'refused with outside inputs preserved' })
	}
	os.write_file(work + '/ordinary', 'ordinary content')!
	pkgcore.sync_file(work + '/ordinary')!; pkgcore.sync_directory(work + '///')!
	assert os.read_file(work + '/ordinary')! == 'ordinary content'
	println('Package durability: ordinary file/directory retry PASS')
}

fn main() { check() or { eprintln(err); exit(1) } }
