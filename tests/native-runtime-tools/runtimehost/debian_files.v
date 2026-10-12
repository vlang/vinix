// SPDX-License-Identifier: GPL-2.0-or-later
module runtimehost

import gamehost
import hosttest
import os
import strconv
import tarstream

#include <stdlib.h>

fn C.mkdtemp(&char) &char

pub struct ArMember {
pub:
	name    string
	payload []u8
}

struct ArEnd {}

fn (e ArEnd) msg() string { return 'end of ar archive' }

fn (e ArEnd) code() int { return 0 }

struct ArReader {
	data []u8
mut:
	offset int = 8
}

fn ar_reader(data []u8) !ArReader {
	if data.len < 8 || data[..8].bytestr() != '!<arch>\n' { return error('not an ar archive') }
	return ArReader{ data: data }
}

fn (mut reader ArReader) next() !ArMember {
	if reader.offset + 60 > reader.data.len { return ArEnd{} }
	header := reader.data[reader.offset..reader.offset + 60]
	if header[..16].any(it >= 128) || header[48..58].any(it >= 128) {
		return error('invalid ASCII ar header')
	}
	name := header[..16].bytestr().trim_space().trim_right('/')
	size := strconv.parse_int(header[48..58].bytestr().trim_space(), 10, 64)!
	reader.offset += 60
	if size < 0 || size > reader.data.len - reader.offset {
		return error('truncated ar member: ' + name)
	}
	payload := reader.data[reader.offset..reader.offset + int(size)]
	reader.offset += int(size) + int(size & 1)
	return ArMember{ name: name, payload: payload }
}

pub fn ar_members(data []u8) ![]ArMember {
	mut reader := ar_reader(data)!
	mut result := []ArMember{}
	for {
		member := reader.next() or {
			if err is ArEnd { break }
			return err
		}
		result << member
	}
	return result
}

fn normalized(name string) string {
	mut parts := []string{}
	for part in name.split('/') {
		if part in ['', '.'] { continue }
		if part == '..' && parts.len > 0 && parts.last() != '..' {
			parts.pop()
		} else {
			parts << part
		}
	}
	result := parts.join('/')
	return if name.starts_with('/') {
		'/' + result
	} else if result == '' {
		'.'
	} else {
		result
	}
}

fn inside(root string, relative string) !string {
	name := normalized(relative)
	if name.starts_with('..') || name.starts_with('/') {
		return error('refusing to unpack ' + relative)
	}
	destination := gamehost.path(root, name)
	// Merged /usr trees may have directory symlinks. Permit those whose resolved
	// parents remain in the private root; reject writes through escaping links.
	base := hosttest.module_resolve(root)!
	parent := hosttest.module_resolve(gamehost.parent(destination))!
	if parent != base && !parent.starts_with(base + '/') {
		return error('archive parent escapes root: ' + relative)
	}
	return destination
}

fn extract_payload(payload string, root string) ! {
	mut reader := tarstream.open(payload)!
	defer { reader.close() }
	for {
		member := reader.next() or {
			if err is tarstream.End { break }
			return err
		}
		destination := inside(root, member.name)!
		if member.kind == `5` {
			gamehost.mkdir(destination)!
			continue
		}
		gamehost.mkdir(gamehost.parent(destination))!
		if os.exists(destination) || os.is_link(destination) { os.rm(destination)! }
		if member.kind == `2` {
			os.symlink(member.linkname, destination)!
		} else if member.kind == `1` {
			source := inside(root, member.linkname)!
			hosttest.module_copy_file_preserving_stat(source, destination)!
		} else if member.regular() {
			mut file := os.create(destination)!
			defer { file.close() }
			mut buffer := []u8{len: 1024 * 1024}
			for {
				count := reader.read(mut buffer)!
				if count == 0 { break }
				unsafe { file.write_full_buffer(buffer.data, usize(count))! }
			}
			file.close()
			os.chmod(destination, int(member.mode & 0o7777))!
		}
	}
}

pub fn extract_deb(archive string, root string) ! {
	mut reader := ar_reader(os.read_bytes(archive)!)!
	for {
		member := reader.next() or {
			if err is ArEnd { break }
			return err
		}
		if !member.name.starts_with('data.tar') { continue }
		// Keep a private compressed payload beside its downloaded .deb. This avoids
		// assuming that the caller's TMPDIR has room for a large package.
		mut pattern := (gamehost.path(gamehost.parent(archive), '.vinix-deb.XXXXXX') + '\x00').bytes()
		if C.mkdtemp(pattern.data) == unsafe { nil } { return os.error_posix() }
		directory := pattern.bytestr().all_before('\x00')
		defer { gamehost.remove(directory) or {} }
		payload := directory + '/' + member.name.all_after_last('/')
		os.write_file_array(payload, member.payload)!
		extract_payload(payload, root)!
		return
	}
	return error(archive.all_after_last('/') + ': no data archive')
}
