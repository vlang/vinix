// SPDX-License-Identifier: GPL-2.0-or-later
module winepatch

import encoding.hex
import os

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>

fn C.mkstemp(&u8) int
fn C.write(int, voidptr, usize) isize
fn C.close(int) int
fn C.rename(&char, &char) int

struct Patch {
	offset int
	old    []u8
	new    []u8
}

fn exact(mut data []u8, patches []Patch) ! {
	// Validate every site before changing even the private in-memory image.
	for patch in patches {
		if patch.old.len != patch.new.len { return error('binary patch changes region size') }
		if patch.offset < 0 || patch.offset > data.len - patch.old.len {
			return error('truncated Wine image at 0x${patch.offset:x}')
		}
		actual := data[patch.offset..patch.offset + patch.old.len].clone()
		if actual != patch.old && actual != patch.new {
			return error('unexpected Wine bytes at 0x${patch.offset:x}: ${hex.encode(actual)}')
		}
	}
	for patch in patches {
		for index, value in patch.new { data[patch.offset + index] = value }
	}
}

fn matches(data []u8, pattern []u8, overlap bool) []int {
	if pattern.len == 0 { return []int{} }
	mut result := []int{}
	mut index := 0
	for index <= data.len - pattern.len {
		mut found := true
		for offset, value in pattern {
			if data[index + offset] != value {
				found = false
				break
			}
		}
		if found { result << index }
		index += if found && !overlap { pattern.len } else { 1 }
	}
	return result
}

fn little(value u64, width int) ![]u8 {
	if width == 4 && value > 0xffffffff { return error('PE address exceeds its pointer width') }
	mut result := []u8{len: width}
	for index in 0 .. width { result[index] = u8(value >> (index * 8)) }
	return result
}

fn integer(data []u8, offset u64, width int) !u64 {
	if offset > u64(data.len) || u64(width) > u64(data.len) - offset {
		return error('truncated PE header')
	}
	mut value := u64(0)
	for index in 0 .. width { value |= u64(data[int(offset) + index]) << (index * 8) }
	return value
}

struct Section {
	offset u64
	size   u64
	rva    u64
}

struct Layout {
	base     u64
	width    int
	sections []Section
}

fn layout(data []u8) !Layout {
	if data.len < 2 || data[..2] != 'MZ'.bytes() { return error('not a PE image') }
	pe := integer(data, 0x3c, 4)!
	if integer(data, pe, 4)! != 0x4550 { return error('invalid PE signature') }
	count := integer(data, pe + 6, 2)!
	size := integer(data, pe + 20, 2)!
	optional := pe + 24
	magic := integer(data, optional, 2)!
	width := match magic {
		0x20b { 8 }
		0x10b { 4 }
		else { return error('unsupported PE optional-header magic: 0x${magic:x}') }
	}
	base := integer(data, optional + if width == 8 { u64(24) } else { u64(28) }, width)!
	table := optional + size
	if table > u64(data.len) || count * 40 > u64(data.len) - table {
		return error('truncated PE section table')
	}
	mut sections := []Section{}
	for index in 0 .. int(count) {
		entry := table + u64(index) * 40
		sections << Section{
			offset: integer(data, entry + 20, 4)!
			size:   integer(data, entry + 16, 4)!
			rva:    integer(data, entry + 12, 4)!
		}
	}
	return Layout{base, width, sections}
}

fn (image Layout) address(offset int) !u64 {
	for section in image.sections {
		if u64(offset) >= section.offset && u64(offset) - section.offset < section.size {
			delta := section.rva + u64(offset) - section.offset
			if image.base > ~u64(0) - delta { return error('PE virtual address overflows') }
			return image.base + delta
		}
	}
	return error('file offset 0x${offset:x} is outside PE sections')
}

fn unicode_handler(mut data []u8) !bool {
	image := layout(data)!
	utf := matches(data, 'UTF-16LE\x00UTF-16BE\x00'.bytes(), false)
	old_alias := 'ISO-8859-16\x00'.bytes()
	new_alias := 'UNICODE\x00\x00\x00\x00\x00'.bytes()
	old := matches(data, old_alias, false)
	new := matches(data, new_alias, false)
	if utf.len != 1 || !((old.len == 1 && new.len == 0) || (old.len == 0 && new.len == 1)) {
		return error('unexpected MSXML handler layout: utf16=${utf.len}, old=${old.len}, new=${new.len}')
	}
	alias := if old.len == 1 { old[0] } else { new[0] }
	utf_refs := matches(data, little(image.address(utf[0])!, image.width)!, true)
	alias_refs := matches(data, little(image.address(alias)!, image.width)!, true)
	if utf_refs.len != 1 || alias_refs.len != 1 {
		return error('unexpected MSXML handler references: utf16=${utf_refs}, alias=${alias_refs}')
	}
	utf_start := utf_refs[0] + image.width
	alias_start := alias_refs[0] + image.width
	length := image.width * 2
	if utf_start > data.len - length || alias_start > data.len - length {
		return error('truncated MSXML converter pointers')
	}
	converters := data[utf_start..utf_start + length].clone()
	if old.len == 0 {
		if data[alias_start..alias_start + length] != converters {
			return error('MSXML unicode alias has unexpected converter pointers')
		}
		return true
	}
	for index, value in new_alias { data[alias + index] = value }
	for index, value in converters { data[alias_start + index] = value }
	return false
}

fn service_timeout(mut data []u8) !bool {
	old := hex.decode('c0d4010060ea000010270000')!
	new := hex.decode('c0d4010060ea000060ea0000')!
	old_sites := matches(data, old, false)
	new_sites := matches(data, new, false)
	if old_sites.len == 0 && new_sites.len == 1 { return true }
	if old_sites.len != 1 || new_sites.len != 0 {
		return error('unexpected Wine services timeout globals: old=${old_sites.len}, new=${new_sites.len}')
	}
	for index, value in new { data[old_sites[0] + index] = value }
	return false
}

fn replace_file(path string, data []u8, mode int) ! {
	mut template := (os.join_path(os.dir(path), '.vinix-wine-patch-XXXXXX') + '\x00').bytes()
	fd := C.mkstemp(template.data)
	if fd < 0 { return error('cannot create temporary Wine image beside ${path}') }
	temporary := template[..template.len - 1].bytestr()
	mut opened := true
	defer {
		if opened { C.close(fd) }
		os.rm(temporary) or {}
	}
	mut written := 0
	for written < data.len {
		count := unsafe { C.write(fd, &data[written], usize(data.len - written)) }
		if count < 0 && C.errno == C.EINTR { continue }
		if count <= 0 { return error('cannot write temporary Wine image') }
		written += int(count)
	}
	closed := C.close(fd)
	opened = false
	if closed != 0 { return error('cannot close temporary Wine image') }
	// Set permissions after writing, preserving setuid/setgid bits too.
	os.chmod(temporary, mode & 0o7777)!
	if C.rename(temporary.str, path.str) != 0 { return error('cannot replace Wine image: ${path}') }
}

pub fn patch_file(kind string, path string) !string {
	mut data := os.read_bytes(path)!
	already := match kind {
		'msxml-unicode' { unicode_handler(mut data)! }
		'wine-service-timeout' { service_timeout(mut data)! }
		else {
			exact(mut data, fixed_patches(kind)!)!
			false
		}
	}
	if !already { replace_file(path, data, int(os.stat(path)!.mode))! }
	prefix := match kind {
		'msxml-unicode' {
			if already {
				'MSXML Windows unicode handler already present'
			} else {
				'patched MSXML Windows unicode handler'
			}
		}
		'wine-service-timeout' {
			if already {
				'translated-service timeout already extended'
			} else {
				'extended translated-service startup timeout'
			}
		}
		'wine-x86_64-qemu' { 'patched qemu-user x86-64 signal handling' }
		'wine-i386-qemu' { 'patched qemu-user i386 signal handling' }
		else { 'patched qemu-user x86-64 CONTEXT alignment' }
	}
	return '${prefix}: ${path}'
}

pub fn run(kind string, args []string) int {
	if args.len != 1 {
		target := match kind {
			'msxml-unicode' { 'MSXML3.DLL' }
			'wine-service-timeout' { 'SERVICES.EXE' }
			'wine-x86_64-context' { 'NTDLL.DLL' }
			else { 'NTDLL.SO' }
		}
		eprintln('usage: patch-${kind} ${target}')
		return 2
	}
	message := patch_file(kind, args[0]) or {
		eprintln(err)
		return 1
	}
	println(message)
	return 0
}
