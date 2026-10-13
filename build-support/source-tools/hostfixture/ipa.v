// SPDX-License-Identifier: GPL-2.0-or-later
module hostfixture

import hash.crc32
import os
import time

// Retain ZipFile's raw zlib compression and local DOS timestamps.
#flag -lz
#include <zlib.h>
@[typedef]
struct C.z_stream {
mut:
	next_in &u8
	avail_in u32
	next_out &u8
	avail_out u32
	total_out u64
}
fn C.zlibVersion() &char
fn C.deflateInit2_(&C.z_stream, i32, i32, i32, i32, i32, &char, i32) i32
fn C.deflateBound(&C.z_stream, u64) u64
fn C.deflate(&C.z_stream, i32) i32
fn C.deflateEnd(&C.z_stream) i32

fn compressed(input []u8) ![]u8 {
	mut stream := C.z_stream{}
	if C.deflateInit2_(&stream, -1, 8, -15, 8, 0, C.zlibVersion(), i32(sizeof(C.z_stream))) != 0 { return error('cannot initialize IPA compressor') }
	defer { C.deflateEnd(&stream) }
	capacity := C.deflateBound(&stream, u64(input.len))
	if capacity > 0x7fffffff { return error('IPA member exceeds size limit') }
	mut output := []u8{len:int(capacity)}
	stream.next_in = input.data
	stream.avail_in = u32(input.len)
	stream.next_out = output.data
	stream.avail_out = u32(output.len)
	if C.deflate(&stream, 4) != 1 { return error('cannot compress IPA member') }
	return output[..int(stream.total_out)].clone()
}

fn put16(mut bytes []u8, value u16) { bytes << u8(value); bytes << u8(value >> 8) }
fn put32(mut bytes []u8, value u32) { put16(mut bytes, u16(value)); put16(mut bytes, u16(value >> 16)) }

fn collect(directory string, prefix string, mut paths []string) ! {
	for name in os.ls(directory)! {
		path := directory + '/' + name
		relative := prefix + name
		// pathlib.rglob does not recurse through directory symlinks, but
		// is_file follows file symlinks and skips dangling links.
		if os.is_file(path) { paths << relative }
		else if os.is_dir(path) && !os.is_link(path) { collect(path, relative + '/', mut paths)! }
	}
}

pub fn ipa(root string, name string) ! {
	if name !in ['Calculator', 'NumberTileGame'] { return error('unknown iOS bundle: ' + name) }
	mut paths := []string{}
	collect(root + '/' + name + '.app', name + '.app/', mut paths)!
	paths.sort()
	mut file := os.create(root + '/' + name + '.ipa')!
	defer { file.close() }
	mut central := []u8{}
	mut offset := u32(0)
	if paths.len > 65535 { return error('IPA has too many members') }
	for path in paths {
		state := os.stat(root + '/' + path)!
		if state.size > 0x7fffffff { return error('IPA member exceeds size limit') }
		data := os.read_bytes(root + '/' + path)!
		body := compressed(data)!
		member := 'Payload/' + path
		if member.len > 65535 { return error('IPA member name exceeds size limit') }
		flags := u16(if member.bytes().any(it >= 128) { 0x800 } else { 0 })
		stamp := time.unix(state.mtime).local()
		if stamp.year < 1980 || stamp.year > 2107 { return error('IPA timestamp exceeds ZIP DOS range') }
		hour := u16((stamp.hour << 11) | (stamp.minute << 5) | (stamp.second / 2))
		date := u16(((stamp.year - 1980) << 9) | (stamp.month << 5) | stamp.day)
		checksum := crc32.sum(data)
		mut header := []u8{}
		put32(mut header, 0x04034b50)
		for value in [u16(20), flags, 8, hour, date] { put16(mut header, value) }
		for value in [checksum, u32(body.len), u32(data.len)] { put32(mut header, value) }
		put16(mut header, u16(member.len)); put16(mut header, 0)
		header << member.bytes()
		if u64(offset) + u64(header.len) + u64(body.len) + u64(central.len) > 0xffffffff { return error('IPA exceeds classic ZIP size limit') }
		unsafe { file.write_full_buffer(header.data, usize(header.len))! }
		unsafe { file.write_full_buffer(body.data, usize(body.len))! }
		put32(mut central, 0x02014b50)
		for value in [u16(0x314), 20, flags, 8, hour, date] { put16(mut central, value) }
		for value in [checksum, u32(body.len), u32(data.len)] { put32(mut central, value) }
		for value in [u16(member.len), 0, 0, 0, 0] { put16(mut central, value) }
		put32(mut central, state.mode << 16); put32(mut central, offset)
		central << member.bytes()
		offset += u32(header.len + body.len)
	}
	if u64(offset) + u64(central.len) > 0xffffffff { return error('IPA exceeds classic ZIP size limit') }
	unsafe { file.write_full_buffer(central.data, usize(central.len))! }
	mut trailer := []u8{}
	put32(mut trailer, 0x06054b50)
	for value in [u16(0), 0, u16(paths.len), u16(paths.len)] { put16(mut trailer, value) }
	put32(mut trailer, u32(central.len)); put32(mut trailer, offset); put16(mut trailer, 0)
	unsafe { file.write_full_buffer(trailer.data, usize(trailer.len))! }
	file.flush()
}
