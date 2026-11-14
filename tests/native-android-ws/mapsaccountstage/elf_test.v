// SPDX-License-Identifier: GPL-2.0-or-later
module mapsaccountstage

import json2
import os

fn set16(mut bytes []u8, at int, value u16) {
	for index in 0 .. 2 { bytes[at + index] = u8(value >> (8 * index)) }
}

fn set64(mut bytes []u8, at int, value u64) {
	for index in 0 .. 8 { bytes[at + index] = u8(value >> (8 * index)) }
}

fn fixture() []u8 {
	mut bytes := []u8{len: 512}
	for index, value in [u8(0x7f), `E`, `L`, `F`, 2, 1, 1] { bytes[index] = value }
	set16(mut bytes, 16, 3)
	set16(mut bytes, 18, 183)
	bytes[20] = 1
	set64(mut bytes, 32, 64)
	set16(mut bytes, 52, 64)
	set16(mut bytes, 54, 56)
	set16(mut bytes, 56, 2)
	bytes[64] = 1
	set64(mut bytes, 64 + 16, 0x1000)
	set64(mut bytes, 64 + 32, 512)
	set64(mut bytes, 64 + 40, 512)
	bytes[120] = 2
	set64(mut bytes, 120 + 8, 192)
	set64(mut bytes, 120 + 16, 0x10c0)
	set64(mut bytes, 120 + 32, 80)
	set64(mut bytes, 192, 5)
	set64(mut bytes, 200, 0x1180)
	set64(mut bytes, 208, 10)
	set64(mut bytes, 216, 128)
	set64(mut bytes, 224, 1)
	set64(mut bytes, 232, 1)
	set64(mut bytes, 240, 14)
	set64(mut bytes, 248, 10)
	for index, value in '\x00libc.so\x00\x00libsample.so\x00'.bytes() { bytes[384 + index] = value }
	return bytes
}

fn test_dependency_and_soname() {
	parsed := inspect_elf(fixture())!
	assert parsed.needed == ['libc.so']
	assert parsed.soname == 'libsample.so'
	assert parsed.interpreter == ''
}

fn test_malformed_dynamic_inputs_rejected() {
	mut cases := [][]u8{}
	for at, value in {4: u64(1), 32: 500, 152: 79, 192: 15, 208: 5, 216: 99999,
		200: 0xfffffffffffffff0, 232: 128, 256: 1} {
		mut bytes := fixture()
		if at == 4 { bytes[4] = u8(value) } else { set64(mut bytes, at, value) }
		cases << bytes
	}
	mut path := fixture()
	path[385] = `/`
	cases << path
	mut unterm := fixture()
	for index in 385 .. 512 { unterm[index] = `x` }
	cases << unterm
	for bytes in cases {
		if _ := inspect_elf(bytes) { assert false, 'malformed ELF accepted' }
	}
}

fn test_static_and_wrong_interpreter() {
	mut bytes := fixture()
	set16(mut bytes, 56, 1)
	assert inspect_elf(bytes)!.needed.len == 0
	bytes = fixture()
	bytes[120] = 3
	set64(mut bytes, 120 + 8, 384)
	set64(mut bytes, 120 + 32, 9)
	if _ := inspect_elf(bytes) { assert false, 'unexpected interpreter accepted' }
}

fn test_dynamic_mapping_matches_loader() {
	for address in [u64(0), 0x10c8, 0xfffffffffffffff0] {
		mut bytes := fixture()
		set64(mut bytes, 120 + 16, address)
		if _ := inspect_elf(bytes) { assert false, 'unmapped or mismatched dynamic span accepted' }
	}
	for partial in [false, true] {
		mut overlap := fixture()
		// Move the table beyond all three program headers, then add an overlapping LOAD.
		table := overlap[192..272].clone()
		for index, value in table { overlap[256 + index] = value }
		set64(mut overlap, 128, 256)
		set64(mut overlap, 136, 0x1100)
		set16(mut overlap, 56, 3)
		for index in 176 .. 232 { overlap[index] = 0 }
		overlap[176] = 1
		set64(mut overlap, 176 + 16, if partial { u64(0x1120) } else { u64(0x1000) })
		set64(mut overlap, 176 + 32, if partial { u64(16) } else { u64(512) })
		set64(mut overlap, 176 + 40, if partial { u64(16) } else { u64(512) })
		if _ := inspect_elf(overlap) { assert false, 'ambiguous dynamic mapping accepted' }
	}
}

fn test_runpath_is_exposed_for_artifact_policy() {
	mut bytes := fixture()
	set64(mut bytes, 240, 29)
	assert inspect_elf(bytes)!.runpath == 'libsample.so'
}

fn art_fixture() []u8 {
	mut bytes := fixture()
	for index in 394 .. 407 { bytes[index] = 0 }
	for index, value in 'libart.so'.bytes() { bytes[394 + index] = value }
	set64(mut bytes, 80, 0x10000)
	set64(mut bytes, 112, 65536)
	set64(mut bytes, 136, 0x100c0)
	set64(mut bytes, 200, 0x10180)
	return bytes
}

fn test_art_page_shape_and_private_search_policy() {
	validate_art_library(art_fixture())!
	for alignment in [u64(0), 4096, 32769] {
		mut bytes := art_fixture()
		set64(mut bytes, 112, alignment)
		if _ := validate_art_library(bytes) { assert false, 'invalid page alignment accepted' }
	}
	mut mismatch := art_fixture()
	set64(mut mismatch, 112, 131072)
	if _ := validate_art_library(mismatch) { assert false, 'noncongruent segment accepted' }
	for wrong in [fixture(), art_fixture()[..63].clone()] {
		if _ := validate_art_library(wrong) { assert false, 'wrong or truncated ART input accepted' }
	}
	mut executable := art_fixture()
	set16(mut executable, 16, 2)
	if _ := validate_art_library(executable) { assert false, 'executable accepted as library' }
	for tag in [u64(15), 29] {
	for path in ['\$ORIGIN', '\${ORIGIN}', '/usr/lib', '../outside'] {
		mut search := art_fixture()
		set64(mut search, 152, 96)
		set64(mut search, 256, tag)
		set64(mut search, 264, 48)
		for index, value in path.bytes() { search[432 + index] = value }
		if tag == 15 {
			if _ := inspect_elf(search) { assert false, 'general ELF checker accepted legacy RPATH' }
		}
		if path.starts_with('\$') {
			validate_art_library(search)!
		} else {
			if _ := validate_art_library(search) { assert false, 'untrusted search path accepted' }
		}
	}
	}
	mut both := art_fixture()
	set64(mut both, 152, 112)
	set64(mut both, 256, 15)
	set64(mut both, 264, 48)
	set64(mut both, 272, 29)
	set64(mut both, 280, 48)
	for index, value in '\${ORIGIN}'.bytes() { both[432 + index] = value }
	if _ := validate_art_library(both) { assert false, 'ambiguous search policy accepted' }
}

fn test_art_staging_tracks_selected_bytes_and_refuses_overwrite() {
	root := os.join_path(os.temp_dir(), 'vinix-art-stage-${os.getpid()}')
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	source := root + '/libart.so'
	os.write_file_array(source, art_fixture())!
	mut inputs := {'unrelated': json2.Any('retained')}
	stage_art_library(source, root + '/payload', mut inputs)!
	assert digest(root + '/payload' + art_library_path)! == digest(source)!
	assert inputs[art_library_path]!.str() == digest(source)!
	assert inputs['unrelated']!.str() == 'retained'
	before := inputs.clone()
	original := digest(root + '/payload' + art_library_path)!
	mut replacement := art_fixture()
	replacement[340] = 99
	os.write_file_array(source, replacement)!
	if _ := stage_art_library(source, root + '/payload', mut inputs) {
		assert false, 'existing ART destination overwritten'
	}
	assert digest(root + '/payload' + art_library_path)! == original
	assert inputs == before
	os.symlink(source, root + '/alias')!
	if _ := stage_art_library(root + '/alias', root + '/symlink-rejected', mut inputs) {
		assert false, 'symlink source accepted'
	}
	assert !os.exists(root + '/symlink-rejected')
	os.write_file(root + '/oversized', '')!
	os.truncate(root + '/oversized', u64(129) * 1024 * 1024)!
	if _ := stage_art_library(root + '/oversized', root + '/size-rejected', mut inputs) {
		assert false, 'oversized source accepted'
	}
	assert !os.exists(root + '/size-rejected')
	os.write_file(source, 'invalid ELF')!
	if _ := stage_art_library(source, root + '/rejected', mut inputs) {
		assert false, 'invalid library staged'
	}
	assert !os.exists(root + '/rejected')
	assert inputs == before
}

fn test_art_supplied_real_library() {
	source := os.getenv_opt('VINIX_ART_TEST_LIBRARY') or { return }
	root := os.join_path(os.temp_dir(), 'vinix-art-real-stage-${os.getpid()}')
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	mut inputs := map[string]json2.Any{}
	stage_art_library(source, root, mut inputs)!
	assert inputs[art_library_path]!.str() == digest(source)!
	assert digest(root + art_library_path)! == digest(source)!
}
