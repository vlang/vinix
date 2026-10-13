// SPDX-License-Identifier: GPL-2.0-or-later
module ioshost

import cachecli
import encoding.binary
import gamehost
import os
import sourcecommand

pub struct Tools {
pub:
	root        string
	environment map[string]string
	hook        fn ([]string, map[string]string, voidptr) !sourcecommand.Output = unsafe { nil }
	context     voidptr
}

pub fn (tools Tools) command(argv []string, environment map[string]string) ! {
	if argv.len == 0 || argv[0].all_after_last('/') in ['python', 'python3'] {
		return error('expected native command')
	}
	result := if tools.hook != unsafe { nil } {
		tools.hook(argv, environment, tools.context)!
	} else {
		sourcecommand.run_preferred(argv, environment, cachecli.cancelled, '')!
	}
	if result.status != 0 { return error('iOS command failed (${result.status}): ' + argv[0]) }
}

pub fn (tools Tools) build(build string, options Options) ! {
	root, env := tools.root, tools.environment
	if !options.no_build {
		mut flags := []string{}
		if options.with_cxx { flags << '--with-cxx' }
		if options.with_gles { flags << '--with-gles' }
		tools.command(['bash', root + '/scripts/build-ios-aarch64.sh', ...flags], env)!
	}
	tools.command(['sh', root + '/tests/ios/build-fixture.sh', build + '/fixtures'], env)!
	if options.with_cxx {
		tools.command(['bash', root + '/tests/ios/build-cxx-fixture.sh', build + '/fixtures'], env)!
		tools.command(['bash', root + '/tests/ios/build-cxx-native.sh', build + '/fixtures'], env)!
	}
	if options.with_gles {
		tools.command(['bash', root + '/tests/ios/build-gles-fixture.sh', build + '/fixtures'], env)!
	}
	mut calculator_env := env.clone()
	calculator_env['VINIX_IOS_CALCULATOR_BUILD_DIR'] = build + '/objc'
	tools.command(['bash', root + '/examples/ios-calculator/build.sh'], calculator_env)!
	if options.with_2048 {
		mut game_env := env.clone()
		game_env['VINIX_IOS_2048_BUILD_DIR'] = build + '/2048'
		tools.command(['bash', root + '/examples/ios-2048/build.sh'], game_env)!
		tools.command(['bash', root + '/tests/ios/build-2048-model.sh'], game_env)!
	}
	if options.with_ppsspp || options.with_gles {
		tools.command([root + '/examples/ios-ppsspp/download', '--output', build + '/ppsspp'], env)!
	}
	if options.ppsspp_cube {
		tools.command([root + '/examples/ios-ppsspp/download-cube', '--output',
			build + '/ppsspp/cube.pbp'], env)!
	}
	if options.ppsspp_nzp {
		tools.command([root + '/examples/ios-ppsspp/download-nzp', '--output', build + '/nzportable'], env)!
	}
	if options.ppsspp_gow {
		tools.command([root + '/examples/ios-ppsspp/download-gow', '--output', build + '/god-of-war'], env)!
	}
}

pub const fixtures = ['calculator', 'calculator-legacy', 'unsupported', 'lifecycle', 'exit-handlers',
	'pointer-tags', 'pointer-tags-legacy', 'core-foundation', 'audio-converter', 'audio-graph',
	'colors', 'provider-images', 'geometry', 'game-constants', 'security', 'security-trust', 'cfnetwork',
	'keychain', 'common-crypto', 'atomic-queue', 'assertions', 'stack-probe', 'libsystem-safety',
	'runes', 'sockets', 'numeric', 'nan', 'poll', 'permissions', 'dispatch', 'fcntl', 'netdb',
	'interfaces', 'system-queries', 'process', 'proc-memory', 'atfork', 'pthread-attr',
	'pthread-condattr', 'pthread-identity', 'pthread-sched', 'pthread-mach', 'ioctl', 'calendar',
	'framework-constants', 'accessibility', 'objc-runtime', 'arc-registers', 'graphics', 'lazy',
	'stdio', 'arc-threads', 'mach-memory']

pub fn stage(build string, work string, options Options) !string {
	rootfs := work + '/rootfs'
	for name in ['root', 'sbin', 'proc', 'sys', 'dev', 'tmp', 'etc', 'opt/ios'] {
		gamehost.mkdir(rootfs + '/' + name)!
	}
	for name, text in {
		'hosts':     '127.0.0.1 localhost\n::1 localhost\n'
		'services':  'domain 53/tcp\ndomain 53/udp\n'
		'protocols': 'icmp 1 ICMP\ntcp 6 TCP\nudp 17 UDP\n'
		'passwd':    'root:*:0:0:Vinix iOS root:/root:/bin/sh\nios-fixture:*:1001:37:' + 'G'.repeat(8192) + ':/var/empty:/bin/false\n'
		'group':     'root:*:0:\nbase:*:37:\nfirst:*:8:ios-fixture\nunrelated:*:9:someone\nsecond:*:11:ios-fixture\n'
	} {
		os.write_file(rootfs + '/etc/' + name, text)!
	}
	destination := rootfs + '/opt/ios'
	os.write_file(destination + '/launch name#é%?.bin', 'native file launch fixture\n')!
	copy_file(build + '/staging/usr/bin/' + if options.with_gles {
		'run-ios-gles'
	} else {
		'run-ios'
	}, destination + '/run-ios')!
	if options.with_gles {
		dependency_tree(build + '/staging/usr/lib/vinix/ios-gles', rootfs + '/usr/lib/vinix/ios-gles')!
		for name in ['gles', 'gles-app', 'compression'] {
			copy_file(build + '/fixtures/' + name, destination + '/' + name)!
		}
		gamehost.copy_tree(build + '/fixtures/TextFixture.app', destination + '/TextFixture.app', true)!
		copy_file(build + '/ppsspp/unpacked/Payload/PPSSPP.app/assets/Roboto_Condensed-Regular.ttf', destination + '/TextFixture.app/font.ttf')!
	}
	for name in fixtures { copy_file(build + '/fixtures/' + name, destination + '/' + name)! }
	os.symlink('permissions-loop', destination + '/permissions-loop')!
	gamehost.copy_tree(build + '/fixtures/SceneFixture.app', destination + '/SceneFixture.app', true)!
	gamehost.copy_tree(build + '/fixtures/Modules.app', destination + '/Modules.app', true)!
	gamehost.copy_tree(destination + '/Modules.app', destination + '/ModulesMissing.app', true)!
	os.rm(destination + '/ModulesMissing.app/Frameworks/Leaf.framework/Leaf')!
	gamehost.copy_tree(destination + '/Modules.app', destination + '/ModulesArm64e.app', true)!
	leaf := destination + '/ModulesArm64e.app/Frameworks/Leaf.framework/Leaf'
	mut unsupported := os.read_bytes(leaf)!
	if unsupported.len < 12 { return error('short dependent Mach-O image') }
	binary.little_endian_put_u32(mut unsupported[8..12], 2)
	os.write_file_array(leaf, unsupported)!
	if options.with_cxx {
		for name in ['cxx', 'cxx-extended', 'cxx-native', 'startup'] {
			copy_file(build + '/fixtures/' + name, destination + '/' + name)!
		}
	}
	copy_file(build + '/objc/Calculator.app/Calculator', destination + '/UIKitCalculator')!
	if options.with_2048 {
		gamehost.copy_tree(build + '/2048/NumberTileGame.app', destination + '/NumberTileGame.app', true)!
		copy_file(build + '/2048/model-tests', destination + '/model-tests')!
	}
	if options.with_ppsspp {
		app := build + '/ppsspp/unpacked/Payload/PPSSPP.app'
		if options.ppsspp_muted {
			asset_tree(app, rootfs + '/usr/share/vinix/ios/PPSSPP.app')!
			os.symlink('/usr/share/vinix/ios/PPSSPP.app/PPSSPP', destination + '/PPSSPP')!
			gamehost.mkdir(rootfs + '/usr/bin')!
			copy_file(build + '/staging/usr/bin/run-ios-gles', rootfs + '/usr/bin/run-ios-gles')!
			os.symlink('run-ios-gles', rootfs + '/usr/bin/vinix-ios-ppsspp')!
			os.write_file(destination + '/ppsspp-muted', '')!
			if options.ppsspp_cube {
				copy_file(build + '/ppsspp/cube.pbp', destination + '/cube.pbp')!
				os.write_file(destination + '/ppsspp-cube', '')!
			}
			if options.ppsspp_nzp {
				game := destination + '/ppsspp-documents/PSP/GAME/nzportable'
				asset_tree(build + '/nzportable/unpacked/nzportable', game)!
				os.write_file(game + '/setup.ini', '-condebug +developer 1 +exec vinix-input.cfg\n')!
				os.write_file(game + '/nzp/vinix-input.cfg', 'bind "SELECT" "edict 1; echo VINIX-NZP-STATE-DONE"\nbinddt "SELECT" ""\n')!
				os.write_file(destination + '/ppsspp-nzp', '')!
			}
			if options.ppsspp_gow {
				game := destination + '/ppsspp-documents/PSP/GAME/UCUS98713'
				asset_tree(build + '/god-of-war/unpacked/PSP/GAME/UCUS98713', game)!
				system := destination + '/ppsspp-documents/PSP/SYSTEM'
				gamehost.mkdir(system)!
				os.write_file(system + '/ppsspp.ini', '[Sound]\nEnable=False\n[Graphics]\nInternalResolution=1\n')!
				os.write_file(destination + '/ppsspp-gow', '')!
			}
		} else {
			asset_tree(app, destination + '/PPSSPP.app')!
			os.symlink('PPSSPP.app/PPSSPP', destination + '/PPSSPP')!
		}
	}
	prepare_images(build + '/fixtures', destination)!
	return rootfs
}

pub fn (tools Tools) compile(work string) ! {
	env := tools.environment
	sdk := env['VINIX_IOS_TEST_SYSROOT'] or { tools.root + '/build-aarch64-userland/sysroot' }
	tools.command([env['CC'] or { 'clang' }, '--target=aarch64-linux-musl', '--sysroot=' + sdk,
		'-static', '-O2', '-fno-stack-protector', '-Wall', '-Wextra', '-Werror',
		tools.root + '/tests/ios/guest.c', tools.root + '/tests/ios/uikit-guest.c',
		tools.root + '/tests/ios/gles-guest.c', '-L' + sdk + '/lib', '-fuse-ld=lld', '-o',
		work + '/init'], env)!
}
