// SPDX-License-Identifier: GPL-2.0-or-later
module runtimehost

import cachecli
import gamehost
import os
import qemubuild
import runtime
import strconv

pub fn qemu_cli(root string, argv []string) !int {
	args := cachecli.arguments(argv, ['--work', '--staging', '--sysroot', '--jobs'], [], ['--refresh'], 0, 0, "Cross-build Dota's patched static native translator.\nUsage: qemu-stage --staging DIR [--work DIR --sysroot DIR --jobs N --refresh]") or { return error_with_code(err.msg(), 2) }
	staging := args.required('--staging') or { return error_with_code(err.msg(), 2) }
	jobs := strconv.atoi(args.value('--jobs', int_min(8, runtime.nr_cpus()).str())) or { return error_with_code(err.msg(), 2) }
	if jobs < 1 { return error_with_code('--jobs must be positive', 2) }
	environment := os.environ()
	// This interpreter belongs to upstream QEMU's configure tooling. Discover
	// its executable without invoking it; first-party production and metadata
	// processing are V, and an existing upstream toolchain is required.
	python := os.getenv_opt('VINIX_DOTA2_QEMU_PYTHON') or { os.find_abs_path_of_executable('python3') or { '' } }
	identity := if python != '' { gamehost.digest(python)! } else { '' }
	options := qemubuild.Options{
		native:                true
		native_sources:        native_sources(root)!
		repo:                  root
		support:               root + '/build-support/dota2/qemu'
		builder:               root + '/tests/native-runtime-tools/main.v'
		work:                  args.value('--work', root + '/build/dota2-qemu')
		staging:               staging
		base:                  args.value('--sysroot', gamehost.env('VINIX_X11_SYSROOT', root + '/build-aarch64-x11/sysroot'))
		jobs:                  jobs.str()
		refresh:               '--refresh' in args.options
		platform:              if os.user_os() == 'macos' { 'darwin' } else { os.user_os() }
		host_arch:             os.uname().machine
		python:                python
		python_version:        'external upstream interpreter sha256:' + identity
		environment:           environment
		inherited_environment: environment
	}
	qemubuild.build(options) or {
		if err is qemubuild.BuildError && err.kind == 'ArgumentError' {
			return error_with_code(err.msg(), 2)
		}
		return err
	}
	return 0
}
