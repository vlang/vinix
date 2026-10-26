// SPDX-License-Identifier: GPL-2.0-or-later
// Complete external evidence inventories. This records no VM ownership claim.
module main

import json2
import os
import time

#include <CommonCrypto/CommonDigest.h>
#include <sys/stat.h>
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32
fn C.mkfifo(&char, u32) int

const source = $embed_file(@FILE).to_string()

struct Entry {
	kind   string
	mode   u32
	size   u64
	sha256 string
	target string
}

struct Root {
	path    string
	entries map[string]Entry
}

struct Manifest {
	format string = 'pidfdwait-evidence-v1'
	roots  []Root
}

fn digest(path string) !string {
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
		if C.CC_SHA256_Update(unsafe { &state }, buffer.data, u32(n)) != 1 {
			return error('SHA256 update')
		}
	}
	mut result := [32]u8{}
	if C.CC_SHA256_Final(unsafe { &result[0] }, unsafe { &state }) != 1 {
		return error('SHA256 finalization')
	}
	return result[..].hex()
}

fn canonical(path string) !string {
	absolute := os.abs_path(path)
	if absolute.contains_any('\x00\r\n') || os.is_link(absolute)
		|| os.real_path(absolute) != absolute || (!os.is_dir(absolute) && !os.is_file(absolute)) {
		return error('canonical regular file or directory required: ' + path)
	}
	return absolute
}

fn visit(root string, key string, exclude_manifest bool, depth int, mut entries map[string]Entry) ! {
	if depth > 128 { return error('evidence nesting limit') }
	path := if key == '.' { root } else { root + '/' + key }
	before := os.lstat(path)!
	kind := before.mode & 0o170000
	if kind == 0o040000 {
		entries[key] = Entry{kind: 'directory', mode: before.mode}
		mut names := os.ls(path)!
		names.sort()
		for name in names {
			if exclude_manifest && key == '.' && name == 'manifest.json' { continue }
			next := if key == '.' { name } else { key + '/' + name }
			visit(root, next, false, depth + 1, mut entries)!
		}
	} else if kind == 0o100000 {
		entries[key] = Entry{kind: 'regular', mode: before.mode, size: before.size, sha256: digest(path)!}
	} else if kind == 0o120000 {
		entries[key] = Entry{kind: 'symlink', mode: before.mode, target: os.readlink(path)!}
	} else {
		return error('special evidence object refused: ' + path)
	}
	after := os.lstat(path)!
	if before.dev != after.dev || before.inode != after.inode || before.mode != after.mode
		|| before.size != after.size || before.mtime != after.mtime || before.ctime != after.ctime {
		return error('evidence changed during read: ' + path)
	}
}

fn tree(root string, exclude_manifest bool) !map[string]Entry {
	mut entries := map[string]Entry{}
	visit(root, '.', exclude_manifest, 0, mut entries)!
	return entries
}

fn check(output string, expected string) ! {
	if canonical(output)! != output || !os.is_dir(output) || expected.len != 64
		|| !expected.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
		|| digest(output + '/manifest.json')! != expected {
		return error('manifest pin differs')
	}
	manifest := json2.decode[Manifest](os.read_file(output + '/manifest.json')!)!
	if manifest.format != 'pidfdwait-evidence-v1' || manifest.roots.len < 2 {
		return error('unsupported manifest')
	}
	mut seen := []string{}
	for record in manifest.roots {
		if canonical(record.path)! != record.path || record.path in seen {
			return error('duplicate or noncanonical evidence root')
		}
		for prior in seen {
			if prior.starts_with(record.path + '/') || record.path.starts_with(prior + '/') {
				return error('overlapping evidence roots')
			}
		}
		seen << record.path
		if tree(record.path, record.path == output)! != record.entries {
			return error('complete evidence tree differs: ' + record.path)
		}
	}
	if output !in seen { return error('sealer output is not bound') }
	println('PIDFDWAIT-SEAL CHECK PASS roots=' + seen.len.str() + ' manifest=' + expected)
}

fn seal(output_arg string, arguments []string) !string {
	output := os.abs_path(output_arg)
	if arguments.len == 0 || os.exists(output) || os.is_link(output)
		|| canonical(os.dir(output))! != os.dir(output) || !os.is_dir(os.dir(output)) {
		return error('fresh canonical external output and evidence roots required')
	}
	mut roots := []string{}
	for argument in arguments {
		root := canonical(argument)!
		for prior in roots {
			if root == prior || root.starts_with(prior + '/') || prior.starts_with(root + '/') {
				return error('duplicate or overlapping evidence roots')
			}
		}
		if output == root || output.starts_with(root + '/') || root.starts_with(output + '/') {
			return error('output overlaps evidence')
		}
		roots << root
	}
	os.mkdir(output)!
	os.chmod(output, 0o700)!
	os.write_file(output + '/seal.v', source)!
	os.cp(os.executable(), output + '/seal')!
	os.write_file(output + '/metadata.json', json2.encode({
		'created_utc': time.utc().str()
		'argv': json2.encode(os.args)
		'source_sha256': digest(output + '/seal.v')!
		'tool_sha256': digest(output + '/seal')!
		'scope': 'Complete quiescent external roots bound in place, then fully rechecked; regular bytes, modes, literal symlinks, directories. Symlink referents require explicit roots. Trusted host; no hostile concurrent namespace guarantee. This tool establishes no VM ownership, execution, process exit or application outcome.'
	}, prettify: true) + '\n')!
	roots << output
	mut records := []Root{}
	mut count := 0
	for root in roots {
		entries := tree(root, root == output)!
		count += entries.len
		records << Root{root, entries}
	}
	os.write_file(output + '/manifest.json', json2.encode(Manifest{roots: records}, prettify: true) + '\n')!
	expected := digest(output + '/manifest.json')!
	check(output, expected)!
	println('PIDFDWAIT-SEAL PASS entries=' + count.str() + ' manifest=' + expected)
	return expected
}

fn refuse_check(output string, expected string) ! {
	check(output, expected) or { return }
	return error('changed evidence accepted')
}

fn self_test() ! {
	base := os.real_path(os.temp_dir()) + '/pidfdwait-seal-' + os.getpid().str()
	if os.exists(base) { return error('fresh self-test root required') }
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
	check(output, pin)!
	os.write_file(root + '/file', 'changed')!
	refuse_check(output, pin)!
	os.write_file(root + '/file', 'content')!
	os.chmod(root + '/file', 0o600)!
	refuse_check(output, pin)!
	os.chmod(root + '/file', 0o640)!
	os.rm(root + '/link')!
	os.symlink('absent', root + '/link')!
	refuse_check(output, pin)!
	os.rm(root + '/link')!
	os.symlink('file', root + '/link')!
	os.write_file(root + '/extra', '')!
	refuse_check(output, pin)!
	os.rm(root + '/extra')!
	os.rm(root + '/file')!
	refuse_check(output, pin)!
	os.write_file(root + '/file', 'content')!
	os.chmod(root + '/file', 0o640)!
	check(output, pin)!
	refuse_check(output, '0'.repeat(64))!
	os.write_file(output + '/manifest.json', '{}\n')!
	refuse_check(output, pin)!
	if _ := seal(base + '/overlap', [root, root + '/empty']) { return error('overlap accepted') }
	if _ := seal(root + '/nested', [root]) { return error('nested output accepted') }
	if C.mkfifo((root + '/fifo').str, 0o600) != 0 { return error('self-test FIFO') }
	if _ := tree(root, false) { return error('special object accepted') }
	println('PIDFDWAIT-SEAL SELF-TEST PASS controls=10')
}

fn run() ! {
	if os.args.len == 2 && os.args[1] == '--self-test' { self_test()!; return }
	if os.args.len >= 4 && os.args[1] == 'seal' {
		seal(os.args[2], os.args[3..])!
		return
	}
	if os.args.len == 4 && os.args[1] == 'check' { check(os.args[2], os.args[3])!; return }
	return error('use seal FRESH_OUTPUT ROOT... | check OUTPUT MANIFEST_SHA256 | --self-test')
}

fn main() { run() or { eprintln(err); exit(1) } }
