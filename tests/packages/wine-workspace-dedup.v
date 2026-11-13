// SPDX-License-Identifier: GPL-2.0-or-later
// Reclaim duplicate artifact storage without removing any evidence bytes.
module main

import json2
import os
import tests.packages.wineoverlay
import tests.packages.winesource

struct Replacement {
	path string
	source string
	sha256 string
	bytes u64
	mode u32
	uid u32
	gid u32
}

fn run() ! {
	if os.args.len != 3 { return error('usage: DEDUP UNFROZEN_WORKSPACE FRESH_EXTERNAL_REPORT') }
	root := os.real_path(os.args[1])
	report := os.abs_path(os.args[2])
	if !os.is_dir(root) || os.is_link(os.args[1]) || report.starts_with(root + '/')
		|| os.exists(report) || os.is_link(report) { return error('canonical workspace and fresh external report required') }
	mut output := os.create(report)!
	defer { output.close() }
	mut originals := map[string]string{}
	mut paths := os.walk_ext(root, '', hidden: true)
	paths.sort()
	mut count := 0
	for path in paths {
		if os.is_link(path) || !os.is_file(path) || os.real_path(path) != path { continue }
		st := os.lstat(path)!
		if st.size < 65536 { continue }
		hash := winesource.file_digest(path)!
		mode := u32(st.mode) & 0o7777
		key := hash + ':' + mode.str() + ':' + st.uid.str() + ':' + st.gid.str()
		if key !in originals { originals[key] = path; continue }
		source := originals[key]
		temporary := path + '.dedup-clone'
		wineoverlay.clone_fresh(source, temporary)!
		cloned := os.lstat(temporary)!
		if winesource.file_digest(temporary)! != hash || u32(cloned.mode) & 0o7777 != mode
			|| cloned.uid != st.uid || cloned.gid != st.gid
			|| winesource.file_digest(path)! != hash || u32(os.lstat(path)!.mode) & 0o7777 != mode {
			return error('artifact changed during clone; original retained: ' + path)
		}
		os.mv(temporary, path)!
		if winesource.file_digest(path)! != hash { return error('replacement digest differs') }
		output.writeln(json2.encode(Replacement{path: path, source: source, sha256: hash, bytes: u64(st.size), mode: mode, uid: st.uid, gid: st.gid}))!
		count++
	}
	println('WINE WORKSPACE DEDUP PASS verified independent clones=' + count.str())
}

fn main() { run() or { eprintln(err); exit(1) } }
