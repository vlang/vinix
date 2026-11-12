// SPDX-License-Identifier: GPL-2.0-or-later
// Complete libarchive/source comparison avoids a second expanded extraction
// on storage-constrained hosts. Originals remain required and retained.
module main

import crypto.sha256
import json2
import os

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	mut buffer := []u8{len: 1048576}
	mut sum := []u8{len: sha256.size}
	defer { unsafe { buffer.free(); sum.free(); hash.free(); free(hash) } }
	for {
		n := file.read(mut buffer) or { if file.eof() { unsafe { err.free() }; break }; return err }
		if n == 0 { break }
		hash.write(buffer[..n])!
	}
	hash.checksum_into(mut sum)
	return sum.hex()
}

fn inventory(root string, relative string, mut entries []string) ! {
	path := root + '/' + relative
	if relative.contains_any('\t\r\n') { return error('unsafe workspace inventory path') }
	mode := (u32(os.lstat(path)!.mode) & 0o7777).str()
	if os.is_link(path) { entries << 'link\t' + mode + '\t' + os.readlink(path)!.bytes().hex() + '\t' + relative }
	else if os.is_dir(path) {
		entries << 'directory\t' + mode + '\t' + relative
		mut names := os.ls(path)!; names.sort()
		for name in names { inventory(root, relative + '/' + name, mut entries)! }
	} else if os.is_file(path) {
		entries << 'file\t' + mode + '\t' + os.file_size(path).str() + '\t' + digest(path)! + '\t' + relative
	} else { return error('workspace contains unsupported node: ' + path) }
}

fn tree(root string, top string) ![]string {
	mut entries := []string{}
	inventory(root, top, mut entries)!
	entries.sort()
	return entries
}

fn invoke(args []string, log string) ! {
	os.write_file(log + '.argv.json', json2.encode(args))!
	result := os.exec(args)
	os.write_file(log, result.output)!
	if result.exit_code != 0 { return error('workspace archive command failed: ' + log) }
}

fn run() ! {
	$if prod {} $else { return error('compile workspace archive with -prod') }
	if os.args.len != 4 { return error('usage: wine-workspace-archive SOURCE NEW_ARCHIVE.tar.gz ARCHIVE_CHECKER') }
	if digest(@FILE)! != sha256.hexhash($embed_file('wine-workspace-archive.v').to_string()) { return error('compiled workspace archive source differs') }
	source := os.abs_path(os.args[1]); archive := os.abs_path(os.args[2]); checker := os.real_path(os.args[3])
	repo := os.real_path(os.dir(@FILE) + '/../..')
	for path in [source, archive] {
		if path == repo || path.starts_with(repo + '/') || os.is_link(path) { return error('requires external ordinary workspace/archive paths') }
	}
	if !os.is_dir(source) || !archive.ends_with('.tar.gz') || archive.starts_with(source + '/')
		|| archive == source || os.exists(archive) || os.exists(archive + '.audit')
		|| os.exists(archive + '.sha256') || os.exists(archive + '.inventory.txt') { return error('requires fresh external outputs and an existing workspace') }
	audit := archive + '.audit'; os.mkdir_all(audit)!
	mut inputs := map[string]string{}
	for path in [@FILE, os.executable(), checker, '/usr/bin/tar'] { inputs[path] = digest(path)! }
	os.write_file(audit + '/inputs.json', json2.encode(inputs))!
	os.cp(@FILE, audit + '/producer.v')!; os.cp(os.executable(), audit + '/producer')!
	top := os.base(source)
	before := tree(os.dir(source), top)!
	invoke(['/usr/bin/tar', '-czpf', archive, '-C', os.dir(source), '--', top], audit + '/archive.log')!
	archive_hash := digest(archive)!
	invoke([checker, 'check-archive-root', archive, archive_hash, source], audit + '/verify.log')!
	if before != tree(os.dir(source), top)! || archive_hash != digest(archive)! { return error('workspace/archive changed during sealing') }
	for path, expected in inputs { if digest(path)! != expected { return error('archive tool input changed: ' + path) } }
	os.write_file(archive + '.inventory.txt', before.join('\n') + '\n')!
	os.write_file(archive + '.sha256', archive_hash + '  ' + os.base(archive) + '\n'
		+ digest(archive + '.inventory.txt')! + '  ' + os.base(archive) + '.inventory.txt\n')!
	os.write_file(audit + '/inputs-verified.json', json2.encode(inputs))!
	os.write_file(audit + '/scope.txt', 'Complete original typed inventories agree before/after compression. The pinned archive checker decodes every archived payload and compares all bytes, paths, modes, types and link targets including root with the complete original. No second expanded extraction; originals remain retained, and original namespaces and dependency bundles remain required.\n')!
	println('WINE WORKSPACE ARCHIVE PASS complete original/archive bytes and metadata; originals retained; no launch qualification')
}

fn main() { run() or { eprintln(err); exit(1) } }
