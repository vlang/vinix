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

struct WorkspaceInventory {
	format int = 1
	source string
	entries []string
	producer_sha256 string
	source_sha256 string
}

fn inventory_receipt(source string, receipt string, check bool) ! {
	repo := os.real_path(os.dir(@FILE) + '/../..')
	canonical_receipt := os.real_path(os.dir(receipt)) + '/' + os.base(receipt)
	if !os.is_dir(source) || os.is_link(source) || os.real_path(source) != source
		|| source == repo || source.starts_with(repo + '/')
		|| canonical_receipt == source || canonical_receipt.starts_with(source + '/')
		|| canonical_receipt == repo || canonical_receipt.starts_with(repo + '/')
		|| os.is_link(receipt) { return error('inventory requires an external canonical workspace and separate receipt') }
	if check {
		proof := json2.decode[WorkspaceInventory](os.read_file(receipt)!)!
		if proof.format != 1 || proof.source != source || proof.producer_sha256.len != 64
			|| proof.source_sha256.len != 64 || proof.entries != tree(os.dir(source), os.base(source))! {
			return error('complete workspace inventory differs')
		}
	} else {
		if os.exists(receipt) { return error('inventory receipt must be fresh') }
		before := tree(os.dir(source), os.base(source))!
		producer := digest(os.executable())!
		code := digest(@FILE)!
		if before != tree(os.dir(source), os.base(source))!
			|| producer != digest(os.executable())! || code != digest(@FILE)! { return error('workspace or inventory tool changed') }
		os.write_file(receipt, json2.encode(WorkspaceInventory{source: source, entries: before, producer_sha256: producer, source_sha256: code}))!
	}
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
	fast := root + '/fast.tar.gz'
	invoke([os.executable(), root + '/input', fast, checker, '--fast'], root + '/fast.log')!
	if os.read_file(fresh + '.inventory.txt')! != os.read_file(fast + '.inventory.txt')! { return error('normal and fast archive inventories disagree') }
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
	println('Workspace archive: fresh/fast/existing sparse baseline and ' + refused.str() + ' refusal controls PASS')
	proof := root + '/typed-inventory.json'
	invoke([os.executable(), 'record-inventory', root + '/input', proof], root + '/inventory-record.log')!
	invoke([os.executable(), 'check-inventory', root + '/input', proof], root + '/inventory-check.log')!
	payload_mode := int(os.lstat(root + '/input/nested/payload')!.mode) & 0o7777
	root_mode := int(os.lstat(root + '/input')!.mode) & 0o7777
	mut inventory_refusals := 0
	for name in ['changed-byte', 'changed-link', 'changed-mode', 'changed-root', 'added-hidden', 'missing-file', 'overwrite', 'inside-source'] {
		if name == 'changed-byte' { os.write_file(root + '/input/nested/payload', 'changed')! }
		if name == 'changed-link' { os.rm(root + '/input/link')!; os.symlink('sparse', root + '/input/link')! }
		if name == 'changed-mode' { os.chmod(root + '/input/nested/payload', payload_mode ^ 0o010)! }
		if name == 'changed-root' { os.chmod(root + '/input', root_mode ^ 0o010)! }
		if name == 'added-hidden' { os.write_file(root + '/input/.hidden', 'added')! }
		if name == 'missing-file' { os.rm(root + '/input/nested/payload')! }
		command := if name == 'overwrite' { [os.executable(), 'record-inventory', root + '/input', proof] }
			else if name == 'inside-source' { [os.executable(), 'record-inventory', root + '/input', root + '/input/receipt.json'] }
			else { [os.executable(), 'check-inventory', root + '/input', proof] }
		answer := os.exec(command)
		os.write_file(root + '/inventory-' + name + '.log', answer.output)!
		if answer.exit_code == 0 { return error('inventory accepted ' + name) }
		inventory_refusals++
		if name == 'changed-byte' || name == 'missing-file' { os.write_file(root + '/input/nested/payload', 'payload')!; os.chmod(root + '/input/nested/payload', payload_mode)! }
		if name == 'changed-link' { os.rm(root + '/input/link')!; os.symlink('nested/payload', root + '/input/link')! }
		if name == 'changed-mode' { os.chmod(root + '/input/nested/payload', payload_mode)! }
		if name == 'changed-root' { os.chmod(root + '/input', root_mode)! }
		if name == 'added-hidden' { os.rm(root + '/input/.hidden')! }
	}
	invoke([os.executable(), 'check-inventory', root + '/input', proof], root + '/inventory-restored.log')!
	println('Workspace typed inventory: restored baseline and ' + inventory_refusals.str() + ' refusal controls PASS')
}

fn run() ! {
	$if prod {} $else { return error('compile workspace archive with -prod') }
	if digest(@FILE)! != sha256.hexhash($embed_file('wine-workspace-archive.v').to_string()) { return error('compiled workspace archive source differs') }
	if os.args.len == 4 && os.args[1] in ['record-inventory', 'check-inventory'] {
		inventory_receipt(os.abs_path(os.args[2]), os.abs_path(os.args[3]), os.args[1] == 'check-inventory')!
		println('WINE WORKSPACE INVENTORY PASS complete bytes, sizes, types, modes and link targets; receipt SHA256=' + digest(os.args[3])!)
		return
	}
	if os.args.len == 4 && os.args[1] == 'selftest' {
		root := os.abs_path(os.args[2])
		repo := os.real_path(os.dir(@FILE) + '/../..')
		if root == repo || root.starts_with(repo + '/') { return error('selftest requires external results') }
		selftest(root, os.real_path(os.args[3]))!; return
	}
	existing := os.args.len == 6 && os.args[1] == 'verify-existing'
	fast := os.args.len == 5 && os.args[4] == '--fast'
	if !existing && !fast && os.args.len != 4 { return error('usage: wine-workspace-archive SOURCE NEW_ARCHIVE.tar.gz ARCHIVE_CHECKER [--fast] | verify-existing SOURCE ARCHIVE.tar.gz SHA256 ARCHIVE_CHECKER') }
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
		mut command := ['/usr/bin/tar', '-czpf', archive, '-C', os.dir(source), '--', top]
		if fast { command.insert(1, '--options=gzip:compression-level=1') }
		invoke(command, audit + '/archive.log')!
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
