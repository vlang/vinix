// SPDX-License-Identifier: GPL-2.0-only
module tarstream

import crypto.sha256
import os
import strconv
import tarcore

$if !tarstream_fd_only ? {
	#flag -larchive
	#flag -I @DIR
	#include "filter_abi.h"
}

#include <unistd.h>
#include <errno.h>
#include <poll.h>
struct C.pollfd {
mut:
	fd      i32
	events  i16
	revents i16
}

// Use private V names so importing another archive/poll caller cannot change
// these bindings. Archive sizes retain the 64-bit size_t/ssize_t ABI.
@[c: 'poll']
fn C.vinix_tar_poll(&C.pollfd, u64, i32) i32

struct C.archive {}

struct C.archive_entry {}

fn C.archive_read_new() &C.archive
fn C.archive_read_support_filter_all(&C.archive) int
fn C.archive_read_support_filter_none(&C.archive) int
fn C.archive_read_support_format_raw(&C.archive) int
@[c: 'archive_read_open_filename']
fn C.vinix_tar_archive_read_open_filename(&C.archive, &char, u64) int
fn C.archive_read_next_header(&C.archive, &&C.archive_entry) int
@[c: 'archive_read_data']
fn C.vinix_tar_archive_read_data(&C.archive, voidptr, u64) i64
fn C.archive_error_string(&C.archive) &char
fn C.archive_read_free(&C.archive) int

pub struct End {}

pub fn (err End) msg() string { return 'end of archive' }

pub fn (err End) code() int { return 0 }

pub struct Reader {
mut:
	stream            &C.archive = unsafe { nil }
	descriptor        i32        = -1
	cancel            fn () bool = unsafe { nil }
	remaining         i64
	padding           int
	started           bool
	ended             bool
	ignore_zeros      bool
	globals           map[string]string
	metadata_limit    i64 = 0x7fffffff
	allow_sparse      bool
	sparse            []SparseExtent
	logical_size      i64 = -1
	sparse_meta_bytes int
	precise_mtime string
}

pub struct SparseExtent {
pub:
	offset i64
	length i64
}

pub fn (mut reader Reader) enable_sparse() { reader.allow_sparse = true }

pub fn (reader &Reader) sparse_layout() (i64, []SparseExtent) {
	return reader.logical_size, reader.sparse
}

// Preserve a PAX fractional time for extractors; rewrite callers still use the
// integral Member.mtime field and keep their existing archive representation.
pub fn (reader &Reader) modification_time() string {return reader.precise_mtime}

fn filter_error(stream &C.archive) IError {
	$if tarstream_fd_only ? {
		return error('archive filter is unavailable in a descriptor reader')
	} $else {
		pointer := C.archive_error_string(stream)
		if pointer == unsafe { nil } { return error('cannot read archive stream') }
		return error(unsafe { pointer.vstring().clone() })
	}
}

// Borrow a decompressed input descriptor. The caller owns its closure and any
// decoder process; the shared V parser retains all tar metadata semantics.
pub fn from_descriptor(descriptor i32) !Reader {
	if descriptor < 0 { return error('invalid archive descriptor') }
	return Reader{ descriptor: descriptor }
}

pub fn from_descriptor_cancelled(descriptor i32, cancel fn () bool) !Reader {
	mut reader := from_descriptor(descriptor)!
	reader.cancel = cancel
	return reader
}

// libarchive only unwraps compression. Parsing names in V preserves their
// exact UTF-8 bytes, including decomposed names on macOS.
pub fn open(path string) !Reader {
	return open_filtered(path, true)
}

// APK v2 concatenates signature, control and payload gzip/tar streams. Its
// reader must continue beyond tar end markers to the physical stream EOF.
pub fn open_concatenated(path string) !Reader {
	mut reader := open_filtered(path, true)!
	reader.ignore_zeros = true
	return reader
}

// Boot module inputs are deliberately uncompressed, matching tar's r: mode.
pub fn open_plain(path string) !Reader {
	return open_filtered(path, false)
}

// Upload validators know the entire physical input size. Reject an extension
// claiming more bytes before allocating its metadata buffer.
pub fn open_plain_bounded(path string, metadata_limit i64) !Reader {
	mut reader := open_filtered(path, false)!
	reader.metadata_limit = metadata_limit
	return reader
}

fn open_filtered(path string, compressed bool) !Reader {
	$if tarstream_fd_only ? {
		return error('use a decompressed descriptor for this reader')
	} $else {
		stream := C.archive_read_new()
		if stream == unsafe { nil } { return error('cannot allocate archive stream') }
		mut opened := false
		defer { if !opened { C.archive_read_free(stream) } }
		filter := if compressed {
			C.archive_read_support_filter_all(stream)
		} else {
			C.archive_read_support_filter_none(stream)
		}
		if filter < 0 || C.archive_read_support_format_raw(stream) != 0
			|| C.vinix_tar_archive_read_open_filename(stream, path.str, 10240) != 0 {
			return filter_error(stream)
		}
		mut entry := &C.archive_entry(unsafe { nil })
		if C.archive_read_next_header(stream, &entry) != 0 { return filter_error(stream) }
		opened = true
		return Reader{ stream: stream }
	}
}

pub fn (mut reader Reader) close() {
	$if !tarstream_fd_only ? {
		if reader.stream != unsafe { nil } {
			C.archive_read_free(reader.stream)
			reader.stream = unsafe { nil }
		}
	}
	reader.descriptor = -1
}

fn (mut reader Reader) exact(mut buffer []u8, allow_eof bool) !bool {
	if reader.descriptor < 0 && reader.stream == unsafe { nil } {
		return error('archive stream is closed')
	}
	mut position := 0
	for position < buffer.len {
		if reader.cancel != unsafe { nil } && reader.cancel() {
			return error('archive input interrupted')
		}
		mut count := i64(0)
		if reader.descriptor >= 0 {
			count = unsafe { C.read(reader.descriptor, &buffer[position], u64(buffer.len - position)) }
			if count < 0 {
				if C.errno == C.EINTR { continue }
				if C.errno in [C.EAGAIN, C.EWOULDBLOCK] {
					mut descriptor := C.pollfd{ fd: reader.descriptor, events: i16(C.POLLIN) }
					if C.vinix_tar_poll(&descriptor, 1, 50) < 0 && C.errno != C.EINTR {
						return os.error_posix()
					}
					continue
				}
				return os.error_posix()
			}
		} else {
			$if tarstream_fd_only ? {
				return error('archive stream is closed')
			} $else {
				count = unsafe { C.vinix_tar_archive_read_data(reader.stream, &buffer[position], u64(buffer.len - position)) }
				if count < 0 { return filter_error(reader.stream) }
			}
		}
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

fn parse_pax(data []u8) !map[string]string {return parse_pax_mode(data,false)!}

fn parse_pax_mode(data []u8, allow_sparse bool) !map[string]string {
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
		if key.starts_with('GNU.sparse.') && !allow_sparse {
			return error('sparse archive members cannot be rewritten as USTAR')
		}
		fields[key] = record.all_after('=')
		if key in ['GNU.sparse.offset', 'GNU.sparse.numbytes'] {
			collected := '_native.' + key
			fields[collected] = (fields[collected] or { '' }) + record.all_after('=') + ','
		}
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
	reader.sparse = []SparseExtent{}
	reader.logical_size = -1
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
			if reader.ignore_zeros { continue }
			reader.ended = true
			return End{}
		}
		mut member := parse_header(data)!
		if member.size < 0 { return error('negative archive member size') }
		if member.kind in [u8(`x`), `g`, `X`, `L`, `K`] {
			if member.size > reader.metadata_limit || member.size > 0x7fffffff {
				return error('archive metadata is too large')
			}
			mut body := []u8{len: int(member.size)}
			reader.exact(mut body, false)!
			reader.padding = int((512 - member.size % 512) % 512)
			reader.skip()!
			extensions = true
			if member.kind in [u8(`L`), `K`] {
				local[if member.kind == `L` { 'path' } else { 'linkpath' }] = body.bytestr().all_before('\x00')
			} else {
				fields := parse_pax_mode(body, reader.allow_sparse)!
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
		if member.kind !in [u8(0), `0`, `1`, `2`, `3`, `4`, `5`, `6`, `7`] && !(reader.allow_sparse && member.kind == `S`) {
			return error('unsupported archive member type: ${member.kind}')
		}
		apply_pax(mut member, reader.globals)!
		apply_pax(mut member, local)!
		reader.precise_mtime=local['mtime'] or {reader.globals['mtime'] or {member.mtime.str()}}
		if reader.allow_sparse { reader.process_sparse(mut member, data, local)! }
		if member.size < 0 { return error('negative archive member size') }
		if member.regular() || member.kind == `S` {
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
