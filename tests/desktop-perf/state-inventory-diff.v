// SPDX-License-Identifier: GPL-2.0-or-later
// Diagnostic comparison only: never replaces a complete original state check.
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

struct Change {
	path string
	field string
	before string
	after string
}

struct Difference {
	scope string = 'Diagnostic comparison of every recorded manifest field; does not qualify the current tree against the original inventory or replace an original checker refusal.'
	original_sha256 string
	current_sha256 string
	original_entries int
	current_entries int
	missing []string
	extra []string
	changes []Change
	verdict string
}

fn decoded(text string) !Manifest {
	m := json2.decode[Manifest](text)!
	if json2.encode(m) + '\n' != text { return error('inventory is not the exact canonical complete schema') }
	if m.format != 'frame-page-state-v1' || !m.root.starts_with('/') || m.entries.len == 0
		|| m.entries[0].path != '.' { return error('unsupported inventory header or root entry') }
	mut seen := map[string]bool{}
	for entry in m.entries {
		if entry.path == '' || entry.path in seen || entry.path.starts_with('/')
			|| entry.path.split('/').any(it == '..') || entry.kind !in ['file', 'directory', 'symlink'] {
			return error('invalid or duplicate inventory entry')
		}
		seen[entry.path] = true
	}
	return m
}

fn changed(path string, field string, before string, after string, mut changes []Change) {
	if before != after { changes << Change{path, field, before, after} }
}

fn compare(original_text string, current_text string) !Difference {
	a := decoded(original_text)!
	b := decoded(current_text)!
	mut changes := []Change{}
	changed('@manifest', 'format', a.format, b.format, mut changes)
	changed('@manifest', 'root', a.root, b.root, mut changes)
	changed('@manifest', 'scope', a.scope, b.scope, mut changes)
	mut originals := map[string]Entry{}
	mut currents := map[string]Entry{}
	for entry in a.entries { originals[entry.path] = entry }
	for entry in b.entries { currents[entry.path] = entry }
	mut missing := []string{}
	mut extra := []string{}
	for x in a.entries {
		if x.path !in currents { missing << x.path; continue }
		y := currents[x.path]
		changed(x.path, 'kind', x.kind, y.kind, mut changes)
		changed(x.path, 'mode', x.mode.str(), y.mode.str(), mut changes)
		changed(x.path, 'uid', x.uid.str(), y.uid.str(), mut changes)
		changed(x.path, 'gid', x.gid.str(), y.gid.str(), mut changes)
		changed(x.path, 'dev', x.dev.str(), y.dev.str(), mut changes)
		changed(x.path, 'inode', x.inode.str(), y.inode.str(), mut changes)
		changed(x.path, 'size', x.size.str(), y.size.str(), mut changes)
		changed(x.path, 'mtime', x.mtime.str(), y.mtime.str(), mut changes)
		changed(x.path, 'ctime', x.ctime.str(), y.ctime.str(), mut changes)
		changed(x.path, 'sha256', x.sha256, y.sha256, mut changes)
		changed(x.path, 'target', x.target, y.target, mut changes)
	}
	for entry in b.entries { if entry.path !in originals { extra << entry.path } }
	// Entry order is part of the original complete canonical representation.
	if a.entries.map(it.path) != b.entries.map(it.path) && missing.len == 0 && extra.len == 0 {
		changed('@manifest', 'entry_order', json2.encode(a.entries.map(it.path)),
			json2.encode(b.entries.map(it.path)), mut changes)
	}
	verdict := if missing.len == 0 && extra.len == 0 && changes.len == 0 { 'IDENTICAL' }
		else if missing.len == 0 && extra.len == 0 && changes.all(it.field == 'dev') { 'DEVICE-ONLY DIFFERENCE; original qualification remains refused' }
		else { 'DIFFERENT; original qualification remains refused' }
	return Difference{
		original_sha256: sha256.sum(original_text.bytes()).hex()
		current_sha256: sha256.sum(current_text.bytes()).hex()
		original_entries: a.entries.len
		current_entries: b.entries.len
		missing: missing
		extra: extra
		changes: changes
		verdict: verdict
	}
}

fn encoded(m Manifest) string { return json2.encode(m) + '\n' }

fn selfcheck() ! {
	a := Manifest{root: '/fixture', entries: [Entry{path: '.', kind: 'directory', mode: 0o40755, dev: 1},
		Entry{path: 'file', kind: 'file', mode: 0o100644, dev: 1, sha256: 'a'.repeat(64)}]}
	if compare(encoded(a), encoded(a))!.verdict != 'IDENTICAL' { return error('identical refused') }
	b := Manifest{...a, entries: a.entries.map(Entry{...it, dev: 2})}
	device := compare(encoded(a), encoded(b))!
	if device.changes.len != 2 || !device.verdict.starts_with('DEVICE-ONLY') { return error('device changes missed') }
	x := a.entries[1]
	c := Manifest{...a, entries: [a.entries[0], Entry{...x, kind: 'symlink', mode: 0o120777,
		uid: 1, gid: 2, dev: 3, inode: 4, size: 5, mtime: 6, ctime: 7, sha256: '', target: 'elsewhere'}]}
	all := compare(encoded(a), encoded(c))!
	if all.changes.len != 11 || !all.verdict.starts_with('DIFFERENT;') { return error('entry field omitted') }
	missing := compare(encoded(a), encoded(Manifest{...a, entries: [a.entries[0]]}))!
	extra := compare(encoded(Manifest{...a, entries: [a.entries[0]]}), encoded(a))!
	if missing.missing != ['file'] || extra.extra != ['file'] { return error('entry membership omitted') }
	header := compare(encoded(a), encoded(Manifest{...a, root: '/other', scope: 'other'}))!
	if header.changes.len != 2 || !header.verdict.starts_with('DIFFERENT;') { return error('header changes omitted') }
	order := Manifest{...a, entries: [a.entries[0], a.entries[1], Entry{...x, path: 'other'}]}
	reordered := Manifest{...order, entries: [order.entries[0], order.entries[2], order.entries[1]]}
	if compare(encoded(order), encoded(reordered))!.changes[0].field != 'entry_order' { return error('entry order omitted') }
	for text in [encoded(a) + '\n', encoded(a).replace('"uid":0,', ''),
		encoded(a).replace('"uid":0,', '"uid":0,"uid":0,'),
		encoded(Manifest{...a, entries: [a.entries[0], x, x]})] {
		decoded(text) or { continue }
		return error('noncanonical or duplicate inventory accepted')
	}
	println('STATE INVENTORY DIFF PASS 11 controls; all fields and original refusal preserved')
}

fn run() ! {
	if os.args.len == 2 && os.args[1] == 'selfcheck' { selfcheck()!; return }
	if os.args.len != 4 { return error('use ORIGINAL.json CURRENT.json NEW-DIFF.json | selfcheck') }
	for path in os.args[1..3] {
		if path != os.real_path(path) || os.lstat(path)!.mode & 0o170000 != 0o100000 {
			return error('canonical regular inventory required')
		}
	}
	output := os.args[3]
	if !output.starts_with('/') || os.exists(output) || os.is_link(output)
		|| os.dir(output) != os.real_path(os.dir(output)) { return error('fresh canonical output required') }
	difference := compare(os.read_file(os.args[1])!, os.read_file(os.args[2])!)!
	os.write_file(output, json2.encode(difference) + '\n')!
	println(difference.verdict + '; entries=' + difference.original_entries.str()
		+ '/' + difference.current_entries.str() + '; changes=' + difference.changes.len.str()
		+ '; missing=' + difference.missing.len.str() + '; extra=' + difference.extra.len.str())
}

fn main() { run() or { eprintln(err); exit(1) } }
