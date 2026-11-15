// SPDX-License-Identifier: GPL-2.0-or-later
// Original admission failures must never produce a SDK-denied replay receipt.
module main

import os
import json2

fn run() ! {
	if os.args.len != 5 { return error('usage: CHECK REPLAY ORIGINAL_BUILDER HOST_BUILD FRESH_OUTPUT') }
	replay := os.real_path(os.args[1]); checker := os.real_path(os.args[2]); build := os.real_path(os.args[3]); out := os.abs_path(os.args[4])
	if os.exists(out) || os.is_link(out) { return error('fresh SDK-denied controls required') }
	os.mkdir_all(out + '/incomplete')!
	os.mkdir_all(out + '/old-format')!
	proof := os.read_file(build + '/host-build.json')!
	os.write_file(out + '/incomplete/host-build.json', proof)!
	mut old := json2.decode[map[string]json2.Any](proof)!
	old['format'] = json2.Any(3)
	os.write_file(out + '/old-format/host-build.json', json2.encode(old))!
	mut passed := []string{}
	for name in ['wrong-checker', 'incomplete', 'old-format'] {
		target := out + '/' + name + '-result'
		command := [replay, if name == 'wrong-checker' { '/usr/bin/true' } else { checker },
			if name == 'wrong-checker' { build } else { out + '/' + name }, target]
		os.write_file(out + '/' + name + '.argv.json', json2.encode(command) + '\n')!
		mut child := os.new_process(command[0])
		defer { child.close() }
		child.set_args(command[1..]); child.set_redirect_stdio_merged(); child.run()
		C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
		text := child.stdout_slurp(); child.wait()
		os.write_file(out + '/' + name + '.log', text)!
		os.write_file(out + '/' + name + '.exit.json', json2.encode({'exit': child.code}) + '\n')!
		expected := if name == 'incomplete' { 'original host admission refused' } else { 'original format-4 host checker required' }
		if child.code != 1 || !text.contains(expected) || os.exists(target + '/receipt.json') || os.is_link(target + '/receipt.json') {
			return error('SDK-denied admission refusal differs: ' + name)
		}
		passed << name
	}
	os.write_file(out + '/result.json', json2.encode(passed) + '\n')!
	println('WINE SDK-DENIED ADMISSION CONTROLS PASS three exact refusals without receipts')
}

fn main() { run() or { eprintln(err); exit(1) } }
