// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import androidhost as ah
import androidrun
import cachecli
import hosttest
import json2
import os
import tarcore

@[heap]
struct Recorder {
mut:
	commands [][]string
	fail_at  int = -1
}

fn command(argv []string, pointer voidptr) ! {
	mut recorder := unsafe { &Recorder(pointer) }
	recorder.commands << argv.clone()
	if recorder.commands.len == recorder.fail_at { return error('controlled compiler failure') }
	if '-o' in argv {
		index := argv.index('-o')
		os.write_file(argv[index + 1], 'native compiler fixture output')!
		os.chmod(argv[index + 1], 0o755)!
	} else {
		assert argv[0].ends_with('/build-support/xorg-server/compile-v-host')
		assert argv[1] == 'winehost' && argv[3..] == ['--arch', 'arm64']
		os.write_file(argv[2], '/* native generation fixture */\n')!
	}
}

fn file(path string, data string) ! {
	os.mkdir_all(os.dir(path))!
	os.write_file(path, data)!
}

fn args_for(root string, work string, initramfs bool, translated bool, probes bool) !map[string]ah.Value {
	mut args := androidrun.defaults(root)
	repo := work + '/repo'
	state := work + '/session'
	file(repo + '/build-aarch64-userland/staging/bin/zsh', '#!/bin/sh\n')!
	os.mkdir_all(repo + '/build-aarch64-userland/staging/usr/lib/zsh')!
	os.mkdir_all(repo + '/build-aarch64-x11/staging/usr/bin')!
	file(repo + '/build-aarch64-x11/staging/usr/lib/base-x11.so', 'x11 library')!
	file(repo + '/desktop/assets/fixture.qoi', 'icon fixture')!
	file(work + '/runtime/usr/bin/run-android', '#!/bin/sh\n')!
	file(work + '/runtime/opt/vinix-android-aarch64/architecture', if translated {
		'x86_64\n'
	} else {
		'aarch64\n'
	})!
	file(work + '/runtime/opt/vinix-android-aarch64/usr/lib/runtime.so', 'private runtime fixture')!
	file(work + '/kernel/bin/vinix', 'kernel fixture')!
	file(work + '/desktop', 'desktop fixture')!
	file(work + '/application.apk', 'application fixture')!
	file(work + '/split.apk', 'split fixture')!
	os.mkdir_all(state)!
	for key, value in {
		'repo':         repo
		'runtime':      work + '/runtime'
		'desktop':      work + '/desktop'
		'kernel_dir':   work + '/kernel'
		'apk':          work + '/application.apk'
		'state_dir':    state
		'runtime_arch': if translated { 'x86_64' } else { 'aarch64' }
	} {
		args[key] = ah.Value(value)
	}
	args['prepare_only'] = ah.Value(true)
	args['observe'] = ah.Value(false)
	args['split_apk'] = ah.Value(if translated {
		[]ah.Value{}
	} else {
		[ah.Value(work + '/split.apk')]
	})
	args['runtime_arg'] = ah.Value([ah.Value('--fixture'), ah.Value("space and 'quote'")])
	if initramfs {
		mut writer := tarcore.create_stream(work + '/base.tar')!
		writer.add(tarcore.Member{ name: './lib/base.so', size: 4 }, 'base'.bytes())!
		writer.finish()!
		writer.close_checked()!
		args['initramfs'] = ah.Value(work + '/base.tar')
	} else {
		archive := repo + '/build-aarch64-userland/downloads/alpine-minirootfs-3.21.7-aarch64.tar.gz'
		os.mkdir_all(os.dir(archive))!
		mut writer := tarcore.create_gzip(archive)!
		for name in ['usr', 'usr/bin', 'lib', 'sbin', 'bin'] {
			writer.add(tarcore.Member{ name: name, kind: `5`, mode: 0o755 }, []u8{})!
		}
		writer.add(tarcore.Member{ name: 'lib/base.so', size: 4 }, 'base'.bytes())!
		writer.finish()!
		writer.close_checked()!
	}
	if probes {
		for name in ['boot_probe', 'layout_probe', 'pointer_probe', 'lifecycle_probe', 'cookie_probe',
			'autofill_probe', 'location_probe', 'egl_queue_probe', 'egl_probe', 'tls_probe'] {
			file(work + '/probes/' + name, name + ' fixture')!
			args[name] = ah.Value(work + '/probes/' + name)
		}
		for name in ['loader-test', 'packed-relocation-probe.so'] {
			file(work + '/loader/' + name, name + ' fixture')!
		}
		args['loader_probe'] = ah.Value(work + '/loader')
		for name in ['android-split-probe.apk', 'config.arm64_v8a.apk', 'invalid.apk'] {
			file(work + '/splits/' + name, name + ' fixture')!
		}
		file(work + '/splits/test-cases.json', '{"cases":[{"name":"invalid","splits":["invalid.apk"],"error":"fixture rejection","options":["--install"]}]}')!
		args['split_probe'] = ah.Value(work + '/splits')
	}
	return args
}

fn prepare_cases(root string, work string) ! {
	for name in ['native-overlay', 'native-initramfs', 'translated-overlay', 'all-probes',
		'compiler-failure'] {
		state := work + '/' + name
		args := args_for(root, state, name != 'native-initramfs', name == 'translated-overlay', name == 'all-probes')!
		mut recorder := &Recorder{ fail_at: if name == 'compiler-failure' { 3 } else { -1 } }
		mut context := androidrun.Context{ root: root, args: args, command_hook: command, command_context: recorder }
		mut refused := false
		status := context.call('main', context.args) or {
			assert name == 'compiler-failure' && err.msg() == 'controlled compiler failure', name + ': ' + err.msg() + '\n' + json2.encode(recorder.commands)
			refused = true
			ah.Value(1)
		}
		context.close()
		if name == 'compiler-failure' {
			assert refused && recorder.commands.len == 3
			assert os.exists(state + '/session/overlay/opt/android-test/x11-probe')
			assert !os.exists(state + '/session/overlay/opt/android-test/runtime-stack-probe')
			continue
		}
		assert !refused && ah.encode(status) == '0'
		overlay := state + '/session/overlay'
		assert os.read_file(overlay + '/opt/android-test/application.apk')! == 'application fixture'
		if name != 'translated-overlay' {
			assert os.read_file(overlay + '/opt/android-test/split-0.apk')! == 'split fixture'
			assert ah.field(context.args, 'split_apk_sha256').items() == [ah.Value(ah.digest(overlay + '/opt/android-test/split-0.apk')!)]
		} else {
			assert ah.field(context.args, 'split_apk_sha256').items().len == 0
		}
		assert os.readlink(overlay + '/usr/bin/vinix-android-calculator')! == 'vinix-desktop'
		assert os.readlink(overlay + '/usr/bin/vinix-terminal')! == 'vinix-desktop'
		assert os.read_file(overlay + '/usr/bin/vinix-desktop')! == 'desktop fixture'
		assert os.read_file(overlay + '/usr/share/vinix/icons/fixture.qoi')! == 'icon fixture'
		launch := os.read_file(overlay + '/opt/android-test/launch')!
		assert launch.starts_with('#!/bin/sh\n') && launch.contains('run-android')
		if name != 'translated-overlay' {
			assert launch.contains('split-0.apk')
		}
		configuration := os.read_file(overlay + '/opt/android-test/config.sh')!
		assert configuration.contains('TEST_APK=/opt/android-test/application.apk\n') && configuration.contains('TEST_WAIT_FOR_RESUME=0\n')
		assert os.stat(overlay + '/opt/android-test/launch')!.mode & 0o777 == 0o755
		assert recorder.commands[0][1..5] == ['-O2', '-Wall', '-Wextra', '-Werror']
		assert recorder.commands[0].contains('-lXtst') && recorder.commands[0].contains('-lX11')
		if name == 'translated-overlay' {
			assert recorder.commands[1][0].ends_with('x86_64-linux-musl-gcc')
		} else {
			assert recorder.commands[1][0].ends_with('aarch64-linux-musl-gcc')
		}
		if name == 'native-initramfs' {
			assert os.is_file(state + '/session/initramfs.tar')
			assert ah.field(context.args, 'initramfs').text() == state + '/session/initramfs.tar'
			assert os.readlink(overlay + '/bin/zsh')! == '../usr/bin/zsh'
		}
		if name == 'all-probes' {
			for key in ['boot_probe', 'layout_probe', 'pointer_probe', 'lifecycle_probe', 'cookie_probe',
				'autofill_probe', 'location_probe', 'egl_queue_probe', 'egl_probe', 'tls_probe'] {
				assert ah.field(context.args, key + '_sha256').text() == ah.digest(ah.field(args, key).text())!
			}
			assert ah.field(context.args, 'loader_probe_sha256').object().len == 2
			assert ah.field(context.args, 'split_probe_sha256').object().len == 4
			assert os.read_file(overlay + '/opt/android-test/split-probe/launch-01-invalid.error')! == 'fixture rejection'
		}
		os.write_file(state + '/commands.json', json2.encode(recorder.commands))!
	}
}

fn split_cases(root string, work string) ! {
	source := work + '/split'
	for name in ['android-split-probe.apk', 'config.arm64_v8a.apk', 'bad.apk'] {
		file(source + '/' + name, name)!
	}
	mut context := androidrun.Context{ root: root }
	defer { context.close() }
	for index, invalid in ['null', 'true', '1', '1.5', 'NaN', 'Infinity', '-Infinity', '[]', '[null]',
		'[true]', '[1]', '[1.5]', '[NaN]', '[{}]',
		'[{"name":"positive","splits":["bad.apk"],"error":"bad"}]'] {
		os.write_file(source + '/test-cases.json', '{"cases":' + invalid + '}')!
		mut refused := false
		context.call('prepare_split_probe', {
			'source':      ah.Value(source)
			'destination': ah.Value(work + '/invalid-' + index.str())
		}) or { refused = true }
		assert refused, invalid
		assert !os.exists(work + '/invalid-' + index.str())
	}
	mut cases := []ah.Value{}
	for index in 0 .. 102 {
		cases << ah.Value({
			'name':    ah.Value('case-' + index.str())
			'splits':  ah.Value([ah.Value('bad.apk')])
			'error':   ah.Value("controlled 'quote' failure")
			'options': ah.Value([ah.Value('--install-internal')])
		})
	}
	os.write_file(source + '/test-cases.json', androidrun.dump_json(ah.Value({
		'cases': ah.Value(cases)
	}), -1))!
	context.call('prepare_split_probe', {
		'source':      ah.Value(source)
		'destination': ah.Value(work + '/many-splits')
	})!
	assert os.read_file(work + '/many-splits/launch-102-case-101.expected')! == '1\n'
	assert os.read_file(work + '/many-splits/launch-102-case-101.error')! == "controlled 'quote' failure"
	assert os.read_file(work + '/many-splits/launch-102-case-101')!.contains('--install-internal')
	assert os.stat(work + '/many-splits/launch-102-case-101')!.mode & 0o777 == 0o755
}

fn qualify(work string) ! {
	os.mkdir(work)!
	bin := work + '/bin'
	os.mkdir(bin)!
	for name in ['aarch64-linux-musl-gcc', 'x86_64-linux-musl-gcc'] {
		os.cp(os.executable(), bin + '/' + name)!
		os.chmod(bin + '/' + name, 0o755)!
	}
	previous := os.getenv('PATH')
	os.setenv('PATH', bin + ':' + previous, true)
	defer { os.setenv('PATH', previous, true) }
	prepare_cases(hosttest.root(), work)!
	split_cases(hosttest.root(), work)!
	os.write_file(work + '/passed', 'PASS\n')!
	println('NATIVE ANDROID PREPARE / complete native and translated overlays, compressed miniroot and initramfs publication / every optional probe identity / compiler argv and partial failure state / 16 invalid split JSON shapes and 102 rejection launchers: PASS')
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.args.len != 2 { exit(2) }
	qualify(os.args[1]) or {
		eprintln(err)
		exit(1)
	}
}
