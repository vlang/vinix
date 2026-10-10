// SPDX-License-Identifier: GPL-2.0-only
module tarcore

import os
import strconv

pub struct Member {
pub mut:
	name     string
	mode     i64 = 0o644
	uid      i64
	gid      i64
	size     i64
	mtime    i64
	kind     u8 = `0`
	linkname string
	uname    string
	gname    string
	major    i64
	minor    i64
}

pub fn (member Member) regular() bool { return member.kind in [u8(0), `0`, `7`] }

fn text(mut data []u8, offset int, length int, value string) {
	for index in 0 .. int_min(value.len, length) { data[offset + index] = value[index] }
}

fn octal(mut data []u8, offset int, length int, value i64) ! {
	if value < 0 { return error('overflow in number field') }
	encoded := strconv.format_int(value, 8)
	if encoded.len >= length { return error('overflow in number field') }
	for index in offset .. offset + length - 1 { data[index] = `0` }
	text(mut data, offset + length - 1 - encoded.len, encoded.len, encoded)
}

pub fn header(member Member) ![]u8 {
	mut name := member.name
	if member.kind == `5` && !name.ends_with('/') { name += '/' }
	mut prefix := ''
	if name.len > 100 {
		mut split := -1
		for index, value in name {
			if value == `/` && index <= 155 && name.len - index - 1 <= 100 {
				split = index
				break
			}
		}
		if split == -1 { return error('name is too long: ${member.name}') }
		prefix = name[..split]
		name = name[split + 1..]
	}
	if member.linkname.len > 100 { return error('linkname is too long') }
	mut data := []u8{len: 512}
	text(mut data, 0, 100, name)
	octal(mut data, 100, 8, member.mode & 0o7777)!
	octal(mut data, 108, 8, member.uid)!
	octal(mut data, 116, 8, member.gid)!
	octal(mut data, 124, 12, member.size)!
	octal(mut data, 136, 12, member.mtime)!
	for index in 148 .. 156 { data[index] = ` ` }
	data[156] = member.kind
	text(mut data, 157, 100, member.linkname)
	text(mut data, 257, 8, 'ustar\x0000')
	text(mut data, 265, 32, member.uname)
	text(mut data, 297, 32, member.gname)
	if member.kind in [u8(`3`), `4`] {
		octal(mut data, 329, 8, member.major)!
		octal(mut data, 337, 8, member.minor)!
	}
	text(mut data, 345, 155, prefix)
	mut checksum := i64(0)
	for value in data { checksum += value }
	octal(mut data, 148, 7, checksum)!
	return data
}

pub struct Writer {
mut:
	file     os.File
	position u64
}

pub fn create(path string) !Writer { return Writer{ file: os.create(path)! } }

pub fn (mut writer Writer) close() { writer.file.close() }

pub fn (mut writer Writer) write(data []u8) ! {
	mut offset := 0
	for offset < data.len {
		count := writer.file.write(data[offset..])!
		if count <= 0 { return error('cannot write archive') }
		offset += count
		writer.position += u64(count)
	}
}

pub fn (mut writer Writer) padding(size i64) ! {
	if size < 0 { return error('negative archive member size') }
	remaining := int((512 - size % 512) % 512)
	writer.write([]u8{len: remaining})!
}

pub fn (mut writer Writer) add(member Member, data []u8) ! {
	if i64(data.len) != member.size { return error('archive data size differs from header') }
	writer.write(header(member)!)!
	writer.write(data)!
	writer.padding(member.size)!
}

pub fn (mut writer Writer) finish() !u64 {
	writer.write([]u8{len: 1024})!
	remaining := int((10240 - writer.position % 10240) % 10240)
	writer.write([]u8{len: remaining})!
	return writer.position
}
