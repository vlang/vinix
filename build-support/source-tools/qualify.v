// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import crypto.sha256
import json2
import os
import sourcecommand

fn checked(argv []string, environment map[string]string, log string) !sourcecommand.Output {
	r := sourcecommand.capture_full(argv, environment, 300, 16 * 1024 * 1024, cachecli.cancelled)!
	text := r.stdout + r.stderr
	os.write_file(log, text)!
	if r.status != 0 || ['retrying with', ': fn ', 'V panic:', 'runtime error:', 'ERROR: AddressSanitizer'].any(text.contains(it)) {
		return error('source-tool qualification failed: ' + log)
	}
	return r
}

fn qualify() ! {
	if os.args.len != 4 { return error('expected COMPILER NEW_EVIDENCE arm|x86|san') }
	compiler, work, profile := os.args[1], os.args[2], os.args[3]
	if os.exists(work) || profile !in ['arm', 'x86', 'san'] { return error('expected new evidence and profile') }
	os.mkdir_all(work)!
	os.mkdir(work + '/tmp')!
	root := os.real_path(os.dir(@FILE) + '/../..')
	mut environment := os.environ()
	for key, value in {'V': compiler, 'VINIX_V_COMPILER': compiler, 'VTMP': work + '/tmp',
		'TMPDIR': work + '/tmp', 'V_C_ERROR_BUG_REPORT_DISABLED': '1', 'V_MACOS_V3_NO_FALLBACK': '1',
		'ASAN_OPTIONS': 'detect_leaks=0:detect_stack_use_after_return=1:abort_on_error=1',
		'UBSAN_OPTIONS': 'halt_on_error=1:print_stacktrace=1'} { environment[key] = value }
	mut flags := []string{}
	mut wrapper_flags := ''
	if profile == 'x86' {
		flags = ['-arch', 'amd64', '-cflags', '--target=x86_64-apple-macos13', '-ldflags', '--target=x86_64-apple-macos13']
		wrapper_flags = '-arch amd64 -cflags --target=x86_64-apple-macos13 -ldflags --target=x86_64-apple-macos13 '
	}
	if profile == 'san' {
		flags = ['-gc', 'none', '-cflags', '-fsanitize=address,undefined', '-cflags', '-fno-omit-frame-pointer',
			'-cflags', '-O1', '-ldflags', '-fsanitize=address,undefined']
		wrapper_flags = '-gc none -cflags -fsanitize=address,undefined -cflags -fno-omit-frame-pointer -ldflags -fsanitize=address,undefined '
	}
	mut receipts := []json2.Any{}
	for name, path in {'main': root + '/build-support/source-tools/main.v',
		'utility': root + '/desktop/tools/native-utility-source.v',
		'check': root + '/build-support/source-tools/check.v',
		'utility-test': root + '/desktop/tools/utilitysource/core_test.v'} {
		output := work + '/' + name
		checked([compiler, '-nocache', '-cc', '/usr/bin/clang', ...flags, '-o', output, path], environment, output + '-build.log')!
		receipts << json2.Any({'name': json2.Any(name), 'sha256': json2.Any(sha256.sum(os.read_bytes(output)!).hex())})
	}
	checked([work + '/check', work + '/fixtures', root], environment, work + '/checks.log')!
	checked([work + '/utility-test'], environment, work + '/utility-test.log')!
	checked([work + '/main', '--help'], environment, work + '/help.log')!
	// Compare the existing merge profile against its unchanged, frozen V source.
	legacy := work + '/reference'
	os.mkdir_all(legacy + '/utilitysource')!
	base := '/Users/alex/.cache/vinix-source-tools-native-20261013/originals/'
	os.write_file(legacy + '/utilitysource/core.v', os.read_file(base + 'desktop/tools/utilitysource/core.v.source')!)!
	os.write_file(legacy + '/main.v', os.read_file(base + 'desktop/tools/native-utility-source.v.source')!)!
	checked([compiler, '-nocache', '-cc', '/usr/bin/clang', ...flags, '-o', work + '/reference-utility', legacy], environment, work + '/reference-build.log')!
	checked([work + '/reference-utility', 'merge', root, work + '/reference-merged.v'], environment, work + '/reference-merge.log')!
	checked([work + '/utility', 'merge', root, work + '/native-merged.v'], environment, work + '/native-merge.log')!
	assert os.read_file(work + '/reference-merged.v')! == os.read_file(work + '/native-merged.v')!
	// Existing shell suites still invoke their original tests and assertions.
	wrapper := work + '/v-compiler'
	os.write_file(wrapper, '#!/bin/sh\nif [ "$1" = version ]; then exec "' + compiler + '" version; fi\nexec /usr/bin/env -u CFLAGS -u LDFLAGS "' + compiler + '" -nocache -cc /usr/bin/clang ' + wrapper_flags + '"$@"\n')!
	os.chmod(wrapper, 0o755)!
	environment['V'] = wrapper
	environment['VINIX_V_COMPILER'] = wrapper
	// Failure must not skip the next independently staged test file.
	os.mkdir(work + '/driver-tests')!
	os.write_file(work + '/driver-tests/a_test.v', 'module main\nfn test_failure() { assert false }\n')!
	os.write_file(work + '/driver-tests/b_test.v', 'module main\nfn test_after_failure() { println("SOURCE_DRIVER_SECOND_TEST_RAN") }\n')!
	failed := sourcecommand.capture_full([work + '/main', 'test-directory', wrapper, work + '/driver-tests'], environment, 300, 4 * 1024 * 1024, cachecli.cancelled)!
	os.write_file(work + '/driver-failure.log', failed.stdout + failed.stderr)!
	assert failed.status != 0 && failed.stdout.contains('SOURCE_DRIVER_SECOND_TEST_RAN')
	os.mkdir(work + '/empty-tests')!
	empty := sourcecommand.capture_full([work + '/main', 'test-directory', wrapper, work + '/empty-tests'], environment, 10, 1024 * 1024, cachecli.cancelled)!
	os.write_file(work + '/driver-empty.log', empty.stdout + empty.stderr)!
	assert empty.status != 0 && empty.stderr.contains('no V tests in ')
	for suite in ['tests/clock-control/run-host.sh', 'tests/mapped-writeback/run-host.sh', 'tests/private-pages/run-host.sh', 'tests/m1-deploy/run.sh'] {
		checked(['/bin/bash', root + '/' + suite], environment, work + '/' + suite.split('/')[1] + '.log')!
	}
	for file_pages in ['0', '1'] {
		for paging in ['0', '1'] {
			if file_pages == '0' && paging == '0' { continue }
			environment['VINIX_FILE_PAGES_HOST'] = file_pages
			environment['VINIX_PAGING_HOST'] = paging
			checked(['/bin/sh', root + '/tests/private-pages/run-host.sh'], environment, work + '/private-pages-' + file_pages + '-' + paging + '.log')!
		}
	}
	for path in ['desktop/tools/test-activity.sh', 'desktop/tools/test-settings.sh',
		'desktop/tools/test-utility-parity.sh', 'desktop/tools/test-window-experience.sh',
		'tests/clock-control/run-host.sh', 'tests/mapped-writeback/run-host.sh',
		'tests/private-pages/run-host.sh', 'tests/m1-deploy/run.sh'] {
		checked(['/bin/bash', '-n', root + '/' + path], environment, work + '/' + os.file_name(os.dir(path)) + '-' + os.file_name(path) + '-syntax.log')!
	}
	os.write_file(work + '/qualification.json', json2.encode(json2.Any({'status': json2.Any('PASS'),
		'profile': json2.Any(profile), 'receipts': json2.Any(receipts),
		'default_merge_sha256': json2.Any(sha256.hexhash(os.read_file(work + '/native-merged.v')!)),
		'limits': json2.Any('Native source behavior and unchanged clock/security-policy, ext2 mapping, private/file/paging host models plus disposable M1 deployment. Frozen V default merge matches byte-for-byte. No Python, live ESP, GUI application, Vinix kernel/guest or new kernel lifetime claim. Desktop UI tests are preserved; this qualification checks their preparation, not complete UI suites.')}), prettify: true) + '\n')!
	println('PASS native source-tool qualification ' + profile)
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	qualify() or { eprintln(err); exit(1) }
}
