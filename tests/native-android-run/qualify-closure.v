// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import crypto.sha256
import gamehost
import json2
import os
import sourcecommand

fn C.mkdtemp(&char) &char

fn checked(argv []string, env map[string]string, log string) ! {
	result := sourcecommand.capture_full(argv, env, -1, 64 * 1024 * 1024, cachecli.cancelled)!
	text := result.stdout + result.stderr
	os.write_file(log, text)!
	if result.status != 0 || ['retrying with', ': fn ', 'V panic:', 'runtime error:',
		'ERROR: AddressSanitizer'].any(text.contains(it)) {
		return error('Android closure qualification failed: ' + log)
	}
}

fn qualify(compiler string, work string, profile string, replay bool) ! {
	if profile !in ['arm', 'x86', 'san'] || (os.exists(work) && !replay) {
		return error('expected a new evidence directory and arm|x86|san')
	}
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
	retained := if replay { json2.decode[[]json2.Any](os.read_file(work + '/cold-builds.json')!)! } else { []json2.Any{} }
	for name, source in {
		'runner':      'tests/native-android-run/main.v'
		'primitives':  'tests/native-android-run/test-primitives.v'
		'prepare':     'tests/native-android-run/test-prepare.v'
		'session':     'tests/native-android-run/test-session.v'
		'interactive': 'tests/native-android-run/test-interactive.v'
		'tools':       'tests/native-android-tools/main.v'
		'files':       'tests/native-android-tools/test-runtime-files.v'
		'metadata':    'tests/native-android-tools/test-manifests.v'
	} {
		executable := work + '/' + name
		if replay {
			if !os.is_executable(executable) || !os.exists(work + '/' + name + '-build.log') {
				return error('missing successful cold build: ' + name)
			}
			matching := retained.filter(it.as_map()['name']!.str() == name)
			if matching.len != 1 || matching[0].as_map()['sha256']!.str() != sha256.sum(os.read_bytes(executable)!).hex() { return error('retained cold build changed: ' + name) }
		} else {
			checked([compiler, '-nocache', '-cc', '/usr/bin/clang', ...flags, '-o', executable,
				root + '/' + source], env, work + '/' + name + '-build.log')!
		}
		programs << json2.Any({
			'name':   json2.Any(name)
			'sha256': json2.Any(sha256.sum(os.read_bytes(executable)!).hex())
		})
		println('PASS ' + if replay { 'retained cold build ' } else { 'cold Android closure ' } + profile + '/' + name)
		flush_stdout()
	}
	if !replay { os.write_file(work + '/cold-builds.json', json2.encode(programs, prettify: true) + '\n')! }
	// Short, exclusive names retain the SDK Unix-socket path limit. Copy the
	// completed cases into evidence only after every process has retired.
	mut pattern := ('/tmp/android-closure.XXXXXX\x00').bytes()
	if C.mkdtemp(pattern.data) == unsafe { nil } { return os.error_posix() }
	cases := os.real_path(pattern.bytestr().all_before('\x00'))
	defer { gamehost.remove(cases) or {} }
	for name in ['primitives', 'prepare', 'session', 'files', 'metadata'] {
		checked([work + '/' + name, cases + '/' + name], env, work + '/' + name + '.log')!
		assert os.read_file(cases + '/' + name + '/passed')! == 'PASS\n'
	}
	checked([work + '/interactive', '--state-dir', cases + '/interactive', '-v'], env, work + '/interactive.log')!
	for mode in ['run', 'input', 'screenshot', 'roblox-build', 'interactive-tests'] {
		checked([work + '/runner', mode, '--help'], env, work + '/' + mode + '-help.log')!
	}
	for mode in ['build', 'art-bootclasspath', 'compile-runtime', 'run-runtime-vm', 'test-runtime-v'] {
		checked([work + '/tools', mode, root + '/build-support/android', '--help'], env, work + '/' + mode + '-help.log')!
	}
	gamehost.copy_tree(cases, work + '/cases', false)!
	os.write_file(work + '/qualification.json', json2.encode(json2.Any({
		'status':   json2.Any('PASS')
		'profile':  json2.Any(profile)
		'programs': json2.Any(programs)
	}),
		prettify: true
	) + '\n')!
	println('PASS Android bridge closure ' + profile)
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.args.len !in [4, 5] { exit(2) }
	if os.args.len == 5 && os.args[4] != '--recheck-cold-builds' { exit(2) }
	qualify(os.args[1], os.args[2], os.args[3], os.args.len == 5) or {
		eprintln(err)
		exit(1)
	}
}
