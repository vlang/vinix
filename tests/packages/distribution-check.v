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

fn check_tests(v string, flags []string, directory string, work string) ! {
	if '--direct-tests' !in os.args {
		run(v, [...flags, 'test', directory])!
		return
	}
	// Compile the same assertion runners directly without the cached vtest tool.
	// Retain declarations to avoid compiler pruning of required crypto SDK types.
	mut files := os.ls(directory)!.filter(it.ends_with('_test.v'))
	files.sort()
	if files.len == 0 { return error('no qualification tests in ${directory}') }
	for file in files {
		output := work + '/' + os.file_name(directory) + '-' + file.all_before_last('.v')
		run(v, [...flags, '-no-skip-unused', '-o', output, directory + '/' + file])!
		run(output, [])!
		println('Passed ' + directory + '/' + file)
	}
}

fn check() ! {
	repository := os.dir(os.dir(os.dir(@FILE)))
	v := os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!
	// The direct mode also retains declarations in fixture executables. The
	// compiler's pruning can otherwise omit types used by imported JSON structs.
	helper_flags := if '--direct-tests' in os.args { ['-no-skip-unused'] } else { []string{} }
	temporary := os.getenv_opt('VINIX_PACKAGE_TEST_WORK') or { os.temp_dir() }
	work := temporary + '/vinix-distribution-check-' + os.getpid().str()
	os.mkdir_all(work + '/software')!
	defer { os.rmdir_all(work) or {} }
	check_tests(v, ['-gc', 'none'], repository + '/tools/packages/pkgcore', work)!
	check_tests(v, ['-gc', 'none', '-manualfree'], repository + '/tools/packages/pkgprotocol', work)!
	check_tests(v, ['-gc', 'none', '-manualfree'], repository + '/desktop/packagecore', work)!
	run(v, [...helper_flags, '-gc', 'none', '-o', work + '/vinix-package', repository + '/tools/packages/main.v'])!
	run(work + '/vinix-package', ['--help'])!
	run(v, [...helper_flags, '-gc', 'none', '-manualfree', '-o', work + '/cli-check', repository + '/tests/packages/distribution-cli.v'])!
	run(work + '/cli-check', [work + '/vinix-package'])!
	os.cp(repository + '/desktop/software_app.v', work + '/software/software_app.v')!
	os.cp(repository + '/desktop/software_repositories.v', work + '/software/software_repositories.v')!
	os.cp(repository + '/desktop/software_progress.v', work + '/software/software_progress.v')!
	os.cp(repository + '/tests/packages/software_fixture.v', work + '/software/main.v')!
	modules := os.getenv_opt('VINIX_PACKAGE_TEST_UI2') or { repository + '/build/vmodules' }
	if !os.is_file(modules + '/ui2/v.mod') {
		return error('Software UI checks need a staged headless ui2 module; set VINIX_PACKAGE_TEST_UI2 to its parent directory')
	}
	run(v, [...helper_flags, '-gc', 'none', '-manualfree', '-enable-globals', '-d', 'ui2_headless', '-path',
		'@vlib|' + modules + '|@vmodules|' + repository, '-o', work + '/software-check',
		work + '/software'])!
	run(work + '/software-check', [])!
	if '--cross' in os.args {
		run(v, [...helper_flags, '-o', work + '/package-stage', repository + '/tools/packages/stage.v'])!
		for architecture in ['aarch64', 'x86_64'] {
			staging := work + '/' + architecture
			os.mkdir_all(staging)!
			run(work + '/package-stage', ['--arch', architecture, '--staging', staging])!
		}
	}
	if '--desktop' in os.args {
		// Reuse generated VML/example assets while reading every current desktop
		// implementation file directly. This never runs the Python staging shim.
		assets := os.getenv_opt('VINIX_PACKAGE_TEST_DESKTOP') or { repository + '/build/app-src' }
		overlay := work + '/desktop'
		os.mkdir_all(overlay)!
		for name in os.ls(assets)! {
			if os.is_file(assets + '/' + name) {
				os.symlink(assets + '/' + name, overlay + '/' + name)!
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
		run(v, [...helper_flags, '-path', '@vlib|@vmodules|' + repository + '/tests/linuxkpi|' + repository,
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
