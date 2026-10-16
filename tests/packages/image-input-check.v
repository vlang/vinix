// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import time

struct ImageInputResult { name string seconds f64 }
struct ImageInputReceipt { format int = 1 compiler string compiler_sha256 string scope string checks []ImageInputResult }

fn image_input_task(name string, argv []string, work string) !ImageInputResult {
	mut child := os.new_process(argv[0]); child.set_args(argv[1..]); child.set_redirect_stdio_merged()
	started := time.now(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/' + name + '.txt', output)!
	if code != 0 { return error(name + ' failed (' + code.str() + '):\n' + output) }
	println(name + ' PASS')
	return ImageInputResult{ name: name, seconds: f64(time.since(started).milliseconds()) / 1000.0 }
}

fn image_input_check() ! {
	if os.args.len != 2 { return error('usage: image-input-check NEW_WORK_DIRECTORY; set V to a reviewed compiler') }
	work := os.abs_path(os.args[1])
	if os.exists(work) || os.is_link(work) { return error('qualification work directory must be new') }
	os.mkdir_all(work)!
	v := os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!
	repository := os.dir(os.dir(os.dir(@FILE)))
	flags := ['-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts']
	mut checks := []ImageInputResult{}
	stage := work + '/stage'
	checks << image_input_task('stage-compile', [v, ...flags, '-o', stage, repository + '/tools/packages/stage.v'], work)!
	os.setenv('VINIX_PACKAGE_STAGE_CHECK_CLI', stage, true)
	for name in ['image_check', 'image_repositories', 'image_configuration', 'release', 'mirror', 'policy', 'catalog', 'publisher_schema'] {
		binary := work + '/' + name
		checks << image_input_task(name + '-compile', [v, ...flags, '-o', binary, repository + '/tools/packages/pkgcore/' + name + '_test.v'], work)!
		checks << image_input_task(name + '-run', [binary], work)!
	}
	checks << image_input_task('image_check-sanitize-compile', [v, ...flags, '-cc', 'clang', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer',
		'-ldflags', '-fsanitize=address,undefined', '-o', work + '/image-check-sanitize', repository + '/tools/packages/pkgcore/image_check_test.v'], work)!
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true); os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
	checks << image_input_task('image_check-sanitize-run', [work + '/image-check-sanitize'], work)!
	cli := work + '/vinix-package'
	checks << image_input_task('cli-compile', [v, ...flags, '-o', cli, repository + '/tools/packages/main.v'], work)!
	checks << image_input_task('distribution-cli-compile', [v, ...flags, '-o', work + '/distribution-cli', repository + '/tests/packages/distribution-cli.v'], work)!
	checks << image_input_task('distribution-cli-run', [work + '/distribution-cli', cli], work)!
	assert checks.len == 22
	os.write_file(work + '/qualification.json', json2.encode(ImageInputReceipt{ compiler: v, compiler_sha256: sha256.sum(os.read_bytes(v)!).hex(),
		scope: 'release image input check: reproducible configuration/bundle summaries, trust/policy, exact metadata digests, architecture/license/firmware counts, unique object bytes, publish/preserve/none decisions, retained-state and destination refusals, source capture independence and real compiler-free stage CLI; bundle/configuration/release/mirror/policy/catalog/schema regressions, sanitizer and signed CLI maintenance; no whole-plan memory or full image-build acceptance claim', checks: checks }) + '\n')!
	println('Image input preflight: twenty-two host build/test checks PASS')
}

fn main() { image_input_check() or { eprintln(err); exit(1) } }
