// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import net.unix
import os
import time

#include <sys/wait.h>
#include <sys/resource.h>
fn C.fork() int
fn C.waitpid(int, &int, int) int
fn C._exit(int)
fn C.alarm(u32) u32
fn C.mkfifo(&char, u32) int
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int

struct MetadataLimit { current u64 maximum u64 }

fn metadata_work() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-metadata-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir(work)!
	return work
}

fn metadata_denied(path string) {
	// A regression to blocking FIFO opens must fail instead of stalling vtest.
	child := C.fork()
	assert child >= 0
	if child == 0 {
		C.alarm(2)
		read_metadata(path) or {
			if err.msg().contains('bounded regular file') { C._exit(0) }
			C._exit(43)
		}
		C._exit(42)
	}
	mut status := 0
	assert C.waitpid(child, &status, 0) == child
	assert status == 0, '${path}: expected prompt metadata refusal, wait status ${status}'
}

fn test_metadata_accepts_owned_exact_bytes_empty_files_and_the_inclusive_limit() {
	work := metadata_work()!
	defer { os.rmdir_all(work) or {} }
	path := work + '/metadata with spaces 日本語'
	for text in ['', 'ordinary metadata', 'binary\x00content', 'x'.repeat(max_metadata)] {
		os.write_file(path, text)!
		result := read_metadata(path)!
		assert result == text
		os.write_file(path, 'replacement')!
		assert result == text // returned text owns its bytes
		unsafe { result.free() }
	}
	mut file := os.open_file(path, 'w', 0o600)!
	file.seek(max_metadata, .start)!; file.write_string('x')!; file.close()
	metadata_denied(path)
}

fn test_metadata_refuses_special_missing_and_leaf_alias_paths_without_changing_them() {
	work := metadata_work()!
	defer { os.rmdir_all(work) or {} }
	os.mkdir(work + '/directory')!
	os.write_file(work + '/ordinary', 'preserved')!
	os.chmod(work + '/ordinary', 0o600)!
	os.symlink(work + '/ordinary', work + '/alias')!
	os.symlink(work + '/missing', work + '/dangling')!
	assert C.mkfifo((work + '/fifo').str, 0o600) == 0
	mut socket := unix.listen_stream(work + '/socket', unix.ListenOptions{})!
	defer { socket.close() or {} }
	for path in [work + '/directory', work + '/missing', work + '/alias', work + '/dangling',
		work + '/fifo', work + '/socket', work + '/ordinary\x00ignored', '/dev/null'] { metadata_denied(path) }
	assert os.read_file(work + '/ordinary')! == 'preserved'
	assert os.lstat(work + '/ordinary')!.mode & 0o777 == 0o600
	assert os.lstat(work + '/fifo')!.mode & 0o170000 == 0o010000
	assert os.readlink(work + '/alias')! == work + '/ordinary'
}

fn metadata_replace_path(phase string, path string) ! {
	if phase != os.file_name(os.dir(path)) { return }
	os.rename(path, path + '.saved')!
	match os.file_name(path) {
		'fifo' { if C.mkfifo(path.str, 0o600) != 0 { return error('cannot create metadata FIFO fixture') } }
		'symlink' { os.symlink(path + '.outside', path)! }
		'directory' { os.mkdir(path)! }
		'regular' { os.write_file(path, 'new pathname contents')! }
		'missing' {}
		else { return error('unknown metadata replacement fixture') }
	}
}

fn test_metadata_path_replacement_retains_the_opened_snapshot_before_and_after_sizing() {
	work := metadata_work()!
	defer { os.rmdir_all(work) or {} }
	for phase in ['opened', 'sized'] {
		os.mkdir(work + '/' + phase)!
		for kind in ['fifo', 'symlink', 'directory', 'regular', 'missing'] {
			path := work + '/' + phase + '/' + kind
			os.write_file(path, 'captured snapshot')!
			os.write_file(path + '.outside', 'never follow this replacement')!
			os.chmod(path + '.outside', 0o600)!
			assert read_metadata_with(path, MetadataReadOptions{ checkpoint: metadata_replace_path })! == 'captured snapshot'
			assert os.read_file(path + '.saved')! == 'captured snapshot'
			assert os.read_file(path + '.outside')! == 'never follow this replacement'
			assert os.lstat(path + '.outside')!.mode & 0o777 == 0o600
		}
	}
}

fn metadata_change_size(phase string, path string) ! {
	if phase != os.file_name(os.dir(path)) { return }
	match os.file_name(path) {
		'grow' { mut file := os.open_append(path)!; defer { file.close() }; file.write_string('appended')! }
		'huge' {
			mut file := os.open_file(path, 'w', 0o600)!
			defer { file.close() }
			file.seek(i64(max_metadata) * 32, .start)!; file.write_string('x')!
		}
		'shrink' { os.write_file(path, '')! }
		else { return error('unknown metadata size fixture') }
	}
}

fn test_metadata_rejects_in_place_growth_shrinkage_and_changes_after_eof_with_restored_retry() {
	work := metadata_work()!
	defer { os.rmdir_all(work) or {} }
	for phase in ['sized', 'read'] {
		os.mkdir(work + '/' + phase)!
		for kind in ['grow', 'huge', 'shrink'] {
			path := work + '/' + phase + '/' + kind
			os.write_file(path, '{}')!
			mut refused := false
			read_metadata_with(path, MetadataReadOptions{ checkpoint: metadata_change_size }) or {
				refused = err.msg().contains('metadata changed size while reading')
			}
			assert refused, phase + '/' + kind
			if kind == 'huge' { assert os.file_size(path) == u64(max_metadata) * 32 + 1 }
			os.write_file(path, '{}')!
			assert read_metadata(path)! == '{}'
		}
	}
}

fn metadata_checkpoint_error(phase string, path string) ! {
	if phase == os.file_name(path) { return error('injected metadata read failure') }
}

fn test_metadata_success_refusal_and_interrupted_reads_release_descriptors() {
	work := metadata_work()!
	defer { os.rmdir_all(work) or {} }
	for name in ['opened', 'sized', 'read', 'valid'] { os.write_file(work + '/' + name, '{}')! }
	assert C.mkfifo((work + '/fifo').str, 0o600) == 0
	mut original := MetadataLimit{}
	assert C.getrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0
	limited := MetadataLimit{ current: 32, maximum: original.maximum }
	assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&limited)) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0 }
	for _ in 0 .. 128 {
		result := read_metadata(work + '/valid')!
		assert result == '{}'
		unsafe { result.free() }
		for name in ['opened', 'sized', 'read', 'fifo'] {
			mut refused := false
			read_metadata_with(work + '/' + name, MetadataReadOptions{ checkpoint: metadata_checkpoint_error }) or {
				refused = err.msg().contains('injected metadata read failure') || err.msg().contains('bounded regular file')
				message := err.msg()
				unsafe { message.free(); err.free() }
			}
			assert refused
		}
	}
}
