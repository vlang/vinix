// SPDX-License-Identifier: GPL-2.0-or-later
module wineheaders

import os
import json2
import tests.packages.winesource

pub struct Snapshot {
pub:
	format int = 1
	directory string
	directories []string
	files map[string]string
}

// Resource discovery is a single canonical path, never shell text.
pub fn selection(text string) !string {
	if !text.ends_with('\n') || text.count('\n') != 1 || text.contains('\r') || text.contains('\x00') {
		return error('invalid Clang resource directory response')
	}
	path := text[..text.len - 1]
	if !os.is_abs_path(path) || os.real_path(path) != path || !os.is_dir(path + '/include') {
		return error('Clang resource directory must be canonical with headers')
	}
	return path
}

fn walk(directory string, mut directories []string, mut files map[string]string) ! {
	if os.lstat(directory)!.get_filetype() != .directory {
		return error('Clang resource tree contains a nonordinary directory')
	}
	if directories.len + files.len >= 20000 { return error('Clang resource tree exceeds entry bound') }
	directories << directory
	for name in os.ls(directory)! {
		path := directory + '/' + name
		st := os.lstat(path)!
		if st.get_filetype() == .directory {
			walk(path, mut directories, mut files)!
		} else if st.get_filetype() == .regular && st.size <= 64 * 1024 * 1024 {
			if directories.len + files.len >= 20000 { return error('Clang resource tree exceeds entry bound') }
			files[path] = winesource.file_digest(path)!
		} else { return error('Clang resource tree contains a linked, special or oversized file') }
	}
}

fn snapshot(directory string) !Snapshot {
	if !os.is_abs_path(directory) || directory.contains('\r') || directory.contains('\n')
		|| directory.contains('\x00') || os.real_path(directory) != directory {
		return error('Clang header directory must be canonical')
	}
	mut directories := []string{}
	mut files := map[string]string{}
	walk(directory, mut directories, mut files)!
	if files.len == 0 { return error('Clang resource header tree is empty') }
	directories.sort()
	return Snapshot{directory: directory, directories: directories, files: files}
}

pub fn capture(directory string, mut inputs map[string]string) !Snapshot {
	result := snapshot(directory)!
	for path, hash in result.files {
		if path in inputs && inputs[path] != hash { return error('Clang header input changed before capture') }
		inputs[path] = hash
	}
	return result
}

pub fn admit(expected Snapshot, inputs map[string]string) ! {
	if expected.format != 1 { return error('unsupported Clang header snapshot') }
	actual := snapshot(expected.directory)!
	if actual.directories != expected.directories || actual.files != expected.files {
		return error('Clang resource header tree changed')
	}
	for path, hash in actual.files {
		if path !in inputs || inputs[path] != hash { return error('Clang resource header input absent or changed') }
	}
}

// Used independently by the producer checker and full retainer. The exact C
// command is checked by the retainer as well; this binds its resource selection.
fn record(path string, bound u64) !string {
	st := os.lstat(path)!
	if st.get_filetype() != .regular || st.size < 1 || st.size > bound {
		return error('Clang resource evidence must be a bounded ordinary file')
	}
	return os.read_file(path)
}

pub fn admit_producer(prepared string, inputs map[string]string) ! {
	expected := json2.decode[Snapshot](record(prepared + '/clang-headers.json', 8 * 1024 * 1024)!)!
	query := json2.decode[[]string](record(prepared + '/logs/clang-resource.log.argv.json', 8192)!)!
	if query != ['/opt/homebrew/opt/llvm/bin/clang', '-print-resource-dir'] {
		return error('Clang resource discovery argv differs')
	}
	resource := selection(record(prepared + '/logs/clang-resource.log', 8192)!)!
	if expected.directory != resource + '/include' { return error('Clang resource snapshot selection differs') }
	cc := json2.decode[[]string](record(prepared + '/logs/cc.log.argv.json', 65536)!)!
	flags := cc.filter(it.starts_with('-resource-dir'))
	if flags != ['-resource-dir=' + resource] || cc.len == 0 || cc[0] != query[0] {
		return error('Clang resource compile selection differs')
	}
	admit(expected, inputs)!
}
