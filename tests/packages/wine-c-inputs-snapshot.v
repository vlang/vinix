// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve admitted observed targets. Original namespaces remain required.
module main

import os
import json2
import crypto.sha256
import tests.packages.winecsource
import tests.packages.winesource

struct Copy {
	original string
	resolved string
	stored string
	sha256 string
	mode u32
}

fn run() ! {
	$if prod {} $else { return error('compile C input snapshot with -prod') }
	if os.args.len != 4 { return error('usage: SNAPSHOT BUILD_DIRECTORY LOG_DIRECTORY FRESH_OUTPUT') }
	for path, source in {
		@FILE: $embed_file('wine-c-inputs-snapshot.v').to_string()
		os.dir(@FILE) + '/winecsource/closure.v': $embed_file('winecsource/closure.v').to_string()
		os.dir(@FILE) + '/winesource/closure.v': $embed_file('winesource/closure.v').to_string()
	} {
		if winesource.file_digest(path)! != sha256.hexhash(source) { return error('compiled C input snapshot source differs') }
	}
	directory := os.real_path(os.args[1])
	logs := os.real_path(os.args[2])
	out := os.abs_path(os.args[3])
	if os.exists(out) || os.is_link(out) { return error('C input snapshot requires fresh output') }
	winecsource.admit(directory, logs)!
	mut records := map[string]string{}
	for path in [directory + '/c-inputs-before.json', directory + '/c-inputs-verified.json',
		logs + '/c-discover.log', logs + '/c-discover.log.argv.json', logs + '/cc.log', logs + '/cc.log.argv.json'] {
		records[path] = winesource.file_digest(path)!
	}
	proof := json2.decode[winecsource.Proof](os.read_file(directory + '/c-inputs-before.json')!)!
	mut copies := []Copy{}
	os.mkdir_all(out + '/files')!
	for file in [...proof.sources, ...proof.includes] {
		st := os.lstat(file.resolved)!
		if st.get_filetype() != .regular { return error('C input snapshot target is not ordinary') }
		mode := u32(st.mode) & 0o7777
		stored := 'files/' + file.sha256 + '-' + mode.str()
		path := out + '/' + stored
		if !os.exists(path) { os.cp(file.resolved, path)!; os.chmod(path, int(mode))! }
		if winesource.file_digest(path)! != file.sha256 || winesource.file_digest(file.resolved)! != file.sha256
			|| u32(os.lstat(path)!.mode) & 0o7777 != mode || u32(os.lstat(file.resolved)!.mode) & 0o7777 != mode {
			return error('C input target changed during snapshot')
		}
		copies << Copy{file.path, file.resolved, stored, file.sha256, mode}
	}
	winecsource.admit(directory, logs)!
	for path, expected in records {
		if winesource.file_digest(path)! != expected { return error('C input evidence changed during snapshot') }
	}
	os.write_file(out + '/sources.json', json2.encode(copies) + '\n')!
	os.write_file(out + '/records.json', json2.encode(records) + '\n')!
	os.cp(directory + '/c-inputs-before.json', out + '/original-inputs.json')!
	println('WINE OBSERVED C INPUTS PRESERVED: resolved bytes/modes; original namespaces and complete toolchain bundles remain required')
}

fn main() { run() or { eprintln(err); exit(1) } }
