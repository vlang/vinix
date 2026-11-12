// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve admitted parsed sources, including files outside the compiler root.
// Original namespaces remain required by the native evidence auditor.
module main

import crypto.sha256
import json2
import os
import tests.packages.winesource

struct SourceCopy {
	original string
	stored string
	sha256 string
	mode u32
}

fn run() ! {
	$if prod {} $else { return error('compile source snapshot with -prod') }
	if os.args.len !in [3, 4] || (os.args.len == 4 && os.args[3] != '--guest-only') { return error('usage: wine-source-snapshot NATIVE_RUN FRESH_OUTPUT [--guest-only]') }
	programs := if os.args.len == 4 { ['guest'] } else { ['guest', 'package'] }
	for path, source in {
		@FILE: $embed_file('wine-source-snapshot.v').to_string()
		os.dir(@FILE) + '/winesource/closure.v': $embed_file('winesource/closure.v').to_string()
	} {
		if winesource.file_digest(path)! != sha256.hexhash(source) { return error('compiled source snapshot differs: ' + path) }
	}
	run := os.real_path(os.args[1])
	out := os.abs_path(os.args[2])
	if os.exists(out) || os.is_link(out) { return error('source snapshot output must be fresh') }
	index := run + '/inputs-verified.json'
	index_hash := winesource.file_digest(index)!
	inputs := json2.decode[map[string]string](os.read_file(index)!)!
	mut sources := map[string]string{}
	mut lists := map[string]string{}
	for program in programs {
		before := run + '/build-' + program + '/sources-before.txt'
		built := run + '/build-' + program + '/sources-built.txt'
		if os.read_file(before)! != os.read_file(built)! { return error('source discovery/build lists differ') }
		for list in [before, built]! {
			lists[list] = winesource.file_digest(list)!
			winesource.capture(list, mut sources)!
		}
	}
	mut copies := []SourceCopy{}
	for path, expected in sources {
		st := os.lstat(path)!
		if st.get_filetype() != .regular || inputs[path] != expected {
			return error('parsed source is not an admitted ordinary file: ' + path)
		}
		mode := u32(st.mode) & 0o7777
		copies << SourceCopy{original: path, stored: 'files/' + expected + '-' + mode.str(),
			sha256: expected, mode: mode}
	}
	os.mkdir_all(out + '/files')!
	for copy in copies {
		path := out + '/' + copy.stored
		if !os.exists(path) { os.cp(copy.original, path)!; os.chmod(path, int(copy.mode))! }
		if winesource.file_digest(path)! != copy.sha256
			|| winesource.file_digest(copy.original)! != copy.sha256
			|| u32(os.lstat(copy.original)!.mode) & 0o7777 != copy.mode
			|| u32(os.lstat(path)!.mode) & 0o7777 != copy.mode {
			return error('parsed source changed during snapshot: ' + copy.original)
		}
	}
	for path, expected in lists {
		if winesource.file_digest(path)! != expected { return error('source list changed during snapshot') }
	}
	if winesource.file_digest(index)! != index_hash { return error('native source inventory changed during snapshot') }
	os.write_file(out + '/sources.json', json2.encode(copies) + '\n')!
	os.write_file(out + '/lists.json', json2.encode(lists) + '\n')!
	os.cp(index, out + '/original-inputs.json')!
	println('WINE PARSED SOURCES PRESERVED ' + copies.len.str() + ': admitted bytes/modes only; original namespaces and complete dependency bundles remain required')
}

fn main() { run() or { eprintln(err); exit(1) } }
