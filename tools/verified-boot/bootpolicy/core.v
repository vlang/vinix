// SPDX-License-Identifier: GPL-2.0-or-later
// Literal boot policy and mapped PE enrollment; signing remains external.
module bootpolicy

import os
import crypto.blake2b
import verityimage

#include <sys/stat.h>

fn C.fstat(i32, &C.stat) i32

pub const config_marker = '++CONFIG_B2SUM_SIGNATURE++'
pub const disk_options = ['vinix.disk=', 'vinix.qemu_persist=', 'vinix.qemu_root=', 'vinix.apple_ans=',
	'vinix.ans_rw=', 'vinix.persist=', 'vinix.root', 'root=']

pub struct InvalidBundle {
pub:
	message string
}

pub fn (e InvalidBundle) msg() string { return e.message }

pub fn (e InvalidBundle) code() int { return 0 }

fn invalid(message string) IError { return InvalidBundle{message} }

pub struct FileError {
pub:
	message  string
	number   int
	filename string
}

pub fn (e FileError) msg() string { return e.message }

pub fn (e FileError) code() int { return e.number }

fn file_error(path string) IError {
	number := int(C.errno)
	return FileError{os.get_error_msg(number), number, path}
}

// Python's buffered reader rejects a directory after inspecting the opened
// descriptor. Keep that error's pathname without a separate pathname check.
fn open_reader(path string) !os.File {
	mut stream := os.open(path) or { return file_error(path) }
	mut state := C.stat{}
	if C.fstat(i32(stream.fd), &state) != 0 {
		err := file_error('')
		stream.close()
		return err
	}
	if u32(state.st_mode) & u32(C.S_IFMT) == u32(C.S_IFDIR) {
		stream.close()
		return FileError{os.get_error_msg(C.EISDIR), int(C.EISDIR), path}
	}
	return stream
}

pub struct Architecture {
pub:
	pe_machine  u16
	elf_machine u16
	loader      string
}

pub fn architecture(name string) !Architecture {
	return match name {
		'x86_64' { Architecture{0x8664, 62, 'BOOTX64.EFI'} }
		'aarch64' { Architecture{0xaa64, 183, 'BOOTAA64.EFI'} }
		else { return error('KeyError: ' + name) }
	}
}

pub fn digest(path string) !string {
	mut stream := open_reader(path)!
	defer { stream.close() }
	mut hash := blake2b.new512()!
	mut buffer := []u8{len: 1024 * 1024}
	for {
		count := stream.read(mut buffer) or {
			if err is os.Eof { break }
			return file_error('')
		}
		if count == 0 { break }
		hash.write(buffer[..count])!
	}
	return hash.checksum().hex()
}

pub fn check_cmdline(value string, verity_token string) !string {
	if value.len > 2048 || !value.bytes().all((it >= `a` && it <= `z`)
		|| (it >= `A` && it <= `Z`) || (it >= `0` && it <= `9`) || it in [`_`, `.`, `,`, `=`, `+`,
		`:`, `/`, ` `, `-`]) {
		return invalid('command line must contain literal ASCII tokens (at most 2048 bytes)')
	}
	for option in disk_options {
		if value.contains(option) {
			return invalid('verified initramfs profile forbids disk root and persistence selectors')
		}
	}
	if verity_token != '' {
		verityimage.parse_command_line(verity_token) or { return invalid(err.msg()) }
		tokens := value.split(' ').filter(it != '')
		if tokens.len == 0 || tokens.last() != verity_token || tokens.filter(it == verity_token).len != 1 || tokens[..tokens.len - 1].join(' ').contains('vinix.verity') {
			return invalid('verified root policy must contain exactly one generated final token')
		}
	} else if value.contains('vinix.verity') {
		return invalid('verified block roots require the explicit --verity-root options')
	}
	return value.trim(' ')
}

fn word16(data []u8, offset u64) !u16 {
	if offset > u64(data.len) || u64(data.len) - offset < 2 {
		return invalid('truncated PE executable')
	}
	return u16(data[int(offset)]) | (u16(data[int(offset) + 1]) << 8)
}

fn word32(data []u8, offset u64) !u32 {
	if offset > u64(data.len) || u64(data.len) - offset < 4 {
		return invalid('truncated PE executable')
	}
	return u32(data[int(offset)]) | (u32(data[int(offset) + 1]) << 8) |
		(u32(data[int(offset) + 2]) << 16) | (u32(data[int(offset) + 3]) << 24)
}

fn equal_at(data []u8, offset u64, expected []u8) bool {
	return offset <= u64(data.len) && u64(data.len) - offset >= u64(expected.len)
		&& data[int(offset)..int(offset) + expected.len] == expected
}

fn find_bytes(data []u8, needle []u8, start int) ?int {
	if start < 0 || needle.len > data.len { return none }
	for index in start .. data.len - needle.len + 1 {
		if data[index..index + needle.len] == needle { return index }
	}
	return none
}

pub struct PE {
pub:
	field          u64
	signature_size u32
}

pub fn pe_info(data []u8, arch string) !PE {
	if !equal_at(data, 0, 'MZ'.bytes()) { return invalid('loader is not a PE executable') }
	pe := u64(word32(data, 0x3c)!)
	if !equal_at(data, pe, 'PE\x00\x00'.bytes()) { return invalid('invalid PE signature') }
	machine := word16(data, pe + 4)!
	sections := word16(data, pe + 6)!
	optional_size := u64(word16(data, pe + 20)!)
	optional := pe + 24
	if machine != architecture(arch)!.pe_machine || word16(data, optional)! != 0x20b {
		return invalid('loader architecture does not match the requested architecture')
	}
	if word16(data, optional + 68)! != 10 { return invalid('loader is not an EFI application') }
	if optional_size < 152 || word32(data, optional + 108)! < 5 {
		return invalid('PE has no certificate data directory')
	}
	certificate := u64(word32(data, optional + 144)!)
	certificate_size := word32(data, optional + 148)!
	if (certificate != 0) != (certificate_size != 0) || certificate + certificate_size > u64(data.len) {
		return invalid('invalid PE certificate directory')
	}
	mut locations := []int{}
	mut position := 0
	for position < data.len {
		found := find_bytes(data, config_marker.bytes(), position) or { break }
		locations << found
		position = found + config_marker.len
	}
	if locations.len != 1 {
		return invalid('loader must contain exactly one Limine config hash field')
	}
	start := u64(locations[0] + config_marker.len)
	if start > u64(data.len) || u64(data.len) - start < 128
		|| !data[int(start)..int(start) + 128].all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`) || (it >= `A` && it <= `F`)) {
		return invalid('invalid Limine config hash field')
	}
	mut mapped := false
	for index in 0 .. int(sections) {
		section := optional + optional_size + u64(index) * 40
		size := u64(word32(data, section + 16)!)
		offset := u64(word32(data, section + 20)!)
		if offset + size > u64(data.len) { return invalid('truncated PE section') }
		if offset <= u64(locations[0]) && start + 128 <= offset + size { mapped = true }
	}
	if !mapped || (certificate != 0 && u64(locations[0]) < certificate + certificate_size && start + 128 > certificate) {
		return invalid('Limine config hash field must be in a signed, mapped PE section')
	}
	loader_arch := if arch == 'x86_64' { 'x86-64' } else { arch }
	label := 'Limine 12.8.0 (${loader_arch}, UEFI)'
	find_bytes(data, label.bytes(), 0) or { return invalid('a trusted Limine 12.8.0 loader is required') }
	return PE{start, certificate_size}
}

pub fn check_kernel(path string, arch string) ! {
	mut stream := open_reader(path)!
	defer { stream.close() }
	mut header := []u8{len: 64}
	mut used := 0
	for used < 64 {
		count := stream.read(mut header[used..]) or {
			if err is os.Eof { break }
			return file_error('')
		}
		if count == 0 { break }
		used += count
	}
	if used != 64 || !equal_at(header, 0, '\x7fELF\x02\x01'.bytes()) || word16(header, 18)! != architecture(arch)!.elf_machine {
		return invalid('kernel must be a little-endian ELF64 image for the requested architecture')
	}
}

pub fn config_text(kernel_hash string, module_hashes []string, cmdline string, dtb_hash string, verity_token string) !string {
	mut lines := ['timeout: 0', 'verbose: yes', 'serial: yes', 'editor_enabled: no',
		'hash_mismatch_panic: yes', '', '/Vinix verified initramfs', '    protocol: limine',
		'    path: boot():/boot/vinix#${kernel_hash}',
		'    cmdline: ${check_cmdline(cmdline, verity_token)!}', '    resolution: 1024x768x32',
		'    kaslr: yes']
	for index, hash in module_hashes {
		lines << '    module_path: boot():/boot/root-${index}.tar#${hash}'
	}
	if dtb_hash != '' { lines << '    dtb_path: boot():/boot/platform.dtb#${dtb_hash}' }
	return lines.join('\n') + '\n'
}

pub fn regular_file(path string) !string {
	if os.is_link(path) || !os.is_file(path) {
		return invalid('bundle file is missing, not regular, or a symlink: ${path}')
	}
	return path
}
