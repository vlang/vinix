// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import time

#include <CommonCrypto/CommonDigest.h>
#include <sys/stat.h>
#include <dirent.h>
#include <errno.h>
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32
fn C.mkfifo(&char, u32) int
fn C.readdir(voidptr) &C.dirent
fn C.__error() &int

const compiled_source = $embed_file(@FILE).to_string()
const format_name = 'vinix-streamed-external-evidence-v1'
const max_roots = 1024
const max_names = 100000

struct Entry {
	kind string
	mode u32
	size u64
	sha256 string
	target string
}

struct Row {
	path string
	entry Entry
}

struct Root {
	path string
	inventory string
	entries u64
	sha256 string
}

struct Manifest {
	format string
	roots []Root
	output_entries map[string]Entry
}

fn same_stat(a os.Stat, b os.Stat) bool {
	return a.dev == b.dev && a.inode == b.inode && a.mode == b.mode && a.size == b.size
		&& a.mtime == b.mtime && a.ctime == b.ctime
}

fn digest(path string) !string {
	before := os.lstat(path)!
	if before.mode & 0o170000 != 0o100000 { return error('regular digest input required: ' + path) }
	mut input := os.open(path)!
	defer { input.close() }
	mut buffer := []u8{len: 1024 * 1024}
	mut state := C.CC_SHA256_CTX{}
	if C.CC_SHA256_Init(unsafe { &state }) != 1 { return error('SHA256 initialization') }
	for {
		n := input.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		if C.CC_SHA256_Update(unsafe { &state }, buffer.data, u32(n)) != 1 { return error('SHA256 update') }
	}
	mut result := [32]u8{}
	if C.CC_SHA256_Final(unsafe { &result[0] }, unsafe { &state }) != 1 { return error('SHA256 finalization') }
	if !same_stat(before, os.lstat(path)!) { return error('digest input changed: ' + path) }
	return result[..].hex()
}

fn canonical(path string) !string {
	absolute := os.abs_path(path)
	if absolute.contains_any('\x00\r\n') || os.is_link(absolute) || os.real_path(absolute) != absolute
		|| (!os.is_dir(absolute) && !os.is_file(absolute)) {
		return error('canonical regular file or directory required: ' + path)
	}
	return absolute
}

fn overlaps(a string, b string) bool {
	return a == b || a.starts_with(b + '/') || b.starts_with(a + '/') || a == '/' || b == '/'
}

fn validate_roots(paths []string, output string) ! {
	if paths.len == 0 || paths.len > max_roots { return error('require 1..1024 roots') }
	for i, path in paths {
		if canonical(path)! != path || overlaps(path, output) { return error('root/output overlap or noncanonical root') }
		for prior in paths[..i] {
			if overlaps(path, prior) { return error('duplicate or overlapping roots') }
		}
	}
}

fn entry(path string, info os.Stat) !Entry {
	kind := info.mode & 0o170000
	if kind == 0o040000 { return Entry{kind: 'directory', mode: info.mode} }
	if kind == 0o100000 { return Entry{kind: 'regular', mode: info.mode, size: info.size, sha256: digest(path)!} }
	if kind == 0o120000 { return Entry{kind: 'symlink', mode: info.mode, target: os.readlink(path)!} }
	return error('special evidence object refused: ' + path)
}

fn names_bounded(path string) ![]string {
	directory := unsafe { C.opendir(path.str) }
	if isnil(directory) { return error('cannot open directory: ' + path) }
	defer { C.closedir(directory) }
	mut names := []string{}
	for {
		errno_pointer := C.__error()
		unsafe { *errno_pointer = 0 }
		record := C.readdir(directory)
		if isnil(record) {
			if unsafe { *errno_pointer } != 0 { return error('cannot read complete directory: ' + path) }
			break
		}
		name := unsafe { cstring_to_vstring(&record.d_name[0]) }
		if name in ['', '.', '..'] { continue }
		if names.len >= max_names { return error('directory exceeds 100000 entries: ' + path) }
		names << name
	}
	names.sort()
	return names
}

fn visit(root string, key string, depth int, mut inventory os.File) !u64 {
	if depth > 128 { return error('evidence nesting limit') }
	path := if key == '.' { root } else { root + '/' + key }
	before := os.lstat(path)!
	record := entry(path, before)!
	inventory.write_string(json2.encode(Row{path: key, entry: record}) + '\n')!
	mut count := u64(1)
	if record.kind == 'directory' {
		names := names_bounded(path)!
		for name in names {
			next := if key == '.' { name } else { key + '/' + name }
			count += visit(root, next, depth + 1, mut inventory)!
		}
	}
	if !same_stat(before, os.lstat(path)!) { return error('evidence changed during read: ' + path) }
	return count
}

fn inventory(root string, destination string) !u64 {
	if os.exists(destination) || os.is_link(destination) { return error('fresh inventory required') }
	mut output := os.create(destination)!
	defer { output.close() }
	return visit(root, '.', 0, mut output)!
}

fn valid_pin(pin string) bool {
	return pin.len == 64 && pin.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

fn check(output string, expected string) ! {
	manifest_info := os.lstat(output + '/manifest.json')!
	if manifest_info.mode & 0o7777 != 0o600 { return error('manifest mode differs') }
	if canonical(output)! != output || !os.is_dir(output) || !valid_pin(expected)
		|| os.file_size(output + '/manifest.json') > 16 * 1024 * 1024
		|| digest(output + '/manifest.json')! != expected { return error('manifest pin differs') }
	manifest := json2.decode[Manifest](os.read_file(output + '/manifest.json')!)!
	if manifest.format != format_name { return error('unsupported manifest') }
	paths := manifest.roots.map(it.path)
	validate_roots(paths, output)!
	if manifest.output_entries.len != manifest.roots.len + 4 { return error('output entry count') }
	actual := names_bounded(output)!
	if actual.len != manifest.output_entries.len { return error('extra or missing output entry') }
	if manifest.output_entries['.'].kind != 'directory' { return error('output directory missing') }
	for name in ['seal.v', 'seal', 'metadata.json'] {
		if name !in manifest.output_entries || manifest.output_entries[name].kind != 'regular' {
			return error('required output file missing: ' + name)
		}
	}
	for name, wanted in manifest.output_entries {
		if name != '.' && (name.contains('/') || name in ['', '..', 'manifest.json']) { return error('unsafe output key') }
		path := if name == '.' { output } else { output + '/' + name }
		before := os.lstat(path)!
		if entry(path, before)! != wanted || !same_stat(before, os.lstat(path)!) { return error('output entry differs: ' + name) }
	}
	for name in actual {
		if name != 'manifest.json' && name !in manifest.output_entries { return error('unbound output entry: ' + name) }
	}
	if digest(output + '/seal.v')! != sha256.sum(compiled_source.bytes()).hex()
		|| digest(output + '/seal')! != digest(os.executable())! { return error('executing checker differs from seal') }
	temporary := os.real_path(os.temp_dir()) + '/vinix-stream-check-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	if os.exists(temporary) || os.is_link(temporary) { return error('fresh temporary directory required') }
	os.mkdir(temporary)!
	defer { os.rmdir_all(temporary) or {} }
	mut count := u64(0)
	for i, root in manifest.roots {
		name := 'inventory-' + i.str() + '.ndjson'
		if root.inventory != name || !valid_pin(root.sha256) || root.entries == 0 { return error('inventory descriptor differs') }
		if manifest.output_entries[name].sha256 != root.sha256 { return error('inventory pin differs') }
		path := temporary + '/' + name
		actual_count := inventory(root.path, path)!
		if actual_count != root.entries || digest(path)! != root.sha256 { return error('complete evidence tree differs: ' + root.path) }
		count += actual_count
		os.rm(path)!
	}
	println('STREAM-EVIDENCE CHECK PASS roots=' + paths.len.str() + ' entries=' + count.str() + ' manifest=' + expected)
}

fn seal(output string, roots []string) !string {
	if output != os.abs_path(output) || os.exists(output) || os.is_link(output)
		|| canonical(os.dir(output))! != os.dir(output) || !os.is_dir(os.dir(output)) {
		return error('fresh canonical output required')
	}
	validate_roots(roots, output)!
	os.mkdir(output)!
	os.chmod(output, 0o700)!
	os.write_file(output + '/seal.v', compiled_source)!
	os.cp(os.executable(), output + '/seal')!
	os.write_file(output + '/metadata.json', json2.encode({
		'created_utc': time.utc().str()
		'argv': json2.encode(os.args)
		'source_sha256': digest(output + '/seal.v')!
		'tool_sha256': digest(output + '/seal')!
		'scope': 'Complete quiescent external roots bound in place and rechecked using streamed sorted typed inventories. Regular bytes, modes, literal symlinks and empty directories are bound; symlink referents require explicit roots. Trusted host, without hostile concurrent namespace guarantees. This establishes no VM ownership, process exit, application result or authentication success. No evidence deletion is qualified.'
	}, prettify: true) + '\n')!
	mut records := []Root{}
	for i, root in roots {
		name := 'inventory-' + i.str() + '.ndjson'
		count := inventory(root, output + '/' + name)!
		records << Root{path: root, inventory: name, entries: count, sha256: digest(output + '/' + name)!}
	}
	mut own := map[string]Entry{}
	own['.'] = entry(output, os.lstat(output)!)!
	for name in names_bounded(output)! { own[name] = entry(output + '/' + name, os.lstat(output + '/' + name)!)! }
	os.write_file(output + '/manifest.json', json2.encode(Manifest{format: format_name, roots: records, output_entries: own}, prettify: true) + '\n')!
	os.chmod(output + '/manifest.json', 0o600)!
	pin := digest(output + '/manifest.json')!
	check(output, pin)!
	println('STREAM-EVIDENCE SEAL PASS manifest=' + pin)
	return pin
}

fn must_reject(output string, pin string) ! {
	check(output, pin) or { return }
	return error('changed evidence accepted')
}

fn self_test() ! {
	base := os.real_path(os.temp_dir()) + '/vinix-stream-selftest-' + os.getpid().str()
	if os.exists(base) { return error('fresh self-test directory required') }
	os.mkdir(base)!
	defer { os.rmdir_all(base) or {} }
	root := base + '/root'
	os.mkdir(root)!
	os.mkdir(root + '/empty')!
	os.write_file(root + '/file', 'content')!
	os.chmod(root + '/file', 0o640)!
	os.symlink('file', root + '/link')!
	output := base + '/sealed'
	pin := seal(output, [root])!
	os.write_file(root + '/file', 'changed')!; must_reject(output, pin)!
	os.write_file(root + '/file', 'content')!
	os.chmod(root + '/file', 0o600)!; must_reject(output, pin)!
	os.chmod(root + '/file', 0o640)!
	os.rm(root + '/link')!; os.symlink('absent', root + '/link')!; must_reject(output, pin)!
	os.rm(root + '/link')!; os.symlink('file', root + '/link')!
	os.write_file(root + '/extra', '')!; must_reject(output, pin)!; os.rm(root + '/extra')!
	os.rm(root + '/file')!; must_reject(output, pin)!; os.write_file(root + '/file', 'content')!; os.chmod(root + '/file', 0o640)!
	os.write_file(output + '/extra', '')!; must_reject(output, pin)!; os.rm(output + '/extra')!
	metadata := os.read_file(output + '/metadata.json')!
	os.write_file(output + '/metadata.json', metadata + 'changed')!; must_reject(output, pin)!
	os.write_file(output + '/metadata.json', metadata)!
	os.chmod(output + '/manifest.json', 0o644)!; must_reject(output, pin)!
	os.chmod(output + '/manifest.json', 0o600)!
	must_reject(output, '0'.repeat(64))!
	os.rmdir(root + '/empty')!; must_reject(output, pin)!; os.mkdir(root + '/empty')!
	check(output, pin)!
	if _ := seal(base + '/overlap', [root, root + '/empty']) { return error('overlap accepted') }
	if _ := seal(root + '/nested', [root]) { return error('nested output accepted') }
	if C.mkfifo((root + '/fifo').str, 0o600) != 0 { return error('self-test FIFO') }
	if _ := inventory(root, base + '/fifo-inventory') { return error('special object accepted') }
	os.rm(root + '/fifo')!
	// A 64 MiB sparse file exercises repeated bounded reads, checked against V's independent streaming implementation.
	sparse := base + '/sparse'
	mut file := os.create(sparse)!
	file.seek(64 * 1024 * 1024 - 1, .start)!; file.write([u8(0)])!; file.close()
	mut reference := sha256.new()
	zeros := []u8{len: 1024 * 1024}
	for _ in 0 .. 64 { reference.write(zeros)! }
	if digest(sparse)! != reference.sum([]u8{}).hex() { return error('sparse digest differs') }
	println('STREAM-EVIDENCE SELF-TEST PASS byte mode symlink missing extra output-extra output-byte manifest-mode pin emptydir special overlap nested-output sparse64MiB')
}

fn run() ! {
	if os.args.len == 2 && os.args[1] == '--self-test' { self_test()!; return }
	if os.args.len == 3 && os.args[1] == '--digest' { println(digest(os.args[2])!); return }
	if os.args.len == 6 && os.args[1] == 'seal' && os.args[2] == '--out' && os.args[4] == '--roots' {
		if os.file_size(os.args[5]) > 1024 * 1024 { return error('root list exceeds 1 MiB') }
		paths := os.read_file(os.args[5])!.trim_right('\n').split('\n')
		seal(os.args[3], paths)!
		return
	}
	if os.args.len == 6 && os.args[1] == 'check' && os.args[2] == '--out' && os.args[4] == '--pin' {
		check(os.args[3], os.args[5])!
		return
	}
	if os.args.len >= 4 && os.args[1] == 'seal' { seal(os.args[2], os.args[3..])!; return }
	if os.args.len == 4 && os.args[1] == 'check' { check(os.args[2], os.args[3])!; return }
	return error('use seal FRESH_OUTPUT CANONICAL_ROOT... | check OUTPUT MANIFEST_SHA256 | --self-test')
}

fn main() { run() or { eprintln(err); exit(1) } }
