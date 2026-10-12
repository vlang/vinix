// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import crypto.sha256
import gamehost
import json2
import os
import sourcecommand

fn checked(argv []string, environment map[string]string, log string) !sourcecommand.Output {
	result := sourcecommand.capture_full(argv, environment, -1, 64 * 1024 * 1024, cachecli.cancelled)!
	os.write_file(log, result.stdout + result.stderr)!
	if result.status != 0 || (result.stdout + result.stderr).contains('retrying with') || (result.stdout + result.stderr).contains(': fn ') || (result.stdout + result.stderr).contains('V panic:') || (result.stdout + result.stderr).contains('runtime error:') || (result.stdout + result.stderr).contains('ERROR: AddressSanitizer') {
		return error('native qualification failed: ' + argv.str() + '\n' + log)
	}
	return result
}

fn qualify(compiler string, work string, profile string) ! {
	root := os.real_path(os.dir(@FILE) + '/../..')
	gamehost.mkdir(work)!
	mut env := os.environ()
	env['V'] = compiler
	env['VINIX_V_COMPILER'] = compiler
	env['V_MACOS_V3_NO_FALLBACK'] = '1'
	env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	env['VINIX_AARCH64_SYSROOT'] = root + '/build-aarch64-userland/sysroot'
	env['ASAN_OPTIONS'] = 'detect_leaks=0:detect_stack_use_after_return=1:strict_string_checks=1:abort_on_error=1'
	env['UBSAN_OPTIONS'] = 'halt_on_error=1:print_stacktrace=1'
	mut flags := []string{}
	if profile == 'x86' { flags = ['-arch', 'amd64', '-cflags', '-arch x86_64', '-ldflags', '-arch x86_64'] }
	if profile == 'san' {
		flags = ['-gc', 'none', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer -O1',
			'-ldflags', '-fsanitize=address,undefined']
	}
	mut programs := []json2.Any{}
	for name, source in {
		'main':       root + '/tests/native-render-tools/main.v'
		'test-tools': root + '/tests/native-render-tools/test-tools.v'
		'core-spawn': root + '/tests/agx-fake-g17/agxhost/core_vm_test.v'
		'vm-owners':  root + '/tests/agx-fake-g17/agxhost/vm_test.v'
	} {
		executable := work + '/' + name
		checked([compiler, '-nocache', '-cc', '/usr/bin/clang', ...flags, '-o', executable, source], env, work + '/' + name + '-build.log')!
		programs << json2.Any({
			'program': json2.Any(name)
			'sha256':  json2.Any(sha256.sum(os.read_bytes(executable)!).hex())
		})
		if name in ['core-spawn', 'vm-owners'] {
			checked([executable], env, work + '/' + name + '-run.log')!
		}
		println('PASS cold native build ' + profile + '/' + name)
		flush_stdout()
	}
	fixture := work + '/test-tools'
	checked([fixture, 'policy',
		os.home_dir() + '/.cache/vinix-python-to-v/agx-vm-runner-20261008/policy-controls.jsonl.gz'], env, work + '/policy.log')!
	checked([fixture, 'recipes', work + '/recipes'], env, work + '/recipes.log')!
	checked([fixture, 'processes', work + '/processes'], env, work + '/processes.log')!
	// Actual cross compilation and linking; the downstream boot endpoint is controlled.
	checked([fixture, 'native-inputs', work + '/native-inputs'], env, work + '/native-inputs.log')!
	os.write_file(work + '/qualification.json', json2.encode({
		'status':          json2.Any('PASS')
		'profile':         json2.Any(profile)
		'programs':        json2.Any(programs)
		'compiler_sha256': json2.Any(sha256.sum(os.read_bytes(compiler)!).hex())
	}))!
	println('PASS full native qualification ' + profile)
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.args.len != 4 { exit(2) }
	qualify(os.args[1], os.args[2], os.args[3]) or {
		eprintln(err)
		exit(1)
	}
}
