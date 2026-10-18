// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import json2
import os

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn collection_request_cycles() int {
	$if collection_request_baseline ? { return 2 }
	$if collection_request_native ? { return 8 }
	return 64
}

fn collection_request_state(directory string, arch string, generation u64, previous u64, digest string) ! {
	name := generation.str(); path := directory + '/generations/' + name
	os.mkdir_all(path)!; os.write_file(path + '/lease', '')!
	package := Package{id: 'app', version: '1.0.0', architecture: arch, name: 'Retained é🚀 application',
		description: 'Collection keeps both referenced payloads', license: 'MIT', kind: 'data',
		files: [Payload{path: 'share/data', sha256: digest, bytes: 7}]}
	text := json2.encode(State{generation: generation, previous: previous, architecture: arch, requested: ['app'],
		packages: [Installed{package: package, repository: 'revoked', public_key: 'd'.repeat(64), sequence: 1}]})
	os.write_file(path + '/state.json', text)!
	unsafe { name.free(); path.free(); text.free() }
}

fn collection_request_prepare(directory string, mode string) !int {
	mut lease := -1
	if mode in ['reclaim', 'leased', 'unsafe-root', 'unsafe-stage', 'bad-number', 'object-directory']! {
		path := directory + '/generations/3'
		os.mkdir_all(path + '/nested/deep')!; os.write_file(path + '/lease', '')!
		os.write_file(path + '/nested/deep/obsolete', 'obsolete')!
		stage := directory + '/generations/.stage-interrupted'
		os.mkdir_all(stage + '/nested')!; os.write_file(stage + '/nested/partial', 'partial')!
		if mode == 'unsafe-root' { os.chmod(path, 0o777)! }
		if mode == 'unsafe-stage' { os.chmod(stage, 0o777)! }
		if mode == 'bad-number' { os.mkdir(directory + '/generations/03')! }
		if mode == 'leased' {
			lease = C.open((path + '/lease').str, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW)
			assert lease >= 0 && C.flock(lease, C.LOCK_SH | C.LOCK_NB) == 0
		}
		for i in 0 .. 40 {
			digest := sha256.hexhash('orphan-' + i.str())
			os.write_file(directory + '/objects/' + digest, 'orphan')!
		}
		os.write_file(directory + '/objects/' + 'a'.repeat(64) + '.part', 'partial')!
		os.write_file(directory + '/objects/' + 'c'.repeat(64) + '.part', 'partial')!
		if mode == 'object-directory' {
			os.mkdir(directory + '/objects/' + 'e'.repeat(64))!
			os.write_file(directory + '/objects/' + 'e'.repeat(64) + '/keep', 'malformed object')!
		}
	}
	return lease
}

fn collection_request_check(directory string, mode string, refused bool) ! {
	if mode == 'fresh' { return }
	assert os.read_file(directory + '/objects/' + 'a'.repeat(64))! == 'current'
	assert os.read_file(directory + '/objects/' + 'b'.repeat(64))! == 'previous'
	assert os.read_file(directory + '/objects/unrelated')! == 'keep'
	assert os.read_file(directory + '/objects/invalid.part')! == 'keep'
	assert os.readlink(directory + '/current')! == 'generations/2'
	assert os.exists(directory + '/generations/1/state.json') && os.exists(directory + '/generations/2/state.json')
	if mode in ['reclaim', 'leased', 'object-directory']! {
		assert !os.exists(directory + '/generations/.stage-interrupted')
		assert os.exists(directory + '/generations/3/lease') == (mode == 'leased')
		if mode != 'object-directory' { assert os.ls(directory + '/objects')!.len == 4 }
	} else if mode in ['unsafe-root', 'unsafe-stage', 'bad-number']! {
		assert refused && os.exists(directory + '/generations/3/lease')
		assert os.read_file(directory + '/generations/.stage-interrupted/nested/partial')! == 'partial'
		assert os.exists(directory + '/objects/' + 'c'.repeat(64) + '.part')
	}
}

fn collection_request_scope(arch string, service Service, config Config, directory string, snapshot bool, mode string, expected string) ! {
	label := arch + (if snapshot { ' explicit ' } else { ' service ' }) + mode
	selection := os.getenv('VINIX_COLLECTION_CASE')
	defer { unsafe { label.free(); selection.free() } }
	if selection != '' && selection != label { return }
	config_path := service.root + '/etc/vinix-packages/config.json'
	mut total := u64(0)
	for pass in 0 .. 2 {
		for _ in 0 .. collection_request_cycles() {
			if mode == 'fresh' { os.rmdir_all(directory)! }
			lease := collection_request_prepare(directory, mode)!
			$if track_heap ? { C.vinix_heap_begin() }
			mut refused := false
			if snapshot {
				collect(config, directory) or {
					refused = true; message := err.msg(); assert expected != '' && message.contains(expected), message
					if mode == 'object-directory' { assert err.code() == C.ENOTEMPTY || err.code() == C.EEXIST }
					unsafe { message.free(); err.free() }
				}
			} else {
				service.collect() or {
					refused = true; message := err.msg(); assert expected != '' && message.contains(expected), message
					if mode == 'object-directory' { assert err.code() == C.ENOTEMPTY || err.code() == C.EEXIST }
					unsafe { message.free(); err.free() }
				}
			}
			mut kept := u64(0); $if track_heap ? { kept = C.vinix_heap_end() }
			if pass == 1 { total += kept }
			assert refused == (expected != ''), mode
			collection_request_check(directory, mode, refused)!
			if lease >= 0 { C.close(lease) }
			if mode in ['reclaim', 'leased', 'unsafe-root', 'unsafe-stage', 'bad-number', 'object-directory']! {
				for name in ['3', '03', '.stage-interrupted']! {
					path := directory + '/generations/' + name
					if os.exists(path) { os.rmdir_all(path)! }
				}
				for name in os.ls(directory + '/objects')! {
					if name in ['unrelated', 'invalid.part']! || name == 'a'.repeat(64) || name == 'b'.repeat(64) { continue }
					path := directory + '/objects/' + name
					if os.is_dir(path) { os.rmdir_all(path)! } else { os.rm(path)! }
				}
			}
		}
	}
	println('COLLECTION REQUEST ' + label + ' retained ' + total.str() + ' tracked bytes')
	$if !collection_request_baseline ? { assert total == 0, label }
	// The service must never rewrite administrator configuration, even offline.
	if expected == '' && mode != 'invalid-root' { assert os.exists(config_path) }
}

fn test_complete_collection_requests_retire_success_and_refusal_storage() {
	selection := os.getenv('VINIX_COLLECTION_CASE')
	defer { unsafe { selection.free() } }
	for arch in ['aarch64', 'x86_64']! {
		if selection != '' && !selection.starts_with(arch) { continue }
		work := os.temp_dir() + '/vinix-collection-request-' + arch + '-' + os.getpid().str()
		defer { os.rmdir_all(work) or {} }
		root := work + '/root'; directory := state_directory(root); path := root + '/etc/vinix-packages/config.json'
		os.mkdir_all(root + '/etc/vinix-packages')!
		config := Config{architecture: arch, repositories: [], policy: Policy{offline: true, reserve_bytes: 0}}
		borrowed := json2.encode(config)
		save_configuration(path, config)!; service := Service{root: root, offline: true}
		guard := acquire(directory)!; guard.release()
		for snapshot in [false, true]! { collection_request_scope(arch, service, config, directory, snapshot, 'fresh', '')! }
		collection_request_state(directory, arch, 1, 0, 'b'.repeat(64))!
		collection_request_state(directory, arch, 2, 1, 'a'.repeat(64))!
		os.symlink('generations/2', directory + '/current')!
		os.write_file(directory + '/objects/' + 'a'.repeat(64), 'current')!
		os.write_file(directory + '/objects/' + 'b'.repeat(64), 'previous')!
		os.write_file(directory + '/objects/unrelated', 'keep')!; os.write_file(directory + '/objects/invalid.part', 'keep')!
		os.write_file(directory + '/catalog.json', '{untrusted catalog')!
		os.write_file(directory + '/trust-history.json', '{untrusted history')!
		original := os.read_file(path)!
		active := os.read_file(directory + '/generations/2/state.json')!
		previous := os.read_file(directory + '/generations/1/state.json')!
		for snapshot in [false, true]! {
			for mode in ['retained', 'reclaim', 'leased', 'unsafe-root', 'unsafe-stage', 'bad-number', 'object-directory']! {
				expected := match mode { 'unsafe-root' { 'collection' } 'unsafe-stage' { 'unsafe unpublished' } 'bad-number' { 'canonical positive' } 'object-directory' { 'remove' } else { '' } }
				collection_request_scope(arch, service, config, directory, snapshot, mode, expected)!
			}
			for number in ['2', '1']! {
				metadata := directory + '/generations/' + number + '/state.json'
				os.write_file(metadata, '{broken state')!
				collection_request_scope(arch, service, config, directory, snapshot, if number == '2' { 'bad-current' } else { 'bad-previous' }, 'metadata')!
				os.write_file(metadata, if number == '2' { active } else { previous })!
			}
		}
		busy := acquire(directory)!; os.write_file(path, '{broken config')!
		for snapshot in [false, true]! { collection_request_scope(arch, service, config, directory, snapshot, 'busy-before-config', 'another package transaction')! }
		busy.release()
		collection_request_scope(arch, service, config, directory, false, 'bad-config', 'invalid package configuration')!
		os.write_file(path, original)!
		collection_request_scope(arch, Service{root: 'relative'}, config, directory, false, 'invalid-root', 'absolute directory')!
		assert os.read_file(path)! == original
		assert os.read_file(directory + '/generations/2/state.json')! == active
		assert os.read_file(directory + '/generations/1/state.json')! == previous
		assert os.read_file(directory + '/catalog.json')! == '{untrusted catalog'
		assert os.read_file(directory + '/trust-history.json')! == '{untrusted history'
		after := json2.encode(config); assert after == borrowed
		unsafe { borrowed.free(); after.free() }
	}
	$if !collection_request_baseline ? {
		if selection == '' {
			println('COLLECTION REQUEST complete service and explicit calls preserve retained payloads, live leases, recovery refusals and borrowed configuration across 64 calls per case on both declarations PASS')
		} else { println('COLLECTION REQUEST selected case PASS') }
	}
}
