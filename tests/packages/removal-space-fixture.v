// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import time
import tools.packages.pkgcore
import tools.packages.pkgprotocol

$if mocked_space ? {
	#include <sys/statvfs.h>
	struct C.statvfs { f_bsize usize f_frsize usize f_bavail usize }
	// The controller redirects statvfs calls through a forced-include header.
	// Production builds and target guests use the actual filesystem reports.
	@[export: 'vinix_removal_fixture_statvfs']
	fn fixture_statvfs(_ &char, output &C.statvfs) int {
		available := os.getenv_opt('VINIX_REMOVAL_FREE') or { '1073741824' }
		unsafe { output.f_bsize = 4096; output.f_frsize = 1; output.f_bavail = usize(available.u64()) }
		return 0
	}
}

fn reserve(available u64) {
	$if mocked_space ? { os.setenv('VINIX_REMOVAL_FREE', available.str(), true) }
}

fn tamper_before_copy(event pkgprotocol.Progress) {
	if event.phase != 'stage' || event.package != '' { return }
	path := os.getenv('VINIX_REMOVAL_TAMPER')
	if path != '' { os.write_file(path, 'x'.repeat(4096)) or { panic(err) } }
}

fn check() ! {
	root := os.real_path(os.temp_dir()) + '/vinix-removal-space-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(root + '/etc/vinix-packages')!
	defer { os.rmdir_all(root) or {} }
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	data := 'k'.repeat(4096)
	other := 'removed application bytes'
	os.mkdir_all(root + '/source/bin')!
	key := pkgcore.keygen(root + '/seed')!
	mut kept := pkgcore.Package{}
	for id in ['keep', 'remove'] {
		os.write_file(root + '/source/bin/one', if id == 'keep' { data } else { other })!
		os.chmod(root + '/source/bin/one', 0o755)!
		if id == 'keep' { os.write_file(root + '/source/bin/two', data)! }
		else { os.rm(root + '/source/bin/two')! }
		manifest := pkgcore.Package{ id: id, name: id, description: 'Uninstall space qualification', version: '1.0.0',
			architecture: architecture, kind: 'native', entrypoint: 'bin/one', license: 'MIT' }
		os.write_file(root + '/manifest.json', json2.encode(manifest))!
		packed := pkgcore.pack(root + '/manifest.json', root + '/source', root + '/repository')!
		if id == 'keep' { kept = packed }
	}
	pkgcore.publish(root + '/repository', 'fixture', root + '/seed', 1, time.now().unix() + 3600)!
	config := pkgcore.Config{ architecture: architecture, policy: pkgcore.Policy{ offline: true, reserve_bytes: 4096 },
		repositories: [pkgcore.Repository{ id: 'fixture', url: 'file://' + root + '/repository', public_key: key }] }
	path := root + '/etc/vinix-packages/config.json'
	os.write_file(path, json2.encode(config))!
	service := pkgcore.Service{ root: root }
	service.refresh()!
	initial := service.transact('install', ['keep', 'remove'], pkgcore.TransactionOptions{})!
	store := pkgcore.state_directory(root)
	current := os.readlink(store + '/current')!
	state := os.read_file(store + '/' + current + '/state.json')!
	retained := store + '/' + current + '/apps/keep/bin/one'
	for file in kept.files {
		object := store + '/objects/' + file.sha256
		if os.exists(object) { os.rm(object)! }
	}
	os.rename(root + '/repository/objects', root + '/hidden-objects')!
	// Uninstall must remain independent of publisher availability and damaged
	// maintenance metadata, with personal files and old generations preserved.
	os.write_file(path, json2.encode(pkgcore.Config{ ...config, repositories: [] }))!
	os.write_file(store + '/catalog.json', 'damaged catalog')!
	os.write_file(store + '/trust-history.json', 'damaged history')!
	os.mkdir_all(root + '/personal')!; os.write_file(root + '/personal/keep.txt', 'personal data')!
	expected := u64(4 * 1024 * 1024) + 2 * (u64(data.len) + 8192)
	available := expected + config.policy.reserve_bytes
	reserve(available)
	mut review := service.review('remove', ['remove'])!
	defer { review.close() }
	println('REMOVAL SPACE review: needed=${review.disk_needed}, expected=${expected}, reserve=${review.disk_reserve}')
	assert review.disk_needed == expected && review.disk_reserve == config.policy.reserve_bytes
	assert review.rows.len == 2 && review.rows.any(it.id == 'keep' && it.action == 'keep')
	assert review.rows.any(it.id == 'remove' && it.action == 'remove')
	$if mocked_space ? { assert review.disk_available == available }
	generic := pkgcore.estimate_space(pkgcore.Plan{ packages: initial.packages.filter(it.package.id == 'keep') }, store)!
	assert generic == expected + u64(data.len) + 8192
	pkgcore.disk_check(available, review.disk_needed, review.disk_reserve)!
	if _ := pkgcore.disk_check(available, generic, review.disk_reserve) { assert false }
	// A tight or newly damaged source must still refuse before activation.
	$if mocked_space ? {
		reserve(available - 1)
		if _ := service.transact('remove', ['remove'], pkgcore.TransactionOptions{ expected_review: review.fingerprint }) {
			assert false
		} else { assert err.msg().contains('insufficient disk space') }
		reserve(available)
	}
	os.write_file(retained, 'x'.repeat(data.len))!
	mut damaged := service.review('remove', ['remove'])!
	assert damaged.disk_needed == generic
	damaged.close()
	if _ := service.transact('remove', ['remove'], pkgcore.TransactionOptions{ expected_review: review.fingerprint }) {
		assert false
	} else {
		$if mocked_space ? { assert err.msg().contains('insufficient disk space') }
	}
	assert os.readlink(store + '/current')! == current && os.read_file(store + '/' + current + '/state.json')! == state
	os.write_file(retained, data)!
	// Admission does not replace per-copy verification: corruption introduced
	// by the progress observer after preflight must not activate a new set.
	os.setenv('VINIX_REMOVAL_TAMPER', retained, true)
	guarded := pkgcore.Service{ root: root, progress: tamper_before_copy }
	if _ := guarded.transact('remove', ['remove'], pkgcore.TransactionOptions{ expected_review: review.fingerprint }) { assert false }
	os.unsetenv('VINIX_REMOVAL_TAMPER')
	assert os.readlink(store + '/current')! == current
	os.write_file(retained, data)!
	final := service.transact('remove', ['remove'], pkgcore.TransactionOptions{ expected_review: review.fingerprint })!
	assert final.generation > initial.generation && final.previous == initial.generation
	assert final.requested == ['keep'] && final.packages.len == 1 && final.packages[0].package == kept
	for file in kept.files {
		assert pkgcore.verified_file(store + '/current/apps/keep/' + file.path, file)
		assert !os.exists(store + '/objects/' + file.sha256)
	}
	assert os.is_file(store + '/current/share/applications/vinix-keep.desktop')
	assert !os.exists(store + '/current/share/applications/vinix-remove.desktop')
	assert os.is_file(store + '/' + current + '/apps/remove/bin/one')
	assert os.read_file(root + '/personal/keep.txt')! == 'personal data'
	assert os.read_file(store + '/catalog.json')! == 'damaged catalog' && os.read_file(store + '/trust-history.json')! == 'damaged history'
	assert sha256.sum(os.read_bytes(store + '/current/apps/keep/bin/one')!).hex() == kept.files[0].sha256
	println('REMOVAL SPACE reviewed offline removal: verified retained files, no object reacquisition, reserve/fallback checks, post-preflight tamper refusal, activation/registration/data PASS')
	$if mocked_space ? { println('REMOVAL SPACE exact free-space threshold and one-byte-short refusal PASS') }
}

fn main() { check() or { eprintln(err); exit(1) } }
