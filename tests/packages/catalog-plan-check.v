// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import time

struct PlanCheck { name string seconds f64 }
struct PlanReceipt { format int = 1 scope string compiler string compiler_sha256 string checks []PlanCheck }

fn plan_task(name string, argv []string, work string) !PlanCheck {
	mut child := os.new_process(argv[0]); child.set_args(argv[1..]); child.set_redirect_stdio_merged()
	started := time.now(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/' + name + '.txt', output)!
	if code != 0 { return error(name + ' failed (' + code.str() + '):\n' + output) }
	println(name + ' PASS')
	return PlanCheck{ name: name, seconds: f64(time.since(started).milliseconds()) / 1000.0 }
}

fn plan_checks() ! {
	if os.args.len != 2 { return error('usage: catalog-plan-check NEW_WORK_DIRECTORY; set V to a reviewed compiler') }
	work := os.abs_path(os.args[1])
	if os.exists(work) || os.is_link(work) { return error('qualification work directory must be new') }
	os.mkdir_all(work)!
	v := os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!
	repository := os.dir(os.dir(os.dir(@FILE)))
	flags := ['-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts']
	mut checks := []PlanCheck{}
	cli := work + '/vinix-package'
	checks << plan_task('cli-compile', [v, ...flags, '-o', cli, repository + '/tools/packages/main.v'], work)!
	os.setenv('VINIX_PACKAGE_COMPOSITION_CLI', cli, true); os.setenv('VINIX_PACKAGE_APPLE_CLI', cli, true)
	for name in ['catalog_plan', 'catalog', 'catalog_decode', 'composition', 'composition_ownership', 'native_profile', 'sqlite_profile', 'ffmpeg_profile',
		'wine_profile', 'apple_profile', 'release', 'publisher_schema'] {
		binary := work + '/' + name
		checks << plan_task(name + '-compile', [v, ...flags, '-o', binary, repository + '/tools/packages/pkgcore/' + name + '_test.v'], work)!
		checks << plan_task(name + '-run', [binary], work)!
	}
	checks << plan_task('distribution-cli-compile', [v, ...flags, '-o', work + '/distribution-cli', repository + '/tests/packages/distribution-cli.v'], work)!
	checks << plan_task('distribution-cli-run', [work + '/distribution-cli', cli], work)!
	checks << plan_task('tracked-compile', [v, ...flags, '-d', 'track_heap', '-o', work + '/tracked', repository + '/tools/packages/pkgcore/catalog_plan_test.v'], work)!
	checks << plan_task('tracked-run', [work + '/tracked'], work)!
	for name in ['catalog_plan', 'catalog'] {
		binary := work + '/' + name + '-sanitize'
		checks << plan_task(name + '-sanitize-compile', [v, ...flags, '-cc', 'clang', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer',
			'-ldflags', '-fsanitize=address,undefined', '-o', binary, repository + '/tools/packages/pkgcore/' + name + '_test.v'], work)!
		os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true); os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
		checks << plan_task(name + '-sanitize-run', [binary], work)!
	}
	assert checks.len == 33
	os.write_file(work + '/qualification.json', json2.encode(PlanReceipt{ compiler: v,
		compiler_sha256: sha256.sum(os.read_bytes(v)!).hex(), checks: checks,
		scope: 'catalog metadata/disk-budget plan ownership, 1792 warmed tracked success/refusal attempts, independent closeable results, original encoding/budget compatibility, five publisher profiles and signed CLI regressions, planning/catalog sanitizers; acquisition and shared filesystem helpers have separate lifetime scopes' }) + '\n')!
	println('Catalog workspace planning: thirty-three host build/test checks PASS')
}

fn main() { plan_checks() or { eprintln(err); exit(1) } }
