// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os

#include <dirent.h>
#include <sys/stat.h>
#include <stdlib.h>

fn C.openat(int, &char, int, ...int) int
fn C.readlinkat(int, &char, voidptr, usize) isize
fn C.fstat(int, &C.stat) int
fn C.fdopendir(int) voidptr
fn C.closedir(voidptr) int
fn C.mkdtemp(&char) &char

pub struct RootEntry {
pub:
	source string // relative to the prepared guest root
	path   string // relative destination in the package
}

pub struct RootRecipe {
pub:
	format   int = 1
	manifest Package
	entries  []RootEntry
}

struct ImportNode {
	fd     int
	mode   u32
	bytes  u64
	device u64
	inode  u64
}

// Every component is opened relative to the captured root, without following
// host symlinks. Link resolution restarts from that descriptor's namespace.
fn import_node(root int, source string) !ImportNode {
	mut pending := source
	mut links := 0
	for {
		if !printable(pending, 4096) || pending.contains('\\') {
			return error('unsafe or oversized guest symlink target')
		}
		mut directory := C.dup(root)
		if directory < 0 { return error('cannot retain import root') }
		mut restart := false
		parts := pending.split('/')
		mut prefix := []string{}
		for index, part in parts {
			if part in ['', '.'] { continue }
			if part == '..' {
				C.close(directory)
				if prefix.len == 0 { return error('guest symlink escapes its source root') }
				prefix.pop()
				pending = prefix.join('/') + if index + 1 < parts.len {
					'/' + parts[index + 1..].join('/')
				} else {
					''
				}
				restart = true
				break
			}
			if !relative_path(part) {
				C.close(directory)
				return error('invalid guest path component')
			}
			mut link := [4097]u8{}
			count := C.readlinkat(directory, part.str, unsafe { &link[0] }, usize(link.len))
			if count >= 0 {
				C.close(directory)
				links++
				if links > 40 {
					return error('guest symlink cycle or excessive link depth: ${source}')
				}
				if count == 0 || count >= link.len {
					return error('invalid or oversized guest symlink: ${pending}')
				}
				target := unsafe { tos(&link[0], int(count)).clone() }
				base := if target.starts_with('/') {
					target
				} else {
					prefix.join('/') + '/' + target
				}
				// Follow an intermediate alias before interpreting any later '..'.
				pending = base + if index + 1 < parts.len {
					'/' + parts[index + 1..].join('/')
				} else {
					''
				}
				restart = true
				break
			}
			flags := C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK |
				if index + 1 < parts.len { C.O_DIRECTORY } else { 0 }
			next := C.openat(directory, part.str, flags)
			C.close(directory)
			if next < 0 { return error('cannot open prepared guest path: ${pending}') }
			directory = next
			prefix << part
		}
		if restart { continue }
		if prefix.len == 0 {
			C.close(directory)
			return error('guest symlink resolves to its source root')
		}
		mut info := C.stat{}
		if C.fstat(directory, &info) != 0 {
			C.close(directory)
			return error('cannot inspect prepared guest path: ${pending}')
		}
		return ImportNode{
			fd:     directory
			mode:   u32(info.st_mode)
			bytes:  u64(info.st_size)
			device: u64(info.st_dev)
			inode:  u64(info.st_ino)
		}
	}
	return error('cannot resolve prepared guest path')
}

fn import_names(fd int) ![]string {
	duplicate := C.dup(fd)
	if duplicate < 0 { return error('cannot retain import directory') }
	directory := C.fdopendir(duplicate)
	if directory == unsafe { nil } {
		C.close(duplicate)
		return error('cannot enumerate import directory')
	}
	defer { C.closedir(directory) }
	mut names := []string{}
	for {
		C.errno = 0
		entry := C.readdir(directory)
		if entry == unsafe { nil } {
			if C.errno != 0 { return error('cannot read import directory') }
			break
		}
		name := unsafe { tos_clone(&u8(&entry.d_name[0])) }
		if name in ['.', '..'] { continue }
		names << name
		if names.len > max_files { return error('prepared directory exceeds package file limit') }
	}
	names.sort()
	return names
}

struct RootImport {
	root   int
	output string
	pins map[string]Payload // populated only by a catalog lock
mut:
	files     int
	bytes     u64
	ancestors []string
}

fn (mut importer RootImport) copy(source string, target string) ! {
	if !relative_path(source) || !relative_path(target) {
		return error('invalid import source/destination path')
	}
	node := import_node(importer.root, source)!
	defer { C.close(node.fd) }
	if node.mode & 0o170000 == 0o040000 {
		identity := '${node.device}:${node.inode}'
		if identity in importer.ancestors {
			return error('guest directory symlink cycle: ${source}')
		}
		importer.ancestors << identity
		defer { importer.ancestors.pop() }
		os.mkdir_all(importer.output + '/' + target)!
		for name in import_names(node.fd)! {
			importer.copy(source + '/' + name, target + '/' + name)!
		}
		return
	}
	if node.mode & 0o170000 != 0o100000 {
		return error('prepared root contains a special file: ${source}')
	}
	if importer.pins.len > 0 {
		if target !in importer.pins || importer.pins[target].bytes != node.bytes
			|| importer.pins[target].executable != (node.mode & 0o111 != 0) {
			return error('catalog payload inventory differs from its lock: ${target}')
		}
	}
	if node.bytes > u64(4) << 30 || importer.bytes > (u64(64) << 30) - node.bytes
		|| importer.files >= max_files {
		return error('prepared payload exceeds package limits')
	}
	importer.bytes += node.bytes
	importer.files++
	path := importer.output + '/' + target
	os.mkdir_all(os.dir(path))!
	mut output := os.open_file(path, 'w', 0o600)!
	defer { output.close() }
	output.set_unbuffered()
	mut buffer := []u8{len: 64 * 1024}
	defer { unsafe { buffer.free() } }
	mut copied := u64(0)
	for {
		count := C.read(node.fd, buffer.data, usize(buffer.len))
		if count < 0 {
			if C.errno == C.EINTR { continue }
			return error('cannot read prepared payload: ${source}')
		}
		if count == 0 { break }
		copied += u64(count)
		if copied > node.bytes { return error('prepared payload grew during import: ${source}') }
		mut sent := 0
		for sent < count {
			written := output.write(buffer[sent..int(count)])!
			if written == 0 { return error('short import write; check disk space') }
			sent += written
		}
	}
	if copied != node.bytes { return error('prepared payload changed during import: ${source}') }
	os.chmod(path, if node.mode & 0o111 != 0 { 0o755 } else { 0o644 })!
	if importer.pins.len > 0 && hash_file(path)! != importer.pins[target].sha256 {
		return error('catalog payload inventory differs from its lock: ${target}')
	}
}

fn validate_root_recipe(recipe RootRecipe) ! {
	if recipe.format != 1 || recipe.entries.len == 0 || recipe.entries.len > 1024 {
		return error('unsupported or empty prepared-root recipe')
	}
	for index, entry in recipe.entries {
		if !relative_path(entry.source) || !relative_path(entry.path) {
			return error('invalid prepared-root selector')
		}
		for previous in recipe.entries[..index] {
			if entry.path == previous.path || entry.path.starts_with(previous.path + '/')
				|| previous.path.starts_with(entry.path + '/') {
				return error('overlapping prepared-root destinations')
			}
		}
	}
}

pub fn pack_root(recipe_file string, source_root string, repository string) !Package {
	text := read_metadata(recipe_file)!
	defer { unsafe { text.free() } }
	recipe := decode_root_recipe(text)!
	root := C.open(source_root.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
	if root < 0 { return error('prepared source root must be an ordinary directory') }
	defer { C.close(root) }
	return pack_root_descriptor(recipe, root, repository, false)
}

// The catalog captures each architecture root once, so namespace aliases cannot
// switch its source directory between package imports.
fn pack_root_descriptor(recipe RootRecipe, root int, repository string, pinned bool) !Package {
	validate_root_recipe(recipe)!
	mut template := (os.temp_dir() + '/vinix-pack-root-XXXXXX').bytes()
	template << u8(0)
	created := C.mkdtemp(&char(template.data))
	if created == unsafe { nil } { return error('cannot create private import workspace') }
	work := unsafe { cstring_to_vstring(created).clone() }
	defer { os.rmdir_all(work) or {} }
	mut pins := map[string]Payload{}
	if pinned { for file in recipe.manifest.files { pins[file.path] = file } }
	mut importer := RootImport{ root: root, output: work + '/payload', pins: pins }
	for entry in recipe.entries { importer.copy(entry.source, entry.path)! }
	os.write_file(work + '/manifest.json', json2.encode(recipe.manifest))!
	return pack(work + '/manifest.json', work + '/payload', repository)!
}
