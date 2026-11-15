// SPDX-License-Identifier: GPL-2.0-or-later
// Selected ordinary host image bytes only; macOS shared-cache bytes excluded.
module main

import os
import json2
import crypto.sha256
import tests.packages.winehostimages
import tests.packages.winesource

struct Copy {
	original string
	stored string
	sha256 string
	mode u32
}

fn admit(directory string) ! {
	winehostimages.admit_build(directory, directory)!
	args := json2.decode[[]string](os.read_file(directory + '/v.log.argv.json')!)!
	if args.len == 0 { return error('host snapshot V compiler command missing') }
	winehostimages.admit_v(directory, directory, args[0], {args[0]: winesource.file_digest(args[0])!})!
}

fn run() ! {
	$if prod {} $else { return error('compile host image snapshot with -prod') }
	if os.args.len != 5 { return error('usage: SNAPSHOT BRIDGE_LOGS GUEST_LOGS PACKAGE_LOGS FRESH_OUTPUT') }
	for path, source in {
		@FILE: $embed_file('wine-host-images-snapshot.v').to_string()
		os.dir(@FILE) + '/winehostimages/images.v': $embed_file('winehostimages/images.v').to_string()
		os.dir(@FILE) + '/winesource/closure.v': $embed_file('winesource/closure.v').to_string()
	} {
		if winesource.file_digest(path)! != sha256.hexhash(source) { return error('compiled host image snapshot differs') }
	}
	out := os.abs_path(os.args[4])
	if os.exists(out) || os.is_link(out) { return error('host image snapshot requires fresh output') }
	mut inputs := map[string]string{}
	mut records := map[string]string{}
	for directory in os.args[1..4] {
		admit(directory)!
		for name in [...winehostimages.artifacts(), ...winehostimages.v_artifacts()] { records[directory + '/' + name] = winesource.file_digest(directory + '/' + name)! }
		mut selected := winehostimages.inputs(directory)!
		for path, hash in winehostimages.v_inputs(directory)! {
			if path in selected && selected[path] != hash { return error('host snapshot V/C image contexts differ') }
			selected[path] = hash
		}
		for path, hash in selected {
			if path in inputs && inputs[path] != hash { return error('host snapshot image contexts differ') }
			inputs[path] = hash
		}
	}
	os.mkdir_all(out + '/files')!
	mut copies := []Copy{}
	for path, expected in inputs {
		st := os.lstat(path)!
		if st.get_filetype() != .regular || os.real_path(path) != path { return error('host snapshot target differs') }
		mode := u32(st.mode) & 0o7777
		stored := 'files/' + expected + '-' + mode.str()
		if !os.exists(out + '/' + stored) { os.cp(path, out + '/' + stored)!; os.chmod(out + '/' + stored, int(mode))! }
		if winesource.file_digest(path)! != expected || winesource.file_digest(out + '/' + stored)! != expected
			|| u32(os.lstat(path)!.mode) & 0o7777 != mode || u32(os.lstat(out + '/' + stored)!.mode) & 0o7777 != mode {
			return error('host image changed during snapshot')
		}
		copies << Copy{path, stored, expected, mode}
	}
	for directory in os.args[1..4] { admit(directory)! }
	for path, expected in records { if winesource.file_digest(path)! != expected { return error('host image evidence changed during snapshot') } }
	os.write_file(out + '/images.json', json2.encode(copies) + '\n')!
	os.write_file(out + '/records.json', json2.encode(records) + '\n')!
	println('WINE HOST IMAGE BYTES PRESERVED: observed non-system bytes/modes; OS shared-cache images remain unadmitted')
}

fn main() { run() or { eprintln(err); exit(1) } }
