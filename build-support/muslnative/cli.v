// SPDX-License-Identifier: GPL-2.0-or-later
module muslnative

import cachecli
import cachekey
import os
import strconv

pub fn cli(argv []string, root string, support string, legacy bool) int {
	mut scalar := ['--arch', '--staging', '--build-dir', '--cc', '--jobs', '--support-dir']
	if !legacy { scalar << '--max-page-size' }
	args := cachecli.arguments(argv, scalar, if legacy {
		[]string{}
	} else {
		['--extra-patch', '--require-export']
	}, []string{}, 0, 0,
		'usage: stage --arch x86_64|aarch64 --staging ROOT [--build-dir CACHE --cc COMMAND --jobs N]') or {
		eprintln(err)
		return 2
	}
	arch := args.required('--arch') or {
		eprintln(err)
		return 2
	}
	staging := args.required('--staging') or {
		eprintln(err)
		return 2
	}
	if arch !in ['x86_64', 'aarch64'] {
		eprintln('invalid architecture')
		return 2
	}
	stage := cachekey.resolve_path(staging) or {
		eprintln(err)
		return 1
	}
	if stage == '/' || !os.is_file(stage + '/lib/ld-musl-' + arch + '.so.1') {
		eprintln('staging must be an existing Alpine root for the requested architecture')
		return 2
	}
	jobs := strconv.atoi(args.value('--jobs', os.getenv_opt('NPROC') or { '8' })) or {
		eprintln('invalid jobs')
		return 2
	}
	max_page_size := strconv.parse_int(args.value('--max-page-size', '0'), 10, 64) or {
		eprintln('invalid max-page-size')
		return 2
	}
	if jobs < 1 {
		eprintln('jobs must be positive')
		return 2
	}
	if '--max-page-size' in args.options && (max_page_size < 4096 || (max_page_size & (max_page_size - 1)) != 0) {
		eprintln('max-page-size must be a power of two of at least 4096')
		return 2
	}
	if os.getenv_opt('VINIX_OPTIMIZED_MUSL') or { '1' } == '0' {
		println("    keeping Alpine's packaged musl (VINIX_OPTIMIZED_MUSL=0)")
		return 0
	}
	retain := os.getenv_opt('VINIX_MUSL_RETAIN') or { '1' }
	if retain !in ['0', '1'] {
		eprintln('VINIX_MUSL_RETAIN must be 0 or 1')
		return 2
	}
	options := Options{
		root:             root
		support:          args.value('--support-dir', support)
		arch:             arch
		stage:            stage
		cache:            args.value('--build-dir', os.getenv_opt('VINIX_MUSL_BUILD_DIR') or { root + '/build/musl' })
		cc:               args.value('--cc', '')
		jobs:             jobs
		max_page_size:    max_page_size
		extra_patches:    args.options['--extra-patch'] or { []string{} }
		required_exports: args.options['--require-export'] or { []string{} }
	}
	guard := cachecli.own_commands()
	defer { guard.close() }
	build := plan(options, retain) or {
		eprintln(err)
		return if cachecli.cancelled() {
			cachecli.interrupt_status()
		} else if err is InputError {
			2
		} else {
			1
		}
	}
	publish(build) or {
		eprintln(err)
		return if cachecli.cancelled() { cachecli.interrupt_status() } else { 1 }
	}
	return 0
}
