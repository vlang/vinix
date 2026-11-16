// SPDX-License-Identifier: GPL-2.0-or-later
// Production-active policy framing and original-host admission controls.
module main

import os
import json2
import tests.packages.winereadclosure

fn run() ! {
	if os.args.len != 5 { return error('usage: CHECK REPLAY ORIGINAL_BUILDER FORMAT5_BUILD FRESH_OUTPUT') }
	replay := os.real_path(os.args[1]); checker := os.real_path(os.args[2]); build := os.real_path(os.args[3]); out := os.abs_path(os.args[4])
	if os.exists(out) || os.is_link(out) { return error('fresh read-closed controls required') }
	os.mkdir_all(out)!
	mut rejected := []string{}
	for path in ['', '/', 'relative', '/a//b', '/a/./b', '/a/../b', '/a/', '/a"b', '/a\\b', '/a\nb',
		'/a*b', '/a(b)', '/a b', '/café', '/a\x00b', '/a;b'] {
		winereadclosure.policy([path]) or { rejected << path; continue }
		return error('unsafe read capability accepted')
	}
	for paths in [([]string{}), ['/a', '/a'], []string{len: 8193, init: '/a'}] {
		winereadclosure.policy(paths) or { rejected << 'list-' + paths.len.str(); continue }
		return error('invalid read capability list accepted')
	}
	a := winereadclosure.policy(['/capture/b', '/capture/a'])!
	b := winereadclosure.policy(['/capture/a', '/capture/b'])!
	if a != b || !a.starts_with('(version 1)\n(allow default)\n(deny file-read-data)\n')
		|| a.count('(literal "/capture/a")') != 1 || a.count('(literal "/capture/b")') != 1
		|| a.count('(subpath ') != 2 || a.count('(vnode-type DIRECTORY)') != 1 || a.contains('(subpath "/capture')
		|| winereadclosure.system('/usr/library/other') || winereadclosure.system('/System/Library-other/file') {
		return error('read capability literal scope differs')
	}
	os.write_file(out + '/policy-controls.json', json2.encode(rejected) + '\n')!
	for name in ['incomplete', 'old-format'] { os.mkdir_all(out + '/' + name)! }
	proof := os.read_file(build + '/host-build.json')!
	os.write_file(out + '/incomplete/host-build.json', proof)!
	mut old := json2.decode[map[string]json2.Any](proof)!
	old['format'] = json2.Any(4)
	os.write_file(out + '/old-format/host-build.json', json2.encode(old))!
	mut passed := []string{}
	for name in ['wrong-checker', 'incomplete', 'old-format'] {
		target := out + '/' + name + '-result'
		command := [replay, if name == 'wrong-checker' { '/usr/bin/true' } else { checker },
			if name == 'wrong-checker' { build } else { out + '/' + name }, target]
		os.write_file(out + '/' + name + '.argv.json', json2.encode(command) + '\n')!
		mut process := os.new_process(command[0])
		defer { process.close() }
		process.set_args(command[1..]); process.set_redirect_stdio_merged(); process.run()
		C.close(process.stdio_fd[0]); process.stdio_fd[0] = -1
		text := process.stdout_slurp(); process.wait()
		os.write_file(out + '/' + name + '.log', text)!
		os.write_file(out + '/' + name + '.exit.json', json2.encode({'exit': process.code}) + '\n')!
		expected := if name == 'incomplete' { 'original host admission refused' } else { 'original format-5 host checker required' }
		if process.code != 1 || !text.contains(expected) || os.exists(target + '/receipt.json') || os.is_link(target + '/receipt.json') {
			return error('read-closed admission refusal differs: ' + name)
		}
		passed << name
	}
	os.write_file(out + '/admission-controls.json', json2.encode(passed) + '\n')!
	println('WINE READ-CLOSED CONTROLS PASS 19 policy refusals, deterministic literal scope and three admission refusals')
}

fn main() { run() or { eprintln(err); exit(1) } }
