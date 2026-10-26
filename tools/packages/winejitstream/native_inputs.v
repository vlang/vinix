// SPDX-License-Identifier: GPL-2.0-or-later
module winejitstream

import crypto.sha256
import os

pub struct NativePin {
pub:
	kind      string
	digest    string
	link      string
	canonical string
}

pub fn native_input_digest(path string) !string {
	mut file := os.open(path) or { return error('input open failed: ' + path + ': ' + err.msg()) }
	defer { file.close() }
	mut hash := sha256.new()
	mut buffer := []u8{len: 65536}
	mut sum := []u8{len: sha256.size}
	defer {
		unsafe {
			buffer.free()
			sum.free()
			hash.free()
			free(hash)
		}
	}
	for {
		count := file.read(mut buffer) or {
			if file.eof() {
				unsafe { err.free() }
				break
			}
			return error('input read failed: ' + path + ': ' + err.msg())
		}
		if count == 0 { break }
		hash.write(buffer[..count])!
	}
	hash.checksum_into(mut sum)
	return sum.hex()
}

fn native_input_pin(path string) !NativePin {
	info := os.lstat(path) or { return error('input lstat failed: ' + path + ': ' + err.msg()) }
	kind := info.get_filetype()
	if kind !in [.regular, .symbolic_link] {
		return error('missing ordinary input: ' + path)
	}
	link := if kind == .symbolic_link {
		os.readlink(path) or { return error('input readlink failed: ' + path + ': ' + err.msg()) }
	} else {
		''
	}
	canonical := os.real_path(path)
	if kind == .symbolic_link && os.is_dir(path) {
		return NativePin{kind: 'directory-link', link: link, canonical: canonical}
	}
	info_target := os.stat(path) or { return error('input stat failed: ' + path + ': ' + err.msg()) }
	if info_target.get_filetype() != .regular {
		return error('missing ordinary input: ' + path)
	}
	return NativePin{
		kind:      if kind == .symbolic_link { 'file-link' } else { 'regular' }
		digest:    native_input_digest(path)!
		canonical: canonical
		link:      link
	}
}

pub fn native_input_add(path string, mut pins map[string]NativePin) ! {
	selected := native_input_pin(path)!
	if selected.kind == 'directory-link' {
		return error('directory link requires covered input tree: ' + path)
	}
	pins[path] = selected
	if selected.canonical != path {
		pins[selected.canonical] = native_input_pin(selected.canonical)!
	}
}

fn native_input_walk(path string, root string, mut pins map[string]NativePin) ! {
	names := os.ls(path) or { return error('input ls failed: ' + path + ': ' + err.msg()) }
	for name in names {
		entry := path + '/' + name
		info := os.lstat(entry) or { return error('input lstat failed: ' + entry + ': ' + err.msg()) }
		kind := info.get_filetype()
		if kind == .directory {
			native_input_walk(entry, root, mut pins)!
		} else if kind == .symbolic_link && os.is_dir(entry) {
			selected := native_input_pin(entry)!
			// Its canonical target is walked through ordinary directories in this
			// same tree. Bind the literal link without following cycles or escapes.
			if selected.canonical != root && !selected.canonical.starts_with(root + '/') {
				return error('directory link escapes input tree: ' + entry)
			}
			pins[entry] = selected
		} else if kind in [.regular, .symbolic_link] {
			native_input_add(entry, mut pins)!
		} else {
			return error('unsupported input entry: ' + entry)
		}
		if pins.len > 30000 { return error('input inventory exceeds 30000 entries') }
	}
}

pub fn native_input_tree(path string, mut pins map[string]NativePin) ! {
	info := os.lstat(path) or { return error('input lstat failed: ' + path + ': ' + err.msg()) }
	if info.get_filetype() != .directory {
		return error('input tree root must be an ordinary directory: ' + path)
	}
	native_input_walk(path, os.real_path(path), mut pins)!
}

pub fn native_input_verify(pins map[string]NativePin) ! {
	if pins.len == 0 { return error('empty native input binding') }
	for path, expected in pins {
		if native_input_pin(path)! != expected { return error('input changed: ' + path) }
	}
}
