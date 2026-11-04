// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve an unsuccessful staging tree, including links, outside the launch checkpoint.
module main

import crypto.sha256
import os
import strconv

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

fn check(archive string, restored string) ! {
	if os.is_link(archive) || os.is_link(archive + '.inventory.txt') || os.is_link(archive + '.sha256')
		|| os.is_link(restored) || !os.is_dir(restored) { return error('requires regular archive receipts and a restored directory') }
	expected := digest(archive)! + '  ' + os.file_name(archive) + '\n'
		+ digest(archive + '.inventory.txt')! + '  ' + os.file_name(archive) + '.inventory.txt\n'
	if os.read_file(archive + '.sha256')! != expected { return error('archive or inventory checksum changed') }
	text := os.read_file(archive + '.inventory.txt')!
	lines := text.trim_space().split_into_lines()
	if lines.len == 0 { return error('empty inventory') }
	top := lines[0].split('\t').last().split('/')[0]
	if top in ['', '.', '..'] || top.contains_any('\\\r\n') { return error('unsafe root') }
	if os.ls(restored)! != [top] || os.is_link(restored + '/' + top) || !os.is_dir(restored + '/' + top) {
		return error('unexpected restored root')
	}
	if inventory(restored, top)!.join('\n') + '\n' != text { return error('restored typed inventory differs') }
	println('Staging archive checksums and complete restored types, modes, links, sizes and hashes: PASS; root mode=' + (int(os.lstat(restored + '/' + top)!.mode) & 0o7777).str())
}

// Compare a pinned archive with an existing complete extraction without making
// another large scratch copy. Libarchive hashes every payload into flat mtree.
// Ambiguous paths/metadata and unsupported types are rejected, never followed.
fn check_archive(archive string, expected_sha string, restored string) ! {
	if expected_sha.len != 64 || digest(archive)! != expected_sha { return error('archive checksum mismatch') }
	if os.is_link(archive) || os.is_link(restored) || !os.is_dir(restored) { return error('requires regular archive and restoration directory') }
	result := os.exec(['/usr/bin/tar', '--format=mtree', '--options=mtree:sha256', '-cf', '-', '@' + archive])
	if result.exit_code != 0 { return error('archive decode failed: ' + result.output) }
	mut expected := []string{}
	mut seen := map[string]bool{}
	mut top := ''
	for line in result.output.split_into_lines() {
		if line == '' || line.starts_with('#') { continue }
		parts := line.split(' ')
		if parts.len < 2 || !parts[0].starts_with('./') || parts[0].contains_any('\\\t\r\n') { return error('unsupported mtree path') }
		path := parts[0][2..]
		for component in path.split('/') { if component in ['', '.', '..']! { return error('unsafe archive path') } }
		if path in seen { return error('duplicate archive entry') }; seen[path] = true
		root := path.split('/')[0]
		if top == '' { top = root }
		if root != top { return error('multiple archive roots') }
		mut fields := map[string]string{}
		for part in parts[1..] {
			pair := part.split_nth('=', 2)
			if pair.len != 2 || pair[0] in fields { return error('ambiguous mtree field') }
			fields[pair[0]] = pair[1]
		}
		mode := strconv.parse_int(fields['mode'], 8, 32)!
		if mode < 0 || mode > 0o7777 { return error('invalid archive mode') }
		prefix := mode.str() + '\t'
		match fields['type'] {
			'dir' { expected << 'directory\t' + prefix + path }
			'file' {
				if fields['sha256digest'].len != 64 { return error('missing file digest or unsupported hard link') }
				size := strconv.parse_uint(fields['size'], 10, 64)!
				expected << 'file\t' + prefix + size.str() + '\t' + fields['sha256digest'] + '\t' + path
			}
			'link' {
				if 'link' !in fields || fields['link'].contains_any('\\\t\r\n') { return error('unsupported link target') }
				expected << 'link\t' + prefix + fields['link'].bytes().hex() + '\t' + path
			}
			else { return error('unsupported archive entry type') }
		}
	}
	if top == '' || os.ls(restored)! != [top] || os.is_link(restored + '/' + top) || !os.is_dir(restored + '/' + top) { return error('unexpected restored root') }
	mut actual := inventory(restored, top)!
	actual << 'directory\t' + (int(os.lstat(restored + '/' + top)!.mode) & 0o7777).str() + '\t' + top
	expected.sort(); actual.sort()
	if expected != actual { return error('archive/restoration typed inventories differ') }
	if digest(archive)! != expected_sha { return error('archive changed during verification') }
	println('Pinned archive and complete restored bytes, paths, types, modes and link targets: PASS')
}

fn create(source string, archive string, scratch string) ! {
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

fn selftest(root string) ! {
	if os.exists(root) { return error('selftest requires fresh scratch') }
	os.mkdir_all(root + '/input/nested')!
	os.write_file(root + '/input/nested/data', 'payload')!
	os.chmod(root + '/input/nested/data', 0o750)!
	os.symlink('nested/data', root + '/input/link')!
	archive := root + '/fixture.tar.gz'
	restored := root + '/restored'
	create(root + '/input', archive, restored)!
	check(archive, restored)!
	archive_sha := digest(archive)!
	check_archive(archive, archive_sha, restored)!
	path := restored + '/input/nested/data'
	os.write_file(path, 'payloae')!
	if _ := check(archive, restored) { return error('accepted changed bytes') }
	if _ := check_archive(archive, archive_sha, restored) { return error('archive accepted changed bytes') }
	os.write_file(path, 'payload')!
	os.chmod(path, 0o640)!
	if _ := check(archive, restored) { return error('accepted changed mode') }
	if _ := check_archive(archive, archive_sha, restored) { return error('archive accepted changed mode') }
	os.chmod(path, 0o750)!
	os.rm(restored + '/input/link')!
	os.symlink('nested/other', restored + '/input/link')!
	if _ := check(archive, restored) { return error('accepted changed link') }
	if _ := check_archive(archive, archive_sha, restored) { return error('archive accepted changed link') }
	os.rm(restored + '/input/link')!
	os.symlink('nested/data', restored + '/input/link')!
	os.write_file(restored + '/extra', 'extra')!
	if _ := check(archive, restored) { return error('accepted extra entry') }
	if _ := check_archive(archive, archive_sha, restored) { return error('archive accepted extra entry') }
	os.rm(restored + '/extra')!
	os.rm(path)!
	if _ := check(archive, restored) { return error('accepted missing entry') }
	if _ := check_archive(archive, archive_sha, restored) { return error('archive accepted missing entry') }
	os.write_file(path, 'payload')!; os.chmod(path, 0o750)!
	check(archive, restored)!
	os.chmod(restored + '/input', 0o750)!
	if _ := check_archive(archive, archive_sha, restored) { return error('archive accepted changed root mode') }
	os.chmod(restored + '/input', 0o755)!
	if _ := check_archive(archive, '0'.repeat(64), restored) { return error('accepted wrong archive binding') }
	check_archive(archive, archive_sha, restored)!
	os.write_file(archive + '.inventory.txt', 'corrupt')!
	if _ := check(archive, restored) { return error('accepted corrupt receipt') }
	println('Staging archive checker: six corruption controls PASS')
	println('Direct archive checker: seven corruption controls PASS')
}

fn main() {
	if os.args.len == 5 && os.args[1] == 'check-archive' {
		check_archive(os.abs_path(os.args[2]), os.args[3], os.abs_path(os.args[4]))!; return
	}
	if os.args.len == 3 && os.args[1] == 'selftest' { selftest(os.abs_path(os.args[2]))!; return }
	if os.args.len != 4 { panic('usage: swift-staging-archive SOURCE ARCHIVE SCRATCH | check ARCHIVE RESTORED | check-archive ARCHIVE SHA256 RESTORED | selftest FRESH_DIR') }
	if os.args[1] == 'check' { check(os.abs_path(os.args[2]), os.abs_path(os.args[3]))!; return }
	create(os.abs_path(os.args[1]), os.abs_path(os.args[2]), os.abs_path(os.args[3]))!
}
