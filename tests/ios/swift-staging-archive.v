// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve an unsuccessful staging tree, including links, outside the launch checkpoint.
module main

import crypto.sha256
import os
import strconv

#flag -larchive
#flag darwin -I/opt/homebrew/opt/libarchive/include
#include <archive.h>
#include <archive_entry.h>
struct C.archive {}
struct C.archive_entry {}
fn C.archive_read_new() &C.archive
fn C.archive_read_support_filter_all(&C.archive) i32
fn C.archive_read_support_format_tar(&C.archive) i32
fn C.archive_read_open_filename(&C.archive, &char, uint) i32
fn C.archive_read_next_header(&C.archive, &&C.archive_entry) i32
fn C.archive_read_data(&C.archive, voidptr, uint) i64
fn C.archive_read_data_skip(&C.archive) i32
fn C.archive_read_free(&C.archive) i32
fn C.archive_entry_pathname(&C.archive_entry) &char
fn C.archive_entry_filetype(&C.archive_entry) u32
fn C.archive_entry_perm(&C.archive_entry) u32
fn C.archive_entry_size(&C.archive_entry) i64
fn C.archive_entry_symlink(&C.archive_entry) &char
fn C.archive_entry_hardlink(&C.archive_entry) &char

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
	mut expected, top := archive_inventory(archive)!
	if top == '' || os.ls(restored)! != [top] || os.is_link(restored + '/' + top) || !os.is_dir(restored + '/' + top) { return error('unexpected restored root') }
	mut actual := inventory(restored, top)!
	actual << 'directory\t' + (int(os.lstat(restored + '/' + top)!.mode) & 0o7777).str() + '\t' + top
	expected.sort(); actual.sort()
	if expected != actual { return error('archive/restoration typed inventories differ') }
	if digest(archive)! != expected_sha { return error('archive changed during verification') }
	println('Pinned archive and complete restored bytes, paths, types, modes and link targets: PASS')
}

// Verify one complete named source tree while its parent may contain other
// workspaces. Decode every archive entry; never follow a linked root. This
// seals originals in place and grants no permission to retire expanded data.
fn check_archive_root(archive string, expected_sha string, root string) ! {
	if expected_sha.len != 64 || digest(archive)! != expected_sha { return error('archive checksum mismatch') }
	if os.is_link(archive) || !os.is_file(archive) || os.is_link(root) || !os.is_dir(root) { return error('requires regular archive and ordinary complete root') }
	mut expected, top := archive_logical_inventory(archive)!
	if top == '' || os.base(root) != top { return error('archive named root differs') }
	mut actual := inventory(os.dir(root), top)!
	actual << 'directory\t' + (int(os.lstat(root)!.mode) & 0o7777).str() + '\t' + top
	expected.sort(); actual.sort()
	if expected != actual {
		eprintln('Archive/root entries: ' + expected.len.str() + '/' + actual.len.str())
		mut root_rows := map[string]string{}
		for row in actual { root_rows[row.split('\t').last()] = row }
		mut differences := 0
		for row in expected {
			path := row.split('\t').last()
			if root_rows[path] != row {
				eprintln('Archive difference: ' + row)
				eprintln('Root difference: ' + root_rows[path])
				differences++
				if differences == 8 { break }
			}
			root_rows.delete(path)
		}
		if differences < 8 {
			for _, row in root_rows {
				eprintln('Root-only difference: ' + row)
				differences++
				if differences == 8 { break }
			}
		}
		return error('archive/named-root typed inventories differ')
	}
	if digest(archive)! != expected_sha { return error('archive changed during verification') }
	println('Pinned archive and complete named root bytes, paths, types, modes and link targets: PASS; originals retained')
}

// archive_read_data expands sparse holes into logical zero bytes. Converting
// tar to mtree on this libarchive hashes only stored extents for sparse files,
// which cannot be compared with a normal file digest. Keep legacy conversion
// modes unchanged and use complete decoded bytes for named-root sealing.
fn archive_logical_inventory(archive string) !([]string, string) {
	reader := C.archive_read_new()
	if reader == unsafe { nil } { return error('cannot allocate archive reader') }
	defer { C.archive_read_free(reader) }
	if C.archive_read_support_filter_all(reader) != 0 || C.archive_read_support_format_tar(reader) != 0
		|| C.archive_read_open_filename(reader, archive.str, 1048576) != 0 { return error('cannot open logical archive stream') }
	mut entries := []string{}
	mut seen := map[string]bool{}
	mut top := ''
	mut root_directory := false
	mut buffer := []u8{len: 1048576}
	defer { unsafe { buffer.free() } }
	for {
		mut entry := &C.archive_entry(unsafe { nil })
		answer := C.archive_read_next_header(reader, &entry)
		if answer == 1 { break } // ARCHIVE_EOF
		if answer != 0 || entry == unsafe { nil } { return error('archive header decode failed') }
		raw := C.archive_entry_pathname(entry)
		if raw == unsafe { nil } { return error('archive entry has no path') }
		kind := C.archive_entry_filetype(entry)
		mut path := unsafe { cstring_to_vstring(raw) }.clone()
		if path.starts_with('./') { path = path[2..] }
		if kind == 0o040000 && path.ends_with('/') { path = path[..path.len - 1] }
		if path == '' || path.contains_any('\\\t\r\n') { return error('unsupported archive path') }
		for component in path.split('/') { if component in ['', '.', '..'] { return error('unsafe archive path') } }
		if path in seen { return error('duplicate archive entry') }; seen[path] = true
		root := path.split('/')[0]
		if top == '' { top = root.clone() }
		if root != top { return error('multiple archive roots') }
		if C.archive_entry_hardlink(entry) != unsafe { nil } { return error('unsupported archive hard link') }
		mode := C.archive_entry_perm(entry)
		if mode > 0o7777 { return error('unsupported archive mode') }
		if path == top {
			if kind != 0o040000 { return error('archive root is not a directory') }
			root_directory = true
		}
		if kind == 0o040000 {
			entries << 'directory\t' + mode.str() + '\t' + path
			if C.archive_read_data_skip(reader) != 0 { return error('archive directory decode failed') }
		} else if kind == 0o120000 {
			target := C.archive_entry_symlink(entry)
			if target == unsafe { nil } { return error('archive link target is absent') }
			text := unsafe { cstring_to_vstring(target) }
			entries << 'link\t' + mode.str() + '\t' + text.bytes().hex() + '\t' + path
			if C.archive_read_data_skip(reader) != 0 { return error('archive symlink decode failed') }
		} else if kind == 0o100000 {
			size := C.archive_entry_size(entry)
			if size < 0 { return error('negative archive file size') }
			mut hash := sha256.new()
			mut sum := []u8{len: sha256.size}
			defer { unsafe { hash.free(); free(hash); sum.free() } }
			mut count := i64(0)
			for {
				n := C.archive_read_data(reader, buffer.data, uint(buffer.len))
				if n < 0 || n > size - count { return error('archive file decode exceeds declared size') }
				if n == 0 { break }
				hash.write(buffer[..int(n)])!
				count += n
			}
			if count != size { return error('incomplete logical archive file') }
			hash.checksum_into(mut sum)
			entries << 'file\t' + mode.str() + '\t' + size.str() + '\t' + sum.hex() + '\t' + path
		} else { return error('unsupported archive entry type') }
	}
	if top == '' || !root_directory { return error('missing archive root') }
	return entries, top
}

fn archive_inventory(archive string) !([]string, string) {
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
	if top == '' || top !in seen { return error('missing archive root') }
	return expected, top
}

// Prove backup coverage, never launch qualification. Every retiring entry must
// exist with identical bytes and metadata in a retained checksum-bound archive.
fn check_coverage(retained string, retained_sha string, retiring string, retiring_sha string) ! {
	if os.is_link(retained) || os.is_link(retiring) || !os.is_file(retained) || !os.is_file(retiring)
		|| retained_sha.len != 64 || retiring_sha.len != 64
		|| digest(retained)! != retained_sha || digest(retiring)! != retiring_sha {
		return error('requires regular checksum-bound archives')
	}
	full, root := archive_inventory(retained)!
	partial, partial_root := archive_inventory(retiring)!
	if root != partial_root { return error('archive roots differ') }
	mut entries := map[string]bool{}
	for line in full { entries[line] = true }
	for line in partial { if line !in entries { return error('retained archive does not cover: ' + line) } }
	if digest(retained)! != retained_sha || digest(retiring)! != retiring_sha { return error('archive changed during coverage check') }
	println('Archive coverage: PASS; retained=' + retained + ' sha256=' + retained_sha
		+ '; retiring=' + retiring + ' sha256=' + retiring_sha
		+ '; identical covered entries=' + partial.len.str() + '; retained entries=' + full.len.str())
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
	check_archive_root(archive, archive_sha, restored + '/input')!
	// Coverage permits extra retained entries; every retiring entry must match.
	subset := root + '/subset/input'
	os.mkdir_all(subset + '/nested')!
	os.write_file(subset + '/nested/data', 'payload')!
	os.chmod(subset + '/nested/data', 0o750)!
	partial := root + '/partial.tar.gz'
	run(['/usr/bin/tar', '-czpf', partial, '-C', os.dir(subset), 'input'])!
	partial_sha := digest(partial)!
	check_coverage(archive, archive_sha, partial, partial_sha)!
	check_coverage(archive, archive_sha, archive, archive_sha)!
	if _ := check_coverage(partial, partial_sha, archive, archive_sha) { return error('accepted uncovered entries') }
	if _ := check_coverage(archive, '0'.repeat(64), partial, partial_sha) { return error('accepted wrong retained checksum') }
	if _ := check_coverage(archive, archive_sha, partial, '0'.repeat(64)) { return error('accepted wrong retiring checksum') }
	for change in ['bytes', 'mode', 'type', 'root', 'link']! {
		os.rm(subset + '/nested/data')!
		os.write_file(subset + '/nested/data', if change == 'bytes' { 'payloae' } else { 'payload' })!
		os.chmod(subset + '/nested/data', if change == 'mode' { 0o644 } else { 0o750 })!
		if change == 'type' { os.rm(subset + '/nested/data')!; os.mkdir(subset + '/nested/data')! }
		if change == 'root' { os.chmod(subset, 0o700)! }
		if change == 'link' { os.symlink('wrong', subset + '/link')! }
		changed := root + '/coverage-' + change + '.tar.gz'
		run(['/usr/bin/tar', '-czpf', changed, '-C', os.dir(subset), 'input'])!
		if _ := check_coverage(archive, archive_sha, changed, digest(changed)!) { return error('accepted coverage ' + change) }
		if change == 'type' { os.rmdir(subset + '/nested/data')!; os.write_file(subset + '/nested/data', 'payload')! }
		os.chmod(subset, 0o755)!
	}
	println('Archive coverage checker: eight corruption controls PASS')
	path := restored + '/input/nested/data'
	os.write_file(path, 'payloae')!
	if _ := check(archive, restored) { return error('accepted changed bytes') }
	if _ := check_archive(archive, archive_sha, restored) { return error('archive accepted changed bytes') }
	if _ := check_archive_root(archive, archive_sha, restored + '/input') { return error('named root accepted changed bytes') }
	os.write_file(path, 'payload')!
	os.rm(path)!; os.mkdir(path)!
	if _ := check_archive_root(archive, archive_sha, restored + '/input') { return error('named root accepted changed type') }
	os.rmdir(path)!; os.write_file(path, 'payload')!
	os.chmod(path, 0o640)!
	if _ := check(archive, restored) { return error('accepted changed mode') }
	if _ := check_archive(archive, archive_sha, restored) { return error('archive accepted changed mode') }
	if _ := check_archive_root(archive, archive_sha, restored + '/input') { return error('named root accepted changed mode') }
	os.chmod(path, 0o750)!
	os.rm(restored + '/input/link')!
	os.symlink('nested/other', restored + '/input/link')!
	if _ := check(archive, restored) { return error('accepted changed link') }
	if _ := check_archive(archive, archive_sha, restored) { return error('archive accepted changed link') }
	if _ := check_archive_root(archive, archive_sha, restored + '/input') { return error('named root accepted changed link') }
	os.rm(restored + '/input/link')!
	os.symlink('nested/data', restored + '/input/link')!
	os.write_file(restored + '/extra', 'extra')!
	if _ := check(archive, restored) { return error('accepted extra entry') }
	if _ := check_archive(archive, archive_sha, restored) { return error('archive accepted extra entry') }
	check_archive_root(archive, archive_sha, restored + '/input')!
	os.rm(restored + '/extra')!
	os.write_file(restored + '/input/extra', 'extra')!
	if _ := check_archive_root(archive, archive_sha, restored + '/input') { return error('named root accepted extra member') }
	os.rm(restored + '/input/extra')!
	os.rm(path)!
	if _ := check(archive, restored) { return error('accepted missing entry') }
	if _ := check_archive(archive, archive_sha, restored) { return error('archive accepted missing entry') }
	if _ := check_archive_root(archive, archive_sha, restored + '/input') { return error('named root accepted missing member') }
	os.write_file(path, 'payload')!; os.chmod(path, 0o750)!
	check(archive, restored)!
	os.chmod(restored + '/input', 0o750)!
	if _ := check_archive(archive, archive_sha, restored) { return error('archive accepted changed root mode') }
	if _ := check_archive_root(archive, archive_sha, restored + '/input') { return error('named root accepted changed root mode') }
	os.chmod(restored + '/input', 0o755)!
	if _ := check_archive(archive, '0'.repeat(64), restored) { return error('accepted wrong archive binding') }
	if _ := check_archive_root(archive, '0'.repeat(64), restored + '/input') { return error('named root accepted wrong archive binding') }
	check_archive(archive, archive_sha, restored)!
	check_archive_root(archive, archive_sha, restored + '/input')!
	os.write_file(archive + '.inventory.txt', 'corrupt')!
	if _ := check(archive, restored) { return error('accepted corrupt receipt') }
	println('Staging archive checker: six corruption controls PASS')
	println('Direct archive checker: seven corruption controls PASS')
	println('Named root archive checker: eight corruption controls PASS')
	// Sparse storage and allocated zeroes represent the same logical bytes.
	sparse_root := root + '/sparse/input'
	os.mkdir_all(sparse_root)!
	sparse_path := sparse_root + '/image'
	mut sparse := os.create(sparse_path)!
	sparse.seek(1048576, .start)!
	sparse.write_string('end')!; sparse.close()
	sparse_archive := root + '/sparse.tar.gz'
	run(['/usr/bin/tar', '-czpf', sparse_archive, '-C', os.dir(sparse_root), 'input'])!
	sparse_sha := digest(sparse_archive)!
	check_archive_root(sparse_archive, sparse_sha, sparse_root)!
	mut changed := os.open_file(sparse_path, 'r+')!
	changed.seek(512, .start)!; changed.write([u8(1)])!; changed.close()
	if _ := check_archive_root(sparse_archive, sparse_sha, sparse_root) { return error('accepted changed sparse-hole byte') }
	mut restored_zero := os.open_file(sparse_path, 'r+')!
	restored_zero.seek(512, .start)!; restored_zero.write([u8(0)])!; restored_zero.close()
	check_archive_root(sparse_archive, sparse_sha, sparse_root)!
	println('Logical sparse archive checker: sparse baseline, changed-hole refusal and allocated-zero retry PASS')
}

fn main() {
	if os.args.len == 5 && os.args[1] == 'check-archive-root' {
		check_archive_root(os.abs_path(os.args[2]), os.args[3], os.abs_path(os.args[4]))!; return
	}
	if os.args.len == 6 && os.args[1] == 'check-coverage' {
		check_coverage(os.abs_path(os.args[2]), os.args[3], os.abs_path(os.args[4]), os.args[5])!; return
	}
	if os.args.len == 5 && os.args[1] == 'check-archive' {
		check_archive(os.abs_path(os.args[2]), os.args[3], os.abs_path(os.args[4]))!; return
	}
	if os.args.len == 3 && os.args[1] == 'selftest' { selftest(os.abs_path(os.args[2]))!; return }
	if os.args.len != 4 { panic('usage: swift-staging-archive SOURCE ARCHIVE SCRATCH | check ARCHIVE RESTORED | check-archive ARCHIVE SHA256 RESTORED | selftest FRESH_DIR') }
	if os.args[1] == 'check' { check(os.abs_path(os.args[2]), os.abs_path(os.args[3]))!; return }
	create(os.abs_path(os.args[1]), os.abs_path(os.args[2]), os.abs_path(os.args[3]))!
}
