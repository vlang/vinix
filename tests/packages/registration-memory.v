// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import desktop.packagecore
import tools.packages.pkgprotocol

#include "@VMODROOT/../../desktop/tools/tests/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

struct Installation { package pkgprotocol.RegisteredPackage }
struct Snapshot {
	format int = 1
	generation u64 = 1
	architecture string = 'aarch64'
	packages []Installation
}

fn consume(text string, expected bool) {
	mut accepted := true
	mut snapshot := pkgprotocol.decode_registration(text) or {
		accepted = false
		message := err.msg(); unsafe { message.free(); err.free() }
		pkgprotocol.RegistrationSnapshot{}
	}
	snapshot.close()
	assert accepted == expected
}

fn main() {
	mut rows := []Installation{cap: 32}
	for index in 0 .. 32 { rows << Installation{package: pkgprotocol.RegisteredPackage{
		id: 'app-' + index.str(), name: 'Application é🚀', description: 'Description é🚀 '.repeat(16), architecture: 'aarch64',
		kind: 'native', permissions: ['files', 'display'], associations: ['text/plain', 'application/octet-stream'] }} }
	text := json2.encode(Snapshot{packages: rows})
	additive := text[..text.len - 1] + ',"future":{"text":"' + 'é🚀'.repeat(1024) + '","array":[null,true,false,-1.25e2,1e9999]}}'
	invalid := [text.replace('"id":"app-31"', '"id":"app-31","i\\u0064":"duplicate"'),
		text.replace('"id":"app-31"', '"id":"app-0"'),
		text.replace('"associations":["text/plain","application/octet-stream"]', '"associations":null'),
		text[..text.len - 2], additive.replace('"array":', '"bad":"\\ud800","array":'),
		text + ' false', '{"format":1,"generation":1,"architecture":"aarch64","packages":null}']
	for warmup in 0 .. 2 {
		if warmup == 1 { C.vinix_heap_begin() }
		for _ in 0 .. 1000 {
			consume(text, true); consume(additive, true)
			for bad in invalid { consume(bad, false) }
		}
	}
	kept := C.vinix_heap_end()
	assert kept == 0, 'registration reader retained ${kept} bytes'
	println('Package registration reader: 1000 wide/additive/partial-invalid decode/close cycles retain zero tracked bytes')
	root := os.real_path(os.temp_dir()) + '/vinix-registration-memory-' + os.getpid().str()
	os.mkdir_all(root + '/generations/1')!
	defer { os.rmdir_all(root) or {} }
	path := root + '/generations/1/state.json'
	os.write_file(path, text)!
	os.symlink('generations/1', root + '/current')!
	bad_root := root + '/bad'
	os.mkdir_all(bad_root + '/generations/1')!
	os.write_file(bad_root + '/generations/1/state.json', invalid[0])!
	os.symlink('generations/1', bad_root + '/current')!
	alias_root := root + '/alias'
	os.mkdir_all(alias_root + '/generations/2')!
	os.link(path, alias_root + '/generations/2/state.json')!
	os.symlink('generations/2', alias_root + '/current')!
	mut registry := packagecore.Registry{}
	owner := u32(os.geteuid())
	for warmup in 0 .. 2 {
		if warmup == 1 { C.vinix_heap_begin() }
		for _ in 0 .. 1000 {
			assert registry.refresh(root, owner, 'aarch64')!
			assert !registry.refresh(root, owner, 'aarch64')!
			for target in [bad_root, root, alias_root]! {
				mut refused := false
				registry.refresh(target, owner, if target == root { 'x86_64' } else { 'aarch64' }) or {
					refused = true
					message := err.msg(); unsafe { message.free(); err.free() }
				}
				assert refused && registry.generation == 1 && registry.apps.len == 32
			}
			registry.close()
		}
	}
	retained := C.vinix_heap_end()
	assert retained == 0, 'registration reload retained ${retained} bytes'
	println('Package registry: 1000 reload/cache/partial-refusal/architecture-refusal/generation-refusal/retirement cycles retain zero tracked bytes')
}
