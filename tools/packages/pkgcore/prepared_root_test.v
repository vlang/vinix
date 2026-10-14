// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time

#include <sys/resource.h>
fn C.mkfifo(&char, u32) int
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int
struct PreparedRootLimit { current u64 maximum u64 }

fn prepared_work() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-prepared-root-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir(work)!
	return work
}

fn test_prepared_root_capture_preserves_root_separators_flags_and_original_namespace() {
	work := prepared_work()!
	defer { os.rmdir_all(work) or {} }
	os.mkdir(work + '/root')!; os.mkdir(work + '/outside')!
	os.write_file(work + '/root/data', 'original')!
	os.symlink('/data', work + '/root/link')!
	os.write_file(work + '/outside/data', 'external')!
	for path in ['/', '////', work + '/root', work + '/root///'] {
		fd := capture_prepared_root(path, 'test')!
		assert C.fcntl(fd, C.F_GETFD, 0) & C.FD_CLOEXEC != 0
		assert C.fcntl(fd, C.F_GETFL, 0) & C.O_NONBLOCK != 0
		C.close(fd)
	}
	fd := capture_prepared_root(work + '/root', 'test')!
	defer { C.close(fd) }
	os.rename(work + '/root', work + '/saved')!
	os.symlink(work + '/outside', work + '/root')!
	node := import_node(fd, 'link')!
	defer { C.close(node.fd) }
	mut bytes := [8]u8{}
	assert C.read(node.fd, &bytes[0], 8) == 8
	assert bytes[..].bytestr() == 'original'
	assert os.read_file(work + '/outside/data')! == 'external'
	// Parent aliases retain normal semantics; capture protects the actual leaf.
	os.symlink(work, work + '/parent-alias')!
	parent := capture_prepared_root(work + '/parent-alias/saved///', 'test')!
	C.close(parent)
}

fn prepared_call(kind string, recipe string, root string, destination string) ! {
	match kind {
		'root' { pack_root(recipe, root, destination)! }
		'catalog' { pack_catalog(recipe, root, destination)! }
		'native' { native_catalog('1.0.0', root, destination)! }
		'sqlite' { sqlite_catalog('3.46.1', '1.0.0', root, destination)! }
		'ffmpeg' { ffmpeg_catalog('1.0.0', root, destination)! }
		else { return error('unknown prepared root fixture') }
	}
}

fn test_prepared_root_all_publishers_refuse_unsafe_roots_before_creating_output_parents() {
	work := prepared_work()!
	defer { os.rmdir_all(work) or {} }
	os.mkdir(work + '/root')!
	os.symlink(work + '/root', work + '/alias')!
	os.write_file(work + '/file', 'preserved')!
	os.chmod(work + '/file', 0o640)!
	assert C.mkfifo((work + '/fifo').str, 0o600) == 0
	p := Package{ id: 'data', version: '1.0.0', architecture: 'all', kind: 'data', name: 'Data', license: 'MIT',
		files: [Payload{ path: 'data', bytes: 1, sha256: '0'.repeat(64) }] }
	recipe := RootRecipe{ manifest: p, entries: [RootEntry{ source: 'data', path: 'data' }] }
	os.write_file(work + '/root.json', json2.encode(recipe))!
	os.write_file(work + '/catalog.json', json2.encode(CatalogRecipe{ format: 1,
		architectures: ['aarch64', 'x86_64'], packages: [CatalogImport{ source: 'shared', recipe: recipe }] }))!
	for kind in ['root', 'catalog', 'native', 'sqlite', 'ffmpeg'] {
		for index, path in ['', work + '/root\x00ignored', work + '/alias', work + '/alias///',
			work + '/missing', work + '/file', work + '/fifo'] {
			destination := work + '/' + kind + '-' + index.str() + '/workspace'
			input := work + '/' + if kind == 'catalog' { 'catalog.json' } else { 'root.json' }
			mut refused := false
			prepared_call(kind, input, path, destination) or { refused = err.msg().contains('prepared root') }
			assert refused && !os.exists(os.dir(destination)), kind + '/' + index.str()
		}
	}
	assert os.read_file(work + '/file')! == 'preserved' && os.lstat(work + '/file')!.mode & 0o777 == 0o640
	assert os.ls(work + '/root')!.len == 0
}

fn test_prepared_root_success_and_admission_failures_retire_descriptors() {
	work := prepared_work()!
	defer { os.rmdir_all(work) or {} }
	os.mkdir(work + '/root')!
	os.symlink(work + '/root', work + '/alias')!
	os.write_file(work + '/file', 'preserved')!
	mut original := PreparedRootLimit{}
	assert C.getrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0
	limit := PreparedRootLimit{ current: 32, maximum: original.maximum }
	assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&limit)) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0 }
	for _ in 0 .. 64 {
		fd := capture_prepared_root(work + '/root///', 'test')!
		C.close(fd)
		for path in ['', work + '/root\x00ignored', work + '/alias///', work + '/file'] {
			mut refused := false
			capture_prepared_root(path, 'test') or {
				refused = true
				message := err.msg(); unsafe { message.free(); err.free() }
			}
			assert refused
		}
	}
}
