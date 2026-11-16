// SPDX-License-Identifier: GPL-2.0-or-later
// Production-active policy framing and original-host admission controls.
module main

import os
import json2
import tests.packages.winedirclosure
import tests.packages.winemetaclosure

fn run() ! {
	if os.args.len != 5 { return error('usage: CHECK REPLAY ORIGINAL_BUILDER FORMAT7_BUILD FRESH_OUTPUT') }
	replay := os.real_path(os.args[1]); checker := os.real_path(os.args[2]); build := os.real_path(os.args[3]); out := os.abs_path(os.args[4])
	if os.exists(out) || os.is_link(out) { return error('fresh metadata-closed controls required') }
	os.mkdir_all(out)!
	mut rejected := []string{}
	for path in ['', '/', 'relative', '/a//b', '/a/./b', '/a/../b', '/a/', '/a"b', '/a\\b', '/a\nb',
		'/a*b', '/a(b)', '/a b', '/café', '/a\x00b', '/a;b', '/' + 'a'.repeat(4096)] {
		winemetaclosure.policy([path], []) or { rejected << path; continue }
		return error('unsafe read capability accepted')
	}
	for paths in [([]string{}), ['/a', '/a'], []string{len: 8193, init: '/a'}] {
		winemetaclosure.policy(paths, []) or { rejected << 'list-' + paths.len.str(); continue }
		return error('invalid read capability list accepted')
	}
	mut deep := []string{}
	for index in 0 .. 160 { deep << '/root' + index.str() + '/a'.repeat(256) + '/file' }
	mut bounded := false
	winemetaclosure.paths(deep, []) or { bounded = err.msg() == 'directory capability count outside bound'; []string{} }
	if !bounded { return error('directory ancestor expansion exceeded bound') }
	rejected << 'ancestor-bound'
	for aliases in [['relative'], ['/a"b'], ['/capture/a'], ['/tools/link', '/tools/link'], []string{len: 129, init: '/alias'}] {
		winemetaclosure.policy(['/capture/a'], aliases) or { rejected << 'aliases-' + rejected.len.str(); continue }
		return error('invalid metadata alias list accepted')
	}
	c := winemetaclosure.policy(['/capture/a'], ['/tools/link'])!
	if rejected.len != 26 || c.all_before('(deny file-read-metadata)') != winedirclosure.policy(['/capture/a'])!
		|| winemetaclosure.paths(['/capture/a'], ['/tools/link'])! != ['/', '/capture', '/capture/a', '/tools', '/tools/link'] {
		return error('metadata alias scope or refusal count differs')
	}
	a := winemetaclosure.policy(['/capture/b', '/capture/a'], [])!
	b := winemetaclosure.policy(['/capture/a', '/capture/b'], [])!
	if a != b || !a.starts_with('(version 1)\n(allow default)\n(deny file-read-data)\n')
		|| a.count('(literal "/capture/a")') != 2 || a.count('(literal "/capture/b")') != 2
		|| a.count('(subpath ') != 4 || a.count('(vnode-type DIRECTORY)') != 1 || a.contains('(subpath "/capture')
		|| a.count('(deny file-read-metadata)') != 1 || a.count('(allow file-read-metadata\n') != 1
		|| winemetaclosure.paths(['/a/b/c', '/a/d'], [])! != ['/', '/a', '/a/b', '/a/b/c', '/a/d']
		|| winemetaclosure.paths(['/a/b/c', '/a/d'], [])! != winemetaclosure.paths(['/a/d', '/a/b/c'], [])!
		|| a.contains('(allow file-read-data (vnode-type DIRECTORY))')
		|| winedirclosure.directories(['/a/b/c', '/a/d'])! != ['/', '/a', '/a/b']
		|| winedirclosure.directories(['/a/b/c', '/a/d'])! != winedirclosure.directories(['/a/d', '/a/b/c'])! {
		return error('read capability literal scope differs')
	}
	os.write_file(out + '/policy-controls.json', json2.encode(rejected) + '\n')!
	for name in ['incomplete', 'old-format'] { os.mkdir_all(out + '/' + name)! }
	proof := os.read_file(build + '/host-build.json')!
	os.write_file(out + '/incomplete/host-build.json', proof)!
	mut old := json2.decode[map[string]json2.Any](proof)!
	old['format'] = json2.Any(6)
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
		expected := if name == 'incomplete' { 'original host admission refused' } else { 'original format-7 host checker required' }
		if process.code != 1 || !text.contains(expected) || os.exists(target + '/receipt.json') || os.is_link(target + '/receipt.json') {
			return error('metadata-closed admission refusal differs: ' + name)
		}
		passed << name
	}
	os.write_file(out + '/admission-controls.json', json2.encode(passed) + '\n')!
	println('WINE METADATA-CLOSED CONTROLS PASS 26 policy refusals, deterministic file/ancestor metadata scope and three admission refusals')
}

fn main() { run() or { eprintln(err); exit(1) } }
