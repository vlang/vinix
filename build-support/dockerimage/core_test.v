// SPDX-License-Identifier: GPL-2.0-only
module dockerimage

import os
import strconv

#include <stdlib.h>

fn C.mkdtemp(&char) &char

fn temporary_directory() !string {
	mut pattern := (os.temp_dir() + '/vinix-dockerimage-XXXXXX\x00').bytes()
	unsafe {
		path := C.mkdtemp(&char(pattern.data))
		if path == nil { return error('cannot create test directory') }
		return path.vstring().clone()
	}
}

fn field(data []u8, offset int, size int) string {
	return data[offset..offset + size].bytestr().all_before('\x00')
}

fn number(data []u8, offset int, size int) i64 {
	return strconv.parse_int(field(data, offset, size).trim_space(), 8, 64) or { panic(err) }
}

// Check the raw archive against the original tool's fixed filesystem contract,
// independently of tarcore's reader and header construction.
fn check_archive(path string, busybox []u8) {
	data := os.read_bytes(path) or { panic(err) }
	mut names := []string{}
	mut pos := 0
	for pos + 512 <= data.len && data[pos..pos + 512].any(it != 0) {
		header := data[pos..pos + 512]
		name := field(header, 0, 100)
		names << name
		assert field(header, 257, 6) == 'ustar'
		assert header[263..265].bytestr() == '00'
		assert number(header, 108, 8) == 0 && number(header, 116, 8) == 0
		assert number(header, 136, 12) == 1735689600
		assert header[265..345].all(it == 0)
		mut checksum := 0
		for index, value in header {
			checksum += if index >= 148 && index < 156 { 32 } else { int(value) }
		}
		assert number(header, 148, 8) == checksum
		size := int(number(header, 124, 12))
		body := data[pos + 512..pos + 512 + size]
		if name.ends_with('/') {
			assert header[156] == `5` && size == 0
			assert number(header, 100, 8) == if name == 'tmp/' { 0o1777 } else { 0o755 }
		} else if name == 'bin/busybox' {
			assert header[156] == `0` && body == busybox
			assert number(header, 100, 8) == 0o755
		} else if name.starts_with('bin/') {
			assert header[156] == `2` && size == 0
			assert field(header, 157, 100) == 'busybox'
			assert number(header, 100, 8) == 0o777
		} else {
			assert header[156] == `0` && number(header, 100, 8) == 0o644
			expected := match name {
				'etc/passwd' {
					'root:x:0:0:root:/root:/bin/sh\nnobody:x:65534:65534:nobody:/:/bin/false\n'
				}
				'etc/group' { 'root:x:0:\nnogroup:x:65534:\n' }
				'etc/os-release' { 'NAME="Vinix busybox"\nID=vinix-busybox\n' }
				else { panic('unexpected member: ${name}') }
			}
			assert body.bytestr() == expected
		}
		pos += 512 + (size + 511) / 512 * 512
	}
	mut expected_names := directories.map(it + '/')
	expected_names << 'bin/busybox'
	expected_names << applets.map('bin/' + it)
	expected_names << ['etc/passwd', 'etc/group', 'etc/os-release']
	assert names == expected_names
	assert data.len % 10240 == 0
	assert data.len >= pos + 1024
	assert data[pos..].all(it == 0)
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

fn test_deterministic_rootfs_all_headers_contents_and_padding() {
	work := temporary_directory()!
	defer { os.rmdir_all(work) or { panic(err) } }
	for length in [0, 1, 511, 512, 513, 8193] {
		busybox := []u8{len: length, init: u8(index * 73)}
		input := work + '/busybox'
		output := work + '/nested/rootfs.tar'
		os.write_file_array(input, busybox)!
		size := build(input, output)!
		check_archive(output, busybox)
		first := os.read_bytes(output)!
		assert size == u64(first.len)
		assert build(input, output)! == size
		assert os.read_bytes(output)! == first
		if os.exists('/usr/bin/tar') {
			listed := invoke('/usr/bin/tar', ['-tf', output])
			assert listed.code == 0 && listed.err == ''
			assert listed.out.trim_space().split('\n').len == 64
			extracted := invoke('/usr/bin/tar', ['-xOf', output, 'bin/busybox'])
			assert extracted.code == 0 && extracted.out.bytes() == busybox
		}
	}
}

fn test_missing_input_does_not_create_output() {
	work := temporary_directory()!
	defer { os.rmdir_all(work) or { panic(err) } }
	output := work + '/missing/rootfs.tar'
	build(work + '/missing-busybox', output) or {
		assert !os.exists(output)
		return
	}
	assert false
}

fn test_native_entrypoint_options_output_and_failures() {
	tool := os.getenv('VINIX_DOCKERIMAGE_TOOL')
	if tool == '' { return }
	work := temporary_directory()!
	defer { os.rmdir_all(work) or { panic(err) } }
	busybox := work + '/busy box'
	output := work + '/root fs.tar'
	os.write_file(busybox, 'fixture busybox')!
	result := invoke(tool, ['--busybox', busybox, '--output', output, '--tag', 'unused'])
	assert result == Result{0, 'rootfs tar: ${output} (${os.file_size(output)} bytes)\n', ''}
	check_archive(output, 'fixture busybox'.bytes())
	assert invoke(tool, ['--busybox=${busybox}', '--output=${output}']).code == 0
	assert invoke(tool, ['--help']).code == 0
	assert invoke(tool, []).code == 2
	assert invoke(tool, ['--output']).code == 2
	assert invoke(tool, ['--unknown']).code == 2
	assert invoke(tool, ['--busybox', work + '/missing', '--output', output]).code == 1
	check_archive(output, 'fixture busybox'.bytes())
}
