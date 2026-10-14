// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.hex
import json2
import os
import tools.packages.pkgcore
import tools.packages.signing

fn memory() {
	text := os.read_file('/proc/meminfo') or { return }
	defer { unsafe { text.free() } }
	for line in text.split_into_lines() { if line.starts_with('MemFree:') || line.starts_with('Slab:') { println(line) } }
}

fn check() ! {
	assert os.args.len == 2
	work := os.abs_path(os.args[1])
	if os.exists(work) || os.is_link(work) { return error('signing repetition requires a new directory') }
	os.mkdir(work, mode: 0o700)!
	defer { os.rmdir_all(work) or {} }
	os.mkdir(work + '/source')!
	os.write_file(work + '/source/data', 'payload')!
	os.write_file(work + '/seed', '01'.repeat(32) + '\n')!; os.chmod(work + '/seed', 0o600)!
	os.write_file(work + '/manifest.json', json2.encode(pkgcore.Package{ id: 'data', name: 'Data',
		version: '1.0.0', architecture: 'all', kind: 'data', license: 'MIT' }))!
	pkgcore.pack(work + '/manifest.json', work + '/source', work + '/repository')!
	seed := []u8{len: 32, init: 1}
	secret := signing.new_key_from_seed(seed)
	key := secret.public_key()
	defer { unsafe { seed.free(); secret.free(); key.free() } }
	mut canonical := ''
	mut canonical_sig := ''
	for iteration in 0 .. 16 {
		pkgcore.publish(work + '/repository', 'fixture', work + '/seed', 1, 2000000000)!
		pkgcore.publish_release(work + '/repository', 'fixture', work + '/seed', 1, 2000000000, work + '/release-' + iteration.str())!
		index := os.read_file(work + '/repository/index.json')!
		sig := os.read_file(work + '/repository/index.sig')!
		if iteration == 0 { canonical = index.clone(); canonical_sig = sig.clone() }
		assert index == canonical && sig == canonical_sig
		assert os.read_file(work + '/release-' + iteration.str() + '/index.json')! == canonical
		assert os.read_file(work + '/release-' + iteration.str() + '/index.sig')! == canonical_sig
		signature := hex.decode(sig.trim_space())!
		assert signing.verify(key, index.bytes(), signature)!
		unsafe { signature.free(); index.free(); sig.free() }
		println('SIGNING REPEAT ' + (iteration + 1).str() + '/16 identical publication and verification PASS')
		memory()
	}
	println('PACKAGE SIGNING REPEAT 32 publications one-process canonical-bytes PASS')
}

fn main() { check() or { eprintln(err); exit(1) } }
