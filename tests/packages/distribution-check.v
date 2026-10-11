// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn run(program string, arguments []string) ! {
	mut process := os.new_process(program)
	process.set_args(arguments)
	process.wait()
	code := process.code
	process.close()
	if code != 0 { return error('${program} failed with status ${code}') }
}

fn check() ! {
	repository := os.dir(os.dir(os.dir(@FILE)))
	v := os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!
	temporary := os.getenv_opt('VINIX_PACKAGE_TEST_WORK') or { os.temp_dir() }
	work := temporary + '/vinix-distribution-check-' + os.getpid().str()
	os.mkdir_all(work + '/software')!
	defer { os.rmdir_all(work) or {} }
	run(v, ['test', repository + '/tools/packages/pkgcore'])!
	run(v, ['-gc', 'none', '-manualfree', 'test', repository + '/desktop/packagecore'])!
	run(v, ['-gc', 'none', '-o', work + '/vinix-package', repository + '/tools/packages/main.v'])!
	run(work + '/vinix-package', ['--help'])!
	run(v, ['-gc', 'none', '-manualfree', '-o', work + '/cli-check', repository + '/tests/packages/distribution-cli.v'])!
	run(work + '/cli-check', [work + '/vinix-package'])!
	os.cp(repository + '/desktop/software_app.v', work + '/software/software_app.v')!
	os.cp(repository + '/tests/packages/software_fixture.v', work + '/software/main.v')!
	modules := os.getenv_opt('VINIX_PACKAGE_TEST_UI2') or { repository + '/build/vmodules' }
	if !os.is_file(modules + '/ui2/v.mod') {
		return error('Software UI checks need a staged headless ui2 module; set VINIX_PACKAGE_TEST_UI2 to its parent directory')
	}
	run(v, ['-gc', 'none', '-manualfree', '-enable-globals', '-d', 'ui2_headless', '-path',
		'@vlib|' + modules + '|@vmodules|' + repository, '-o', work + '/software-check',
		work + '/software'])!
	run(work + '/software-check', [])!
	if '--cross' in os.args {
		run(v, ['-o', work + '/package-stage', repository + '/tools/packages/stage.v'])!
		for architecture in ['aarch64', 'x86_64'] {
			staging := work + '/' + architecture
			os.mkdir_all(staging)!
			run(work + '/package-stage', ['--arch', architecture, '--staging', staging])!
		}
	}
	if '--desktop' in os.args {
		// Reuse generated VML/example assets while reading every current desktop
		// implementation file directly. This never runs the Python staging shim.
		overlay := work + '/desktop'
		os.mkdir_all(overlay)!
		for name in os.ls(repository + '/build/app-src')! {
			if os.is_file(repository + '/build/app-src/' + name) {
				os.symlink(repository + '/build/app-src/' + name, overlay + '/' + name)!
			}
		}
		for name in os.ls(repository + '/desktop')! {
			if !name.ends_with('.v') && !name.ends_with('.h') && !name.ends_with('.vml') {
				continue
			}
			if os.exists(overlay + '/' + name) || os.is_link(overlay + '/' + name) {
				os.rm(overlay + '/' + name)!
			}
			os.symlink(repository + '/desktop/' + name, overlay + '/' + name)!
		}
		for architecture in ['arm64', 'amd64'] {
			run(v, ['-check', '-os', 'linux', '-arch', architecture, '-gc', 'none', '-manualfree',
				'-enable-globals', '-d', 'ui2_headless', '-path',
				'@vlib|' + modules + '|@vmodules|' + repository + '|' + repository + '/third_party',
				overlay])!
		}
		run(v, ['-path', '@vlib|@vmodules|' + repository + '/tests/linuxkpi|' + repository,
			'-o', work + '/launcher-check', repository + '/tests/packages/launcher-check.v'])!
		run(work + '/launcher-check', [work])!
	}
	println('Package distribution checks passed')
}

fn main() {
	check() or {
		eprintln(err)
		exit(1)
	}
}
