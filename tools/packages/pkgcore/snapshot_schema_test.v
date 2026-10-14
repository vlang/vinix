// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn snapshot_schema_work() !string {
	path := os.real_path(os.temp_dir()) + '/vinix-snapshot-schema-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(path)!
	return path
}

fn snapshot_schema_fixture() string {
	return json2.encode([Snapshot{ repository: Repository{ id: 'publisher', url: 'file:///repository', public_key: 'a'.repeat(64) },
		text: '{"format":1}', signature: 'b'.repeat(128) }])
}

fn test_cache_reader_refuses_null_ambiguous_incomplete_and_dangling_records() {
	work := snapshot_schema_work()!
	defer { os.rmdir_all(work) or {} }
	text := snapshot_schema_fixture()
	mut accepted := 0
	for label, invalid in {
		'null cache': 'null'
		'unknown field': text.replace('"repository":', '"future":false,"repository":')
		'duplicate text': text.replace('"text":', '"text":"ignored","text":')
		'missing URL': text.replace('"url":"file:///repository",', '')
	} {
		assert invalid != text
		os.write_file(work + '/catalog.json', invalid)!
		mut admitted := false
		if _ := read_snapshots(work) { admitted = true; accepted++ }
		println('Snapshot probe: ' + label + ' accepted=' + admitted.str())
	}
	os.rm(work + '/catalog.json')!
	os.symlink(work + '/absent', work + '/catalog.json')!
	mut dangling := false
	if _ := read_snapshots(work) { dangling = true; accepted++ }
	println('Snapshot probe: dangling cache accepted=' + dangling.str())
	assert accepted == 0
}

fn snapshot_refused(text string) {
	if snapshots := decode_snapshots(text) { close_decoded_snapshots(snapshots); assert false, text }
}

fn snapshot_without(text string, key string, value string) string {
	field := '"' + key + '":' + value
	return if text.contains(field + ',') { text.replace_once(field + ',', '') } else { text.replace_once(',' + field, '') }
}

fn test_cached_snapshot_schema_preserves_signed_bytes_and_requires_complete_typed_unique_records() {
	text := snapshot_schema_fixture()
	for key, value in {
		'repository': json2.encode(Repository{ id: 'publisher', url: 'file:///repository', public_key: 'a'.repeat(64) })
		'text': json2.encode('{"format":1}')
		'signature': json2.encode('b'.repeat(128))
		'id': '"publisher"'
		'url': '"file:///repository"'
		'public_key': json2.encode('a'.repeat(64))
	} {
		invalid := snapshot_without(text, key, value)
		assert invalid != text
		snapshot_refused(invalid)
	}
	for invalid in ['null', '{}', '[null]', '[[[]]]', ' '.repeat(max_metadata + 1),
		text.replace('"repository":{', '"repository":null,"extra":{'),
		text.replace('"text":', '"text":false,"discard":'),
		text.replace('"signature":', '"signature":null,"discard":'),
		text.replace('"url":"file:///repository"', '"url":123'),
		text.replace('"text":', '"te\\u0078t":"ignored","text":'),
		text.replace('"url":', '"url":"https://ignored.invalid","u\\u0072l":'),
		text.replace('"url":', '"unknown":false,"url":'),
		text.replace('"id":"publisher"', '"id":"Publisher"'),
		text.replace('file:///repository', 'http://example.invalid'),
		text.replace('file:///repository', 'file:///../outside'),
		text.replace('file:///repository', 'https://example.invalid/repo?key=1'),
		text.replace('"text":' + json2.encode('{"format":1}'), '"text":""'),
		text.replace('b'.repeat(128), 'b'.repeat(257)),
		text.replace('b'.repeat(128), ''),
		text.replace('"id":"publisher"', '"id":"\\ud800"'),
		'[' + text[1..text.len - 1] + ',' + text[1..text.len - 1] + ']'] { snapshot_refused(invalid) }
	for valid in [text, ' \n' + text + '\t', text.replace('"text":', '"te\\u0078t":'),
		text.replace('"url":', '"u\\u0072l":')] {
		snapshots := decode_snapshots(valid)!
		assert json2.encode(snapshots) == text && snapshots[0].text == '{"format":1}'
		close_decoded_snapshots(snapshots)
	}
	// Signed content and legacy signature whitespace remain opaque until the
	// ordinary signature/expiry/floor checks; decoding never rewrites them.
	sample := Snapshot{ repository: Repository{ id: 'publisher', url: 'https://example.invalid/repo', public_key: 'a'.repeat(64) },
		text: " {\n\t\"text\":\"literal \\\"repository\\\": 0 and λ\"}\n", signature: 'b'.repeat(128) + '\n' }
	snapshots := decode_snapshots(json2.encode([sample]))!
	assert snapshots == [sample]
	close_decoded_snapshots(snapshots)
	work := snapshot_schema_work()!
	defer { os.rmdir_all(work) or {} }
	assert read_snapshots(work)!.len == 0 && os.ls(work)!.len == 0
	for empty in ['[]', ' \n[ ]\t'] {
		os.write_file(work + '/catalog.json', empty)!
		assert read_snapshots(work)!.len == 0 && os.read_file(work + '/catalog.json')! == empty
	}
	println('Snapshot schema: complete typed records, ambiguity refusal, exact signed bytes, legacy whitespace and fresh/empty caches passed')
}

fn test_cached_snapshot_and_configuration_identity_limits_agree() {
	mut snapshots := []Snapshot{cap: 4097}
	mut repositories := []Repository{cap: 4097}
	for i in 0 .. 4097 {
		repository := Repository{ id: 'publisher-' + i.str(), url: 'file:///repository', public_key: 'a'.repeat(64) }
		repositories << repository
		snapshots << Snapshot{ repository: repository, text: '{}', signature: 'b'.repeat(128) }
		if i == 4095 {
			decoded := decode_snapshots(json2.encode(snapshots))!
			assert decoded.len == 4096
			close_decoded_snapshots(decoded)
			(Config{ architecture: 'aarch64', repositories: repositories }).validate()!
		}
	}
	snapshot_refused(json2.encode(snapshots))
	if _ := (Config{ architecture: 'x86_64', repositories: repositories }).validate() { assert false }
}

fn snapshot_inventory(path string) ![]string {
	mut result := []string{}
	mut names := os.ls(path)!; names.sort()
	for name in names {
		child := path + '/' + name
		if os.is_link(child) { result << child + ' -> ' + os.readlink(child)!
		} else if os.is_dir(child) { result << child + '/'; result << snapshot_inventory(child)!
		} else { result << child + ' ' + hash_file(child)! }
	}
	return result
}

fn test_cache_refusal_preserves_legacy_migration_replay_floor_and_installed_recovery() {
	work := snapshot_schema_work()!
	defer { os.rmdir_all(work) or {} }
	os.mkdir_all(work + '/root/etc/vinix-packages')!
	os.mkdir_all(work + '/source/bin')!
	os.write_file(work + '/source/bin/app', 'signed payload')!
	os.chmod(work + '/source/bin/app', 0o755)!
	key := keygen(work + '/seed')!
	repository := Repository{ id: 'publisher', url: 'file://' + work + '/repository', public_key: key }
	config := Config{ architecture: 'aarch64', repositories: [repository], policy: Policy{ offline: true, reserve_bytes: 0 } }
	os.write_file(work + '/root/etc/vinix-packages/config.json', json2.encode(config))!
	os.write_file(work + '/manifest.json', json2.encode(Package{ id: 'app', version: '1.0.0', architecture: 'aarch64',
		name: 'Application', license: 'MIT', kind: 'native', entrypoint: 'bin/app' }))!
	pack(work + '/manifest.json', work + '/source', work + '/repository')!
	publish(work + '/repository', 'publisher', work + '/seed', 10, time.now().unix() + 3600)!
	service := Service{ root: work + '/root' }
	service.refresh()!
	service.transact('install', ['app'], TransactionOptions{})!
	service.transact('remove', ['app'], TransactionOptions{})!
	mut review := service.review('install', ['app'])!
	defer { review.close() }
	directory := state_directory(service.root)
	cache := os.read_file(directory + '/catalog.json')!
	os.rm(directory + '/trust-history.json')! // authenticated pre-history cache migration
	publish(work + '/repository', 'publisher', work + '/seed', 1, time.now().unix() + 3600)!
	os.mkdir(directory + '/generations/.stage-cache-sentinel')!
	os.write_file(directory + '/objects/' + 'd'.repeat(64) + '.part', 'interrupted download')!
	for invalid in ['null', cache.replace('"repository":', '"unknown":0,"repository":'),
		cache.replace('"url":', '"url":null,"discard":'),
		cache.replace('"text":', '"text":"discarded","te\\u0078t":')] {
		os.write_file(directory + '/catalog.json', invalid)!
		before := snapshot_inventory(work + '/root')!
		mut errors := []string{}
		service.refresh() or { errors << err.msg() }
		service.plan('install', ['app']) or { errors << err.msg() }
		service.review('install', ['app']) or { errors << err.msg() }
		service.transact('install', ['app'], TransactionOptions{ expected_review: review.fingerprint }) or { errors << err.msg() }
		service.mirror(work + '/invalid-mirror', ['app']) or { errors << err.msg() }
		repository_status(service.root) or { errors << err.msg() }
		review_repository(service.root, 'enroll', repository, true) or { errors << err.msg() }
		enroll_repository(service.root, repository, true) or { errors << err.msg() }
		assert errors.len == 8 && errors.all(it.contains('invalid cached repository metadata:')), errors.str()
		assert service.verify()!.generation == 2 && snapshot_inventory(work + '/root')! == before
		assert !os.exists(work + '/invalid-mirror') && !os.exists(directory + '/refresh') && !os.exists(directory + '/enrollment')
	}
	os.write_file(directory + '/catalog.json', cache)!
	if _ := service.refresh() { assert false, 'legacy cache sequence floor lost' }
	if _ := enroll_repository(service.root, repository, true) { assert false, 'legacy cache enrollment replay accepted' }
	assert !os.exists(directory + '/trust-history.json')
	service.transact('install', ['app'], TransactionOptions{ expected_review: review.fingerprint })!
	assert service.verify()!.packages.len == 1
	assert service.rollback('')!.generation == 2
	publish(work + '/repository', 'publisher', work + '/seed', 11, time.now().unix() + 3600)!
	service.refresh()!
	assert read_history(directory)!.repositories[0].sequence == 11
	service.transact('install', ['app'], TransactionOptions{})!
	os.write_file(directory + '/catalog.json', 'null')!
	revoke_repository(service.root, 'publisher')!
	service.transact('remove', ['app'], TransactionOptions{})!
	assert service.verify()!.packages.len == 0 && os.read_file(directory + '/catalog.json')! == 'null'
	println('Snapshot schema: failed migration preserves state/cache/recovery; restored legacy floor rejects replay, authentic renewal and revoked-publisher uninstall passed')
}

fn test_snapshot_schema_scanner_retires_owned_keys() {
	$if track_heap ? {
		valid := snapshot_schema_fixture()
		inputs := [valid, valid.replace('"url":"file:///repository",', ''),
			valid.replace('"text":', '"text":false,"other":'),
			valid.replace('"text":', '"te\\u0078t":"ignored","text":'),
			valid.replace('"repository":', '"unknown":0,"repository":')]
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				for i, input in inputs {
					mut accepted := true
					document_keys_schema(input, snapshot_field, snapshot_required, snapshot_value_type) or {
						accepted = false
						message := err.msg(); unsafe { message.free(); err.free() }
					}
					assert accepted == (i == 0)
				}
			}
			if warmup == 1 { kept := C.vinix_heap_end(); println('Snapshot scanner: retained ' + kept.str() + ' tracked bytes in 1000 cycles'); assert kept == 0 }
		}
	}
}
