// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import json2
import os
import time

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32

fn administration_encoding_fixture() (Config, TrustHistory) {
	repository := Repository{ id: 'trusted', url: 'file:///srv/é/文件/"quoted"/back\\slash', public_key: 'a'.repeat(64) }
	config := Config{ architecture: 'aarch64', repositories: [repository], launch_user: 'alex',
		policy: Policy{ offline: true, allowed: ['editor'], pins: [Dependency{ id: 'editor', minimum: '1.0.0', before: '2.0.0' }],
			permissions: ['files'], licenses: ['Vendor-EULA'], allow_firmware: true, reserve_bytes: ~u64(0) } }
	mut floors := []RepositoryFloor{}
	for i in 0 .. 128 {
		floors << RepositoryFloor{ id: 'publisher-' + i.str(), public_key: repository.public_key,
			sequence: if i == 127 { ~u64(0) } else { u64(i + 1) }, index_sha256: 'b'.repeat(64) }
	}
	return config, TrustHistory{ repositories: floors }
}

fn check_administration_bytes[T](value T) ! {
	body := json2.encode(value)
	expected := body + '\n'
	actual := encode_administration_document(value, 'too large')!
	defer { unsafe { body.free(); expected.free(); actual.free() } }
	assert actual == expected
}

fn test_administration_encodings_preserve_exact_json_and_reader_round_trips() {
	config, history := administration_encoding_fixture()
	check_administration_bytes(config)!
	check_administration_bytes(Config{ architecture: 'x86_64' })!
	check_administration_bytes(history)!
	check_administration_bytes(TrustHistory{})!
	check_administration_bytes(ReleaseHistory{ indexes: history.repositories })!
	check_administration_bytes(ReleaseHistory{})!
	consumer := encode_administration_document(history, 'too large')!
	publisher := encode_administration_document(ReleaseHistory{ indexes: history.repositories }, 'too large')!
	decoded_consumer := decode_history(consumer, false)!
	decoded_publisher := decode_history(publisher, true)!
	assert decoded_consumer == history && decoded_publisher == history
	close_decoded_history(decoded_consumer); close_decoded_history(decoded_publisher)
	unsafe { consumer.free(); publisher.free() }
	println('ADMINISTRATION METADATA configuration and both history formats preserve exact JSON, escaping, defaults, u64 widths and reader round-trips PASS')
}

fn administration_boundary_config() Config {
	// Synthetic scalar length isolates the persisted byte boundary, rather than
	// configuration admission. Writers keep the same serialization limit.
	base := Config{ architecture: 'aarch64' }
	text := json2.encode(base)
	length := max_metadata - text.len - 1
	unsafe { text.free() }
	return Config{ ...base, launch_user: 'x'.repeat(length) }
}

fn test_administration_document_limit_includes_newline_and_escape_expansion() {
	boundary := administration_boundary_config()
	below := Config{ ...boundary, launch_user: boundary.launch_user[..boundary.launch_user.len - 1] }
	for config in [below, boundary] {
		text := encode_administration_document(config, 'exact limit diagnostic')!
		assert text.len == max_metadata - (boundary.launch_user.len - config.launch_user.len)
		assert text.ends_with('\n') && !text.ends_with('\n\n')
		unsafe { text.free() }
	}
	for config in [Config{ ...boundary, launch_user: boundary.launch_user + 'x' },
		Config{ ...boundary, launch_user: '"'.repeat(max_metadata / 2) }] {
		if text := encode_administration_document(config, 'exact limit diagnostic') { unsafe { text.free() }; assert false }
		else {
			message := err.msg(); assert message == 'exact limit diagnostic'
			unsafe { message.free(); err.free() }
		}
	}
	println('ADMINISTRATION METADATA limit-minus-one and exact 8 MiB accepted; newline and escape expansion overflow refused PASS')
}

fn test_repository_fingerprint_preserves_legacy_digest_and_binds_every_review_input() {
	config, history := administration_encoding_fixture()
	repository := config.repositories[0]
	digest := 'c'.repeat(64)
	for operation in ['enroll', 'revoke'] {
		identity := RepositoryReviewIdentity{ config: config, history: history, operation: operation, repository: repository, index_sha256: digest }
		legacy := json2.encode(identity)
		expected := sha256.hexhash(legacy)
		actual := repository_fingerprint(config, history, operation, repository, digest)
		assert actual == expected
		assert repository_fingerprint(Config{ ...config, architecture: 'x86_64' }, history, operation, repository, digest) != actual
		assert repository_fingerprint(config, TrustHistory{}, operation, repository, digest) != actual
		assert repository_fingerprint(config, history, operation, Repository{ ...repository, url: repository.url + '/changed' }, digest) != actual
		assert repository_fingerprint(config, history, operation, repository, 'd'.repeat(64)) != actual
		assert repository_fingerprint(config, history, operation + '-changed', repository, digest) != actual
		unsafe { legacy.free(); expected.free(); actual.free() }
	}
	println('ADMINISTRATION METADATA review fingerprints preserve legacy digests and bind configuration, history, intent, publisher and index bytes PASS')
}

fn test_repeated_administration_encoding_and_fingerprinting_retire_all_scratch() {
	$if track_heap ? {
		config, history := administration_encoding_fixture()
		repository := config.repositories[0]
		digest := 'c'.repeat(64)
		for _ in 0 .. 64 {
			C.vinix_heap_begin()
			configuration := encode_administration_document(config, 'too large')!
			consumer := encode_administration_document(history, 'too large')!
			publisher := encode_administration_document(ReleaseHistory{ indexes: history.repositories }, 'too large')!
			fingerprint := repository_fingerprint(config, history, 'enroll', repository, digest)
			unsafe { configuration.free(); consumer.free(); publisher.free(); fingerprint.free() }
			kept := C.vinix_heap_end(); count := C.vinix_heap_count()
			assert kept == 0 && count == 0, '${kept} bytes / ${count} allocations retained'
		}
		boundary := administration_boundary_config()
		rejected := Config{ ...boundary, launch_user: boundary.launch_user + 'x' }
		for _ in 0 .. 8 {
			C.vinix_heap_begin()
			if text := encode_administration_document(rejected, 'too large') { unsafe { text.free() }; assert false }
			else { message := err.msg(); unsafe { message.free(); err.free() } }
			kept := C.vinix_heap_end(); count := C.vinix_heap_count()
			assert kept == 0 && count == 0, '${kept} bytes / ${count} allocations retained'
		}
		assert config.repositories[0] == repository && history.repositories.len == 128
		println('ADMINISTRATION METADATA 64 accepted encoding/fingerprint passes and 8 oversized refusals retain zero scratch after caller cleanup PASS')
	}
}

fn test_administration_writes_preserve_inputs_and_refuse_before_replacing_oversized_documents() {
	directory := os.temp_dir() + '/vinix-administration-encoding-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(directory)!
	defer { os.rmdir_all(directory) or {} }
	config, history := administration_encoding_fixture()
	path := directory + '/config.json'
	for _ in 0 .. 3 { save_configuration(path, config)!; save_history(directory, history)! }
	configuration := os.read_file(path)!
	remembered := read_history(directory)!
	assert configuration == json2.encode(config) + '\n' && remembered == history
	close_decoded_history(remembered)
	boundary := administration_boundary_config()
	oversized := Config{ ...boundary, launch_user: boundary.launch_user + 'x' }
	if _ := save_configuration(path, oversized) { assert false }
	else { assert err.msg() == 'package administration metadata exceeds its size limit' }
	assert os.read_file(path)! == configuration
	too_big := TrustHistory{ repositories: [RepositoryFloor{ id: 'x'.repeat(max_metadata) }] }
	before := os.read_file(directory + '/trust-history.json')!
	if _ := save_history(directory, too_big) { assert false }
	else { assert err.msg() == 'repository trust history exceeds metadata limit' }
	assert os.read_file(directory + '/trust-history.json')! == before
	blocked := directory + '/blocked'
	os.mkdir(blocked)!
	if _ := save_configuration(blocked, config) { assert false }
	assert os.is_dir(blocked) && os.read_file(path)! == configuration
	assert os.ls(directory)!.len == 3
	assert config.repositories.len == 1 && history.repositories.len == 128
	println('ADMINISTRATION METADATA repeated writes remain readable; oversized and publication failures preserve prior documents and source models PASS')
}
