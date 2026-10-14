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
struct PackSourceLimit { current u64 maximum u64 }

fn pack_source_work() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-pack-source-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir(work)!
	return work
}

fn pack_source_manifest(work string) !string {
	path := work + '/manifest.json'
	os.write_file(path, json2.encode(Package{ id: 'fixture', version: '1.0.0', architecture: 'all',
		kind: 'data', name: 'Fixture', license: 'MIT' }))!
	return path
}

fn pack_source_change(phase string, relative string) ! {
	if phase != os.getenv('VINIX_PACK_SOURCE_PHASE') || relative != os.getenv('VINIX_PACK_SOURCE_ENTRY') { return }
	path := os.getenv('VINIX_PACK_SOURCE_PATH')
	mode := os.getenv('VINIX_PACK_SOURCE_CHANGE')
	match mode {
		'grow' { mut file := os.open_append(path)!; file.write_string('extra')!; file.close() }
		'shrink' { os.truncate(path, 0)! }
		'exec' { os.chmod(path, 0o755)! }
		'content' { os.write_file(path, 'external')! }
		else {
			os.rename(path, path + '.saved')!
			match mode {
				'alias' { os.symlink(os.getenv('VINIX_PACK_SOURCE_OUTSIDE'), path)! }
				'fifo' { assert C.mkfifo(path.str, 0o600) == 0 }
				'ordinary' { os.write_file(path, 'external')! }
				'missing' {}
				else { panic('unknown pack source mutation') }
			}
		}
	}
}

fn pack_source_hook(phase string, entry string, path string, outside string, mode string) PackSourceOptions {
	for key, value in {'PHASE': phase, 'ENTRY': entry, 'PATH': path, 'OUTSIDE': outside, 'CHANGE': mode} {
		os.setenv('VINIX_PACK_SOURCE_' + key, value, true)
	}
	return PackSourceOptions{ checkpoint: pack_source_change }
}

fn test_pack_source_root_capture_survives_path_replacement_and_parent_aliases() {
	work := pack_source_work()!
	defer { os.rmdir_all(work) or {} }
	manifest := pack_source_manifest(work)!
	os.mkdir(work + '/source')!; os.mkdir(work + '/outside')!
	os.write_file(work + '/source/data', 'original')!; os.write_file(work + '/outside/data', 'external')!
	options := pack_source_hook('root', work + '/source///', work + '/source', work + '/outside', 'alias')
	p := pack_with(manifest, work + '/source///', work + '/repository', options)!
	assert p.files.len == 1 && p.files[0].sha256 == sha256.hexhash('original') && !p.files[0].executable
	assert os.read_file(work + '/repository/objects/' + p.files[0].sha256)! == 'original'
	assert !os.exists(work + '/repository/objects/' + sha256.hexhash('external'))
	os.symlink(work, work + '/parent')!
	retried := pack(manifest, work + '/parent/source.saved///', work + '/retry')!
	assert p == retried
}

fn test_pack_source_directory_replacement_cannot_redirect_enumeration_or_reads() {
	work := pack_source_work()!
	defer { os.rmdir_all(work) or {} }
	manifest := pack_source_manifest(work)!
	os.mkdir(work + '/outside')!; os.write_file(work + '/outside/data', 'external')!
	for phase in ['opened', 'directory'] {
		root := work + '/' + phase; os.mkdir_all(root + '/source/d')!
		os.write_file(root + '/source/d/data', 'original')!
		options := pack_source_hook(phase, 'd', root + '/source/d', work + '/outside', 'alias')
		mut refused := false
		pack_with(manifest, root + '/source', root + '/repository', options) or { refused = err.msg().contains('source identity') }
		assert refused && !os.exists(root + '/repository/manifests')
		assert !os.exists(root + '/repository/objects/' + sha256.hexhash('external'))
		assert os.read_file(work + '/outside/data')! == 'external'
		os.rm(root + '/source/d')!; os.rename(root + '/source/d.saved', root + '/source/d')!
		p := pack(manifest, root + '/source', root + '/repository')!
		assert p.files[0].sha256 == sha256.hexhash('original')
	}
}

fn test_pack_source_checks_file_identity_size_and_executable_mode_at_each_stage() {
	work := pack_source_work()!
	defer { os.rmdir_all(work) or {} }
	manifest := pack_source_manifest(work)!
	os.write_file(work + '/outside', 'external')!
	os.chmod(work + '/outside', 0o640)!
	for phase in ['opened', 'sized', 'block', 'read', 'hashed', 'copied', 'cached'] {
		for mode in ['alias', 'fifo', 'ordinary', 'missing', 'grow', 'shrink', 'exec'] {
			root := work + '/' + phase + '-' + mode
			os.mkdir_all(root + '/source')!
			path := root + '/source/data'
			os.write_file(path, 'original')!; os.chmod(path, 0o644)!
			if phase == 'cached' { pack(manifest, root + '/source', root + '/repository')! }
			options := pack_source_hook(phase, 'data', path, work + '/outside', mode)
			mut refused := false
			pack_with(manifest, root + '/source', root + '/repository', options) or { refused = true }
			assert refused, phase + '/' + mode
			assert os.exists(root + '/repository/manifests/fixture-all-1.0.0.json') == (phase == 'cached')
			assert !os.exists(root + '/repository/objects/' + sha256.hexhash('external'))
			assert os.read_file(work + '/outside')! == 'external' && os.lstat(work + '/outside')!.mode & 0o777 == 0o640
			os.rm(path) or { assert mode == 'missing' }
			os.write_file(path, 'original')!; os.chmod(path, 0o644)!
			if os.exists(path + '.saved') { os.rm(path + '.saved')! }
			p := pack(manifest, root + '/source', root + '/repository')!
			assert p.files[0].sha256 == sha256.hexhash('original') && !p.files[0].executable
		}
	}
	// A same-size rewrite between hashing and copying must fail digest checking.
	os.mkdir(work + '/content')!; os.write_file(work + '/content/data', 'original')!
	options := pack_source_hook('hashed', 'data', work + '/content/data', work + '/outside', 'content')
	mut refused := false
	pack_with(manifest, work + '/content', work + '/content-repository', options) or { refused = err.msg().contains('changed contents') }
	assert refused && !os.exists(work + '/content-repository/manifests')
}

fn test_pack_source_bounds_empty_directory_work_file_count_and_total_bytes_before_reading() {
	work := pack_source_work()!
	defer { os.rmdir_all(work) or {} }
	assert max_pack_depth == 128 && max_pack_entries == 32768
	mut source := PackSource{}
	source.admit(u64(4) << 30)!
	assert source.bytes == u64(4) << 30
	for bytes in [(u64(4) << 30) + 1, ~u64(0)] {
		mut refused := false; source.admit(bytes) or { refused = true }; assert refused
	}
	source.bytes = u64(64) << 30
	mut refused := false; source.admit(1) or { refused = true }; assert refused
	source.admit(0)!
	source.files = []Payload{len: max_files}
	refused = false; source.admit(0) or { refused = true }; assert refused
	os.mkdir(work + '/source')!; os.mkdir(work + '/source/empty')!
	root := capture_prepared_root(work + '/source', 'test')!
	defer { C.close(root) }
	mut walker := PackSource{ entries: max_pack_entries }
	refused = false; walker.walk(root, '', 0) or { refused = err.msg().contains('entry limit') }; assert refused
}

fn test_pack_source_success_and_failed_walks_retire_descriptors() {
	work := pack_source_work()!
	defer { os.rmdir_all(work) or {} }
	manifest := pack_source_manifest(work)!
	os.mkdir_all(work + '/source/d')!; os.write_file(work + '/source/d/data', 'payload')!
	mut original := PackSourceLimit{}
	assert C.getrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0
	limit := PackSourceLimit{ current: 32, maximum: original.maximum }
	assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&limit)) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0 }
	for _ in 0 .. 64 {
		pack(manifest, work + '/source', work + '/repository')!
		assert C.mkfifo((work + '/source/d/fifo').str, 0o600) == 0
		mut refused := false
		pack(manifest, work + '/source', work + '/repository') or { refused = true }
		assert refused
		os.rm(work + '/source/d/fifo')!
	}
}
