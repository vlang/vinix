// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import tools.packages.pkgprotocol

// Bound directory work as well as the manifest's regular-file count. The root
// is depth zero; at most 128 descendant directory levels are traversed.
const max_pack_depth = 128
const max_pack_entries = max_files * 2

struct PackSourceOptions {
	checkpoint fn (string, string) ! = mirror_no_checkpoint
}

struct PackSource {
	repository string
	options PackSourceOptions
mut:
	entries int
	bytes u64
	files []Payload
}

fn check_pack_node(parent int, name string, node ImportNode, relative string) ! {
	mut opened := C.stat{}
	mut named := C.stat{}
	if C.fstat(node.fd, &opened) != 0 || u64(opened.st_dev) != node.device
		|| u64(opened.st_ino) != node.inode || u32(opened.st_mode) & 0o170111 != node.mode & 0o170111
		|| C.fstatat(parent, name.str, &named, C.AT_SYMLINK_NOFOLLOW) != 0
		|| u64(named.st_dev) != node.device || u64(named.st_ino) != node.inode
		|| u32(named.st_mode) & 0o170111 != node.mode & 0o170111 {
		return error('package source identity or executable mode changed while packing: ${relative}')
	}
	if node.mode & 0o170000 == 0o100000 && (opened.st_size < 0 || named.st_size < 0
		|| u64(opened.st_size) != node.bytes || u64(named.st_size) != node.bytes) {
		return error('package source changed size while packing: ${relative}')
	}
}

fn (mut source PackSource) admit(bytes u64) ! {
	if source.files.len >= max_files || bytes > u64(4) << 30
		|| source.bytes > (u64(64) << 30) - bytes {
		return error('package source exceeds file or payload size limits')
	}
	source.bytes += bytes
}

fn (mut source PackSource) walk(directory int, prefix string, depth int) ! {
	names := import_names(directory)!
	defer { unsafe { names.free() } }
	if names.len > max_pack_entries - source.entries {
		return error('package source exceeds directory entry limit')
	}
	source.entries += names.len
	for name in names {
		relative := if prefix == '' { name.clone() } else { prefix + '/' + name }
		defer { unsafe { relative.free() } }
		if !relative_path(relative) { return error('package source contains an unsafe path: ${relative}') }
		source.entry(directory, name, relative, depth)!
	}
}

fn (mut source PackSource) entry(parent int, name string, relative string, depth int) ! {
	// Neither a raced directory alias nor a leaf FIFO can redirect or block this
	// open. Each recursive step retains its own captured directory descriptor.
	fd := C.openat(parent, name.str, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 { return error('cannot open ordinary package source entry without following symlinks: ${relative}') }
	defer { C.close(fd) }
	mut info := C.stat{}
	if C.fstat(fd, &info) != 0 || info.st_mode & 0o170000 !in [0o040000, 0o100000] || info.st_size < 0 {
		return error('package source contains an invalid or special file: ${relative}')
	}
	node := ImportNode{ fd: fd, mode: u32(info.st_mode), bytes: u64(info.st_size),
		device: u64(info.st_dev), inode: u64(info.st_ino) }
	source.options.checkpoint('opened', relative)!
	check_pack_node(parent, name, node, relative)!
	if node.mode & 0o170000 == 0o040000 {
		if depth >= max_pack_depth { return error('package source exceeds directory depth limit: ${relative}') }
		source.options.checkpoint('directory', relative)!
		source.walk(fd, relative, depth + 1)!
		check_pack_node(parent, name, node, relative)!
		return
	}
	source.admit(node.bytes)!
	source.options.checkpoint('sized', relative)!
	digest := hash_opened(fd, node.bytes, relative, HashReadOptions{ checkpoint: source.options.checkpoint })!
	source.options.checkpoint('hashed', relative)!
	check_pack_node(parent, name, node, relative)!
	payload := Payload{ path: relative.clone(), bytes: node.bytes, sha256: digest, executable: node.mode & 0o111 != 0 }
	target := source.repository + '/objects/' + digest
	if !verified_file(target, payload) {
		input := CopySource{ fd: fd, bytes: node.bytes, device: node.device, inode: node.inode }
		copy_opened(input, relative, target + '.new', 0, pkgprotocol.Progress{}, no_progress)!
		if !verified_file(target + '.new', payload) {
			return error('package source changed contents while packing: ${relative}')
		}
		source.options.checkpoint('copied', relative)!
		check_pack_node(parent, name, node, relative)!
		os.rename(target + '.new', target)!
	} else {
		source.options.checkpoint('cached', relative)!
		check_pack_node(parent, name, node, relative)!
	}
	source.files << payload
}
