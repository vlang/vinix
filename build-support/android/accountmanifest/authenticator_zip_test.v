// SPDX-License-Identifier: GPL-2.0-or-later
module accountmanifest

import compress.deflate
import hash.crc32
import os
import rand

struct AuthZipTestMember {
	name                 string
	data                 []u8
	method               u16
	flags                u16
	descriptor           bool
	descriptor_signature bool
	trailing_compressed  []u8
}

struct AuthZipTestArchive {
mut:
	data        []u8
	locals      []int
	centrals    []int
	payloads    []int
	descriptors []int
	central     int
	end         int
}

fn az_put16(mut out []u8, value u16) {
	out << u8(value)
	out << u8(value >> 8)
}

fn az_put32(mut out []u8, value u32) {
	az_put16(mut out, u16(value))
	az_put16(mut out, u16(value >> 16))
}

fn az_set16(mut out []u8, at int, value u16) {
	out[at] = u8(value)
	out[at + 1] = u8(value >> 8)
}

fn az_set32(mut out []u8, at int, value u32) {
	az_set16(mut out, at, u16(value))
	az_set16(mut out, at + 2, u16(value >> 16))
}

// Build precisely controlled fixtures without opening or decoding another ZIP.
fn az_archive(members []AuthZipTestMember) !AuthZipTestArchive {
	mut archive := AuthZipTestArchive{}
	mut central := []u8{}
	defer { unsafe { central.free() } }
	for member in members {
		flags := member.flags | if member.descriptor { u16(8) } else { u16(0) }
		mut payload := if member.method == 8 {
			deflate.compress_raw(member.data)!
		} else {
			member.data.clone()
		}
		payload << member.trailing_compressed
		checksum := crc32.sum(member.data)
		local := archive.data.len
		archive.locals << local
		az_put32(mut archive.data, 0x04034b50)
		for value in [u16(20), flags, member.method, 0, 0] { az_put16(mut archive.data, value) }
		for value in [checksum, u32(payload.len), u32(member.data.len)] {
			az_put32(mut archive.data, if member.descriptor { u32(0) } else { value })
		}
		az_put16(mut archive.data, u16(member.name.len))
		az_put16(mut archive.data, 0)
		archive.data << member.name.bytes()
		archive.payloads << archive.data.len
		archive.data << payload
		archive.descriptors << archive.data.len
		if member.descriptor {
			if member.descriptor_signature { az_put32(mut archive.data, 0x08074b50) }
			for value in [checksum, u32(payload.len), u32(member.data.len)] {
				az_put32(mut archive.data, value)
			}
		}
		archive.centrals << central.len
		az_put32(mut central, 0x02014b50)
		for value in [u16(20), 20, flags, member.method, 0, 0] { az_put16(mut central, value) }
		for value in [checksum, u32(payload.len), u32(member.data.len)] {
			az_put32(mut central, value)
		}
		for value in [u16(member.name.len), 0, 0, 0, 0] { az_put16(mut central, value) }
		az_put32(mut central, 0)
		az_put32(mut central, u32(local))
		central << member.name.bytes()
		unsafe { payload.free() }
	}
	archive.central = archive.data.len
	for i in 0 .. archive.centrals.len { archive.centrals[i] += archive.central }
	archive.data << central
	archive.end = archive.data.len
	az_put32(mut archive.data, 0x06054b50)
	for value in [u16(0), 0, u16(members.len), u16(members.len)] {
		az_put16(mut archive.data, value)
	}
	az_put32(mut archive.data, u32(central.len))
	az_put32(mut archive.data, u32(archive.central))
	az_put16(mut archive.data, 0)
	return archive
}

fn az_read(data []u8, name string, limit u64) ![]u8 {
	path := os.join_path(os.temp_dir(), 'vinix-authenticator-zip-' + rand.uuid_v4() + '.apk')
	defer {
		os.rm(path) or {}
		unsafe { path.free() }
	}
	os.write_file_array(path, data)!
	mut file := os.open(path)!
	defer { file.close() }
	return read_authenticator_zip_entry(mut file, name, limit)
}

fn az_expect(data []u8, name string, limit u64, expected []u8) {
	actual := az_read(data, name, limit) or { panic(err) }
	defer { unsafe { actual.free() } }
	assert actual == expected
}

fn az_reject(data []u8, name string, limit u64) {
	if actual := az_read(data, name, limit) {
		unsafe { actual.free() }
		assert false, 'accepted malformed or oversized authenticator ZIP'
	}
}

fn test_authenticator_zip_stored_deflate_descriptors_and_lazy_repeated_selection() {
	plain := 'ordinary authenticator metadata payload'.repeat(32).bytes()
	for method in [u16(0), 8] {
		for descriptor in [false, true] {
			for signature in [false, true] {
				archive := az_archive([AuthZipTestMember{
					name:                 'res/xml/account.xml'
					data:                 plain
					method:               method
					descriptor:           descriptor
					descriptor_signature: signature
					flags:                0x800
				}])!
				az_expect(archive.data, 'res/xml/account.xml', u64(plain.len), plain)
			}
		}
	}
	mut archive := az_archive([
		AuthZipTestMember{ name: 'unrelated', data: plain, method: 8 },
		AuthZipTestMember{ name: 'AndroidManifest.xml', data: 'manifest payload'.bytes() },
		AuthZipTestMember{ name: 'resources.arsc', data: plain, method: 8 },
	])!
	// A corrupt unselected deflate stream must never be inflated.
	archive.data[archive.payloads[0]] = 0xff
	path := os.join_path(os.temp_dir(), 'vinix-authenticator-reopen-' + rand.uuid_v4() + '.apk')
	defer { os.rm(path) or {} }
	os.write_file_array(path, archive.data)!
	mut file := os.open(path)!
	defer { file.close() }
	for name in ['resources.arsc', 'AndroidManifest.xml', 'resources.arsc'] {
		actual := read_authenticator_zip_entry(mut file, name, 4096)!
		assert actual == if name == 'resources.arsc' { plain } else { 'manifest payload'.bytes() }
		unsafe { actual.free() }
	}
}

fn test_authenticator_zip_requires_unique_exact_name_and_complete_directory() {
	member := AuthZipTestMember{ name: 'AndroidManifest.xml', data: 'manifest payload'.bytes() }
	duplicate := az_archive([member, member])!
	az_reject(duplicate.data, member.name, 4096)
	nested := az_archive([AuthZipTestMember{ name: 'other/AndroidManifest.xml', data: member.data }])!
	az_reject(nested.data, member.name, 4096)
	mut suffix := az_archive([member, AuthZipTestMember{ name: 'after', data: member.data }])!
	suffix.data[suffix.centrals[1]] = 0
	az_reject(suffix.data, member.name, 4096)
	valid := az_archive([member])!
	for end in 0 .. valid.data.len { az_reject(valid.data[..end], member.name, 4096) }
	for field in [4, 6, 8, 10] {
		mut bad := valid.data.clone()
		az_set16(mut bad, valid.end + field, 2)
		az_reject(bad, member.name, 4096)
	}
	for field in [12, 16] {
		mut bad := valid.data.clone()
		az_set32(mut bad, valid.end + field, 0xffffffff)
		az_reject(bad, member.name, 4096)
	}
}

fn test_authenticator_zip_rejects_local_central_and_crc_disagreement() {
	name := 'res/xml/account.xml'
	valid := az_archive([AuthZipTestMember{ name: name, data: 'authenticator metadata'.bytes() }])!
	for local_field in [0, 6, 8, 14, 18, 22, 26, 28, 30] {
		mut bad := valid.data.clone()
		bad[local_field] ^= 1
		az_reject(bad, name, 4096)
	}
	for central_field in [0, 8, 10, 16, 20, 24, 28, 30, 32, 34, 42, 46] {
		mut bad := valid.data.clone()
		bad[valid.centrals[0] + central_field] ^= 1
		az_reject(bad, name, 4096)
	}
	mut wrong_crc := valid.data.clone()
	wrong_crc[14] ^= 1
	wrong_crc[valid.centrals[0] + 16] ^= 1
	az_reject(wrong_crc, name, 4096)
	mut overlap := valid.data.clone()
	az_set32(mut overlap, valid.centrals[0] + 42, u32(valid.central))
	az_reject(overlap, name, 4096)
}

fn test_authenticator_zip_rejects_size_flags_methods_and_deflate_expansion() {
	name := 'resources.arsc'
	plain := 'bounded metadata'.repeat(128).bytes()
	valid := az_archive([AuthZipTestMember{ name: name, data: plain }])!
	az_reject(valid.data, name, u64(plain.len - 1))
	az_reject(valid.data, name, 7)
	az_reject(valid.data, name, u64(128 * 1024 * 1024) + 1)
	az_reject(valid.data, '', 4096)
	for field in [20, 24, 42] {
		mut bad := valid.data.clone()
		az_set32(mut bad, valid.centrals[0] + field, 0xffffffff)
		az_reject(bad, name, 4096)
	}
	for advertised in [u32(4097), u32(valid.central), u32(0xfffffffe)] {
		mut bad := valid.data.clone()
		az_set32(mut bad, 18, advertised)
		az_set32(mut bad, valid.centrals[0] + 20, advertised)
		az_reject(bad, name, 4096)
	}
	for flags in [u16(1), 0x10, 0x20, 0x40, 0x2000] {
		mut bad := valid.data.clone()
		az_set16(mut bad, 6, flags)
		az_set16(mut bad, valid.centrals[0] + 8, flags)
		az_reject(bad, name, 4096)
	}
	mut method := valid.data.clone()
	az_set16(mut method, 8, 12)
	az_set16(mut method, valid.centrals[0] + 10, 12)
	az_reject(method, name, 4096)
	compressed := az_archive([AuthZipTestMember{ name: name, data: plain, method: 8 }])!
	for advertised in [u32(8), u32(plain.len - 1), u32(plain.len + 1), u32(0xffffffff)] {
		mut bad := compressed.data.clone()
		az_set32(mut bad, 22, advertised)
		az_set32(mut bad, compressed.centrals[0] + 24, advertised)
		az_reject(bad, name, 4096)
	}
	mut corrupt := compressed.data.clone()
	corrupt[compressed.payloads[0]] = 0xff
	az_reject(corrupt, name, 4096)
	trailing := az_archive([AuthZipTestMember{
		name:                name
		data:                plain
		method:              8
		trailing_compressed: [u8(0), 1, 2, 3]
	}])!
	az_reject(trailing.data, name, 4096)
}

fn test_authenticator_zip_rejects_bad_or_truncated_data_descriptors() {
	name := 'res/xml/account.xml'
	for signature in [false, true] {
		valid := az_archive([AuthZipTestMember{
			name:                 name
			data:                 'authenticator metadata'.bytes()
			method:               8
			descriptor:           true
			descriptor_signature: signature
		}])!
		start := valid.descriptors[0] + if signature { 4 } else { 0 }
		for field in [0, 4, 8] {
			mut bad := valid.data.clone()
			bad[start + field] ^= 1
			az_reject(bad, name, 4096)
		}
		// Retain a complete, correctly positioned directory after a short descriptor.
		mut short := valid.data[..valid.descriptors[0] + 7].clone()
		new_central := short.len
		short << valid.data[valid.central..]
		new_end := new_central + valid.end - valid.central
		az_set32(mut short, new_end + 16, u32(new_central))
		az_reject(short, name, 4096)
	}
}
