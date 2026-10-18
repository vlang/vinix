// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import tools.packages.pkgprotocol

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

struct HttpsOwnerLimit { current u64 maximum u64 }
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int
#include <sys/resource.h>
fn C.link(&char, &char) int
fn C.mkfifo(&char, u32) int

fn https_owner_cycles() int {
	$if https_owner_baseline ? { return 2 }
	return 64
}

fn https_owner_change(phase string, path string) ! {
	wanted := os.getenv('VINIX_HTTPS_OWNER_PHASE')
	kind := os.getenv('VINIX_HTTPS_OWNER_KIND')
	outside := os.getenv('VINIX_HTTPS_OWNER_OUTSIDE')
	defer { unsafe { wanted.free(); kind.free(); outside.free() } }
	if wanted != phase { return }
	if kind == 'grow' {
		mut file := os.open_append(path)!; file.write_string('extra')!; file.close()
	} else {
		saved := path + '.saved'; defer { unsafe { saved.free() } }
		assert C.rename(path.str, saved.str) == 0
		os.symlink(outside, path)!
	}
}

fn https_owner_event(event pkgprotocol.Progress) {
	path := os.getenv('VINIX_HTTPS_OWNER_TARGET')
	defer { unsafe { path.free() } }
	phase := if event.current == event.total { 'finish' }
		else if event.current == 0 || event.current == 512 { 'start' } else { '' }
	if phase != '' { https_owner_change(phase, path) or { panic(err) } }
}

fn https_owner_flush(fd int) int {
	mode := os.getenv('VINIX_HTTPS_OWNER_FLUSH')
	path := os.getenv('VINIX_HTTPS_OWNER_TARGET')
	marker := path + '.flushed'
	defer { unsafe { mode.free(); path.free(); marker.free() } }
	mut info := C.stat{}
	first := C.lstat(marker.str, unsafe { &info }) != 0
	if first { os.write_file(marker, 'once') or { panic(err) } }
	if mode == 'interrupted' && first { C.errno = C.EINTR; return -1 }
	if mode == 'failure' { C.errno = C.EIO; return -1 }
	if mode == 'link' {
		linked := path + '.linked'; defer { unsafe { linked.free() } }
		assert C.link(path.str, linked.str) == 0
	}
	return C.fsync(fd)
}

fn https_owner_scope(work string, producer string, text string, mode string, resume bool) ! {
	label := mode + if resume { ' resumed' } else { ' fresh' }
	defer { unsafe { label.free() } }
	path := work + '/target'; outside := work + '/outside'; calls := work + '/calls'
	defer { unsafe { path.free(); outside.free(); calls.free() } }
	for name, value in {'VINIX_OUTPUT_SOURCE': work + '/source', 'VINIX_OUTPUT_CALLS': calls,
		'VINIX_OUTPUT_TARGET': path, 'VINIX_HTTPS_OWNER_TARGET': path, 'VINIX_HTTPS_OWNER_OUTSIDE': outside} {
		os.setenv(name, value, true)
	}
	parts := mode.split('-')
	defer { unsafe { parts.free() } }
	phase := if mode.starts_with('change-') { parts[1] } else { '' }
	kind := if phase != '' { parts[2] } else { '' }
	flush := if mode.starts_with('flush-') { parts[1] } else { '' }
	os.setenv('VINIX_HTTPS_OWNER_PHASE', phase, true); os.setenv('VINIX_HTTPS_OWNER_KIND', kind, true)
	os.setenv('VINIX_HTTPS_OWNER_FLUSH', flush, true)
	program := if mode == 'missing-program' { work + '/absent' } else { producer.clone() }
	route := if mode in ['full', 'no-range', 'empty', 'partial', 'oversized', 'failure', 'terminated']! { mode } else { 'full' }
	url := if mode == 'insecure' { 'http://fixture/full' } else if mode == 'nul' { 'https://fixture/\x00full' } else { 'https://fixture/' + route }
	defer { unsafe { program.free(); url.free() } }
	event := pkgprotocol.Progress{phase: 'download', package: 'app', path: 'payload', total: u64(text.len)}
	mut retained := u64(0)
	for pass in 0 .. 2 {
		loops := if pass == 0 { 2 } else { https_owner_cycles() }
		for _ in 0 .. loops {
			for suffix in ['', '.saved', '.linked', '.flushed']! {
				name := path + suffix
				C.remove(name.str); unsafe { name.free() }
			}
			if os.is_dir(path) { os.rmdir(path)! }
			prefix := if resume { unsafe { tos(text.str, 512) } } else { 'retained prefix' }
			os.write_file(path, prefix)!; os.write_file(calls, '')!; os.write_file(outside, 'foreign bytes')!
			if mode == 'directory' { os.rm(path)!; os.mkdir(path)! }
			if mode == 'alias' { os.rm(path)!; os.symlink(outside, path)! }
			if mode == 'hardlink' { assert C.link(path.str, (path + '.linked').str) == 0 }
			if mode == 'fifo' { os.rm(path)!; assert C.mkfifo(path.str, 0o600) == 0 }
			maximum := if mode == 'empty' { u64(if resume { 512 } else { 0 }) }
				else if mode == 'prefix-limit' { u64(16) } else { u64(text.len) }
			$if track_heap ? { C.vinix_heap_begin() }
			mut refused := false
			used_prefix := fetch_https_with(url, path, maximum, resume, mode == 'offline', event, https_owner_event,
				HttpsOutputOptions{program: program, checkpoint: https_owner_change, flush: https_owner_flush}) or {
				message := err.msg()
				wanted := if mode.starts_with('change-') || mode == 'flush-link' { 'destination changed' }
					else if mode == 'flush-failure' { 'cannot flush' } else if mode == 'oversized' { 'size limit' }
					else if mode in ['insecure', 'nul']! { 'requires HTTPS' } else if mode == 'offline' { 'offline mode' }
					else if mode == 'prefix-limit' { 'prefix exceeds' } else if mode in ['alias', 'directory', 'fifo']! { 'ordinary' }
					else if mode == 'hardlink' { 'without hard links' } else { 'download failed' }
				assert message.contains(wanted), label + ': ' + message
				unsafe { message.free(); err.free() }; refused = true; false
			}
			$if track_heap ? { bytes := C.vinix_heap_end(); if pass == 1 { retained += bytes } }
			expected_failure := mode !in ['full', 'no-range', 'empty', 'flush-interrupted']!
			assert refused == expected_failure, label
			if !refused { assert used_prefix == (resume && mode != 'no-range'), label }
			mut status := i32(0)
			assert C.vinix_package_waitpid(-1, unsafe { &status }, C.WNOHANG) == -1 && C.errno == C.ECHILD
			assert os.read_file(outside)! == 'foreign bytes'
			if mode in ['full', 'no-range', 'flush-interrupted']! { assert os.read_file(path)! == text }
			if mode == 'empty' { assert os.file_size(path) == if resume { 512 } else { 0 } }
			if mode == 'partial' { assert os.file_size(path) == if resume { 1536 } else { 1024 } }
			if mode in ['failure', 'terminated', 'missing-program', 'offline', 'insecure', 'nul', 'prefix-limit']! { assert os.read_file(path)! == prefix }
			if mode == 'oversized' { assert os.file_size(path) <= maximum }
			requests := os.read_file(calls)!.split_into_lines()
			count := if mode in ['offline', 'insecure', 'nul', 'prefix-limit', 'alias', 'directory', 'fifo', 'hardlink', 'missing-program']!
				|| phase == 'opened' { 0 } else if mode == 'no-range' && resume { 2 } else { 1 }
			// Cancellation before a read may kill the producer before it records
			// its request. Completed transfers and opened-only refusals are exact.
			if phase !in ['start', 'written']! && mode != 'oversized' { assert requests.len == count, label }
			unsafe { requests.free() }
		}
	}
	println('HTTPS OWNER ' + label + ' retained ' + retained.str() + ' tracked bytes')
	$if !https_owner_baseline ? { assert retained == 0, label }
}

fn test_complete_https_transport_owns_process_arguments_fallback_and_refusal_scratch() {
	assert os.args.len == 3 && os.args[1] == '--producer'
	work := os.temp_dir() + '/vinix-https-owner-' + os.getpid().str()
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	text := '0123456789abcdef'.repeat(1024)
	os.write_file(work + '/source', text)!
	mut original := HttpsOwnerLimit{}
	assert C.getrlimit(C.RLIMIT_NOFILE, unsafe { voidptr(&original) }) == 0
	limit := HttpsOwnerLimit{current: 32, maximum: original.maximum}
	assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { voidptr(&limit) }) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { voidptr(&original) }) == 0 }
	for resume in [false, true]! {
		for mode in ['full', 'no-range', 'empty', 'partial', 'oversized', 'failure', 'terminated', 'missing-program',
			'offline', 'insecure', 'nul', 'alias', 'directory', 'fifo', 'hardlink']! { https_owner_scope(work, os.args[2], text, mode, resume)! }
		for phase in ['opened', 'written', 'finished', 'start', 'finish']! {
			for kind in ['alias', 'grow']! { https_owner_scope(work, os.args[2], text, 'change-' + phase + '-' + kind, resume)! }
		}
		for mode in ['flush-interrupted', 'flush-failure', 'flush-link']! { https_owner_scope(work, os.args[2], text, mode, resume)! }
	}
	https_owner_scope(work, os.args[2], text, 'prefix-limit', true)!
	$if !https_owner_baseline ? { println('HTTPS OWNER 57 cases with 64 measured calls preserve bytes, bounded retries, output guards and child/descriptor retirement PASS') }
}
