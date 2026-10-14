// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import json2
import os
import time

#include <sys/resource.h>
fn C.mkfifo(&char, u32) int
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int
struct SeedLimit { current u64 maximum u64 }

fn seed_workspace() !(string, string, i64) {
	work := seed_work()!
	os.mkdir_all(work + '/source')!
	os.mkdir(work + '/repository', mode: 0o700)!
	key := keygen(work + '/seed')!
	os.write_file(work + '/source/data', 'ordinary data')!
	os.write_file(work + '/manifest.json', json2.encode(Package{ id: 'data', name: 'Data', version: '1.0.0',
		architecture: 'all', kind: 'data', license: 'MIT' }))!
	pack(work + '/manifest.json', work + '/source', work + '/repository')!
	return work, key, time.now().unix() + 3600
}

fn seed_work() !string {
	path := os.real_path(os.temp_dir()) + '/vinix-seed-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir(path, mode: 0o700)!
	return path
}

fn seed_replace(phase string, path string) ! {
	if phase != os.file_name(os.dir(path)) { return }
	kind := os.file_name(path)
	if kind == 'grow' {
		mut file := os.open_file(path, 'a', 0o600)!
		file.write_string('0')!; file.close()
	} else if kind == 'shrink' {
		mut file := os.open_file(path, 'w', 0o600)!; file.close()
	} else if kind == 'public' { os.chmod(path, 0o644)!
	} else {
		os.rename(path, path + '.saved')!
		if kind == 'alias' { os.symlink(path + '.saved', path)!
		} else if kind == 'fifo' { assert C.mkfifo(path.str, 0o600) == 0
		} else if kind == 'directory' { os.mkdir(path)!
		} else { os.write_file(path, 'b'.repeat(64))!; os.chmod(path, 0o600)! }
	}
}

fn test_signing_seed_private_bounded_capture_and_digest_from_exact_bytes() {
	work := seed_work()!
	defer { os.rmdir_all(work) or {} }
	path := work + '/seed'
	for text in ['aB'.repeat(32), 'aB'.repeat(32) + '\n', ' \t' + 'aB'.repeat(32) + '\r\n', ' '.repeat(64) + 'aB'.repeat(32)] {
		os.write_file(path, text)!; os.chmod(path, 0o600)!
		seed := read_signing_seed(path, SigningSeedOptions{})!
		assert seed.bytes == []u8{len: 32, init: 0xab} && seed.file_sha256 == sha256.hexhash(text)
		seed.close()
	}
	for text in ['', '0'.repeat(63), '0'.repeat(66), 'g'.repeat(64), '0'.repeat(63) + '\x00',
		'0'.repeat(64) + ' '.repeat(65)] {
		os.write_file(path, text)!; os.chmod(path, 0o600)!
		mut refused := false
		read_signing_seed(path, SigningSeedOptions{}) or { refused = true }
		assert refused
	}
	os.write_file(path, '0'.repeat(64))!; os.chmod(path, 0o600)!
	for invalid in ['', path + '\x00ignored'] {
		mut refused := false
		read_signing_seed(invalid, SigningSeedOptions{}) or { refused = true }
		assert refused
	}
	for phase in ['sized', 'read'] {
		os.mkdir(work + '/' + phase)!
		for kind in ['grow', 'shrink', 'public', 'alias', 'fifo', 'directory', 'ordinary'] {
			target := work + '/' + phase + '/' + kind
			os.write_file(target, 'a'.repeat(64))!; os.chmod(target, 0o600)!
			mut refused := false
			read_signing_seed(target, SigningSeedOptions{ checkpoint: seed_replace }) or { refused = err.msg().contains('changed while reading') }
			assert refused, phase + '/' + kind
		}
	}
}

fn seed_after_capture(phase string, path string) ! {
	if phase != 'seed' { return }
	os.rename(path, path + '.saved')!
	os.write_file(path, 'b'.repeat(64) + '\n')!; os.chmod(path, 0o600)!
}

fn test_release_secret_exclusion_uses_the_same_seed_capture_as_signing() {
	work, key, expires := seed_workspace()!
	defer { os.rmdir_all(work) or {} }
	seed_text := os.read_file(work + '/seed')!
	mut invalid_path := false
	publish_release(work + '/repository', 'fixture', work + '/seed\x00ignored', 1, expires, work + '/nul-path') or {
		invalid_path = err.msg().contains('valid private-file path')
	}
	assert invalid_path && !os.exists(work + '/nul-path') && !os.exists(work + '/repository/.publisher/history.json')
	os.write_file(work + '/source/data', seed_text)!
	os.write_file(work + '/manifest.json', json2.encode(Package{ id: 'secret', name: 'Accidental seed', version: '1.0.0',
		architecture: 'all', kind: 'data', license: 'MIT' }))!
	pack(work + '/manifest.json', work + '/source', work + '/repository')!
	mut refused := false
	release_locked(work + '/repository', 'fixture', work + '/seed', 1, expires, work + '/release', ReleaseOptions{ checkpoint: seed_after_capture }) or {
		refused = err.msg().contains('include the signing seed as a payload')
	}
	assert refused && !os.exists(work + '/release') && !os.exists(work + '/repository/.publisher/history.json')
	assert os.ls(work)!.all(!it.starts_with('.vinix-release-'))
	os.rm(work + '/seed')!; os.rename(work + '/seed.saved', work + '/seed')!
	os.rm(work + '/repository/manifests/secret-all-1.0.0.json')!
	info := publish_release(work + '/repository', 'fixture', work + '/seed', 1, expires, work + '/retry')!
	assert info.public_key == key
}

fn test_signing_seed_repeated_success_and_refusal_retire_descriptors() {
	work := seed_work()!
	defer { os.rmdir_all(work) or {} }
	path := work + '/seed'
	mut original := SeedLimit{}
	assert C.getrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0
	limited := SeedLimit{ current: 32, maximum: original.maximum }
	assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&limited)) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0 }
	for _ in 0 .. 128 {
		os.write_file(path, 'a'.repeat(64))!; os.chmod(path, 0o600)!
		seed := read_signing_seed(path, SigningSeedOptions{})!
		assert seed.bytes.len == 32
		seed.close()
		for mode in ['public', 'malformed'] {
			if mode == 'public' { os.chmod(path, 0o644)! } else { os.write_file(path, 'g'.repeat(64))!; os.chmod(path, 0o600)! }
			mut refused := false
			read_signing_seed(path, SigningSeedOptions{}) or { refused = true }
			assert refused
		}
	}
}
