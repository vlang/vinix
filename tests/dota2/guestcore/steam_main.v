// SPDX-License-Identifier: GPL-2.0-or-later
module guestcore

import androidhost as ah

fn steam_settings(options string, root string, preloads string, environment string) ! {
	write(join(root, 'etc/steam-smoke-mode')!, call('operator.add', o(attr(options, 'mode')!), s('\n'))!)!
	for row in [['game_library_priority', 'steam-smoke-game-priority'],
		['pin_network_manager', 'steam-smoke-pin-nm'], ['load_tier0', 'steam-smoke-load-tier0'],
		['strace', 'steam-smoke-strace']] {
		method(join(root, 'etc/' + row[1])!, 'write_text', [s(if truth(attr(options, row[0])!)! {
			'1\n'
		} else {
			'0\n'
		})], {})!
	}
	method(join(root, 'etc/steam-smoke-ld-debug')!, 'write_text', [s(if truth(attr(options, 'ld_debug_bindings')!)! {
		'bindings\n'
	} else {
		'\n'
	})], {})!
	paths := list()!
	items := call('_vm.iterate_value', o(preloads))!
	for {
		item := next(items)!
		if item.done { break }
		append(paths, o(get(item.id, s('guest_path'))!))!
	}
	joined := method(literal(ah.Value(':'))!, 'join', [o(paths)], {})!
	write(join(root, 'etc/steam-smoke-extra-preload')!, call('operator.add', o(joined), s('\n'))!)!
	mut script := "# Target environment; leave native QEMU's loader environment unchanged.\n"
	entries := call('_vm.iterate_value', o(method(environment, 'items', [], {})!))!
	for {
		entry := next(entries)!
		if entry.done { break }
		pair := call('_vm.unpack_pair', o(entry.id))!
		setting := call('operator.add', o(call('operator.add', o(get(pair, n(0))!), s('='))!), o(get(pair, n(1))!))!
		script += 'set -- -E ' + format(call('shlex.quote', o(setting))!)! + ' "$@"\n'
	}
	method(join(root, 'etc/steam-smoke-game-env.sh')!, 'write_text', [s(script)], {})!
}

fn steam_archive(root string, archive string) ! {
	manager := invoke('tarfile.open', [o(archive), s('w:gz')], {
		'compresslevel': n(1)
		'format':        o(call('tarfile.USTAR_FORMAT')!)
	})!
	output := enter(manager)!
	invoke_archive(output, root) or {
		failure := err
		if !retire(manager, failure)! { return failure }
		return
	}
	retire(manager, none)!
}

fn steam_main(options string, parser string) ! {
	game_environment := steam_environment(options, parser)!
	if truth(attr(options, 'load_tier0')!)! {
		call('_vm.set_attribute', o(options), s('game_library_priority'), v(ah.Value(true)))!
	}
	preloads := steam_preloads(options, parser)!
	work := method(attr(options, 'work')!, 'resolve', [], {})!
	mkdir(work)!
	root := join(work, 'root')!
	source := method(attr(options, 'base_root')!, 'resolve', [], {})!
	if eq(root, o(source))! || truth(call('operator.contains', o(attr(root, 'parents')!), o(source))!)! || truth(call('operator.contains', o(attr(source, 'parents')!), o(root))!)! {
		argument_error(parser, 'the smoke fixture must be separate from its source root')!
	}
	steam_source(source, root)!
	runtime := join(root, 'usr/libexec/vinix-dota2/root')!
	binary := join(work, 'steam-smoke')!
	command_line := command([s('clang'), s('--target=x86_64-linux-gnu'), s('-fPIE'), s('-pie'),
		s('-fno-stack-protector'), s('-nostdlib'), s('-fuse-ld=lld'), s('-rdynamic'),
		s('-Wl,--dynamic-linker=/lib64/ld-linux-x86-64.so.2'), s('-Wl,-e,_start'),
		o(str(method(path(global('__file__')!)!, 'with_name', [s('steam-smoke.c')], {})!)!),
		o(str(join(runtime, 'lib/x86_64-linux-gnu/libc.so.6')!)!), s('-o'), o(str(binary)!)])!
	invoke('subprocess.run', [o(command_line)], {
		'check': v(ah.Value(true))
	})!
	call('install', o(binary), o(join(root, 'usr/bin/steam-smoke')!))!
	call('install', o(attr(options, 'library')!), o(join(root, 'usr/libexec/vinix-dota2/smoke/libsteam_api.so')!))!
	steam_copy_preloads(root, preloads)!
	game_bin := steam_game_libraries(options, root)!
	init := join(root, 'sbin/init')!
	call('install', o(method(path(global('__file__')!)!, 'with_name', [s('steam-smoke-init.sh')], {})!), o(init))!
	method(init, 'chmod', [n(0o755)], {})!
	steam_settings(options, root, preloads.records, game_environment)!
	archive := join(work, 'initramfs.tar.gz')!
	steam_archive(root, archive)!
	kernel := join(work, 'kernel/bin/vinix')!
	call('install', o(join(method(attr(options, 'kernel_dir')!, 'resolve', [], {})!, 'bin/vinix')!), o(kernel))!
	environment := call('_vm.mapping_copy', o(call('os.environ')!))!
	for row in [
		['VINIX_KERNEL_DIR', text_id(attr(attr(kernel, 'parent')!, 'parent')!)!],
		['VINIX_INITRAMFS', text_id(archive)!],
		['VINIX_INITRAMFS_COMPRESSED', '1'],
		['VINIX_QEMU_ROOT_DISK', '0'],
		['VINIX_BOOT_DISK', text_id(join(work, 'boot.img')!)!],
		['VINIX_EFIVARS', text_id(join(work, 'efivars.fd')!)!],
		['VINIX_BOOT_DISK_SIZE_MB', '2048'],
		['VINIX_QEMU_PACKAGE_STORE', text_id(join(work, 'packages.tar')!)!],
		['VINIX_QEMU_PACKAGE_PERSIST', '0'],
		['VINIX_QEMU_HOST_SOURCE', '0'],
		['VINIX_QEMU_AUDIO', 'off'],
		['VINIX_QEMU_SMP', '4'],
		['VINIX_KEEP_TEMP_BOOT_DISK', '1'],
		['VINIX_QEMU_EXTRA', ''],
	] {
		set(environment, row[0], s(row[1]))!
	}
	boot_command := command([
		o(str(join(global('REPO')!, 'scripts/run-aarch64.sh')!)!),
		s('--no-build'),
		s('--serial'),
		s('--no-persist'),
		s('--mem=4096'),
	])!
	mut guest := SteamGuest{}
	steam_launch(boot_command, environment, options, work, mut guest)!
	steam_result(options, work, root, kernel, game_bin, preloads.records, game_environment, guest.transcript)!
	release(guest.last_data)!
}

fn steam_result(options string, work string, root string, kernel string, game_bin string, preloads string, environment string, transcript string) ! {
	expected := if eq(attr(options, 'mode')!, s('load'))! {
		'VINIX-DOTA2-STEAM-SMOKE-LOAD-PASS'
	} else {
		'VINIX-DOTA2-STEAM-SMOKE-PASS'
	}
	result := dict()!
	for name in ['mode', 'game_library_priority', 'pin_network_manager', 'load_tier0',
		'ld_debug_bindings'] {
		set(result, name, o(attr(options, name)!))!
	}
	set(result, 'extra_preloads', o(preloads))!
	set(result, 'game_env', o(environment))!
	set(result, 'passed', v(ah.Value(steam_contains(transcript, expected)! && steam_contains(transcript, 'VINIX-DOTA2-STEAM-SMOKE-EXIT: 0')!)))!
	set(result, 'api_returned', v(ah.Value(steam_contains(transcript, 'VINIX-DOTA2-STEAM-SMOKE-RETURN:')!)))!
	set(result, 'completed', v(ah.Value(steam_contains(transcript, 'VINIX-DOTA2-STEAM-SMOKE-END')!)))!
	set(result, 'kernel_sha256', o(steam_file_hash(kernel)!))!
	set(result, 'translator_sha256', o(steam_file_hash(join(root, 'usr/bin/qemu-x86_64')!)!))!
	set(result, 'steam_api_sha256', o(steam_file_hash(attr(options, 'library')!)!))!
	set(result, 'tier0_sha256', o(if truth(attr(options, 'load_tier0')!)! {
		steam_file_hash(join(game_bin, 'libtier0.so')!)!
	} else {
		null_id()!
	}))!
	set(result, 'steamclient_sha256', o(steam_file_hash(join(root, 'home/dota2/.steam/sdk64/steamclient.so')!)!))!
	set(result, 'log', o(str(join(work, 'vinix.log')!)!))!
	write_json(join(work, 'results.json')!, result)!
	print_json(result, true)!
	if !truth(get(result, s('passed'))!)! {
		call('_vm.raise_error', o(call('builtins.SystemExit', n(1))!))!
	}
}
