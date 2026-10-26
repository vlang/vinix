// SPDX-License-Identifier: GPL-2.0-or-later
// Production-safe controls for guest-rooted compiler input capture.
module main

import crypto.sha256
import json2
import os
import tests.packages.audioinputs

#include <sys/stat.h>
fn C.mkfifo(&char, u32) int

struct Report {
	format int = 1
	result string = 'PASS'
	checker string
	helper string
	controls []string
}

fn file(root string, name string, contents string) ! {
	os.mkdir_all(os.dir(root + '/' + name))!
	os.write_file(root + '/' + name, contents)!
}

fn link(root string, name string, target string) ! {
	os.mkdir_all(os.dir(root + '/' + name))!
	os.symlink(target, root + '/' + name)!
}

fn expect(root string, files map[string]string, links map[string]string) ! {
	snapshot := audioinputs.snapshot(root)!
	mut expected := map[string]string{}
	for name, target in files { expected[name] = root + '/' + target }
	if snapshot.root != root || snapshot.files != expected || snapshot.links != links {
		return error('captured sysroot files or literal links differ: ' + root)
	}
}

fn refuse(root string, reason string) ! {
	audioinputs.snapshot(root) or {
		if reason != '' && !err.msg().contains(reason) { return error('unexpected sysroot refusal: ' + err.msg()) }
		return
	}
	return error('accepted invalid sysroot: ' + root)
}

fn run(out string) ! {
	$if prod {} $else { return error('compile audio input checker with -prod') }
	if os.exists(out) || os.is_link(out) { return error('requires new control output') }
	os.mkdir_all(out)!
	mut controls := []string{}
	mut root := out + '/empty'
	os.mkdir_all(root)!
	expect(root, {}, {})!
	controls << 'empty-root'
	root = out + '/regular'
	file(root, 'include/header.h', 'regular header\n')!
	expect(root, {'include/header.h': 'include/header.h'}, {})!
	controls << 'nested-regular-input'
	for absolute in [false, true] {
		root = out + if absolute { '/absolute' } else { '/relative' }
		file(root, 'lib/libc.so', 'guest libc\n')!
		target := if absolute { '/lib/libc.so' } else { '../lib/libc.so' }
		link(root, 'lib64/loader', target)!
		expect(root, {'lib/libc.so': 'lib/libc.so', 'lib64/loader': 'lib/libc.so'}, {'lib64/loader': target})!
		controls << if absolute { 'absolute-link-rooted-in-guest' } else { 'relative-parent-link-rooted-in-guest' }
	}
	root = out + '/chain'
	file(root, 'lib/libc.so', 'guest libc\n')!
	link(root, 'first', 'second')!
	link(root, 'second', '/lib/libc.so')!
	expect(root, {'lib/libc.so': 'lib/libc.so', 'first': 'lib/libc.so', 'second': 'lib/libc.so'},
		{'first': 'second', 'second': '/lib/libc.so'})!
	controls << 'mixed-absolute-relative-link-chain'
	root = out + '/component-parent'
	file(root, 'leaf', 'wrong lexical target\n')!
	file(root, 'real/leaf', 'correct resolved target\n')!
	os.mkdir_all(root + '/real/sub')!
	link(root, 'alias', '/real/sub')!
	link(root, 'entry', 'alias/../leaf')!
	expect(root, {'leaf': 'leaf', 'real/leaf': 'real/leaf', 'entry': 'real/leaf'},
		{'alias': '/real/sub', 'entry': 'alias/../leaf'})!
	controls << 'directory-link-resolved-before-parent-component'
	root = out + '/directory-alias'
	file(root, 'real/header.h', 'aliased header\n')!
	link(root, 'include', '/real')!
	expect(root, {'real/header.h': 'real/header.h', 'include/header.h': 'real/header.h'}, {'include': '/real'})!
	controls << 'directory-alias-materializes-logical-files'
	root = out + '/literal-mutation'
	file(root, 'lib/libc.so', 'unchanged bytes\n')!
	link(root, 'loader', '/lib/libc.so')!
	before := audioinputs.snapshot(root)!
	os.rm(root + '/loader')!
	link(root, 'loader', 'lib/libc.so')!
	after := audioinputs.snapshot(root)!
	if before.files != after.files || before.links == after.links { return error('literal mutation was not independently observable') }
	controls << 'literal-link-mutation-with-identical-files-detected'
	for name, target in {'escape': '../outside', 'absolute-escape': '/../outside', 'missing': '/lib/missing'} {
		root = out + '/' + name
		link(root, 'bad', target)!
		refuse(root, if name.contains('escape') { 'escapes its root' } else { '' })!
		controls << name + '-refused'
	}
	root = out + '/link-cycle'
	link(root, 'a', 'b')!
	link(root, 'b', 'a')!
	refuse(root, 'cyclic')!
	controls << 'file-link-cycle-refused'
	root = out + '/directory-cycle'
	file(root, 'dir/file', 'cycle fixture\n')!
	link(root, 'dir/up', '/')!
	refuse(root, 'cyclic sysroot directory')!
	controls << 'directory-cycle-refused'
	root = out + '/nondirectory-component'
	file(root, 'regular', 'not a directory\n')!
	link(root, 'bad', 'regular/../regular')!
	refuse(root, 'nonregular sysroot input')!
	controls << 'regular-file-before-parent-component-refused'
	root = out + '/special'
	os.mkdir_all(root)!
	path := root + '/fifo'
	if C.mkfifo(path.str, 0o600) != 0 { return error('cannot create FIFO control') }
	refuse(root, 'nonregular sysroot input')!
	controls << 'special-file-refused-without-opening'
	refuse(out + '/does-not-exist', '')!
	controls << 'missing-root-refused'
	os.write_file(out + '/result.json', json2.encode(Report{
		checker: sha256.sum(os.read_bytes(@FILE)!).hex()
		helper: sha256.sum($embed_file('audioinputs/tree.v').to_string().bytes()).hex()
		controls: controls
	}) + '\n')!
	println('AUDIO INPUT CAPTURE PASS controls=' + controls.len.str())
}

fn main() {
	if os.args.len != 2 || !os.args[1].starts_with('--out=') { eprintln('use --out=NEW_DIRECTORY'); exit(1) }
	run(os.abs_path(os.args[1].all_after('='))) or { eprintln(err); exit(1) }
}
