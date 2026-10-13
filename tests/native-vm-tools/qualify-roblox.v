// SPDX-License-Identifier: MIT
@[has_globals]
module main

import cachecli
import crypto.sha256
import gamehost
import json2
import os
import sourcecommand

fn checked(argv []string, env map[string]string, log string) ! {
	result := sourcecommand.capture_full(argv, env, -1, 64 * 1024 * 1024, cachecli.cancelled)!
	text := result.stdout + result.stderr
	os.write_file(log, text)!
	if result.status != 0 || ['retrying with', ': fn ', 'V panic:', 'runtime error:',
		'ERROR: AddressSanitizer'].any(text.contains(it)) {
		return error('Roblox qualification failed; see ' + log)
	}
}

fn run() ! {
	if os.args.len != 4 { return error('Usage: qualify-roblox COMPILER NEW_EVIDENCE arm|x86|san') }
	compiler, work, profile := os.args[1], os.args[2], os.args[3]
	if profile !in ['arm', 'x86', 'san'] { return error('unknown build profile') }
	if os.exists(work) { return error('qualification requires a new evidence directory') }
	gamehost.mkdir(work)!
	root := os.real_path(os.dir(@FILE) + '/../..')
	mut env := os.environ()
	env['V_MACOS_V3_NO_FALLBACK'] = '1'
	env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	env['ASAN_OPTIONS'] = 'detect_leaks=0:detect_stack_use_after_return=1:abort_on_error=1'
	env['UBSAN_OPTIONS'] = 'halt_on_error=1:print_stacktrace=1'
	mut flags := []string{}
	if profile == 'x86' {
		flags = ['-arch', 'amd64', '-cflags', '-arch x86_64', '-ldflags', '-arch x86_64']
	}
	if profile == 'san' {
		flags = ['-gc', 'none', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer -O1',
			'-ldflags', '-fsanitize=address,undefined']
	}
	mut programs := []json2.Any{}
	for name, source in {
		'main':  'main.v'
		'tests': 'test-roblox.v'
	} {
		executable := work + '/' + name
		checked([compiler, '-nocache', '-cc', '/usr/bin/clang', ...flags, '-o', executable,
			root + '/tests/native-vm-tools/' + source], env, work + '/' + name + '-build.log')!
		programs << json2.Any({
			'name':   json2.Any(name)
			'sha256': json2.Any(sha256.sum(os.read_bytes(executable)!).hex())
		})
		println('PASS cold Roblox build ' + profile + '/' + name)
		flush_stdout()
	}
	checked([work + '/tests', work + '/main', work + '/cases'], env, work + '/tests.log')!
	assert os.read_file(work + '/cases/passed')! == 'PASS\n'
	checked([work + '/main', 'roblox-windows', '--help'], env, work + '/help.log')!
	os.write_file(work + '/qualification.json', json2.encode(json2.Any({
		'status':   json2.Any('PASS')
		'profile':  json2.Any(profile)
		'programs': json2.Any(programs)
	}),
		prettify: true
	) + '\n')!
	println('PASS Roblox qualification ' + profile)
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	run() or {
		eprintln(err)
		exit(1)
	}
}
