// SPDX-License-Identifier: GPL-2.0-or-later
module androidrun

import androidhost as ah
import androidtools
import cachecli
import json2
import os
import strconv

pub fn defaults(root string) map[string]ah.Value {
	mut result := map[string]ah.Value{}
	for name in ['runtime', 'runtime_arch', 'desktop', 'kernel_dir', 'initramfs', 'apk', 'boot_probe',
		'layout_probe', 'pointer_probe', 'lifecycle_probe', 'cookie_probe', 'autofill_probe',
		'location_probe', 'egl_queue_probe', 'split_probe', 'egl_probe', 'tls_probe', 'loader_probe',
		'roblox_staging', 'screenshot', 'input'] {
		result[name] = null()
	}
	for name in ['linker_diagnostics', 'prepare_only', 'strace', 'observe', 'interactive'] {
		result[name] = ah.Value(false)
	}
	for key, value in {
		'repo':      root
		'launcher':  'android'
		'activity':  'calculator/Calculator'
		'title':     ''
		'mode':      'desktop'
		'keys':      '123+456'
		'expect':    '579'
		'state_dir': root + '/build/android-smoke'
	} {
		result[key] = ah.Value(value)
	}
	for key, value in {
		'memory':              8192
		'cpus':                4
		'startup_timeout':     240
		'timeout':             420
		'observation_seconds': 30
	} {
		result[key] = ah.Value(value)
	}
	for key in ['runtime_arg', 'split_apk', 'split_apk_sha256'] {
		result[key] = ah.Value([]ah.Value{})
	}
	// The embedded ATL window has no inner GTK title bar. Target Arity's
	// input below its result, in desktop and window-relative coordinates.
	result['click'] = ah.Value([ah.Value(360), ah.Value(155)])
	result['focus'] = ah.Value([ah.Value(240), ah.Value(72)])
	return result
}

pub fn parse_cli(root string, argv []string) !map[string]ah.Value {
	mut values := defaults(root)
	mut scalar := []string{}
	mut flags := []string{}
	for key, value in values {
		if key in ['click', 'focus', 'runtime_arg', 'split_apk', 'split_apk_sha256'] { continue }
		flag := '--' + key.replace('_', '-')
		if value is bool { flags << flag } else { scalar << flag }
	}
	mut normalized := []string{}
	scalar << '--click'
	scalar << '--focus'
	mut index := 0
	for index < argv.len {
		arg := argv[index]
		short := arg.all_before('=')
		mut matches := []string{}
		for candidate in [...scalar, ...flags, '--runtime-arg', '--split-apk', '--help'] {
			if short.starts_with('--') && candidate.starts_with(short) { matches << candidate }
		}
		name := if short in ['--click', '--focus'] {
			short
		} else if matches.len == 1 {
			matches[0]
		} else {
			short
		}
		if name in ['--click', '--focus'] {
			mut pair := []string{}
			if arg.contains('=') {
				return androidtools.InputError{name + ' requires two separate coordinates'}
			} else {
				index++
				if index >= argv.len { return androidtools.InputError{name + ' requires X Y'} }
				pair << argv[index]
			}
			index++
			if index >= argv.len { return androidtools.InputError{name + ' requires X Y'} }
			pair << argv[index]
			mut coordinates := []string{}
			for value in pair {
				coordinates << (strconv.parse_int(value, 10, 64) or { return androidtools.InputError{'invalid coordinate: ' + value} }).str()
			}
			normalized << name + '=' + coordinates.join(',')
		} else {
			normalized << arg
		}
		index++
	}
	args := cachecli.arguments(normalized, scalar, ['--runtime-arg', '--split-apk'], flags, 0, 0, 'Run an Android APK on Vinix, check a calculator or observe its real window.\nUsage: run [--repo PATH --runtime PATH --runtime-arch aarch64|x86_64 --desktop PATH --kernel-dir PATH --initramfs PATH --apk PATH --split-apk PATH --mode desktop|direct --input qmp|xtest --keys TEXT --expect TEXT --click X Y --focus X Y --state-dir PATH --screenshot PATH --memory MB --cpus COUNT --startup-timeout SECONDS --timeout SECONDS --prepare-only --observe --interactive --observation-seconds SECONDS --launcher android|roblox --roblox-staging PATH --activity NAME --runtime-arg ARG --title TEXT --strace --linker-diagnostics] and optional --boot-probe/--layout-probe/--pointer-probe/--lifecycle-probe/--cookie-probe/--autofill-probe/--location-probe/--egl-queue-probe/--split-probe/--egl-probe/--tls-probe/--loader-probe PATH') or { return androidtools.InputError{err.msg()} }
	for flag, inputs in args.options {
		name := flag[2..].replace('-', '_')
		if name in ['click', 'focus'] {
			values[name] = ah.Value(inputs[0].split(',').map(ah.Value(ah.Number{strconv.parse_int(it, 10, 64) or { return androidtools.InputError{'invalid coordinate: ' + it} }.str()})))
			continue
		}
		if name in ['runtime_arg', 'split_apk'] {
			values[name] = ah.Value(inputs.map(ah.Value(it)))
			continue
		}
		previous := values[name] or { null() }
		if previous is bool {
			values[name] = ah.Value(true)
		} else if previous is int {
			values[name] = ah.Value(ah.Number{strconv.parse_int(inputs[0], 10, 64) or { return androidtools.InputError{'invalid integer for ' + flag + ': ' + inputs[0]} }.str()})
		} else {
			values[name] = ah.Value(inputs[0])
		}
	}
	for key, choices in {
		'runtime_arch': ['aarch64', 'x86_64']
		'mode':         ['desktop', 'direct']
		'input':        ['qmp', 'xtest']
		'launcher':     ['android', 'roblox']
	} {
		if ah.field(values, key) !is json2.Null && text(values, key) !in choices {
			return androidtools.InputError{'invalid choice for --' + key.replace('_', '-') + ': ' + text(values, key)}
		}
	}
	return values
}

pub fn run_cli(root string, argv []string) !int {
	mut context := Context{ root: root, args: parse_cli(root, argv)! }
	defer { context.close() }
	return int(number(context.call('main', context.args)!)!)
}

pub fn roblox_cli(root string, argv []string) !int {
	args := cachecli.arguments(argv, ['--build-dir', '--android-staging'], [], [], 0, 0, "Stage Roblox APK launchers using Vinix's native Android Translation Layer.\nUsage: build [--build-dir PATH --android-staging PATH]") or { return androidtools.InputError{err.msg()} }
	stage := stage_roblox(root, expand_home(args.value('--build-dir', root + '/build-aarch64-roblox/aarch64')), expand_home(args.value('--android-staging', if os.getenv('VINIX_ANDROID_STAGING') != '' {
		os.getenv('VINIX_ANDROID_STAGING')
	} else {
		root + '/build-aarch64-android/aarch64/staging'
	})))!
	println('Staged native ATL/ART Roblox launchers in ' + stage)
	return 0
}

fn expand_home(path string) string {
	return if path == '~' {
		os.home_dir()
	} else if path.starts_with('~/') {
		os.home_dir() + path[1..]
	} else {
		path
	}
}
