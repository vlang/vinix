// SPDX-License-Identifier: GPL-2.0-or-later
module nativehost

import hosttest
import fixturehost
import policyhost
import os

pub struct GameOptions {
pub:
	base_root          string
	work               string
	desktop            string
	host_source        string
	steamclient        string
	gldriverquery      string
	translator_staging string
	export_state       string
	kernel_dir         string
	userland           string
	sysroot            string
	native_cc          string
	native_readelf     string
	readelf            string
	game_env           []string
	extra_preload      []string
	extra_game_arg     []string
	timeout            int = 900
	memory_mib         int = 8192
	capture_interval   int = 60
	venus              bool
	prepare_only       bool
}

fn game_options(args []string) !GameOptions {
	mut specifications := []hosttest.Option{}
	for name in ['--base-root', '--work', '--desktop', '--host-source', '--steamclient',
		'--gldriverquery', '--translator-staging', '--export-state', '--kernel-dir', '--native-root',
		'--sysroot', '--native-cc', '--native-readelf', '--readelf', '--game-env', '--extra-preload',
		'--extra-game-arg', '--timeout', '--memory-mib', '--capture-interval'] {
		specifications << hosttest.Option{ name: name, value: true }
	}
	specifications << [hosttest.Option{ name: '--venus' }, hosttest.Option{ name: '--prepare-only' }]
	options := parse(args, specifications, ['--game-env', '--extra-preload', '--extra-game-arg'], 'Usage: dota2/run [--base-root DIR --work DIR --desktop ELF --export-state DIR --prepare-only]')!
	seconds := positive(options, '--timeout', 900)!
	memory := positive(options, '--memory-mib', 8192)!
	interval := positive(options, '--capture-interval', 60)!
	game_settings(options.values['--game-env'])!
	work := resolve(options.value('--work', root() + '/build/dota2/game-test'))!
	base := resolve(options.value('--base-root', root() + '/build/dota2-vulkan/test/root'))!
	kernel := resolve(options.value('--kernel-dir', root() + '/kernel'))!
	export_state := resolve(options.value('--export-state', root() + '/build/dota2/linux-export'))!
	separate(work, [base, kernel, export_state])!
	return GameOptions{
		base_root:          base
		work:               work
		kernel_dir:         kernel
		export_state:       export_state
		desktop:            resolve(options.value('--desktop', root() + '/build/vinix-desktop'))!
		host_source:        resolve(options.value('--host-source', root() + '/build-support/xorg-server/winehost/core.v'))!
		steamclient:        resolve(options.value('--steamclient', root() + '/build-aarch64-steam/preseed-home/.local/share/Steam/steamrt64'))!
		gldriverquery:      resolve(options.value('--gldriverquery', root() + '/build-aarch64-steam/preseed-home/.local/share/Steam/ubuntu12_64/gldriverquery'))!
		translator_staging: if options.has('--translator-staging') {
			resolve(options.value('--translator-staging', ''))!
		} else {
			''
		}
		userland:           resolve(options.value('--native-root', root() + '/build-aarch64-userland/staging'))!
		sysroot:            resolve(options.value('--sysroot', root() + '/build-aarch64-x11/sysroot'))!
		native_cc:          options.value('--native-cc', 'aarch64-linux-musl-gcc')
		native_readelf:     options.value('--native-readelf', 'aarch64-linux-musl-readelf')
		readelf:            options.value('--readelf', 'x86_64-linux-musl-readelf')
		game_env:           options.values['--game-env']
		extra_preload:      options.values['--extra-preload']
		extra_game_arg:     options.values['--extra-game-arg']
		timeout:            seconds
		memory_mib:         memory
		capture_interval:   interval
		venus:              options.has('--venus')
		prepare_only:       options.has('--prepare-only')
	}
}

pub fn game_settings(values []string) !map[string]string {
	mut result := map[string]string{}
	for entry in values {
		name := entry.all_before('=')
		if !entry.contains('=') || name == '' || !(name[0].is_letter() || name[0] == `_`) || !name.bytes().all(it.is_alnum() || it == `_`) {
			return argument('Invalid --game-env: ' + entry)
		}
		result[name] = entry.all_after('=')
	}
	return result
}

fn prepare_game(options GameOptions, preloads []Preload) !string {
	rootfs := options.work + '/root'
	if !os.exists(rootfs) {
		if !os.is_file(options.base_root + '/.prepared') {
			return error("Prepare tests/dota2/vulkan-run's root first: " + options.base_root)
		}
		clone_tree(options.base_root, rootfs)!
	}
	refresh_game_runtime(options.base_root, rootfs)!
	runtime := rootfs + '/usr/libexec/vinix-dota2/root'
	trim_game_runtime(runtime)!
	if options.translator_staging != '' {
		overlay_game_translator(options.translator_staging, rootfs, options.userland, options.native_readelf)!
	}
	for name in ['sh', 'cat', 'mkdir', 'chmod', 'sleep', 'kill', 'tail', 'uname', 'mount', 'od',
		'tr', 'ps', 'grep', 'ln', 'ls', 'readlink', 'date'] {
		target := rootfs + '/bin/' + name
		remove_existing(target)!
		os.symlink('busybox', target)!
	}
	directories(rootfs, ['usr/share/games/dota2', 'home/dota2/.steam/sdk64', 'run', 'root'])!
	game_install(options.desktop, rootfs + '/usr/bin/vinix-desktop')!
	remove_existing(rootfs + '/usr/bin/vinix-dota2')!
	os.symlink('vinix-desktop', rootfs + '/usr/bin/vinix-dota2')!
	game_install(here() + '/game-init.sh', rootfs + '/sbin/init')!
	game_install(root() + '/build-support/dota2/run-dota2', rootfs + '/usr/libexec/vinix-dota2/run-dota2')!
	game_install(options.userland + '/bin/zsh', rootfs + '/bin/zsh')!
	for name in ['steamclient.so', 'libtier0_s.so', 'libvstdlib_s.so'] {
		source := options.steamclient + '/' + name
		mut file := os.open(source)!
		header := file.read_bytes(7)
		file.close()
		if header != [u8(0x7f), `E`, `L`, `F`, 2, 1, 1] {
			return error("Expected Valve's actual Linux64 library: " + source)
		}
		game_install(source, rootfs + '/home/dota2/.steam/sdk64/' + name)!
	}
	game_install(options.gldriverquery, rootfs + '/home/dota2/.steam/ubuntu12_64/gldriverquery')!
	stage_game_vulkan_query(options.gldriverquery, rootfs)!
	verify_game_sdk(rootfs, options.readelf)!
	generated := options.work + '/mmap32-probe-v.c'
	run([root() + '/build-support/run-v-tool.sh', root() + '/build-support/dota2/compat.v', 'mmap-probe',
		generated, '--bare'])!
	run(['clang', '--target=x86_64-linux-gnu', '-fPIE', '-pie', '-ffreestanding', '-fno-stack-protector',
		'-nostdlib', '-fuse-ld=lld', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function',
		'-Wno-unused-label', '-Wno-unused-parameter', '-DVINIX_DOTA_BARE_FFI', '-I', here(),
		'-Wl,--dynamic-linker=/lib64/ld-linux-x86-64.so.2', '-Wl,-e,_start', generated,
		here() + '/mmap-probe-start.S', runtime + '/lib/x86_64-linux-gnu/libc.so.6', '-o',
		rootfs + '/usr/libexec/vinix-dota2/mmap32-probe'])!
	mut environment := {
		'HOME':                        '/home/dota2'
		'XDG_RUNTIME_DIR':             '/run/user/0'
		'VALVE_TESTMODE':              '1'
		'LP_NUM_THREADS':              '2'
		'MESA_SHADER_CACHE_DISABLE':   'true'
		'VINIX_DOTA2_LD_LIBRARY_PATH': '/home/dota2/.steam/sdk64'
	}
	for name, value in game_settings(options.game_env)! { environment[name] = value }
	for preload in preloads {
		target := rootfs + preload.guest_path
		os.mkdir_all(os.dir(target))!
		remove_existing(target)!
		os.write_file_array(target, preload.data)!
		os.chmod(target, 0o644)!
	}
	if preloads.len > 0 {
		existing := environment['VINIX_X86_64_PRELOAD']
		environment['VINIX_X86_64_PRELOAD'] = preloads.map(it.guest_path).join(':') + if existing != '' {
			':' + existing
		} else {
			''
		}
	}
	mut exports := []string{}
	for name, value in environment {
		exports << 'export ' + name + '=' + hosttest.shell_join([value])
	}
	launcher := rootfs + '/usr/bin/run-dota2'
	remove_existing(launcher)!
	os.write_file(launcher, '#!/bin/sh\n' + exports.join('\n') + '\n/usr/libexec/vinix-dota2/run-dota2 -insecure -novid -vulkan ' + options.extra_game_arg.map(hosttest.shell_join([it])).join(' ') + ' "$@" &\npid=$!\necho "$pid" > /run/dota2-game.pid\necho "VINIX-DOTA2-GAME-STARTED: $pid"\nstatus=0\nwait "$pid" || status=$?\necho "VINIX-DOTA2-GAME-EXIT: $status"\nexit "$status"\n')!
	os.chmod(launcher, 0o755)!
	mut host_sources := [options.host_source]
	if options.host_source == root() + '/build-support/xorg-server/winehost/core.v' {
		host_core := options.work + '/wine-host-core.c'
		hosttest.generate_module_with_capture(os.dir(options.host_source), host_core, 'arm64', [], game_module_capture)!
		os.write_file(host_core, '#define VINIX_XINPUT_V_RUNTIME 1\n' + os.read_file(host_core)!)!
		host_sources = [host_core, '-I' + root() + '/build-support/xorg-server']
	}
	host := rootfs + '/usr/bin/vinix-wine-host'
	run([options.native_cc, '-O2', '-w', '-D__vinix__', '-I' + options.sysroot + '/usr/include',
		...host_sources, '-L' + options.sysroot + '/usr/lib', '-L' + options.sysroot + '/lib',
		'-Wl,--allow-shlib-undefined', '-lXtst', '-lXdamage', '-lX11', '-lXext', '-lxcb', '-o',
		host])!
	complete_game_native_closure(rootfs, options.userland, [host, rootfs + '/bin/zsh'], options.native_readelf)!
	game_install(options.kernel_dir + '/bin/vinix', options.work + '/kernel/bin/vinix')!
	disk := options.work + '/unused.raw'
	if !os.exists(disk) {
		mut file := os.create(disk)!
		defer { file.close() }
		file.seek(16 * 1024 * 1024 - 1, .start)!
		file.write([u8(0)])!
	}
	for path in [options.work + '/initramfs.tar', options.work + '/initramfs.tar.gz',
		options.work + '/boot-initramfs.tar'] {
		remove_existing(path)!
	}
	return archive(rootfs, options.work, true)!
}

fn game_module_capture(argv []string, directory string, limit int, environment map[string]string) !hosttest.Result {
	result := fixturehost.capture_owned_bounded(argv, environment, policyhost.caller_arch(), directory, limit, policyhost.command_interrupted, false)!
	return hosttest.Result{result.stdout, result.stderr, result.status}
}
