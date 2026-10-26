module main

import crypto.sha256
import json2
import os

#include <sys/stat.h>
fn C.mkfifo(&char, u32) int

struct Entry {
	path   string
	kind   string
	mode   u32
	uid    u32
	gid    u32
	dev    u64
	inode  u64
	size   u64
	mtime  i64
	ctime  i64
	sha256 string
	target string
}

struct Manifest {
	format  string = 'frame-page-state-v1'
	root    string
	scope   string = 'Complete quiescent root: regular bytes, literal links and directory metadata. Symlinks are never traversed. External link referents are not retained by this inventory. Trusted host; no hostile concurrent namespace guarantee.'
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

fn capture(root string) !Manifest {
	if os.lstat(root)!.mode & 0o170000 != 0o040000 { return error('root must be an ordinary directory') }
	mut entries := []Entry{}
	visit(root, '.', 0, mut entries)!
	return Manifest{root: root, entries: entries}
}

fn check(root string, manifest string) ! {
	if os.lstat(manifest)!.mode & 0o170000 != 0o100000 { return error('manifest must be regular') }
	actual := json2.encode(capture(root)!)
	// Compare the complete canonical representation, refusing missing/extra keys,
	// duplicates, reordered entries and trailing data as well as changed objects.
	if os.read_file(manifest)! != actual + '\n' { return error('state inventory mismatch') }
}

fn seal(root string, output string) ! {
	if !output.starts_with('/') || os.exists(output) || os.is_link(output)
		|| os.real_path(os.dir(output)) != os.dir(output) {
		return error('output must be new with an existing canonical parent')
	}
	if output == root || output.starts_with(root + '/') { return error('output must be outside state') }
	first := json2.encode(capture(root)!)
	if first != json2.encode(capture(root)!) { return error('state changed between complete scans') }
	os.mkdir(output)!
	manifest := output + '/inventory.json'
	os.write_file(manifest, first + '\n')!
	check(root, manifest)!
	os.write_file(output + '/inventory.sha256', digest(manifest)! + '  inventory.json\n')!
	println('FRAME-PAGE COMPLETE STATE PASS ' + digest(manifest)!)
}

fn refuse_check(root string, manifest string) ! {
	check(root, manifest) or { return }
	return error('changed state unexpectedly accepted')
}

fn refuse_seal(root string, output string) ! {
	seal(root, output) or { return }
	return error('invalid seal destination accepted')
}

fn selfcheck(output string) ! {
	if !output.starts_with('/') || os.exists(output) || os.is_link(output) { return error('selfcheck output must be new') }
	os.mkdir(output)!
	root := output + '/state'
	os.mkdir(root)!
	os.mkdir(root + '/empty')!
	os.write_file(root + '/file with space', 'same-size bytes')!
	os.chmod(root + '/file with space', 0o644)!
	os.symlink('/this-target-does-not-exist', root + '/absolute')!
	os.symlink('cycle', root + '/cycle')!
	seal(root, output + '/sealed')!
	manifest := output + '/sealed/inventory.json'
	check(root, manifest)!
	refuse_seal(root, output + '/sealed')!
	refuse_seal(root, root + '/nested-output')!
	if os.exists(root + '/nested-output') { return error('refused destination was created') }
	check(root, manifest)!
	os.write_file(root + '/file with space', 'changed bytes!!')!
	refuse_check(root, manifest)!
	// A fresh seal avoids relying on timestamp restoration after each mutation.
	seal(root, output + '/changed')!
	os.write_file(root + '/extra', '')!
	refuse_check(root, output + '/changed/inventory.json')!
	os.rm(root + '/extra')!
	seal(root, output + '/before-missing')!
	os.rm(root + '/file with space')!
	refuse_check(root, output + '/before-missing/inventory.json')!
	os.write_file(root + '/file with space', 'changed bytes!!')!
	os.chmod(root + '/file with space', 0o644)!
	seal(root, output + '/before-link')!
	os.rm(root + '/absolute')!
	os.symlink('/different-target', root + '/absolute')!
	refuse_check(root, output + '/before-link/inventory.json')!
	seal(root, output + '/before-mode')!
	os.chmod(root + '/file with space', 0o600)!
	refuse_check(root, output + '/before-mode/inventory.json')!
	if C.mkfifo((root + '/fifo').str, 0o600) != 0 { return error('cannot create selfcheck FIFO') }
	if _ := capture(root) { return error('special object accepted') }
	println('FRAME-PAGE STATE SEAL CONTROLS PASS 9')
}

fn run() ! {
	if os.args.len == 3 && os.args[1] == 'selfcheck' { selfcheck(os.args[2])!; return }
	if os.args.len != 4 || os.args[1] !in ['seal', 'check'] { return error('use seal ROOT NEW-OUT | check ROOT MANIFEST | selfcheck NEW-OUT') }
	root := os.real_path(os.args[2])
	if root == '' || root != os.args[2] { return error('state root must be canonical') }
	if os.args[1] == 'seal' { seal(root, os.args[3])! }
	else { check(root, os.args[3])!; println('FRAME-PAGE COMPLETE STATE CHECK PASS') }
}

fn main() { run() or { eprintln(err); exit(1) } }
