// SPDX-License-Identifier: GPL-2.0-or-later
// Bind complete external evidence roots without copying their large images.
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
const repo = '/Users/alex/code/vinix'
const qemu = repo + '/build/qemu-horizontal/bin/qemu-system-aarch64'

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
	format int
	vm     string
	roots  []Root
}

struct Owner {
	pid     int
	command string
	started string
}

struct Stop {
	pid           int
	signal        string
	requested_utc string
}

struct Gone {
	pid              int
	ownership_sha256 string
	stop_sha256      string
	checked_utc      string
}

fn hash(path string) !string {
	mut input := os.open(path)!
	defer { input.close() }
	mut buffer := []u8{len: 1024 * 1024}
	mut state := C.CC_SHA256_CTX{}
	if C.CC_SHA256_Init(unsafe { &state }) != 1 { return error('SHA256 initialization') }
	for {
		n := input.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		if C.CC_SHA256_Update(unsafe { &state }, buffer.data, u32(n)) != 1 { return error('SHA256 update') }
	}
	mut result := [32]u8{}
	if C.CC_SHA256_Final(unsafe { &result[0] }, unsafe { &state }) != 1 { return error('SHA256 finalization') }
	return result[..].hex()
}

fn canonical(path string) !string {
	absolute := os.abs_path(path)
	if !os.is_dir(absolute) || os.is_link(absolute) || os.real_path(absolute) != absolute
		|| absolute.contains_any('\x00\r\n') || absolute == repo || absolute.starts_with(repo + '/') {
		return error('canonical external directory required: ' + path)
	}
	return absolute
}

fn inventory(root string, relative string, exclude_manifest bool, mut entries map[string]Entry) ! {
	mut names := os.ls(root + '/' + relative)!
	names.sort()
	for name in names {
		key := if relative == '' { name } else { relative + '/' + name }
		if exclude_manifest && key == 'manifest.json' { continue }
		path := root + '/' + key
		stat := os.lstat(path)!
		kind := stat.mode & 0o170000
		if kind == 0o040000 {
			entries[key] = Entry{kind: 'directory', mode: stat.mode}
			inventory(root, key, false, mut entries)!
		} else if kind == 0o100000 {
			entries[key] = Entry{kind: 'regular', mode: stat.mode, size: stat.size, sha256: hash(path)!}
		} else if kind == 0o120000 {
			entries[key] = Entry{kind: 'symlink', mode: stat.mode, target: os.readlink(path)!}
		} else {
			return error('special evidence entry refused: ' + path)
		}
	}
}

fn stopped(root string, require_absent bool) ! {
	owner := json2.decode[Owner](os.read_file(root + '/ownership.json')!)!
	stop := json2.decode[Stop](os.read_file(root + '/stop.json')!)!
	gone := json2.decode[Gone](os.read_file(root + '/gone.json')!)!
	if owner.pid <= 1 || owner.started == '' || !owner.command.starts_with(qemu + ' ')
		|| !owner.command.contains('unix:' + root + '/qmp.sock,server=on,wait=off')
		|| !owner.command.ends_with('-pidfile ' + root + '/qemu.pid')
		|| stop.pid != owner.pid || stop.signal != 'SIGTERM' || stop.requested_utc == ''
		|| gone.pid != owner.pid || gone.checked_utc == ''
		|| gone.ownership_sha256 != hash(root + '/ownership.json')!
		|| gone.stop_sha256 != hash(root + '/stop.json')! {
		return error('stopped VM ownership/stop/gone receipts do not match')
	}
	if require_absent {
		result := os.exec(['/bin/ps', '-ww', '-p', owner.pid.str(), '-o', 'lstart=,command='])
		if result.exit_code != 1 || result.output.trim_space() != '' {
			return error('recorded VM PID is not absent; seal requires a stopped guest')
		}
	}
}

fn write_json(path string, value json2.Any) ! {
	mut output := os.open_file(path, 'wx', 0o600)!
	defer { output.close() }
	output.write_string(json2.encode(value, prettify: true) + '\n')!
}

fn check(output_arg string, expected string) ! {
	output := canonical(output_arg)!
	if expected.len != 64 || hash(output + '/manifest.json')! != expected {
		return error('manifest hash differs')
	}
	manifest := json2.decode[Manifest](os.read_file(output + '/manifest.json')!)!
	if manifest.format != 1 || manifest.roots.len < 2 { return error('unsupported manifest') }
	mut seen := []string{}
	for root in manifest.roots {
		if canonical(root.path)! != root.path || root.path in seen {
			return error('duplicate or noncanonical manifest root')
		}
		seen << root.path
		mut current := map[string]Entry{}
		inventory(root.path, '', root.path == output, mut current)!
		if current != root.entries { return error('evidence tree differs: ' + root.path) }
	}
	if output !in seen || manifest.vm !in seen { return error('missing output or VM root') }
	// The recorded disappearance is historical evidence. PID reuse at a later
	// check does not invalidate that receipt; creating a seal requires absence.
	stopped(manifest.vm, false)!
	println('BROWSER-SEAL CHECK PASS roots=' + seen.len.str() + ' manifest=' + expected)
}

fn seal(output_arg string, arguments []string) ! {
	if arguments.len == 0 { return error('VM root required') }
	output := os.abs_path(output_arg)
	if os.exists(output) || os.is_link(output) { return error('fresh seal directory required') }
	parent := canonical(os.dir(output))!
	if output != parent + '/' + os.file_name(output) { return error('canonical output required') }
	mut roots := []string{}
	for argument in arguments {
		root := canonical(argument)!
		for prior in roots {
			if root == prior || root.starts_with(prior + '/') || prior.starts_with(root + '/') {
				return error('duplicate or overlapping evidence roots')
			}
		}
		if output == root || output.starts_with(root + '/') || root.starts_with(output + '/') {
			return error('seal output overlaps evidence')
		}
		roots << root
	}
	stopped(roots[0], true)!
	os.mkdir(output)!
	os.chmod(output, 0o700)!
	os.write_file(output + '/seal.v', source)!
	os.cp(os.executable(), output + '/seal')!
	write_json(output + '/metadata.json', json2.Any({
		'completed_utc': json2.Any(time.utc().str())
		'argv': json2.Any(os.args)
		'source_sha256': json2.Any(hash(output + '/seal.v')!)
		'tool_sha256': json2.Any(hash(output + '/seal')!)
		'scope': json2.Any('Complete original external trees bound in place; no images copied; stopped ownership required. Browser/account outcomes remain those recorded in the retained evidence.')
	}))!
	roots << output
	mut records := []Root{}
	mut count := 0
	for root in roots {
		mut entries := map[string]Entry{}
		inventory(root, '', root == output, mut entries)!
		count += entries.len
		records << Root{root, entries}
	}
	write_json(output + '/manifest.json', json2.decode[json2.Any](json2.encode(Manifest{1, roots[0], records}))!)!
	expected := hash(output + '/manifest.json')!
	check(output, expected)!
	println('BROWSER-SEAL PASS entries=' + count.str() + ' manifest=' + expected)
}

fn self_test() ! {
	root := os.join_path(os.real_path(os.temp_dir()), 'vinix-browser-seal-selftest-' + os.getpid().str())
	if os.exists(root) || os.is_link(root) { return error('fresh selftest root required') }
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	vm := root + '/vm'
	os.mkdir(vm)!
	mut child := os.new_process('/usr/bin/true')
	child.run()
	child.wait()
	pid := child.pid
	child.close()
	write_json(vm + '/ownership.json', json2.decode[json2.Any](json2.encode(Owner{pid,
		qemu + ' -qmp unix:' + vm + '/qmp.sock,server=on,wait=off -pidfile ' + vm + '/qemu.pid',
		'fixture exited child'}))!)!
	write_json(vm + '/stop.json', json2.decode[json2.Any](json2.encode(Stop{pid, 'SIGTERM', 'fixture'}))!)!
	write_json(vm + '/gone.json', json2.decode[json2.Any](json2.encode(Gone{pid,
		hash(vm + '/ownership.json')!, hash(vm + '/stop.json')!, 'fixture'}))!)!
	os.write_file(vm + '/data', 'original')!
	os.symlink('data', vm + '/link')!
	output := root + '/sealed'
	seal(output, [vm])!
	expected := hash(output + '/manifest.json')!
	for action in ['changed', 'added', 'missing', 'link', 'stop'] {
		match action {
			'changed' { os.write_file(vm + '/data', 'mutated')! }
			'added' { os.write_file(vm + '/extra', 'extra')! }
			'missing' { os.rm(vm + '/data')! }
			'link' { os.rm(vm + '/link')!; os.symlink('elsewhere', vm + '/link')! }
			else { os.write_file(vm + '/stop.json', '{}')! }
		}
		if _ := check(output, expected) { return error('accepted ' + action + ' evidence') }
		match action {
			'changed', 'missing' { os.write_file(vm + '/data', 'original')! }
			'added' { os.rm(vm + '/extra')! }
			'link' { os.rm(vm + '/link')!; os.symlink('data', vm + '/link')! }
			else { }
		}
	}
	if _ := stopped(vm, false) { return error('accepted changed stop receipt') }
	if _ := check(output, '0'.repeat(64)) { return error('accepted changed manifest hash') }
	os.rm(vm + '/ownership.json')!
	os.rm(vm + '/stop.json')!
	os.rm(vm + '/gone.json')!
	write_json(vm + '/ownership.json', json2.decode[json2.Any](json2.encode(Owner{os.getpid(),
		qemu + ' -qmp unix:' + vm + '/qmp.sock,server=on,wait=off -pidfile ' + vm + '/qemu.pid',
		'fixture live self'}))!)!
	write_json(vm + '/stop.json', json2.decode[json2.Any](json2.encode(Stop{os.getpid(), 'SIGTERM', 'fixture'}))!)!
	write_json(vm + '/gone.json', json2.decode[json2.Any](json2.encode(Gone{os.getpid(),
		hash(vm + '/ownership.json')!, hash(vm + '/stop.json')!, 'fixture'}))!)!
	if _ := stopped(vm, true) { return error('accepted live PID for sealing') }
	if C.mkfifo((vm + '/fifo').str, 0o600) != 0 { return error('selftest FIFO creation') }
	mut entries := map[string]Entry{}
	if _ := inventory(vm, '', false, mut entries) { return error('accepted special evidence entry') }
	println('BROWSER-SEAL SELF-TEST PASS full-tree changed added missing symlink stop-receipt manifest-pin live-pid special-entry')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' {
		self_test() or { eprintln(err); exit(1) }
		return
	}
	if os.args.len < 4 { eprintln('usage: seal seal FRESH_OUTPUT STOPPED_VM [EXTRA_ROOT ...] | check OUTPUT MANIFEST_SHA256'); exit(2) }
	if os.args[1] == 'seal' {
		seal(os.args[2], os.args[3..]) or { eprintln(err); exit(1) }
	} else if os.args[1] == 'check' && os.args.len == 4 {
		check(os.args[2], os.args[3]) or { eprintln(err); exit(1) }
	} else { eprintln('unsupported seal operation'); exit(2) }
}
