module main
import json2
import os
import time
import tools.packages.pkgcore
struct Result { name string code int seconds f64 }
fn task(name string, argv []string, work string) !Result {
	mut child := os.new_process(argv[0]); child.set_args(argv[1..]); child.set_redirect_stdio_merged()
	started := time.now(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/' + name + '.txt', output)!
	if code != 0 || output.contains(': fn test_') || output.contains('V panic:') { print(output); return error(name + ' failed') }
	println(name + ' PASS')
	return Result{ name: name, code: code, seconds: f64(time.since(started).milliseconds()) / 1000.0 }
}
fn main() {
	work := os.real_path(os.dir(@FILE)); phase := os.args[1]; v := os.real_path('build/package-release-work/v-toolchain/v')
	os.setenv('V', v, true); os.setenv('VFLAGS', '-nocache', true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true); os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true); os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
	os.unsetenv('VINIX_PACKAGE_IMAGE_CONFIG'); os.unsetenv('VINIX_PACKAGE_IMAGE_REPOSITORIES')
	flags := ['-keepc', '-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|.|tools/accounts']
	mut results := []Result{}
	if phase == 'core' {
		for name in ['image_repositories', 'image_configuration', 'release', 'mirror', 'repository_signature', 'copy', 'policy', 'catalog']! {
			results << task(name + '-compile', [v, ...flags, '-o', work + '/' + name, 'tools/packages/pkgcore/' + name + '_test.v'], work)!
			results << task(name + '-run', [work + '/' + name], work)!
		}
	} else if phase == 'asan' {
		results << task('asan-compile', [v, ...flags, '-cc', 'clang', '-d', 'no_segfault_handler', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer',
			'-ldflags', '-fsanitize=address,undefined', '-o', work + '/asan', 'tools/packages/pkgcore/image_repositories_test.v'], work)!
		results << task('asan-run', [work + '/asan'], work)!
	} else if phase == 'cache' {
		results << task('cache-compile', [v, '-nocache', '-no-skip-unused', '-o', work + '/cache', 'build-support/cachekey/desktop_test.v'], work)!
		results << task('cache-run', [work + '/cache'], work)!
	} else if phase == 'cli' {
		results << task('cli-compile', [v, ...flags, '-o', work + '/vinix-package', 'tools/packages/main.v'], work)!
		results << task('distribution-cli-compile', [v, ...flags, '-o', work + '/distribution-cli', 'tests/packages/distribution-cli.v'], work)!
		results << task('distribution-cli-run', [work + '/distribution-cli', work + '/vinix-package'], work)!
	} else if phase == 'controller' {
		results << task('controller-compile', [v, ...flags, '-path', '@vlib|@vmodules|.|tools/accounts|tests/hardware-platform', '-o', work + '/controller', 'tests/packages/native-catalog-check.v'], work)!
		for mode in ['legacy', 'image', 'software']! {
			results << task('list-' + mode, [work + '/controller', ...if mode == 'legacy' { []string{} } else { ['--' + mode] }, '--list'], work)!
		}
	} else if phase == 'stage' {
		for name in ['preflight-root', 'preflight-data', 'preflight-workspace', 'preflight-bundle']! { if os.exists(work + '/' + name) { os.rmdir_all(work + '/' + name)! } }
		if os.exists(work + '/preflight-seed') { os.rm(work + '/preflight-seed')! }
		results << task('stage-compile', [v, ...flags, '-o', work + '/package-stage', 'tools/packages/stage.v'], work)!
		root := work + '/preflight-root'; os.mkdir(root)!
		defer { os.rmdir_all(root) or {} }
		key := pkgcore.keygen(work + '/preflight-seed')!
		config := work + '/preflight-config.json'
		os.write_file(config, json2.encode(pkgcore.Config{ architecture: 'aarch64', repositories: [pkgcore.Repository{ id: 'native',
			url: 'file://' + pkgcore.image_repositories_path + '/native', public_key: key }] }))!
		os.mkdir_all(work + '/preflight-data/share')!; os.write_file(work + '/preflight-data/share/data', 'preflight')!
		os.write_file(work + '/preflight-manifest.json', json2.encode(pkgcore.Package{ id: 'data', name: 'Data', description: 'Preflight data', architecture: 'all', version: '1.0.0', license: 'MIT', kind: 'data' }))!
		pkgcore.pack(work + '/preflight-manifest.json', work + '/preflight-data', work + '/preflight-workspace')!
		pkgcore.publish_release(work + '/preflight-workspace', 'native', work + '/preflight-seed', 1, time.now().unix() + 3600, work + '/preflight-bundle/native')!
		base := [work + '/package-stage', '--arch', 'aarch64', '--staging', root, '--config', config, '--cc', 'vinix-missing-compiler']
		for name in ['option-refusal', 'environment-refusal', 'option-precedence', 'empty-option']! {
			os.setenv('VINIX_PACKAGE_IMAGE_REPOSITORIES', work + '/absent', true)
			mut argv := base.clone()
			match name {
				'option-refusal' { argv << ['--repositories', work + '/absent'] }
				'option-precedence' { argv << ['--repositories', work + '/preflight-bundle'] }
				'empty-option' { argv << ['--repositories', ''] }
				else {}
			}
			started := time.now(); r := os.exec(argv)
			os.write_file(work + '/' + name + '.txt', r.output)!
			assert r.exit_code == 1 && os.ls(root)!.len == 0, r.output
			assert r.output.contains('os: failed to find executable') == (name == 'option-precedence'), r.output
			results << Result{ name: name, code: 0, seconds: f64(time.since(started).milliseconds()) / 1000.0 }
		}
	} else { panic('phase') }
	os.write_file(work + '/results-' + phase + '.json', json2.encode(results) + '\n')!
}
