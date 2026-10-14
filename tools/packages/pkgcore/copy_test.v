// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time
import tools.packages.pkgprotocol

#include <sys/resource.h>
fn C.mkfifo(&char, u32) int
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int

struct CopyLimit { current u64 maximum u64 }

fn copy_work() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-copy-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir(work)!
	return work
}

fn test_copy_full_empty_and_resumed_files_preserve_exact_contents_and_modes() {
	work := copy_work()!
	defer { os.rmdir_all(work) or {} }
	text := '0123456789abcdef'.repeat(16384)
	source := work + '/source'
	target := work + '/target'
	os.write_file(source, text)!
	for offset in [0, 1, 65536, text.len] {
		os.write_file(target, if offset == 0 { 'old destination contents' } else { text[..offset] })!
		os.chmod(target, 0o640)!
		copy_file(source, target, u64(offset), u64(text.len))!
		assert os.read_file(source)! == text && os.read_file(target)! == text
		assert os.lstat(target)!.mode & 0o777 == 0o640
	}
	os.write_file(source, '')!
	copy_file(source, target, 0, 0)!
	assert os.read_file(target)! == ''
	os.rm(target)!
	copy_file(source, target, 0, 0)!
	assert os.read_file(target)! == '' && os.lstat(target)!.mode & 0o077 == 0
}

fn test_copy_invalid_bounds_and_missing_resumes_preserve_existing_files() {
	work := copy_work()!
	defer { os.rmdir_all(work) or {} }
	source := work + '/source'
	target := work + '/target'
	os.write_file(source, 'payload')!
	os.write_file(target, 'retained')!
	for offset in [u64(1), 8, ~u64(0)] {
		mut refused := false
		copy_file(source, target, offset, 7) or { refused = err.msg().contains('offset') }
		assert refused && os.read_file(source)! == 'payload' && os.read_file(target)! == 'retained'
	}
	mut limited := false
	copy_file(source, target, 0, 6) or { limited = err.msg().contains('exceeds authenticated size') }
	assert limited && os.read_file(target)! == 'retained'
	mut missing := false
	copy_file(source, work + '/missing', 1, 7) or { missing = true }
	assert missing && !os.exists(work + '/missing')
	for path in [source + '\x00ignored', work + '/absent', work] {
		mut refused := false
		copy_file(path, target, 0, 64) or { refused = true }
		assert refused && os.read_file(target)! == 'retained'
	}
	mut nul := false
	copy_file(source, target + '\x00ignored', 0, 7) or { nul = true }
	assert nul && os.read_file(target)! == 'retained'
}

fn test_offline_fetch_resumes_or_restarts_ordinary_partials_after_source_admission() {
	work := copy_work()!
	defer { os.rmdir_all(work) or {} }
	source := work + '/source'
	target := work + '/target'
	os.write_file(source, 'payload')!
	for prefix in ['', 'pay', 'payload', 'oversized partial'] {
		os.write_file(target, prefix)!
		resumed := fetch_file_progress(source, target, 7, true, pkgprotocol.Progress{}, no_progress)!
		assert resumed == (prefix.len > 0 && prefix.len <= 7)
		assert os.read_file(target)! == 'payload'
	}
	os.write_file(target, 'retained')!
	os.write_file(source, 'oversized source')!
	mut refused := false
	fetch('file://' + source, target, 7, true, true) or { refused = err.msg().contains('exceeds authenticated size') }
	assert refused && os.read_file(target)! == 'retained'
	os.write_file(source, 'payload')!
	fetch('file://' + source, target, 7, true, true)!
	assert os.read_file(target)! == 'payload'
}

fn copy_interfere(event pkgprotocol.Progress) {
	event.validate() or { panic(err) }
	work := os.getenv('VINIX_COPY_WORK')
	mut log := os.open_append(work + '/events') or { panic(err) }
	log.writeln(json2.encode(event)) or { panic(err) }; log.close()
	if event.current != 0 || os.exists(work + '/interfered') { return }
	os.write_file(work + '/interfered', 'once') or { panic(err) }
	mode := os.getenv('VINIX_COPY_MODE')
	path := work + if mode.starts_with('source-') { '/source' } else { '/target' }
	match mode {
		'source-fifo', 'target-fifo', 'source-alias', 'target-alias' {
			os.rename(path, path + '.saved') or { panic(err) }
			if mode.ends_with('fifo') { assert C.mkfifo(path.str, 0o600) == 0 }
			else { os.symlink(work + '/outside', path) or { panic(err) } }
		}
		'source-grow' { mut file := os.open_append(path) or { panic(err) }; file.write_string('growth') or { panic(err) }; file.close() }
		'source-shrink' { os.write_file(path, 'pay') or { panic(err) } }
		'target-grow' { os.write_file(path, 'x'.repeat(128)) or { panic(err) } }
		else { panic('unknown copy interference') }
	}
}

fn test_copy_uses_captured_descriptors_and_refuses_size_or_destination_identity_changes() {
	for mode in ['source-fifo', 'source-alias', 'target-fifo', 'target-alias', 'source-grow', 'source-shrink', 'target-grow'] {
		work := copy_work()!
		defer { os.rmdir_all(work) or {} }
		os.write_file(work + '/source', 'payload')!
		os.write_file(work + '/target', 'old')!
		os.write_file(work + '/outside', 'preserved')!
		os.chmod(work + '/outside', 0o600)!
		os.write_file(work + '/events', '')!
		os.setenv('VINIX_COPY_WORK', work, true); os.setenv('VINIX_COPY_MODE', mode, true)
		defer { os.unsetenv('VINIX_COPY_WORK'); os.unsetenv('VINIX_COPY_MODE') }
		mut refused := false
		copy_file_progress(work + '/source', work + '/target', 0, 7,
			pkgprotocol.Progress{ phase: 'copy', package: 'app', path: 'bin/app', total: 7 }, copy_interfere) or {
			refused = err.msg().contains('changed')
		}
		assert refused == (mode !in ['source-fifo', 'source-alias']), mode
		if !refused { assert os.read_file(work + '/target')! == 'payload' }
		if mode.starts_with('target-') && mode != 'target-grow' { assert os.read_file(work + '/target.saved')! == 'payload' }
		assert os.read_file(work + '/outside')! == 'preserved' && os.lstat(work + '/outside')!.mode & 0o777 == 0o600
		mut events := []pkgprotocol.Progress{}
		for line in os.read_file(work + '/events')!.split_into_lines() { events << pkgprotocol.decode_progress(line)! }
		assert events.first().current == 0 && events.all(it.current <= 7)
		assert events.any(it.current == 7) == !refused
	}
}

fn test_copy_success_and_admission_failures_close_descriptors() {
	work := copy_work()!
	defer { os.rmdir_all(work) or {} }
	os.write_file(work + '/source', 'payload')!
	assert C.mkfifo((work + '/fifo').str, 0o600) == 0
	mut original := CopyLimit{}
	assert C.getrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0
	limited := CopyLimit{ current: 32, maximum: original.maximum }
	assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&limited)) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0 }
	for _ in 0 .. 128 {
		copy_file(work + '/source', work + '/target', 0, 7)!
		for pair in [['fifo', 'target'], ['source', 'fifo'], ['source', 'source']] {
			mut refused := false
			copy_file(work + '/' + pair[0], work + '/' + pair[1], 0, 7) or {
				refused = true
				message := err.msg(); unsafe { message.free(); err.free() }
			}
			assert refused
		}
	}
}
