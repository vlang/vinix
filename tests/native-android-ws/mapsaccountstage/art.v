// SPDX-License-Identifier: GPL-2.0-or-later
module mapsaccountstage

import json2
import os

pub const art_library_path = '/opt/vinix-android-aarch64/usr/lib/art/libart.so'

// This checks deployment shape, not source provenance or companion-library ABI.
// Those require the native build audit and the signed ARM runtime regression.
fn validate_art_library(bytes []u8) ! {
	elf := inspect_elf_policy(bytes, true)!
	if u16_at(bytes, 16) != 3 || elf.soname != 'libart.so' || elf.interpreter != ''
		|| elf.runpath !in ['', '\$ORIGIN', '\${ORIGIN}'] {
		return error('ART requires a shared libart.so with a private-library search path')
	}
	offset, stride, count := u64_at(bytes, 32), int(u16_at(bytes, 54)), int(u16_at(bytes, 56))
	mut loads := 0
	for index in 0 .. count {
		at := int(offset) + index * stride
		if u32_at(bytes, at) != 1 { continue }
		loads++
		alignment := u64_at(bytes, at + 48)
		file_offset, address := u64_at(bytes, at + 8), u64_at(bytes, at + 16)
		if alignment < 16384 || alignment & (alignment - 1) != 0
			|| file_offset % alignment != address % alignment
			|| file_offset % 16384 != address % 16384 {
			return error('ART load segment is incompatible with 16-KiB pages')
		}
	}
	if loads == 0 { return error('ART load segment missing') }
}

pub fn stage_art_library(source string, payload string, mut inputs map[string]json2.Any) ! {
	info := os.lstat(source)!
	if info.get_filetype() != .regular || info.size <= 0 || info.size > 128 * 1024 * 1024 {
		return error('ART input must be a bounded regular library')
	}
	mut input := os.open(source)!
	defer { input.close() }
	mut bytes := []u8{len: int(info.size)}
	defer { unsafe { bytes.free() } }
	if input.read_bytes_into(0, mut bytes)! != bytes.len || os.file_size(source) != u64(info.size) {
		return error('ART input size changed during read')
	}
	validate_art_library(bytes)!
	mut sum := new_host_sha256()!
	defer { sum.close() }
	sum.update(bytes)!
	selected := sum.finish()!
	target := payload + art_library_path
	if os.exists(target) || os.is_link(target) { return error('fresh ART destination required') }
	os.mkdir_all(os.dir(target))!
	mut published := false
	defer { if !published { os.rm(target) or {} } }
	os.cp(source, target)!
	os.chmod(target, 0o755)!
	if digest(target)! != selected || digest(source)! != selected {
		return error('ART input changed during staging')
	}
	inputs[art_library_path] = json2.Any(selected)
	published = true
}
