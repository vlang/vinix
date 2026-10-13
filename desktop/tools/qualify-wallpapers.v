// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import crypto.sha256
import json2
import os
import sourcecommand

fn checked(argv []string, env map[string]string, log string) !string {
	result := sourcecommand.capture_full(argv, env, -1, 16 * 1024 * 1024, cachecli.cancelled)!
	text := result.stdout + result.stderr
	os.write_file(log, text)!
	if result.status != 0 || ['retrying with', ': fn ', 'V panic:', 'runtime error:', 'ERROR: AddressSanitizer'].any(text.contains(it)) {
		return error('wallpaper qualification failed: ' + log)
	}
	return text
}

fn qualify(compiler string, captures string, work string, profile string, sdk string) ! {
	if profile !in ['arm', 'x86', 'san'] || os.exists(work) { return error('expected new evidence directory and arm|x86|san') }
	os.mkdir_all(work)!
	root := os.real_path(os.dir(@FILE))
	mut env := os.environ()
	env['V_MACOS_V3_NO_FALLBACK'] = '1'
	env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	env['ASAN_OPTIONS'] = 'detect_leaks=0:detect_stack_use_after_return=1:abort_on_error=1'
	env['UBSAN_OPTIONS'] = 'halt_on_error=1:print_stacktrace=1'
	mut flags := []string{}
	if profile == 'x86' {
		if sdk == '' { return error('x86 qualification requires its native JPEG SDK directory') }
		flags = ['-arch', 'amd64', '-d', 'wallpaper_jpeg_custom', '-cflags', '-arch x86_64 -I' + sdk + '/include', '-ldflags', '-arch x86_64 ' + sdk + '/lib/libturbojpeg.a']
	}
	if profile == 'san' { flags = ['-gc', 'none', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer -O1', '-ldflags', '-fsanitize=address,undefined'] }
	mut programs := []json2.Any{}
	for name, source in {'check': 'wallpaper-check.v', 'test': 'wallpaper-test.v', 'cli': 'fetch_wallpapers.v'} {
		checked([compiler, '-nocache', '-cc', '/usr/bin/clang', ...flags, '-o', work + '/' + name, root + '/' + source], env, work + '/' + name + '-build.log')!
		programs << json2.Any({'name': json2.Any(name), 'sha256': json2.Any(sha256.sum(os.read_bytes(work + '/' + name)!).hex())})
		println('PASS cold wallpaper ' + profile + '/' + name)
		flush_stdout()
	}
	checked([work + '/check', captures, work + '/pixels'], env, work + '/pixels.log')!
	checked([work + '/test', captures, work + '/cases'], env, work + '/cases.log')!
	for path in [work + '/pixels/passed', work + '/cases/passed'] { assert os.read_file(path)! == 'PASS\n' }
	os.mkdir(work + '/cache')!
	rows := json2.decode[[]json2.Any](os.read_file(captures + '/captures.json')!)!
	for row in rows { id := row.as_map()['id']!.int(); os.cp(captures + '/fixtures/' + id.str() + '.jpg', work + '/cache/' + id.str() + '.jpg')! }
	text := checked([work + '/cli', work + '/output', '--cache', work + '/cache'], env, work + '/cli.log')!
	assert text.contains('10 wallpaper(s)') && !text.contains('SKIPPED')
	mut index := ''
	mut sources := 'Wallpapers from Lorem Picsum (https://picsum.photos), which\nserves photographs from Unsplash under the Unsplash License\n(https://unsplash.com/license).\n\n'
	for row in rows {
		entry := row.as_map(); slot := entry['slot']!.int(); id := entry['id']!.int(); name := '0' + slot.str() + '.vwp'
		assert sha256.sum(os.read_bytes(work + '/output/' + name)!).hex() == entry['output_sha256']!.str()
		index += name + ' Photo ' + (slot + 1).str() + '\n'
		sources += name + '  https://picsum.photos/id/' + id.str() + '/1024/768\n'
	}
	assert os.read_file(work + '/output/index.txt')! == index && os.read_file(work + '/output/SOURCES.txt')! == sources
	assert checked([work + '/cli', '--help'], env, work + '/help.log')!.contains('Usage: fetch_wallpapers')
	bad := sourcecommand.capture_full([work + '/cli'], env, -1, 1024 * 1024, cachecli.cancelled)!
	os.write_file(work + '/guard.log', bad.stdout + bad.stderr)!
	assert bad.status == 2
	os.write_file(work + '/qualification.json', json2.encode(json2.Any({'status': json2.Any('PASS'), 'profile': json2.Any(profile), 'programs': json2.Any(programs)}), prettify: true) + '\n')!
	println('PASS wallpaper pixels, caches, downloads and whole CLI ' + profile)
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.args.len !in [5, 6] { exit(2) }
	qualify(os.args[1], os.args[2], os.args[3], os.args[4], if os.args.len == 6 { os.args[5] } else { '' }) or { eprintln(err); exit(1) }
}
