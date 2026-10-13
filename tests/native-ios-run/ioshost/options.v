// SPDX-License-Identifier: GPL-2.0-or-later
module ioshost

import cachecli
import strconv

pub struct Options {
pub:
	no_build     bool
	with_2048    bool
	with_cxx     bool
	with_gles    bool
	with_ppsspp  bool
	ppsspp_muted bool
	ppsspp_cube  bool
	ppsspp_nzp   bool
	ppsspp_gow   bool
	timeout      int = 180
}

pub fn parse(argv []string) !Options {
	args := cachecli.arguments(argv, ['--timeout'], [], ['--no-build', '--with-2048', '--with-cxx',
		'--with-gles', '--with-ppsspp', '--ppsspp-muted', '--ppsspp-cube', '--ppsspp-nzp',
		'--ppsspp-gow'], 0, 0, 'Run real iOS-targeted Mach-O instructions in an isolated Vinix ARM64 VM.\nUsage: run [--no-build --with-2048 --with-cxx --with-gles --with-ppsspp --ppsspp-muted --ppsspp-cube|--ppsspp-nzp|--ppsspp-gow --timeout 180]') or { return error_with_code(err.msg(), 2) }
	options := Options{ no_build: '--no-build' in args.options, with_2048: '--with-2048' in args.options, with_cxx: '--with-cxx' in args.options, with_gles: '--with-gles' in args.options, with_ppsspp: '--with-ppsspp' in args.options, ppsspp_muted: '--ppsspp-muted' in args.options, ppsspp_cube: '--ppsspp-cube' in args.options, ppsspp_nzp: '--ppsspp-nzp' in args.options, ppsspp_gow: '--ppsspp-gow' in args.options, timeout: int(strconv.common_parse_int(args.value('--timeout', '180'), 10, 32, true, true) or { return error_with_code('invalid timeout', 2) }) }
	options.validate()!
	return options
}

pub fn (options Options) validate() ! {
	if options.timeout <= 0 { return error_with_code('timeout must be positive', 2) }
	if options.with_ppsspp && !options.with_cxx {
		return error_with_code("--with-ppsspp requires --with-cxx for PPSSPP's native C++ runtime", 2)
	}
	if options.ppsspp_muted && !(options.with_ppsspp && options.with_gles) {
		return error_with_code('--ppsspp-muted requires --with-ppsspp and --with-gles', 2)
	}
	if options.ppsspp_cube && !options.ppsspp_muted {
		return error_with_code('--ppsspp-cube requires --ppsspp-muted', 2)
	}
	if options.ppsspp_nzp && (!options.ppsspp_muted || options.ppsspp_cube) {
		return error_with_code('--ppsspp-nzp requires --ppsspp-muted and cannot be combined with --ppsspp-cube', 2)
	}
	if options.ppsspp_gow && (!options.ppsspp_muted || options.ppsspp_cube || options.ppsspp_nzp) {
		return error_with_code('--ppsspp-gow requires --ppsspp-muted and cannot be combined with another PSP game', 2)
	}
}

pub fn (options Options) expected() []string {
	mut result := features.clone()
	if options.with_2048 {
		result << ['iOS PASS: upstream 2048 eight model merge tests',
			'iOS PASS: upstream 2048 launch, swipes, merges, timers and ARC teardown']
	}
	if options.with_ppsspp {
		result << if options.ppsspp_muted {
			'iOS PASS: upstream PPSSPP native framebuffer and process lifecycle (muted)'
		} else {
			'iOS BLOCKED: upstream PPSSPP unsupported API reached at runtime'
		}
	}
	if options.ppsspp_cube {
		result << 'iOS PASS: unchanged PPSSPP iOS binary executes PSP cube homebrew'
	}
	if options.ppsspp_nzp {
		result << 'iOS PASS: unchanged PPSSPP iOS binary plays NZP PSP shooter'
	}
	if options.ppsspp_gow {
		result << 'iOS PASS: unchanged PPSSPP iOS binary runs God of War PSP demo'
	}
	if options.with_cxx {
		result << ['iOS PASS: native C++ strings, streams, regex and lifetime',
			'iOS PASS: extended C++ ABI, Darwin entropy and variadic abort',
			'iOS PASS: native ELF vector exception helpers',
			'iOS PASS: Objective-C image startup and C++ ivars']
	}
	if options.with_gles {
		result << ['iOS PASS: native OpenGL ES shader rendering and GLKView lifecycle',
			'iOS PASS: display links, main queue and desktop shared-surface presentation',
			'iOS PASS: native CoreText fonts and bitmap glyph rendering',
			'iOS PASS: native zlib and Mach-O callbacks']
	}
	result << 'VINIX iOS GUEST: PASS'
	return result
}
