// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import cpythonapi
import crypto.sha256
import json2
import os
import sourcecommand

fn checked(argv []string, environment map[string]string, log string) !sourcecommand.Output {
	result := sourcecommand.capture_full(argv, environment, -1, 32 * 1024 * 1024, cachecli.cancelled)!
	output := result.stdout + result.stderr
	os.write_file(log, output)!
	if result.status != 0 || ['retrying with', ': fn ', 'V panic:', 'runtime error:',
		'ERROR: AddressSanitizer'].any(output.contains(it)) {
		return error('installer qualification failed: ' + log)
	}
	return result
}

fn run() ! {
	if os.args.len != 5 {
		return error('expected COMPILER NEW_EVIDENCE arm|x86|san SDK_FRAMEWORK_DATA')
	}
	compiler, work, profile, sdk := os.args[1], os.args[2], os.args[3], os.args[4]
	if os.exists(work) || profile !in ['arm', 'x86', 'san'] {
		return error('expected new evidence and profile')
	}
	os.mkdir_all(work)!
	os.mkdir(work + '/tmp')!
	os.setenv('VTMP', work + '/tmp', true)
	os.setenv('TMPDIR', work + '/tmp', true)
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
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
		'main':            root + '/installer/macos/native-auto/main.v'
		'core':            root + '/installer/macos/asahipolicy/core_test.v'
		'bridge':          root + '/installer/macos/asahipolicy/bridge_test.v'
		'ui':              root + '/installer/macos/installer_test.v'
		'smoke-ownership': root + '/tests/native-python-smoke/pysmoke/callback_test.v'
	} {
		checked([compiler, '-nocache', '-cc', '/usr/bin/clang', '-gc', 'none', ...flags, '-path',
			'@vlib|@vmodules|' + root + '/third_party', '-o', work + '/' + name, path], os.environ(), work + '/' + name + '-build.log')!
		receipts << json2.Any({
			'name':   json2.Any(name)
			'sha256': json2.Any(sha256.sum(os.read_bytes(work + '/' + name)!).hex())
		})
		println('PASS cold installer build ' + profile + '/' + name)
		flush_stdout()
	}
	for name in ['core', 'bridge', 'ui', 'smoke-ownership'] {
		checked([work + '/' + name], os.environ(), work + '/' + name + '.log')!
	}
	checked([work + '/main', '--help'], os.environ(), work + '/help.log')!
	mut environment := os.environ()
	environment['VINIX_TARGET_DISK'] = 'disk0oops'
	environment['VINIX_SPACE_BYTES'] = '32000000000'
	for args in [[]string{}, ['--unknown']] {
		result := sourcecommand.capture_full([work + '/main', ...args], environment, -1, 1024 * 1024, cachecli.cancelled)!
		assert result.status == if args.len == 0 { 1 } else { 2 }, result.str()
		os.write_file(work + '/guard-' + args.len.str() + '.log', result.stdout + result.stderr)!
	}
	for arch in ['arm64', 'x86_64'] {
		result := checked(['/usr/bin/nm', '-arch', arch, '-gU', sdk], os.environ(), work + '/sdk-' + arch + '-symbols.log')!
		mut names := map[string]bool{}
		for line in result.stdout.split_into_lines() {
			fields := line.fields()
			if fields.len >= 3 { names[fields.last()] = true }
		}
		for name in cpythonapi.symbols {
			assert names['_' + name], arch + '/' + name
		}
	}
	for path in ['installer/macos/install-vinix.sh', 'installer/macos/test.sh',
		'scripts/build-macos-installer.sh'] {
		checked(['/bin/sh', '-n', root + '/' + path], os.environ(), work + '/' + os.file_name(path) + '-syntax.log')!
	}
	os.write_file(work + '/qualification.json', json2.encode(json2.Any({
		'status':      json2.Any('PASS')
		'profile':     json2.Any(profile)
		'receipts':    json2.Any(receipts)
		'sdk_sha256':  json2.Any(sha256.sum(os.read_bytes(sdk)!).hex())
		'sdk_exports': json2.Any(cpythonapi.symbols.len)
		'limits':      json2.Any('Native policy/reference/callback and existing ui2 tests only. Shutdown and delay are replaced by V recorders. Both SDK Mach-O slices inspected as data. No SDK initialization, Python execution, authentication, APFS mutation, installation, shutdown, or Vinix guest executed.')
	}), prettify: true) + '\n')!
	println('PASS installer qualification ' + profile)
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	run() or {
		eprintln(err)
		exit(1)
	}
}
