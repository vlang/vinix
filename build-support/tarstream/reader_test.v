// SPDX-License-Identifier: GPL-2.0-only
module tarstream

import crypto.sha256
import os
import tarcore

#include <stdlib.h>

fn C.mkdtemp(&char) &char

fn temporary_directory() !string {
	mut pattern := (os.temp_dir() + '/vinix-tarstream-XXXXXX\x00').bytes()
	unsafe {
		path := C.mkdtemp(&char(pattern.data))
		if path == nil { return error('cannot create test directory') }
		return path.vstring().clone()
	}
}

fn pax_record(key string, value string) string {
	mut length := key.len + value.len + 4
	for {
		record := '${length} ${key}=${value}\n'
		if record.len == length { return record }
		length = record.len
	}
}

fn test_pax_global_local_gnu_extensions_and_exact_unicode() {
	work := temporary_directory()!
	defer { os.rmdir_all(work) or { panic(err) } }
	path := work + '/pax.tar'
	mut writer := tarcore.create(path)!
	globals := (pax_record('uid', '42') + pax_record('gname', 'global group')).bytes()
	writer.add(tarcore.Member{ name: 'global', kind: `g`, size: globals.len }, globals)!
	local := (pax_record('path', 'usr/lib/e\u0301.so') + pax_record('uid', '73') + pax_record('mtime', '123.75') + pax_record('size', '3')).bytes()
	writer.add(tarcore.Member{ name: 'local', kind: `x`, size: local.len }, local)!
	writer.write(tarcore.header(tarcore.Member{ name: 'unused', size: 0 })!)!
	writer.write('abc'.bytes())!
	writer.padding(3)!
	long_name := ('usr/share/' + 'folder/'.repeat(15) + 'data\x00').bytes()
	writer.add(tarcore.Member{ name: '././@LongLink', kind: `L`, size: long_name.len }, long_name)!
	long_link := 'target\x00'.bytes()
	writer.add(tarcore.Member{ name: '././@LongLink', kind: `K`, size: long_link.len }, long_link)!
	writer.add(tarcore.Member{ name: 'short', kind: `2` }, []u8{})!
	writer.add(tarcore.Member{ name: 'after', size: 0 }, []u8{})!
	writer.finish()!
	writer.close()
	mut reader := open(path)!
	defer { reader.close() }
	first := reader.next()!
	assert first.name == 'usr/lib/e\u0301.so' && first.uid == 73 && first.gname == 'global group'
	assert first.mtime == 123 && first.size == 3
	mut buffer := []u8{len: 2}
	assert reader.read(mut buffer)! == 2 && buffer.bytestr() == 'ab'
	assert reader.read(mut buffer)! == 1 && buffer[0] == `c`
	assert reader.read(mut buffer)! == 0
	second := reader.next()!
	assert second.name == long_name.bytestr().all_before('\x00')
	assert second.linkname == 'target' && second.uid == 42 && second.kind == `2`
	assert reader.next()!.name == 'after'
	reader.next() or {
		assert err is End
		return
	}
	assert false
}

fn test_streaming_digest_and_skip_around_chunk_boundaries() {
	work := temporary_directory()!
	defer { os.rmdir_all(work) or { panic(err) } }
	path := work + '/stream.tar'
	data := []u8{len: 1024 * 1024 + 777, init: u8(index * 67)}
	mut writer := tarcore.create(path)!
	writer.add(tarcore.Member{ name: 'skipped', size: data.len }, data)!
	writer.add(tarcore.Member{ name: 'hashed', size: data.len }, data)!
	writer.add(tarcore.Member{ name: 'empty' }, []u8{})!
	writer.finish()!
	writer.close()
	mut reader := open(path)!
	defer { reader.close() }
	assert reader.next()!.name == 'skipped'
	assert reader.next()!.name == 'hashed'
	assert reader.digest()! == sha256.hexhash(data.bytestr())
	assert reader.next()!.name == 'empty'
	assert reader.digest()! == 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
}

fn test_descriptor_skips_unread_and_partly_read_members_with_padding() {
	work := temporary_directory()!
	defer { os.rmdir_all(work) or { panic(err) } }
	path := work + '/skips.tar'
	sizes := [1, 511, 512, 513, 1024 * 1024 - 1, 1024 * 1024, 1024 * 1024 + 1]
	data := []u8{len: 1024 * 1024 + 1, init: u8(index * 67)}
	mut writer := tarcore.create_stream(path)!
	for index, size in sizes {
		writer.add(tarcore.Member{ name: 'member-${index}', size: size }, data[..size])!
	}
	writer.add(tarcore.Member{ name: 'after', size: 5 }, 'after'.bytes())!
	writer.finish()!
	writer.close_checked()!
	mut file := os.open(path)!
	defer { file.close() }
	mut reader := from_descriptor(file.fd)!
	defer { reader.close() }
	mut prefix := []u8{len: 17}
	for index, size in sizes {
		member := reader.next()!
		assert member.name == 'member-${index}' && member.size == size
		if index % 2 == 1 {
			assert reader.read(mut prefix)! == prefix.len
			assert prefix == data[..prefix.len]
		}
	}
	assert reader.next()!.name == 'after'
	mut tail := []u8{len: 5}
	assert reader.read(mut tail)! == tail.len && tail == 'after'.bytes()
	mut ended := false
	reader.next() or { assert err is End; ended = true }
	assert ended
}

fn test_concatenated_tar_streams_continue_beyond_end_markers() {
	work := temporary_directory()!
	defer { os.rmdir_all(work) or { panic(err) } }
	mut bytes := []u8{}
	for name in ['signature', 'control', 'payload'] {
		path := work + '/' + name + '.tar'
		mut writer := tarcore.create(path)!
		writer.add(tarcore.Member{name: name, size: name.len}, name.bytes())!
		writer.finish()!
		writer.close()
		bytes << os.read_bytes(path)!
	}
	path := work + '/concatenated.tar'
	os.write_file_array(path, bytes)!
	mut normal := open(path)!
	defer { normal.close() }
	assert normal.next()!.name == 'signature'
	mut normal_ended := false
	normal.next() or { assert err is End; normal_ended = true }
	assert normal_ended
	mut reader := open_concatenated(path)!
	defer { reader.close() }
	assert reader.next()!.name == 'signature'
	// Leave this member unread, and partially read the next member.
	assert reader.next()!.name == 'control'
	mut buffer := []u8{len: 2}
	assert reader.read(mut buffer)! == 2 && buffer.bytestr() == 'co'
	assert reader.next()!.name == 'payload'
	assert reader.digest()! == sha256.hexhash('payload')
	mut ended := false
	reader.next() or { assert err is End; ended = true }
	assert ended
	// A physical short header after an otherwise complete stream is invalid.
	bytes << [u8(1), 2, 3]
	os.write_file_array(work + '/truncated.tar', bytes)!
	mut broken := open_concatenated(work + '/truncated.tar')!
	defer { broken.close() }
	for _ in 0 .. 3 { broken.next()! }
	mut refused := false
	broken.next() or { assert err !is End; refused = true }
	assert refused
}

fn test_numeric_fields_and_header_errors() {
	mut data := []u8{len: 12, init: 255}
	assert number(data, 0, 12)! == -1
	data[11] = 254
	assert number(data, 0, 12)! == -2
	data = []u8{len: 12}
	data[0] = 0x80
	data[11] = 42
	assert number(data, 0, 12)! == 42
	data[1] = 1
	expect_number_error(data)
	mut header := tarcore.header(tarcore.Member{ name: 'a' })!
	header[0] = `b`
	parse_header(header) or {
		assert err.msg().contains('checksum')
		return
	}
	assert false
}

fn expect_number_error(data []u8) {
	number(data, 0, data.len) or {
		assert err.msg().contains('too large')
		return
	}
	assert false
}

fn test_malformed_pax_sparse_and_truncated_input() {
	for bad in ['10 abc=x\n', '0 x=y\n', '12 =valuexx\n', '999 x=y\n',
		pax_record('GNU.sparse.map', '0,1')] {
		parse_pax(bad.bytes()) or { continue }
		assert false, bad
	}
	work := temporary_directory()!
	defer { os.rmdir_all(work) or { panic(err) } }
	path := work + '/bad.tar'
	for data in [tarcore.header(tarcore.Member{ name: 'file', size: 4096 })!, 'not a tar'.bytes()] {
		os.write_file_array(path, data)!
		mut reader := open(path)!
		reader.next() or {
			reader.close()
			continue
		}
		reader.digest() or {
			reader.close()
			continue
		}
		reader.close()
		assert false
	}
}
