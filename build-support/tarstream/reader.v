// SPDX-License-Identifier: GPL-2.0-only
module tarstream

import crypto.sha256
import strconv
import tarcore

#flag -larchive
#flag -I @DIR
#include "filter_abi.h"

struct C.archive {}

struct C.archive_entry {}

fn C.archive_read_new() &C.archive
fn C.archive_read_support_filter_all(&C.archive) int
fn C.archive_read_support_filter_none(&C.archive) int
fn C.archive_read_support_format_raw(&C.archive) int
fn C.archive_read_open_filename(&C.archive, &char, usize) int
fn C.archive_read_next_header(&C.archive, &&C.archive_entry) int
fn C.archive_read_data(&C.archive, voidptr, usize) isize
fn C.archive_error_string(&C.archive) &char
fn C.archive_read_free(&C.archive) int

pub struct End {}

pub fn (err End) msg() string { return 'end of archive' }

pub fn (err End) code() int { return 0 }

pub struct Reader {
mut:
	stream    &C.archive = unsafe { nil }
	remaining i64
	padding   int
	started   bool
	ended     bool
	globals   map[string]string
}

fn filter_error(stream &C.archive) IError {
	pointer := C.archive_error_string(stream)
	if pointer == unsafe { nil } { return error('cannot read archive stream') }
	return error(unsafe { pointer.vstring().clone() })
}

// libarchive only unwraps compression. Parsing names in V preserves their
// exact UTF-8 bytes, including decomposed names on macOS.
pub fn open(path string) !Reader {
	return open_filtered(path, true)
}

// Boot module inputs are deliberately uncompressed, matching tar's r: mode.
pub fn open_plain(path string) !Reader {
	return open_filtered(path, false)
}

fn open_filtered(path string, compressed bool) !Reader {
	stream := C.archive_read_new()
	if stream == unsafe { nil } { return error('cannot allocate archive stream') }
	mut opened := false
	defer { if !opened { C.archive_read_free(stream) } }
	filter := if compressed { C.archive_read_support_filter_all(stream) } else { C.archive_read_support_filter_none(stream) }
	if filter < 0 || C.archive_read_support_format_raw(stream) != 0
		|| C.archive_read_open_filename(stream, path.str, 10240) != 0 {
		return filter_error(stream)
	}
	mut entry := &C.archive_entry(unsafe { nil })
	if C.archive_read_next_header(stream, &entry) != 0 { return filter_error(stream) }
	opened = true
	return Reader{ stream: stream }
}

pub fn (mut reader Reader) close() {
	if reader.stream != unsafe { nil } {
		C.archive_read_free(reader.stream)
		reader.stream = unsafe { nil }
	}
}

fn (mut reader Reader) exact(mut buffer []u8, allow_eof bool) !bool {
	if reader.stream == unsafe { nil } { return error('archive stream is closed') }
	mut position := 0
	for position < buffer.len {
		count := unsafe { C.archive_read_data(reader.stream, &buffer[position], usize(buffer.len - position)) }
		if count < 0 { return filter_error(reader.stream) }
		if count == 0 {
			if position == 0 && allow_eof { return false }
			return error('unexpected end of archive')
		}
		position += int(count)
	}
	return true
}

pub fn (mut reader Reader) read(mut buffer []u8) !int {
	count := if reader.remaining < buffer.len { int(reader.remaining) } else { buffer.len }
	if count == 0 { return 0 }
	// Borrow the caller's stable buffer only for the synchronous read.
	mut portion := unsafe { buffer[..count] }
	reader.exact(mut portion, false)!
	reader.remaining -= count
	return count
}

fn (mut reader Reader) skip() ! {
	if reader.remaining > 0 {
		mut buffer := []u8{len: 1024 * 1024}
		for reader.remaining > 0 { reader.read(mut buffer)! }
	}
	mut padding := []u8{len: reader.padding}
	reader.exact(mut padding, false)!
	reader.padding = 0
}

fn field(data []u8, offset int, length int) string {
	return data[offset..offset + length].bytestr().all_before('\x00')
}

fn number(data []u8, offset int, length int) !i64 {
	first := data[offset]
	if first in [u8(0x80), 0xff] {
		mut value := if first == 0xff { i64(-1) } else { i64(0) }
		for byte in data[offset + 1..offset + length] {
			if value > 0x7fffffffffffff || value < i64(-0x80000000000000) {
				return error('archive number is too large')
			}
			value = value * 256 + i64(byte)
		}
		return value
	}
	value := field(data, offset, length).trim_space()
	return if value == '' { i64(0) } else { strconv.parse_int(value, 8, 64)! }
}

fn parse_header(data []u8) !tarcore.Member {
	checksum := number(data, 148, 8)!
	mut unsigned := i64(0)
	mut signed := i64(0)
	for index, byte in data {
		unsigned += if index >= 148 && index < 156 { 32 } else { int(byte) }
		signed += if index >= 148 && index < 156 { 32 } else { int(i8(byte)) }
	}
	if checksum != unsigned && checksum != signed { return error('bad archive header checksum') }
	mut member := tarcore.Member{
		name:     field(data, 0, 100)
		mode:     number(data, 100, 8)!
		uid:      number(data, 108, 8)!
		gid:      number(data, 116, 8)!
		size:     number(data, 124, 12)!
		mtime:    number(data, 136, 12)!
		kind:     data[156]
		linkname: field(data, 157, 100)
		uname:    field(data, 265, 32)
		gname:    field(data, 297, 32)
		major:    number(data, 329, 8)!
		minor:    number(data, 337, 8)!
	}
	if member.kind == 0 && member.name.ends_with('/') { member.kind = `5` }
	if member.kind == `5` { member.name = member.name.trim_right('/') }
	prefix := field(data, 345, 155)
	if prefix != '' && member.kind !in [u8(`L`), `K`, `S`] {
		member.name = prefix + '/' + member.name
	}
	return member
}

fn parse_pax(data []u8) !map[string]string {
	mut fields := map[string]string{}
	mut pos := 0
	for pos < data.len {
		mut delimiter := pos
		for delimiter < data.len && data[delimiter] != ` ` { delimiter++ }
		if delimiter == data.len { return error('invalid PAX record') }
		length := strconv.parse_int(data[pos..delimiter].bytestr(), 10, 64)!
		if length <= delimiter - pos + 2 || length > data.len - pos || data[pos + int(length) - 1] != `\n` {
			return error('invalid PAX record')
		}
		record := data[delimiter + 1..pos + int(length) - 1].bytestr()
		if !record.contains('=') || record.starts_with('=') { return error('invalid PAX record') }
		key := record.all_before('=')
		if key.starts_with('GNU.sparse.') {
			return error('sparse archive members cannot be rewritten as USTAR')
		}
		fields[key] = record.all_after('=')
		pos += int(length)
	}
	return fields
}

fn apply_pax(mut member tarcore.Member, fields map[string]string) ! {
	for key, value in fields {
		match key {
			'path' { member.name = value.trim_right('/') }
			'linkpath' { member.linkname = value }
			'uname' { member.uname = value }
			'gname' { member.gname = value }
			'uid' { member.uid = strconv.parse_int(value, 10, 64) or { 0 } }
			'gid' { member.gid = strconv.parse_int(value, 10, 64) or { 0 } }
			'size' { member.size = strconv.parse_int(value, 10, 64) or { 0 } }
			'mtime' {
				time := strconv.atof64(value) or { 0.0 }
				if time != time || time >= 9223372036854775808.0 || time < -9223372036854775808.0 {
					return error('archive time is too large')
				}
				member.mtime = i64(time)
			}
			else {}
		}
	}
}

pub fn (mut reader Reader) next() !tarcore.Member {
	if reader.ended { return End{} }
	reader.skip()!
	mut local := map[string]string{}
	mut extensions := false
	for {
		mut data := []u8{len: 512}
		if !reader.exact(mut data, true)! {
			if !reader.started || extensions { return error('missing archive header') }
			reader.ended = true
			return End{}
		}
		reader.started = true
		if data.all(it == 0) {
			if extensions { return error('missing subsequent archive header') }
			reader.ended = true
			return End{}
		}
		mut member := parse_header(data)!
		if member.size < 0 { return error('negative archive member size') }
		if member.kind in [u8(`x`), `g`, `X`, `L`, `K`] {
			if member.size > 0x7fffffff { return error('archive metadata is too large') }
			mut body := []u8{len: int(member.size)}
			reader.exact(mut body, false)!
			reader.padding = int((512 - member.size % 512) % 512)
			reader.skip()!
			extensions = true
			if member.kind in [u8(`L`), `K`] {
				local[if member.kind == `L` { 'path' } else { 'linkpath' }] = body.bytestr().all_before('\x00')
			} else {
				fields := parse_pax(body)!
				for key, value in fields {
					if member.kind == `g` {
						reader.globals[key] = value
					} else {
						local[key] = value
					}
				}
			}
			continue
		}
		if member.kind !in [u8(0), `0`, `1`, `2`, `3`, `4`, `5`, `6`, `7`] {
			return error('unsupported archive member type: ${member.kind}')
		}
		apply_pax(mut member, reader.globals)!
		apply_pax(mut member, local)!
		if member.size < 0 { return error('negative archive member size') }
		if member.regular() {
			reader.remaining = member.size
			reader.padding = int((512 - member.size % 512) % 512)
		}
		return member
	}
}

pub fn (mut reader Reader) digest() !string {
	mut hash := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		count := reader.read(mut buffer)!
		if count == 0 { break }
		hash.write(buffer[..count])!
	}
	return hash.sum([]u8{}).hex()
}

pub fn (mut reader Reader) copy_to(mut writer tarcore.Writer) ! {
	mut buffer := []u8{len: 1024 * 1024}
	for {
		count := reader.read(mut buffer)!
		if count == 0 { break }
		writer.write(buffer[..count])!
	}
}
