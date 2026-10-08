// SPDX-License-Identifier: GPL-2.0-or-later
module prepcore

import json2

struct Setting {
	name string
mut:
	value string
}

fn set_environment(mut environment []Setting, name string, value string) {
	for mut setting in environment {
		if setting.name == name {
			setting.value = value
			return
		}
	}
	environment << Setting{name, value}
}

fn prepare(work string, repo string) !json2.Any {
	root := join(work, 'root')!
	if !test('exists', root)! {
		base := field('base_root')!
		if !test('is_file', join(base, '.prepared')!)! {
			return failed("Prepare tests/dota2/vulkan-run.py's root first: " + field('base_root')!)
		}
		clone(field('base_root')!, root)!
	}
	refresh_runtime(root)!
	trim_runtime(join(root, 'usr/libexec/vinix-dota2/root')!)!
	if attribute('translator_staging')! != json2.Any(json2.Null{}) {
		overlay_translator(field('translator_staging')!, root, repo)!
	}
	for name in ['sh', 'cat', 'mkdir', 'chmod', 'sleep', 'kill', 'tail', 'uname', 'mount', 'od',
		'tr', 'ps', 'grep', 'ln', 'ls', 'readlink', 'date'] {
		target := join(root, 'bin', name)!
		remove_existing(target)!
		primitive('symlink', [target, 'busybox'])!
	}
	for directory in ['usr/share/games/dota2', 'home/dota2/.steam/sdk64', 'run', 'root'] {
		mkdir(join(root, directory)!)!
	}
	install(field('desktop')!, join(root, 'usr/bin/vinix-desktop')!)!
	link := join(root, 'usr/bin/vinix-dota2')!
	remove_existing(link)!
	primitive('symlink', [link, 'vinix-desktop'])!
	install(join(repo, 'tests/dota2/game-init.sh')!, join(root, 'sbin/init')!)!
	install(join(repo, 'build-support/dota2/run-dota2')!, join(root, 'usr/libexec/vinix-dota2/run-dota2')!)!
	install(join(repo, 'build-aarch64-userland/staging/bin/zsh')!, join(root, 'bin/zsh')!)!
	for name in ['steamclient.so', 'libtier0_s.so', 'libvstdlib_s.so'] {
		source := join(field('steamclient')!, name)!
		if read(source, 7)! != [u8(0x7f), `E`, `L`, `F`, 2, 1, 1] {
			return failed("Expected Valve's actual Linux64 library: " + source)
		}
		install(source, join(root, 'home/dota2/.steam/sdk64', name)!)!
	}
	install(field('gldriverquery')!, join(root, 'home/dota2/.steam/ubuntu12_64/gldriverquery')!)!
	stage_vulkan_query(field('gldriverquery')!, root)!
	verify_sdk_closure(root)!
	runtime := join(root, 'usr/libexec/vinix-dota2/root')!
	generated_probe := join(work, 'mmap32-probe-v.c')!
	checked([decode(primitive('executable', [])!.str())!,
		join(repo, 'build-support/dota2/compile-v-compat.py')!, 'mmap-probe', generated_probe,
		'--bare'])!
	checked(['clang', '--target=x86_64-linux-gnu', '-fPIE', '-pie', '-ffreestanding',
		'-fno-stack-protector', '-nostdlib', '-fuse-ld=lld', '-Wall', '-Wextra', '-Werror',
		'-Wno-unused-function', '-Wno-unused-label', '-Wno-unused-parameter', '-DVINIX_DOTA_BARE_FFI',
		'-I', join(repo, 'tests/dota2')!, '-Wl,--dynamic-linker=/lib64/ld-linux-x86-64.so.2',
		'-Wl,-e,_start', generated_probe, join(repo, 'tests/dota2/mmap-probe-start.S')!,
		join(runtime, 'lib/x86_64-linux-gnu/libc.so.6')!, '-o',
		join(root, 'usr/libexec/vinix-dota2/mmap32-probe')!])!
	mut environment := [
		Setting{'HOME', '/home/dota2'},
		Setting{'XDG_RUNTIME_DIR', '/run/user/0'},
		Setting{'VALVE_TESTMODE', '1'},
		Setting{'LP_NUM_THREADS', '2'},
		Setting{'MESA_SHADER_CACHE_DISABLE', 'true'},
		Setting{'VINIX_DOTA2_LD_LIBRARY_PATH', '/home/dota2/.steam/sdk64'},
	]
	for setting in fields('game_env')! {
		separator := setting.index('=') or { return failed('Invalid --game-env: ' + setting) }
		name := setting[..separator]
		if !callback('regex', {
			'function': json2.Any('fullmatch')
			'args':     encoded([r'[A-Za-z_][A-Za-z0-9_]*', name])
		})!.bool() {
			return failed('Invalid --game-env: ' + setting)
		}
		set_environment(mut environment, name, setting[separator + 1..])
	}
	records := attribute('preload_records')!.as_array()
	if records.len != 0 {
		contents := attribute('preload_contents')!.as_array()
		for index in 0 .. if records.len < contents.len { records.len } else { contents.len } {
			record := records[index].as_map()
			target := join(root, decode(record['guest_path']!.str())!.trim_left('/'))!
			mkdir(parent(target)!)!
			if test('is_symlink', target)! { primitive('unlink', [target])! }
			callback('write_bytes', {
				'args': encoded([target])
				'data': contents[index]
			})!
			chmod(target, 0o644)!
		}
		preloads := records.map(decode(it.as_map()['guest_path']!.str())!).join(':')
		mut existing := ''
		for setting in environment {
			if setting.name == 'VINIX_X86_64_PRELOAD' { existing = setting.value }
		}
		set_environment(mut environment, 'VINIX_X86_64_PRELOAD', preloads + if existing != '' {
			':' + existing
		} else {
			''
		})
	}
	launcher := join(root, 'usr/bin/run-dota2')!
	if test('is_symlink', launcher)! { primitive('unlink', [launcher])! }
	mut exports := []string{}
	for setting in environment { exports << 'export ' + setting.name + '=' + quote(setting.value)! }
	mut game_arguments := []string{}
	for argument in fields('extra_game_arg')! { game_arguments << quote(argument)! }
	primitive('write_text', [launcher, '#!/bin/sh\n' + exports.join('\n') +
		'\n/usr/libexec/vinix-dota2/run-dota2 -insecure -novid -vulkan ' + game_arguments.join(' ') +
		' "$@" &\npid=$!\necho "$pid" > /run/dota2-game.pid\n' +
		'echo "VINIX-DOTA2-GAME-STARTED: $pid"\nstatus=0\nwait "$pid" || status=$?\n' +
		'echo "VINIX-DOTA2-GAME-EXIT: $status"\nexit "$status"\n'])!
	chmod(launcher, 0o755)!
	sysroot := join(repo, 'build-aarch64-x11/sysroot')!
	mut host_sources := [field('host_source')!]
	if field('host_source')! == join(repo, 'build-support/xorg-server/winehost/core.v')! {
		host_core := join(work, 'wine-host-core.c')!
		checked(['python3', join(repo, 'build-support/xorg-server/compile-v-host.py')!, 'winehost',
			host_core, '--arch', 'arm64'])!
		host_sources = [host_core, '-I' + repo + '/build-support/xorg-server']
	}
	checked(['aarch64-linux-musl-gcc', '-O2', '-w', '-D__vinix__', '-I' + sysroot + '/usr/include',
		...host_sources, '-L' + sysroot + '/usr/lib', '-L' + sysroot + '/lib',
		'-Wl,--allow-shlib-undefined', '-lXtst', '-lXdamage', '-lX11', '-lXext', '-lxcb', '-o',
		join(root, 'usr/bin/vinix-wine-host')!])!
	mut binaries := [join(root, 'usr/bin/vinix-wine-host')!, join(root, 'bin/zsh')!]
	closure(root, repo, mut binaries, false)!
	archive := join(work, 'initramfs.tar.gz')!
	callback('archive', {
		'args':   encoded([archive, root, '.'])
		'mode':   json2.Any('w:gz')
		'level':  json2.Any(1)
		'format': json2.Any(0)
	})!
	install(join(field('kernel_dir')!, 'bin/vinix')!, join(work, 'kernel/bin/vinix')!)!
	disk := join(work, 'unused.raw')!
	if !test('exists', disk)! {
		callback('truncate', {
			'args': encoded([disk])
			'mode': json2.Any('xb')
			'size': json2.Any(16 * 1024 * 1024)
		})!
	}
	return json2.Any([json2.Any(root.bytes().hex()), json2.Any(archive.bytes().hex())])
}
