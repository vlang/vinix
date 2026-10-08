// The original three offline archive-integrity scenarios, in native V.
module upstreamsource

import os
import json2
import strconv
import hosttest

struct Member {
	name     string
	contents string
}

fn field(mut block []u8, start int, width int, text string) {
	assert text.len <= width
	for index, byte in text.bytes() { block[start + index] = byte }
}

fn octal(value u64, width int) string {
	text := strconv.format_uint(value, 8)
	assert text.len < width
	return '0'.repeat(width - text.len - 1) + text + '\x00'
}

// A POSIX regular-member fixture. Header/data bytes are independent of the
// importer; the original Python control supplies the same TarInfo fields.
fn fixture_archive(base string, members []Member) ! {
	mut bytes := []u8{}
	for member in members {
		mut block := []u8{len: 512}
		field(mut block, 0, 100, 'linux-test/' + member.name)
		field(mut block, 100, 8, octal(0o644, 8))
		field(mut block, 108, 8, octal(0, 8))
		field(mut block, 116, 8, octal(0, 8))
		field(mut block, 124, 12, octal(u64(member.contents.len), 12))
		field(mut block, 136, 12, octal(0, 12))
		field(mut block, 148, 8, '        ')
		block[156] = `0`
		field(mut block, 257, 6, 'ustar\x00')
		field(mut block, 263, 2, '00')
		field(mut block, 329, 8, octal(0, 8))
		field(mut block, 337, 8, octal(0, 8))
		mut checksum := u64(0)
		for byte in block { checksum += byte }
		field(mut block, 148, 8, octal(checksum, 7) + ' ')
		bytes << block
		bytes << member.contents.bytes()
		if member.contents.len % 512 != 0 { bytes << []u8{len: 512 - member.contents.len % 512} }
	}
	bytes << []u8{len: 1024}
	if bytes.len % 10240 != 0 { bytes << []u8{len: 10240 - bytes.len % 10240} }
	source := os.join_path(base, 'fixture.tar')
	os.write_file_array(source, bytes)!
	defer { os.rm(source) or {} }
	compressed := hosttest.command([hosttest.tool('xz'), '-c', source], '', -1, os.environ())!
	os.write_file_array(os.join_path(base, 'linux-test.tar.xz'), compressed.stdout.bytes())!
}

fn fixture_pin(base string) !map[string]json2.Any {
	return {
		'version':              json2.Any('test')
		'url':                  json2.Any('unused')
		'directories':          json2.Any(hosttest.strings(['driver/']))
		'files':                json2.Any([]json2.Any{})
		'excluded_directories': json2.Any([]json2.Any{})
		'sha256':               json2.Any(hosttest.file_digest(os.join_path(base, 'linux-test.tar.xz'))!)
	}
}

fn test_modifications_and_added_files_are_rejected() {
	base := hosttest.work_dir('', 'vinix-source-integrity-')!
	defer { os.rmdir_all(base) or {} }
	fixture_archive(base, [Member{'driver/a.c', 'unmodified\n'}, Member{'unwanted.c', 'excluded\n'}])!
	pin := fixture_pin(base)!
	root := fetch(base, pin)!
	assert !os.exists(os.join_path(root, 'unwanted.c'))
	hosttest.verify_upstream(root, pin)!
	file := os.join_path(root, 'driver/a.c')
	os.write_file(file, 'changed\n')!
	mut rejected := false
	hosttest.verify_upstream(root, pin) or {
		assert err.msg().contains('modified upstream source')
		rejected = true
	}
	assert rejected
	os.write_file(file, 'unmodified\n')!
	os.write_file(os.join_path(root, 'driver/extra.c'), 'extra\n')!
	rejected = false
	hosttest.verify_upstream(root, pin) or {
		assert err.msg().contains('file set changed')
		rejected = true
	}
	assert rejected
}

fn test_manifest_pin_rejects_rewritten_checksums() {
	base := hosttest.work_dir('', 'vinix-source-manifest-')!
	defer { os.rmdir_all(base) or {} }
	fixture_archive(base, [Member{'driver/a.c', 'unmodified\n'}, Member{'unwanted.c', 'excluded\n'}])!
	mut pin := fixture_pin(base)!
	root := fetch(base, pin)!
	manifest := os.join_path(root, '.vinix-upstream.json')
	pin['manifest_sha256'] = hosttest.file_digest(manifest)!
	file := os.join_path(root, 'driver/a.c')
	os.write_file(file, 'changed\n')!
	mut data := hosttest.decode_json(os.read_file(manifest)!)!.as_map()
	mut files := data['files']!.as_map()
	files['driver/a.c'] = hosttest.file_digest(file)!
	data['files'] = files
	os.write_file(manifest, json2.encode(data))!
	mut rejected := false
	hosttest.verify_upstream(root, pin) or {
		assert err.msg().contains('pinned manifest')
		rejected = true
	}
	assert rejected
}

fn test_path_escape_is_rejected() {
	base := hosttest.work_dir('', 'vinix-source-traversal-')!
	defer { os.rmdir_all(base) or {} }
	fixture_archive(base, [Member{'driver/../../outside.c', 'x'}])!
	pin := fixture_pin(base)!
	mut rejected := false
	fetch(base, pin) or {
		assert err.msg().contains('unsafe archive member')
		rejected = true
	}
	assert rejected
	assert !os.exists(os.join_path(base, 'outside.c'))
	assert !os.exists(os.join_path(base, 'linux-test'))
	assert !os.ls(base)!.any(it.starts_with('.extract-'))
}
