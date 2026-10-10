// SPDX-License-Identifier: GPL-2.0-or-later
module winepatch

import crypto.sha256
import encoding.hex
import hosttest
import json2
import os

fn put(mut data []u8, offset int, value u64, width int) {
	for index in 0 .. width { data[offset + index] = u8(value >> (index * 8)) }
}

fn store(mut data []u8, offset int, bytes []u8) {
	for index, value in bytes { data[offset + index] = value }
}

fn msxml(width int) []u8 {
	mut data := []u8{len: 1024, init: 0xcc}
	store(mut data, 0, 'MZ'.bytes())
	put(mut data, 0x3c, 0x80, 4)
	store(mut data, 0x80, 'PE\x00\x00'.bytes())
	put(mut data, 0x86, 1, 2)
	size := if width == 4 { 0xe0 } else { 0xf0 }
	put(mut data, 0x94, u64(size), 2)
	put(mut data, 0x98, if width == 4 { u64(0x10b) } else { u64(0x20b) }, 2)
	base := if width == 4 { u64(0x400000) } else { u64(0x140000000) }
	put(mut data, 0x98 + if width == 4 { 28 } else { 24 }, base, width)
	section := 0x98 + size
	put(mut data, section + 12, 0x1000, 4)
	put(mut data, section + 16, 0x200, 4)
	put(mut data, section + 20, 0x200, 4)
	store(mut data, 0x240, 'UTF-16LE\x00UTF-16BE\x00'.bytes())
	store(mut data, 0x280, 'ISO-8859-16\x00'.bytes())
	put(mut data, 0x300, base + 0x1040, width)
	put(mut data, 0x340, base + 0x1080, width)
	for index in 0 .. 2 * width {
		data[0x300 + width + index] = u8(0xa0 + index)
		data[0x340 + width + index] = u8(0xb0 + index)
	}
	return data
}

fn test_msxml_pe32_and_pe64_copy_only_alias_and_two_converter_pointers() {
	for width in [4, 8] {
		mut data := msxml(width)
		mut expected := data.clone()
		store(mut expected, 0x280, 'UNICODE\x00\x00\x00\x00\x00'.bytes())
		store(mut expected, 0x340 + width, data[0x300 + width..0x300 + 3 * width])
		assert unicode_handler(mut data)! == false
		assert data == expected
		assert unicode_handler(mut data)! == true
		assert data == expected
		data[0x340 + width] ^= 1
		unicode_handler(mut data) or {
			assert err.msg() == 'MSXML unicode alias has unexpected converter pointers'
			continue
		}
		assert false, 'accepted corrupt patched converters'
	}
}

fn test_msxml_rejects_ambiguous_strings_references_and_bad_sections_without_mutation() {
	for width in [4, 8] {
		for fault in 0 .. 8 {
			mut data := msxml(width)
			match fault {
				0 { store(mut data, 0x200, 'UTF-16LE\x00UTF-16BE\x00'.bytes()) }
				1 { store(mut data, 0x200, 'ISO-8859-16\x00'.bytes()) }
				2 { store(mut data, 0x200, 'UNICODE\x00\x00\x00\x00\x00'.bytes()) }
				3 { data[0x300] ^= 1 }
				4 { store(mut data, 0x380, data[0x300..0x300 + width].clone()) }
				5 { data[0x340] ^= 1 }
				6 { put(mut data, 0x98 + if width == 4 { 0xe0 } else { 0xf0 } + 20, 0x10000, 4) }
				else {
					pointer := data[0x300..0x300 + width].clone()
					data[0x300] ^= 1
					store(mut data, data.len - width, pointer)
				}
			}
			before := data.clone()
			unicode_handler(mut data) or {
				assert data == before
				continue
			}
			assert false, 'accepted MSXML fault ${fault}, width ${width}'
		}
	}
}

fn test_pe_truncation_pointer_width_and_address_overflow_are_bounded() {
	for width in [4, 8] {
		fixture := msxml(width)
		for length in 0 .. 0x290 {
			mut data := fixture[..length].clone()
			unicode_handler(mut data) or { continue }
			assert false, 'accepted truncated PE length ${length}'
		}
		mut data := fixture.clone()
		put(mut data, 0x98 + if width == 4 { 28 } else { 24 }, if width == 4 {
			u64(0xfffffff0)
		} else {
			~u64(0) - 3
		}, width)
		unicode_handler(mut data) or { continue }
		assert false, 'accepted overflowing PE address'
	}
	mut data := msxml(4)
	put(mut data, 0x3c, 0xffffffff, 4)
	layout(data) or { return }
	assert false, 'accepted overflowing header offset'
}

fn test_service_timeout_unique_signature_and_idempotence() {
	mut data := hex.decode('0102c0d4010060ea0000102700000304')!
	assert service_timeout(mut data)! == false
	assert hex.encode(data) == '0102c0d4010060ea000060ea00000304'
	assert service_timeout(mut data)! == true
	for text in ['', 'c0d4010060ea000010270000c0d4010060ea000010270000',
		'c0d4010060ea000060ea0000c0d4010060ea000060ea0000',
		'c0d4010060ea000010270000c0d4010060ea000060ea0000'] {
		mut invalid := hex.decode(text)!
		before := invalid.clone()
		service_timeout(mut invalid) or {
			assert invalid == before
			continue
		}
		assert false, 'accepted ambiguous service globals'
	}
}

fn test_fixed_sites_allow_partial_updates_and_validate_the_last_site_before_mutation() {
	patches := [Patch{2, [u8(2), 3], [u8(20), 30]}, Patch{7, [u8(7), 8], [u8(70), 80]}]
	for partial in [false, true] {
		mut data := [u8(0), 1, 2, 3, 4, 5, 6, 7, 8, 9]
		if partial { store(mut data, 2, [u8(20), 30]) }
		exact(mut data, patches)!
		assert data == [u8(0), 1, 20, 30, 4, 5, 6, 70, 80, 9]
		exact(mut data, patches)!
		assert data == [u8(0), 1, 20, 30, 4, 5, 6, 70, 80, 9]
	}
	for data in [[u8(0), 1, 2, 3, 4, 5, 6, 0, 8, 9], [u8(0), 1, 2, 3, 4]] {
		mut invalid := data.clone()
		exact(mut invalid, patches) or {
			assert invalid == data
			continue
		}
		assert false, 'accepted invalid final site'
	}
}

fn test_atomic_replacement_modes_hardlinks_symlinks_and_publication_cleanup() {
	work := hosttest.work_dir('', 'vinix-wine-files-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	path := work + '/services.exe'
	old := hex.decode('01c0d4010060ea00001027000002')!
	new := hex.decode('01c0d4010060ea000060ea000002')!
	for mode in [0o644, 0o751, 0o6751] {
		os.write_file_array(path, old)!
		os.chmod(path, mode)!
		// The filesystem can clear a requested setgid bit when the process
		// does not belong to the file's group. Preserve the actual source mode.
		original_mode := int(os.stat(path)!.mode) & 0o7777
		inode := os.stat(path)!.inode
		assert patch_file('wine-service-timeout', path)!.starts_with('extended translated-service')
		assert os.read_bytes(path)! == new
		assert int(os.stat(path)!.mode) & 0o7777 == original_mode
		assert os.stat(path)!.inode != inode
		patched_inode := os.stat(path)!.inode
		assert patch_file('wine-service-timeout', path)!.starts_with('translated-service timeout already')
		assert os.stat(path)!.inode == patched_inode
	}
	os.write_file_array(path, old)!
	for linked in [work + '/hard.exe', work + '/symbolic.exe'] {
		if linked.ends_with('hard.exe') {
			os.link(path, linked)!
		} else {
			os.symlink(path, linked)!
		}
		patch_file('wine-service-timeout', linked)!
		assert os.read_bytes(linked)! == new && os.read_bytes(path)! == old && !os.is_link(linked)
	}
	directory := work + '/directory'
	os.mkdir(directory)!
	os.write_file(directory + '/keep', 'unchanged')!
	replace_file(directory, new, 0o755) or {
		assert os.read_file(directory + '/keep')! == 'unchanged'
		assert os.ls(directory)! == ['keep']
		assert os.ls(work)!.all(!it.starts_with('.vinix-wine-patch-'))
		return
	}
	assert false, 'published a file inside the directory destination'
}

fn test_repeated_failure_and_success_leave_descriptors_and_temporary_files_flat() {
	work := hosttest.work_dir('', 'vinix-wine-resources-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	path := work + '/services.exe'
	old := hex.decode('c0d4010060ea000010270000')!
	before := os.ls('/dev/fd')!.len
	for _ in 0 .. 100 {
		os.write_file_array(path, old)!
		patch_file('wine-service-timeout', path)!
		patch_file('wine-service-timeout', path)!
		os.write_file(path, 'invalid')!
		patch_file('wine-service-timeout', path) or { continue }
		assert false, 'accepted bad service image'
	}
	assert os.ls('/dev/fd')!.len == before
	assert os.ls(work)! == ['services.exe']
}

fn test_cached_alpine_wine_payloads_match_previously_staged_images_in_full() {
	root := os.getenv('VINIX_WINEPATCH_REPO')
	if root == '' { return }
	work := hosttest.work_dir('', 'vinix-wine-apks-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	build := root + '/build-aarch64-x86-translation'
	hashes := json2.decode[map[string]string](os.read_file(os.join_path(os.dir(@FILE), 'reference_hashes.json'))!)!
	for arch in ['x86', 'x86_64'] {
		path := 'downloads/${arch}_wine-9.17-r1.apk'
		assert sha256.sum(os.read_bytes(build + '/' + path)!).hex() == hashes[path], 'cached APK differs from qualified input'
	}
	for row in [
		['wine-x86_64-qemu', 'x86_64', 'x86_64-unix/ntdll.so'],
		['wine-i386-qemu', 'x86', 'i386-unix/ntdll.so'],
		['wine-x86_64-context', 'x86_64', 'x86_64-windows/ntdll.dll'],
		['msxml-unicode', 'x86_64', 'x86_64-windows/msxml3.dll'],
		['msxml-unicode', 'x86', 'i386-windows/msxml3.dll'],
		['wine-service-timeout', 'x86_64', 'x86_64-windows/services.exe'],
		['wine-service-timeout', 'x86', 'i386-windows/services.exe'],
	] {
		member := 'usr/lib/wine/' + row[2]
		archive := build + '/downloads/${row[1]}_wine-9.17-r1.apk'
		target := work + '/${row[0]}-${row[1]}'
		result := hosttest.capture(['/bin/sh', '-c', 'exec tar -xOf "$1" "$2" > "$3"', 'sh', archive,
			member, target], '', 60, os.environ())!
		assert result.code == 0, result.stderr
		original := os.read_bytes(target)!
		patch_file(row[0], target)!
		expected_root := if row[1] == 'x86' { 'vinix-i386' } else { 'vinix-x86_64' }
		expected_path := 'staging/usr/libexec/${expected_root}/root/' + member
		expected := os.read_bytes(build + '/' + expected_path)!
		assert sha256.sum(expected).hex() == hashes[expected_path], 'cached reference differs from qualified output'
		assert os.read_bytes(target)! == expected, '${row[0]} ${row[1]} differs from staged image'
		patch_file(row[0], target)!
		assert os.read_bytes(target)! == expected
		// Reject a changed package before replacing the original path or inode.
		os.write_file_array(target, original[..int_min(100, original.len)])!
		inode := os.stat(target)!.inode
		patch_file(row[0], target) or {
			assert os.stat(target)!.inode == inode
			assert os.read_bytes(target)! == original[..int_min(100, original.len)]
			continue
		}
		assert false, 'accepted truncated production image'
	}
}

fn test_native_commands_status_and_success_output() {
	directory := os.getenv('VINIX_WINEPATCH_BIN')
	if directory == '' { return }
	work := hosttest.work_dir('', 'vinix-wine-cli-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	for kind in ['wine-x86_64-qemu', 'wine-i386-qemu', 'wine-x86_64-context', 'msxml-unicode',
		'wine-service-timeout'] {
		tool := directory + '/patch-' + kind
		for args in [[]string{}, ['one', 'two']] {
			mut command := [tool]
			command << args
			result := hosttest.capture(command, '', 30, os.environ())!
			assert result.code == 2 && result.stdout == '' && result.stderr.starts_with('usage: patch-${kind} ')
		}
		missing := hosttest.capture([tool, work + '/absent'], '', 30, os.environ())!
		assert missing.code == 1 && missing.stdout == '' && missing.stderr != ''
	}
	path := work + '/services.exe'
	os.write_file_array(path, hex.decode('c0d4010060ea000010270000')!)!
	first := hosttest.capture([directory + '/patch-wine-service-timeout', path], '', 30, os.environ())!
	assert first.code == 0 && first.stderr == '' && first.stdout == 'extended translated-service startup timeout: ${path}\n'
	second := hosttest.capture([directory + '/patch-wine-service-timeout', path], '', 30, os.environ())!
	assert second.code == 0 && second.stderr == '' && second.stdout == 'translated-service timeout already extended: ${path}\n'
}
