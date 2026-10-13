// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import crypto.sha256
import json2
import os
import sourcecommand

fn checked(argv []string, log string) ! {
	r := sourcecommand.capture_full(argv, os.environ(), -1, 16 * 1024 * 1024, cachecli.cancelled)!
	text := r.stdout + r.stderr
	os.write_file(log, text)!
	if r.status != 0 || ['retrying with', ': fn ', 'V panic:', 'runtime error:', 'ERROR: AddressSanitizer', 'FAIL'].any(text.contains(it)) { return error('ext2 host qualification failed: ' + log) }
}

fn run() ! {
	if os.args.len != 4 { return error('expected COMPILER NEW_EVIDENCE arm|x86|san') }
	compiler, work, profile := os.args[1], os.args[2], os.args[3]
	if profile !in ['arm', 'x86', 'san'] || os.exists(work) { return error('expected new directory and arm|x86|san') }
	os.mkdir_all(work)!
	os.mkdir(work + '/tmp')!
	os.setenv('VTMP', work + '/tmp', true)
	os.setenv('TMPDIR', work + '/tmp', true)
	root := os.real_path(os.dir(@FILE) + '/../..')
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0:detect_stack_use_after_return=1:abort_on_error=1', true)
	os.setenv('UBSAN_OPTIONS', 'halt_on_error=1:print_stacktrace=1', true)
	mut flags := []string{}
	// The native host command passes compiler flag values as intact argv entries.
	if profile == 'x86' { flags = ['-arch', 'amd64', '-cflags', '--target=x86_64-apple-macos13', '-ldflags', '--target=x86_64-apple-macos13'] }
	if profile == 'san' { flags = ['-gc', 'none', '-cflags', '-fsanitize=address,undefined', '-cflags', '-fno-omit-frame-pointer', '-cflags', '-O1', '-ldflags', '-fsanitize=address,undefined'] }
	checked([compiler, '-nocache', '-cc', '/usr/bin/clang', ...flags, '-o', work + '/host', root + '/tests/ext2-xattr/host.v'], work + '/build.log')!
	checked([work + '/host', '--compiler', compiler, '--state-dir', work + '/fixture', '--', '-nocache', '-cc', '/usr/bin/clang', ...flags], work + '/tests.log')!
	assert os.read_file(work + '/tests.log')!.contains('4 passed, 4 total')
	checked([work + '/host', '--help'], work + '/help.log')!
	mut generated := []json2.Any{}
	for directory in ['ext2', 'fs', 'errno', 'memory', 'resource', 'posix_acl', 'time'] {
		for file in os.ls(work + '/fixture/' + directory)!.sorted().filter(it.ends_with('.v')) {
			path := directory + '/' + file
			generated << json2.Any({'path': json2.Any(path), 'sha256': json2.Any(sha256.sum(os.read_bytes(work + '/fixture/' + path)!).hex())})
		}
	}
	os.write_file(work + '/qualification.json', json2.encode(json2.Any({'status': json2.Any('PASS'), 'profile': json2.Any(profile), 'host_sha256': json2.Any(sha256.sum(os.read_bytes(work + '/host')!).hex()), 'generated': json2.Any(generated)}), prettify: true) + '\n')!
	println('PASS four production ext2/copy/ACL host suites ' + profile)
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	run() or { eprintln(err); exit(1) }
}
