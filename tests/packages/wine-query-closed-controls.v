// SPDX-License-Identifier: GPL-2.0-or-later
// Production-active policy framing and original-host admission controls.
module main

import os
import json2
import tests.packages.winedirclosure
import tests.packages.winemetaclosure
import tests.packages.winequeryclosure

fn projection(kind int, files []string, aliases []string) !string {
	return match kind {
		0 { winequeryclosure.policy(files, aliases)! }
		1 { winequeryclosure.existence_policy(files, aliases)! }
		else { winequeryclosure.xattr_policy(files, aliases)! }
	}
}

fn refuse(files []string, aliases []string) ! {
	mut count := 0
	for kind in 0 .. 3 {
		projection(kind, files, aliases) or { count++; continue }
		return error('query projection accepted invalid literals')
	}
	if count != 3 { return error('query projection refusal count differs') }
}

fn write_scope(out string) ! {
	mut write_refusals := 0
	for paths in [([]string{}), ['/a"b'], ['/a', '/a'], ['relative'], []string{len: 17, init: '/a'}] {
		winequeryclosure.writes(paths) or { write_refusals++; continue }
		return error('invalid execution query accepted')
	}
	writes := winequeryclosure.writes(['/run/b', '/run/a'])!
	if write_refusals != 5 || writes != winequeryclosure.writes(['/run/a', '/run/b'])!
		|| !writes.starts_with('(allow file-test-existence\n') || writes.count('(literal ') != 2
		|| writes.contains('file-read') || writes.contains('subpath') {
		return error('execution query scope differs')
	}
	os.write_file(out + '/execution-policy.sb', writes)!
	mut temporary_refusals := 0
	for path in ['relative', '/a/../b', '/a"b', '/', '/' + 'a'.repeat(4096)] {
		winequeryclosure.temporary_queries(path) or { temporary_refusals++; continue }
		return error('invalid temporary query accepted')
	}
	temporary := winequeryclosure.temporary_queries('/run/a.b+c')!
	if temporary_refusals != 5 || temporary.count('(regex ') != 1
		|| !temporary.contains('^/run/a[.]b[+]c[.]tmp' + '[0-9a-f]'.repeat(7) + '$')
		|| temporary.contains('file-read') || temporary.contains('subpath') {
		return error('temporary query scope differs')
	}
	os.write_file(out + '/temporary-policy.sb', temporary)!
}

fn run() ! {
	if os.args.len != 5 { return error('usage: CHECK REPLAY ORIGINAL_BUILDER FORMAT8_BUILD FRESH_OUTPUT') }
	replay := os.real_path(os.args[1]); checker := os.real_path(os.args[2]); build := os.real_path(os.args[3]); out := os.abs_path(os.args[4])
	if os.exists(out) || os.is_link(out) { return error('fresh query-closed controls required') }
	os.mkdir_all(out)!
	write_scope(out)!
	mut rejected := []string{}
	for path in ['', '/', 'relative', '/a//b', '/a/./b', '/a/../b', '/a/', '/a"b', '/a\\b', '/a\nb',
		'/a*b', '/a(b)', '/a b', '/café', '/a\x00b', '/a;b', '/' + 'a'.repeat(4096)] {
		refuse([path], [])!; rejected << path
	}
	for paths in [([]string{}), ['/a', '/a'], []string{len: 8193, init: '/a'}] {
		refuse(paths, [])!; rejected << 'list-' + paths.len.str()
	}
	mut deep := []string{}
	for index in 0 .. 160 { deep << '/root' + index.str() + '/a'.repeat(256) + '/file' }
	mut bounded := false
	winemetaclosure.paths(deep, []) or { bounded = err.msg() == 'directory capability count outside bound'; []string{} }
	if !bounded { return error('directory ancestor expansion exceeded bound') }
	refuse(deep, [])!
	rejected << 'ancestor-bound'
	for aliases in [['relative'], ['/a"b'], ['/capture/a'], ['/tools/link', '/tools/link'], []string{len: 129, init: '/alias'}] {
		refuse(['/capture/a'], aliases)!; rejected << 'aliases-' + rejected.len.str()
	}
	c := winequeryclosure.policy(['/capture/a'], ['/tools/link'])!
	if rejected.len != 26 || c.all_before('(deny file-read-metadata)') != winedirclosure.policy(['/capture/a'])!
		|| winemetaclosure.paths(['/capture/a'], ['/tools/link'])! != ['/', '/capture', '/capture/a', '/tools', '/tools/link'] {
		return error('metadata alias scope or refusal count differs')
	}
	a := winequeryclosure.policy(['/capture/b', '/capture/a'], [])!
	b := winequeryclosure.policy(['/capture/a', '/capture/b'], [])!
	if a != b || !a.starts_with('(version 1)\n(allow default)\n(deny file-read-data)\n')
		|| a.count('(literal "/capture/a")') != 3 || a.count('(literal "/capture/b")') != 3
		|| a.count('(subpath ') != 6 || a.count('(vnode-type DIRECTORY)') != 1 || a.contains('(subpath "/capture')
		|| a.count('(deny file-test-existence file-read-xattr)') != 1
		|| a.count('(allow file-test-existence file-read-xattr\n') != 1
		|| a.count('(deny file-read-metadata)') != 1 || a.count('(allow file-read-metadata\n') != 1
		|| winemetaclosure.paths(['/a/b/c', '/a/d'], [])! != ['/', '/a', '/a/b', '/a/b/c', '/a/d']
		|| winemetaclosure.paths(['/a/b/c', '/a/d'], [])! != winemetaclosure.paths(['/a/d', '/a/b/c'], [])!
		|| a.contains('(allow file-read-data (vnode-type DIRECTORY))')
		|| winedirclosure.directories(['/a/b/c', '/a/d'])! != ['/', '/a', '/a/b']
		|| winedirclosure.directories(['/a/b/c', '/a/d'])! != winedirclosure.directories(['/a/d', '/a/b/c'])! {
		return error('read capability literal scope differs')
	}
	base := winemetaclosure.policy(['/capture/a'], [])!
	for kind in 0 .. 3 {
		policy := projection(kind, ['/capture/a'], [])!
		operation := match kind { 0 { 'file-test-existence file-read-xattr' } 1 { 'file-test-existence' } else { 'file-read-xattr' } }
		if policy.all_before('(deny ' + operation + ')') != base
			|| policy.count('(deny ' + operation + ')') != 1
			|| policy.count('(allow ' + operation + '\n') != 1 {
			return error('query projection changed base or operation framing')
		}
	}
	os.write_file(out + '/policy-controls.json', json2.encode(rejected) + '\n')!
	for name in ['incomplete', 'old-format'] { os.mkdir_all(out + '/' + name)! }
	proof := os.read_file(build + '/host-build.json')!
	os.write_file(out + '/incomplete/host-build.json', proof)!
	mut old := json2.decode[map[string]json2.Any](proof)!
	old['format'] = json2.Any(7)
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
		expected := if name == 'incomplete' { 'original host admission refused' } else { 'original format-8 host checker required' }
		if process.code != 1 || !text.contains(expected) || os.exists(target + '/receipt.json') || os.is_link(target + '/receipt.json') {
			return error('query-closed admission refusal differs: ' + name)
		}
		passed << name
	}
	os.write_file(out + '/admission-controls.json', json2.encode(passed) + '\n')!
	println('WINE QUERY-CLOSED CONTROLS PASS 88 policy refusals across query/execution projections, exact scope and three admission refusals')
}

fn main() { run() or { eprintln(err); exit(1) } }
