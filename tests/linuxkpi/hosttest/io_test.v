// SPDX-License-Identifier: GPL-2.0-or-later
module hosttest

import os

fn test_module_streams_preserve_binary_bytes_across_buffer_boundaries() {
	work := work_dir('', 'vinix-module-io-') or { panic(err) }
	defer { remove_work_dir(work) or { panic(err) } }
	for length in [0, 8192, 8193, 65537] {
		bytes := []u8{len: length, init: u8(index % 251)}
		module_write(work + '/source', bytes.bytestr()) or { panic(err) }
		os.write_file(work + '/copy', 'old trailing bytes') or { panic(err) }
		module_copy_file(work + '/source', work + '/copy') or { panic(err) }
		assert os.read_bytes(work + '/source') or { panic(err) } == bytes
		assert os.read_bytes(work + '/copy') or { panic(err) } == bytes
	}
	os.write_file(work + '/copy', 'retained destination') or { panic(err) }
	module_copy_file(work + '/missing', work + '/copy') or {
		assert os.read_file(work + '/copy') or { panic(err) } == 'retained destination'
		return
	}
	assert false, 'missing source accepted'
}

fn test_bounds_publication_preserves_binary_bytes_and_retires_temporary_files() {
	work := work_dir('', 'vinix-bounds-io-') or { panic(err) }
	defer { remove_work_dir(work) or { panic(err) } }
	for length in [8193, 1, 0] {
		bytes := []u8{len: length, init: u8(index % 251)}
		bounds_publish(work + '/published', bytes) or { panic(err) }
		bounds_publish(work + '/published', bytes) or { panic(err) }
		assert os.read_bytes(work + '/published') or { panic(err) } == bytes
		assert os.ls(work) or { panic(err) } == ['published']
	}
}

fn test_archive_streams_read_complete_members_and_refuse_truncated_payloads() {
	work := work_dir('', 'vinix-archive-io-') or { panic(err) }
	defer { remove_work_dir(work) or { panic(err) } }
	os.mkdir(work + '/fixture') or { panic(err) }
	bytes := []u8{len: 65537, init: u8(index % 251)}
	os.write_file_array(work + '/fixture/payload', bytes) or { panic(err) }
	os.write_file(work + '/fixture/empty', '') or { panic(err) }
	mut env := os.environ(); env['COPYFILE_DISABLE'] = '1'
	result := command(['/usr/bin/tar', '--format=ustar', '-cf', work + '/input.tar', '-C', work, 'fixture'],
		'', 30, env) or { panic(err) }
	assert result.code == 0, result.stderr
	names := ['fixture/empty', 'fixture/payload']
	for ascii in [false, true] {
		members := if ascii {
			archive_ascii_members(work + '/input.tar', ['fixture/'], []string{}) or { panic(err) }
		} else { archive_members(work + '/input.tar', names) or { panic(err) } }
		assert members.len == 2
		assert members['fixture/payload'] == bytes
		assert members['fixture/empty'] == []u8{}
	}
	archive := os.read_bytes(work + '/input.tar') or { panic(err) }
	os.write_file_array(work + '/truncated.tar', archive[..2048]) or { panic(err) }
	for ascii in [false, true] {
		if ascii {
			archive_ascii_members(work + '/truncated.tar', ['fixture/'], []string{}) or { continue }
		} else { archive_members(work + '/truncated.tar', names) or { continue } }
		assert false, 'truncated archive accepted'
	}
}
