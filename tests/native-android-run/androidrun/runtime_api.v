// SPDX-License-Identifier: GPL-2.0-or-later
module androidrun

import androidhost as ah
import androidtools
import boothost
import cachecli
import json2

pub fn android_preflight(stage string) ! {
	runtime := stage + '/' + roblox_prefix
	art := androidtools.read_runtime(runtime, 'art')!
	bionic := androidtools.read_runtime(runtime, 'bionic')!
	atl := androidtools.read_runtime(runtime, 'atl')!
	musl := androidtools.read_android_musl(runtime)!
	androidtools.validate_art_pair(art, atl)!
	manifest := load_json(read_text(runtime + '/runtime-manifest.json')!)!.object()
	for key, value in {
		'architecture': ah.Value('aarch64')
		'execution':    ah.Value('native')
		'page_size':    ah.Value(16384)
		'art':          art
		'bionic':       bionic
		'atl':          atl
		'musl':         musl
	} {
		if !boothost.receipt_equal(ah.field(manifest, key), value) {
			return error('--with-android requires the verified native ARM64 Android runtime')
		}
	}
	if !truth(ah.field(art.object(), 'bootclasspath')) {
		return error('--with-android requires the verified native ARM64 Android runtime')
	}
}

pub fn preflight_cli(root string, command string, argv []string) !int {
	args := cachecli.arguments(argv, ['--staging', '--android-staging'], [], [], 0, 0, 'Usage: desktop-check-android|desktop-check-roblox --staging PATH [--android-staging PATH]') or { return androidtools.InputError{err.msg()} }
	stage := args.required('--staging') or { return androidtools.InputError{err.msg()} }
	if command == 'desktop-check-android' {
		android_preflight(stage)!
	} else {
		android := args.required('--android-staging') or { return androidtools.InputError{err.msg()} }
		validate_roblox_stage(root, stage, android) or { return error('--with-roblox requires a verified ATL launcher stage: ' + err.msg() + '\nRun ./scripts/build-roblox-aarch64.sh first.') }
	}
	return 0
}

pub fn runtime_api(argv []string, kind string) !int {
	args := cachecli.arguments(argv, ['--runtime', '--overlay', '--kind'], [], [], 1, 1, 'Usage: art-runtime read|apply --overlay PATH [--runtime PATH --kind art|bionic|atl]\n       musl-runtime read --runtime PATH\n       musl-runtime source-patches') or { return androidtools.InputError{err.msg()} }
	operation := args.positional[0]
	mut result := ah.Value(json2.Null{})
	if kind == 'musl' {
		if operation == 'source-patches' {
			constants := androidtools.musl_constants()
			result = androidtools.musl_source_patches(ah.field(constants, 'MUSL').text(), ah.field(constants, 'PATCH').text())!
		} else if operation == 'read' {
			runtime := args.required('--runtime') or { return androidtools.InputError{err.msg()} }
			result = androidtools.read_android_musl(runtime)!
		} else {
			return androidtools.InputError{'unknown musl runtime operation'}
		}
	} else {
		overlay := args.required('--overlay') or { return androidtools.InputError{err.msg()} }
		selected := args.value('--kind', 'art')
		if selected !in ['art', 'bionic', 'atl'] {
			return androidtools.InputError{'unknown Android overlay kind'}
		}
		result = androidtools.read_runtime(overlay, selected)!
		if operation == 'apply' {
			runtime := args.required('--runtime') or { return androidtools.InputError{err.msg()} }
			result = androidtools.apply_runtime(overlay, runtime, result, selected)!
		} else if operation != 'read' {
			return androidtools.InputError{'unknown Android runtime operation'}
		}
	}
	println(ah.encode(result))
	return 0
}
