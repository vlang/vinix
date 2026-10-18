// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

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

// Build one owned restart path without temporary joins or borrowed array
// slices. Prefix components belong to the current split, not to this helper.
fn import_restart(prefix []string, target string, parts []string, next int) !string {
	absolute := target.starts_with('/')
	mut size := target.len
	if !absolute {
		for index, part in prefix { size += part.len + if index > 0 { 1 } else { 0 } }
		if target != '' { size++ }
	}
	if next < parts.len {
		size++
		for index := next; index < parts.len; index++ { size += parts[index].len + if index > next { 1 } else { 0 } }
	}
	if size > 4096 { return error('unsafe or oversized guest symlink target') }
	mut bytes := []u8{cap: size}
	defer { unsafe { bytes.free() } }
	if !absolute {
		for index, part in prefix {
			if index > 0 { bytes << `/` }
			for byte in part { bytes << byte }
		}
		if target != '' { bytes << `/` }
	}
	for byte in target { bytes << byte }
	if next < parts.len {
		bytes << `/`
		for index := next; index < parts.len; index++ {
			if index > next { bytes << `/` }
			for byte in parts[index] { bytes << byte }
		}
	}
	return bytes.bytestr()
}

// Every component is opened relative to the captured root, without following
// host symlinks. Link resolution restarts from that descriptor's namespace.
fn import_node(root int, source string) !ImportNode {
	if !printable(source, 4096) || source.contains('\\') {
		return error('unsafe or oversized guest symlink target')
	}
	mut pending := source.clone()
	defer { unsafe { pending.free() } }
	mut links := 0
	for {
		if !printable(pending, 4096) || pending.contains('\\') {
			return error('unsafe or oversized guest symlink target')
		}
		mut directory := C.dup(root)
		if directory < 0 { return error('cannot retain import root') }
		mut restart := false
		parts := pending.split('/')
		defer { unsafe { parts.free() } }
		mut prefix := []string{cap: parts.len}
		// Only the buffer is owned: its strings are borrowed from parts.
		defer { unsafe { (&array(&prefix)).free() } }
		for index, part in parts {
			if part in ['', '.'] { continue }
			if part == '..' {
				C.close(directory)
				if prefix.len == 0 { return error('guest symlink escapes its source root') }
				prefix.pop()
				next_pending := import_restart(prefix, '', parts, index + 1)!
				unsafe { pending.free() }
				pending = next_pending
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
				defer { unsafe { target.free() } }
				// Follow an intermediate alias before interpreting any later '..'.
				next_pending := import_restart(prefix, target, parts, index + 1)!
				unsafe { pending.free() }
				pending = next_pending
				restart = true
				break
			}
			flags := C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK |
				if index + 1 < parts.len { C.O_DIRECTORY } else { 0 }
			next := C.openat(directory, part.str, flags)
			C.close(directory)
			if next < 0 { return error('cannot open prepared guest path: ${pending}') }
			directory = next
			// A normal string append clones each component in manual-free builds.
			// Keep borrowed views until parts is retired at this iteration's end.
			unsafe { prefix.push_many(&part, 1) }
		}
		if restart { continue }
		if prefix.len == 0 {
			C.close(directory)
			return error('guest symlink resolves to its source root')
		}
		mut info := C.stat{}
		if C.fstat(directory, unsafe { &info }) != 0 {
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
	return import_names_limit(fd, max_files)
}

// Also bound enumeration by the importer's remaining aggregate work budget.
// Returned names are owned; a refusal retires the partially collected list.
fn import_names_limit(fd int, limit int) ![]string {
	duplicate := C.dup(fd)
	if duplicate < 0 { return error('cannot retain import directory') }
	directory := C.fdopendir(duplicate)
	if directory == unsafe { nil } {
		C.close(duplicate)
		return error('cannot enumerate import directory')
	}
	defer { C.closedir(directory) }
	mut names := []string{}
	unsafe { names.flags |= .noslices }
	mut accepted := false
	defer { if !accepted { unsafe { names.free() } } }
	for {
		C.errno = 0
		entry := C.readdir(directory)
		if entry == unsafe { nil } {
			if C.errno != 0 { return error('cannot read import directory') }
			break
		}
		name := unsafe { tos_clone(&u8(&entry.d_name[0])) }
		if name in ['.', '..'] { unsafe { name.free() }; continue }
		if names.len >= limit {
			unsafe { name.free() }
			return error('prepared directory exceeds entry limit')
		}
		// name is already an independent copy of the directory entry. Move it
		// into the owner rather than cloning again on variable append.
		unsafe { names.push_many(&name, 1) }
	}
	names.sort()
	accepted = true
	return names
}

struct ImportDirectoryIdentity {
	device u64
	inode u64
}

struct RootImport {
	root   int
	output string
	pins map[string]Payload // populated only by a catalog lock
	options PackSourceOptions
mut:
	entries   int // includes selected roots and every materialized alias visit
	files     int
	bytes     u64
	ancestors []ImportDirectoryIdentity
}

// The returned descriptor is owned by the caller. Resolve through the captured
// guest namespace again: a host pathname check would misinterpret guest-absolute
// links and could inspect an entirely different prepared root after a rename.
fn recheck_import_node(root int, source string, node ImportNode) !int {
	mut opened := C.stat{}
	if C.fstat(node.fd, unsafe { &opened }) != 0 || u64(opened.st_dev) != node.device
		|| u64(opened.st_ino) != node.inode || u32(opened.st_mode) & 0o170111 != node.mode & 0o170111
		|| (node.mode & 0o170000 == 0o100000 && (opened.st_size < 0 || u64(opened.st_size) != node.bytes)) {
		return error('prepared source identity, size or executable mode changed during import: ${source}')
	}
	current := import_node(root, source)!
	if current.device != node.device || current.inode != node.inode
		|| current.mode & 0o170111 != node.mode & 0o170111
		|| (node.mode & 0o170000 == 0o100000 && current.bytes != node.bytes) {
		C.close(current.fd)
		return error('prepared source identity, size or executable mode changed during import: ${source}')
	}
	return current.fd
}

fn (mut importer RootImport) copy(source string, target string) ! {
	importer.copy_at(source, target, target.count('/'))!
}

// Depth counts destination parents, so deeply nested selectors cannot bypass
// the same directory bound that the final pack walk applies to its output.
fn (mut importer RootImport) copy_at(source string, target string, depth int) ! {
	if !relative_path(source) || !relative_path(target) {
		return error('invalid import source/destination path')
	}
	if depth > max_pack_depth { return error('prepared import exceeds directory depth limit: ${target}') }
	if importer.entries >= max_pack_entries { return error('prepared import exceeds directory entry limit') }
	importer.entries++
	node := import_node(importer.root, source)!
	defer { C.close(node.fd) }
	importer.options.checkpoint('opened', source)!
	C.close(recheck_import_node(importer.root, source, node)!)
	if node.mode & 0o170000 == 0o040000 {
		if depth >= max_pack_depth { return error('prepared import exceeds directory depth limit: ${target}') }
		identity := ImportDirectoryIdentity{ device: node.device, inode: node.inode }
		if identity in importer.ancestors {
			return error('guest directory symlink cycle: ${source}')
		}
		// Keep only values in this ancestry stack: string interpolation and
		// variable string append retain scratch in manual-free builds.
		unsafe { importer.ancestors.flags |= .noslices; importer.ancestors.push_many(&identity, 1) }
		defer { importer.ancestors.pop() }
		remaining := max_pack_entries - importer.entries
		names := import_names_limit(node.fd, if remaining < max_files { remaining } else { max_files })!
		defer { unsafe { names.free() } }
		importer.options.checkpoint('directory', source)!
		C.close(recheck_import_node(importer.root, source, node)!)
		path := importer.output + '/' + target
		defer { unsafe { path.free() } }
		make_package_directories(path, 0o777)!
		for name in names {
			child_source := source + '/' + name
			child_target := target + '/' + name
			defer { unsafe { child_source.free(); child_target.free() } }
			importer.copy_at(child_source, child_target, depth + 1)!
		}
		current := recheck_import_node(importer.root, source, node)!
		defer { C.close(current) }
		final_names := import_names_limit(current, if remaining < max_files { remaining } else { max_files })!
		defer { unsafe { final_names.free() } }
		if final_names != names { return error('prepared directory entries changed during import: ${source}') }
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
	importer.options.checkpoint('sized', source)!
	// A catalog lock supplies the expected digest. Unpinned imports
	// first hash the captured file, so a same-size rewrite between that read and
	// materialization cannot silently become a new reproducible declaration.
	digest := if importer.pins.len > 0 { importer.pins[target].sha256.clone() } else {
		hash_opened(node.fd, node.bytes, source, HashReadOptions{ checkpoint: importer.options.checkpoint })!
	}
	defer { unsafe { digest.free() } }
	importer.options.checkpoint('hashed', source)!
	C.close(recheck_import_node(importer.root, source, node)!)
	if C.lseek(node.fd, 0, C.SEEK_SET) != 0 { return error('cannot seek prepared payload: ${source}') }
	path := importer.output + '/' + target
	parent := os.dir(path)
	defer { unsafe { path.free(); parent.free() } }
	make_package_directories(parent, 0o777)!
	// The variadic V File helper retains its permission-options array with
	// no collector. Own one native descriptor and write the captured blocks.
	output := C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_TRUNC | C.O_CLOEXEC, 0o600)
	if output < 0 { return error('cannot create prepared payload; check permissions and disk space: ' + target) }
	defer { C.close(output) }
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
			written := C.write(output, unsafe { &u8(buffer.data) + sent }, usize(int(count) - sent))
			if written < 0 && C.errno == C.EINTR { continue }
			if written <= 0 { return error('cannot write prepared payload; check disk space: ' + target) }
			sent += int(written)
		}
		importer.options.checkpoint('copy-block', source)!
	}
	if copied != node.bytes { return error('prepared payload changed during import: ${source}') }
	importer.options.checkpoint('copied', source)!
	C.close(recheck_import_node(importer.root, source, node)!)
	os.chmod(path, if node.mode & 0o111 != 0 { 0o755 } else { 0o644 })!
	materialized := hash_file(path)!
	defer { unsafe { materialized.free() } }
	if materialized != digest {
		if importer.pins.len > 0 { return error('catalog payload inventory differs from its lock: ${target}') }
		return error('prepared payload changed contents during import: ${source}')
	}
}

fn root_destination_contains(parent string, child string) bool {
	return child.len > parent.len && child[parent.len] == `/` && child.starts_with(parent)
}

fn validate_root_recipe(recipe RootRecipe) ! {
	if recipe.format != 1 || recipe.entries.len == 0 || recipe.entries.len > 1024 {
		return error('unsupported or empty prepared-root recipe')
	}
	for index, entry in recipe.entries {
		if !relative_path(entry.source) || !relative_path(entry.path) {
			return error('invalid prepared-root selector')
		}
		for previous_index in 0 .. index {
			previous := recipe.entries[previous_index]
			if entry.path == previous.path || root_destination_contains(previous.path, entry.path)
				|| root_destination_contains(entry.path, previous.path) {
				return error('overlapping prepared-root destinations')
			}
		}
	}
}

pub fn pack_root(recipe_file string, source_root string, repository string) !Package {
	return pack_root_with(recipe_file, source_root, repository, PackSourceOptions{})
}

fn pack_root_with(recipe_file string, source_root string, repository string, options PackSourceOptions) !Package {
	text := read_metadata(recipe_file)!
	defer { unsafe { text.free() } }
	recipe := decode_root_recipe(text)!
	defer { close_decoded_root_recipe(recipe) }
	root := capture_prepared_root(source_root, 'package import')!
	defer { C.close(root) }
	options.checkpoint('root', source_root)!
	return pack_root_descriptor_with(recipe, root, repository, false, options)
}

// The catalog captures each architecture root once, so namespace aliases cannot
// switch its source directory between package imports.
fn pack_root_descriptor(recipe RootRecipe, root int, repository string, pinned bool) !Package {
	return pack_root_descriptor_with(recipe, root, repository, pinned, PackSourceOptions{})
}

fn pack_root_descriptor_with(recipe RootRecipe, root int, repository string, pinned bool, options PackSourceOptions) !Package {
	validate_root_recipe(recipe)!
	temporary := os.temp_dir()
	process := os.getpid().str()
	template_path := temporary + '/vinix-pack-root-' + process + '-XXXXXX'
	defer { unsafe { temporary.free(); process.free(); template_path.free() } }
	mut template := template_path.bytes()
	template << u8(0)
	defer { unsafe { template.free() } }
	created := C.mkdtemp(&char(template.data))
	if created == unsafe { nil } { return error('cannot create private import workspace') }
	work := unsafe { cstring_to_vstring(created).clone() }
	defer { os.rmdir_all(work) or {}; unsafe { work.free() } }
	mut pins := map[string]Payload{}
	defer { unsafe { pins.free() } }
	if pinned { for file in recipe.manifest.files { pins[file.path] = file } }
	payload := work + '/payload'
	manifest_path := work + '/manifest.json'
	defer { unsafe { payload.free(); manifest_path.free() } }
	mut importer := RootImport{ root: root, output: payload, pins: pins, options: options, ancestors: []ImportDirectoryIdentity{cap: max_pack_depth} }
	defer { unsafe { (&array(&importer.ancestors)).free() } }
	for entry in recipe.entries { importer.copy(entry.source, entry.path)! }
	manifest := publisher_json(recipe.manifest)
	defer { unsafe { manifest.free() } }
	os.write_file(manifest_path, manifest)!
	return pack(manifest_path, payload, repository)!
}
