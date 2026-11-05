// SPDX-License-Identifier: GPL-2.0-or-later
// Fixed read-only comparison with the qualified host bootstrap map.
// No subprocesses, compiler invocations or loader discovery are performed.
module main

import crypto.sha256
import json2
import os
import time

const state = '/Users/alex/Library/Caches/vinix-codex/section14/current-peer-frame-integration-20261105-01'
const setup = state + '/target-freeze-host-01'
const output = setup + '/tool-inputs-02'
const baseline = state + '/host-bootstrap-01/inputs-before.json'
const baseline_sha = 'e6582519df2c91330848552ba6f1bcd9582ea27a5757c667e12b6ad8bf5f61f5'
const clang = '/opt/homebrew/Cellar/llvm/23.1.0/bin/clang-23'
const resource_headers = '/opt/homebrew/Cellar/llvm/23.1.0/lib/clang/23/include'
const sdk = '/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk'
const sdk_alias = '/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk'
const scope = 'Complete named source/tool trees and loaded libraries; SDK metadata and clang resource headers, not a hermetic SDK inventory.'

struct Scan {
mut:
	started i64 = time.sys_mono_now()
	entries int
	bytes u64
}

fn require(ok bool, message string) ! {
	if !ok { return error(message) }
}

fn present(path string) bool { return os.exists(path) || os.is_link(path) }

fn bound(mut scan Scan) ! {
	scan.entries++
	require(scan.entries <= 100000 && scan.bytes <= u64(4) << 30
		&& time.sys_mono_now() - scan.started <= 120 * time.second,
		'fixed bootstrap input comparison bound')!
}

fn unchanged(before os.Stat, after os.Stat) bool {
	return before.dev == after.dev && before.inode == after.inode
		&& before.mode == after.mode && before.uid == after.uid && before.gid == after.gid
		&& before.nlink == after.nlink && before.size == after.size
		&& before.mtime == after.mtime && before.ctime == after.ctime
}

fn digest(path string, mut scan Scan) !string {
	before := os.lstat(path)!
	require(before.mode & 0o170000 == 0o100000, 'ordinary digest input required: ' + path)!
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	defer { unsafe { hash.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		bound(mut scan)!
		n := file.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		scan.bytes += u64(n)
		hash.write(buffer[..n])!
	}
	require(unchanged(before, os.lstat(path)!), 'file changed during hash: ' + path)!
	return hash.sum([]u8{}).hex()
}

// This is the exact mode/hash, directory and literal-link schema used by H.
fn leaf(path string, mut scan Scan) !string {
	bound(mut scan)!
	before := os.lstat(path)!
	kind := before.mode & 0o170000
	mode := (before.mode & 0o177777).str()
	mut value := ''
	if kind == 0o100000 { value = mode + ':' + digest(path, mut scan)! }
	else if kind == 0o040000 { value = mode + ':directory' }
	else if kind == 0o120000 {
		resolved := os.real_path(path)
		require(resolved != '' && resolved != path, 'dangling input link: ' + path)!
		value = mode + ':link:' + os.readlink(path)! + ':resolved:' + resolved
	} else { return error('unsupported bootstrap input: ' + path) }
	require(unchanged(before, os.lstat(path)!), 'input changed during observation: ' + path)!
	return value
}

fn tree(path string, ancestors []string, mut scan Scan, mut actual map[string]string) ! {
	require(ancestors.len <= 128 && path !in ancestors, 'input tree cycle/depth')!
	before := os.lstat(path)!
	actual[path] = leaf(path, mut scan)!
	mut next := ancestors.clone()
	next << path
	kind := before.mode & 0o170000
	if kind == 0o040000 {
		mut names := os.ls(path)!
		names.sort()
		for name in names { tree(path + '/' + name, next, mut scan, mut actual)! }
	} else if kind == 0o120000 {
		tree(os.real_path(path), next, mut scan, mut actual)!
	}
	require(unchanged(before, os.lstat(path)!), 'tree changed during comparison: ' + path)!
}

fn ordinary_directory(path string) ! {
	info := os.lstat(path)!
	require(os.real_path(path) == path && info.mode & 0o170000 == 0o040000
		&& info.uid == u32(os.getuid()) && info.mode & 0o022 == 0,
		'canonical owned directory required: ' + path)!
}

fn read_baseline(mut scan Scan) !map[string]string {
	before := os.lstat(baseline)!
	require(before.mode & 0o170000 == 0o100000 && before.size <= 4 * 1024 * 1024,
		'bounded ordinary qualified map required')!
	body := os.read_file(baseline)!
	require(unchanged(before, os.lstat(baseline)!)
		&& u64(body.len) == before.size && sha256.sum(body.bytes()).hex() == baseline_sha,
		'qualified H baseline changed')!
	bound(mut scan)!
	result := json2.decode[map[string]string](body)!
	require(result['scope'] == scope, 'qualified map scope differs')!
	return result
}

// H's user-owned source, compiler and result trees are checked separately by
// the original full auditor. This pass covers its recorded external files.
fn external_input(path string) bool {
	return path.starts_with('/') && !path.starts_with('/Users/alex/')
}

fn loader_filesystem(pins map[string]string, mut scan Scan) !(int, int) {
	mut checked := 0
	mut retained := 0
	for key, expected in pins {
		if !key.starts_with('loader:') { continue }
		retained++
		bound(mut scan)!
		if key.starts_with('loader:mode:') {
			path := key.all_after('loader:mode:')
			require(path.starts_with('/') && (os.lstat(path)!.mode & 0o177777).str() == expected,
				'loader path mode differs: ' + path)!
			checked++
		} else if key.starts_with('loader:link:') {
			path := key.all_after('loader:link:')
			require(path.starts_with('/') && os.is_link(path) && os.readlink(path)! == expected,
				'loader literal link differs: ' + path)!
			checked++
		} else if key.starts_with('loader:resolved:') {
			path := key.all_after('loader:resolved:')
			require(path.starts_with('/') && os.real_path(path) == expected,
				'loader resolved path differs: ' + path)!
			checked++
		} else if key.starts_with('loader:absent:') {
			path := key.all_after('loader:absent:')
			require(expected == 'absent' && path.starts_with('/') && !present(path),
				'previously absent loader candidate exists: ' + path)!
			checked++
		}
	}
	require(checked > 0 && retained > checked, 'complete qualified loader metadata required')!
	return checked, retained
}

fn selected_digest(pins map[string]string) string {
	mut keys := pins.keys()
	keys.sort()
	mut rows := []string{}
	for key in keys { rows << json2.encode({'path': key, 'value': pins[key]}) }
	return sha256.sum(rows.join('\n').bytes()).hex()
}

fn compare() !map[string]string {
	mut scan := Scan{}
	pins := read_baseline(mut scan)!
	for suffix in ['SDKSettings.json', 'SDKSettings.plist'] {
		canonical := sdk + '/' + suffix
		require(canonical in pins, 'canonical SDK metadata absent from qualified map')!
		require(leaf(canonical, mut scan)! == pins[canonical], 'canonical SDK metadata differs: ' + canonical)!
	}
	for path in [clang, resource_headers,
		'/opt/homebrew/Cellar/llvm/23.1.0/bin/llvm-ar',
		'/opt/homebrew/Cellar/llvm/23.1.0/bin/llvm-readelf',
		'/opt/homebrew/Cellar/llvm/23.1.0/bin/llvm-nm',
		'/opt/homebrew/Cellar/lld/23.1.0/bin/ld.lld',
		'/bin/df', '/usr/bin/du', '/usr/bin/xcrun', '/usr/bin/otool',
		'/usr/bin/file', '/bin/sh', '/usr/bin/env', '/opt/homebrew/bin/timeout'] {
		require(path in pins, 'required external root absent from qualified H map: ' + path)!
	}
	require('loader:otool-L:' + clang + '|' + clang in pins,
		'qualified clang loader record absent')!
	mut expected := map[string]string{}
	mut actual := map[string]string{}
	for path, value in pins {
		if !external_input(path) { continue }
		expected[path] = value
		actual[path] = leaf(path, mut scan)!
	}
	// Recursive enumeration supplies the required added/removed-header check;
	// comparing only pre-existing baseline paths would miss new inputs.
	tree(resource_headers, [], mut scan, mut actual)!
	require(actual == expected && expected.len > 100,
		'external tool/library or complete resource-header map differs')!
	loader_checked, loader_retained := loader_filesystem(pins, mut scan)!
	require(digest(baseline, mut scan)! == baseline_sha, 'qualified map drifted during comparison')!
	return {'baseline': baseline, 'baseline_sha256': baseline_sha,
		'external_entries': expected.len.str(), 'external_entries_sha256': selected_digest(expected),
		'loader_filesystem_entries_checked': loader_checked.str(),
		'loader_metadata_entries_bound_by_baseline': loader_retained.str(),
		'selected_sdk': sdk, 'sdk_alias_informational': sdk_alias,
		'sdk_alias_resolved_informational': os.real_path(sdk_alias), 'clang_resource_headers': resource_headers,
		'hashed_bytes': scan.bytes.str(), 'elapsed_ms': ((time.sys_mono_now() - scan.started) / time.millisecond).str(),
		'scope': 'Qualified H external file/link/directory values and complete clang resource headers compared; SDK settings only. Recorded loader filesystem state checked without subprocesses. Loader command text is bound by the exact H map and recorded binary/library bytes; no fresh otool/dyld discovery, hermetic SDK or user-owned compiler-tree qualification.'}
}

fn run() ! {
	$if !prod { return error('compile this fixed input checker with -prod for embedded source binding') }
	require(os.args.len == 2 && os.args[1] in ['--check-after-copier', '--check-after-freezer'],
		'fixed after-copier or after-freezer mode required')!
	require(os.read_file(@FILE)! == $embed_file('check-current-target-bootstrap-inputs.v').to_string(),
		'bootstrap input checker differs from compiled source')!
	ordinary_directory(setup)!
	if !present(output) { os.mkdir(output)! }
	ordinary_directory(output)!
	label := if os.args[1] == '--check-after-copier' { 'after-copier' } else { 'after-freezer' }
	directory := output + '/' + label
	require(!present(directory), 'fresh fixed comparison output required')!
	os.mkdir(directory)!
	result := compare() or {
		os.write_file(directory + '/failure.txt', err.msg() + '\n')!
		return err
	}
	body := json2.encode(result) + '\n'
	require(body.len <= 16384, 'small fixed comparison receipt required')!
	os.write_file(directory + '/comparison.json', body)!
	println('CURRENT TARGET BOOTSTRAP INPUTS PASS ' + label + ' ' + sha256.sum(body.bytes()).hex())
}

fn main() { run() or { eprintln(err); exit(1) } }
