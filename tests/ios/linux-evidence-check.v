// SPDX-License-Identifier: GPL-2.0-or-later
// External verifier for Linux iOS file inventories. It never writes a capture.
module main

import os
import json2
import crypto.sha256

#include <sys/stat.h>
#include <dirent.h>
#include <errno.h>
fn C.mkfifo(&char, u32) int

struct Entry {
	path   string
	sha256 string
}

struct Summary {
mut:
	files       int
	directories int
	bytes       u64
	manifest    string
}

fn safe_relative(path string) ! {
	if path == '' || os.is_abs_path(path) || path.contains_any('\\\x00\r\n')
		|| (path.len > 1 && path[1] == `:`) {
		return error('unsafe inventory path: ${path}')
	}
	for part in path.split('/') {
		if part in ['', '.', '..'] { return error('unsafe inventory path: ${path}') }
	}
}

fn file_hash(path string) !(string, u64) {
	data := os.read_bytes(path)!
	defer { unsafe { data.free() } }
	return sha256.sum(data).hex(), u64(data.len)
}

// Frozen os.ls propagates opendir errors but not readdir errors. Distinguish
// the end of a directory from a failed enumeration before accepting coverage.
fn directory_names(path string) ![]string {
	directory := unsafe { C.opendir(path.str) }
	if isnil(directory) { return os.error_posix() }
	mut names := []string{}
	for {
		C.errno = 0
		entry := C.readdir(directory)
		if isnil(entry) {
			number := C.errno
			closed := C.closedir(directory)
			if number != 0 { return error_with_code('cannot enumerate directory: ${path}', number) }
			if closed != 0 { return os.error_posix() }
			return names
		}
		name := unsafe { tos_clone(&u8(&entry.d_name[0])) }
		if name !in ['.', '..'] { names << name }
	}
	return names
}

fn walk(root string, relative string, expected map[string]string, mut seen map[string]bool,
	mut summary Summary) ! {
	directory := if relative == '' { root } else { root + '/' + relative }
	mut names := directory_names(directory)!
	names.sort()
	for name in names {
		entry := if relative == '' { name } else { relative + '/' + name }
		safe_relative(entry)!
		path := root + '/' + entry
		kind := os.lstat(path)!.get_filetype()
		match kind {
			.directory {
				summary.directories++
				walk(root, entry, expected, mut seen, mut summary)!
			}
			.regular {
				if entry == 'inventory.json' { continue }
				if entry !in expected { return error('unlisted evidence file: ${entry}') }
				actual, bytes := file_hash(path)!
				if actual != expected[entry] {
					return error('SHA-256 mismatch: ${entry}; expected ${expected[entry]}, got ${actual}')
				}
				seen[entry] = true
				summary.files++
				summary.bytes += bytes
			}
			.symbolic_link { return error('symlink in evidence: ${entry}') }
			else { return error('unsupported evidence entry: ${entry} (${kind})') }
		}
	}
}

fn audit(requested string) !Summary {
	root := os.abs_path(requested)
	if os.lstat(root)!.get_filetype() != .directory {
		return error('bundle root must be a directory, not a symlink: ${root}')
	}
	manifest_path := root + '/inventory.json'
	if os.lstat(manifest_path)!.get_filetype() != .regular {
		return error('inventory.json must be a regular file, not a symlink')
	}
	manifest := os.read_file(manifest_path)!
	entries := json2.decode[[]Entry](manifest)!
	mut expected := map[string]string{}
	for entry in entries {
		safe_relative(entry.path)!
		if entry.path == 'inventory.json' {
			return error('inventory.json must not list itself')
		}
		if entry.path in expected { return error('duplicate inventory path: ${entry.path}') }
		if entry.sha256.len != 64 || entry.sha256.bytes().any(!((it >= `0` && it <= `9`)
			|| (it >= `a` && it <= `f`))) {
			return error('invalid SHA-256: ${entry.path}')
		}
		expected[entry.path] = entry.sha256
	}
	mut summary := Summary{ manifest: sha256.sum(manifest.bytes()).hex() }
	mut seen := map[string]bool{}
	walk(root, '', expected, mut seen, mut summary)!
	for path in expected.keys().sorted() {
		if path !in seen { return error('missing listed file: ${path}') }
	}
	final_manifest, _ := file_hash(manifest_path)!
	if final_manifest != summary.manifest { return error('inventory changed during verification') }
	return summary
}

fn write_inventory(root string, entries []Entry) ! {
	os.write_file(root + '/inventory.json', json2.encode(entries, prettify: true))!
}

fn fixture(base string, name string) !(string, []Entry) {
	root := base + '/' + name
	os.mkdir(root)!
	os.mkdir(root + '/.hidden')!
	os.mkdir(root + '/empty-directory')!
	os.write_file(root + '/a.txt', 'stable payload\n')!
	os.write_file(root + '/.hidden/record', 'hidden payload\n')!
	os.write_file(root + '/result.txt', 'PASS synthetic inventory control\n')!
	mut entries := []Entry{}
	for path in ['.hidden/record', 'a.txt', 'result.txt'] {
		digest, _ := file_hash(root + '/' + path)!
		entries << Entry{ path: path, sha256: digest }
	}
	write_inventory(root, entries)!
	return root, entries
}

fn rejected(root string, fragment string) ! {
	audit(root) or {
		if !err.msg().contains(fragment) {
			return error('wrong rejection for ${root}: expected ${fragment}, got ${err.msg()}')
		}
		println('CONTROL REJECTED ${os.file_name(root)}: ${err.msg()}')
		return
	}
	return error('corrupt fixture unexpectedly accepted: ${root}')
}

fn self_test(requested string) ! {
	base := os.abs_path(requested)
	if _ := os.lstat(base) { return error('self-test directory must be fresh: ${base}') }
	os.mkdir(base)!
	valid, _ := fixture(base, 'valid')!
	summary := audit(valid)!
	if summary.files != 3 || summary.directories != 2 {
		return error('positive control omitted hidden files or directories')
	}
	println('CONTROL ACCEPTED valid: ${summary.files} files, ${summary.directories} directories')
	changed, _ := fixture(base, 'changed')!
	os.write_file(changed + '/a.txt', 'changed payload\n')!
	rejected(changed, 'SHA-256 mismatch')!
	extra, _ := fixture(base, 'extra-hidden')!
	os.write_file(extra + '/.hidden/extra', 'unlisted\n')!
	rejected(extra, 'unlisted evidence file')!
	missing, _ := fixture(base, 'missing')!
	os.rm(missing + '/a.txt')!
	rejected(missing, 'missing listed file')!
	duplicate, mut duplicate_entries := fixture(base, 'duplicate')!
	duplicate_entries << duplicate_entries[0]
	write_inventory(duplicate, duplicate_entries)!
	rejected(duplicate, 'duplicate inventory path')!
	for index, path in ['../escape', '/absolute/entry', './entry', 'a//entry', 'a/../entry',
		'C:/entry', 'back\\slash', 'line\nentry'] {
		root, mut entries := fixture(base, 'unsafe-${index}')!
		entries[0] = Entry{ path: path, sha256: entries[0].sha256 }
		write_inventory(root, entries)!
		rejected(root, 'unsafe inventory path')!
	}
	bad_hash, mut bad_hash_entries := fixture(base, 'bad-hash')!
	bad_hash_entries[0] = Entry{ path: bad_hash_entries[0].path, sha256: 'g'.repeat(64) }
	write_inventory(bad_hash, bad_hash_entries)!
	rejected(bad_hash, 'invalid SHA-256')!
	self_listed, mut self_entries := fixture(base, 'self-listed')!
	self_entries << Entry{ path: 'inventory.json', sha256: '0'.repeat(64) }
	write_inventory(self_listed, self_entries)!
	rejected(self_listed, 'must not list itself')!
	link_file, _ := fixture(base, 'symlink-file')!
	os.rm(link_file + '/a.txt')!
	os.symlink(link_file + '/.hidden/record', link_file + '/a.txt')!
	rejected(link_file, 'symlink in evidence')!
	link_dir, _ := fixture(base, 'symlink-directory')!
	os.rmdir(link_dir + '/empty-directory')!
	os.symlink(link_dir + '/.hidden', link_dir + '/empty-directory')!
	rejected(link_dir, 'symlink in evidence')!
	link_inventory, _ := fixture(base, 'symlink-inventory')!
	os.rename(link_inventory + '/inventory.json', link_inventory + '/manifest')!
	os.symlink(link_inventory + '/manifest', link_inventory + '/inventory.json')!
	rejected(link_inventory, 'inventory.json must be a regular file')!
	link_root := base + '/symlink-root'
	os.symlink(valid, link_root)!
	rejected(link_root, 'bundle root must be a directory')!
	fifo, _ := fixture(base, 'fifo')!
	fifo_path := fifo + '/pipe'
	if unsafe { C.mkfifo(fifo_path.str, 0o600) } != 0 { return os.error_posix() }
	rejected(fifo, 'unsupported evidence entry')!
	println('SELF-TEST PASS: 1 accepted control; 19 corruption controls rejected')
}

fn main() {
	if os.args.len == 3 && os.args[1] == '--self-test' {
		self_test(os.args[2]) or { eprintln('SELF-TEST FAIL: ${err}'); exit(1) }
		return
	}
	if os.args.len < 2 {
		eprintln('usage: linux-evidence-check BUNDLE... | --self-test FRESH_EXTERNAL_DIRECTORY')
		exit(2)
	}
	mut failed := false
	for root in os.args[1..] {
		summary := audit(root) or {
			eprintln('AUDIT FAIL ${root}: ${err}')
			failed = true
			continue
		}
		println('AUDIT PASS ${root}: files=${summary.files} directories=${summary.directories} bytes=${summary.bytes} inventory_sha256=${summary.manifest}')
	}
	if failed { exit(1) }
}
