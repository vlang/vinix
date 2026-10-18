// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time
import tools.packages.pkgprotocol

#include <sys/resource.h>
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int
fn C.link(&char, &char) int
fn C.mkfifo(&char, u32) int
struct OutputLimit { current u64 maximum u64 }

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn test_https_failure_explanations_retire_owned_errors() {
	$if track_heap ? {
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				for code in [1, 2, 3, 4, 5, 6, 7, 16, 18, 22, 23, 27, 28, 33, 35, 36, 47, 48, 52, 55, 56, 58, 59, 60, 63, 67, 77, 80, 82, 83, 90, 91, 92, 94, 95, 96, 97, 98, 126, 127, 143, 199, 42]! {
					err := https_transport_failure(code, 'https://fixture/repository', '/usr/bin/curl')
					message := err.msg()
					assert message.starts_with('download failed (') && message.ends_with('https://fixture/repository')
					unsafe { message.free(); err.free() }
				}
			}
		}
		assert C.vinix_heap_end() == 0
		println('HTTPS DIAGNOSTICS 1000 cycles across 43 statuses retire owned messages and errors with zero tracked bytes PASS')
	}
}

fn test_https_transport_diagnostics_preserve_prefixes_and_bounded_retry() {
	work := output_work()!; defer { os.rmdir_all(work) or {} }
	fixture := output_fixture(work)!
	os.write_file(work + '/calls', '')!; os.setenv('VINIX_OUTPUT_CALLS', work + '/calls', true)
	defer { os.unsetenv('VINIX_OUTPUT_CALLS') }
	path := work + '/payload'; prefix := 'retained authenticated prefix'
	for code, expected in {1: 'redirect protocol', 2: 'initialize', 3: 'URL is malformed', 4: 'required feature',
		5: 'proxy hostname', 6: 'repository hostname', 7: 'cannot connect', 16: 'protocol connection',
		18: 'before all bytes arrived', 22: 'HTTP error', 23: 'disk space', 27: 'out of memory', 28: 'timed out',
		33: 'byte range', 35: 'TLS handshake', 36: 'byte range', 47: 'redirected too many', 48: 'required feature',
		52: 'no response', 55: 'interrupted', 56: 'interrupted', 58: 'client certificate', 59: 'cipher',
		60: 'certificate or hostname', 63: 'allowed download size', 67: 'authentication failed', 77: 'CA certificates could not be read',
		80: 'did not close', 82: 'TLS identity', 83: 'TLS identity', 90: 'TLS identity', 91: 'TLS identity',
		92: 'protocol connection', 94: 'authentication failed', 95: 'protocol connection', 96: 'protocol connection',
		97: 'proxy handshake', 98: 'client certificate', 126: 'cannot start HTTPS transport', 127: 'cannot start HTTPS transport',
		42: 'inspect the transport diagnostic'} {
		for resume in [false, true]! {
			os.write_file(path, prefix)!
			before := os.read_file(work + '/calls')!.split_into_lines().len
			number := code.str(); url := 'https://fixture/exit-' + number
			mut refused := false
			fetch_https_with(url, path, 4096, resume, false, pkgprotocol.Progress{}, no_progress, HttpsOutputOptions{program: fixture}) or {
				message := err.msg()
				assert message.starts_with('download failed (' + number + '): ') && message.contains(expected), message
				assert message.contains('retained partial data for retry') && message.ends_with(url), message
				unsafe { message.free(); err.free() }; refused = true
			}
			assert refused && os.read_file(path)! == prefix
			calls := os.read_file(work + '/calls')!.split_into_lines()
			assert calls.len - before == if code == 33 && resume { 2 } else { 1 }
			output_no_children()
		}
	}
	os.write_file(path, prefix)!
	mut terminated := false
	fetch_https_with('https://fixture/terminated', path, 4096, true, false, pkgprotocol.Progress{}, no_progress, HttpsOutputOptions{program: fixture}) or {
		message := err.msg(); terminated = message.contains('terminated unexpectedly')
		unsafe { message.free(); err.free() }
	}
	assert terminated && os.read_file(path)! == prefix
	output_no_children()
	println('HTTPS DIAGNOSTICS 41 exit statuses and terminated transport give actionable errors, preserve fresh/resumed prefixes, retry only range refusal and reap children PASS')
}

fn output_work() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-output-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir(work)!
	return work
}

fn output_fixture(work string) !string {
	if os.args.len == 3 && os.args[1] == '--producer' { return os.args[2] }
	if executable := os.getenv_opt('VINIX_PACKAGE_OUTPUT_FIXTURE') { return executable }
	v := os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!
	mut compiler := os.new_process(v)
	compiler.set_args(['-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-o', work + '/fixture', 'tests/packages/output-fixture.v'])
	compiler.wait(); code := compiler.code; compiler.close()
	if code != 0 { return error('cannot compile output fixture') }
	return work + '/fixture'
}

fn output_event(event pkgprotocol.Progress) {
	event.validate() or { panic(err) }
	mut file := os.open_append(os.getenv('VINIX_OUTPUT_EVENTS')) or { panic(err) }
	file.writeln(event.current.str()) or { panic(err) }; file.close()
}

fn output_mutate(phase string, path string) ! {
	if phase != os.file_name(os.dir(path)) { return }
	if os.exists(path + '.saved') || os.exists(path + '.changed') { return }
	os.write_file(path + '.changed', 'once')!
	if os.file_name(path) == 'grow' {
		mut file := os.open_file(path, 'a', 0o600)!
		assert C.ftruncate(file.fd, os.file_size(os.getenv('VINIX_OUTPUT_SOURCE')) + 1) == 0
		file.close(); return
	}
	os.rename(path, path + '.saved')!
	os.symlink(os.getenv('VINIX_OUTPUT_OUTSIDE'), path)!
}

fn output_no_children() {
	mut status := i32(0)
	assert C.vinix_package_waitpid(-1, &status, C.WNOHANG) == -1 && C.errno == C.ECHILD
}

fn test_https_output_capture_bounded_writes_recovery_progress_and_descriptor_retirement() {
	work := output_work()!
	defer { os.rmdir_all(work) or {} }
	fixture := output_fixture(work)!
	text := 'binary\x00output\xff'.repeat(8192)
	os.write_file(work + '/source', text)!
	os.write_file(work + '/calls', '')!
	os.write_file(work + '/events', '')!
	for key, value in {'VINIX_OUTPUT_SOURCE': work + '/source', 'VINIX_OUTPUT_CALLS': work + '/calls',
		'VINIX_OUTPUT_EVENTS': work + '/events', 'VINIX_OUTPUT_OUTSIDE': work + '/outside'} { os.setenv(key, value, true) }
	defer { for key in ['VINIX_OUTPUT_SOURCE', 'VINIX_OUTPUT_CALLS', 'VINIX_OUTPUT_EVENTS', 'VINIX_OUTPUT_OUTSIDE', 'VINIX_OUTPUT_TARGET', 'VINIX_OUTPUT_LOCK'] { os.unsetenv(key) } }
	path := work + '/payload'
	os.setenv('VINIX_OUTPUT_TARGET', path, true)
	guard := acquire(work + '/store')!
	defer { guard.release() }
	os.setenv('VINIX_OUTPUT_LOCK', work + '/store/lock', true)
	options := HttpsOutputOptions{ program: fixture }
	event := pkgprotocol.Progress{ phase: 'download', package: 'app', path: 'payload', total: u64(text.len) }
	for mode in ['full', 'slow', 'no-range'] {
		os.write_file(path, text[..4096])!
		os.write_file(work + '/events', '')!
		before := os.read_file(work + '/calls')!.split_into_lines().len
		resumed := fetch_https_with('https://fixture/' + mode, path, u64(text.len), true, false, event, output_event, options)!
		assert resumed == (mode != 'no-range') && os.read_file(path)! == text
		calls := os.read_file(work + '/calls')!.split_into_lines()[before..]
		assert calls == if mode == 'no-range' { [mode + ' 4096', mode + ' 0'] } else { [mode + ' 4096'] }
		counts := os.read_file(work + '/events')!.split_into_lines().map(it.u64())
		assert counts.first() == 4096 && counts.last() == u64(text.len) && counts.all(it <= u64(text.len))
		output_no_children()
	}
	os.write_file(path, 'old prefix')!
	assert !fetch_https_with('https://fixture/full', path, u64(text.len), false, false, event, no_progress, options)! && os.read_file(path)! == text
	for resume in [false, true] {
		os.write_file(path, text[..4096])!
		mut refused := false
		fetch_https_with('https://fixture/failure', path, u64(text.len), resume, false, event, no_progress, options) or { refused = err.msg().contains('download failed (60)') }
		assert refused && os.read_file(path)! == text[..4096]
		output_no_children()
	}
	os.write_file(path, text[..4096])!
	mut partial := false
	fetch_https_with('https://fixture/partial', path, u64(text.len), true, false, event, no_progress, options) or { partial = err.msg().contains('download failed (18)') }
	assert partial && os.read_file(path)! == text[..5120]
	assert fetch_https_with('https://fixture/full', path, u64(text.len), true, false, event, no_progress, options)!
	assert os.read_file(path)! == text
	for maximum in [u64(0), u64(8192), u64(text.len)] {
		os.write_file(path, '')!
		mut refused := false
		fetch_https_with('https://fixture/oversized', path, maximum, false, false, pkgprotocol.Progress{}, no_progress, options) or { refused = err.msg().contains('authenticated size limit') }
		assert refused && os.file_size(path) <= maximum && text.starts_with(os.read_file(path)!)
		output_no_children()
	}
	os.write_file(path, 'old')!
	assert !fetch_https_with('https://fixture/empty', path, 0, false, false, pkgprotocol.Progress{}, no_progress, options)! && os.file_size(path) == 0
	for phase in ['written', 'finished'] {
		os.mkdir(work + '/' + phase)!
		for kind in ['alias', 'grow'] {
			target := work + '/' + phase + '/' + kind
			os.write_file(target, '')!; os.write_file(work + '/outside', 'preserved')!
			os.setenv('VINIX_OUTPUT_TARGET', target, true)
			mut message := ''
			fetch_https_with('https://fixture/full', target, u64(text.len), false, false, event, no_progress, HttpsOutputOptions{ program: fixture, checkpoint: output_mutate }) or { message = err.msg() }
			assert message.contains('destination changed') && os.read_file(work + '/outside')! == 'preserved', phase + '/' + kind + ': ' + message
			output_no_children()
		}
	}
	os.setenv('VINIX_OUTPUT_TARGET', path, true)
	mut original := OutputLimit{}
	assert C.getrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0
	limited := OutputLimit{ current: 32, maximum: original.maximum }
	assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&limited)) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0 }
	for _ in 0 .. 64 {
		os.write_file(path, '')!
		assert !fetch_https_with('https://fixture/full', path, u64(text.len), false, false, event, no_progress, options)! && os.read_file(path)! == text
		for program in [fixture, work + '/missing-program'] {
			mut refused := false
			fetch_https_with('https://fixture/failure', path, u64(text.len), true, false, event, no_progress, HttpsOutputOptions{ program: program }) or {
				refused = err.msg().contains('download failed')
				message := err.msg(); unsafe { message.free(); err.free() }
			}
			assert refused && os.read_file(path)! == text
			output_no_children()
		}
	}
}

fn output_guard_change(phase string, path string) ! {
	if phase != os.getenv('VINIX_OUTPUT_GUARD_PHASE') || os.exists(path + '.before') { return }
	os.write_file(path + '.before', os.read_file(path)!)!
	match os.getenv('VINIX_OUTPUT_GUARD_KIND') {
		'link' { assert C.link(path.str, (path + '.linked').str) == 0 }
		'grow' { mut file := os.open_append(path)!; file.write_string('extra')!; file.close() }
		else {
			os.rename(path, path + '.saved')!
			match os.getenv('VINIX_OUTPUT_GUARD_KIND') {
				'alias' { os.symlink(os.getenv('VINIX_OUTPUT_OUTSIDE'), path)! }
				'fifo' { assert C.mkfifo(path.str, 0o600) == 0 }
				'ordinary' { os.write_file(path, 'replacement')! }
				'missing' {}
				else { panic('unknown HTTPS output mutation') }
			}
		}
	}
}

fn output_guard_event(event pkgprotocol.Progress) {
	phase := if event.current == event.total { 'finish' } else if event.current == 0 || event.current == 4096 { 'start' } else { 'middle' }
	output_guard_change(phase, os.getenv('VINIX_OUTPUT_TARGET')) or { panic(err) }
}

fn test_https_output_callbacks_refuse_changes_before_further_writes_and_after_final_progress() {
	work := output_work()!; defer { os.rmdir_all(work) or {} }
	fixture := output_fixture(work)!
	text := '0123456789abcdef'.repeat(16384)
	os.write_file(work + '/source', text)!; os.write_file(work + '/calls', '')!
	os.write_file(work + '/outside', 'preserved')!; os.chmod(work + '/outside', 0o640)!
	for key, value in {'VINIX_OUTPUT_SOURCE': work + '/source', 'VINIX_OUTPUT_CALLS': work + '/calls',
		'VINIX_OUTPUT_OUTSIDE': work + '/outside'} { os.setenv(key, value, true) }
	defer { for key in ['VINIX_OUTPUT_SOURCE', 'VINIX_OUTPUT_CALLS', 'VINIX_OUTPUT_OUTSIDE',
		'VINIX_OUTPUT_TARGET', 'VINIX_OUTPUT_GUARD_PHASE', 'VINIX_OUTPUT_GUARD_KIND'] { os.unsetenv(key) } }
	for phase in ['opened', 'written', 'finished', 'start', 'middle', 'finish'] {
		for kind in ['link', 'grow', 'alias', 'fifo', 'ordinary', 'missing'] {
			for resume in [false, true] {
				name := phase + '-' + kind + '-' + resume.str()
				path := work + '/' + name
				prefix := if resume { text[..4096] } else { 'retained prefix' }
				os.write_file(path, prefix)!
				os.setenv('VINIX_OUTPUT_TARGET', path, true); os.setenv('VINIX_OUTPUT_GUARD_PHASE', phase, true)
				os.setenv('VINIX_OUTPUT_GUARD_KIND', kind, true)
				calls := os.read_file(work + '/calls')!.split_into_lines().len
				mut message := ''
				fetch_https_with('https://fixture/slow', path, u64(text.len), resume, false,
					pkgprotocol.Progress{ phase: 'download', package: 'app', path: 'payload', total: u64(text.len) },
					output_guard_event, HttpsOutputOptions{ program: fixture, checkpoint: output_guard_change }) or { message = err.msg() }
				assert os.exists(path + '.before'), name + ': mutation was not reached'
				before := os.read_file(path + '.before')!
				after := os.read_file(path + if kind == 'link' { '.linked' } else if kind == 'grow' { '' } else { '.saved' })!
				preserved := after == before + if kind == 'grow' { 'extra' } else { '' }
				println('HTTPS GUARD ' + name + ' refused=' + message.contains('destination changed').str() + ' preserved=' + preserved.str())
				assert message.contains('destination changed') && preserved, name + ': ' + message
				if phase in ['opened', 'start'] { assert before == prefix }
				if phase == 'opened' { assert os.read_file(work + '/calls')!.split_into_lines().len == calls }
				if phase in ['written', 'middle'] { assert before.len < text.len && text.starts_with(before) }
				assert os.read_file(work + '/outside')! == 'preserved' && os.lstat(work + '/outside')!.mode & 0o777 == 0o640
				if kind == 'alias' { assert os.is_link(path) }
				if kind == 'ordinary' { assert os.read_file(path)! == 'replacement' }
				if kind == 'missing' { assert !os.exists(path) }
				output_no_children()
				// Retire only the deliberate mutation, then retry the retained prefix.
				if kind == 'link' { os.rm(path + '.linked')! }
				else if kind == 'grow' { mut file := os.open_file(path, 'w', 0o600)!; file.write_string(before)!; file.close() }
				else { if os.exists(path) || os.is_link(path) { os.rm(path)! }; os.rename(path + '.saved', path)! }
				os.setenv('VINIX_OUTPUT_GUARD_PHASE', '', true)
				fetch_https_with('https://fixture/full', path, u64(text.len), resume, false, pkgprotocol.Progress{}, no_progress,
					HttpsOutputOptions{ program: fixture })!
				assert os.read_file(path)! == text
				output_no_children()
			}
		}
	}
	println('HTTPS GUARD 72 fresh/resumed checkpoint and progress mutations stop before further writes; replacements survive and restored output retries PASS')
}

fn output_guard_flush(fd int) int {
	marker := os.getenv('VINIX_OUTPUT_GUARD_FLUSH')
	mode := os.getenv('VINIX_OUTPUT_GUARD_FLUSH_MODE')
	first := !os.exists(marker)
	os.write_file(marker, if first { 'once' } else { 'retried' }) or { panic(err) }
	if mode == 'interrupted' && first { C.errno = C.EINTR; return -1 }
	if mode == 'failure' { C.errno = C.EIO; return -1 }
	if mode == 'link' {
		path := os.getenv('VINIX_OUTPUT_TARGET')
		assert C.link(path.str, (path + '.linked').str) == 0
	}
	return C.fsync(fd)
}

fn test_https_output_flush_retries_interruptions_preserves_failures_and_retires_descriptors() {
	work := output_work()!; defer { os.rmdir_all(work) or {} }
	fixture := output_fixture(work)!
	text := 'payload'.repeat(8192)
	os.write_file(work + '/source', text)!; os.write_file(work + '/calls', '')!
	for key, value in {'VINIX_OUTPUT_SOURCE': work + '/source', 'VINIX_OUTPUT_CALLS': work + '/calls',
		'VINIX_OUTPUT_TARGET': work + '/target', 'VINIX_OUTPUT_GUARD_FLUSH': work + '/flushed'} { os.setenv(key, value, true) }
	defer { for key in ['VINIX_OUTPUT_SOURCE', 'VINIX_OUTPUT_CALLS', 'VINIX_OUTPUT_TARGET',
		'VINIX_OUTPUT_GUARD_FLUSH', 'VINIX_OUTPUT_GUARD_FLUSH_MODE'] { os.unsetenv(key) } }
	mut original := OutputLimit{}
	assert C.getrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0
	limit := OutputLimit{ current: 32, maximum: original.maximum }
	assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&limit)) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0 }
	for _ in 0 .. 16 {
		for mode in ['interrupted', 'failure', 'link'] {
			for resume in [false, true] {
				os.write_file(work + '/target', text[..4096])!
				if os.exists(work + '/flushed') { os.rm(work + '/flushed')! }
				os.setenv('VINIX_OUTPUT_GUARD_FLUSH_MODE', mode, true)
				mut message := ''
				resumed := fetch_https_with('https://fixture/full', work + '/target', u64(text.len), resume, false,
					pkgprotocol.Progress{}, no_progress, HttpsOutputOptions{ program: fixture, flush: output_guard_flush }) or { message = err.msg(); false }
				assert os.read_file(work + '/target')! == text
				if mode == 'interrupted' { assert message == '' && resumed == resume && os.read_file(work + '/flushed')! == 'retried' }
				else if mode == 'failure' { assert message.contains('cannot flush captured download destination') && os.read_file(work + '/flushed')! == 'once' }
				else { assert message.contains('destination changed') && os.read_file(work + '/target.linked')! == text; os.rm(work + '/target.linked')! }
				output_no_children()
				// A successful empty resumed response still flushes the retained file.
				assert fetch_https_with('https://fixture/full', work + '/target', u64(text.len), true, false,
					pkgprotocol.Progress{}, no_progress, HttpsOutputOptions{ program: fixture })!
				assert os.read_file(work + '/target')! == text
				output_no_children()
			}
		}
	}
	println('HTTPS GUARD 96 fresh/resumed flush interruption, storage failure and link-change cycles preserve partials and retire children/descriptors under a 32-descriptor limit PASS')
}
