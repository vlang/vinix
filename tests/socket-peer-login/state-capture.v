// SPDX-License-Identifier: GPL-2.0-or-later
// Diagnostic single scan, derived from tests/kernel-allocs/frame-page-seal.v.
// This creates no seal and supplies no qualification against a saved inventory.
module main

import crypto.sha256
import json2
import os

struct Entry {
	path string
	kind string
	mode u32
	uid u32
	gid u32
	dev u64
	inode u64
	size u64
	mtime i64
	ctime i64
	sha256 string
	target string
}

struct Manifest {
	format string = 'frame-page-state-v1'
	root string
	scope string = 'Complete quiescent root: regular bytes, literal links and directory metadata. Symlinks are never traversed. External link referents are not retained by this inventory. Trusted host; no hostile concurrent namespace guarantee.'
	entries []Entry
}

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	defer { unsafe { hash.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		hash.write(buffer[..n])!
	}
	return hash.sum([]u8{}).hex()
}

fn visit(root string, relative string, depth int, mut entries []Entry) ! {
	if depth > 128 { return error('state nesting limit') }
	path := if relative == '.' { root } else { root + '/' + relative }
	before := os.lstat(path)!
	kind := before.mode & 0o170000
	if kind !in [u32(0o100000), u32(0o040000), u32(0o120000)] {
		return error('unsupported state object: ' + path)
	}
	hash := if kind == 0o100000 { digest(path)! } else { '' }
	target := if kind == 0o120000 { os.readlink(path)! } else { '' }
	entries << Entry{
		path: relative
		kind: if kind == 0o100000 { 'file' } else if kind == 0o040000 { 'directory' } else { 'symlink' }
		mode: before.mode
		uid: before.uid
		gid: before.gid
		dev: before.dev
		inode: before.inode
		size: if kind == 0o040000 { 0 } else { before.size }
		mtime: before.mtime
		ctime: before.ctime
		sha256: hash
		target: target
	}
	if kind == 0o040000 {
		mut names := os.ls(path)!
		names.sort()
		for name in names {
			if name in ['.', '..'] || name.contains('/') { return error('invalid state name') }
			next := if relative == '.' { name } else { relative + '/' + name }
			visit(root, next, depth + 1, mut entries)!
		}
	}
	after := os.lstat(path)!
	if before.dev != after.dev || before.inode != after.inode || before.mode != after.mode
		|| before.uid != after.uid || before.gid != after.gid || before.size != after.size
		|| before.mtime != after.mtime || before.ctime != after.ctime {
		return error('state object changed during read: ' + path)
	}
}

fn run() ! {
	if os.args.len != 3 { return error('use CANONICAL-ROOT NEW-DIAGNOSTIC-INVENTORY.json') }
	root := os.args[1]
	output := os.args[2]
	if root != os.real_path(root) || os.lstat(root)!.mode & 0o170000 != 0o040000 {
		return error('canonical ordinary directory root required')
	}
	if !output.starts_with('/') || os.exists(output) || os.is_link(output)
		|| os.dir(output) != os.real_path(os.dir(output))
		|| output == root || output.starts_with(root + '/') {
		return error('fresh diagnostic output outside root required')
	}
	mut entries := []Entry{}
	visit(root, '.', 0, mut entries)!
	text := json2.encode(Manifest{root: root, entries: entries}) + '\n'
	if text.len > 8 * 1024 * 1024 { return error('diagnostic inventory exceeds 8 MiB') }
	os.write_file(output, text)!
	println('DIAGNOSTIC SINGLE SCAN ONLY; NO SEAL OR ORIGINAL QUALIFICATION; entries=' + entries.len.str())
}

fn main() { run() or { eprintln(err); exit(1) } }
