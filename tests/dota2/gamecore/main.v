// SPDX-License-Identifier: GPL-2.0-or-later
module gamecore

import androidhost as ah
import gapcore as gc

fn main_policy(options string) ! {
	preloads := pair_values(call('probe_preloads', o(attr(options, 'extra_preload')!))!)!
	set_attr(options, 'preload_records', o(preloads[0]))!
	set_attr(options, 'preload_contents', o(preloads[1]))!
	for name in ['base_root', 'work', 'desktop', 'host_source', 'steamclient', 'gldriverquery',
		'export_state', 'kernel_dir'] {
		set_attr(options, name, o(method(attr(options, name)!, 'resolve', [], {})!))!
	}
	if !compare('is_', attr(options, 'translator_staging')!, o(null_id()!))! {
		set_attr(options, 'translator_staging', o(method(attr(options, 'translator_staging')!, 'resolve', [], {})!))!
	}
	work := attr(options, 'work')!
	mkdir(work)!
	prepared := pair_values(call('prepare', o(options), o(work))!)!
	root, archive := prepared[0], prepared[1]
	if truth(attr(options, 'prepare_only')!)! {
		call('builtins.print', s('Prepared private game probe: ' + format(root)! + '; ' + format(archive)!))!
		return
	}
	socket := join(work, 'qmp.sock')!
	if truth(method(socket, 'exists', [], {})!)! { method(socket, 'unlink', [], {})! }
	exporter := call('module', s('dota2_ext2_export'), o(join('repo', 'tools/dota2/ext2_export.py')!))!
	mut state := Guest{ transcript: call('builtins.bytearray')!, captures: list()!, failure: null_id()! }
	manager := method(exporter, 'Server', [o(attr(options, 'export_state')!), n(0)], {})!
	server := enter(manager)!
	mut reads := ReadOwner{}
	mut retired := false
	server_policy(server, options, work, socket, archive, mut state, mut reads) or {
		failure := err
		retired = true
		if !retire(manager, failure)! { return failure }
	}
	if !retired { retire(manager, none)! }
	report(state, reads.id, options, work, root)!
}

struct ReadOwner {
mut:
	id string
}

fn server_policy(server string, options string, work string, socket string, archive string, mut state Guest, mut reads ReadOwner) ! {
	reads.id = call('ExportReads', o(attr(server, 'export')!))!
	worker := invoke('threading.Thread', [], {
		'target': o(attr(server, 'serve_forever')!)
	})!
	method(worker, 'start', [], {})!
	server_vm(server, options, work, socket, archive, mut state) or {
		failure := err
		gc.activate(failure, true)!
		method(server, 'shutdown', [], {})!
		method(worker, 'join', [], {})!
		return failure
	}
	method(server, 'shutdown', [], {})!
	method(worker, 'join', [], {})!
}

fn server_vm(server string, options string, work string, socket string, archive string, mut state Guest) ! {
	uri := 'nbd://127.0.0.1:' + format(get(attr(server, 'server_address')!, n(1))!)! + '/'
	env := call('builtins.dict', o(call('os.environ')!))!
	for pair in [['VINIX_KERNEL_DIR', text(join(work, 'kernel')!)!],
		['VINIX_INITRAMFS', text(archive)!], ['VINIX_INITRAMFS_COMPRESSED', '1'],
		['VINIX_QEMU_ROOT_DISK', '0'], ['VINIX_BOOT_DISK', text(join(work, 'boot.img')!)!],
		['VINIX_EFIVARS', text(join(work, 'efivars.fd')!)!], ['VINIX_BOOT_DISK_SIZE_MB', '512'],
		['VINIX_QEMU_PACKAGE_STORE', text(join(work, 'packages.tar')!)!],
		['VINIX_QEMU_PACKAGE_PERSIST', '0'], ['VINIX_QEMU_HOST_SOURCE', '0'],
		['VINIX_QEMU_PERSIST_DISK', text(join(work, 'unused.raw')!)!], ['VINIX_QEMU_PERSIST', '1'],
		['VINIX_QEMU_AUDIO', 'off'], ['VINIX_QEMU_SMP', '4'], ['VINIX_KEEP_TEMP_BOOT_DISK', '1'],
		['VINIX_QEMU_EXTRA',
			'-qmp unix:' + format(socket)! + ',server=on,wait=off -drive if=none,id=dota-data,file=' + uri + ',format=raw,readonly=on -device virtio-blk-device,drive=dota-data']] {
		set(env, pair[0], s(pair[1]))!
	}
	firmware := join('repo', 'boot-image/edk2-aarch64-code-2048x1536.fd')!
	if truth(method(firmware, 'is_file', [], {})!)! {
		set(env, 'VINIX_OVMF_CODE', o(call('builtins.str', o(firmware))!))!
		set(env, 'VINIX_QEMU_RESOLUTION', s('2048x1536x32'))!
	}
	if !eq(call('platform.system')!, s('Darwin'))! {
		method(env, 'setdefault', [s('USE_TCG'), s('1')], {})!
	}
	launch_args := command([
		o(call('builtins.str', o(join('repo', 'scripts/run-aarch64.sh')!))!),
		s('--no-build'),
		s(if truth(attr(options, 'venus')!)! { '--venus' } else { '--serial' }),
		s('--mem=' + format(attr(options, 'memory_mib')!)!),
	])!
	invoke('builtins.print', [s('Real game probe artifacts: ' + format(work)! + '; read-only game disk: ' + uri)], {
		'flush': v(ah.Value(true))
	})!
	launch(launch_args, env, options, work, socket, mut state)!
}

fn report(state Guest, reads string, options string, work string, root string) ! {
	result := dict()!
	set(result, 'status', s(if truth(state.failure)! { 'failed' } else { 'captured_for_review' }))!
	set(result, 'guest_memory_mib', o(attr(options, 'memory_mib')!))!
	set(result, 'gpu', s(if truth(attr(options, 'venus')!)! { 'venus' } else { 'software' }))!
	set(result, 'failure', o(state.failure))!
	set(result, 'rendering_verified', v(ah.Value(false)))!
	set(result, 'game_started', o(call('game_start_observed', o(state.transcript))!))!
	set(result, 'anonymous_steam_initialized', o(call('operator.contains', o(state.transcript), b('initialized steam in anonymous user mode'.bytes().hex()))!))!
	matched := call('re.search', b(r'VINIX-DOTA2-GAME-EXIT:\s*(\d+)'.bytes().hex()), o(state.transcript))!
	set(result, 'game_exit_status', o(if truth(matched)! {
		call('builtins.int', o(get(matched, n(1))!))!
	} else {
		null_id()!
	}))!
	for pair in [['kernel_sha256', join(work, 'kernel/bin/vinix')!],
		['desktop_sha256', join(root, 'usr/bin/vinix-desktop')!],
		['translator_sha256', join(root, 'usr/bin/qemu-x86_64')!]] {
		set(result, pair[0], o(call('sha256', o(pair[1]))!))!
	}
	staging := attr(options, 'translator_staging')!
	set(result, 'translator_staging', o(if truth(staging)! {
		call('builtins.str', o(staging))!
	} else {
		null_id()!
	}))!
	set(result, 'launcher_sha256', o(call('sha256', o(join(root, 'usr/libexec/vinix-dota2/run-dota2')!))!))!
	generation := method(method(join(root, 'usr/libexec/vinix-dota2/root/.vinix-dota2-vulkan-generation')!, 'read_text', [], {})!, 'strip', [], {})!
	set(result, 'runtime_generation', o(generation))!
	set(result, 'extra_game_arguments', o(attr(options, 'extra_game_arg')!))!
	settings := dict()!
	entries := iter(attr(options, 'game_env')!)!
	for {
		row := next(entries)!
		if row.done { break }
		parts := pair_values(method(row.id, 'split', [s('='), n(1)], {})!)!
		call('operator.setitem', o(settings), o(parts[0]), o(parts[1]))!
	}
	set(result, 'extra_game_environment', o(settings))!
	set(result, 'extra_preloads', o(attr(options, 'preload_records')!))!
	set(result, 'steamclient_sha256', o(call('sha256', o(join(root, 'home/dota2/.steam/sdk64/steamclient.so')!))!))!
	query := join(root, 'home/dota2/.steam/ubuntu12_64/vulkandriverquery')!
	set(result, 'vulkandriverquery_sha256', o(if truth(method(query, 'is_file', [], {})!)! {
		call('sha256', o(query))!
	} else {
		null_id()!
	}))!
	set(result, 'export_manifest_sha256', o(call('sha256', o(join(attr(options, 'export_state')!, 'manifest.json')!))!))!
	if reads == '' {
		gc.callback('raise_builtin', {
			'kind':  ah.Value('UnboundLocalError')
			'value': s("local variable 'reads' referenced before assignment")
		})!
	}
	set(result, 'export_reads', o(method(reads, 'report', [], {})!))!
	set(result, 'captures', o(state.captures))!
	set(result, 'log', o(call('builtins.str', o(join(work, 'vinix.log')!))!))!
	write_json(join(work, 'results.json')!, result)!
	print_json(result, true)!
	gc.callback('raise_builtin', {
		'kind':  ah.Value('SystemExit')
		'value': n(if truth(state.failure)! { 1 } else { 2 })
	})!
}
