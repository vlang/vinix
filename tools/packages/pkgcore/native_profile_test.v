// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time

fn native_fixture_elf(architecture string, interpreter bool) []u8 {
	mut bytes := []u8{len: 128}
	for i, byte in [u8(127), `E`, `L`, `F`, 2, 1, 1] { bytes[i] = byte }
	bytes[16] = 2
	bytes[18] = if architecture == 'aarch64' { u8(183) } else { u8(62) }
	bytes[20] = 1
	bytes[32] = 64
	bytes[54] = 56
	bytes[56] = 1
	bytes[64] = if interpreter { u8(3) } else { u8(1) }
	return bytes
}

fn native_profile_fixture() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-native-profile-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	for architecture in ['aarch64', 'x86_64'] {
		root := work + '/roots/' + architecture
		os.mkdir_all(root + '/bin')!
		os.mkdir_all(root + '/licenses')!
		for path in ['bin/package-hello', 'bin/counter', 'bin/memo'] {
			os.write_file_array(root + '/' + path, native_fixture_elf(architecture, false))!
			os.chmod(root + '/' + path, 0o755)!
		}
		for name in ['application-sdk-MIT.txt', 'v-MIT.txt', 'musl-MIT.txt'] { os.write_file(root + '/licenses/' + name, name)! }
	}
	return work
}

fn test_native_profile_pins_both_targets_matches_examples_and_installs_a_signed_offline_release() {
	repository := os.dir(os.dir(os.dir(os.dir(@FILE))))
	work := native_profile_fixture()!
	defer { os.rmdir_all(work) or {} }
	one := native_catalog('1.0.0', work + '/roots', work + '/one')!
	two := native_catalog('1.0.0', work + '/roots', work + '/two')!
	assert one.profile == 'native-sdk' && one.catalog_sha256 == two.catalog_sha256
	assert os.ls(one.directory)! == ['catalog.json'] && os.stat(one.directory)!.mode & 0o777 == 0o700
	recipe := catalog_recipe(read_metadata(one.catalog)!)!
	assert recipe.architectures == ['aarch64', 'x86_64'] && recipe.packages.len == 6
	for item in recipe.packages {
		p := item.recipe.manifest
		assert p.kind == 'native' && p.runtime == '' && p.dependencies.len == 0 && p.files.len == 4
		assert !p.proprietary && !p.firmware && p.license == 'MIT'
		name := if p.id == 'org.vinix.package-hello' { 'hello' } else { p.id.all_after_last('.') }
		manifest := json2.decode[Package](read_metadata(repository + '/examples/package-' + name + '/manifest-' + p.architecture + '.json')!)!
		assert Package{ ...p, files: [] } == manifest
	}
	assert pack_catalog(one.catalog, work + '/roots', work + '/workspace')!.package_count == 6
	key := keygen(work + '/seed')!
	publish_release(work + '/workspace', 'native', work + '/seed', 1, time.now().unix() + 3600, work + '/release')!
	for architecture in one.architectures {
		config := Config{ architecture: architecture, repositories: [Repository{ id: 'native', url: 'file://' + work + '/release', public_key: key }],
			policy: Policy{ offline: true, reserve_bytes: 0 } }
		store := work + '/store-' + architecture
		refresh(config, store)!
		ids := ['org.vinix.counter', 'org.vinix.memo', 'org.vinix.package-hello']
		installed := transact(config, store, 'install', ids, TransactionOptions{})!
		assert installed.packages.len == 3 && installed.packages.all(it.package.architecture == architecture)
		assert os.is_file(store + '/current/share/applications/vinix-org.vinix.memo.desktop')
		assert transact(config, store, 'remove', ids, TransactionOptions{})!.packages.len == 0
		assert !os.exists(store + '/current/share/applications/vinix-org.vinix.memo.desktop')
		assert rollback(config, store)!.packages.len == 3
	}
}

fn native_profile_no_space(_ string) !u64 { return 0 }

fn native_profile_changed(phase string, stage string) ! {
	if phase == 'created' {
		os.write_file_array(os.dir(stage) + '/roots/aarch64/bin/memo', native_fixture_elf('x86_64', false))!
	}
}

fn native_profile_changed_notice(phase string, stage string) ! {
	if phase == 'created' { os.write_file(os.dir(stage) + '/roots/aarch64/licenses/musl-MIT.txt', '')! }
}

fn native_profile_changed_lock(phase string, stage string) ! {
	if phase == 'ready' { os.write_file(stage + '/lock/catalog.json', '{}')! }
}

fn native_profile_notice_directory(phase string, stage string) ! {
	if phase == 'created' {
		path := os.dir(stage) + '/roots/aarch64/licenses/musl-MIT.txt'
		os.rm(path)!
		os.mkdir(path)!
		os.write_file(path + '/nested', 'unexpected notice directory')!
	}
}

fn native_profile_raced_target(phase string, stage string) ! {
	if phase == 'ready' { os.mkdir(os.dir(stage) + '/refused')! }
}

fn test_native_profile_refuses_bad_inputs_changed_imports_and_insufficient_space_without_output() {
	work := native_profile_fixture()!
	defer { os.rmdir_all(work) or {} }
	path := work + '/roots/aarch64/bin/memo'
	original := os.read_bytes(path)!
	for invalid in [native_fixture_elf('x86_64', false), native_fixture_elf('aarch64', true), []u8{}] {
		os.write_file_array(path, invalid)!
		mut denied := false
		native_catalog('1.0.0', work + '/roots', work + '/refused') or { denied = true }
		assert denied && !os.exists(work + '/refused')
	}
	os.write_file_array(path, original)!
	os.chmod(path, 0o644)!
	mut denied := false
	native_catalog('1.0.0', work + '/roots', work + '/refused') or { denied = true }
	assert denied && !os.exists(work + '/refused')
	os.chmod(path, 0o755)!
	for options in [CatalogOptions{ available_space: native_profile_no_space }, CatalogOptions{ checkpoint: native_profile_changed },
		CatalogOptions{ checkpoint: native_profile_changed_notice }, CatalogOptions{ checkpoint: native_profile_changed_lock }] {
		mut failed := false
		native_catalog_with('1.0.0', work + '/roots', work + '/refused', options) or { failed = true }
		assert failed && !os.exists(work + '/refused')
		os.write_file(work + '/roots/aarch64/licenses/musl-MIT.txt', 'musl-MIT.txt')!
		os.write_file_array(path, original)!
	}
	os.write_file_array(path, original)!
	os.write_file(work + '/roots/x86_64/licenses/musl-MIT.txt', '')!
	mut notice := false
	native_catalog('1.0.0', work + '/roots', work + '/refused') or { notice = err.msg().contains('redistribution notice') }
	assert notice && !os.exists(work + '/refused')
	assert os.ls(work)!.all(!it.starts_with('.vinix-native-profile-'))
}

fn test_native_profile_preserves_a_concurrent_destination() {
	work := native_profile_fixture()!
	defer { os.rmdir_all(work) or {} }
	mut raced := false
	native_catalog_with('1.0.0', work + '/roots', work + '/refused', CatalogOptions{ checkpoint: native_profile_raced_target }) or { raced = true }
	assert raced && os.is_dir(work + '/refused') && os.ls(work + '/refused')!.len == 0
	assert os.ls(work)!.all(!it.starts_with('.vinix-native-profile-'))
}

fn test_native_profile_refuses_a_notice_changed_to_a_directory_after_preflight() {
	work := native_profile_fixture()!
	defer { os.rmdir_all(work) or {} }
	mut denied := false
	native_catalog_with('1.0.0', work + '/roots', work + '/refused', CatalogOptions{ checkpoint: native_profile_notice_directory }) or {
		denied = err.msg().contains('unexpected payload')
	}
	assert denied && !os.exists(work + '/refused')
	assert os.ls(work)!.all(!it.starts_with('.vinix-native-profile-'))
}

fn test_native_profile_requires_complete_ordinary_roots_new_output_and_canonical_version() {
	work := native_profile_fixture()!
	defer { os.rmdir_all(work) or {} }
	for version in ['', '1.01.0', '1.0'] {
		mut denied := false
		native_catalog(version, work + '/roots', work + '/refused') or { denied = true }
		assert denied && !os.exists(work + '/refused')
	}
	native_catalog('1.0.0', work + '/roots', work + '/occupied')!
	before := read_metadata(work + '/occupied/catalog.json')!
	mut denied := false
	native_catalog('1.1.0', work + '/roots', work + '/occupied') or { denied = true }
	assert denied && read_metadata(work + '/occupied/catalog.json')! == before
	os.rename(work + '/roots/x86_64', work + '/saved')!
	mut missing := false
	native_catalog('1.0.0', work + '/roots', work + '/refused') or { missing = true }
	assert missing && !os.exists(work + '/refused')
	os.symlink(work + '/saved', work + '/roots/x86_64')!
	mut linked := false
	native_catalog('1.0.0', work + '/roots', work + '/refused') or { linked = true }
	assert linked && !os.exists(work + '/refused')
}
