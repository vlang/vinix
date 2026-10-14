// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time
import tools.packages.pkgprotocol

#include <sys/resource.h>
fn C.link(&char, &char) int
fn C.mkfifo(&char, u32) int
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int
struct CopyOutputLimit { current u64 maximum u64 }

fn copy_output_work() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-copy-output-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir(work)!
	return work
}

fn copy_output_change(phase string, path string) ! {
	if phase != os.file_name(os.dir(path)) { return }
	match os.file_name(path) {
		'link' { assert C.link(path.str, (path + '.linked').str) == 0 }
		'grow' { mut file := os.open_append(path)!; file.write_string('extra')!; file.close() }
		else {
			os.rename(path, path + '.saved')!
			match os.file_name(path) {
				'fifo' { assert C.mkfifo(path.str, 0o600) == 0 }
				'alias' { os.symlink(os.getenv('VINIX_COPY_OUTPUT_OUTSIDE'), path)! }
				'ordinary' { os.write_file(path, 'replacement')! }
				'missing' {}
				else { panic('unknown copy output change') }
			}
		}
	}
}

fn copy_output_flush(fd int) int {
	os.write_file(os.getenv('VINIX_COPY_OUTPUT_FLUSHED'), 'once') or { panic(err) }
	return C.fsync(fd)
}

fn copy_output_interrupted(fd int) int {
	if os.getenv('VINIX_COPY_OUTPUT_INTERRUPTED') == '' {
		os.setenv('VINIX_COPY_OUTPUT_INTERRUPTED', 'once', true)
		C.errno = C.EINTR
		return -1
	}
	return C.fsync(fd)
}

fn copy_output_failed(_ int) int { C.errno = C.EIO; return -1 }

fn test_copy_output_captures_identity_and_rechecks_links_size_and_name_before_writing_and_after_flush() {
	work := copy_output_work()!
	defer { os.rmdir_all(work) or {} }
	defer { os.unsetenv('VINIX_COPY_OUTPUT_OUTSIDE'); os.unsetenv('VINIX_COPY_OUTPUT_FLUSHED') }
	os.write_file(work + '/source', 'payload')!
	os.write_file(work + '/outside', 'preserved')!
	os.chmod(work + '/outside', 0o640)!
	os.setenv('VINIX_COPY_OUTPUT_OUTSIDE', work + '/outside', true)
	os.setenv('VINIX_COPY_OUTPUT_FLUSHED', work + '/marker', true)
	input := copy_source(work + '/source', 7)!
	defer { C.close(input.fd) }
	for phase in ['opened', 'flushed'] {
		os.mkdir(work + '/' + phase)!
		for kind in ['link', 'grow', 'fifo', 'alias', 'ordinary', 'missing'] {
			path := work + '/' + phase + '/' + kind
			os.write_file(path, 'retained')!
			if os.exists(work + '/marker') { os.rm(work + '/marker')! }
			mut refused := false
			copy_opened_with(input, work + '/source', path, 0, pkgprotocol.Progress{}, no_progress,
				CopyOptions{ checkpoint: copy_output_change, flush: copy_output_flush }) or {
				refused = err.msg().contains('destination changed')
			}
			assert refused && os.exists(work + '/marker') == (phase == 'flushed'), phase + '/' + kind
			expected := if phase == 'opened' { 'retained' } else { 'payload' }
			if kind == 'link' { assert os.read_file(path + '.linked')! == expected }
			else if kind == 'grow' { assert os.read_file(path)! == expected + 'extra' }
			else { assert os.read_file(path + '.saved')! == expected }
			assert os.read_file(work + '/outside')! == 'preserved'
			assert os.lstat(work + '/outside')!.mode & 0o777 == 0o640
		}
	}
}

fn copy_output_observer(event pkgprotocol.Progress) {
	work := os.getenv('VINIX_COPY_OUTPUT_WORK')
	defer { unsafe { work.free() } }
	when := os.getenv('VINIX_COPY_OUTPUT_WHEN')
	defer { unsafe { when.free() } }
	if (when == 'start' && event.current != 0) || (when == 'finish' && event.current != event.total) { return }
	assert C.link((work + '/target').str, (work + '/linked').str) == 0
}

fn test_copy_output_observer_cannot_add_shared_output_before_writing_or_after_flush() {
	for when in ['start', 'finish'] {
		work := copy_output_work()!
		defer { os.rmdir_all(work) or {} }
		defer { os.unsetenv('VINIX_COPY_OUTPUT_WORK'); os.unsetenv('VINIX_COPY_OUTPUT_WHEN') }
		os.write_file(work + '/source', 'payload')!
		os.write_file(work + '/target', 'retained')!
		os.setenv('VINIX_COPY_OUTPUT_WORK', work, true)
		os.setenv('VINIX_COPY_OUTPUT_WHEN', when, true)
		input := copy_source(work + '/source', 7)!
		mut refused := false
		copy_opened_with(input, work + '/source', work + '/target', 0,
			pkgprotocol.Progress{ phase: 'copy', path: 'payload', total: 7 }, copy_output_observer, CopyOptions{}) or {
			refused = err.msg().contains('destination changed')
		}
		C.close(input.fd)
		assert refused && os.read_file(work + '/linked')! == if when == 'start' { '' } else { 'payload' }
		// Remove only the extra name; restoring ordinary output permits retry.
		os.rm(work + '/linked')!
		copy_file(work + '/source', work + '/target', 0, 7)!
		assert os.read_file(work + '/target')! == 'payload'
	}
}

fn test_copy_output_flush_retries_interruption_reports_storage_failure_and_retires_descriptors() {
	work := copy_output_work()!
	defer { os.rmdir_all(work) or {} }
	defer { os.unsetenv('VINIX_COPY_OUTPUT_INTERRUPTED') }
	os.write_file(work + '/source', 'payload')!
	os.write_file(work + '/outside', 'preserved')!
	assert C.link((work + '/outside').str, (work + '/linked').str) == 0
	input := copy_source(work + '/source', 7)!
	defer { C.close(input.fd) }
	copy_opened_with(input, work + '/source', work + '/target', 0, pkgprotocol.Progress{}, no_progress,
		CopyOptions{ flush: copy_output_interrupted })!
	assert os.getenv('VINIX_COPY_OUTPUT_INTERRUPTED') == 'once' && os.read_file(work + '/target')! == 'payload'
	mut original := CopyOutputLimit{}
	assert C.getrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0
	limit := CopyOutputLimit{ current: 32, maximum: original.maximum }
	assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&limit)) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0 }
	for _ in 0 .. 64 {
		mut refused := false
		copy_opened_with(input, work + '/source', work + '/target', 0, pkgprotocol.Progress{}, no_progress,
			CopyOptions{ flush: copy_output_failed }) or {
			refused = err.msg().contains('cannot flush captured payload')
			message := err.msg(); unsafe { message.free(); err.free() }
		}
		assert refused
		refused = false
		copy_file(work + '/source', work + '/linked', 0, 7) or {
			refused = err.msg().contains('without hard links')
			message := err.msg(); unsafe { message.free(); err.free() }
		}
		assert refused && os.read_file(work + '/outside')! == 'preserved'
		copy_file(work + '/source', work + '/target', 0, 7)!
		assert os.read_file(work + '/target')! == 'payload'
	}
}
