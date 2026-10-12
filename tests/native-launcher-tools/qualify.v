// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import crypto.sha256
import gamehost
import json2
import os
import sourcecommand

fn checked(argv []string, env map[string]string, log string) !sourcecommand.Output {
	r := sourcecommand.capture_full(argv, env, -1, 64 * 1024 * 1024, cachecli.cancelled)!
	os.write_file(log, r.stdout + r.stderr)!
	text := r.stdout + r.stderr
	if r.status != 0 || text.contains('retrying with') || text.contains(': fn ') || text.contains('V panic:') || text.contains('runtime error:') || text.contains('ERROR: AddressSanitizer') {
		return error('launcher qualification failed: ' + argv.str() + '\n' + log)
	}
	return r
}

fn qualify(compiler string, work string, profile string) ! {
	root := os.real_path(os.dir(@FILE) + '/../..')
	gamehost.mkdir(work)!
	mut env := os.environ()
	env['V'] = compiler
	env['VINIX_V_COMPILER'] = compiler
	env['V_MACOS_V3_NO_FALLBACK'] = '1'
	env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	env['ASAN_OPTIONS'] = 'detect_leaks=0:detect_stack_use_after_return=1:strict_string_checks=1:abort_on_error=1'
	env['UBSAN_OPTIONS'] = 'halt_on_error=1:print_stacktrace=1'
	mut flags := []string{}
	if profile == 'x86' {
		flags = ['-arch', 'amd64', '-cflags', '-arch x86_64', '-ldflags', '-arch x86_64']
	}
	if profile == 'san' {
		flags = ['-gc', 'none', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer -O1',
			'-ldflags', '-fsanitize=address,undefined']
	}
	mut binaries := []json2.Any{}
	for name, source in {
		'main':       root + '/tests/native-launcher-tools/main.v'
		'shims':      root + '/tests/native-launcher-tools/test-shims.v'
		'tar-reader': root + '/build-support/tarstream/reader_test.v'
		'tar-writer': root + '/build-support/tarcore/stream_test.v'
		'builder':    root + '/tests/native-validation-tools/build-guest.v'
	} {
		executable := work + '/' + name
		checked([compiler, '-nocache', '-cc', '/usr/bin/clang', ...flags, '-o', executable, source], env, work + '/' + name + '-build.log')!
		binaries << json2.Any({
			'program': json2.Any(name)
			'sha256':  json2.Any(sha256.sum(os.read_bytes(executable)!).hex())
		})
		if name in ['tar-reader', 'tar-writer'] {
			checked([executable], env, work + '/' + name + '-run.log')!
		}
		println('PASS cold native launcher build ' + profile + '/' + name)
		flush_stdout()
	}
	checked([work + '/shims', work + '/shims-cases'], env, work + '/shims.log')!
	// Select the host ABI explicitly even when the controller runs under ASan.
	os.cp(os.executable(), work + '/model-cc')!
	os.chmod(work + '/model-cc', 0o755)!
	env['CC'] = work + '/model-cc'
	env['VINIX_LAUNCHER_MODEL_CC_TARGET'] = if profile == 'x86' { 'x86_64' } else { 'arm64' }
	for mode in ['vnc', 'venus'] {
		checked([work + '/main', mode, '--state-dir', work + '/' + mode], env, work + '/' + mode + '.log')!
		checked([work + '/main', mode, '--help'], env, work + '/' + mode + '-help.log')!
		rejected := sourcecommand.capture_full([work + '/main', mode, '--native', 'aarch64'], env, -1, 1024 * 1024, cachecli.cancelled)!
		assert rejected.status == 2
	}
	os.write_file(work + '/qualification.json', json2.encode({
		'status':   json2.Any('PASS')
		'profile':  json2.Any(profile)
		'binaries': json2.Any(binaries)
	},
		prettify: true
	))!
	println('PASS launcher models and native shims ' + profile)
}

fn main() {
	if os.file_name(os.executable()) == 'model-cc' {
		result := os.exec(['/usr/bin/clang', '-arch', os.getenv('VINIX_LAUNCHER_MODEL_CC_TARGET'),
			...os.args[1..]])
		print(result.output)
		exit(result.exit_code)
	}
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.args.len != 4 { exit(2) }
	qualify(os.args[1], os.args[2], os.args[3]) or {
		eprintln(err)
		exit(1)
	}
}
