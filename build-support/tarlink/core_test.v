// SPDX-License-Identifier: GPL-2.0-only
module tarlink

import compress.gzip
import os
import tarcore
import tarstream

#include <stdlib.h>

fn C.mkdtemp(&char) &char

fn temporary_directory() !string {
	mut pattern := (os.temp_dir() + '/vinix-tarlink-XXXXXX\x00').bytes()
	unsafe {
		path := C.mkdtemp(&char(pattern.data))
		if path == nil { return error('cannot create test directory') }
		return path.vstring().clone()
	}
}

fn write_archive(path string, members []tarcore.Member, bodies [][]u8) ! {
	mut writer := tarcore.create(path)!
	defer { writer.close() }
	for index, member in members { writer.add(member, bodies[index])! }
	writer.finish()!
}

fn fixture(path string) ! {
	data := []u8{len: 4096, init: u8(index * 67)}
	mut members := []tarcore.Member{}
	mut bodies := [][]u8{}
	for name in ['usr/lib/a', 'usr/lib/b', './usr/lib/c', 'usr/share/d', './usr/share/e', 'bin/a',
		'usr/library/a'] {
		members << tarcore.Member{ name: name, size: data.len, mtime: 42, uname: 'owner', gname: 'group' }
		bodies << data
	}
	for name, property in {
		'usr/lib/mode': 'mode'
		'usr/lib/uid':  'uid'
		'usr/lib/gid':  'gid'
	} {
		mut member := tarcore.Member{ name: name, size: data.len }
		match property {
			'mode' { member.mode = 0o755 }
			'uid' { member.uid = 17 }
			'gid' { member.gid = 42 }
			else {}
		}
		members << member
		bodies << data
	}
	for name in ['usr/lib/small1', 'usr/lib/small2'] {
		members << tarcore.Member{ name: name, size: 4095 }
		bodies << data[..4095]
	}
	members << tarcore.Member{ name: 'usr/lib/changed-time', size: data.len, mtime: 99, uname: 'different' }
	bodies << data
	members << tarcore.Member{ name: 'symlink', kind: `2`, linkname: 'usr/lib/a' }
	bodies << []u8{}
	members << tarcore.Member{ name: 'original-link', kind: `1`, linkname: 'usr/lib/a' }
	bodies << []u8{}
	members << tarcore.Member{ name: 'dev/null', kind: `3`, major: 1, minor: 3 }
	bodies << []u8{}
	write_archive(path, members, bodies)!
}

struct Result {
	code int
	out  string
	err  string
}

fn invoke(tool string, args []string) Result {
	mut process := os.new_process(tool)
	process.set_args(args)
	process.set_redirect_stdio()
	process.run()
	process.wait()
	result := Result{process.code, process.stdout_slurp(), process.stderr_slurp()}
	process.close()
	return result
}

fn test_link_eligibility_metadata_and_verified_contents() {
	work := temporary_directory()!
	defer { os.rmdir_all(work) or { panic(err) } }
	src := work + '/input.tar'
	dst := work + '/output.tar'
	fixture(src)!
	expected := {
		'usr/lib/b':            'usr/lib/a'
		'./usr/lib/c':          'usr/lib/a'
		'usr/share/d':          'usr/lib/a'
		'./usr/share/e':        'usr/lib/a'
		'usr/lib/changed-time': 'usr/lib/a'
	}
	assert plan(src)! == expected
	stats := transform(src, dst)!
	assert stats.linked == 5 && stats.saved == 5 * 4096
	check(src, dst)!
	assert !os.exists(dst + '.tmp')
	mut archive := tarstream.open(dst)!
	defer { archive.close() }
	for {
		member := archive.next() or {
			if err is tarstream.End { break }
			panic(err)
		}
		if member.name in expected {
			assert member.kind == `1` && member.size == 0 && member.linkname == 'usr/lib/a'
		}
		if member.name == 'usr/lib/changed-time' {
			assert member.mtime == 99 && member.uname == 'different'
		}
		if member.name == 'dev/null' {
			assert member.kind == `3` && member.major == 1 && member.minor == 3
		}
	}
	if os.exists('/usr/bin/tar') {
		extract := work + '/extracted'
		os.mkdir(extract)!
		// Skip the device node; extraction needs no special privileges.
		result := invoke('/usr/bin/tar', ['-xf', dst, '-C', extract, '--exclude=dev/null'])
		assert result.code == 0, result.err
		first := os.stat(extract + '/usr/lib/a')!
		assert first.inode == os.stat(extract + '/usr/lib/b')!.inode
		assert first.inode == os.stat(extract + '/usr/share/d')!.inode
		assert first.inode != os.stat(extract + '/usr/lib/mode')!.inode
		assert os.read_bytes(extract + '/usr/lib/a')! == os.read_bytes(extract + '/bin/a')!
		assert os.readlink(extract + '/symlink')! == 'usr/lib/a'
	}
}

fn test_long_first_name_never_replaced_by_later_short_name() {
	work := temporary_directory()!
	defer { os.rmdir_all(work) or { panic(err) } }
	src := work + '/long.tar'
	data := []u8{len: 4096, init: 42}
	for first in ['usr/lib/' + 'a'.repeat(90) + '/file', 'usr/lib/' + 'e\u0301'.repeat(20),
		'usr/lib/' + 'e\u0301'.repeat(31)] {
		write_archive(src, [tarcore.Member{ name: first, size: data.len },
			tarcore.Member{ name: 'usr/lib/short', size: data.len },
			tarcore.Member{ name: 'usr/lib/third', size: data.len }], [data, data, data])!
		links := plan(src)!
		if first.runes().len > 100 {
			assert links.len == 0
		} else {
			assert links == {
				'usr/lib/short': first
				'usr/lib/third': first
			}
			if first.len <= 100 {
				assert transform(src, work + '/unicode.tar')!.linked == 2
			} else {
				expect_transform_error(src, work + '/unicode.tar', 'linkname is too long')
				assert !os.exists(work + '/unicode.tar.tmp')
			}
		}
	}
}

fn test_duplicate_names_and_transaction_failures_keep_destination() {
	work := temporary_directory()!
	defer { os.rmdir_all(work) or { panic(err) } }
	src := work + '/duplicate.tar'
	dst := work + '/output.tar'
	os.write_file(dst, 'old destination')!
	write_archive(src, [tarcore.Member{ name: 'same' }, tarcore.Member{ name: 'same' }], [
		[]u8{},
		[]u8{},
	])!
	expect_transform_error(src, dst, 'error: same appears twice; not linking anything')
	assert os.read_file(dst)! == 'old destination' && !os.exists(dst + '.tmp')
	// A representable GNU name whose basename cannot fit USTAR fails in rewrite.
	long := ('x'.repeat(101) + '\x00').bytes()
	write_archive(src, [
		tarcore.Member{ name: '././@LongLink', kind: `L`, size: long.len },
		tarcore.Member{ name: 'short' },
	], [long, []u8{}])!
	expect_transform_error(src, dst, 'name is too long')
	assert os.read_file(dst)! == 'old destination' && !os.exists(dst + '.tmp')
	fixture(src)!
	directory := work + '/destination-directory'
	os.mkdir(directory)!
	expect_transform_error(src, directory, 'cannot replace')
	assert os.is_dir(directory) && os.ls(directory)!.len == 0 && !os.exists(directory + '.tmp')
	// Source and destination may be the same: the input stays readable through
	// all verification passes and is replaced only after they finish.
	assert transform(src, src)!.linked == 5
	assert plan(src)!.len == 0
}

fn test_check_rejects_changed_content_and_forward_links() {
	work := temporary_directory()!
	defer { os.rmdir_all(work) or { panic(err) } }
	src := work + '/input.tar'
	dst := work + '/bad.tar'
	write_archive(src, [tarcore.Member{ name: 'a', size: 1 }], ['a'.bytes()])!
	write_archive(dst, [tarcore.Member{ name: 'a', size: 1 }], ['b'.bytes()])!
	expect_check_error(src, dst, 'error: output differs')
	write_archive(dst, [tarcore.Member{ name: 'a', kind: `1`, linkname: 'later' }], [[]u8{}])!
	expect_check_error(src, dst, 'error: a links to later, which comes later')
}

fn expect_transform_error(src string, dst string, expected string) {
	transform(src, dst) or {
		assert err.msg().starts_with(expected)
		return
	}
	assert false, 'expected transformation to fail'
}

fn expect_check_error(src string, dst string, expected string) {
	check(src, dst) or {
		assert err.msg().starts_with(expected)
		return
	}
	assert false, 'expected content check to fail'
}

fn test_plain_gzip_bzip2_xz_and_system_tar_pax_inputs() {
	work := temporary_directory()!
	defer { os.rmdir_all(work) or { panic(err) } }
	src := work + '/input.tar'
	fixture(src)!
	baseline := plan(src)!
	gz := src + '.gz'
	os.write_file_array(gz, gzip.compress(os.read_bytes(src)!)!)!
	assert plan(gz)! == baseline
	assert transform(gz, work + '/gzip.tar')!.linked == 5
	for name in ['bzip2', 'xz'] {
		tool := os.find_abs_path_of_executable(name) or { continue }
		result := invoke(tool, ['-c', src])
		assert result.code == 0
		compressed := work + '/input.' + name
		os.write_file(compressed, result.out)!
		assert plan(compressed)! == baseline
		assert transform(compressed, work + '/output.' + name + '.tar')!.linked == 5
	}
	if os.exists('/usr/bin/tar') {
		root := work + '/root'
		os.mkdir_all(root + '/usr/lib')!
		data := []u8{len: 8193, init: u8(index * 73)}
		for name in ['first', 'second'] { os.write_file_array(root + '/usr/lib/' + name, data)! }
		for format in ['ustar', 'pax', 'gnutar'] {
			archive := work + '/' + format + '.tar'
			result := invoke('/usr/bin/tar', ['--format=' + format, '-cf', archive, '-C', root,
				'usr/lib/first', 'usr/lib/second'])
			assert result.code == 0, result.err
			assert plan(archive)! == {
				'usr/lib/second': 'usr/lib/first'
			}
			assert transform(archive, work + '/' + format + '-out.tar')!.saved == 8193
		}
	}
}

fn test_native_command_status_and_saved_bytes() {
	tool := os.getenv('VINIX_TARLINK_TOOL')
	if tool == '' { return }
	work := temporary_directory()!
	defer { os.rmdir_all(work) or { panic(err) } }
	src := work + '/input.tar'
	dst := work + '/output.tar'
	fixture(src)!
	assert invoke(tool, [src, dst]) == Result{0, 'linked 5 repeated files, 0.0 MB stored once\n', ''}
	check(src, dst)!
	assert invoke(tool, []).code == 1
	assert invoke(tool, [work + '/missing', dst]).code == 1
	assert !os.exists(dst + '.tmp')
}

fn test_stored_megabytes_round_the_original_binary_float() {
	assert megabytes(50000) == '0.1'
	assert megabytes(150000) == '0.1'
	assert megabytes(1250000) == '1.2'
	assert megabytes(1350000) == '1.4'
}
