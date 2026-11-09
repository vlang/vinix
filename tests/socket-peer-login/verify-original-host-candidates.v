// SPDX-License-Identifier: GPL-2.0-or-later
// Fixed read-only coverage of retained candidate bytes against the original H
// map. The sole write is a fresh receipt; no candidate or original is restored.
module main

import crypto.sha256
import json2
import os
import time

#include <errno.h>
#include <fcntl.h>
#include <unistd.h>

const baseline = '/Users/alex/Library/Caches/vinix-codex/section14/current-peer-frame-integration-20261105-01/host-bootstrap-01/inputs-before.json'
const baseline_sha = 'e6582519df2c91330848552ba6f1bcd9582ea27a5757c667e12b6ad8bf5f61f5'
const old_root = '/Users/alex/code/vinix/build/package-https-runtime-work/toolchain'
const recovery = '/Users/alex/Library/Caches/vinix-codex/section14/current-peer-frame-integration-20261105-01/original-host-recovery-01'

struct Scan {
mut:
	started i64 = time.sys_mono_now()
	entries int
	bytes u64
}

struct Observed {
	value string
	identity string
}

struct Planned {
	path string
	required string
	payload_candidates []string
	strict_candidates []string
}

struct Receipt {
	format string = 'original-host-candidate-coverage-v1'
	baseline string
	baseline_sha256 string
	old_root string
	candidate_roots []string
	expected_entries int
	reconstructable_complete bool
	strict_metadata_complete bool
	plan []Planned
	uncovered []string
	observations map[string]string
	source_before map[string]string
	source_after map[string]string
	namespace_before map[string][]string
	namespace_after map[string][]string
	hashed_bytes u64
	elapsed_ns i64
	scope string
}

fn need(ok bool, message string) ! { if !ok { return error(message) } }
fn present(path string) bool { return os.exists(path) || os.is_link(path) }
fn candidates() []string {
	return ['/Users/alex/.cache/vinix-waitpid-width-20261026-01/toolchain',
		'/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain']
}
fn under(path string, root string) bool { return path == root || path.starts_with(root + '/') }

fn bound(mut scan Scan) ! {
	scan.entries++
	need(scan.entries <= 100000 && scan.bytes <= u64(4) << 30
		&& time.sys_mono_now() - scan.started <= 120 * time.second,
		'fixed candidate verification entry/byte/wall bound')!
}

fn unchanged(before os.Stat, after os.Stat) bool {
	return before.dev == after.dev && before.inode == after.inode && before.mode == after.mode
		&& before.uid == after.uid && before.gid == after.gid && before.nlink == after.nlink
		&& before.size == after.size && before.mtime == after.mtime && before.ctime == after.ctime
}

fn digest(path string, mut scan Scan) !string {
	before := os.lstat(path)!
	need(before.mode & 0o170000 == 0o100000, 'ordinary hash input required: ' + path)!
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	defer { unsafe { hash.free() } }
	mut buffer := []u8{len: 65536}
	defer { unsafe { buffer.free() } }
	for {
		bound(mut scan)!
		n := file.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		scan.bytes += u64(n)
		hash.write(buffer[..n])!
	}
	need(unchanged(before, os.lstat(path)!), 'source changed during hash: ' + path)!
	return hash.sum([]u8{}).hex()
}

fn inspect(path string, mut scan Scan) !Observed {
	bound(mut scan)!
	before := os.lstat(path)!
	need(before.uid == u32(os.getuid()), 'candidate input owner differs: ' + path)!
	mode := (before.mode & 0o177777).str()
	kind := before.mode & 0o170000
	mut value := ''
	if kind == 0o100000 {
		need(before.nlink == 1, 'candidate file aliases another inode name: ' + path)!
		value = mode + ':' + digest(path, mut scan)!
	} else if kind == 0o040000 {
		need(os.real_path(path) == path && before.mode & 0o022 == 0,
			'canonical privately writable directory required: ' + path)!
		value = mode + ':directory'
	} else if kind == 0o120000 {
		resolved := os.real_path(path)
		need(resolved != '' && resolved != path, 'candidate link has no canonical referent: ' + path)!
		value = mode + ':link:' + os.readlink(path)! + ':resolved:' + resolved
	} else { return error('candidate special entry refused: ' + path) }
	need(unchanged(before, os.lstat(path)!), 'candidate changed during observation: ' + path)!
	identity := [before.dev.str(), before.inode.str(), before.mode.str(), before.uid.str(),
		before.gid.str(), before.nlink.str(), before.size.str(), before.mtime.str(), before.ctime.str(), value].join(':')
	return Observed{value, identity}
}

fn namespace(path string, relative string, depth int, mut scan Scan, mut names []string) ! {
	bound(mut scan)!
	need(depth <= 128 && names.len < 100000, 'candidate namespace depth/entry bound')!
	before := os.lstat(path)!
	names << relative
	if before.mode & 0o170000 == 0o040000 {
		need(os.real_path(path) == path && before.uid == u32(os.getuid()) && before.mode & 0o022 == 0,
			'canonical owned candidate namespace required')!
		for name in os.ls(path)! {
			need(name !in ['', '.', '..'] && !name.contains('\x00'), 'invalid candidate child name')!
			namespace(path + '/' + name, if relative == '.' { name } else { relative + '/' + name },
				depth + 1, mut scan, mut names)!
		}
	} else {
		need(before.mode & 0o170000 in [u32(0o100000), 0o120000], 'candidate special namespace entry')!
	}
	need(unchanged(before, os.lstat(path)!), 'candidate namespace changed during enumeration')!
}

fn expected(root_map map[string]string) !map[string]string {
	mut result := map[string]string{}
	for path, value in root_map {
		if !under(path, old_root) { continue }
		relative := if path == old_root { '.' } else { path[old_root.len + 1..] }
		need(relative == '.' || !relative.split('/').any(it in ['', '.', '..']), 'invalid original relative path')!
		mode := value.all_before(':')
		need(mode != '' && mode.bytes().all(it >= `0` && it <= `9`), 'original mode schema differs')!
		kind := mode.u32() & 0o170000
		tail := value.all_after(':')
		need((kind == 0o040000 && tail == 'directory')
			|| (kind == 0o100000 && tail.len == 64 && tail.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`)))
			|| (kind == 0o120000 && tail.starts_with('link:') && tail.contains(':resolved:/')),
			'original leaf schema differs: ' + path)!
		result[relative] = value
	}
	need(result.len > 100 && result.len <= 10000 && result['.'] == '16877:directory',
		'complete original toolchain namespace required')!
	for relative, _ in result {
		if relative == '.' { continue }
		parent := if !relative.contains('/') { '.' } else { relative.all_before_last('/') }
		need(parent in result && result[parent].ends_with(':directory'), 'original namespace parent missing')!
	}
	return result
}

fn rebased(value string, candidate string) string {
	if !value.contains(':link:') { return value }
	resolved := value.all_after_last(':resolved:')
	if under(resolved, old_root) {
		return value.all_before_last(':resolved:') + ':resolved:' + candidate + resolved[old_root.len..]
	}
	return value
}

fn write_receipt(path string, body string) ! {
	need(body.len <= 8 * 1024 * 1024, 'complete candidate receipt exceeds 8MiB')!
	fd := unsafe { C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_CLOEXEC, 0o600) }
	if fd < 0 { return os.error_posix() }
	mut closed := false
	defer { if !closed { C.close(fd) } }
	mut offset := usize(0)
	for offset < usize(body.len) {
		n := C.write(fd, unsafe { body.str + offset }, usize(body.len) - offset)
		if n < 0 { if C.errno == C.EINTR { continue }; return os.error_posix() }
		need(n > 0, 'candidate receipt write made no progress')!
		offset += usize(n)
	}
	if C.fsync(fd) != 0 { return os.error_posix() }
	status := C.close(fd)
	closed = true
	if status != 0 { return os.error_posix() }
}

fn run() ! {
	$if !prod { return error('compile the fixed verifier with -prod for source binding') }
	need(os.args.len == 3 && os.args[1] == '--verify', 'fixed --verify NEWRECEIPT mode required')!
	need(os.read_file(@FILE)! == $embed_file('verify-original-host-candidates.v').to_string(),
		'candidate verifier source differs from compiled bytes')!
	output := os.args[2]
	need(under(output, recovery) && output != recovery && !present(output)
		&& os.real_path(os.dir(output)) == os.dir(output), 'fresh canonical recovery receipt required')!
	parent := os.lstat(os.dir(output))!
	need(parent.mode & 0o170000 == 0o040000 && parent.uid == u32(os.getuid())
		&& parent.mode & 0o022 == 0, 'owned recovery receipt parent required')!
	mut scan := Scan{}
	baseline_before := os.lstat(baseline)!
	need(baseline_before.size <= 4 * 1024 * 1024 && digest(baseline, mut scan)! == baseline_sha,
		'original complete H baseline differs')!
	text := os.read_file(baseline)!
	need(sha256.hexhash(text) == baseline_sha, 'baseline read changed')!
	pins := expected(json2.decode[map[string]string](text)!)!
	mut paths := pins.keys()
	paths.sort()
	mut namespaces := map[string][]string{}
	for candidate in candidates() {
		mut names := []string{}
		namespace(candidate, '.', 0, mut scan, mut names)!
		names.sort()
		namespaces[candidate] = names
	}
	mut plan := []Planned{}
	mut uncovered := []string{}
	mut notes := map[string]string{}
	mut before := map[string]string{}
	mut source_paths := map[string]string{}
	mut strict_complete := true
	for relative in paths {
		mut payload := []string{}
		mut strict := []string{}
		for i, candidate in candidates() {
			path := if relative == '.' { candidate } else { candidate + '/' + relative }
			id := i.str() + '/' + relative
			observation := inspect(path, mut scan) or {
				notes[id] = 'unavailable: ' + err.msg() + '; code=' + err.code().str()
				continue
			}
			before[id] = observation.identity
			source_paths[id] = path
			want := rebased(pins[relative], candidate)
			if observation.value == want { strict << id }
			else { notes[id] = 'metadata/content differs: expected=' + want + '; actual=' + observation.value }
			if observation.value.all_before(':').u32() & 0o170000 == want.all_before(':').u32() & 0o170000
				&& observation.value.all_after(':') == want.all_after(':') { payload << id }
		}
		if payload.len == 0 { uncovered << relative }
		if strict.len == 0 { strict_complete = false }
		plan << Planned{relative, pins[relative], payload, strict}
	}
	mut after := map[string]string{}
	for id, path in source_paths { after[id] = inspect(path, mut scan)!.identity }
	need(before == after, 'candidate source identities changed during coverage verification')!
	mut namespaces_after := map[string][]string{}
	for candidate in candidates() {
		mut names := []string{}
		namespace(candidate, '.', 0, mut scan, mut names)!
		names.sort()
		namespaces_after[candidate] = names
	}
	need(namespaces == namespaces_after, 'candidate relative namespace changed during verification')!
	need(unchanged(baseline_before, os.lstat(baseline)!) && digest(baseline, mut scan)! == baseline_sha,
		'original baseline changed during coverage verification')!
	bound(mut scan)!
	receipt := Receipt{baseline: baseline, baseline_sha256: baseline_sha, old_root: old_root,
		candidate_roots: candidates(), expected_entries: paths.len, reconstructable_complete: uncovered.len == 0,
		strict_metadata_complete: strict_complete, plan: plan, uncovered: uncovered, observations: notes,
		source_before: before, source_after: after, namespace_before: namespaces, namespace_after: namespaces_after,
		hashed_bytes: scan.bytes, elapsed_ns: time.sys_mono_now() - scan.started,
		scope: 'Complete original H relative namespace covered only by byte/type/literal-link/resolved-link-equal retained entries. Strict metadata matching is separate; required H modes remain explicit for any future independent restoration. No copying, candidate modification, original restoration, original-auditor pass or runtime qualification.'}
	write_receipt(output, json2.encode(receipt) + '\n')!
	bound(mut scan)!
	println('ORIGINAL HOST CANDIDATE COVERAGE entries=' + paths.len.str() + ' uncovered=' + uncovered.len.str()
		+ ' strict_metadata_complete=' + strict_complete.str())
	need(uncovered.len == 0, 'complete original candidate coverage refused; retain receipt')!
}

fn main() { run() or { eprintln(err); exit(1) } }
