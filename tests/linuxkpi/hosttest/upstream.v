// SPDX-License-Identifier: GPL-2.0-or-later
// Pinned source verification and archive selection stay outside the import.
module hosttest

import os
import crypto.sha256
import json2

#flag -larchive
#flag -O2
#flag -I @DIR
#include "archive_abi.h"
struct C.archive {}

struct C.archive_entry {}

fn C.archive_read_new() &C.archive
fn C.archive_read_support_filter_xz(&C.archive) i32
fn C.archive_read_support_format_tar(&C.archive) i32
fn C.archive_read_open_filename(&C.archive, &char, usize) i32
fn C.archive_read_next_header(&C.archive, &&C.archive_entry) i32
fn C.archive_entry_pathname(&C.archive_entry) &char
fn C.archive_entry_filetype(&C.archive_entry) u32
fn C.archive_entry_size(&C.archive_entry) i64
fn C.archive_read_data(&C.archive, voidptr, usize) isize
fn C.archive_error_string(&C.archive) &char
fn C.archive_read_free(&C.archive) i32

pub fn upstream_here() string { return os.join_path(root(), 'kernel/linuxkpi') }

pub fn upstream_default() string { return os.join_path(root(), 'third_party/linux-i915') }

pub fn upstream_pin() !map[string]json2.Any {
	return decode_json(os.read_file(os.join_path(upstream_here(), 'upstream.json'))!)!.as_map()
}

// Hash streams in the original 1 MiB chunks rather than retaining an archive.
pub fn file_digest(path string) !string {
	mut source := os.open(path)!
	defer { source.close() }
	mut digest := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		count := source.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if count == 0 { break }
		digest.write(buffer[..count])!
	}
	return digest.sum([]u8{}).hex()
}

pub fn verify_upstream(source_root string, pin map[string]json2.Any) ! {
	manifest_path := os.join_path(source_root, '.vinix-upstream.json')
	if expected := pin['manifest_sha256'] {
		if file_digest(manifest_path)! != expected.str() {
			return error('source manifest differs from the pinned manifest')
		}
	}
	manifest := decode_json(os.read_file(manifest_path)!)!.as_map()
	if (manifest['archive_sha256'] or { return error('archive_sha256') }).str() !=
		(pin['sha256'] or { return error('sha256') }).str() {
		return error('source manifest does not match the pinned archive')
	}
	expected := (manifest['files'] or { return error('files') }).as_map()
	mut actual := map[string]bool{}
	for path in os.walk_ext(source_root, '', hidden: true) {
		if os.file_name(path) != '.vinix-upstream.json' && os.is_file(path) {
			actual[os.path_rel(source_root, path)!] = true
		}
	}
	if actual.len != expected.len || expected.keys().any(it !in actual) {
		return error('imported source file set changed')
	}
	for name, checksum in expected {
		path := os.join_path(source_root, name)
		if os.is_link(path) || file_digest(path)! != checksum.str() {
			return error('modified upstream source: ' + name)
		}
	}
	println('Verified unmodified Linux ' + (pin['version'] or { return error('version') }).str() +
		' (${expected.len} files)')
}

fn archive_error(reader &C.archive) IError {
	pointer := C.archive_error_string(reader)
	message := if pointer == unsafe { nil } {
		'invalid archive'
	} else {
		unsafe { cstring_to_vstring(pointer) }
	}
	return error(message)
}

// The caller supplies exact member names. No archive pathname becomes an
// output path, and only regular files can supply compiler inputs.
pub fn archive_members(archive string, names []string) !map[string][]u8 {
	reader := C.archive_read_new()
	if reader == unsafe { nil } { return error('Cannot allocate archive reader') }
	defer { C.archive_read_free(reader) }
	if C.archive_read_support_filter_xz(reader) != 0
		|| C.archive_read_support_format_tar(reader) != 0
		|| C.archive_read_open_filename(reader, archive.str, 10240) != 0 {
		return archive_error(reader)
	}
	mut found := map[string][]u8{}
	mut entry := &C.archive_entry(unsafe { nil })
	for {
		status := C.archive_read_next_header(reader, &entry)
		if status == 1 { break }
		if status != 0 { return archive_error(reader) }
		pathname := C.archive_entry_pathname(entry)
		if pathname == unsafe { nil } { return error('Archive entry has no pathname') }
		name := unsafe { cstring_to_vstring(pathname) }
		if name !in names || name in found { continue }
		if C.archive_entry_filetype(entry) != 0o100000 {
			return error(name.all_after('/') + ' is not a regular archive member')
		}
		size := C.archive_entry_size(entry)
		if size < 0 || size > i64(0x7fffffff) {
			return error('Archive member is too large: ' + name)
		}
		mut bytes := []u8{len: int(size)}
		mut position := 0
		for position < bytes.len {
			read := unsafe { C.archive_read_data(reader, &bytes[position], usize(bytes.len - position)) }
			if read < 0 { return archive_error(reader) }
			if read == 0 { return error('Unexpected end of archive member: ' + name) }
			position += int(read)
		}
		found[name] = bytes
		if found.len == names.len { break }
	}
	return found
}
