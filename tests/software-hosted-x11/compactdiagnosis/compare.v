// SPDX-License-Identifier: GPL-2.0-or-later
// Compare complete original inventories; this neither captures nor seals a tree.
module compactdiagnosis

import crypto.sha256
import json2
import os

const inventory_limit = 8 * 1024 * 1024
const report_limit = 1024 * 1024
const original_scope = 'Complete quiescent root: regular bytes, literal links and directory metadata. Symlinks are never traversed. External link referents are not retained by this inventory. Trusted host; no hostile concurrent namespace guarantee.'

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

pub struct Summary {
pub:
	old_manifest_path string
	new_manifest_path string
	old_manifest_sha256 string
	new_manifest_sha256 string
	old_manifest_sha256_after string
	new_manifest_sha256_after string
	old_entries int
	new_entries int
	changed_entries int
	metadata_changes int
	refused_changes int
	accepted_metadata_only bool
}

struct Delta {
	index int
	path string
	field string
	before string
	after string
}

struct Report {
	scope string = 'Complete recorded-field comparison only. An original checker refusal remains refused; metadata differences do not qualify a tree or replace a fresh complete original seal/check.'
	summary Summary
	changes []Delta
}

fn need(ok bool, message string) ! { if !ok { return error(message) } }

pub fn source() string { return $embed_file('compare.v').to_string() }

fn absolute(path string) bool {
	return path.starts_with('/') && (path == '/'
		|| path[1..].split('/').all(it != '' && it != '.' && it != '..'))
}

fn same(a os.Stat, b os.Stat) bool {
	return a.dev == b.dev && a.inode == b.inode && a.mode == b.mode && a.uid == b.uid
		&& a.gid == b.gid && a.nlink == b.nlink && a.size == b.size
		&& a.mtime == b.mtime && a.ctime == b.ctime
}

fn read_inventory(path string) !string {
	before := os.lstat(path)!
	need(path.starts_with('/') && os.real_path(path) == path
		&& before.mode & 0o170000 == 0o100000 && before.size <= inventory_limit,
		'requires a canonical regular inventory of at most8MiB')!
	mut file := os.open(path)!
	defer { file.close() }
	mut bytes := []u8{cap: int(before.size)}
	mut buffer := []u8{len: 65536}
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		need(bytes.len + n <= inventory_limit, 'inventory grew beyond8MiB')!
		bytes << buffer[..n]
	}
	need(bytes.len == int(before.size) && same(before, os.lstat(path)!),
		'inventory changed during read')!
	return bytes.bytestr()
}

fn decoded(text string) !Manifest {
	m := json2.decode[Manifest](text, strict: true)!
	need(json2.encode(m) + '\n' == text, 'requires the exact canonical complete inventory schema')!
	need(m.format == 'frame-page-state-v1' && m.scope == original_scope
		&& absolute(m.root)
		&& m.entries.len > 0 && m.entries.len <= 250000
		&& m.entries[0].path == '.' && m.entries[0].kind == 'directory', 'invalid original inventory header')!
	mut seen := map[string]bool{}
	for e in m.entries {
		need(e.path != '' && !e.path.starts_with('/') && e.path !in seen
			&& (e.path == '.' || e.path.split('/').all(it != '' && it != '.' && it != '..'))
			&& e.kind in ['file', 'directory', 'symlink'], 'invalid or duplicate inventory entry')!
		seen[e.path] = true
	}
	return m
}

fn fields(e Entry) []string {
	return [e.path, e.kind, e.mode.str(), e.uid.str(), e.gid.str(), e.dev.str(),
		e.inode.str(), e.size.str(), e.mtime.str(), e.ctime.str(), e.sha256, e.target]
}

fn difference(a Manifest, b Manifest) ([]Delta, int, int, int) {
	mut changes := []Delta{}
	mut changed_entries := 0
	mut metadata := 0
	mut refused := 0
	for field, values in {'format': [a.format, b.format], 'root': [a.root, b.root], 'scope': [a.scope, b.scope]} {
		if values[0] != values[1] { changes << Delta{-1, '@manifest', field, values[0], values[1]}; refused++ }
	}
	names := ['path', 'kind', 'mode', 'uid', 'gid', 'dev', 'inode', 'size', 'mtime', 'ctime', 'sha256', 'target']
	upper := if a.entries.len > b.entries.len { a.entries.len } else { b.entries.len }
	for index in 0 .. upper {
		if index >= a.entries.len || index >= b.entries.len {
			before := if index < a.entries.len { json2.encode(a.entries[index]) } else { '' }
			after := if index < b.entries.len { json2.encode(b.entries[index]) } else { '' }
			changes << Delta{index, '@entry', 'entry', before, after}
			refused++; changed_entries++; continue
		}
		x, y := a.entries[index], b.entries[index]
		before, after := fields(x), fields(y)
		initial := changes.len
		for j, field in names {
			if before[j] == after[j] { continue }
			changes << Delta{index, x.path, field, before[j], after[j]}
			if field in ['dev', 'inode', 'mtime', 'ctime'] { metadata++ } else { refused++ }
		}
		if changes.len != initial { changed_entries++ }
	}
	return changes, changed_entries, metadata, refused
}

// Only dev/inode/mtime/ctime may differ. Every other drift is written in the
// bounded report and then refused. Neither complete input manifest is written.
pub fn compare(old_manifest_path string, new_manifest_path string, new_report_path string) !Summary {
	old_text, new_text := read_inventory(old_manifest_path)!, read_inventory(new_manifest_path)!
	a, b := decoded(old_text)!, decoded(new_text)!
	need(absolute(new_report_path)
		&& !os.exists(new_report_path) && !os.is_link(new_report_path)
		&& os.dir(new_report_path) == os.real_path(os.dir(new_report_path))
		&& os.lstat(os.dir(new_report_path))!.mode & 0o170000 == 0o040000,
		'requires a fresh canonical external report path')!
	for root in [a.root, b.root] {
		need(root != '/' && new_report_path != root && !new_report_path.starts_with(root + '/'),
			'report must remain outside original roots')!
	}
	changes, entries, metadata, refused := difference(a, b)
	old_before, new_before := sha256.hexhash(old_text), sha256.hexhash(new_text)
	old_after, new_after := sha256.hexhash(read_inventory(old_manifest_path)!), sha256.hexhash(read_inventory(new_manifest_path)!)
	need(old_before == old_after && new_before == new_after, 'complete inventory changed during comparison')!
	summary := Summary{old_manifest_path, new_manifest_path, old_before, new_before, old_after,
		new_after, a.entries.len, b.entries.len, entries, metadata, refused, refused == 0}
	text := json2.encode(Report{summary: summary, changes: changes}) + '\n'
	need(text.len <= report_limit, 'full diagnosis exceeds1MiB; no partial report written')!
	os.write_file(new_report_path, text)!
	need(sha256.hexhash(read_inventory(old_manifest_path)!) == old_before
		&& sha256.hexhash(read_inventory(new_manifest_path)!) == new_before, 'complete input changed after report write')!
	need(summary.accepted_metadata_only, 'recorded content, namespace or protected metadata drift; retained diagnosis: ' + new_report_path)!
	return summary
}
