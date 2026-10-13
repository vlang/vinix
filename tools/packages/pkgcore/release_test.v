// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time

fn C.fork() int
fn C.waitpid(int, &int, int) int
fn C._exit(int)

fn release_fixture() !(string, string, i64) {
	work := os.real_path(os.temp_dir()) + '/vinix-release-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(work + '/source/bin')!
	os.mkdir_all(work + '/repository')!
	os.chmod(work + '/repository', 0o700)!
	key := keygen(work + '/seed')!
	for architecture in ['aarch64', 'x86_64'] {
		os.write_file(work + '/source/bin/app', 'application ' + architecture)!
		os.chmod(work + '/source/bin/app', 0o755)!
		p := Package{ id: 'app', name: 'Application', version: '1.0.0', architecture: architecture,
			license: 'MIT', kind: 'native', entrypoint: 'bin/app', dependencies: [Dependency{ id: 'assets', before: '2.0.0' }] }
		os.write_file(work + '/manifest.json', json2.encode(p))!
		pack(work + '/manifest.json', work + '/source', work + '/repository')!
	}
	os.write_file(work + '/source/bin/app', 'licensed firmware bytes')!
	os.write_file(work + '/manifest.json', json2.encode(Package{ id: 'assets', name: 'Assets',
		version: '1.0.0', architecture: 'all', kind: 'data', license: 'Vendor-EULA', proprietary: true, firmware: true }))!
	pack(work + '/manifest.json', work + '/source', work + '/repository')!
	return work, key, time.now().unix() + 3600
}

fn test_release_reproducibility_both_architectures_and_no_private_publisher_files() {
	work, key, expires := release_fixture()!
	defer { os.rmdir_all(work) or {} }
	first := publish_release(work + '/repository', 'fixture', work + '/seed', 1, expires, work + '/first')!
	os.symlink(work, work + '/parent-alias')!
	second := publish_release(work + '/parent-alias/repository', 'fixture', work + '/parent-alias/seed', 1, expires, work + '/second')!
	assert first.package_count == 3 && first.object_count == 3 && first.public_key == key
	assert second.index_sha256 == first.index_sha256
	assert os.read_file(work + '/first/index.json')! == os.read_file(work + '/second/index.json')!
	assert os.read_file(work + '/first/index.sig')! == os.read_file(work + '/second/index.sig')!
	mut names := os.ls(work + '/first')!
	names.sort()
	assert names == ['index.json', 'index.sig', 'objects']
	assert !os.exists(work + '/repository/index.json') && !os.exists(work + '/repository/index.sig')
	assert os.stat(work + '/repository')!.mode & 0o777 == 0o700
	assert os.stat(work + '/repository/.publisher')!.mode & 0o777 == 0o700
	for architecture in ['aarch64', 'x86_64'] {
		store := work + '/store-' + architecture
		config := Config{ architecture: architecture,
			repositories: [Repository{ id: 'fixture', url: 'file://' + work + '/first', public_key: key }],
			policy: Policy{ offline: true, licenses: ['Vendor-EULA'], allow_firmware: true, reserve_bytes: 0 } }
		catalog := refresh(config, store)!
		assert catalog.packages.len == 3
		mut denied := false
		resolve(catalog, Config{ ...config, policy: Policy{ reserve_bytes: 0 } }, State{}, ['app'], true) or { denied = true }
		assert denied, 'publisher validation accepted a license on behalf of the consumer'
		state := transact(config, store, 'install', ['app'], TransactionOptions{})!
		assert state.packages.len == 2 && state.packages.any(it.package.architecture == 'all')
		assert os.read_file(store + '/generations/1/apps/app/bin/app')! == 'application ' + architecture
	}
	assert os.ls(work)!.all(!it.starts_with('.vinix-release-'))
}

fn test_release_missing_and_wrong_architecture_closures_cannot_hide_behind_other_versions() {
	work, _, expires := release_fixture()!
	defer { os.rmdir_all(work) or {} }
	path := work + '/repository/manifests/app-aarch64-1.0.0.json'
	valid := json2.decode[Package](os.read_file(path)!)!
	for dependencies in [[Dependency{ id: 'missing' }], [Dependency{ id: 'assets', minimum: '2.0.0' }]] {
		os.write_file(path, json2.encode(Package{ ...valid, dependencies: dependencies }))!
		// A working newer app must not cover up this exact advertised version.
		os.write_file(work + '/repository/manifests/app-aarch64-2.0.0.json', json2.encode(Package{ ...valid, version: '2.0.0' }))!
		mut refused := false
		publish_release(work + '/repository', 'fixture', work + '/seed', 1, expires, work + '/broken') or {
			refused = err.msg().contains('dependency closure failed for app/aarch64/1.0.0')
		}
		assert refused && !os.exists(work + '/broken') && !os.exists(work + '/repository/.publisher/history.json')
	}
	os.write_file(path, json2.encode(valid))!
	assets_path := work + '/repository/manifests/assets-all-1.0.0.json'
	assets := json2.decode[Package](os.read_file(assets_path)!)!
	os.write_file(assets_path, json2.encode(Package{ ...assets, architecture: 'aarch64' }))!
	mut refused := false
	publish_release(work + '/repository', 'fixture', work + '/seed', 1, expires, work + '/wrong-arch') or {
		refused = err.msg().contains('on x86_64')
	}
	assert refused && !os.exists(work + '/wrong-arch')
}

fn release_stop_reserved(phase string, _ string) ! {
	if phase == 'reserved' { C._exit(77) }
}

fn release_corrupt_copy(phase string, path string) ! {
	if phase == 'copied' {
		mut bytes := os.read_bytes(path)!
		bytes[0] ^= 1
		os.write_file_array(path, bytes)!
	}
}

fn release_no_space(_ string) !u64 { return 0 }

fn release_race_destination(phase string, path string) ! {
	if phase == 'copied' { assert os.stat(os.dir(os.dir(path)))!.mode & 0o777 == 0o700 }
	if phase == 'reserved' {
		assert os.stat(path)!.mode & 0o777 == 0o755
		assert os.is_file(os.dir(path) + '/repository/.publisher/history.json')
		os.mkdir(os.dir(path) + '/raced')!
	}
}

fn test_release_failed_copy_and_space_check_do_not_reserve_or_publish() {
	work, _, expires := release_fixture()!
	defer { os.rmdir_all(work) or {} }
	for options in [ReleaseOptions{ checkpoint: release_corrupt_copy }, ReleaseOptions{ available_space: release_no_space }] {
		mut refused := false
		release_locked(work + '/repository', 'fixture', work + '/seed', 1, expires, work + '/failed', options) or {
			refused = err.msg().contains('changed while copying') || err.msg().contains('insufficient disk space')
		}
		assert refused && !os.exists(work + '/failed') && !os.exists(work + '/repository/.publisher/history.json')
		assert os.ls(work)!.all(!it.starts_with('.vinix-release-'))
	}
	os.chmod(work + '/seed', 0o644)!
	mut refused := false
	publish_release(work + '/repository', 'fixture', work + '/seed', 1, expires, work + '/unsafe-seed') or {
		refused = err.msg().contains('signing seed must be a private ordinary file')
	}
	assert refused && !os.exists(work + '/unsafe-seed')
}

fn test_release_raced_publication_and_corrupt_history_fail_closed() {
	work, _, expires := release_fixture()!
	defer { os.rmdir_all(work) or {} }
	guard := publisher_lock(work + '/repository')!
	mut refused := false
	release_locked(work + '/repository', 'fixture', work + '/seed', 1, expires, work + '/raced', ReleaseOptions{ checkpoint: release_race_destination }) or {
		refused = err.msg().contains('without replacing')
	}
	guard.release()
	assert refused && os.ls(work + '/raced')!.len == 0
	assert os.ls(work)!.all(!it.starts_with('.vinix-release-'))
	assert release_history(work + '/repository')!.repositories[0].sequence == 1
	path := work + '/repository/.publisher/history.json'
	history := os.read_file(path)!
	for invalid in ['{broken history', 'null', '{"format":1}', '{"format":1,"indexes":null}',
		history.replace('"sequence":1', '"sequence":0,"sequ\\u0065nce":1'),
		history.replace('"indexes":', '"indexes":[],"indexes":')] {
		os.write_file(path, invalid)!
		refused = false
		publish_release(work + '/repository', 'fixture', work + '/seed', 2, expires, work + '/broken-history') or {
			refused = err.msg().contains('invalid publisher release history:')
		}
		assert refused && !os.exists(work + '/broken-history')
		assert os.read_file(path)! == invalid && os.ls(work)!.all(!it.starts_with('.vinix-release-'))
	}
	os.write_file(path, history)!
	publish_release(work + '/repository', 'fixture', work + '/seed', 1, expires, work + '/retry')!
}

fn test_release_refuses_an_accidentally_packaged_signing_seed() {
	work, _, expires := release_fixture()!
	defer { os.rmdir_all(work) or {} }
	os.write_file(work + '/source/bin/app', os.read_file(work + '/seed')!)!
	os.write_file(work + '/manifest.json', json2.encode(Package{ id: 'secret', name: 'Accidental secret',
		version: '1.0.0', architecture: 'all', kind: 'data', license: 'MIT' }))!
	pack(work + '/manifest.json', work + '/source', work + '/repository')!
	mut refused := false
	publish_release(work + '/repository', 'fixture', work + '/seed', 1, expires, work + '/unsafe') or {
		refused = err.msg().contains('include the signing seed as a payload')
	}
	assert refused && !os.exists(work + '/unsafe') && !os.exists(work + '/repository/.publisher/history.json')
}

fn test_release_interruption_preserves_sequence_and_exact_retry_without_fork_or_rollback() {
	work, _, expires := release_fixture()!
	defer { os.rmdir_all(work) or {} }
	pid := C.fork()
	assert pid >= 0
	if pid == 0 {
		guard := publisher_lock(work + '/repository') or { C._exit(78); return }
		_ = guard
		release_locked(work + '/repository', 'fixture', work + '/seed', 2, expires, work + '/release', ReleaseOptions{ checkpoint: release_stop_reserved }) or { C._exit(79) }
		C._exit(80)
	}
	mut status := 0
	assert C.waitpid(pid, &status, 0) == pid && status == 77 << 8
	assert !os.exists(work + '/release') && os.ls(work)!.filter(it.starts_with('.vinix-release-')).len == 1
	assert release_history(work + '/repository')!.repositories[0].sequence == 2
	for sequence in [u64(1), 2] {
		mut refused := false
		publish_release(work + '/repository', 'fixture', work + '/seed', sequence, expires + 1, work + '/fork') or {
			refused = err.msg().contains('rollback or sequence equivocation')
		}
		assert refused && !os.exists(work + '/fork')
	}
	info := publish_release(work + '/repository', 'fixture', work + '/seed', 2, expires, work + '/release')!
	assert info.sequence == 2 && os.ls(work)!.filter(it.starts_with('.vinix-release-')).len == 1
	mut refused := false
	publish_release(work + '/repository', 'fixture', work + '/seed', 3, expires, work + '/release') or { refused = err.msg().contains('must be new') }
	assert refused && release_history(work + '/repository')!.repositories[0].sequence == 2
	guard := publisher_lock(work + '/repository')!
	refused = false
	publish_release(work + '/repository', 'fixture', work + '/seed', 3, expires, work + '/busy') or { refused = err.msg().contains('another publisher release') }
	guard.release()
	assert refused && !os.exists(work + '/busy')
	publish_release(work + '/repository', 'fixture', work + '/seed', 3, expires, work + '/third')!
	assert release_history(work + '/repository')!.repositories[0].sequence == 3
}
