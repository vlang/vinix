// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
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

fn probe(manifest string, source string, destination string) int {
	child := C.fork()
	assert child >= 0
	if child == 0 {
		C.alarm(3)
		pkgcore.pack(manifest, source, destination) or { C._exit(1) }
		C._exit(0)
	}
	mut status := 0
	assert C.waitpid(child, &status, 0) == child
	return status
}

fn check() ! {
	if os.args.len !in [2, 3] || (os.args.len == 3 && os.args[2] != '--before') {
		return error('usage: pack-source-check NEW_WORK_DIRECTORY [--before]')
	}
	work := os.abs_path(os.args[1]); before := os.args.len == 3
	if os.exists(work) || os.is_link(work) { return error('pack source qualification directory must be new') }
	os.mkdir_all(work + '/source/bin')!
	os.write_file(work + '/source/bin/app', 'executable payload')!
	os.chmod(work + '/source/bin/app', 0o755)!
	os.write_file(work + '/source/empty', '')!
	os.write_file(work + '/source/data', 'shared payload')!
	assert C.link((work + '/source/data').str, (work + '/source/shared').str) == 0
	p := pkgcore.Package{ id: 'fixture', version: '1.0.0', architecture: 'all', kind: 'data', name: 'Fixture', license: 'MIT' }
	manifest := work + '/manifest.json'
	os.write_file(manifest, json2.encode(p))!
	os.symlink(work + '/source', work + '/alias')!
	os.write_file(work + '/file', 'preserved')!
	assert C.mkfifo((work + '/fifo').str, 0o600) == 0
	for mode in ['nul', 'alias-slashes', 'alias', 'empty', 'missing', 'file', 'fifo'] {
		source := match mode {
			'nul' { work + '/source\x00ignored' }
			'alias-slashes' { work + '/alias///' }
			'alias' { work + '/alias' }
			'empty' { '' }
			else { work + '/' + mode }
		}
		status := probe(manifest, source, work + '/' + mode + '-output/repository')
		assert status == if before && mode == 'alias-slashes' { 0 } else { 256 }, mode
		assert os.exists(work + '/' + mode + '-output') == (before && mode in ['nul', 'alias-slashes']), mode
		println('${mode}: wait status ${status}; ${if before { 'previous pack source/output behavior reproduced' } else { 'refused before creating output parents' }}')
	}
	for mode in ['link', 'fifo', 'depth'] {
		root := work + '/unsafe-' + mode
		os.mkdir(root)!
		if mode == 'link' { os.symlink(work + '/file', root + '/data')! }
		if mode == 'fifo' { assert C.mkfifo((root + '/data').str, 0o600) == 0 }
		if mode == 'depth' {
			mut path := root
			for _ in 0 .. 129 { path += '/d'; os.mkdir(path)! }
			os.write_file(path + '/data', 'bounded')!
		}
		destination := work + '/unsafe-' + mode + '-output'
		status := probe(manifest, root, destination)
		assert status == if before && mode == 'depth' { 0 } else { 256 }, mode
		assert !os.exists(destination + '/manifests/fixture-all-1.0.0.json') || (before && mode == 'depth')
		assert os.read_file(work + '/file')! == 'preserved'
		println('${mode}: wait status ${status}; ${if before { 'previous tree admission reproduced' } else { 'unsafe tree refused without a manifest' }}')
	}
	one := pkgcore.pack(manifest, work + '/source', work + '/ordinary')!
	two := pkgcore.pack(manifest, work + '/source///', work + '/slashes')!
	assert one == two && one.files.len == 4
	assert one.files.map(it.path) == ['bin/app', 'data', 'empty', 'shared']
	assert one.files[0].executable && one.files[2].bytes == 0
	println('Ordinary/slashed roots, sorted paths, empty files, executable mode and shared read-only sources preserve canonical metadata')
	println('Pack source qualification passed')
}

fn main() { check() or { eprintln(err); exit(1) } }
