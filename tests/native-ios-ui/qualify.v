// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import crypto.sha256
import json2
import os
import sourcecommand

fn checked(argv []string, log string) !sourcecommand.Output {
	result := sourcecommand.capture_full(argv, os.environ(), -1, 32 * 1024 * 1024, cachecli.cancelled)!
	text := result.stdout + result.stderr
	os.write_file(log, text)!
	if result.status != 0 || ['retrying with', ': fn ', 'V panic:', 'runtime error:',
		'ERROR: AddressSanitizer'].any(text.contains(it)) {
		return error('iOS UI qualification failed: ' + log)
	}
	return result
}

fn run() ! {
	if os.args.len != 4 { return error('expected COMPILER NEW_EVIDENCE arm|x86|san') }
	compiler, work, profile := os.args[1], os.args[2], os.args[3]
	if os.exists(work) || profile !in ['arm', 'x86', 'san'] {
		return error('expected new evidence directory and profile')
	}
	os.mkdir_all(work)!
	os.mkdir(work + '/tmp')!
	os.setenv('VTMP', work + '/tmp', true)
	os.setenv('TMPDIR', work + '/tmp', true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0:detect_stack_use_after_return=1:abort_on_error=1', true)
	os.setenv('UBSAN_OPTIONS', 'halt_on_error=1:print_stacktrace=1', true)
	root := os.real_path(os.dir(@FILE) + '/../..')
	mut flags := []string{}
	if profile == 'x86' {
		flags = ['-arch', 'amd64', '-cflags', '--target=x86_64-apple-macos13', '-ldflags',
			'--target=x86_64-apple-macos13']
	}
	if profile == 'san' {
		flags = ['-gc', 'none', '-cflags', '-fsanitize=address,undefined', '-cflags',
			'-fno-omit-frame-pointer', '-cflags', '-O1', '-ldflags', '-fsanitize=address,undefined']
	}
	mut receipts := []json2.Any{}
	for name, path in {
		'main':  root + '/tests/native-ios-ui/main.v'
		'tests': root + '/tests/native-ios-ui/test-ui.v'
		'qmp':   root + '/tools/qmpclient/core_test.v'
		'shims': root + '/tests/native-launcher-tools/test-shims.v'
	} {
		checked([compiler, '-nocache', '-cc', '/usr/bin/clang', ...flags, '-o', work + '/' + name,
			path], work + '/' + name + '-build.log')!
		receipts << json2.Any({
			'name':   json2.Any(name)
			'sha256': json2.Any(sha256.sum(os.read_bytes(work + '/' + name)!).hex())
		})
		println('PASS cold iOS UI build ' + profile + '/' + name)
		flush_stdout()
	}
	checked([work + '/tests', work + '/cases'], work + '/tests.log')!
	assert os.read_file(work + '/cases/passed')! == 'PASS\n'
	checked([work + '/qmp'], work + '/qmp.log')!
	checked([work + '/shims', work + '/shims-cases'], work + '/shims.log')!
	for mode in ['uikit', 'game2048'] {
		checked([work + '/main', mode], work + '/' + mode + '-real.log')!
	}
	for mode in ['uikit', 'game2048', 'desktop'] {
		checked([work + '/main', mode, '--help'], work + '/' + mode + '-help.log')!
	}
	for argv in [['desktop', '--app', 'unknown'], ['desktop', '--desktop', '/missing-desktop'],
		['game2048', '--cycles', 'nan'], ['game2048', '--cycles', '2147483648'],
		['uikit', '--unknown']] {
		result := sourcecommand.capture_full([work + '/main', ...argv], os.environ(), -1, 1024 * 1024, cachecli.cancelled)!
		assert result.status == 2, result.str()
	}
	for relative in ['build/ios/run-ios-host', 'build/ios/objc/Calculator.app/Calculator',
		'build/ios/2048/NumberTileGame.app/NumberTileGame'] {
		receipts << json2.Any({
			'input':  json2.Any(relative)
			'sha256': json2.Any(sha256.sum(os.read_bytes(root + '/' + relative)!).hex())
		})
	}
	os.write_file(work + '/qualification.json', json2.encode(json2.Any({
		'status':   json2.Any('PASS')
		'profile':  json2.Any(profile)
		'receipts': json2.Any(receipts)
	}),
		prettify: true
	) + '\n')!
	println('PASS iOS UI qualification ' + profile)
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	run() or {
		eprintln(err)
		exit(1)
	}
}
