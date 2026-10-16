// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import time

struct ImageExportResult { name string seconds f64 }
struct ImageExportReceipt { format int = 1 compiler string compiler_sha256 string scope string checks []ImageExportResult }

fn image_export_task(name string, argv []string, work string) !ImageExportResult {
	mut child := os.new_process(argv[0]); child.set_args(argv[1..]); child.set_redirect_stdio_merged()
	started := time.now(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/' + name + '.txt', output)!
	if code != 0 { return error(name + ' failed (' + code.str() + '):\n' + output) }
	println(name + ' PASS')
	return ImageExportResult{ name: name, seconds: f64(time.since(started).milliseconds()) / 1000.0 }
}

fn image_export_check() ! {
	if os.args.len != 2 { return error('usage: image-export-check NEW_WORK_DIRECTORY; set V to a reviewed compiler') }
	work := os.abs_path(os.args[1])
	if os.exists(work) || os.is_link(work) { return error('qualification work directory must be new') }
	os.mkdir_all(work)!
	v := os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!
	repository := os.dir(os.dir(os.dir(@FILE)))
	flags := ['-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts']
	mut checks := []ImageExportResult{}
	stage := work + '/stage'
	checks << image_export_task('stage-compile', [v, ...flags, '-o', stage, repository + '/tools/packages/stage.v'], work)!
	os.setenv('VINIX_PACKAGE_STAGE_CHECK_CLI', stage, true)
	checks << image_export_task('desktop-cache-compile', [v, ...flags, '-o', work + '/desktop-cache', repository + '/build-support/cachekey/desktop_test.v'], work)!
	checks << image_export_task('desktop-cache-run', [work + '/desktop-cache'], work)!
	for name in ['image_applications', 'image_check', 'image_repositories', 'image_configuration', 'deployment', 'resolve_search', 'release', 'mirror', 'policy', 'catalog', 'publisher_schema', 'atomic_new'] {
		binary := work + '/' + name
		checks << image_export_task(name + '-compile', [v, ...flags, '-o', binary, repository + '/tools/packages/pkgcore/' + name + '_test.v'], work)!
		checks << image_export_task(name + '-run', [binary], work)!
	}
	checks << image_export_task('image_applications-sanitize-compile', [v, ...flags, '-cc', 'clang', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer',
		'-ldflags', '-fsanitize=address,undefined', '-o', work + '/image-applications-sanitize', repository + '/tools/packages/pkgcore/image_applications_test.v'], work)!
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true); os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
	checks << image_export_task('image_applications-sanitize-run', [work + '/image-applications-sanitize'], work)!
	cli := work + '/vinix-package'
	checks << image_export_task('cli-compile', [v, ...flags, '-o', cli, repository + '/tools/packages/main.v'], work)!
	checks << image_export_task('distribution-cli-compile', [v, ...flags, '-o', work + '/distribution-cli', repository + '/tests/packages/distribution-cli.v'], work)!
	checks << image_export_task('distribution-cli-run', [work + '/distribution-cli', cli], work)!
	assert checks.len == 32
	os.write_file(work + '/qualification.json', json2.encode(ImageExportReceipt{ compiler: v, compiler_sha256: sha256.sum(os.read_bytes(v)!).hex(),
		scope: 'explicit image deployment export: exact canonical format-2 locks from signed app requirements, independent output/source digests, new-file preservation, captured image namespace exclusion, atomic failure/race cleanup and saved-file diagnostics, real compiler-free CLI and reviewed offline consumer; twelve package suites, desktop cache, ASan/UBSan and signed CLI maintenance; no full desktop, runtime or production catalog acceptance claim', checks: checks }) + '\n')!
	println('Image deployment export: thirty-two host build/test checks PASS')
}

fn main() { image_export_check() or { eprintln(err); exit(1) } }
