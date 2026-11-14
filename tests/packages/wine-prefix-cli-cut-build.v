// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os

fn run() ! {
	if os.args.len != 3 { return error('usage: PREPARE ORIGINAL_MAIN.v FRESH_DIRECTORY') }
	source := os.abs_path(os.args[1]); work := os.abs_path(os.args[2])
	if os.exists(work) || os.is_link(work) { return error('fresh CLI cut build directory required') }
	entry := os.read_file(source)!
	hook_path := os.dir(@FILE) + '/wineclicut/hook.v'
	hook := os.read_file(hook_path)!
	os.mkdir_all(work)!
	os.write_file(work + '/main.v', entry)!
	os.write_file(work + '/hook.v', hook)!
	if os.read_file(source)! != entry || os.read_file(work + '/main.v')! != entry
		|| os.read_file(work + '/hook.v')! != hook { return error('CLI cut source changed during copy') }
	os.write_file(work + '/source-identity.json', json2.encode({'entrypoint': source,
		'entrypoint_sha256': sha256.hexhash(entry), 'hook': hook_path,
		'hook_sha256': sha256.hexhash(hook), 'generator_sha256': sha256.hexhash(os.read_file(@FILE)!)}))!
	println('WINE CLI CUT PREPARE PASS byte-identical entrypoint and test hook')
}

fn main() { run() or { eprintln(err); exit(1) } }
