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

fn selftest(root string, checker string) ! {
	if os.exists(root) || os.is_link(root) { return error('selftest requires fresh external directory') }
	os.mkdir_all(root + '/input/nested')!
	os.write_file(root + '/input/nested/payload', 'payload')!
	os.symlink('nested/payload', root + '/input/link')!
	mut sparse := os.create(root + '/input/sparse')!
	sparse.seek(1048576, .start)!; sparse.write_string('end')!; sparse.close()
	fresh := root + '/fresh.tar.gz'
	invoke([os.executable(), root + '/input', fresh, checker], root + '/fresh.log')!
	for name in ['existing', 'wrong-pin', 'changed-byte', 'changed-link'] {
		os.cp(fresh, root + '/' + name + '.tar.gz')!
	}
	existing := root + '/existing.tar.gz'
	invoke([os.executable(), 'verify-existing', root + '/input', existing, digest(existing)!, checker], root + '/existing.log')!
	if os.read_file(fresh + '.inventory.txt')! != os.read_file(existing + '.inventory.txt')! { return error('fresh and existing archive inventories disagree') }
	mut refused := 0
	for name in ['wrong-pin', 'changed-byte', 'changed-link', 'existing'] {
		archive := root + '/' + name + '.tar.gz'
		if name == 'changed-byte' { os.write_file(root + '/input/nested/payload', 'changed')! }
		if name == 'changed-link' {
			os.rm(root + '/input/link')!; os.symlink('sparse', root + '/input/link')!
		}
		answer := os.exec([os.executable(), 'verify-existing', root + '/input', archive, if name == 'wrong-pin' { '0'.repeat(64) } else { digest(archive)! }, checker])
		os.write_file(root + '/' + name + '-refusal.log', answer.output)!
		if answer.exit_code == 0 { return error('accepted ' + name) }
		if name != 'existing' && (os.exists(archive + '.inventory.txt') || os.exists(archive + '.sha256')) { return error('failed seal published qualification receipts') }
		refused++
		if name == 'changed-byte' { os.write_file(root + '/input/nested/payload', 'payload')! }
		if name == 'changed-link' { os.rm(root + '/input/link')!; os.symlink('nested/payload', root + '/input/link')! }
	}
	println('Workspace archive: fresh/existing sparse baseline and ' + refused.str() + ' refusal controls PASS')
}

fn run() ! {
	$if prod {} $else { return error('compile workspace archive with -prod') }
	if os.args.len == 4 && os.args[1] == 'selftest' {
		root := os.abs_path(os.args[2])
		repo := os.real_path(os.dir(@FILE) + '/../..')
		if root == repo || root.starts_with(repo + '/') { return error('selftest requires external results') }
		selftest(root, os.real_path(os.args[3]))!; return
	}
	existing := os.args.len == 6 && os.args[1] == 'verify-existing'
	if !existing && os.args.len != 4 { return error('usage: wine-workspace-archive SOURCE NEW_ARCHIVE.tar.gz ARCHIVE_CHECKER | verify-existing SOURCE ARCHIVE.tar.gz SHA256 ARCHIVE_CHECKER') }
	if digest(@FILE)! != sha256.hexhash($embed_file('wine-workspace-archive.v').to_string()) { return error('compiled workspace archive source differs') }
	source := os.abs_path(os.args[if existing { 2 } else { 1 }])
	archive := os.abs_path(os.args[if existing { 3 } else { 2 }])
	checker := os.real_path(os.args[if existing { 5 } else { 3 }])
	audit := archive + if existing { '.verified-audit' } else { '.audit' }
	repo := os.real_path(os.dir(@FILE) + '/../..')
	for path in [source, archive] {
		if path == repo || path.starts_with(repo + '/') || os.is_link(path) { return error('requires external ordinary workspace/archive paths') }
	}
	if !os.is_dir(source) || !archive.ends_with('.tar.gz') || archive.starts_with(source + '/')
		|| archive == source || (!existing && os.exists(archive)) || os.exists(audit)
		|| os.exists(archive + '.sha256') || os.exists(archive + '.inventory.txt') { return error('requires fresh external outputs and an existing workspace') }
	if existing && (!os.is_file(archive) || os.args[4].len != 64 || digest(archive)! != os.args[4]) { return error('existing archive checksum mismatch') }
	os.mkdir_all(audit)!
	mut inputs := map[string]string{}
	checker_source := repo + '/tests/ios/swift-staging-archive.v'
	for path in [@FILE, os.executable(), checker, checker_source, '/usr/bin/tar'] { inputs[path] = digest(path)! }
	os.write_file(audit + '/inputs.json', json2.encode(inputs))!
	os.cp(@FILE, audit + '/producer.v')!; os.cp(os.executable(), audit + '/producer')!
	os.cp(checker_source, audit + '/checker.v')!; os.cp(checker, audit + '/checker')!
	top := os.base(source)
	before := tree(os.dir(source), top)!
	if existing {
		os.write_file(audit + '/existing-archive-sha256.txt', os.args[4] + '\n')!
	} else {
		invoke(['/usr/bin/tar', '-czpf', archive, '-C', os.dir(source), '--', top], audit + '/archive.log')!
	}
	archive_hash := digest(archive)!
	if existing && archive_hash != os.args[4] { return error('existing archive changed before verification') }
	invoke([checker, 'check-archive-root', archive, archive_hash, source], audit + '/verify.log')!
	if before != tree(os.dir(source), top)! || archive_hash != digest(archive)! { return error('workspace/archive changed during sealing') }
	for path, expected in inputs { if digest(path)! != expected { return error('archive tool input changed: ' + path) } }
	os.write_file(archive + '.inventory.txt', before.join('\n') + '\n')!
	os.write_file(archive + '.sha256', archive_hash + '  ' + os.base(archive) + '\n'
		+ digest(archive + '.inventory.txt')! + '  ' + os.base(archive) + '.inventory.txt\n')!
	os.write_file(audit + '/inputs-verified.json', json2.encode(inputs))!
	os.write_file(audit + '/scope.txt', 'Complete original typed inventories agree before/after ' + if existing { 'verification of the explicitly pinned existing archive. Earlier failed audit receipts remain unchanged. ' } else { 'compression. ' }
		+ 'The pinned archive checker decodes every logical payload, including sparse holes, and compares all bytes, paths, modes, types and link targets including root with the complete original. No second expanded extraction; originals remain retained, and original namespaces and dependency bundles remain required.\n')!
	println('WINE WORKSPACE ARCHIVE PASS complete original/archive bytes and metadata; originals retained; no launch qualification')
}

fn main() { run() or { eprintln(err); exit(1) } }
