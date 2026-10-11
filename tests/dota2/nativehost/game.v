// SPDX-License-Identifier: GPL-2.0-or-later
module nativehost

import ext2host
import fixturehost
import guesthost
import hosttest
import json2
import os
import policyhost
import qemuhost

pub fn game_start_observed(text string) bool {
	return text.contains('VINIX-DOTA2-GAME-STARTED:') || text.contains('VINIX-DOTA2-GAME-ALIVE')
}

pub fn game_exit_status(text string) ?string {
	needle := 'VINIX-DOTA2-GAME-EXIT:'
	mut at := 0
	for at < text.len {
		at += text[at..].index(needle) or { return none }
		at += needle.len
		for at < text.len && text[at] in [u8(9), 10, 11, 12, 13, 32] { at++ }
		start := at
		for at < text.len && text[at] >= `0` && text[at] <= `9` { at++ }
		if at > start { return text[start..at].clone() }
	}
	return none
}

fn take_game_screenshot(socket string, target string) bool {
	if !os.exists(socket) { return false }
	mut env := policyhost.environment()
	env['VINIX_QMP_SOCKET'] = socket
	tool := os.getenv_opt('VINIX_DOTA_SCREENSHOT') or { root() + '/desktop/tools/screenshot.sh' }
	result := fixturehost.capture_owned_bounded([tool, target], env, policyhost.caller_arch(), '', 35, game_command_interrupted, false) or {
		println('Screenshot unavailable: ' + err.msg())
		return false
	}
	if result.status != 0 {
		println('Screenshot unavailable: ' + result.stderr.trim_space())
		return false
	}
	println('Actual guest capture: ' + target)
	return true
}

fn game_command_interrupted() bool {
	return policyhost.command_interrupted() || guesthost.game_capture_interrupted()
}

fn game_launch(options GameOptions, tar string, uri string) !guesthost.Launch {
	firmware := root() + '/boot-image/edk2-aarch64-code-2048x1536.fd'
	previous := os.getenv_opt('VINIX_OVMF_CODE')
	if os.is_file(firmware) { os.setenv('VINIX_OVMF_CODE', firmware, true) }
	defer {
		if value := previous {
			os.setenv('VINIX_OVMF_CODE', value, true)
		} else {
			os.unsetenv('VINIX_OVMF_CODE')
		}
	}
	configured := launch(options.work, tar, options.memory_mib, 4, root(), true)!
	mut command := configured.command.clone()
	mut env := configured.env.clone()
	command << ['-drive', 'if=none,id=vinix-persist,file=' + options.work + '/unused.raw,format=raw',
		'-device', 'virtio-blk-device,drive=vinix-persist']
	command << ['-drive', 'if=none,id=dota-data,file=' + uri + ',format=raw,readonly=on', '-device',
		'virtio-blk-device,drive=dota-data']
	if !options.prepare_only {
		config := options.work + '/game-limine.conf'
		run(['xorriso', '-osirrox', 'on', '-indev', options.work + '/test.iso', '-extract',
			'/boot/limine.conf', config])!
		mut lines := os.read_file(config)!.split_into_lines()
		mut replaced := false
		for index, line in lines {
			if os.is_file(firmware) && line.trim_space().starts_with('resolution:') {
				lines[index] = '    resolution: 2048x1536x32'
				replaced = true
			}
		}
		if os.is_file(firmware) && !replaced { lines << '    resolution: 2048x1536x32' }
		mut command_line := false
		for index, line in lines {
			if line.trim_space().starts_with('cmdline:') {
				lines[index] = line.replace('vinix.disk=auto', '').trim_right(' ') + ' vinix.qemu_persist=1'
				command_line = true
			}
		}
		if !command_line { lines << '    cmdline: vinix.qemu_persist=1' }
		os.chmod(config, 0o600)!
		os.write_file(config, lines.join('\n') + '\n')!
		patched := options.work + '/game.iso'
		run(['xorriso', '-indev', options.work + '/test.iso', '-outdev', patched, '-map', config,
			'/boot/limine.conf', '-boot_image', 'any', 'replay'])!
		os.mv(patched, options.work + '/test.iso')!
	}
	if options.venus {
		kekvm := os.getenv_opt('VINIX_KEKVM_DIR') or { root() + '/../kekvm' }
		source := os.getenv_opt('VINIX_VIRGL_QEMU') or { kekvm + '/.tools/qemu-virgl/bin/kekvm-qemu-system-aarch64' }
		prefix := os.dir(os.dir(source))
		mut selected := os.getenv_opt('VINIX_DOTA_VENUS_QEMU') or { source }
		$if macos {
			if os.getenv('VINIX_DOTA_VENUS_QEMU') == '' {
				selected = options.work + '/vinix-venus-qemu-system-aarch64'
				qemuhost.prepare(source, selected)!
			}
			library := root() + '/build/virglrenderer-host/lib'
			if !os.is_file(library + '/libvirglrenderer.1.dylib') {
				return error('Prepare the Vinix VirGL renderer before using --venus')
			}
			env['DYLD_LIBRARY_PATH'] = library + ':' + prefix + '/lib'
		}
		if !os.is_executable(selected) { return error('Prepared Venus QEMU missing: ' + selected) }
		command[0] = selected
		command[command.index('-display') + 1] = os.getenv_opt('QEMU_DISPLAY_BACKEND') or {
			$if macos {
				'cocoa,gl=es'
			} $else {
				'default,gl=on'
			}
		}
		command << ['-device', 'virtio-gpu-gl-pci,blob=on,hostmem=4G,venus=on,max_outputs=1']
		env['VK_DRIVER_FILES'] = prefix + '/share/vulkan/icd.d/libkosmickrisp_icd.json'
		env['DYLD_FALLBACK_LIBRARY_PATH'] = prefix + '/lib:/usr/local/lib:/usr/lib'
	}
	return guesthost.Launch{command, env}
}

fn game(args []string) !int {
	options := game_options(args)!
	preloads := game_preloads(options.extra_preload)!
	os.mkdir_all(options.work)!
	tar := prepare_game(options, preloads)!
	rootfs := options.work + '/root'
	if options.prepare_only {
		println('Prepared private game probe: ' + rootfs + '; ' + tar)
		return 0
	}
	socket := options.work + '/qmp.sock'
	remove_existing(socket)!
	mut server := ext2host.serve(options.export_state, 0, '', 3, 30000)!
	defer { server.close() }
	server.observe_reads()
	uri := 'nbd://127.0.0.1:' + server.port.str() + '/'
	configured := game_launch(options, tar, uri)!
	mut argv := configured.command.clone()
	mut bridge := &guesthost.GameNetwork(unsafe { nil })
	defer { if !isnil(bridge) { bridge.close() } }
	if options.venus && argv.contains('-netdev') && !capture([argv[0], '-machine', 'virt', '-netdev',
		'help'])!.split_into_lines().contains('user') {
		backend := os.getenv_opt('VINIX_NETWORK_QEMU') or { 'qemu-system-aarch64' }
		if !capture([backend, '-machine', 'virt', '-netdev', 'help'])!.split_into_lines().contains('user') {
			return error('VirGL networking needs QEMU with the user backend; set VINIX_NETWORK_QEMU')
		}
		bridge = guesthost.game_network(backend, configured.env, options.work + '/network-bridge.log')!
		argv[argv.index('-netdev') + 1] = 'stream,id=net0,server=off,addr.type=unix,addr.path=' + bridge.socket
	}
	println('Real game probe artifacts: ' + options.work + '; read-only game disk: ' + uri)
	result := guesthost.capture_game(argv, configured.env, options.work, socket, options.timeout, options.capture_interval, take_game_screenshot, true)!
	if !isnil(bridge) { bridge.close() }
	server.close()
	query := rootfs + '/home/dota2/.steam/ubuntu12_64/vulkandriverquery'
	mut report := {
		'status':                      json2.Any(if result.failure == '' {
			'captured_for_review'
		} else {
			'failed'
		})
		'guest_memory_mib':            json2.Any(options.memory_mib)
		'gpu':                         json2.Any(if options.venus { 'venus' } else { 'software' })
		'failure':                     if result.failure == '' {
			json2.Any(json2.Null{})
		} else {
			json2.Any(result.failure)
		}
		'rendering_verified':          json2.Any(false)
		'game_started':                json2.Any(game_start_observed(result.text))
		'anonymous_steam_initialized': json2.Any(result.text.contains('initialized steam in anonymous user mode'))
		'game_exit_status':            json2.Any(json2.Null{})
		'translator_staging':          if options.translator_staging == '' {
			json2.Any(json2.Null{})
		} else {
			json2.Any(options.translator_staging)
		}
		'runtime_generation':          json2.Any(os.read_file(rootfs + '/usr/libexec/vinix-dota2/root/.vinix-dota2-vulkan-generation')!.trim_space())
		'extra_game_arguments':        json2.decode[json2.Any](json2.encode(options.extra_game_arg))!
		'extra_game_environment':      json2.decode[json2.Any](json2.encode(game_settings(options.game_env)!))!
		'extra_preloads':              json2.decode[json2.Any](json2.encode(preloads))!
		'vulkandriverquery_sha256':    if os.is_file(query) {
			json2.Any(hosttest.sha(query)!)
		} else {
			json2.Any(json2.Null{})
		}
		'export_reads':                json2.decode[json2.Any](json2.encode(server.read_report()))!
		'captures':                    json2.decode[json2.Any](json2.encode(result.captures))!
		'log':                         json2.Any(options.work + '/vinix.log')
	}
	for name, path in {
		'kernel_sha256':          options.work + '/kernel/bin/vinix'
		'desktop_sha256':         rootfs + '/usr/bin/vinix-desktop'
		'translator_sha256':      rootfs + '/usr/bin/qemu-x86_64'
		'launcher_sha256':        rootfs + '/usr/libexec/vinix-dota2/run-dota2'
		'steamclient_sha256':     rootfs + '/home/dota2/.steam/sdk64/steamclient.so'
		'export_manifest_sha256': options.export_state + '/manifest.json'
	} {
		report[name] = json2.Any(hosttest.sha(path)!)
	}
	mut encoded := json2.encode(json2.Any(report), prettify: true)
	if status := game_exit_status(result.text) {
		normalized := status.trim_left('0')
		encoded = encoded.replace('"game_exit_status": null', '"game_exit_status": ' + if normalized == '' {
			'0'
		} else {
			normalized
		})
	}
	os.write_file(options.work + '/results.json', encoded + '\n')!
	println(encoded)
	return if result.failure == '' { 2 } else { 1 }
}
