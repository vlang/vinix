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
	result := sourcecommand.capture_full(argv, env, -1, 64 * 1024 * 1024, cachecli.cancelled)!
	text := result.stdout + result.stderr
	os.write_file(log, text)!
	if result.status != 0 || ['retrying with', ': fn ', 'V panic:', 'runtime error:',
		'ERROR: AddressSanitizer'].any(text.contains(it)) {
		return error('VM qualification failed: ' + argv.str() + '\n' + log)
	}
	return result
}

fn cross_cc() !int {
	root := os.real_path(os.dir(@FILE) + '/../..')
	sdk := root + '/build-amd64-desktop/initramfs-root'
	gccroot := sdk + '/usr/lib/gcc/x86_64-alpine-linux-musl'
	versions := os.ls(gccroot)!.filter(os.is_file(gccroot + '/' + it + '/libgcc.a')).sorted()
	gcc := gccroot + '/' + versions.last()
	args := os.args[1..]
	compiler := '/opt/homebrew/opt/llvm/bin/clang'
	resource := sourcecommand.capture_full([compiler, '--print-resource-dir'], os.environ(), -1, 1024 * 1024, cachecli.cancelled)!
	if resource.status != 0 { return error('cannot locate Clang SDK headers') }
	mut flags := [compiler, '--target=x86_64-linux-musl', '-nostdinc', '-isystem',
		resource.stdout.trim_space() + '/include', '-isystem', sdk + '/usr/include']
	if '-c' in args {
		flags << args
	} else {
		flags << ['-nostdlib', sdk + '/usr/lib/crt1.o', sdk + '/usr/lib/crti.o', gcc + '/crtbeginT.o',
			...args, '-L' + sdk + '/usr/lib', '-L' + gcc, '-lgcc_eh', '-lc', '-lgcc', '-lm',
			gcc + '/crtend.o', sdk + '/usr/lib/crtn.o', '-fuse-ld=lld']
	}
	result := sourcecommand.capture_full(flags, os.environ(), -1, 64 * 1024 * 1024, cachecli.cancelled)!
	print(result.stdout)
	eprint(result.stderr)
	return result.status
}

fn qualify(compiler string, work string, profile string) ! {
	root := os.real_path(os.dir(@FILE) + '/../..')
	gamehost.mkdir(work)!
	mut env := os.environ()
	env['V'] = compiler
	env['VINIX_V_COMPILER'] = compiler
	env['V_MACOS_V3_NO_FALLBACK'] = '1'
	env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	env['ASAN_OPTIONS'] = 'detect_leaks=0:detect_stack_use_after_return=1:abort_on_error=1'
	env['UBSAN_OPTIONS'] = 'halt_on_error=1:print_stacktrace=1'
	os.cp(os.executable(), work + '/musl-cc')!
	os.chmod(work + '/musl-cc', 0o755)!
	env['CC'] = '/opt/homebrew/opt/llvm/bin/clang'
	env['CC_AMD64'] = work + '/musl-cc'
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
		'main':   root + '/tests/native-vm-tools/main.v'
		'tests':  root + '/tests/native-vm-tools/test-tools.v'
		'eof':    root + '/tests/native-vm-tools/test-pointer-eof.v'
		'qmp':    root + '/tools/qmpclient/core_test.v'
		'reader': root + '/tests/native-launcher-tools/test-shims.v'
	} {
		executable := work + '/' + name
		checked([compiler, '-nocache', '-cc', '/usr/bin/clang', ...flags, '-o', executable, source], env, work + '/' + name + '-build.log')!
		programs << json2.Any({
			'name':   json2.Any(name)
			'sha256': json2.Any(sha256.sum(os.read_bytes(executable)!).hex())
		})
		println('PASS cold native VM build ' + profile + '/' + name)
		flush_stdout()
	}
	checked([work + '/tests', work + '/cases'], env, work + '/tests.log')!
	assert os.read_file(work + '/cases/passed')! == 'PASS\n'
	checked([work + '/eof', work + '/tests'], env, work + '/eof.log')!
	checked([work + '/qmp'], env, work + '/qmp.log')!
	checked([work + '/reader', work + '/reader-cases'], env, work + '/reader.log')!
	for mode in ['browser', 'activity', 'pointer'] {
		checked([work + '/main', mode, '--help'], env, work + '/' + mode + '-help.log')!
	}
	os.write_file(work + '/qualification.json', json2.encode(json2.Any({
		'status':   json2.Any('PASS')
		'profile':  json2.Any(profile)
		'programs': json2.Any(programs)
	}),
		prettify: true
	) + '\n')!
	println('PASS native VM qualification ' + profile)
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.file_name(os.executable()) == 'musl-cc' {
		exit(cross_cc() or {
			eprintln(err)
			1
		})
	}
	if os.args.len != 4 { exit(2) }
	qualify(os.args[1], os.args[2], os.args[3]) or {
		eprintln(err)
		exit(1)
	}
}
