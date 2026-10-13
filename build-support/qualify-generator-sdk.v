// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import crypto.sha256
import json2
import os
import sourcecommand

fn checked(argv []string, environment map[string]string, log string) !sourcecommand.Output {
	result := sourcecommand.capture_full(argv, environment, 600, 32 * 1024 * 1024, cachecli.cancelled)!
	text := result.stdout + result.stderr
	os.write_file(log, text)!
	if result.status != 0 || ['retrying with', ': fn ', 'V panic:', 'runtime error:', 'ERROR: AddressSanitizer'].any(text.contains(it)) {
		return error('generator SDK qualification failed: ' + log)
	}
	return result
}

fn qualify() ! {
	if os.args.len != 4 { return error('expected COMPILER NEW_EVIDENCE arm|x86|san') }
	compiler, work, profile := os.args[1], os.args[2], os.args[3]
	if os.exists(work) || profile !in ['arm', 'x86', 'san'] { return error('expected new evidence and profile') }
	os.mkdir_all(work + '/tmp')!
	root := os.real_path(os.dir(@FILE) + '/..')
	mut environment := os.environ()
	for key, value in {'V': compiler, 'VTMP': work + '/tmp', 'TMPDIR': work + '/tmp',
		'V_C_ERROR_BUG_REPORT_DISABLED': '1', 'V_MACOS_V3_NO_FALLBACK': '1',
		'ASAN_OPTIONS': 'detect_leaks=0:detect_stack_use_after_return=1:abort_on_error=1',
		'UBSAN_OPTIONS': 'halt_on_error=1:print_stacktrace=1'} { environment[key] = value }
	mut flags := []string{}
	if profile == 'x86' { flags = ['-arch', 'amd64', '-cflags', '--target=x86_64-apple-macos13', '-ldflags', '--target=x86_64-apple-macos13'] }
	if profile == 'san' { flags = ['-gc', 'none', '-cflags', '-fsanitize=address,undefined', '-cflags', '-fno-omit-frame-pointer', '-cflags', '-O1', '-ldflags', '-fsanitize=address,undefined'] }
	mut receipts := []json2.Any{}
	for name, path in {'checker': 'build-support/generator-sdk.v', 'model': 'build-support/generatorsdk/core_test.v',
		'smoke-qualifier': 'tests/native-python-smoke/qualify.v'} {
		checked([compiler, '-nocache', '-cc', '/usr/bin/clang', ...flags, '-path', '@vlib|' + root + '/build-support|' + root + '/tests/native-python-smoke|@vmodules', '-o', work + '/' + name, root + '/' + path], environment, work + '/' + name + '-build.log')!
		receipts << json2.Any({'name': json2.Any(name), 'sha256': json2.Any(sha256.sum(os.read_bytes(work + '/' + name)!).hex())})
	}
	checked([work + '/model'], environment, work + '/model.log')!
	checked([work + '/checker', '--help'], environment, work + '/help.log')!
	missing := sourcecommand.capture_full([work + '/checker', 'qemu', '/missing-sdk/bin/python3'], environment, 10, 65536, cachecli.cancelled)!
	assert missing.status == 1 && missing.stderr.contains('missing')
	checked([work + '/smoke-qualifier', compiler, work + '/smoke', profile], environment, work + '/smoke.log')!
	for path in ['scripts/build-qemu-input.sh', 'build-support/virglrenderer/build-host.sh', 'build-support/generator-sdk'] {
		checked(['/bin/bash', '-n', root + '/' + path], environment, work + '/syntax-' + os.file_name(path) + '.log')!
	}
	mut inputs := map[string]json2.Any{}
	for path in ['build-support/generator-sdk.v', 'build-support/generator-sdk', 'build-support/generatorsdk/core.v',
		'build-support/generatorsdk/core_test.v', 'build-support/qualify-generator-sdk.v',
		'tests/native-python-smoke/pysmoke/entry.v', 'tests/native-python-smoke/pysmoke/callback_test.v',
		'tests/native-python-smoke/qualify.v', 'scripts/build-developer-tools-aarch64.sh',
		'tests/developer-tools/smoke.sh', 'scripts/build-qemu-input.sh', 'build-support/virglrenderer/build-host.sh'] {
		inputs[path] = json2.Any(sha256.sum(os.read_bytes(root + '/' + path)!).hex())
	}
	os.write_file(work + '/qualification.json', json2.encode(json2.Any({'status': json2.Any('PASS'),
		'profile': json2.Any(profile), 'receipts': json2.Any(receipts), 'inputs': json2.Any(inputs),
		'limits': json2.Any('Native SDK metadata/layout and CPython reference/lifecycle models; cold host builds and real ARM/x86 musl guest ELF builds/export checks. No interpreter, upstream generator, target ELF or Vinix guest executed. SDK metadata declares prerequisites; it does not establish runtime importability.')}), prettify: true) + '\n')!
	println('PASS generator SDK and developer-tools probe ' + profile)
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	qualify() or { eprintln(err); exit(1) }
}
