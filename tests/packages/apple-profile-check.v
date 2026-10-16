// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import time

struct AppleCheck { name string seconds f64 }
struct AppleCheckReceipt { format int = 1 scope string compiler string compiler_sha256 string checks []AppleCheck }

fn apple_check_task(name string, arguments []string, work string) !AppleCheck {
	mut child := os.new_process(arguments[0]); child.set_args(arguments[1..]); child.set_redirect_stdio_merged()
	started := time.now(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/' + name + '.txt', output)!
	if code != 0 { return error(name + ' failed (' + code.str() + '):\n' + output) }
	println(name + ' PASS')
	return AppleCheck{ name: name, seconds: f64(time.since(started).milliseconds()) / 1000.0 }
}

fn apple_checks() ! {
	if os.args.len != 2 { return error('usage: apple-profile-check NEW_WORK_DIRECTORY; set V to a reviewed compiler') }
	work := os.abs_path(os.args[1])
	if os.exists(work) || os.is_link(work) { return error('qualification work directory must be new') }
	os.mkdir_all(work)!
	v := os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!
	repository := os.dir(os.dir(os.dir(@FILE)))
	flags := ['-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts']
	mut checks := []AppleCheck{}
	cli := work + '/vinix-package'
	checks << apple_check_task('cli-compile', [v, ...flags, '-o', cli, repository + '/tools/packages/main.v'], work)!
	os.setenv('VINIX_PACKAGE_APPLE_CLI', cli, true)
	for name in ['apple_headers', 'apple_profile', 'elf_profile', 'catalog', 'composition'] {
		binary := work + '/' + name
		checks << apple_check_task(name + '-compile', [v, ...flags, '-o', binary, repository + '/tools/packages/pkgcore/' + name + '_test.v'], work)!
		checks << apple_check_task(name + '-run', [binary], work)!
	}
	for name in ['apple_headers', 'apple_profile'] {
		binary := work + '/' + name + '-sanitize'
		checks << apple_check_task(name + '-sanitize-compile', [v, ...flags, '-cc', 'clang', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer',
			'-ldflags', '-fsanitize=address,undefined', '-o', binary, repository + '/tools/packages/pkgcore/' + name + '_test.v'], work)!
		os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true); os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
		checks << apple_check_task(name + '-sanitize-run', [binary], work)!
	}
	os.write_file(work + '/qualification.json', json2.encode(AppleCheckReceipt{
		scope: 'host publisher/CLI, structural Mach-O/ELF and XML/binary plist admission; target execution has a separate Apple runtime receipt',
		compiler: v, compiler_sha256: sha256.sum(os.read_bytes(v)!).hex(), checks: checks }) + '\n')!
	println('Apple publisher profile: fifteen host build/test checks PASS')
}

fn main() { apple_checks() or { eprintln(err); exit(1) } }
