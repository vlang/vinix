// SPDX-License-Identifier: GPL-2.0-or-later
// Seal successful and refused MIME qualification attempts without rewriting them.
module main

import crypto.sha256
import os

const manifest_name = 'HISTORY.sha256'

fn file_hash(path string) !string {
	mut input := os.open(path)!
	defer { input.close() }
	mut hash := sha256.new()
	defer { unsafe { hash.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		n := input.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		hash.write(buffer[..n])!
	}
	return hash.sum([]u8{}).hex()
}

fn inventory(root string, relative string, mut entries []string) ! {
	// The sibling Git worktree remains mutable. Its exact owned qualification
	// sources are retained separately by capture; it is not execution evidence.
	if relative == 'worktree' { return }
	if entries.len > 10000 { return error('too many retained entries') }
	path := if relative == '' { root } else { root + '/' + relative }
	kind := os.lstat(path)!.mode & 0o170000
	if kind == 0o040000 {
		mut names := os.ls(path)!
		names.sort()
		for name in names {
			child := if relative == '' { name } else { relative + '/' + name }
			if child == manifest_name { continue }
			if child.contains('\n') || child.contains('\r') || child.contains('\\') {
				return error('unrepresentable retained path')
			}
			inventory(root, child, mut entries)!
		}
	} else if kind == 0o100000 {
		entries << file_hash(path)! + '  ' + relative + '\n'
	} else { return error('nonordinary retained entry: ' + relative) }
}

fn retain() ! {
	if os.args.len != 3 || os.args[1] !in ['capture', 'seal', 'check'] {
		return error('usage: mime-association-retain capture|seal|check EXTERNAL_HISTORY_DIRECTORY')
	}
	root := os.real_path(os.args[2])
	repository := os.dir(os.dir(os.dir(@FILE)))
	if !os.is_dir(root) || root == repository || root.starts_with(repository + '/') {
		return error('history must be an existing external directory')
	}
	if os.args[1] == 'capture' {
		if os.exists(root + '/' + manifest_name) { return error('history is already sealed') }
		os.mkdir(root + '/qualified-source')!
		for relative in ['tools/packages/pkgprotocol/mime.v', 'tools/packages/pkgprotocol/mime_test.v',
			'tools/packages/pkgprotocol/registration.v', 'tools/packages/pkgprotocol/registration_test.v',
			'tools/packages/pkgcore/model.v', 'tools/packages/pkgcore/association_test.v',
			'tools/packages/SDK.md', 'tests/packages/mime-association-check.v',
			'tests/packages/mime-association-retain.v'] {
			destination := root + '/qualified-source/' + relative
			os.mkdir_all(os.dir(destination))!
			os.cp(repository + '/' + relative, destination)!
		}
		println('MIME qualified source captured')
		return
	}
	mut entries := []string{}
	inventory(root, '', mut entries)!
	text := entries.join('')
	path := root + '/' + manifest_name
	if os.args[1] == 'seal' {
		if os.exists(path) || os.is_link(path) { return error('history is already sealed') }
		os.write_file(path, text)!
	}
	if os.lstat(path)!.mode & 0o170000 != 0o100000 || os.read_file(path)! != text {
		return error('retained history differs')
	}
	println('MIME history ' + os.args[1] + ' PASS; ' + entries.len.str() + ' files; SHA256 ' + sha256.hexhash(text))
}

fn main() { retain() or { eprintln(err); exit(1) } }
