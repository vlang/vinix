// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import time

struct ImageApplicationsResult { name string seconds f64 }
struct ImageApplicationsReceipt { format int = 1 compiler string compiler_sha256 string scope string checks []ImageApplicationsResult }

fn image_applications_task(name string, argv []string, work string) !ImageApplicationsResult {
	mut child := os.new_process(argv[0]); child.set_args(argv[1..]); child.set_redirect_stdio_merged()
	started := time.now(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/' + name + '.txt', output)!
	if code != 0 { return error(name + ' failed (' + code.str() + '):\n' + output) }
	println(name + ' PASS')
	return ImageApplicationsResult{ name: name, seconds: f64(time.since(started).milliseconds()) / 1000.0 }
}

fn image_applications_check() ! {
	if os.args.len != 2 { return error('usage: image-applications-check NEW_WORK_DIRECTORY; set V to a reviewed compiler') }
	work := os.abs_path(os.args[1])
	if os.exists(work) || os.is_link(work) { return error('qualification work directory must be new') }
	os.mkdir_all(work)!
	v := os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!
	repository := os.dir(os.dir(os.dir(@FILE)))
	flags := ['-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts']
	mut checks := []ImageApplicationsResult{}
	stage := work + '/stage'
	checks << image_applications_task('stage-compile', [v, ...flags, '-o', stage, repository + '/tools/packages/stage.v'], work)!
	os.setenv('VINIX_PACKAGE_STAGE_CHECK_CLI', stage, true)
	for name in ['image_applications', 'image_check', 'image_repositories', 'image_configuration', 'deployment', 'resolve_search', 'release', 'mirror', 'policy', 'catalog', 'publisher_schema'] {
		binary := work + '/' + name
		checks << image_applications_task(name + '-compile', [v, ...flags, '-o', binary, repository + '/tools/packages/pkgcore/' + name + '_test.v'], work)!
		checks << image_applications_task(name + '-run', [binary], work)!
	}
	checks << image_applications_task('image_applications-sanitize-compile', [v, ...flags, '-cc', 'clang', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer',
		'-ldflags', '-fsanitize=address,undefined', '-o', work + '/image-applications-sanitize', repository + '/tools/packages/pkgcore/image_applications_test.v'], work)!
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true); os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
	checks << image_applications_task('image_applications-sanitize-run', [work + '/image-applications-sanitize'], work)!
	cli := work + '/vinix-package'
	checks << image_applications_task('cli-compile', [v, ...flags, '-o', cli, repository + '/tools/packages/main.v'], work)!
	checks << image_applications_task('distribution-cli-compile', [v, ...flags, '-o', work + '/distribution-cli', repository + '/tests/packages/distribution-cli.v'], work)!
	checks << image_applications_task('distribution-cli-run', [work + '/distribution-cli', cli], work)!
	assert checks.len == 28
	os.write_file(work + '/qualification.json', json2.encode(ImageApplicationsReceipt{ compiler: v, compiler_sha256: sha256.sum(os.read_bytes(v)!).hex(),
		scope: 'release-image advertised applications: signed bundled target candidates, joint runtime/dependency resolution, canonical independent format-2 deployment locks, app-kind/host/input/conflict refusals, unchanged image and normal/check CLI gates before compiler lookup; ordinary reviewed offline deployment and integrity verification, eleven core suites, sanitizer and signed CLI maintenance; structural app/runtime fixtures are never executed; no full graphical/runtime/catalog acceptance claim', checks: checks }) + '\n')!
	println('Image application preflight: twenty-eight host build/test checks PASS')
}

fn main() { image_applications_check() or { eprintln(err); exit(1) } }
