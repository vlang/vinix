// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time
import tools.packages.pkgprotocol

fn C.mkfifo(&char, u32) int

struct DownloadRecoveryFixture {
	work string
	root string
	directory string
	object string
	part string
	source string
	text string
	payload Payload
}

fn download_recovery_record(event pkgprotocol.Progress) {
	event.validate() or { panic(err) }
	mut file := os.open_file(os.getenv('VINIX_DOWNLOAD_RECOVERY_EVENTS'), 'a', 0o600) or { panic(err) }
	file.writeln(json2.encode(event)) or { panic(err) }
	file.close()
}

fn download_recovery_fixture(label string) !DownloadRecoveryFixture {
	work := os.temp_dir() + '/vinix-download-recovery-' + label + '-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	root := work + '/root'
	os.mkdir_all(root + '/etc/vinix-packages')!
	os.mkdir_all(work + '/source/bin')!
	text := 'authenticated application payload\n'.repeat(4096)
	os.write_file(work + '/source/bin/app', text)!
	os.chmod(work + '/source/bin/app', 0o755)!
	key := keygen(work + '/seed')!
	config := Config{ architecture: 'aarch64', repositories: [Repository{ id: 'trusted',
		url: 'file://' + work + '/repository', public_key: key }], policy: Policy{ offline: true, reserve_bytes: 0 } }
	os.write_file(root + '/etc/vinix-packages/config.json', json2.encode(config))!
	os.write_file(work + '/manifest.json', json2.encode(Package{ id: 'app', name: 'Application', version: '1.0.0',
		architecture: 'aarch64', kind: 'native', license: 'MIT', entrypoint: 'bin/app' }))!
	p := pack(work + '/manifest.json', work + '/source', work + '/repository')!
	publish(work + '/repository', 'trusted', work + '/seed', 1, time.now().unix() + 3600)!
	service := Service{ root: root }
	service.refresh()!
	service.transact('install', ['app'], TransactionOptions{})!
	service.transact('remove', ['app'], TransactionOptions{})!
	directory := state_directory(root)
	object := directory + '/objects/' + p.files[0].sha256
	os.rm(object)!
	os.write_file(work + '/events', '')!
	os.setenv('VINIX_DOWNLOAD_RECOVERY_EVENTS', work + '/events', true)
	return DownloadRecoveryFixture{ work: work, root: root, directory: directory, object: object,
		part: object + '.part', source: work + '/repository/objects/' + p.files[0].sha256, text: text, payload: p.files[0] }
}

fn (fixture DownloadRecoveryFixture) close() {
	os.unsetenv('VINIX_DOWNLOAD_RECOVERY_EVENTS')
	os.rmdir_all(fixture.work) or { panic(err) }
}

fn (fixture DownloadRecoveryFixture) service() Service {
	return Service{ root: fixture.root, progress: download_recovery_record }
}

// Verification emits progress too. Keep health reads out of the transaction's
// event log so assertions describe only the download/recovery under test.
fn (fixture DownloadRecoveryFixture) verified_state() !State {
	return Service{ root: fixture.root }.verify()
}

fn (fixture DownloadRecoveryFixture) events() ![]pkgprotocol.Progress {
	mut result := []pkgprotocol.Progress{}
	for line in os.read_file(fixture.work + '/events')!.split_into_lines() {
		result << pkgprotocol.decode_progress(line)!
	}
	return result
}

fn test_corrupt_resumed_prefix_restarts_once_and_activates_verified_bytes() {
	fixture := download_recovery_fixture('prefix')!
	defer { fixture.close() }
	os.write_file(fixture.part, 'wrong prefix'.repeat(1024))!
	mut review := fixture.service().review('install', ['app'])!
	defer { review.close() }
	state := fixture.service().transact('install', ['app'], TransactionOptions{ expected_review: review.fingerprint })!
	assert state.generation == 3 && state.previous == 2
	assert fixture.verified_state()!.generation == 3 && verified_file(fixture.object, fixture.payload)
	assert !os.exists(fixture.part) && os.read_file(fixture.directory + '/current/apps/app/bin/app')! == fixture.text
	events := fixture.events()!
	downloads := events.filter(it.phase == 'download')
	assert downloads.first().current == 12 * 1024 && downloads.filter(it.current == 0).len == 1
	assert downloads.filter(it.current == it.total).len == 2 && downloads.all(it.current <= it.total)
	assert events[events.len - 2].phase == 'activate' && events.last().phase == 'complete'
	println('Package download recovery: damaged resumed prefix restarted once and verified before activation')
}

fn test_complete_invalid_and_oversized_partials_start_fresh_while_valid_partials_stay_cached() {
	for mode in ['complete-invalid', 'oversized', 'valid-prefix', 'valid-complete', 'empty'] {
		fixture := download_recovery_fixture(mode)!
		defer { fixture.close() }
		content := match mode {
			'complete-invalid' { 'x'.repeat(fixture.text.len) }
			'oversized' { fixture.text + 'overflow' }
			'valid-prefix' { fixture.text[..4096] }
			'valid-complete' { fixture.text }
			else { '' }
		}
		os.write_file(fixture.part, content)!
		if mode == 'valid-complete' { os.rm(fixture.source)! }
		assert fixture.service().transact('install', ['app'], TransactionOptions{})!.generation == 3
		assert verified_file(fixture.object, fixture.payload) && !os.exists(fixture.part)
		downloads := fixture.events()!.filter(it.phase == 'download')
		if mode == 'valid-complete' { assert downloads.len == 0 }
		else {
			assert downloads.first().current == if mode == 'valid-prefix' { u64(4096) } else { u64(0) }
			assert downloads.filter(it.current == it.total).len == 1
		}
	}
}

fn test_bad_repository_stops_after_bounded_recovery_and_preserves_activation_and_rollback() {
	for resumed in [true, false] {
		fixture := download_recovery_fixture('bad-source-' + resumed.str())!
		defer { fixture.close() }
		if resumed { os.write_file(fixture.part, 'bad-prefix')! }
		os.write_file(fixture.source, 'x'.repeat(fixture.text.len))!
		mut refused := false
		fixture.service().transact('install', ['app'], TransactionOptions{}) or {
			refused = err.msg().contains('payload checksum or size mismatch')
		}
		assert refused && fixture.verified_state()!.generation == 2
		assert os.readlink(fixture.directory + '/current')! == 'generations/2'
		assert !os.exists(fixture.part) && !os.exists(fixture.object)
		assert os.ls(fixture.directory + '/generations')!.sorted() == ['1', '2']
		events := fixture.events()!
		assert events.filter(it.phase == 'verify').len == if resumed { 2 } else { 1 }
		assert events.all(it.phase !in ['activate', 'complete'])
		assert fixture.service().rollback('')!.generation == 3 && fixture.verified_state()!.generation == 3
		assert fixture.verified_state()!.previous == 2 && fixture.verified_state()!.packages.len == 1
	}
	println('Package download recovery: bad source refused after bounded attempts; activation and rollback preserved')
}

fn test_partial_special_files_refuse_before_transfer_and_symbolic_targets_are_preserved() {
	for kind in ['directory', 'fifo', 'symlink', 'dangling-symlink'] {
		fixture := download_recovery_fixture(kind)!
		defer { fixture.close() }
		outside := fixture.work + '/outside'
		match kind {
			'directory' { os.mkdir(fixture.part)!; os.write_file(fixture.part + '/sentinel', 'keep')! }
			'fifo' { assert C.mkfifo(fixture.part.str, 0o600) == 0 }
			'symlink' { os.write_file(outside, 'untouched')!; os.symlink(outside, fixture.part)! }
			else { os.symlink(outside, fixture.part)! }
		}
		if kind in ['directory', 'fifo'] {
			mut refused := false
			fixture.service().transact('install', ['app'], TransactionOptions{}) or {
				refused = err.msg().contains('partial download must be an ordinary regular file')
			}
			assert refused && fixture.service().state()!.generation == 2 && os.exists(fixture.part)
			assert fixture.events()!.all(it.phase !in ['download', 'verify', 'activate', 'complete'])
			if kind == 'directory' { assert os.read_file(fixture.part + '/sentinel')! == 'keep' }
		} else {
			assert fixture.service().transact('install', ['app'], TransactionOptions{})!.generation == 3
			assert verified_file(fixture.object, fixture.payload) && !os.is_link(fixture.part)
			if kind == 'symlink' { assert os.read_file(outside)! == 'untouched' }
			else { assert !os.exists(outside) }
		}
	}
}

fn test_verification_metadata_and_offline_fetch_refuse_fifo_without_opening_it() {
	fixture := download_recovery_fixture('fifo-reads')!
	defer { fixture.close() }
	os.rm(fixture.source)!
	assert C.mkfifo(fixture.source.str, 0o600) == 0
	assert !verified_file(fixture.source, Payload{ ...fixture.payload, bytes: 0 })
	mut hash_refused := false
	hash_file(fixture.source) or { hash_refused = err.msg().contains('regular file') }
	assert hash_refused
	mut metadata_refused := false
	read_metadata(fixture.source) or { metadata_refused = err.msg().contains('regular file') }
	assert metadata_refused
	mut transfer_refused := false
	fixture.service().transact('install', ['app'], TransactionOptions{}) or {
		transfer_refused = err.msg().contains('offline repository file unavailable')
	}
	assert transfer_refused && fixture.service().state()!.generation == 2
	assert !os.exists(fixture.object) && !os.exists(fixture.part)
	assert fixture.events()!.all(it.phase !in ['activate', 'complete'])
}

fn test_oversized_offline_source_preserves_partial_activation_and_restored_resume() {
	fixture := download_recovery_fixture('oversized-source')!
	defer { fixture.close() }
	prefix := fixture.text[..4096]
	os.write_file(fixture.part, prefix)!
	os.write_file(fixture.source, fixture.text + 'overflow')!
	mut refused := false
	fixture.service().transact('install', ['app'], TransactionOptions{}) or {
		refused = err.msg().contains('exceeds authenticated size')
	}
	assert refused && fixture.verified_state()!.generation == 2
	assert os.read_file(fixture.part)! == prefix && !os.exists(fixture.object)
	assert fixture.events()!.all(it.phase !in ['download', 'verify', 'activate', 'complete'])
	assert os.ls(fixture.directory + '/generations')!.sorted() == ['1', '2']
	os.write_file(fixture.source, fixture.text)!
	assert fixture.service().transact('install', ['app'], TransactionOptions{})!.generation == 3
	assert verified_file(fixture.object, fixture.payload) && !os.exists(fixture.part)
	assert fixture.events()!.filter(it.phase == 'download').first().current == 4096
}
