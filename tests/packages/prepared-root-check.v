// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import tools.packages.pkgcore

#include <sys/wait.h>
#include <unistd.h>
fn C.fork() int
fn C.waitpid(int, &int, int) int
fn C._exit(int)
fn C.alarm(u32) u32
fn C.mkfifo(&char, u32) int

fn import_root(kind string, recipe string, root string, destination string) !string {
	if kind == 'root' { return json2.encode(pkgcore.pack_root(recipe, root, destination)!) }
	return pkgcore.pack_catalog(recipe, root, destination)!.catalog_sha256
}

fn check() ! {
	if os.args.len !in [2, 3] || (os.args.len == 3 && os.args[2] != '--before') {
		return error('usage: prepared-root-check NEW_WORK_DIRECTORY [--before]')
	}
	work := os.abs_path(os.args[1])
	before := os.args.len == 3
	if os.exists(work) || os.is_link(work) { return error('prepared root qualification directory must be new') }
	os.mkdir_all(work + '/roots/shared')!
	os.write_file(work + '/roots/shared/data', 'payload')!
	p := pkgcore.Package{ id: 'data', version: '1.0.0', architecture: 'all', name: 'Data', license: 'MIT', kind: 'data',
		files: [pkgcore.Payload{ path: 'data', bytes: 7, sha256: sha256.sum('payload'.bytes()).hex() }] }
	recipe := pkgcore.RootRecipe{ manifest: p, entries: [pkgcore.RootEntry{ source: 'data', path: 'data' }] }
	os.write_file(work + '/root.json', json2.encode(recipe))!
	os.write_file(work + '/catalog.json', json2.encode(pkgcore.CatalogRecipe{
		format: 1, architectures: ['aarch64', 'x86_64'], packages: [pkgcore.CatalogImport{ source: 'shared', recipe: recipe }]
	}))!
	os.write_file(work + '/file', 'preserved')!
	assert C.mkfifo((work + '/fifo').str, 0o600) == 0
	for kind in ['root', 'catalog'] {
		root := work + '/roots' + if kind == 'root' { '/shared' } else { '' }
		alias := work + '/source-alias-' + kind
		os.symlink(root, alias)!
		for mode in ['nul', 'alias-slashes', 'alias', 'empty', 'missing', 'file', 'fifo'] {
			base := work + '/' + kind + '-' + mode
			os.mkdir(base)!
			destination := base + '/output-parent/workspace'
			input := match mode {
				'nul' { root + '\x00ignored' }
				'alias-slashes' { alias + '///' }
				'alias' { alias }
				'empty' { '' }
				else { work + '/' + mode }
			}
			child := C.fork()
			assert child >= 0
			if child == 0 {
				C.alarm(3)
				import_root(kind, work + '/' + kind + '.json', input, destination) or { C._exit(1) }
				C._exit(0)
			}
			mut status := 0
			assert C.waitpid(child, &status, 0) == child
			accepted_before := mode in ['nul', 'alias-slashes']
			assert status == if before && accepted_before { 0 } else { 256 }, kind + '/' + mode
			assert os.exists(base + '/output-parent') == (before && (kind == 'catalog' || accepted_before)), kind + '/' + mode
			assert os.read_file(work + '/roots/shared/data')! == 'payload'
			assert os.read_file(work + '/file')! == 'preserved'
			println('${kind}/${mode}: wait status ${status}; ${if before { 'previous root admission/output behavior reproduced' } else { 'refused before creating output parents' }}')
		}
		one := import_root(kind, work + '/' + kind + '.json', root, work + '/' + kind + '-ordinary')!
		two := import_root(kind, work + '/' + kind + '.json', root + '///', work + '/' + kind + '-slashes')!
		assert one == two
		println('${kind}: ordinary directory and redundant separators preserve canonical metadata')
	}
	println('Prepared root qualification passed')
}

fn main() { check() or { eprintln(err); exit(1) } }
