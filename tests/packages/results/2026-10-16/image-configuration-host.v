module main
import json2
import os
import time
struct Result { name string code int seconds f64 }
fn task(name string, program string, args []string, work string) !Result {
	mut child := os.new_process(program); child.set_args(args); child.set_redirect_stdio_merged()
	started := time.now(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/' + name + '.txt', output)!
	if code != 0 || output.contains(': fn test_') || output.contains('V panic:') { print(output); return error(name + ' failed: ' + code.str()) }
	println(name + ' PASS')
	return Result{ name: name, code: code, seconds: f64(time.since(started).milliseconds()) / 1000.0 }
}
fn main() {
	work := os.real_path(os.dir(@FILE)); phase := os.args[1]; v := os.real_path('build/package-release-work/v-toolchain/v')
	os.setenv('V', v, true); os.setenv('VFLAGS', '-nocache', true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true); os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true); os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
	os.unsetenv('VINIX_PACKAGE_IMAGE_CONFIG')
	flags := ['-keepc', '-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|.|tools/accounts']
	mut results := []Result{}
	if phase == 'core' {
		for name in ['image_configuration', 'configuration', 'keygen', 'atomic', 'administration', 'service', 'native_profile', 'release', 'catalog', 'distribution'] {
			results << task(name + '-compile', v, [...flags, '-o', work + '/' + name, 'tools/packages/pkgcore/' + name + '_test.v'], work)!
			results << task(name + '-run', work + '/' + name, [], work)!
		}
	} else if phase == 'image-final' {
		results << task('image-final-compile', v, [...flags, '-o', work + '/image-final', 'tools/packages/pkgcore/image_configuration_test.v'], work)!
		results << task('image-final-run', work + '/image-final', [], work)!
	} else if phase == 'asan' {
		results << task('asan-compile', v, [...flags, '-cc', 'clang', '-d', 'no_segfault_handler', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer',
			'-ldflags', '-fsanitize=address,undefined', '-o', work + '/asan', 'tools/packages/pkgcore/image_configuration_test.v'], work)!
		results << task('asan-run', work + '/asan', [], work)!
	} else if phase == 'cli' {
		results << task('package-cli-compile', v, [...flags, '-o', work + '/vinix-package', 'tools/packages/main.v'], work)!
		results << task('distribution-cli-compile', v, [...flags, '-o', work + '/distribution-cli', 'tests/packages/distribution-cli.v'], work)!
		results << task('distribution-cli-run', work + '/distribution-cli', [work + '/vinix-package'], work)!
		results << task('stage-compile', v, [...flags, '-o', work + '/package-stage', 'tools/packages/stage.v'], work)!
		results << task('distribution-driver-compile', v, [...flags, '-o', work + '/distribution-check', 'tests/packages/distribution-check.v'], work)!
	} else if phase == 'cache' {
		results << task('cache-compile', v, ['-nocache', '-no-skip-unused', '-o', work + '/cache-key', 'build-support/cachekey/desktop_test.v'], work)!
		results << task('cache-run', work + '/cache-key', [], work)!
	} else if phase == 'stage' {
		root := work + '/invalid-root'; os.mkdir(root)!
		source := work + '/invalid-config.json'; os.write_file(source, '{broken')!
		args := ['--arch', 'aarch64', '--staging', root, '--cc', 'vinix-missing-compiler']
		for from_environment in [false, true]! {
			if from_environment { os.setenv('VINIX_PACKAGE_IMAGE_CONFIG', source, true) }
			name := if from_environment { 'stage-environment-preflight' } else { 'stage-option-preflight' }
			mut child := os.new_process(work + '/package-stage')
			child.set_args(if from_environment { args } else { [...args, '--config', source] })
			child.set_redirect_stdio_merged(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
			os.write_file(work + '/' + name + '.txt', output)!
			assert code == 1 && !output.contains('vinix-missing-compiler') && output.contains('package staging:')
			assert os.ls(root)!.len == 0
			results << Result{ name: name, code: 0 }
		}
		os.rmdir(root)!; os.rm(source)!
	} else { panic('phase') }
	os.write_file(work + '/results-' + phase + '.json', json2.encode(results) + '\n')!
}
