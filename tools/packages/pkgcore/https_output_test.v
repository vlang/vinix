// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time
import tools.packages.pkgprotocol

#include <sys/resource.h>
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int
struct OutputLimit { current u64 maximum u64 }

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
