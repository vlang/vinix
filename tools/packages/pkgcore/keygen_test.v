// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time

#include <sys/resource.h>
fn C.mkfifo(&char, u32) int
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int
struct KeygenLimit { current u64 maximum u64 }

fn keygen_work() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-keygen-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir(work, mode: 0o700)!
	return work
}

fn keygen_fault(phase string, path string) ! {
	if phase != os.getenv('VINIX_KEYGEN_PHASE') { return }
	kind := os.getenv('VINIX_KEYGEN_KIND')
	if kind == 'stop' { return error('injected checkpoint failure') }
	if kind == 'parent-alias' || kind == 'parent-ordinary' {
		parent := os.getenv('VINIX_KEYGEN_PARENT')
		os.rename(parent, parent + '.saved')!
		if kind == 'parent-alias' { os.symlink(os.getenv('VINIX_KEYGEN_OUTSIDE'), parent)! } else { os.mkdir(parent, mode: 0o700)! }
	} else if kind.starts_with('race-') {
		target := os.getenv('VINIX_KEYGEN_TARGET')
		match kind {
			'race-file' { os.write_file(target, 'raced destination')! }
			'race-directory' { os.mkdir(target)! }
			'race-alias' { os.symlink(os.getenv('VINIX_KEYGEN_OUTSIDE') + '/preserved', target)! }
			else { assert C.mkfifo(target.str, 0o600) == 0 }
		}
	} else if kind == 'public' { os.chmod(path, 0o644)!
	} else if kind == 'grow' {
		mut file := os.open_file(path, 'a', 0o600)!; file.write_string('changed')!; file.close()
	} else {
		os.rename(path, path + '.saved')!
		if kind == 'alias' { os.symlink(os.getenv('VINIX_KEYGEN_OUTSIDE') + '/preserved', path)!
		} else { os.write_file(path, 'replacement')!; os.chmod(path, 0o600)! }
	}
}

fn keygen_short_write(fd int, bytes voidptr, count usize) isize {
	if os.getenv('VINIX_KEYGEN_WRITE') == '' { os.setenv('VINIX_KEYGEN_WRITE', 'interrupted', true); C.errno = C.EINTR; return -1 }
	return C.write(fd, bytes, if count > 7 { usize(7) } else { count })
}

fn keygen_failed_write(fd int, bytes voidptr, count usize) isize {
	if os.getenv('VINIX_KEYGEN_WRITE') == '' { os.setenv('VINIX_KEYGEN_WRITE', 'partial', true); return C.write(fd, bytes, if count > 5 { usize(5) } else { count }) }
	C.errno = C.ENOSPC; return -1
}

fn keygen_interrupted_flush(fd int) int {
	mut info := C.stat{}; assert C.fstat(fd, &info) == 0
	key := if info.st_mode & 0o170000 == 0o040000 { 'VINIX_KEYGEN_DIRECTORY_FLUSH' } else { 'VINIX_KEYGEN_FILE_FLUSH' }
	if os.getenv(key) == '' { os.setenv(key, 'interrupted', true); C.errno = C.EINTR; return -1 }
	return C.fsync(fd)
}

fn keygen_failed_flush(fd int) int {
	mut info := C.stat{}; assert C.fstat(fd, &info) == 0
	directory := info.st_mode & 0o170000 == 0o040000
	if directory == (os.getenv('VINIX_KEYGEN_KIND') == 'directory-flush') { C.errno = C.EIO; return -1 }
	return C.fsync(fd)
}

fn keygen_environment() {
	for key in ['VINIX_KEYGEN_PHASE', 'VINIX_KEYGEN_KIND', 'VINIX_KEYGEN_PARENT', 'VINIX_KEYGEN_OUTSIDE',
		'VINIX_KEYGEN_TARGET', 'VINIX_KEYGEN_WRITE', 'VINIX_KEYGEN_DIRECTORY_FLUSH', 'VINIX_KEYGEN_FILE_FLUSH'] { os.unsetenv(key) }
}

fn test_keygen_short_writes_eintr_flushes_private_seed_and_read_only_recovery() {
	work := keygen_work()!; defer { os.rmdir_all(work) or {} }; defer { keygen_environment() }
	keygen_environment()
	path := work + '/seed'
	key := keygen_with(path, KeygenOptions{ write: keygen_short_write, flush: keygen_interrupted_flush })!
	assert key == key_public(path)! && key.len == 64
	assert os.getenv('VINIX_KEYGEN_WRITE') == 'interrupted'
	assert os.getenv('VINIX_KEYGEN_DIRECTORY_FLUSH') == 'interrupted' && os.getenv('VINIX_KEYGEN_FILE_FLUSH') == 'interrupted'
	assert os.ls(work)! == ['seed']
	info := os.lstat(path)!; text := os.read_file(path)!
	assert info.mode & 0o777 == 0o600 && info.uid == u32(os.geteuid()) && info.size == 65
	assert text.ends_with('\n') && text[..64].bytes().all(signing_hex(it) >= 0)
	mut refused := false
	keygen(path) or { refused = err.msg().contains('already exists') }
	assert refused && os.read_file(path)! == text && key_public(path)! == key
	for invalid in ['', work + '/.', work + '/..', work + '/', path + '\x00ignored'] {
		mut invalid_path := false; keygen(invalid) or { invalid_path = true }; assert invalid_path
	}
	os.chmod(path, 0o644)!
	mut unsafe_seed := false; key_public(path) or { unsafe_seed = true }; assert unsafe_seed
	os.chmod(path, 0o600)!; os.symlink(path, work + '/alias')!
	mut alias := false; key_public(work + '/alias') or { alias = true }; assert alias
	assert key_public(path)! == key && os.read_file(path)! == text
}

fn test_keygen_prepublication_errors_clean_up_and_postpublication_errors_preserve_seed() {
	work := keygen_work()!; defer { os.rmdir_all(work) or {} }; defer { keygen_environment() }
	for phase in ['created', 'written', 'flushed', 'published'] {
		keygen_environment(); os.setenv('VINIX_KEYGEN_PHASE', phase, true); os.setenv('VINIX_KEYGEN_KIND', 'stop', true)
		base := work + '/' + phase; os.mkdir(base, mode: 0o700)!
		mut failed := false
		keygen_with(base + '/seed', KeygenOptions{ checkpoint: keygen_fault }) or { failed = true; assert err.msg().contains('saved') == (phase == 'published') }
		assert failed && os.ls(base)!.len == if phase == 'published' { 1 } else { 0 }
		keygen_environment()
		if phase == 'published' { assert key_public(base + '/seed')!.len == 64 } else { assert keygen(base + '/seed')! == key_public(base + '/seed')! }
	}
	for kind in ['partial-write', 'file-flush', 'directory-flush'] {
		keygen_environment(); os.setenv('VINIX_KEYGEN_KIND', kind, true)
		base := work + '/' + kind; os.mkdir(base, mode: 0o700)!
		mut failed := false
		keygen_with(base + '/seed', KeygenOptions{ write: if kind == 'partial-write' { keygen_failed_write } else { atomic_write_bytes }, flush: keygen_failed_flush }) or {
			failed = true; assert err.msg().contains('saved') == (kind == 'directory-flush')
		}
		assert failed && os.ls(base)!.len == if kind == 'directory-flush' { 1 } else { 0 }
		keygen_environment()
		if kind == 'directory-flush' { assert key_public(base + '/seed')!.len == 64 } else { assert keygen(base + '/seed')! == key_public(base + '/seed')! }
	}
}

fn test_keygen_substitutions_never_overwrite_or_remove_replacement_names() {
	work := keygen_work()!; defer { os.rmdir_all(work) or {} }; defer { keygen_environment() }
	os.mkdir(work + '/outside', mode: 0o700)!; os.write_file(work + '/outside/preserved', 'preserved')!; os.chmod(work + '/outside/preserved', 0o600)!
	for phase in ['created', 'written', 'flushed'] {
		for kind in ['alias', 'ordinary', 'public', 'grow'] {
			base := work + '/' + phase + '-' + kind; os.mkdir(base, mode: 0o700)!
			keygen_environment(); os.setenv('VINIX_KEYGEN_PHASE', phase, true); os.setenv('VINIX_KEYGEN_KIND', kind, true); os.setenv('VINIX_KEYGEN_OUTSIDE', work + '/outside', true)
			mut failed := false; keygen_with(base + '/seed', KeygenOptions{ checkpoint: keygen_fault }) or { failed = true }
			assert failed && !os.exists(base + '/seed')
			assert os.ls(base)!.len == if kind in ['alias', 'ordinary'] { 2 } else { 0 }
		}
	}
	for kind in ['race-file', 'race-directory', 'race-alias', 'race-fifo'] {
		base := work + '/' + kind; os.mkdir(base, mode: 0o700)!
		keygen_environment(); os.setenv('VINIX_KEYGEN_PHASE', 'flushed', true); os.setenv('VINIX_KEYGEN_KIND', kind, true)
		os.setenv('VINIX_KEYGEN_TARGET', base + '/seed', true); os.setenv('VINIX_KEYGEN_OUTSIDE', work + '/outside', true)
		mut failed := false; keygen_with(base + '/seed', KeygenOptions{ checkpoint: keygen_fault }) or { failed = err.msg().contains('exclusively publish') }
		assert failed && os.ls(base)! == ['seed']
		if kind == 'race-file' { assert os.read_file(base + '/seed')! == 'raced destination' }
	}
	for phase in ['captured', 'flushed', 'published'] {
		for kind in ['parent-alias', 'parent-ordinary'] {
			base := work + '/' + phase + '-' + kind; os.mkdir(base, mode: 0o700)!
			keygen_environment(); os.setenv('VINIX_KEYGEN_PHASE', phase, true); os.setenv('VINIX_KEYGEN_KIND', kind, true)
			os.setenv('VINIX_KEYGEN_PARENT', base, true); os.setenv('VINIX_KEYGEN_OUTSIDE', work + '/outside', true)
			mut failed := false; keygen_with(base + '/seed', KeygenOptions{ checkpoint: keygen_fault }) or { failed = true; assert err.msg().contains('saved') == (phase == 'published') }
			assert failed && os.ls(base + '.saved')!.len == if phase == 'published' { 1 } else { 0 }
			if phase == 'published' { assert key_public(base + '.saved/seed')!.len == 64 }
		}
	}
	assert os.ls(work + '/outside')! == ['preserved'] && os.read_file(work + '/outside/preserved')! == 'preserved'
	assert os.lstat(work + '/outside/preserved')!.mode & 0o777 == 0o600
}

fn test_keygen_repeated_success_and_failure_close_descriptors() {
	work := keygen_work()!; defer { os.rmdir_all(work) or {} }; defer { keygen_environment() }
	mut original := KeygenLimit{}; assert C.getrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0
	limit := KeygenLimit{ current: 32, maximum: original.maximum }; assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&limit)) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0 }
	for _ in 0 .. 64 {
		keygen_environment(); assert keygen(work + '/seed')! == key_public(work + '/seed')!
		mut exists := false; keygen(work + '/seed') or { exists = true }; assert exists
		os.rm(work + '/seed')!
		os.setenv('VINIX_KEYGEN_KIND', 'file-flush', true)
		mut failed := false; keygen_with(work + '/seed', KeygenOptions{ flush: keygen_failed_flush }) or { failed = true }; assert failed
		assert os.ls(work)!.len == 0
	}
}
