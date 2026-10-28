// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve an unsuccessful staging tree, including links, outside the launch checkpoint.
module main

import crypto.sha256
import os

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	defer { unsafe { hash.free() } }
	mut buffer := []u8{len: 1048576}
	defer { unsafe { buffer.free() } }
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		hash.write(buffer[..n])!
	}
	return hash.sum([]u8{}).hex()
}

fn inventory(root string, relative string) ![]string {
	mut names := os.ls(root + '/' + relative)!
	names.sort()
	mut lines := []string{}
	for name in names {
		if name.contains_any('\r\n\t') { return error('unsafe inventory name') }
		path := if relative == '' { name } else { relative + '/' + name }
		full := root + '/' + path
		mode := (int(os.lstat(full)!.mode) & 0o7777).str()
		if os.is_link(full) {
			lines << 'link\t' + mode + '\t' + os.readlink(full)!.bytes().hex() + '\t' + path
		} else if os.is_dir(full) {
			lines << 'directory\t' + mode + '\t' + path
			lines << inventory(root, path)!
		} else if os.is_file(full) {
			lines << 'file\t' + mode + '\t' + os.file_size(full).str() + '\t' + digest(full)! + '\t' + path
		} else { return error('unexpected staging file type') }
	}
	return lines
}

fn run(args []string) ! {
	result := os.exec(args)
	if result.exit_code != 0 { return error(result.output) }
}

fn main() {
	if os.args.len != 4 { panic('usage: swift-staging-archive SOURCE FRESH_ARCHIVE.tar.gz FRESH_SCRATCH') }
	source := os.abs_path(os.args[1])
	archive := os.abs_path(os.args[2])
	scratch := os.abs_path(os.args[3])
	repo := os.real_path(os.getwd())
	if os.is_link(source) || !os.is_dir(source) || !archive.ends_with('.tar.gz')
		|| [source, archive, scratch].any(it == repo || it.starts_with(repo + '/'))
		|| archive.starts_with(source + '/') || scratch.starts_with(source + '/')
		|| os.exists(archive) || os.is_link(archive) || os.exists(scratch) || os.is_link(scratch)
		|| os.exists(archive + '.inventory.txt') || os.exists(archive + '.sha256') {
		panic('requires an external staging directory and fresh external archive and scratch paths')
	}
	before := inventory(os.dir(source), os.file_name(source))!
	run(['/usr/bin/tar', '-czpf', archive, '-C', os.dir(source), '--', os.file_name(source)])!
	os.mkdir_all(scratch)!
	run(['/usr/bin/tar', '-xzpf', archive, '-C', scratch])!
	if before != inventory(scratch, os.file_name(source))!
		|| before != inventory(os.dir(source), os.file_name(source))! {
		panic('staging archive typed restoration mismatch; retain every copy')
	}
	os.write_file(archive + '.inventory.txt', before.join('\n') + '\n')!
	os.write_file(archive + '.sha256', digest(archive)! + '  ' + os.file_name(archive) + '\n'
		+ digest(archive + '.inventory.txt')! + '  ' + os.file_name(archive) + '.inventory.txt\n')!
	println('Failed staging archive: complete types, modes, links, sizes and hashes restore exactly; original retained')
}
