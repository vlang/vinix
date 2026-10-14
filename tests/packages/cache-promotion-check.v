// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import tools.packages.pkgcore
import tools.packages.pkgprotocol

fn record(event pkgprotocol.Progress) {
	mut file := os.open_file(os.getenv('VINIX_CACHE_PROBE_EVENTS'), 'a') or { panic(err) }
	file.writeln(event.phase) or { panic(err) }; file.close()
	if event.phase == 'verify' && os.getenv('VINIX_CACHE_PROBE_SWAP') == '1' {
		os.unsetenv('VINIX_CACHE_PROBE_SWAP')
		partial := os.getenv('VINIX_CACHE_PROBE_PARTIAL')
		os.rm(partial) or { panic(err) }
		os.link(os.getenv('VINIX_CACHE_PROBE_OUTSIDE'), partial) or { panic(err) }
	}
}

fn check_case(directory string, mode string, before bool) ! {
	root := directory + '/root'
	os.mkdir_all(root + '/etc/vinix-packages')!
	os.mkdir_all(directory + '/source/bin')!
	text := 'authenticated cache payload\n'.repeat(1024)
	os.write_file(directory + '/source/bin/app', text)!; os.chmod(directory + '/source/bin/app', 0o755)!
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	manifest := pkgcore.Package{ id: 'app', name: 'Application', version: '1.0.0', architecture: architecture,
		kind: 'native', license: 'MIT', entrypoint: 'bin/app' }
	os.write_file(directory + '/manifest.json', json2.encode(manifest))!
	package := pkgcore.pack(directory + '/manifest.json', directory + '/source', directory + '/repository')!
	key := pkgcore.keygen(directory + '/seed')!
	pkgcore.publish(directory + '/repository', 'fixture', directory + '/seed', 1, time.now().unix() + 3600)!
	config := pkgcore.Config{ architecture: architecture, policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 },
		repositories: [pkgcore.Repository{ id: 'fixture', url: 'file://' + directory + '/repository', public_key: key }] }
	os.write_file(root + '/etc/vinix-packages/config.json', json2.encode(config))!
	initial := pkgcore.Service{ root: root }
	initial.refresh()!
	initial.transact('install', ['app'], pkgcore.TransactionOptions{})!
	initial.transact('remove', ['app'], pkgcore.TransactionOptions{})!
	store := pkgcore.state_directory(root)
	payload := package.files[0]
	object := store + '/objects/' + payload.sha256
	partial := object + '.part'
	os.rm(object)!
	outside := directory + '/outside'
	content := match mode {
		'prefix' { text[..4096] }
		'invalid-complete' { 'x'.repeat(text.len) }
		'oversized' { text + 'overflow' }
		else { text }
	}
	os.write_file(outside, content)!; os.chmod(outside, 0o640)!
	if mode == 'verify-hardlink' { os.write_file(partial, content)!; os.chmod(partial, 0o640)! }
	else { os.link(outside, partial)! }
	cache := os.read_file(store + '/catalog.json')!
	history := os.read_file(store + '/trust-history.json')!
	state := os.read_file(store + '/current/state.json')!
	os.write_file(directory + '/events', '')!
	os.setenv('VINIX_CACHE_PROBE_EVENTS', directory + '/events', true)
	os.setenv('VINIX_CACHE_PROBE_PARTIAL', partial, true); os.setenv('VINIX_CACHE_PROBE_OUTSIDE', outside, true)
	if mode == 'verify-hardlink' { os.setenv('VINIX_CACHE_PROBE_SWAP', '1', true) }
	service := pkgcore.Service{ root: root, progress: record }
	mut review := service.review('install', ['app'])!
	defer { review.close() }
	mut message := ''
	service.transact('install', ['app'], pkgcore.TransactionOptions{ expected_review: review.fingerprint }) or { message = err.msg() }
	if before {
		assert mode == 'valid-complete' && message == '' && service.verify()!.generation == 3
		assert os.read_file(outside)! == content && os.lstat(outside)!.mode & 0o777 == 0o444
		println('CACHE PROMOTION BEFORE: complete hard-linked partial installed and changed unrelated file permissions from 0640 to 0444')
		return
	}
	assert message.contains('without hard links'), message
	assert service.verify()!.generation == 2 && os.read_file(store + '/current/state.json')! == state
	assert os.read_file(outside)! == content && os.lstat(outside)!.mode & 0o777 == 0o640
	assert os.read_file(partial)! == content && !os.exists(object)
	assert os.read_file(store + '/catalog.json')! == cache && os.read_file(store + '/trust-history.json')! == history
	events := os.read_file(directory + '/events')!.split_into_lines()
	assert events.all(it !in ['activate', 'complete'])
	if mode != 'verify-hardlink' { assert events.all(it !in ['download', 'verify']) }
	// Retiring only the alias permits an ordinary verified retry without the
	// upstream payload. The unrelated file's bytes/mode stay unchanged.
	os.rm(partial)!; os.write_file(partial, text)!
	os.rm(directory + '/repository/objects/' + payload.sha256)!
	os.write_file(directory + '/events', '')!
	assert service.transact('install', ['app'], pkgcore.TransactionOptions{ expected_review: review.fingerprint })!.generation == 3
	assert service.verify()!.packages[0].package == package
	assert pkgcore.verified_file(object, payload) && os.lstat(object)!.mode & 0o777 == 0o444 && !os.exists(partial)
	assert os.read_file(outside)! == content && os.lstat(outside)!.mode & 0o777 == 0o640
	assert !os.read_file(directory + '/events')!.split_into_lines().contains('download')
	assert service.rollback('')!.generation == 2 && service.rollback('')!.generation == 1
	assert service.verify()!.generation == 1
	println('CACHE PROMOTION ' + mode + ': refused alias with unrelated bytes/mode and state/history preserved; ordinary offline retry and rollback PASS')
}

fn check() ! {
	if os.args.len !in [2, 3] || (os.args.len == 3 && os.args[2] != '--before') {
		return error('usage: cache-promotion-check NEW_WORK_DIRECTORY [--before]')
	}
	work := os.abs_path(os.args[1])
	if os.exists(work) || os.is_link(work) { return error('cache promotion qualification directory must be new') }
	os.mkdir(work)!
	before := os.args.len == 3
	modes := if before { ['valid-complete'] } else { ['prefix', 'valid-complete', 'invalid-complete', 'oversized', 'verify-hardlink'] }
	for mode in modes { check_case(work + '/' + mode, mode, before)! }
	for name in ['VINIX_CACHE_PROBE_EVENTS', 'VINIX_CACHE_PROBE_PARTIAL', 'VINIX_CACHE_PROBE_OUTSIDE', 'VINIX_CACHE_PROBE_SWAP'] { os.unsetenv(name) }
	if !before { println('CACHE PROMOTION signed reviewed recovery, hard-link refusal, preserved outside metadata and ordinary cache/rollback PASS') }
}

fn main() { check() or { eprintln(err); exit(1) } }
