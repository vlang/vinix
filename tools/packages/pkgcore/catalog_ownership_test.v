// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import json2
import os
import time
import tools.packages.signing

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32

fn catalog_ownership_fixture() !(string, Config) {
	directory := os.temp_dir() + '/vinix-catalog-ownership-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(directory)!
	private := signing.new_key_from_seed([]u8{len: 32, init: 7})
	repository := Repository{ id: 'trusted', url: 'file:///unused-catalog-source', public_key: private.public_key().hex() }
	p := Package{ id: 'app', name: 'Editor', version: '1.0.0', architecture: 'aarch64', kind: 'native', license: 'MIT',
		description: 'd'.repeat(2048), entrypoint: 'bin/app', arguments: ['--literal', 'x'.repeat(2048)], permissions: ['files'],
		files: [Payload{ path: 'bin/app', bytes: 7, executable: true, sha256: sha256.hexhash('payload') }] }
	text := canonical_index(Index{ repository: repository.id, sequence: 7, expires: time.now().unix() + 3600, packages: [p] })!
	signature := signing.sign(private, text.bytes())!.hex()
	os.write_file(directory + '/catalog.json', json2.encode([Snapshot{ repository: repository, text: text, signature: signature }]))!
	os.write_file(directory + '/trust-history.json', json2.encode(TrustHistory{ repositories: [RepositoryFloor{
		id: repository.id, public_key: repository.public_key, sequence: 7, index_sha256: index_digest(text) }] }))!
	return directory, Config{ architecture: 'aarch64', repositories: [repository] }
}

fn test_loaded_catalog_remains_usable_after_wrapper_and_history_scratch_are_retired() {
	directory, config := catalog_ownership_fixture()!; defer { os.rmdir_all(directory) or {} }
	catalog := load_catalog(config, directory)!
	assert catalog.packages.len == 1 && catalog.packages[0].package.description == 'd'.repeat(2048)
	plan := resolve(catalog, config, State{}, ['app'], true)!
	assert plan.packages[0].package.arguments[1] == 'x'.repeat(2048)
	assert plan.packages[0].repository == config.repositories[0].id && plan.packages[0].sequence == 7
	close_authenticated_catalog(catalog)
	assert config.repositories[0].id == 'trusted' && config.repositories[0].public_key.len == 64
	println('CATALOG OWNERSHIP returned manifests and configured publisher identities survive scratch retirement PASS')
}

fn test_repeated_catalog_loads_bound_retained_scratch_after_retiring_the_owned_result() {
	$if track_heap ? {
		directory, config := catalog_ownership_fixture()!; defer { os.rmdir_all(directory) or {} }
		warm := load_catalog(config, directory)!; close_authenticated_catalog(warm)
		mut maximum := u64(0); mut maximum_count := u32(0)
		for _ in 0 .. 64 {
			C.vinix_heap_begin()
			catalog := load_catalog(config, directory)!
			close_authenticated_catalog(catalog)
			kept := C.vinix_heap_end(); count := C.vinix_heap_count()
			assert kept <= u64(12 * 1024 + directory.len * 2) && count <= 110, 'catalog scratch: ${kept} bytes / ${count} allocations'
			if kept > maximum { maximum = kept }; if count > maximum_count { maximum_count = count }
		}
		println('CATALOG OWNERSHIP 64 loads/retirements stay within scratch budget: maximum ${maximum} bytes / ${maximum_count} allocations PASS')
	}
}

fn catalog_ownership_snapshot(repository Repository, packages []Package, expires i64) !Snapshot {
	private := signing.new_key_from_seed([]u8{len: 32, init: 7})
	text := canonical_index(Index{ repository: repository.id, sequence: 7, expires: expires, packages: packages })!
	return Snapshot{ repository: repository, text: text, signature: signing.sign(private, text.bytes())!.hex() }
}

fn test_catalog_growth_transfers_manifests_without_borrowing_wrapper_strings() {
	directory, config := catalog_ownership_fixture()!; defer { os.rmdir_all(directory) or {} }
	mut snapshots := read_snapshots(directory)!
	decoded := verify_index(config.repositories[0], snapshots[0].text, snapshots[0].signature, time.now().unix())!
	mut packages := []Package{}
	for index in 0 .. 33 { packages << Package{ ...decoded.packages[0], id: 'item-' + index.str() } }
	text := catalog_ownership_snapshot(config.repositories[0], packages, time.now().unix() + 3600)!
	mut owned := decode_snapshots(json2.encode([text]))!
	catalog := snapshots_catalog(config, owned, time.now().unix())!
	close_decoded_snapshots(owned); close_decoded_snapshots(snapshots); close_decoded_index(decoded)
	mut ids := packages.map(it.id); ids.sort()
	assert catalog.packages.len == 33
	for index, installed in catalog.packages {
		assert installed.package.id == ids[index]
		assert installed.package.arguments[1] == 'x'.repeat(2048) && installed.package.description == 'd'.repeat(2048)
		assert installed.package.files[0].path == 'bin/app' && installed.public_key == config.repositories[0].public_key
	}
	close_authenticated_catalog(catalog)
	assert config.repositories[0].id == 'trusted'
	println('CATALOG OWNERSHIP growing catalog survives source wrapper/index retirement with intact nested manifests PASS')
}

fn test_later_publisher_failures_retire_prior_transfers_without_changing_persistent_metadata() {
	directory, first := catalog_ownership_fixture()!; defer { os.rmdir_all(directory) or {} }
	base := read_snapshots(directory)!
	index := verify_index(first.repositories[0], base[0].text, base[0].signature, time.now().unix())!
	other := Repository{ ...first.repositories[0], id: 'other', url: 'file:///unused-other-source' }
	config := Config{ ...first, repositories: [first.repositories[0], other] }
	p := Package{ ...index.packages[0], id: 'other-app' }
	for fault in ['signature', 'syntax', 'schema', 'expiry', 'floor', 'equivocation', 'ambiguous', 'missing', 'identity'] {
		signed := catalog_ownership_snapshot(other, [if fault == 'ambiguous' { index.packages[0] } else { p }],
			if fault == 'expiry' { time.now().unix() - 1 } else { time.now().unix() + 3600 })!
		text := match fault {
			'syntax' { signed.text[..signed.text.len - 8] }
			'schema' { signed.text.replace('"entrypoint":"bin/app",', '') }
			else { signed.text }
		}
		private := signing.new_key_from_seed([]u8{len: 32, init: 7})
		snapshot := Snapshot{ ...signed, text: text, signature: if fault == 'signature' { '00'.repeat(64) } else { signing.sign(private, text.bytes())!.hex() } }
		snapshots := if fault == 'missing' { base } else { [base[0], snapshot] }
		catalog_text := json2.encode(snapshots)
		history_text := json2.encode(TrustHistory{ repositories: [RepositoryFloor{
			id: other.id, public_key: other.public_key, sequence: if fault == 'floor' { 8 } else { 7 },
			index_sha256: if fault == 'equivocation' { '0'.repeat(64) } else { index_digest(signed.text) } }] })
		os.write_file(directory + '/catalog.json', catalog_text)!; os.write_file(directory + '/trust-history.json', history_text)!
		active := if fault == 'identity' { Config{ ...config, repositories: [config.repositories[0], Repository{ ...other, url: 'file:///changed-source' }] } } else { config }
		if result := load_catalog(active, directory) { close_authenticated_catalog(result); assert false, fault }
		else {
			message := err.msg()
			assert message.contains(match fault {
				'signature' { 'signature verification failed' }
				'syntax' { 'unterminated administration document string' }
				'schema' { 'missing required' }
				'expiry' { 'expired' }
				'floor', 'equivocation' { 'rollback or sequence equivocation' }
				'ambiguous' { 'ambiguous package' }
				else { 'no authenticated cached index' }
			}), message
		}
		assert os.read_file(directory + '/catalog.json')! == catalog_text && os.read_file(directory + '/trust-history.json')! == history_text
		assert config.repositories[0].id == 'trusted' && config.repositories[1].id == 'other'
	}
	// A revoked, syntactically valid snapshot is ignored without authenticating
	// its retired signature or changing its retained history.
	os.write_file(directory + '/catalog.json', json2.encode([Snapshot{ ...base[0], signature: '00'.repeat(64) }]))!
	config_empty := Config{ ...config, repositories: [] }
	result := load_catalog(config_empty, directory)!; assert result.packages.len == 0; close_authenticated_catalog(result)
	if result_active := load_catalog(first, directory) { close_authenticated_catalog(result_active); assert false }
	close_decoded_index(index); close_decoded_snapshots(base)
	println('CATALOG OWNERSHIP later signature/syntax/schema/expiry/floor/equivocation/ambiguity/missing/identity refusal and revoked snapshots preserve metadata and configured identities PASS')
}
