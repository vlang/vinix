// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import tools.packages.pkgcore

#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
fn C.mkfifo(&char, u32) int
fn C.link(&char, &char) int
fn C.fork() int
fn C.waitpid(int, &i32, int) int
fn C.alarm(u32) u32
fn C._exit(int)

fn check() ! {
	if os.args.len !in [2, 3] || (os.args.len == 3 && os.args[2] != '--before') {
		return error('usage: keygen-check NEW_WORK_DIRECTORY [--before]')
	}
	work := os.abs_path(os.args[1]); before := os.args.len == 3
	if os.exists(work) || os.is_link(work) { return error('key generation work directory must be new') }
	os.mkdir_all(work, mode: 0o700)!
	for kind in ['path-nul', 'parent-alias', 'parent-alias-slashes', 'parent-writable',
		'leaf-existing', 'leaf-alias', 'leaf-dangling', 'leaf-fifo', 'leaf-directory', 'leaf-hardlink'] {
		base := work + '/' + kind
		os.mkdir(base, mode: 0o700)!; os.mkdir(base + '/outside', mode: 0o700)!
		os.write_file(base + '/outside/preserved', 'preserved input')!; os.chmod(base + '/outside/preserved', 0o600)!
		mut path := base + '/seed'
		match kind {
			'path-nul' { path += '\x00ignored' }
			'parent-alias', 'parent-alias-slashes' {
				os.symlink(base + '/outside', base + '/alias')!
				path = base + '/alias' + if kind.ends_with('slashes') { '///seed' } else { '/seed' }
			}
			'parent-writable' { os.chmod(base, 0o777)! }
			'leaf-existing' { os.write_file(path, 'preserved input')!; os.chmod(path, 0o600)! }
			'leaf-alias' { os.symlink(base + '/outside/preserved', path)! }
			'leaf-dangling' { os.symlink(base + '/outside/missing', path)! }
			'leaf-fifo' { assert C.mkfifo(path.str, 0o600) == 0 }
			'leaf-directory' { os.mkdir(path)! }
			'leaf-hardlink' { assert C.link((base + '/outside/preserved').str, path.str) == 0 }
			else {}
		}
		child := C.fork(); assert child >= 0
		if child == 0 {
			C.alarm(3)
			pkgcore.keygen(path) or { C._exit(1) }
			C._exit(0)
		}
		mut status := i32(0)
		assert C.waitpid(child, &status, 0) == child
		accepted := before && !kind.starts_with('leaf-')
		assert status == if accepted { 0 } else { 256 }, kind + ': wait status ' + status.str()
		assert os.read_file(base + '/outside/preserved')! == 'preserved input'
		assert os.lstat(base + '/outside/preserved')!.mode & 0o777 == 0o600
		if !before {
			assert os.ls(base + '/outside')! == ['preserved']
			assert !os.ls(base)!.any(it.starts_with('.package-key-'))
			if !kind.starts_with('leaf-') { assert !os.exists(base + '/seed') }
		}
		println(kind + ': wait status ' + status.str() + '; ' + if accepted { 'previous unsafe creation reproduced' } else { 'refused with existing inputs preserved' })
	}
	key := pkgcore.keygen(work + '/ordinary')!
	assert key.len == 64 && key.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
	assert os.read_file(work + '/ordinary')!.len == 65 && os.lstat(work + '/ordinary')!.mode & 0o777 == 0o600
	println('Package key generation: private ordinary retry PASS')
}

fn main() { check() or { eprintln(err); exit(1) } }
