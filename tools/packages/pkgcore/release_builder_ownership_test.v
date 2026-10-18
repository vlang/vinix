// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time

#include <sys/resource.h>
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int
fn C.setenv(&char, &char, int) int
struct ReleaseOwnerLimit { current u64 maximum u64 }

$if track_heap ? {
#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32
}

fn release_owner_close(mut info ReleaseInfo) {
	$if !release_owner_baseline ? { info.close(); info.close() }
}

// Structural payloads are signed and copied, never executed. The seed, expiry
// and declarations are fixed so independent builds have identical signed bytes.
fn release_owner_fixture() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-release-owner-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(work + '/repository', mode: 0o700)!; os.mkdir_all(work + '/source')!; os.mkdir(work + '/output')!
	os.write_file(work + '/seed', '00'.repeat(32) + '\n')!; os.chmod(work + '/seed', 0o600)!
	for architecture in ['aarch64', 'x86_64']! {
		os.write_file(work + '/source/data', 'application ' + architecture)!
		os.write_file(work + '/manifest.json', publisher_json(Package{ id: 'app', name: 'Application', version: '1.0.0',
			architecture: architecture, kind: 'native', entrypoint: 'data', license: 'MIT', permissions: ['files'],
			associations: ['text/plain'], dependencies: [Dependency{ id: 'assets', before: '2.0.0' }] }))!
		os.chmod(work + '/source/data', 0o755)!
		mut p := pack(work + '/manifest.json', work + '/source', work + '/repository')!; p.close()
	}
	os.write_file(work + '/source/data', 'licensed firmware bytes')!
	os.write_file(work + '/manifest.json', publisher_json(Package{ id: 'assets', name: 'Explicit licensed firmware',
		version: '1.0.0', architecture: 'all', kind: 'data', license: 'Vendor-EULA', proprietary: true, firmware: true }))!
	mut p := pack(work + '/manifest.json', work + '/source', work + '/repository')!; p.close()
	os.cp(work + '/repository/manifests/app-aarch64-1.0.0.json', work + '/original-manifest.json')!
	return work
}

fn release_owner_selected(mode string) bool {
	if os.args.len == 1 { return true }
	assert os.args.len == 3 && os.args[1] == 'case'
	return os.args[2] == mode
}

fn release_owner_descriptors() int {
	mut count := 0; for fd in 0 .. 256 { if C.fcntl(fd, C.F_GETFD, 0) >= 0 { count++ } }; return count
}

fn release_owner_write(path string, text string) ! {
	fd := C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_TRUNC | C.O_CLOEXEC | C.O_NOFOLLOW, 0o600)
	if fd < 0 { return error('cannot write release owner fixture') }
	defer { C.close(fd) }; assert C.write(fd, text.str, usize(text.len)) == text.len
}

fn release_owner_checkpoint(phase string, input string) ! {
	mode := os.getenv('VINIX_RELEASE_OWNER_MODE'); defer { unsafe { mode.free() } }
	if phase == 'created' { assert C.setenv(c'VINIX_RELEASE_OWNER_STAGE', input.str, 1) == 0 }
	if mode == phase { return error('injected release checkpoint refusal') }
	if phase == 'seed' && mode == 'captured-seed' {
		saved := input + '.saved'; defer { unsafe { saved.free() } }
		assert C.rename(input.str, saved.str) == 0
		release_owner_write(input, '1111111111111111111111111111111111111111111111111111111111111111\n')!
	}
	if phase == 'created' && mode.starts_with('root-replaced') {
		work := os.getenv('VINIX_RELEASE_OWNER_WORK'); saved := work + '/saved-stage'; keep := input + '/keep'
		defer { unsafe { work.free(); saved.free(); keep.free() } }
		assert C.rename(input.str, saved.str) == 0; assert C.mkdir(input.str, 0o700) == 0
		release_owner_write(keep, 'preserved replacement')!
		if mode == 'root-replaced-refused' { return error('injected release checkpoint refusal') }
	}
	if phase == 'staged' && mode == 'history-write' {
		work := os.getenv('VINIX_RELEASE_OWNER_WORK'); path := work + '/repository/.publisher/history.json'; keep := path + '/keep'
		defer { unsafe { work.free(); path.free(); keep.free() } }; assert C.mkdir(path.str, 0o700) == 0; release_owner_write(keep, 'preserved history replacement')!
	}
	if phase == 'staged' && mode in ['late-index', 'late-signature', 'extra-entry']! {
		path := input + match mode { 'late-index' { '/index.json' } 'late-signature' { '/index.sig' } else { '/extra' } }
		defer { unsafe { path.free() } }; release_owner_write(path, 'changed')!
	}
	if phase == 'copied' && mode == 'late-object' { release_owner_write(input, 'changed')! }
	if phase == 'reserved' && mode == 'reserved-index' {
		path := input + '/index.json'; defer { unsafe { path.free() } }; release_owner_write(path, '{}')!
	}
	if phase == 'reserved' && mode == 'raced-target' {
		path := os.getenv('VINIX_RELEASE_OWNER_TARGET'); keep := path + '/keep'
		defer { unsafe { path.free(); keep.free() } }; assert C.mkdir(path.str, 0o700) == 0; release_owner_write(keep, 'preserved replacement')!
	}
}

fn release_owner_space(_ string) !u64 {
	mode := os.getenv('VINIX_RELEASE_OWNER_MODE'); defer { unsafe { mode.free() } }
	if mode == 'space-error' { return error('injected release space refusal') }
	return if mode == 'no-space' { u64(0) } else { ~u64(0) }
}

fn release_owner_call(workspace string, id string, seed string, sequence u64, expires i64, target string) !ReleaseInfo {
	// Same workspace admission/guard as the public entry point, with only the
	// existing in-process checkpoint and space hooks supplied to release_locked.
	root := publisher_workspace(workspace, false)!; defer { unsafe { root.free() } }
	guard := publisher_lock(root)!; defer { guard.release() }
	return release_locked(root, id, seed, sequence, expires, target, ReleaseOptions{ checkpoint: release_owner_checkpoint, available_space: release_owner_space })
}

fn release_owner_attempt(mode string, work string, target string) {
	workspace := work + '/repository'; suffix := if mode == 'nul-seed' { '/seed\x00ignored' } else { '/seed' }; seed := work + suffix
	defer { unsafe { workspace.free(); seed.free() } }
	if mode == 'in-place' { publish(workspace, 'fixture', seed, 1, 2100000000) or { panic(err) }; return }
	id := if mode == 'invalid-id' { 'Invalid Repository' } else { 'fixture' }
	sequence := if mode == 'zero-sequence' { u64(0) } else { u64(1) }
	expires := if mode == 'expired' { i64(1) } else if mode == 'equivocation' { i64(2100000001) } else { i64(2100000000) }
	if result := release_owner_call(workspace, id, seed, sequence, expires, target) {
		mut info := result
		assert info.repository == 'fixture' && info.sequence == 1 && info.package_count == 3 && info.object_count == 3
		release_owner_close(mut info)
		assert mode in ['complete', 'nested', 'captured-seed']!
	} else {
		message := err.msg(); defer { unsafe { message.free(); err.free() } }
		assert mode !in ['complete', 'nested', 'captured-seed']!
		expected := match mode {
			'invalid-seed' { 'invalid hex' } 'unsafe-seed', 'missing-seed', 'alias-seed' { 'signing seed must be' } 'nul-seed' { 'valid private-file path' }
			'invalid-id', 'zero-sequence', 'expired' { 'publishing requires' }
			'invalid-manifest' { 'incomplete administration' } 'duplicate-manifest' { 'duplicate package' }
			'missing-object', 'changed-object' { 'payload verification failed' }
			'bad-history' { 'invalid publisher release history' } 'equivocation', 'rollback' { 'rollback or sequence equivocation' }
			'unresolved' { 'dependency closure' } 'seed-payload' { 'include the signing seed' }
			'no-space' { 'insufficient disk space' } 'space-error' { 'injected release space' }
			'seed', 'created', 'copied', 'staged', 'reserved' { 'injected release checkpoint' }
			'late-index', 'late-signature', 'extra-entry' { 'before sequence reservation' }
			'reserved-index' { 'after sequence reservation' } 'late-object' { 'payload changed while copying' }
			'history-write' { 'reserve publisher sequence' } 'raced-target' { 'without replacing' }
			'occupied' { 'destination must be new' } 'root-replaced', 'root-replaced-refused' { 'cleanup refused' } else { panic(mode) }
		}
		assert message.contains(expected), message
	}
}

fn release_owner_remove(path string) ! {
	if os.is_dir(path) && !os.is_link(path) { os.rmdir_all(path)! }
	else if os.exists(path) || os.is_link(path) { os.rm(path)! }
}

fn release_owner_reset(work string) ! {
	for name in ['output', 'saved-stage', 'repository/.publisher/history.json', 'repository/manifests/duplicate.json', 'repository/index.json', 'repository/index.sig']! { release_owner_remove(work + '/' + name)! }
	os.mkdir(work + '/output')!
	if os.is_link(work + '/seed') { os.rm(work + '/seed')! }
	os.write_file(work + '/seed', '00'.repeat(32) + '\n')!; os.chmod(work + '/seed', 0o600)!
	if os.exists(work + '/seed.saved') { os.rm(work + '/seed.saved')! }
	os.cp(work + '/original-manifest.json', work + '/repository/manifests/app-aarch64-1.0.0.json')!
	hash := index_digest('application aarch64'); path := work + '/repository/objects/' + hash
	os.write_file(path, 'application aarch64')!
}

fn release_owner_prepare(mode string, work string, target string, history string) ! {
	manifest := work + '/repository/manifests/app-aarch64-1.0.0.json'; text := os.read_file(manifest)!
	object := work + '/repository/objects/' + index_digest('application aarch64')
	match mode {
		'invalid-seed' { os.write_file(work + '/seed', 'gg'.repeat(32) + '\n')! }
		'unsafe-seed' { os.chmod(work + '/seed', 0o644)! }
		'missing-seed' { os.rm(work + '/seed')! }
		'alias-seed' { os.rename(work + '/seed', work + '/seed.saved')!; os.symlink(work + '/seed.saved', work + '/seed')! }
		'invalid-manifest' { os.write_file(manifest, '{')! }
		'duplicate-manifest' { os.cp(manifest, work + '/repository/manifests/duplicate.json')! }
		'missing-object' { os.rm(object)! }
		'changed-object' { os.write_file(object, 'Application aarch64')! }
		'bad-history' { os.write_file(work + '/repository/.publisher/history.json', '{')! }
		'equivocation' { os.write_file(work + '/repository/.publisher/history.json', history)! }
		'rollback' { os.write_file(work + '/repository/.publisher/history.json', history.replace('"sequence":1', '"sequence":2'))! }
		'unresolved' { os.write_file(manifest, text.replace('"before":"2.0.0"', '"minimum":"2.0.0","before":"3.0.0"').replace('"minimum":"",', ''))! }
		'seed-payload' {
			mut p := decode_manifest(text, true)!; defer { p.close() }
			seed_text := os.read_file(work + '/seed')!; hash := index_digest(seed_text)
			os.write_file(work + '/repository/objects/' + hash, seed_text)!
			os.write_file(manifest, publisher_json(Package{ ...p, files: [Payload{ ...p.files[0], sha256: hash, bytes: u64(seed_text.len) }] }))!
		}
		'occupied' { os.write_file(target, 'preserved replacement')! }
		else {}
	}
}

fn test_complete_release_builder_retires_signed_publication_and_refusal_storage() {
	defer { for name in ['MODE', 'WORK', 'TARGET', 'STAGE']! { os.unsetenv('VINIX_RELEASE_OWNER_' + name) } }
	for mode in ['complete', 'nested', 'in-place', 'invalid-seed', 'unsafe-seed', 'missing-seed', 'nul-seed', 'alias-seed',
		'invalid-id', 'zero-sequence', 'expired', 'invalid-manifest', 'duplicate-manifest', 'missing-object', 'changed-object',
		'bad-history', 'equivocation', 'rollback', 'unresolved', 'seed-payload', 'no-space', 'space-error',
		'seed', 'created', 'copied', 'staged', 'reserved', 'late-index', 'late-signature', 'late-object', 'extra-entry', 'reserved-index',
		'history-write', 'raced-target', 'occupied', 'root-replaced', 'root-replaced-refused', 'captured-seed']! {
		if !release_owner_selected(mode) { continue }
		work := release_owner_fixture()!; defer { os.rmdir_all(work) or {} }
		workspace := work + '/repository'; seed := work + '/seed'; target := work + if mode == 'nested' { '/output/new/parent/release' } else { '/output/release' }
		mut warm := publish_release(workspace, 'fixture', seed, 1, 2100000000, target)!
		golden := os.read_file(target + '/index.json')!; signature := os.read_file(target + '/index.sig')!; history := os.read_file(workspace + '/.publisher/history.json')!
		assert index_digest(golden) == '1cfdd899be97f03a74ec4d2176acf68e2b4e2d8ef541a440bcc82a38272dc112'
		release_owner_close(mut warm); println('RELEASE OWNER golden=' + index_digest(golden))
		os.setenv('VINIX_RELEASE_OWNER_MODE', mode, true); os.setenv('VINIX_RELEASE_OWNER_WORK', work, true); os.setenv('VINIX_RELEASE_OWNER_TARGET', target, true)
		mut original := ReleaseOwnerLimit{}; assert C.getrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0
		limited := ReleaseOwnerLimit{ current: 32, maximum: original.maximum }; assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &limited }) == 0
		before := release_owner_descriptors(); mut maximum := u64(0); mut records := u32(0)
		for _ in 0 .. 8 {
			release_owner_reset(work)!; release_owner_prepare(mode, work, target, history)!
			$if track_heap ? { C.vinix_heap_begin() }
			release_owner_attempt(mode, work, target)
			$if track_heap ? { kept := C.vinix_heap_end(); count := C.vinix_heap_count(); if kept > maximum { maximum = kept }; if count > records { records = count } }
			assert release_owner_descriptors() == before
			if mode in ['complete', 'nested', 'captured-seed']! { assert os.read_file(target + '/index.json')! == golden && os.read_file(target + '/index.sig')! == signature }
			else if mode == 'in-place' { assert !os.exists(target) && os.read_file(workspace + '/index.json')! == golden && os.read_file(workspace + '/index.sig')! == signature }
			else if mode == 'occupied' { assert os.read_file(target)! == 'preserved replacement' }
			else if mode == 'raced-target' { assert os.read_file(target + '/keep')! == 'preserved replacement' }
			else { assert !os.exists(target) }
			if mode.starts_with('root-replaced') {
				stage := os.getenv('VINIX_RELEASE_OWNER_STAGE'); assert os.read_file(stage + '/keep')! == 'preserved replacement' && os.is_dir(work + '/saved-stage')
			} else { assert os.ls(work + '/output')!.all(!it.starts_with('.vinix-release-')) }
			if mode == 'history-write' { assert os.read_file(workspace + '/.publisher/history.json/keep')! == 'preserved history replacement' }
			else if mode in ['complete', 'nested', 'captured-seed', 'reserved', 'reserved-index', 'raced-target', 'equivocation', 'rollback']! { assert os.exists(workspace + '/.publisher/history.json') }
			else if mode != 'bad-history' { assert !os.exists(workspace + '/.publisher/history.json') }
		}
		assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0
		$if track_heap ? { println('RELEASE OWNER case=' + mode + ' retained=' + maximum.str() + ' allocations=' + records.str()); $if !release_owner_baseline ? { assert maximum == 0 && records == 0 } }
		release_owner_reset(work)!; os.unsetenv('VINIX_RELEASE_OWNER_MODE')
		mut retry := publish_release(workspace, 'fixture', seed, 1, 2100000000, target)!
		assert os.read_file(target + '/index.json')! == golden && os.read_file(target + '/index.sig')! == signature; release_owner_close(mut retry)
		assert os.read_file(seed)! == '00'.repeat(32) + '\n'
		println('RELEASE OWNER ' + mode + ' exact signed retry, sequence reservation, recovery, seed and descriptors PASS')
	}
}

fn test_release_reply_survives_caller_paths_and_id_and_preserves_published_artifacts() {
	$if !release_owner_baseline ? {
		if !release_owner_selected('complete') { return }
		work := release_owner_fixture()!; defer { os.rmdir_all(work) or {} }
		workspace := work + '/repository'; id := 'fixture'.clone(); seed := work + '/seed'; target := work + '/release'
		mut info := publish_release(workspace, id, seed, 1, 2100000000, target)!
		unsafe { workspace.free(); id.free(); seed.free(); target.free() }
		assert info.repository == 'fixture' && info.sequence == 1 && info.expires == 2100000000
		assert info.public_key == key_public(work + '/seed')! && info.directory == work + '/release'
		assert info.index_sha256 == index_digest(os.read_file(info.directory + '/index.json')!)
		before := os.read_file(work + '/repository/.publisher/history.json')!
		info.close(); info.close(); assert info.repository == '' && info.public_key == '' && info.directory == ''
		assert os.read_file(work + '/repository/.publisher/history.json')! == before && os.is_file(work + '/release/index.sig')
		println('RELEASE OWNER independent idempotently closeable replies preserve signed output, seed and reservation PASS')
	}
}
