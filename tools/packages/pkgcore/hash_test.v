// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
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

struct HashLimit { current u64 maximum u64 }

fn hash_work() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-hash-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir(work)!
	return work
}

fn test_hash_exact_bytes_boundaries_and_owned_results() {
	work := hash_work()!
	defer { os.rmdir_all(work) or {} }
	path := work + '/payload with spaces 日本語'
	for text in ['', 'binary\x00content', 'x'.repeat(65535), 'y'.repeat(65536), 'z'.repeat(65537), 'a'.repeat(140000)] {
		os.write_file(path, text)!
		os.chmod(path, 0o600)!
		digest := hash_file(path)!
		assert digest == sha256.hexhash(text)
		payload := Payload{ bytes: u64(text.len), sha256: digest }
		assert verified_file(path, payload)
		assert !verified_file(path, Payload{ ...payload, bytes: payload.bytes + 1 })
		assert !verified_file(path, Payload{ ...payload, bytes: ~u64(0) })
		assert !verified_file(path, Payload{ ...payload, sha256: '0'.repeat(64) })
		assert os.read_file(path)! == text && os.lstat(path)!.mode & 0o777 == 0o600
		os.write_file(path, 'changed')!
		assert digest == sha256.hexhash(text)
		unsafe { digest.free() }
	}
}

fn hash_denied(path string) {
	child := C.fork()
	assert child >= 0
	if child == 0 {
		C.alarm(2)
		hash_file(path) or {
			if !verified_file(path, Payload{ bytes: 0, sha256: sha256.hexhash('') }) { C._exit(0) }
			C._exit(43)
		}
		C._exit(42)
	}
	mut status := 0
	assert C.waitpid(child, &status, 0) == child
	assert status == 0, '${path}: expected prompt hash/verification refusal, wait status ${status}'
}

fn test_hash_rejects_special_files_aliases_and_nul_paths_without_modifying_them() {
	work := hash_work()!
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
		work + '/fifo', work + '/socket', work + '/ordinary\x00ignored', '/dev/null'] { hash_denied(path) }
	assert os.read_file(work + '/ordinary')! == 'preserved' && os.lstat(work + '/ordinary')!.mode & 0o777 == 0o600
	assert os.lstat(work + '/fifo')!.mode & 0o170000 == 0o010000
	assert os.readlink(work + '/alias')! == work + '/ordinary'
}

fn hash_replace_path(phase string, path string) ! {
	if phase != os.file_name(os.dir(path)) { return }
	if os.exists(path + '.saved') { return }
	os.rename(path, path + '.saved')!
	match os.file_name(path) {
		'fifo' { if C.mkfifo(path.str, 0o600) != 0 { return error('cannot create hash FIFO fixture') } }
		'symlink' { os.symlink(path + '.outside', path)! }
		'directory' { os.mkdir(path)! }
		'regular' { os.write_file(path, 'same captured bytes')! }
		'missing' {}
		else { return error('unknown hash replacement fixture') }
	}
}

fn test_hash_refuses_replaced_names_at_every_checkpoint_even_with_identical_bytes() {
	work := hash_work()!
	defer { os.rmdir_all(work) or {} }
	for phase in ['opened', 'sized', 'block', 'read'] {
		for operation in ['hash', 'verify'] {
			directory := work + '/' + operation + '/' + phase
			os.mkdir_all(directory)!
			for kind in ['fifo', 'symlink', 'directory', 'regular', 'missing'] {
				path := directory + '/' + kind
				os.write_file(path, 'same captured bytes')!
				os.write_file(path + '.outside', 'never follow this replacement')!
				os.chmod(path + '.outside', 0o600)!
				options := HashReadOptions{ checkpoint: hash_replace_path }
				if operation == 'verify' {
					assert !verified_file_with(path, Payload{ bytes: 19, sha256: sha256.hexhash('same captured bytes') }, options)
				} else {
					mut refused := false
					hash_file_with(path, options) or { refused = err.msg().contains('payload path changed') }
					assert refused, phase + '/' + kind
				}
				assert os.read_file(path + '.saved')! == 'same captured bytes'
				assert os.read_file(path + '.outside')! == 'never follow this replacement'
				assert os.lstat(path + '.outside')!.mode & 0o777 == 0o600
			}
		}
	}
}

fn hash_change_size(phase string, path string) ! {
	if phase != os.file_name(os.dir(path)) { return }
	match os.file_name(path) {
		'grow' { mut file := os.open_append(path)!; defer { file.close() }; file.write_string('appended')! }
		'huge' {
			mut file := os.open_file(path, 'w', 0o600)!
			defer { file.close() }
			file.seek(i64(1) << 32, .start)!; file.write_string('x')!
		}
		'shrink' { os.write_file(path, '')! }
		else { return error('unknown hash size fixture') }
	}
}

fn test_hash_rejects_size_changes_during_and_after_reading_and_restored_files_retry() {
	work := hash_work()!
	defer { os.rmdir_all(work) or {} }
	text := 'x'.repeat(65537)
	payload := Payload{ bytes: u64(text.len), sha256: sha256.hexhash(text) }
	for phase in ['sized', 'block', 'read'] {
		os.mkdir(work + '/' + phase)!
		for kind in ['grow', 'huge', 'shrink'] {
			path := work + '/' + phase + '/' + kind
			os.write_file(path, text)!
			mut refused := false
			hash_file_with(path, HashReadOptions{ checkpoint: hash_change_size }) or {
				refused = err.msg().contains('payload changed size while hashing')
			}
			assert refused, phase + '/' + kind
			assert !verified_file(path, payload)
			os.write_file(path, text)!
			assert !verified_file_with(path, payload, HashReadOptions{ checkpoint: hash_change_size })
			os.write_file(path, text)!
			assert verified_file(path, payload) && hash_file(path)! == payload.sha256
		}
	}
}

fn hash_checkpoint_error(phase string, path string) ! {
	if phase == os.file_name(path) { return error('injected hash read failure') }
}

fn test_verification_admits_the_captured_signed_length_before_reading_payload_bytes() {
	work := hash_work()!
	defer { os.rmdir_all(work) or {} }
	path := work + '/block'
	mut file := os.open_file(path, 'w', 0o600)!
	file.seek(i64(1) << 32, .start)!; file.write_string('x')!; file.close()
	for expected in [u64(0), u64(7), ~u64(0)] {
		mut refused := false
		hash_file_with(path, HashReadOptions{ exact: true, bytes: expected, checkpoint: hash_checkpoint_error }) or {
			refused = err.msg().contains('differs from authenticated length')
		}
		assert refused // a block read would instead throw the injected error
		assert !verified_file(path, Payload{ bytes: expected, sha256: sha256.hexhash('payload') })
	}
	assert os.file_size(path) == (u64(1) << 32) + 1
}

fn test_hash_success_refusal_and_interrupted_reads_release_descriptors() {
	work := hash_work()!
	defer { os.rmdir_all(work) or {} }
	for name in ['opened', 'sized', 'block', 'read', 'valid'] { os.write_file(work + '/' + name, 'payload')! }
	assert C.mkfifo((work + '/fifo').str, 0o600) == 0
	mut original := HashLimit{}
	assert C.getrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0
	limited := HashLimit{ current: 32, maximum: original.maximum }
	assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&limited)) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0 }
	payload := Payload{ bytes: 7, sha256: sha256.hexhash('payload') }
	for _ in 0 .. 128 {
		digest := hash_file(work + '/valid')!
		assert digest == payload.sha256 && verified_file(work + '/valid', payload)
		unsafe { digest.free() }
		assert !verified_file(work + '/valid', Payload{ ...payload, bytes: 0 })
		for name in ['opened', 'sized', 'block', 'read', 'fifo'] {
			options := HashReadOptions{ checkpoint: hash_checkpoint_error }
			mut refused := false
			hash_file_with(work + '/' + name, options) or {
				refused = err.msg().contains('injected hash read failure') || err.msg().contains('regular file')
				message := err.msg()
				unsafe { message.free(); err.free() }
			}
			assert refused && !verified_file_with(work + '/' + name, payload, options)
		}
	}
}
