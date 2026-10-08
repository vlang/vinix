// SPDX-License-Identifier: GPL-2.0-or-later
module buildcore

import hosttest
import json2
import os

fn item(value Value, key string) !Value {
	if value is map[string]Value { return value[key] or { return error('Missing ' + key) } }
	return error('Not an object')
}

fn contains(value Value, key string) bool {
	return match value {
		map[string]Value { key in value }
		string { value.contains(key) }
		[]Value { value.any(equal(it, Value(key))) }
		else { false }
	}
}

fn path_join(root string, relative string) string {
	return if relative.starts_with('/') { relative } else if root.ends_with('/') { root + relative } else { root + '/' + relative }
}

// JSON metadata carries Python code points, while POSIX paths use UTF-8 with
// surrogateescape. Convert only the allowed U+DC80..U+DCFF byte escapes.
fn filesystem(text string) !string {
	mut bytes := []u8{cap: text.len}
	mut i := 0
	for i < text.len {
		if i + 2 < text.len && text[i] == 0xed && text[i + 1] >= 0xa0 && text[i + 1] <= 0xbf {
			if text[i + 1] !in [u8(0xb2), 0xb3] { return error('Invalid filesystem surrogate') }
			bytes << u8(0x80 + int(text[i + 1] - 0xb2) * 64 + int(text[i + 2] - 0x80))
			i += 3
		} else {
			bytes << text[i]
			i++
		}
	}
	return bytes.bytestr()
}

fn regular(path string) bool {
	if path.contains('\x00') { return false }
	state := os.stat(path) or { return false }
	return state.get_filetype() == .regular
}

pub fn glibc_valid(root string, marker Value, pin Value, alias_policy string, libraries []string) bool {
	return validate_glibc_package(root, marker, pin, alias_policy, libraries) or { false }
}

fn validate_glibc_package(root string, marker Value, pin Value, alias_policy string, libraries []string) !bool {
	if !equal(item(marker, 'package')!, pin) || !equal(item(marker, 'alias_policy')!, Value(alias_policy)) { return false }
	file_value := item(marker, 'files')!
	alias_value := item(marker, 'aliases')!
	if file_value !is map[string]Value || alias_value !is map[string]Value { return false }
	files := file_value as map[string]Value
	aliases := alias_value as map[string]Value
	for name in libraries {
		required := files['usr/lib/x86_64-linux-gnu/' + name] or { return false }
		if !contains(required, 'sha256') { return false }
	}
	if !equal(get(aliases, 'lib64/ld-linux-x86-64.so.2', Value(json2.Null{}))!, Value('../usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2')) { return false }
	for name in libraries {
		relative := 'lib/x86_64-linux-gnu/' + name
		legacy := path_join(root, relative)
		if (os.exists(legacy) || os.is_link(legacy)) && !equal(get(aliases, relative, Value(json2.Null{}))!, Value('../../usr/lib/x86_64-linux-gnu/' + name)) { return false }
	}
	for relative, expected in files {
		if !safe_relative(relative) { return false }
		path := path_join(root, filesystem(relative)!)
		if path.contains('\x00') { return false }
		if contains(expected, 'target') {
			value := item(expected, 'target')!
			if value !is string || !os.is_link(path) || os.readlink(path)! != filesystem(value)! { return false }
		} else {
			if os.is_link(path) || !regular(path) { return false }
			state := os.stat(path)!
			if !equal(Value(Number{(state.mode & 0o7777).str(), true, ''}), item(expected, 'mode')!) || !equal(Value(file_hash(path)!), item(expected, 'sha256')!) { return false }
		}
	}
	resolved_root := hosttest.module_resolve(root)!
	for relative, target in aliases {
		path := path_join(root, filesystem(relative)!)
		if path.contains('\x00') { return false }
		if target !is string || !safe_relative(relative) || !os.is_link(path) || os.readlink(path)! != filesystem(target)! { return false }
		resolved := hosttest.module_resolve(path)!
		prefix := if resolved_root.ends_with('/') { resolved_root } else { resolved_root + '/' }
		if resolved != resolved_root && !resolved.starts_with(prefix) { return false }
	}
	return true
}

pub fn driver_valid(root string, marker Value, expected Value, library string, icd string) bool {
	return validate_driver(root, marker, expected, library, icd) or { false }
}

fn validate_driver(root string, marker Value, expected Value, library string, icd string) !bool {
	if !equal(item(marker, 'inputs')!, expected) { return false }
	if icd != '' && !regular(path_join(root, icd)) { return false }
	return equal(Value(file_hash(path_join(root, library))!), item(marker, 'sha256')!)
}
