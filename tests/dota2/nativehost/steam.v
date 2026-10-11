// SPDX-License-Identifier: GPL-2.0-or-later
module nativehost

import buildcore
import crypto.sha256
import guesthost
import hosttest
import json2
import os

pub fn game_environment(entries []string) !map[string]string {
	mut result := map[string]string{}
	for entry in entries {
		name := entry.all_before('=')
		if !entry.contains('=') || name == '' || !(name[0].is_letter() || name[0] == `_`)
			|| !name.bytes().all(it.is_alnum() || it == `_`) {
			return argument('invalid --game-env: ' + entry)
		}
		value := entry.all_after('=')
		if value.contains('\x00') || value.contains(',') {
			return argument("--game-env values cannot contain NUL or QEMU's comma separator")
		}
		result[name] = value
	}
	return result
}

struct Preload {
	source     string
	sha256     string
	guest_path string
	data       []u8 @[json: '-']
}

fn steam(args []string) !int {
	options := parse(args, [hosttest.Option{ name: '--base-root', value: true },
		hosttest.Option{ name: '--work', value: true },
		hosttest.Option{ name: '--library', value: true },
		hosttest.Option{ name: '--kernel-dir', value: true }, hosttest.Option{
			name:    '--mode'
			value:   true
			choices: ['anonymous', 'safe', 'safe-anonymous', 'load']
		}, hosttest.Option{ name: '--game-library-priority' },
		hosttest.Option{ name: '--pin-network-manager' }, hosttest.Option{ name: '--load-tier0' },
		hosttest.Option{ name: '--ld-debug-bindings' },
		hosttest.Option{ name: '--extra-preload', value: true },
		hosttest.Option{ name: '--game-env', value: true }, hosttest.Option{ name: '--strace' },
		hosttest.Option{ name: '--timeout', value: true }, hosttest.Option{ name: '--prepare-only' }], [
		'--extra-preload',
		'--game-env',
	], 'Usage: steam-smoke-run [--base-root DIR --work DIR --library ELF --mode anonymous|safe|safe-anonymous|load --prepare-only]')!
	seconds := positive(options, '--timeout', 600)!
	game_env := game_environment(options.values['--game-env'])!
	priority := options.has('--game-library-priority') || options.has('--load-tier0')
	mode := options.value('--mode', 'anonymous')
	mut preloads := []Preload{}
	for index, path in options.values['--extra-preload'] {
		source := resolve(path)!
		data := os.read_bytes(source) or { return argument('extra preload is not a file: ' + source) }
		if !buildcore.shared_elf(data) {
			return argument('extra preload must be a Linux x86-64 shared ELF: ' + source)
		}
		preloads << Preload{source, sha256.sum(data).hex(), '/usr/libexec/vinix-dota2/smoke/preloads/extra-' + index.str() + '.so', data}
	}
	work := resolve(options.value('--work', root() + '/build/dota2-steam-smoke'))!
	source := resolve(options.value('--base-root', root() + '/build/dota2/game-test/root'))!
	rootfs := work + '/root'
	separate(rootfs, [source])!
	library := resolve(options.value('--library', root() + '/build/dota2/steamcmd/steamapps/content/app_570/depot_373306/game/bin/linuxsteamrt64/libsteam_api.so'))!
	kernel_dir := resolve(options.value('--kernel-dir', root() + '/kernel'))!
	separate(work, [kernel_dir])!
	mut identity := {
		'source': json2.Any(source)
	}
	for relative in ['usr/libexec/vinix-dota2/root/.vinix-dota2-vulkan-generation',
		'home/dota2/.steam/sdk64/steamclient.so', 'home/dota2/.steam/sdk64/libtier0_s.so',
		'home/dota2/.steam/sdk64/libvstdlib_s.so', 'home/dota2/.steam/ubuntu12_64/gldriverquery',
		'usr/bin/qemu-x86_64', 'usr/bin/Xvfb'] {
		identity[relative] = json2.Any(hosttest.sha(source + '/' + relative)!)
	}
	os.mkdir_all(work)!
	stamp := rootfs + '/.steam-smoke-source.json'
	previous := if os.is_file(stamp) {
		json2.decode[json2.Any](os.read_file(stamp)!)!
	} else {
		json2.Any(json2.Null{})
	}
	if previous != json2.Any(identity) {
		if os.exists(rootfs) { os.rmdir_all(rootfs)! }
		$if macos {
			run(['/bin/cp', '-cRp', source, rootfs])!
		} $else {
			os.cp_all(source, rootfs, false)!
		}
		write_json(stamp, json2.Any(identity))!
	}
	runtime := rootfs + '/usr/libexec/vinix-dota2/root'
	binary := work + '/steam-smoke'
	run(['clang', '--target=x86_64-linux-gnu', '-fPIE', '-pie', '-fno-stack-protector', '-nostdlib',
		'-fuse-ld=lld', '-rdynamic', '-Wl,--dynamic-linker=/lib64/ld-linux-x86-64.so.2', '-Wl,-e,_start',
		here() + '/steam-smoke.c', runtime + '/lib/x86_64-linux-gnu/libc.so.6', '-o', binary])!
	install(binary, rootfs + '/usr/bin/steam-smoke')!
	install(library, rootfs + '/usr/libexec/vinix-dota2/smoke/libsteam_api.so')!
	for preload in preloads {
		destination := rootfs + preload.guest_path
		os.mkdir_all(os.dir(destination))!
		if os.is_link(destination) { os.rm(destination)! }
		if os.exists(destination) { os.chmod(destination, 0o600)! }
		os.write_file_array(destination, preload.data)!
		os.chmod(destination, 0o644)!
	}
	game_bin := rootfs + '/usr/libexec/vinix-dota2/smoke/game-bin'
	if priority {
		os.mkdir_all(game_bin)!
		for name in os.ls(os.dir(library))! {
			path := os.dir(library) + '/' + name
			if os.is_file(path) && (name.ends_with('.so') || name.contains('.so.')) {
				install(path, game_bin + '/' + name)!
			}
		}
	}
	install(here() + '/steam-smoke-init.sh', rootfs + '/sbin/init')!
	os.chmod(rootfs + '/sbin/init', 0o755)!
	os.mkdir_all(rootfs + '/etc')!
	for name, value in {
		'mode':          mode
		'game-priority': if priority { '1' } else { '0' }
		'pin-nm':        if options.has('--pin-network-manager') { '1' } else { '0' }
		'load-tier0':    if options.has('--load-tier0') { '1' } else { '0' }
		'strace':        if options.has('--strace') { '1' } else { '0' }
		'ld-debug':      if options.has('--ld-debug-bindings') { 'bindings' } else { '' }
		'extra-preload': preloads.map(it.guest_path).join(':')
	} {
		os.write_file(rootfs + '/etc/steam-smoke-' + name, value + '\n')!
	}
	mut environment_script := "# Target environment; leave native QEMU's loader environment unchanged.\n"
	for name, value in game_env {
		environment_script += 'set -- -E ' + hosttest.shell_join([name + '=' + value]) + ' "$@"\n'
	}
	os.write_file(rootfs + '/etc/steam-smoke-game-env.sh', environment_script)!
	tar := archive(rootfs, work, true)!
	install(kernel_dir + '/bin/vinix', work + '/kernel/bin/vinix')!
	mut report := {
		'mode':                  json2.Any(mode)
		'game_library_priority': json2.Any(priority)
		'pin_network_manager':   json2.Any(options.has('--pin-network-manager'))
		'load_tier0':            json2.Any(options.has('--load-tier0'))
		'ld_debug_bindings':     json2.Any(options.has('--ld-debug-bindings'))
		'extra_preloads':        json2.decode[json2.Any](json2.encode(preloads))!
		'game_env':              json2.decode[json2.Any](json2.encode(game_env))!
		'kernel_sha256':         json2.Any(hosttest.sha(work + '/kernel/bin/vinix')!)
		'translator_sha256':     json2.Any(hosttest.sha(rootfs + '/usr/bin/qemu-x86_64')!)
		'steam_api_sha256':      json2.Any(hosttest.sha(library)!)
		'tier0_sha256':          if options.has('--load-tier0') {
			json2.Any(hosttest.sha(game_bin + '/libtier0.so')!)
		} else {
			json2.Any(json2.Null{})
		}
		'steamclient_sha256':    json2.Any(hosttest.sha(rootfs + '/home/dota2/.steam/sdk64/steamclient.so')!)
		'archive_sha256':        json2.Any(hosttest.sha(tar)!)
	}
	write_json(work + '/inputs.json', json2.Any(report))!
	if options.has('--prepare-only') {
		print_json(json2.Any(report))
		return 0
	}
	configured := launch(work, tar, 4096, 4, root(), true)!
	result := guesthost.boot_session(configured.command, configured.env, work, guesthost.SessionPolicy{ pass: 'VINIX-DOTA2-STEAM-SMOKE-END', failures: ['KERNEL PANIC'], log: work + '/vinix.log', cleanup_wait: 0, term_wait: 5, kill_wait: 5 }, seconds, true)!
	expected := if mode == 'load' {
		'VINIX-DOTA2-STEAM-SMOKE-LOAD-PASS'
	} else {
		'VINIX-DOTA2-STEAM-SMOKE-PASS'
	}
	report['passed'] = json2.Any(result.text.contains(expected) && result.text.contains('VINIX-DOTA2-STEAM-SMOKE-EXIT: 0'))
	report['api_returned'] = json2.Any(result.text.contains('VINIX-DOTA2-STEAM-SMOKE-RETURN:'))
	report['completed'] = json2.Any(result.text.contains('VINIX-DOTA2-STEAM-SMOKE-END'))
	report['log'] = json2.Any(work + '/vinix.log')
	write_json(work + '/results.json', json2.Any(report))!
	print_json(json2.Any(report))
	return if report['passed']!.bool() { 0 } else { 1 }
}
