// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import androidhost as ah
import cachecli
import hosttest
import os
import tarstream

#include <unistd.h>
fn C.link(&char, &char) int

// POSIX path operations preserve literal backslashes and resolve a symlink
// before any following '..' component, matching the original payload checks.
fn posix_parent(path string) string {
	position := path.last_index('/') or { return '.' }
	return if position == 0 { '/' } else { path[..position] }
}

fn posix_parents(path string) ! {
	if path == '' || os.is_dir(path) { return }
	parent := posix_parent(path)
	if parent != path { posix_parents(parent)! }
	os.mkdir(path)!
}

fn lexical_path(path string) string {
	mut parts := []string{}
	for part in path.split('/') {
		if part in ['', '.'] { continue }
		if part == '..' { if parts.len > 0 { parts.delete_last() } }
		else { parts << part }
	}
	return '/' + parts.join('/')
}

fn within(path string, root string) bool { return path == root || path.starts_with(root.trim_right('/') + '/') }

pub fn extract_apk(archive string, destination string) ! {
	target := hosttest.module_resolve(destination)!
	mut reader := tarstream.open_concatenated(archive)!
	defer { reader.close() }
	mut buffer := []u8{len: 1024 * 1024}
	for {
		cachecli.checkpoint()!
		mut member := reader.next() or { if err is tarstream.End { break }; return err }
		parts := member.name.split('/').filter(it != '' && it != '.')
		if parts.len == 0 || parts[0].starts_with('.') { continue }
		if member.name.starts_with('/') || '..' in parts { return error('unsafe APK payload path: ' + member.name) }
		if !member.regular() && member.kind !in [u8(`5`), `2`, `1`] { continue }
		name := parts.join('/')
		path := target + '/' + name
		parent := posix_parent(path)
		if member.kind == `2` {
			if member.linkname.starts_with('/') {
				// Absolute APK symlinks refer to the private runtime's root.
				depth := parts.len - 1
				member.linkname = '../'.repeat(depth) + member.linkname.trim_left('/')
			}
			if !within(lexical_path(parent + '/' + member.linkname), target) { return error('unsafe APK symlink: ' + member.name) }
		}
		if member.kind == `1` && (member.linkname.starts_with('/') || '..' in member.linkname.split('/').filter(it != '' && it != '.')) { return error('unsafe APK hardlink: ' + member.name) }
		posix_parents(parent)!
		if !within(hosttest.module_resolve(parent)!, target) { return error('APK payload parent escapes prefix: ' + member.name) }
		if member.kind == `5` { if !os.is_dir(path) { os.mkdir(path)! }; continue }
		if os.exists(path) || os.is_link(path) { os.rm(path)! }
		if member.kind == `2` { os.symlink(member.linkname, path)!; continue }
		if member.kind == `1` {
			existing := hosttest.module_resolve(target + '/' + member.linkname)!
			if !os.exists(existing) { return error('APK hardlink source is missing: ' + member.linkname) }
			if !within(existing, target) { return error('APK hardlink escapes prefix: ' + member.name) }
			if C.link(existing.str, path.str) != 0 { return os.error_posix() }
			continue
		}
		mut file := os.create(path)!
		defer { file.close() }
		for {
			count := reader.read(mut buffer)!
			if count == 0 { break }
			mut offset := 0
			for offset < count {
				written := file.write(buffer[offset..count])!
				if written == 0 { return error('APK payload write stopped') }
				offset += written
			}
		}
		os.chmod(path, int(member.mode & 0o777))!
	}
}

fn descendants(directory string, mut output []string) ! {
	if !os.is_dir(directory) { return }
	for name in os.ls(directory)! {
		path := directory + '/' + name
		output << path
		if !os.is_link(path) && os.is_dir(path) { descendants(path, mut output)! }
	}
}

pub fn materialize_library_links(runtime string) ! {
	root_path := hosttest.module_resolve(runtime)!
	for name in ['lib', 'usr/lib'] {
		mut paths := []string{}
		descendants(runtime + '/' + name, mut paths)!
		paths.sort()
		for path in paths {
			if !os.is_link(path) { continue }
			name_part := os.file_name(path)
			if !name_part.contains('.so') && !name_part.starts_with('ld-musl-') { continue }
			source := hosttest.module_resolve(path)!
			if !os.exists(source) { return error('runtime library symlink is missing: ' + path) }
			if !within(source, root_path) { return error('runtime library symlink escapes prefix: ' + path) }
			os.rm(path)!
			if C.link(source.str, path.str) != 0 { return os.error_posix() }
		}
	}
}

pub fn relocate_configuration(runtime string) ! {
	mut paths := []string{}
	descendants(runtime + '/etc/fonts', mut paths)!
	for path in paths {
		if !path.ends_with('.conf') || os.is_link(path) { continue }
		mut content := os.read_file(path)!
		hosttest.module_decode_utf8(content)!
		for name in ['/usr/share/fonts', '/usr/local/share/fonts', '/etc/fonts'] { content = content.replace(name, runtime_prefix + name) }
		os.write_file(path, content)!
	}
}

fn copy_tree(source string, destination string, preserve_links bool) ! {
	if os.is_link(source) && preserve_links { os.symlink(os.readlink(source)!, destination)!; return }
	if os.is_dir(source) {
		posix_parents(destination)!
		for name in os.ls(source)! { copy_tree(source + '/' + name, destination + '/' + name, preserve_links)! }
		os.chmod(destination, int(os.stat(source)!.mode & 0o7777))!
	} else {
		posix_parents(posix_parent(destination))!
		os.cp(source, destination)!
		os.chmod(destination, int(os.stat(source)!.mode & 0o7777))!
	}
}

pub fn package_download(url string, target string, expected string) !string {
	if os.exists(target) {
		actual := ah.digest(target)!
		if expected == '' || actual == expected { return actual }
		return error('cached download checksum mismatch: ' + target)
	}
	println('  downloading ' + os.file_name(target)); flush_stdout()
	temporary := target + '.part'
	defer { if os.exists(temporary) { os.rm(temporary) or {} } }
	probe_command(['curl', '--fail', '--location', '--silent', '--show-error', '--retry', '3', '--output', temporary, url], false, '')!
	actual := ah.digest(temporary)!
	if expected != '' && expected != actual { return error('download checksum mismatch: ' + url) }
	replace_file(temporary, target)!
	return actual
}
