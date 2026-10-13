// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import crypto.sha256
import json2
import os
import sourcecommand

fn checked(argv []string, env map[string]string, log string) ! {
	r := sourcecommand.capture_full(argv, env, -1, 32 * 1024 * 1024, cachecli.cancelled)!
	text := r.stdout + r.stderr
	os.write_file(log, text)!
	if r.status != 0 || ['retrying with', ': fn ', 'V panic:', 'runtime error:',
		'ERROR: AddressSanitizer'].any(text.contains(it)) {
		return error('font qualification failed: ' + log)
	}
}

fn run() ! {
	if os.args.len != 6 { return error('expected COMPILER CAPTURES SDK NEW_EVIDENCE arm|x86|san') }
	compiler, captures, sdk, work, profile := os.args[1], os.args[2], os.args[3], os.args[4], os.args[5]
	if profile !in ['arm', 'x86', 'san'] || os.exists(work) {
		return error('expected new directory and arm|x86|san')
	}
	os.mkdir_all(work)!
	os.mkdir(work + '/tmp')!
	mut env := os.environ()
	env['VTMP'] = work + '/tmp'
	env['TMPDIR'] = work + '/tmp'
	env['V_MACOS_V3_NO_FALLBACK'] = '1'
	env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	env['ASAN_OPTIONS'] = 'detect_leaks=0:detect_stack_use_after_return=1:abort_on_error=1'
	env['UBSAN_OPTIONS'] = 'halt_on_error=1:print_stacktrace=1'
	env['VINIX_TEST_JAPANESE_SOURCE'] = captures + '/NotoSansJP-variable.ttf'
	root := os.real_path(os.dir(@FILE))
	mut flags := []string{}
	if profile == 'x86' {
		flags = ['-arch', 'amd64', '-cflags', '-arch x86_64', '-ldflags', '-arch x86_64']
	}
	if profile == 'san' {
		flags = ['-gc', 'none', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer -O1',
			'-ldflags', '-fsanitize=address,undefined']
	}
	includes := '-I' + sdk + '/include/freetype2 -I' + sdk + '/include/harfbuzz'
	libraries := sdk + '/lib/libharfbuzz-subset.a ' + sdk + '/lib/libharfbuzz.a ' + sdk + '/lib/libfreetype.a -lc++ -framework CoreText -framework CoreGraphics -framework CoreFoundation'
	mut programs := []json2.Any{}
	for name, source in {
		'generator': 'genfont.v'
		'atlas':     'font-atlas-check.v'
		'compare':   'font-compare.v'
		'tests':     'tests/test_font_data.v'
		'bindings':  'fontnative/binding_test.v'
		'policy':    'fonthost/policy_test.v'
		'driver':    'font-driver.v'
	} {
		checked([compiler, '-nocache', '-cc', '/usr/bin/clang', ...flags, '-d', 'font_sdk_custom',
			'-cflags', includes, '-ldflags', libraries, '-o', work + '/' + name, root + '/' + source], env, work + '/' + name + '-build.log')!
		programs << json2.Any({
			'name':   json2.Any(name)
			'sha256': json2.Any(sha256.sum(os.read_bytes(work + '/' + name)!).hex())
		})
		println('PASS cold fonts ' + profile + '/' + name)
		flush_stdout()
	}
	for name in ['bindings', 'policy'] {
		checked([work + '/' + name], env, work + '/' + name + '.log')!
	}
	checked([work + '/atlas', captures + '/captures/current.v.source'], env, work + '/atlas.log')!
	checked([work + '/generator', '--output', work + '/warm.v'], env, work + '/warm.log')!
	checked([work + '/compare', captures + '/captures/current.v.source', work + '/warm.v'], env, work + '/warm-compare.log')!
	checked([work + '/generator', '--update-japanese-subsets', '--japanese-source',
		captures + '/NotoSansJP-variable.ttf', '--japanese-font-dir', work + '/japanese', '--output',
		work + '/regenerated.v'], env, work + '/regenerate.log')!
	checked([work + '/compare', captures + '/captures/current.v.source', work + '/regenerated.v'], env, work + '/regenerated-compare.log')!
	env['VINIX_FONT_PREVIEW'] = work + '/preview.png'
	checked([work + '/tests', '--atlas', work + '/regenerated.v', '--japanese-font-dir',
		work + '/japanese'], env, work + '/tests.log')!
	env.delete('VINIX_FONT_PREVIEW')
	env['V'] = compiler
	env['VINIX_FONT_SDK'] = sdk
	checked([work + '/driver', 'generate', '--output', work + '/driver.v'], env, work + '/driver.log')!
	checked([work + '/compare', captures + '/captures/current.v.source', work + '/driver.v'], env, work + '/driver-compare.log')!
	checked([work + '/driver', 'generate', '--help'], env, work + '/help.log')!
	os.write_file(work + '/qualification.json', json2.encode(json2.Any({
		'status':   json2.Any('PASS')
		'profile':  json2.Any(profile)
		'programs': json2.Any(programs)
	}),
		prettify: true
	) + '\n')!
	println('PASS native font generation, regeneration, masks, tests, owners and driver ' + profile)
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	run() or {
		eprintln(err)
		exit(1)
	}
}
