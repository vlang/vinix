// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import time

struct WineCheck {
	name string
	seconds f64
}

struct WineCheckReceipt {
	format int = 1
	scope string
	compiler string
	compiler_sha256 string
	checks []WineCheck
}

fn wine_check_task(name string, arguments []string, work string) !WineCheck {
	mut child := os.new_process(arguments[0])
	child.set_args(arguments[1..])
	child.set_redirect_stdio_merged()
	started := time.now()
	child.run()
	output := child.stdout_slurp()
	child.wait()
	code := child.code
	child.close()
	os.write_file(work + '/' + name + '.txt', output)!
	if code != 0 { return error(name + ' failed (' + code.str() + '):\n' + output) }
	println(name + ' PASS')
	return WineCheck{ name: name, seconds: f64(time.since(started).milliseconds()) / 1000.0 }
}

fn wine_checks() ! {
	if os.args.len != 2 { return error('usage: wine-profile-check NEW_WORK_DIRECTORY; set V to a reviewed compiler') }
	work := os.abs_path(os.args[1])
	if os.exists(work) || os.is_link(work) { return error('qualification work directory must be new') }
	os.mkdir_all(work)!
	v := os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!
	repository := os.dir(os.dir(os.dir(@FILE)))
	flags := ['-nocache', '-no-skip-unused', '-gc', 'none', '-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts']
	mut checks := []WineCheck{}
	cli := work + '/vinix-package'
	checks << wine_check_task('cli-compile', [v, ...flags, '-o', cli, repository + '/tools/packages/main.v'], work)!
	os.setenv('VINIX_PACKAGE_WINE_CLI', cli, true)
	for name in ['wine_profile', 'elf_profile', 'catalog', 'composition'] {
		binary := work + '/' + name
		checks << wine_check_task(name + '-compile', [v, ...flags, '-o', binary, repository + '/tools/packages/pkgcore/' + name + '_test.v'], work)!
		checks << wine_check_task(name + '-run', [binary], work)!
	}
	os.write_file(work + '/qualification.json', json2.encode(WineCheckReceipt{
		scope: 'host publisher/CLI, structural PE/ELF fixtures; no Wine execution',
		compiler: v, compiler_sha256: sha256.sum(os.read_bytes(v)!).hex(), checks: checks }) + '\n')!
	println('Wine publisher profile: nine host build/test checks PASS; runtime API qualification remains separate')
}

fn main() {
	wine_checks() or { eprintln(err); exit(1) }
}
