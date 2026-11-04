// SPDX-License-Identifier: GPL-2.0-or-later
// Read-only diagnosis of A4 binding edits and retained fixture aliases.
module main

import crypto.sha256
import json2
import os

const old_root = '/Users/alex/Library/Caches/vinix-codex/section14/package-audio-portal/a4-matched-host-01'
const old_inventory = old_root + '-seal-02/complete/inventory.json'
const old_sum = 'bfb9db85b6253b2b6f0351f3e993c997f1c3604d106f944cd633b5c24a6e7572'
const source_root = '/Users/alex/code/vinix/build/package-audio-a4-prepare-worktree'
const fresh_root = '/Users/alex/Library/Caches/vinix-codex/section14/package-audio-portal/a4-atomic-fresh-host-20261026-01'
const output_parent = '/Users/alex/Library/Caches/vinix-codex/section14/package-audio-portal/a4-binding-alias-diagnostic-20261104-01'

struct Expected {
	relative string
	old_sum string
	new_sum string
}
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
	format string
	root string
	scope string
	entries []Entry
}
struct Observation {
	path string
	mode u32
	uid u32
	gid u32
	dev u64
	inode u64
	nlink u64
	size u64
	mtime i64
	ctime i64
	sha256 string
}
struct Finding {
	binding string
	old Entry
	current Observation
	changed_fields []string
	aliases_current_source bool
}
struct Group {
	binding string
	source Observation
	old_snapshot Observation
	new_snapshot Observation
	aliases []Observation
	all_current_links_accounted bool
}
struct Report {
	format int = 1
	result string = 'DIAGNOSIS COMPLETE; HISTORICAL BYTE MUTATION CONFIRMED'
	superseded_unchanged_history_receipt_sha256 string = '87c2d627fbf20fe1e08bd0a7a58342f670d30001a6618e23b9ad8d7af563b8b6'
	tool_source string
	tool_source_sha256 string
	old_inventory string
	old_inventory_sha256 string
	old_inventory_entries int
	groups []Group
	historical_candidates []Finding
	historical_byte_changes int
	scope string = 'Read-only comparison of original-inventory entries matching three edited paths or current source inodes, independent snapshots and aliases. Alias completeness is checked against current nlink; original inventory has no nlink. Prior unchanged-history claims are incorrect: source edits mutated four retained kernel-helper aliases. No repair, links, unlinks, resealing or requalification. Other metadata differences are recorded without attributing cause. No host, guest or audio qualification.'
}

fn digest(path string) !string {
	before := os.lstat(path)!
	if before.mode & 0o170000 != 0o100000 || before.size > (u64(32) << 20) {
		return error('requires bounded regular input: ' + path)
	}
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	defer { unsafe { hash.free() } }
	mut buffer := []u8{len: 65536}
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		hash.write(buffer[..n])!
	}
	return hash.sum([]u8{}).hex()
}

fn observe(path string) !Observation {
	before := os.lstat(path)!
	sum := digest(path)!
	after := os.lstat(path)!
	if before.dev != after.dev || before.inode != after.inode || before.nlink != after.nlink
		|| before.mode != after.mode || before.uid != after.uid || before.gid != after.gid
		|| before.size != after.size || before.mtime != after.mtime || before.ctime != after.ctime {
		return error('input changed during diagnosis: ' + path)
	}
	return Observation{path: path, mode: before.mode, uid: before.uid, gid: before.gid,
		dev: before.dev, inode: before.inode, nlink: before.nlink, size: before.size,
		mtime: before.mtime, ctime: before.ctime, sha256: sum}
}

fn same_inode(a Observation, b Observation) bool {
	return a.dev == b.dev && a.inode == b.inode
}

fn differences(old Entry, current Observation) []string {
	mut fields := []string{}
	for field, changed in {'kind': old.kind != 'file', 'mode': old.mode != current.mode,
		'uid': old.uid != current.uid, 'gid': old.gid != current.gid,
		'dev': old.dev != current.dev, 'inode': old.inode != current.inode,
		'size': old.size != current.size, 'mtime': old.mtime != current.mtime,
		'ctime': old.ctime != current.ctime, 'sha256': old.sha256 != current.sha256,
		'target': old.target != ''} {
		if changed { fields << field }
	}
	fields.sort()
	return fields
}

fn check() ! {
	if os.args.len != 2 { return error('use audio-binding-alias-diagnose FRESH_EXTERNAL_OUTPUT') }
	out := os.args[1]
	if !os.is_abs_path(out) || os.dir(out) != output_parent
		|| os.real_path(os.dir(out)) != os.dir(out)
		|| os.exists(out) || os.is_link(out) || out.bytes().any(it < 32 || it == 127)
		|| [old_root, source_root, fresh_root].any(out == it || out.starts_with(it + '/')) {
		return error('requires fresh external output with a canonical existing parent')
	}
	if digest(@FILE)! != sha256.hexhash($embed_file('audio-binding-alias-diagnose.v').to_string()) {
		return error('diagnosis source differs from compiled source')
	}
	if digest(old_inventory)! != old_sum { return error('original inventory pin differs') }
	text := os.read_file(old_inventory)!
	manifest := json2.decode[Manifest](text)!
	if manifest.format != 'frame-page-state-v1' || manifest.root != old_root
		|| manifest.entries.len > 250000 || text != json2.encode(manifest) + '\n' {
		return error('original complete inventory schema or scope differs')
	}
	expected := [
		Expected{'tests/packages/audiokernel/kernel.v', 'f5750020a869c5cf0e4f76e748dd5c416e97ef4fdc006d3ec4048e2a94679dd2', '6631cf071ead5f4aee4f263b6cbc88a0795802a5c73732a4563a3fb47db6621a'},
		Expected{'tests/packages/audio-portal-prepare-host.v', '77cf9ba85918ca5f4f51e3bdee5af6c0fb55e498a9bca0d51d3960b03202b123', '0f60f504d09def5ab3dd646006c2114c0cb93394ac625565e80907ac02fb57ad'},
		Expected{'tests/packages/audio-portal-prepare-run.v', 'cd0fbcec210d400938ef20ed7a4cc0f877cd10ab2248d77e7a7418e31e3be7de', '66a703b4d3730d932d6e04952764ed16d283ebd6450b62658b23210331e2d5cb'}
	]
	mut groups := []Group{}
	mut findings := []Finding{}
	for item in expected {
		source := observe(source_root + '/' + item.relative)!
		old := observe(old_root + '/qualification-07/source/' + item.relative)!
		fresh := observe(fresh_root + '/qualification-01/source/' + item.relative)!
		if source.sha256 != item.new_sum || old.sha256 != item.old_sum
			|| fresh.sha256 != item.new_sum || old.nlink != 1 || fresh.nlink != 1
			|| same_inode(source, old) || same_inode(source, fresh) {
			return error('binding or independent snapshot differs: ' + item.relative)
		}
		mut aliases := [source]
		for entry in manifest.entries {
			if entry.kind != 'file' || !(entry.path.ends_with('/' + item.relative)
				|| (entry.dev == source.dev && entry.inode == source.inode)) { continue }
			if os.is_abs_path(entry.path) || entry.path.split('/').any(it in ['', '.', '..']) {
				return error('invalid original relative path')
			}
			current := observe(old_root + '/' + entry.path)!
			shared := same_inode(source, current)
			findings << Finding{binding: item.relative, old: entry, current: current,
				changed_fields: differences(entry, current), aliases_current_source: shared}
			if shared { aliases << current }
		}
		fixture := fresh_root + '/qualification-01/prepare-controls/preparation/inputs/source/' + item.relative
		if os.exists(fixture) {
			current := observe(fixture)!
			if same_inode(source, current) { aliases << current }
		}
		mut paths := map[string]bool{}
		for alias in aliases {
			if alias.path in paths || alias.sha256 != source.sha256 || alias.nlink != source.nlink {
				return error('duplicate or inconsistent current alias')
			}
			paths[alias.path] = true
		}
		if u64(paths.len) != source.nlink || observe(source.path)! != source {
			return error('complete current alias set unaccounted for or source changed')
		}
		groups << Group{binding: item.relative, source: source, old_snapshot: old,
			new_snapshot: fresh, aliases: aliases, all_current_links_accounted: true}
	}
	mut changed := 0
	for finding in findings {
		if finding.old.sha256 == finding.current.sha256 { continue }
		if finding.binding != expected[0].relative || !finding.aliases_current_source
			|| finding.old.sha256 != expected[0].old_sum
			|| finding.current.sha256 != expected[0].new_sum
			|| finding.old.inode != finding.current.inode {
			return error('changed historical entry is not an expected retained kernel-helper alias')
		}
		// Saved and actual device IDs differ. Only current dev+inode establish
		// the current alias; no historical metadata equality is asserted.
		changed++
	}
	if changed != 4 || digest(old_inventory)! != old_sum {
		return error('historical mutation count or original inventory differs')
	}
	report := Report{tool_source: @FILE, tool_source_sha256: digest(@FILE)!,
		old_inventory: old_inventory, old_inventory_sha256: old_sum,
		old_inventory_entries: manifest.entries.len, groups: groups,
		historical_candidates: findings, historical_byte_changes: changed}
	os.mkdir(out, mode: 0o700)!
	os.write_file(out + '/diagnosis.json', json2.encode(report) + '\n')!
	println('AUDIO BINDING ALIAS DIAGNOSIS COMPLETE historical_byte_changes=' + changed.str())
}

fn main() { check() or { eprintln('audio-binding-alias-diagnose: ' + err.msg()); exit(1) } }
