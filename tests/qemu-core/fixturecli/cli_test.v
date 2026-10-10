// SPDX-License-Identifier: BSD-2-Clause
module fixturecli

import hosttest
import os

fn parse_error(kind string, args []string) string {
	parse_options(kind, args) or { return err.msg() }
	return 'unexpected success'
}

fn test_actions_are_rejected_before_help_or_staging_and_defaults_stay_distinct() {
	for kind in kinds {
		for args in [['out', '--prepare-only', '--native-build', '--help'],
			['out', '--native-build', '--prepare-only', '--help']] {
			parse_options(kind, args) or {
				assert err.msg().contains('not allowed with')
				continue
			}
			assert false
		}
		assert parse_options(kind, ['--help', '--prepare-only', '--native-build'])!.help
		assert parse_options(kind, ['--unknown', '--help'])!.help
		assert parse_options(kind, ['-hhh'])!.help
		assert parse_options(kind, ['out', '--arch=amd64', '--arch', 'arm64'])!.arch == 'arm64'
		assert parse_options(kind, ['--', '-output'])!.output == '-output'
		assert parse_options(kind, ['--', '--arch'])!.output == '--arch'
		assert parse_error(kind, ['out', '--', '--help']) == 'unrecognized arguments: --help'
		assert parse_options(kind, ['-1'])!.output == '-1'
		assert parse_options(kind, ['', '--prepare-only'])!.output == '.'
		assert parse_options(kind, ['./out//../界'])!.output == 'out/../界'
		assert parse_options(kind, ['//root//./file'])!.output == '//root/file'
		assert parse_options(kind, ['out', '--prepare-only', '--prepare-only', '--guest'])!.guest
		assert parse_options(kind, ['out', '--na', '--arch=amd64'])!.native
		if kind == 'touch' {
			assert parse_options(kind, ['out', '--native-build'])!.arch == host_arch()
		} else {
			parse_options(kind, ['out', '--native-build']) or {
				assert err.msg() == '--native-build requires --arch'
				continue
			}
			assert false
		}
	}
	for args in [['out'], ['out', '--arch=no'], ['out', '--arch', '--help'], ['--cc=clang', 'out']] {
		parse_options('generate', args) or {
			assert err.msg() != ''
			continue
		}
		assert false
	}
	assert parse_options('generate', ['out', '--arch=arm64'])!.arch == 'arm64'
}

fn test_pending_cli_preserves_distinct_defaults_and_arguments() {
	assert parse_options('base-generate', ['out'])!.arch == 'arm64'
	assert parse_options('base-generate', ['out', '--mod', '--arch=amd64'])!.module_only
	assert parse_options('base', ['out', '--native-headers=./headers//'])!.headers == 'headers'
	assert parse_options('base', ['out'])!.headers.ends_with('/sysroot/include')
	assert parse_options('base', ['out', '--cc=clang'])!.cc == 'clang'
	assert parse_error('base', ['out', '--arch=amd64']).contains('unrecognized arguments')
	assert parse_error('base-generate', ['out', '--native-build']).contains('unrecognized arguments')
	assert parse_options('futex', ['out', '--prepare-only', '--guest'])!.guest
	assert parse_error('futex', ['out', '--native-build']) == '--native-build requires --arch'
	assert parse_error('futex', ['out', '--prepare-only', '--native-build', '--help']).contains('not allowed with')
}

fn test_native_commands_reject_bad_modes_and_protected_output_without_staging() {
	tool := os.getenv('VINIX_QEMU_FIXTURE_TOOL')
	generator := os.getenv('VINIX_QEMU_FIXTURE_GENERATOR')
	if tool == '' || generator == '' { return }
	work := hosttest.work_dir('', 'vinix-fixture-cli-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	for args in [['out', '--prepare-only', '--native-build', '--help'], ['out', '--native-build'],
		['out', '--arch=bad'], ['out', '--cc', '--help'], ['out', '--', '--help'], []string{}] {
		failed := hosttest.capture_in([tool, ...args], '', 30, os.environ(), work)!
		assert failed.code == 2 && failed.stdout == '' && failed.stderr.starts_with('usage:')
	}
	for args in [['--help'], ['--unknown', '-h'], ['--help', '--arch=bad']] {
		help := hosttest.capture_in([tool, ...args], '', 30, os.environ(), work)!
		assert help.code == 0 && help.stderr == '' && help.stdout.starts_with('usage:')
	}
	assert os.ls(work)!.len == 0
	protected := os.join_path(hosttest.root(), 'tests/qemu-core/.fixture-must-not-exist')
	assert !os.exists(protected)
	for argv in [[tool, protected, '--prepare-only'], [generator, protected, '--arch=arm64']] {
		failed := hosttest.capture(argv, '', 30, os.environ())!
		assert failed.code == 1 && failed.stdout == '' && failed.stderr.contains('outside the maintained checkout')
		assert !os.exists(protected)
	}
}
