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
	if '--https' in os.args || '--https-only' in os.args {
		run(v, [...helper_flags, '-gc', 'none', '-o', work + '/https-fixture', repository + '/tests/packages/https-fixture.v'])!
		run(v, [...helper_flags, '-gc', 'none', '-path', '@vlib|@vmodules|' + repository,
			'-o', work + '/https-check', repository + '/tests/packages/https-check.v'])!
		run(work + '/https-check', [work + '/https-fixture', work + '/https-run'])!
		run(v, [...helper_flags, '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts',
			'-o', work + '/https-destination-check', repository + '/tests/packages/https-destination-check.v'])!
		run(work + '/https-destination-check', [work + '/https-fixture', work + '/https-destinations'])!
		if '--https-only' in os.args { println('Package HTTPS checks passed'); return }
	}
	if '--software-only' !in os.args {
		check_tests(v, ['-gc', 'none'], repository + '/tools/packages/signing', work)!
		run(v, [...helper_flags, '-enable-globals', '-d', 'track_heap', '-gc', 'none', '-manualfree',
			'-path', '@vlib|@vmodules|' + repository, '-o', work + '/signing-allocation-check',
			repository + '/tests/packages/signing-allocation-check.v'])!
		run(work + '/signing-allocation-check', [])!
		run(v, [...helper_flags, '-d', 'track_heap', '-gc', 'none', '-manualfree',
			'-path', '@vlib|@vmodules|' + repository, '-o', work + '/signing-tables-check',
			repository + '/tests/packages/signing-tables-check.v'])!
		run(work + '/signing-tables-check', [])!
		run(v, [...helper_flags, '-gc', 'none', '-manualfree', '-d', 'track_heap',
			'-path', '@vlib|@vmodules|' + repository, '-o', work + '/signing-buffers-check',
			repository + '/tests/packages/signing-buffers-check.v'])!
		run(work + '/signing-buffers-check', [])!
		run(v, [...helper_flags, '-gc', 'none', '-manualfree', '-d', 'track_heap',
			'-path', '@vlib|@vmodules|' + repository, '-o', work + '/publisher-key-memory',
			repository + '/tests/packages/publisher-key-memory.v'])!
		run(work + '/publisher-key-memory', [])!
		check_tests(v, ['-gc', 'none'], repository + '/tools/packages/pkgcore', work)!
		run(v, [...helper_flags, '-no-skip-unused', '-gc', 'none', '-manualfree', '-d', 'track_heap',
			'-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts',
			'-o', work + '/diagnostics-memory', repository + '/tools/packages/pkgcore/view_test.v'])!
		run(work + '/diagnostics-memory', [])!
		check_tests(v, ['-gc', 'none', '-manualfree'], repository + '/tools/packages/pkgprotocol', work)!
		run(v, [...helper_flags, '-no-skip-unused', '-gc', 'none', '-manualfree', '-d', 'track_heap',
			'-path', '@vlib|@vmodules|' + repository, '-o', work + '/repository-configuration-memory',
			repository + '/tools/packages/pkgprotocol/repository_configuration_test.v'])!
		run(work + '/repository-configuration-memory', [])!
		check_tests(v, ['-gc', 'none', '-manualfree'], repository + '/tools/packages/appsdk', work)!
		check_tests(v, ['-gc', 'none', '-manualfree'], repository + '/tools/packages/pkgadmin', work)!
		run(v, ['-nocache', 'run', repository + '/tests/packages/space-check.v'])!
		run(v, ['-nocache', 'run', repository + '/tests/packages/removal-space-check.v'])!
		check_tests(v, ['-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts'], repository + '/tools/packages/pkglaunch', work)!
		run(v, [...helper_flags, '-gc', 'none', '-manualfree', '-d', 'track_heap', '-o', work + '/context-memory', repository + '/tests/packages/sdk-context-memory.v'])!
		run(work + '/context-memory', [])!
		run(v, [...helper_flags, '-gc', 'none', '-manualfree', '-d', 'track_heap', '-o', work + '/window-memory', repository + '/tests/packages/window-memory.v'])!
		run(work + '/window-memory', [])!
		run(v, [...helper_flags, '-gc', 'none', '-manualfree', '-d', 'track_heap', '-o', work + '/review-memory', repository + '/tests/packages/review-memory.v'])!
		run(work + '/review-memory', [])!
		run(v, [...helper_flags, '-gc', 'none', '-manualfree', '-d', 'track_heap', '-o', work + '/view-memory', repository + '/tests/packages/view-memory.v'])!
		run(work + '/view-memory', [])!
		run(v, [...helper_flags, '-gc', 'none', '-manualfree', '-d', 'track_heap', '-o', work + '/registration-memory', repository + '/tests/packages/registration-memory.v'])!
		run(work + '/registration-memory', [])!
		check_tests(v, ['-gc', 'none', '-manualfree'], repository + '/desktop/packagecore', work)!
		run(v, [...helper_flags, '-gc', 'none', '-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts', '-o', work + '/vinix-package', repository + '/tools/packages/main.v'])!
		run(work + '/vinix-package', ['--help'])!
		run(v, [...helper_flags, '-gc', 'none', '-manualfree', '-o', work + '/cli-check', repository + '/tests/packages/distribution-cli.v'])!
		run(work + '/cli-check', [work + '/vinix-package'])!
		run(v, [...helper_flags, '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|' + repository,
			'-o', work + '/elf-profile-check', repository + '/tests/packages/elf-profile-check.v'])!
		run(work + '/elf-profile-check', [work + '/vinix-package', work + '/elf-profiles'])!
		run(v, [...helper_flags, '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts',
			'-o', work + '/metadata-race-check', repository + '/tests/packages/metadata-race-check.v'])!
		run(work + '/metadata-race-check', [work + '/metadata-races'])!
		run(v, [...helper_flags, '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts',
			'-o', work + '/copy-file-check', repository + '/tests/packages/copy-file-check.v'])!
		run(work + '/copy-file-check', [work + '/copy-files'])!
		run(v, [...helper_flags, '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts',
			'-o', work + '/copy-output-check', repository + '/tests/packages/copy-output-check.v'])!
		run(work + '/copy-output-check', [work + '/copy-output'])!
		run(v, [...helper_flags, '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts',
			'-o', work + '/prepared-root-check', repository + '/tests/packages/prepared-root-check.v'])!
		run(work + '/prepared-root-check', [work + '/prepared-root'])!
		run(v, [...helper_flags, '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts',
			'-o', work + '/pack-source-check', repository + '/tests/packages/pack-source-check.v'])!
		run(work + '/pack-source-check', [work + '/pack-source'])!
		run(v, [...helper_flags, '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts',
			'-o', work + '/publisher-workspace-check', repository + '/tests/packages/publisher-workspace-check.v'])!
		run(work + '/publisher-workspace-check', [work + '/vinix-package', work + '/publisher-workspace'])!
		run(v, [...helper_flags, '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts',
			'-o', work + '/signing-repeat-check', repository + '/tests/packages/signing-repeat-check.v'])!
		run(work + '/signing-repeat-check', [work + '/signing-repeat'])!
		run(v, [...helper_flags, '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts',
			'-o', work + '/publisher-key-check', repository + '/tests/packages/publisher-key-check.v'])!
		run(work + '/publisher-key-check', [work + '/publisher-keys'])!
		run(v, [...helper_flags, '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts',
			'-o', work + '/publisher-recovery-check', repository + '/tests/packages/publisher-recovery-check.v'])!
		run(work + '/publisher-recovery-check', [work + '/publisher-recovery'])!
		run(v, [...helper_flags, '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts',
			'-o', work + '/hash-file-check', repository + '/tests/packages/hash-file-check.v'])!
		run(work + '/hash-file-check', [work + '/hash-files'])!
		run(v, [...helper_flags, '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts',
			'-o', work + '/atomic-write-check', repository + '/tests/packages/atomic-write-check.v'])!
		run(work + '/atomic-write-check', [work + '/atomic-writes'])!
		run(v, [...helper_flags, '-gc', 'none', '-manualfree', '-o', work + '/signing-seed-check', repository + '/tests/packages/signing-seed-check.v'])!
		run(work + '/signing-seed-check', [work + '/vinix-package', work + '/signing-seeds'])!
		run(v, [...helper_flags, '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts',
			'-o', work + '/durability-check', repository + '/tests/packages/durability-check.v'])!
		run(work + '/durability-check', [work + '/durability'])!
		run(v, [...helper_flags, '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts',
			'-o', work + '/keygen-check', repository + '/tests/packages/keygen-check.v'])!
		run(work + '/keygen-check', [work + '/keygen'])!
		run(v, [...helper_flags, '-o', work + '/terminal-check', repository + '/tests/packages/terminal-check.v'])!
		run(work + '/terminal-check', [])!
	}
	os.cp(repository + '/desktop/software_app.v', work + '/software/software_app.v')!
	os.cp(repository + '/desktop/software_details.v', work + '/software/software_details.v')!
	os.cp(repository + '/tests/packages/software_details_fixture.v', work + '/software/details_fixture.v')!
	os.cp(repository + '/tests/packages/software_view_fixture.v', work + '/software/view_fixture.v')!
	os.cp(repository + '/desktop/software_repositories.v', work + '/software/software_repositories.v')!
	os.cp(repository + '/desktop/software_progress.v', work + '/software/software_progress.v')!
	os.cp(repository + '/desktop/software_failure.v', work + '/software/software_failure.v')!
	os.cp(repository + '/tests/packages/software_failure_fixture.v', work + '/software/failure_fixture.v')!
	os.cp(repository + '/desktop/software_deployment.v', work + '/software/software_deployment.v')!
	os.cp(repository + '/desktop/software_mirror.v', work + '/software/software_mirror.v')!
	os.cp(repository + '/desktop/software_terminal.v', work + '/software/software_terminal.v')!
	os.cp(repository + '/desktop/software_launch.v', work + '/software/software_launch.v')!
	os.cp(repository + '/desktop/software_window.v', work + '/software/software_window.v')!
	os.cp(repository + '/desktop/software_admin.v', work + '/software/software_admin.v')!
	os.cp(repository + '/desktop/software_data.v', work + '/software/software_data.v')!
	os.cp(repository + '/desktop/software_policy.v', work + '/software/software_policy.v')!
	os.cp(repository + '/desktop/software_policy_pages.v', work + '/software/software_policy_pages.v')!
	os.cp(repository + '/tests/packages/software_policy_fixture.v', work + '/software/policy_fixture.v')!
	os.cp(repository + '/tests/packages/software_metadata_fixture.v', work + '/software/metadata_fixture.v')!
	os.cp(repository + '/tests/packages/software_data_fixture.v', work + '/software/data_fixture.v')!
	os.cp(repository + '/tests/packages/software_terminal_fixture.v', work + '/software/terminal_fixture.v')!
	os.cp(repository + '/tests/packages/software_fixture.v', work + '/software/main.v')!
	modules := os.getenv_opt('VINIX_PACKAGE_TEST_UI2') or { repository + '/build/vmodules' }
	if !os.is_file(modules + '/ui2/v.mod') {
		return error('Software UI checks need a staged headless ui2 module; set VINIX_PACKAGE_TEST_UI2 to its parent directory')
	}
	run(v, [...helper_flags, '-gc', 'none', '-manualfree', '-enable-globals', '-d', 'ui2_headless', '-path',
		'@vlib|' + modules + '|@vmodules|' + repository, '-o', work + '/software-check',
		work + '/software'])!
	run(work + '/software-check', [])!
	run(v, [...helper_flags, '-gc', 'none', '-manualfree', '-enable-globals', '-d', 'ui2_headless', '-d', 'track_heap',
		'-cflags', '-I' + repository + '/desktop', '-path',
		'@vlib|' + modules + '|@vmodules|' + repository, '-o', work + '/window-broker-memory', work + '/software'])!
	run(work + '/window-broker-memory', ['window-memory'])!
	run(work + '/window-broker-memory', ['admin-memory'])!
	run(work + '/window-broker-memory', ['data-memory'])!
	run(work + '/window-broker-memory', ['policy-memory'])!
	run(work + '/window-broker-memory', ['metadata-memory'])!
	run(work + '/window-broker-memory', ['details-memory'])!
	run(work + '/window-broker-memory', ['view-memory'])!
	run(work + '/window-broker-memory', ['failure-memory'])!
	if '--cross' in os.args {
		run(v, [...helper_flags, '-o', work + '/package-stage', repository + '/tools/packages/stage.v'])!
		for architecture in ['aarch64', 'x86_64'] {
			staging := work + '/' + architecture
			os.mkdir_all(staging)!
			run(work + '/package-stage', ['--arch', architecture, '--staging', staging])!
			assert os.read_file(staging + '/usr/share/licenses/vinix-packages/ed25519-MIT.txt')!
				== os.read_file(repository + '/tools/packages/signing/LICENSE')!
			assert os.read_file(staging + '/usr/share/licenses/vinix-packages/application-sdk-MIT.txt')!
				== os.read_file(repository + '/tools/packages/appsdk/LICENSE')!
			println('Package signing license staged (${architecture})')
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
	println(if '--software-only' in os.args { 'Software distribution checks passed' } else { 'Package distribution checks passed' })
}

fn main() {
	check() or {
		eprintln(err)
		exit(1)
	}
}
