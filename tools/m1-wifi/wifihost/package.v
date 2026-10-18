// SPDX-License-Identifier: ISC
module wifihost

import crypto.sha256
import os
import x.json2

#include <sys/stat.h>

fn C.mkdir(&char, u32) int

pub struct SelectionError {
pub:
	message string
}

pub fn (e SelectionError) msg() string { return e.message }

pub fn (e SelectionError) code() int { return 2 }

pub struct PackageOptions {
pub:
	status   string
	firmware string
	nvram    string
	clm      string
	txcap    string
	output   string
}

struct Part {
	name   string
	source string
	data   []u8
}

// Path's lexical spelling, without resolving symlinks or parent components.
pub fn path_value(path string) string {
	prefix := if path.starts_with('//') && !path.starts_with('///') {
		'//'
	} else if path.starts_with('/') {
		'/'
	} else {
		''
	}
	value := prefix + path.split('/').filter(it != '' && it != '.').join('/')
	return if value == '' { '.' } else { value }
}

fn parent_path(path string) string {
	index := path.last_index('/') or { return '.' }
	return if index == 0 { '/' } else { path[..index] }
}

fn package_parents(path string) ! {
	if path == '' || path == '/' || path == '.' { return }
	if C.mkdir(path.str, 0o777) == 0 { return }
	if os.is_dir(path) { return }
	package_parents(parent_path(path))!
	if C.mkdir(path.str, 0o777) != 0 && !os.is_dir(path) {
		return error('Cannot create directory: ' + path)
	}
}

pub fn package(a PackageOptions) ! {
	if [a.status, a.firmware, a.nvram, a.clm, a.txcap, a.output].any(it.contains('\x00')) {
		return error('embedded null byte')
	}
	status := os.read_bytes(path_value(a.status))!
	if status.len != 256 || little(status, 0, 4) != 1 {
		return SelectionError{'status must be a 256-byte successful chip-probe response'}
	}
	revision := little(status, 8, 4)
	board := status[120..152]
	if revision !in [u64(3), 5] || board.bytestr().all_before('\x00') != 'apple,shikoku' {
		return SelectionError{'unsupported chip revision or board'}
	}
	mut manifest := []u8{len: 128}
	manifest[0] = u8(revision)
	for row in [[8, 40, 16]!, [24, 56, 16]!, [40, 72, 16]!, [56, 104, 16]!, [72, 120, 32]!] {
		value := status[row[1]..row[1] + row[2]]
		if value[0] == 0 || u8(0) !in value {
			return SelectionError{'incomplete OTP/board identity'}
		}
		copy(mut manifest[row[0]..row[0] + row[2]], value)
	}
	package_files(a, manifest, [])!
}

fn package_files(a PackageOptions, manifest []u8, sources []string) ! {
	mut parts := []Part{}
	names := ['firmware.bin', 'nvram.txt', 'clm.blob', 'txcap.blob']
	limits := [u64(4 * 1024 * 1024), 65536, 1024 * 1024, 1024 * 1024]
	for i, raw in [a.firmware, a.nvram, a.clm, a.txcap] {
		source := path_value(raw)
		size := os.stat(source)!.size
		if !os.is_file(source) || size == 0 || size > limits[i] {
			return SelectionError{'invalid file size: ' + source}
		}
		data := os.read_bytes(source)!
		if u64(data.len) != size { return SelectionError{'file changed while reading: ' + source} }
		if i == 0 && data.len < 0x74 {
			return SelectionError{'firmware is shorter than the reset/vector table'}
		}
		if i == 1 {
			if u8(0) in data {
				return SelectionError{'provide textual board NVRAM, not a packed binary'}
			}
			if data.any(it > 127) { return error('NVRAM is not ASCII text') }
		}
		parts << Part{names[i], if sources.len == 4 { sources[i] } else { source }, data}
	}
	output := path_value(a.output)
	package_parents(parent_path(output))!
	// The leaf must be new, even if it is a symlink or the current directory.
	if C.mkdir(output.str, 0o777) != 0 {
		return error('Cannot create new output directory: ' + output)
	}
	os.write_file_array(output.trim_right('/') + '/manifest.bin', manifest)!
	mut records := map[string]json2.Any{}
	for part in parts {
		os.write_file_array(output.trim_right('/') + '/' + part.name, part.data)!
		records[part.name] = json2.Any({
			'source': json2.Any(part.source)
			'sha256': json2.Any(sha256.sum(part.data).hex())
			'bytes':  json2.Any(part.data.len)
		})
	}
	os.write_file(output.trim_right('/') + '/provenance.json', json2.encode(records,
		prettify:       true
		indent_string:  '  '
		escape_unicode: true
	) + '\n')!
}
