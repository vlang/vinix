// SPDX-License-Identifier: GPL-2.0-or-later
// Exact ordinary-file/directory inventory for sealed native audio preparation.
module audioprepare

import crypto.sha256
import os

pub struct Entry {
pub:
	path   string
	kind   string
	mode   u32
	sha256 string
}

fn relative(path string) bool {
	if path == '' || os.is_abs_path(path) || path.contains('\\') { return false }
	for byte in path { if byte < 32 || byte == 127 { return false } }
	for part in path.split('/') {
		if part in ['', '.', '..'] { return false }
	}
	return true
}

fn ignores(ignored []string) ! {
	mut seen := map[string]bool{}
	for path in ignored {
		if !relative(path) || path in seen { return error('invalid or duplicate ignored preparation path: ' + path) }
		seen[path] = true
	}
}

fn excluded(path string, ignored []string) bool {
	for name in ignored {
		if path == name || path.starts_with(name + '/') { return true }
	}
	return false
}

pub fn regular(path string) ! {
	if (os.lstat(path)!).mode & 0o170000 != 0o100000 {
		return error('requires regular preparation file: ' + path)
	}
}

pub fn digest(path string) !string {
	regular(path)!
	mut file := os.open(path)!
	defer { file.close() }
	mut sum := sha256.new()
	defer { unsafe { sum.free() } }
	mut buffer := []u8{len: 64 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		n := file.read(mut buffer) or {
			if err is os.Eof { break } else { return err }
		}
		if n == 0 { break }
		sum.write(buffer[..n])!
	}
	mut bytes := sum.sum([]u8{})
	result := bytes.hex()
	unsafe { bytes.free() }
	return result
}

fn walk(root string, path string, ignored []string, mut entries []Entry) ! {
	if path != '' && (!relative(path) || excluded(path, ignored)) {
		if !relative(path) { return error('invalid preparation entry path: ' + path) }
		return
	}
	full := if path == '' { root } else { os.join_path(root, path) }
	stat := os.lstat(full)!
	type_bits := stat.mode & 0o170000
	if type_bits == 0o040000 {
		entries << Entry{path: path, kind: 'directory', mode: stat.mode & 0o7777}
		for name in os.ls(full)! {
			walk(root, if path == '' { name } else { path + '/' + name }, ignored, mut entries)!
		}
	} else if type_bits == 0o100000 {
		entries << Entry{path: path, kind: 'file', mode: stat.mode & 0o7777, sha256: digest(full)!}
	} else {
		return error('nonordinary preparation entry: ' + full)
	}
}

// The root itself is included. Ignored names are exact relative subtrees;
// their contents and kind are deliberately outside this inventory.
pub fn capture(root string, ignored []string) ![]Entry {
	ignores(ignored)!
	if !os.is_abs_path(root) || root != os.real_path(root)
		|| (os.lstat(root)!).mode & 0o170000 != 0o040000 {
		return error('preparation root must be a canonical absolute ordinary directory')
	}
	mut entries := []Entry{}
	walk(root, '', ignored, mut entries)!
	entries.sort(a.path < b.path)
	return entries
}

fn expected(entries []Entry, ignored []string) ! {
	ignores(ignored)!
	if entries.len == 0 || entries[0].path != '' || entries[0].kind != 'directory' {
		return error('preparation inventory requires its root directory')
	}
	mut parents := map[string]string{}
	mut previous := ''
	for i, entry in entries {
		if (i > 0 && (!relative(entry.path) || entry.path <= previous))
			|| excluded(entry.path, ignored) || entry.mode & ~u32(0o7777) != 0 {
			return error('invalid, duplicate or unsorted preparation entry: ' + entry.path)
		}
		if entry.kind == 'directory' {
			if entry.sha256 != '' { return error('directory has a preparation digest: ' + entry.path) }
		} else if entry.kind == 'file' {
			if entry.sha256.len != 64 || !entry.sha256.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`)) {
				return error('invalid preparation SHA-256: ' + entry.path)
			}
		} else { return error('invalid preparation entry kind: ' + entry.path) }
		if i > 0 {
			parent := if entry.path.contains('/') { entry.path.all_before_last('/') } else { '' }
			if parents[parent] != 'directory' { return error('missing preparation parent directory: ' + entry.path) }
		}
		parents[entry.path] = entry.kind
		previous = entry.path
	}
}

pub fn verify(root string, entries []Entry, ignored []string) ! {
	expected(entries, ignored)!
	if capture(root, ignored)! != entries {
		return error('preparation tree differs from its complete inventory')
	}
}
