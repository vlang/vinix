// SPDX-License-Identifier: GPL-2.0-or-later
module compactdiagnosis

import crypto.sha256
import json2
import os

fn encoded(m Manifest) string { return json2.encode(m) + '\n' }

fn refusal(root string, name string, a string, b string, recorded bool) ! {
	old, new, report := root + '/' + name + '-old.json', root + '/' + name + '-new.json', root + '/' + name + '-report.json'
	os.write_file(old, a)!
	os.write_file(new, b)!
	mut rejected := false
	compare(old, new, report) or { rejected = true }
	need(rejected && os.exists(report) == recorded, 'missing explicit refusal/report: ' + name)!
	if recorded {
		r := json2.decode[Report](os.read_file(report)!, strict: true)!
		need(!r.summary.accepted_metadata_only && r.summary.refused_changes > 0
			&& r.changes.len > 0, 'refusal report lost full differences: ' + name)!
	}
	need(sha256.hexhash(os.read_file(old)!) == sha256.hexhash(a)
		&& sha256.hexhash(os.read_file(new)!) == sha256.hexhash(b), 'control inputs changed')!
}

// Explicit checks execute identically with and without -prod; no assert gates.
pub fn controls(root string) ! {
	need(root.starts_with('/') && os.dir(root) == os.real_path(os.dir(root))
		&& !os.exists(root) && !os.is_link(root), 'requires a fresh canonical external control directory')!
	os.mkdir(root, mode: 0o700)!
	a := Manifest{'frame-page-state-v1', '/compactdiagnosis-fixture', original_scope,
		[Entry{path: '.', kind: 'directory', mode: 0o40755},
		Entry{path: 'dir', kind: 'directory', mode: 0o40755},
		Entry{path: 'dir/file', kind: 'file', mode: 0o100644, size: 1, sha256: 'a'.repeat(64)},
		Entry{path: 'link', kind: 'symlink', mode: 0o120777, size: 4, target: 'file'}]}
	old, new := root + '/old.json', root + '/new.json'
	os.write_file(old, encoded(a))!
	os.write_file(new, encoded(a))!
	identical := compare(old, new, root + '/identical.json')!
	need(identical.accepted_metadata_only && identical.changed_entries == 0
		&& identical.old_manifest_sha256 == sha256.hexhash(encoded(a)), 'identical summary differs')!
	b := Manifest{...a, entries: a.entries.map(Entry{...it, dev: 3, inode: 4, mtime: -5, ctime: 6})}
	os.write_file(new, encoded(b))!
	metadata := compare(old, new, root + '/metadata.json')!
	need(metadata.accepted_metadata_only && metadata.changed_entries == 4
		&& metadata.metadata_changes == 16 && metadata.refused_changes == 0
		&& metadata.old_manifest_sha256 == metadata.old_manifest_sha256_after
		&& metadata.new_manifest_sha256 == metadata.new_manifest_sha256_after, 'metadata summary differs')!
	x := a.entries[2]
	variants := [Entry{...x, mode: x.mode + 1}, Entry{...x, uid: 1}, Entry{...x, gid: 1},
		Entry{...x, size: 2}, Entry{...x, sha256: 'b'.repeat(64)},
		Entry{...x, kind: 'symlink'}, Entry{...x, path: 'dir/renamed'}]
	for i, entry in variants {
		refusal(root, 'protected-' + i.str(), encoded(a),
			encoded(Manifest{...a, entries: [a.entries[0], a.entries[1], entry, a.entries[3]]}), true)!
	}
	refusal(root, 'link-target', encoded(a), encoded(Manifest{...a,
		entries: [a.entries[0], a.entries[1], x, Entry{...a.entries[3], target: 'else'}]}), true)!
	refusal(root, 'missing', encoded(a), encoded(Manifest{...a, entries: a.entries[..3]}), true)!
	refusal(root, 'extra', encoded(Manifest{...a, entries: a.entries[..3]}), encoded(a), true)!
	refusal(root, 'order', encoded(a), encoded(Manifest{...a,
		entries: [a.entries[0], a.entries[1], a.entries[3], x]}), true)!
	refusal(root, 'root', encoded(a), encoded(Manifest{...a, root: '/other'}), true)!
	for i, text in [encoded(a) + '\n', encoded(a) + '{}',
		encoded(a).replace('"uid":0,', ''), encoded(a).replace('"uid":0,', '"extra":0,"uid":0,'),
		encoded(a).replace('"uid":0,', '"uid":0,"uid":0,'),
		encoded(a).replace('"path":".","kind":"directory"', '"kind":"directory","path":"."'),
		encoded(Manifest{...a, entries: [a.entries[0], x, x]})] {
		refusal(root, 'schema-' + i.str(), encoded(a), text, false)!
	}
	refusal(root, 'report-limit', encoded(a), encoded(Manifest{...a,
		entries: [a.entries[0], a.entries[1], Entry{...x, sha256: 'b'.repeat(report_limit)}, a.entries[3]]}), false)!
	before := os.read_file(root + '/identical.json')!
	mut overwritten := true
	compare(old, new, root + '/identical.json') or { overwritten = false }
	need(!overwritten && os.read_file(root + '/identical.json')! == before, 'existing report accepted or changed')!
	os.write_file(root + '/results.json', json2.encode({'outcome': 'PASS', 'controls': '23',
		'scope': 'Pure complete-inventory comparison fixtures; no original audit, tree capture, import or native qualification.'}) + '\n')!
	println('PASS compact diagnosis23 explicit controls')
}
