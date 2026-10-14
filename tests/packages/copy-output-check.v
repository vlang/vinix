// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import tools.packages.pkgcore

#include <sys/wait.h>
#include <unistd.h>
fn C.fork() int
fn C.waitpid(int, &int, int) int
fn C._exit(int)
fn C.alarm(u32) u32
fn C.link(&char, &char) int

fn check() ! {
	if os.args.len !in [2, 3] || (os.args.len == 3 && os.args[2] != '--before') {
		return error('usage: copy-output-check NEW_WORK_DIRECTORY [--before]')
	}
	work := os.abs_path(os.args[1])
	before := os.args.len == 3
	if os.exists(work) || os.is_link(work) { return error('copy output qualification directory must be new') }
	os.mkdir(work)!
	for kind in ['copy-fresh', 'copy-resume', 'offline-fresh', 'offline-resume', 'pack-temporary'] {
		directory := work + '/' + kind
		os.mkdir(directory)!
		source := directory + '/source'
		outside := directory + '/outside'
		prefix := if kind.ends_with('resume') { 'pay' } else { 'preserved' }
		os.write_file(source, 'payload')!
		os.write_file(outside, prefix)!
		os.chmod(outside, 0o640)!
		mut destination := directory + '/destination'
		if kind == 'pack-temporary' {
			os.mkdir_all(directory + '/payload/bin')!
			os.write_file(directory + '/payload/bin/app', 'payload')!
			os.chmod(directory + '/payload/bin/app', 0o755)!
			os.mkdir_all(directory + '/repository/objects')!
			os.write_file(directory + '/manifest.json', json2.encode(pkgcore.Package{
				id: 'app', version: '1.0.0', architecture: 'x86_64', name: 'Application',
				kind: 'native', license: 'MIT', entrypoint: 'bin/app'
			}))!
			destination = directory + '/repository/objects/' + sha256.sum('payload'.bytes()).hex() + '.new'
		}
		assert C.link(outside.str, destination.str) == 0
		child := C.fork()
		assert child >= 0
		if child == 0 {
			C.alarm(3)
			if kind == 'pack-temporary' {
				pkgcore.pack(directory + '/manifest.json', directory + '/payload', directory + '/repository') or { C._exit(1) }
			} else if kind.starts_with('offline-') {
				pkgcore.fetch('file://' + source, destination, 64, kind.ends_with('resume'), true) or { C._exit(1) }
			} else {
				pkgcore.copy_file(source, destination, if kind.ends_with('resume') { u64(3) } else { u64(0) }, 64) or { C._exit(1) }
			}
			C._exit(0)
		}
		mut status := 0
		assert C.waitpid(child, &status, 0) == child
		assert status == if before { 0 } else { 256 }, '${kind}: wait status ${status}'
		assert os.read_file(source)! == 'payload'
		assert os.read_file(outside)! == if before { 'payload' } else { prefix }
		assert os.lstat(outside)!.mode & 0o777 == 0o640
		if !before {
			assert os.read_file(destination)! == prefix
			if kind == 'pack-temporary' { assert !os.exists(directory + '/repository/manifests') }
		}
		println('${kind}: wait status ${status}; ${if before { 'unrelated hard-linked file overwritten' } else { 'refused with unrelated file and retained prefix preserved' }}')
	}
	// Sharing a read-only source is safe: only output aliases are refused.
	os.write_file(work + '/shared-source', 'payload')!
	assert C.link((work + '/shared-source').str, (work + '/source-alias').str) == 0
	pkgcore.copy_file(work + '/source-alias', work + '/ordinary', 0, 7)!
	assert os.read_file(work + '/ordinary')! == 'payload'
	assert os.read_file(work + '/shared-source')! == 'payload'
	println('Shared source and ordinary output accepted')
	println('Copy output qualification passed')
}

fn main() { check() or { eprintln(err); exit(1) } }
