// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import os
import time

#include <sys/resource.h>
struct CacheDescriptorLimit { current u64 maximum u64 }
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int
fn C.mkfifo(&char, u32) int

struct CachePromotionFixture { directory string partial string object string outside string payload Payload }

fn cache_promotion_fixture() !CachePromotionFixture {
	directory := os.real_path(os.temp_dir()) + '/vinix-cache-promotion-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(directory + '/objects')!
	text := 'authenticated complete partial'
	payload := Payload{ path: 'bin/app', bytes: u64(text.len), sha256: sha256.sum(text.bytes()).hex(), executable: true }
	object := directory + '/objects/' + payload.sha256
	os.write_file(object + '.part', text)!; os.chmod(object + '.part', 0o640)!
	os.write_file(directory + '/outside', text)!; os.chmod(directory + '/outside', 0o640)!
	return CachePromotionFixture{ directory: directory, partial: object + '.part', object: object, outside: directory + '/outside', payload: payload }
}

fn cache_promotion_change(_ string, path string) ! {
	mode := os.getenv('VINIX_CACHE_PROMOTION_CHANGE')
	parent := os.dir(path)
	outside := os.dir(parent) + '/outside'
	match mode {
		'link' { os.link(path, path + '.alias')! }
		'replace', 'symlink', 'fifo' {
			os.rename(path, path + '.held')!
			if mode == 'replace' { os.write_file(path, 'authenticated complete partial')!; os.chmod(path, 0o640)! }
			else if mode == 'symlink' { os.symlink(outside, path)! }
			else { assert C.mkfifo(path.str, 0o600) == 0 }
		}
		'parent' {
			os.rename(parent, parent + '.held')!; os.mkdir(parent)!
			os.link(outside, path)!
		}
		'destination-link' { os.symlink(os.dir(parent), path.all_before_last('.part'))! }
		'contents' { os.write_file(path, 'x'.repeat(30))! }
		else {}
	}
}

fn cache_promotion_flush(fd int) int {
	mode := os.getenv('VINIX_CACHE_PROMOTION_FLUSH')
	count := os.getenv('VINIX_CACHE_PROMOTION_FLUSHES').int()
	os.setenv('VINIX_CACHE_PROMOTION_FLUSHES', (count + 1).str(), true)
	mut info := C.stat{}
	assert C.fstat(fd, &info) == 0
	if mode == 'interrupt' && count == 0 { C.errno = C.EINTR; return -1 }
	if mode == 'directory-interrupt' && count == 1 { C.errno = C.EINTR; return -1 }
	if mode == 'failure' || (mode == 'directory-failure' && info.st_mode & 0o170000 == 0o040000) { C.errno = C.EIO; return -1 }
	return C.fsync(fd)
}

fn test_cache_promotion_captures_the_partial_and_parent_without_changing_unrelated_files() {
	for mode in ['link', 'replace', 'symlink', 'fifo', 'parent', 'contents', 'destination-link'] {
		fixture := cache_promotion_fixture()!
		defer { os.rmdir_all(fixture.directory) or {} }
		os.setenv('VINIX_CACHE_PROMOTION_CHANGE', mode, true)
		mut refused := false
		promote_cached_payload_with(fixture.directory, fixture.payload, CachePromotionOptions{ checkpoint: cache_promotion_change }) or { refused = true }
		os.unsetenv('VINIX_CACHE_PROMOTION_CHANGE')
		assert os.read_file(fixture.outside)! == 'authenticated complete partial'
		assert os.lstat(fixture.outside)!.mode & 0o777 == 0o640
		if mode == 'destination-link' {
			assert !refused && !os.is_link(fixture.object) && verified_file(fixture.object, fixture.payload)
			assert !os.exists(fixture.directory + '/' + os.file_name(fixture.partial))
		} else {
			assert refused && !os.exists(fixture.object)
			if mode == 'parent' { assert os.lstat(fixture.partial.all_before_last('/objects/') + '/objects.held/' + os.file_name(fixture.partial))!.mode & 0o777 == 0o640 }
			else if mode in ['replace', 'symlink', 'fifo'] { assert os.lstat(fixture.partial + '.held')!.mode & 0o777 == 0o640 }
			else { assert os.lstat(fixture.partial)!.mode & 0o777 == 0o640 }
		}
	}
	println('CACHE PROMOTION captured partial/parent, link/replacement/FIFO/content refusal and atomic destination-link replacement PASS')
}

fn test_cache_promotion_checks_hash_length_and_retires_descriptors_under_failures() {
	mut original := CacheDescriptorLimit{}
	assert C.getrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0
	limited := CacheDescriptorLimit{ current: 32, maximum: original.maximum }
	assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&limited)) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0 }
	for _ in 0 .. 16 {
		for mode in ['hardlink', 'size', 'hash', 'failure', 'directory-failure', 'interrupt', 'directory-interrupt', 'success'] {
			fixture := cache_promotion_fixture()!
			defer { os.rmdir_all(fixture.directory) or {} }
			if mode == 'hardlink' { os.link(fixture.partial, fixture.partial + '.alias')! }
			if mode == 'size' { os.write_file(fixture.partial, 'short')! }
			if mode == 'hash' { os.write_file(fixture.partial, 'x'.repeat(int(fixture.payload.bytes)))! }
			os.setenv('VINIX_CACHE_PROMOTION_FLUSH', mode, true); os.setenv('VINIX_CACHE_PROMOTION_FLUSHES', '0', true)
			mut message := ''
			promote_cached_payload_with(fixture.directory, fixture.payload, CachePromotionOptions{ flush: cache_promotion_flush }) or { message = err.msg() }
			os.unsetenv('VINIX_CACHE_PROMOTION_FLUSH')
			assert os.read_file(fixture.outside)! == 'authenticated complete partial' && os.lstat(fixture.outside)!.mode & 0o777 == 0o640
			if mode in ['success', 'interrupt', 'directory-interrupt', 'directory-failure'] {
				assert verified_file(fixture.object, fixture.payload) && !os.exists(fixture.partial)
				assert os.lstat(fixture.object)!.mode & 0o777 == 0o444
				if mode == 'directory-failure' { assert message.contains('cached payload saved') }
				else { assert message == '' }
				if mode in ['interrupt', 'directory-interrupt'] { assert os.getenv('VINIX_CACHE_PROMOTION_FLUSHES') == '3' }
			} else {
				assert message != '' && !os.exists(fixture.object) && os.exists(fixture.partial)
				assert os.lstat(fixture.partial)!.mode & 0o777 == if mode == 'failure' { 0o444 } else { 0o640 }
			}
		}
	}
	os.unsetenv('VINIX_CACHE_PROMOTION_FLUSHES')
	println('CACHE PROMOTION signed hash/length, captured flush EINTR/EIO, published-cache diagnostics and 128 cycles under 32 descriptors PASS')
}
