module androidhost

import os
import crypto.sha256

#include <unistd.h>
#include <stdlib.h>

fn C.mkstemp(&u8) i32
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.unlink(&char) i32
fn C.rename(&char, &char) i32
fn C.mkdir(&char, u32) i32

// POSIX paths permit backslashes in names. os.join_path/mkdir_all also
// understand Windows separators, so use slash-only operations here.
fn path_join(root string, name string) string {
	if name.starts_with('/') { return name }
	if name in ['', '.'] { return if root == '' { '.' } else { root } }
	if root == '.' || root == '' { return name }
	if root == '//' { return '//' + name }
	return root.trim_right('/') + '/' + name
}

fn path_parent(path string) string {
	position := path.last_index('/') or { return '.' }
	return if position == 0 { '/' } else { path[..position] }
}

pub fn regular(path string) ! {
	if path.contains('\x00') { return error('ValueError: embedded null byte') }
	state := os.lstat(path) or {
		return error('ART overlay file is missing or unreadable: ${path}')
	}
	if state.get_filetype() != .regular {
		return error('ART overlay file is not a regular file: ${path}')
	}
}

pub struct SymlinkLoop {
	path string
}

pub fn (err SymlinkLoop) msg() string { return 'Symlink loop from ' + err.path }

pub fn (err SymlinkLoop) code() int { return 0 }

// Follow links component by component, including through absent ancestors.
// The cache distinguishes links currently resolving from completed links.
// Only '/' is a separator; '..' follows the resolved parent, not a lexical
// normalization performed before following a link.
fn resolve_walk(start string, rest string, mut seen map[string]string) !string {
	mut prefix := if rest.starts_with('/') { '' } else { start }
	for name in rest.split('/') {
		if name in ['', '.'] { continue }
		if name == '..' {
			position := prefix.last_index('/') or { 0 }
			prefix = prefix[..position]
			continue
		}
		candidate := prefix.trim_right('/') + '/' + name
		if candidate in seen {
			resolved := seen[candidate]
			if resolved == '' { return SymlinkLoop{candidate} }
			prefix = resolved
			continue
		}
		target := os.readlink(candidate) or {
			prefix = candidate
			continue
		}
		seen[candidate] = ''
		prefix = resolve_walk(prefix, target, mut seen)!
		seen[candidate] = prefix
	}
	return if prefix == '' { '/' } else { prefix }
}

fn resolved_path(path string) !string {
	if path.contains('\x00') { return error('ValueError: embedded null byte') }
	mut seen := map[string]string{}
	return resolve_walk(if path.starts_with('/') { '' } else { os.getwd() }, path, mut seen)
}

pub fn inside(root string, name string) !string {
	if root.contains('\x00') || name.contains('\x00') {
		return error('ValueError: embedded null byte')
	}
	parts := name.split('/').filter(it != '' && it != '.')
	path := path_join(root, name)
	mut parent := if name.starts_with('//') && !name.starts_with('///') {
		'//'
	} else if name.starts_with('/') {
		'/'
	} else {
		root
	}
	for part in parts[..if parts.len > 0 { parts.len - 1 } else { 0 }] {
		parent = path_join(parent, part)
		if os.is_link(parent) { return error('ART overlay has a symlink parent: ${parent}') }
	}
	actual := resolved_path(path_parent(path))!
	base := resolved_path(root)!
	if actual != base && !actual.starts_with(base.trim_right('/') + '/') {
		return error('ART overlay path escapes its root: ${path}')
	}
	return path
}

fn append_source(mut hash sha256.Digest, path string) ! {
	mut source := open_reader(path)!
	defer { source.close() }
	mut buffer := []u8{len: 1024 * 1024}
	for {
		count := source.read(mut buffer) or {
			if err is os.Eof { break }
			return file_error('')
		}
		if count == 0 { break }
		hash.write(buffer[..count])!
	}
}

pub fn configuration_probe_digest(support string) !string {
	mut hash := sha256.new()
	for name in ['android/atlconfiguration/core.v', 'android/atl-configuration-v-abi.h',
		'android/compile-v-atl-configuration.py', 'compile-v-module.py', 'find-v.sh'] {
		hash.write(name.bytes())!
		hash.write([u8(0)])!
		append_source(mut hash, path_join(path_parent(support), name))!
	}
	return hash.sum([]u8{}).hex()
}

// Match mkdir(parents=True, exist_ok=True), including failure on a regular
// leaf and the original leaf-before-parent creation attempt.
fn mkdir_parents(path string) ! {
	if C.mkdir(&char(path.str), 0o777) == 0 { return }
	failure := file_error(path)
	if failure.code() == int(C.ENOENT) {
		parent := path_parent(path)
		if parent != path {
			mkdir_parents(parent)!
			if C.mkdir(&char(path.str), 0o777) == 0 { return }
			if os.is_dir(path) { return }
			return file_error(path)
		}
	}
	if os.is_dir(path) { return }
	return failure
}

struct Temporary {
	path string
	fd   i32
}

fn absolute_path(path string) string {
	absolute := if path.starts_with('/') { path } else { path_join(os.getwd(), path) }
	mut parts := []string{}
	for name in absolute.split('/') {
		if name in ['', '.'] { continue }
		if name == '..' {
			if parts.len > 0 { parts.delete_last() }
			continue
		}
		parts << name
	}
	return (if absolute.starts_with('//') && !absolute.starts_with('///') { '//' } else { '/' }) + parts.join('/')
}

fn temporary_file(directory string) !Temporary {
	mut pattern := (path_join(absolute_path(directory), '.vinix-art-XXXXXX') + '\x00').bytes()
	fd := C.mkstemp(pattern.data)
	if fd == -1 { return file_error(path_join(directory, '.vinix-art-XXXXXX')) }
	return Temporary{pattern[..pattern.len - 1].bytestr(), fd}
}

fn remove_temporary(path string) ! {
	if C.unlink(&char(path.str)) != 0 && int(C.errno) != int(C.ENOENT) {
		return file_error(path)
	}
}

fn copy_to_temporary(source string, temporary Temporary) ! {
	mut input := open_reader(source) or {
		C.close(temporary.fd)
		return err
	}
	defer { input.close() }
	mut buffer := []u8{len: 64 * 1024}
	for {
		count := input.read(mut buffer) or {
			if err is os.Eof { break }
			failure := file_error('')
			C.close(temporary.fd)
			return failure
		}
		if count == 0 { break }
		mut cursor := 0
		for cursor < count {
			written := C.write(temporary.fd, unsafe { &u8(buffer.data) + cursor }, usize(count - cursor))
			if written < 0 {
				if int(C.errno) == int(C.EINTR) { continue }
				failure := file_error('')
				C.close(temporary.fd)
				return failure
			}
			cursor += int(written)
		}
	}
	if C.close(temporary.fd) != 0 { return file_error('') }
}

fn publish_file(source string, target string, record map[string]Value, required bool, temporary Temporary) ! {
	copy_to_temporary(source, temporary)!
	state := os.stat(temporary.path) or { return file_error(temporary.path) }
	if !size_matches(field(record, 'size'), state.size) {
		return error('ART runtime file changed during installation: ' + field(record, 'path').text())
	}
	if digest(temporary.path)! != field(record, 'sha256').text() {
		return error('ART runtime file changed during installation: ' + field(record, 'path').text())
	}
	check_elf(temporary.path, required)!
	permissions := os.stat(source) or { return file_error(source) }
	os.chmod(temporary.path, int(permissions.mode & 0o777)) or { return file_error(temporary.path) }
	if C.rename(&char(temporary.path.str), &char(target.str)) != 0 {
		number := int(C.errno)
		return FileError{
			message:   os.get_error_msg(number)
			number:    number
			filename:  temporary.path
			filename2: target
		}
	}
}

pub fn install_runtime(overlay string, runtime string, manifest Value, bionic bool, atl bool) ! {
	if runtime.contains('\x00') { return error('ValueError: embedded null byte') }
	if os.is_link(runtime) { return error('ART destination must not be a symlink: ${runtime}') }
	mkdir_parents(runtime)!
	files := field(manifest.object(), 'files').items()
	mut destinations := []string{cap: files.len}
	// Complete preflight before copying or publishing the first payload.
	for value in files {
		destinations << inside(runtime, relative(field(value.object(), 'path'))!)!
	}
	for index, value in files {
		record := value.object()
		name := relative(field(record, 'path'))!
		source := inside(overlay, name)!
		target := destinations[index]
		mkdir_parents(path_parent(target))!
		temporary := temporary_file(path_parent(target))!
		publish_file(source, target, record, bionic || name in (if atl {
			atl_elfs
		} else {
			art_elfs
		}), temporary) or {
			failure := err
			remove_temporary(temporary.path)!
			return failure
		}
		remove_temporary(temporary.path)!
	}
}
