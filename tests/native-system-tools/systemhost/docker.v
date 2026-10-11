// SPDX-License-Identifier: GPL-2.0-or-later
module systemhost

import diskhost
import guesthost
import hosttest
import os

fn docker(args []string) !int {
	options := parse(args, [hosttest.Option{ name: '--init', value: true },
		hosttest.Option{ name: '--initramfs', value: true },
		hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--timeout', value: true },
		hosttest.Option{ name: '--mem', value: true },
		hosttest.Option{ name: '--pass-marker', value: true },
		hosttest.Option{ name: '--fail-marker', value: true },
		hosttest.Option{ name: '--log', value: true }, hosttest.Option{ name: '--no-build' },
		hosttest.Option{ name: '--kernel-dir', value: true }, hosttest.Option{ name: '--build-only' }],
		['--fail-marker'], 'Usage: run_vm --init FILE --initramfs TAR --state-dir DIR --pass-marker TEXT [--fail-marker TEXT] [--timeout 900] [--mem 4096] [--log FILE] [--no-build] [--kernel-dir DIR] [--build-only]')!
	required(options, ['--init', '--initramfs', '--state-dir', '--pass-marker'])!
	seconds := positive(options, '--timeout', 900)!
	memory := positive(options, '--mem', 4096)!
	state := state_dir(options, 'vinix-docker-')!
	init := resolve(options.value('--init', ''))!
	archive := resolve(options.value('--initramfs', ''))!
	kernel := snapshot(state, kernel_source(options, 'aarch64'), 'aarch64')!
	tree := state + '/init-overlay'
	diskhost.mkdir(tree)!
	run(['tar', '-xf', archive, '-C', tree])!
	diskhost.mkdir(tree + '/sbin')!
	if os.exists(tree + '/sbin/init') || os.is_link(tree + '/sbin/init') {
		os.rm(tree + '/sbin/init')!
	}
	hosttest.module_copy_file_preserving_stat(init, tree + '/sbin/init')!
	os.chmod(tree + '/sbin/init', 0o755)!
	patched := guesthost.archive_tree(tree, state + '/initramfs.tar')!
	configured := guesthost.launch(init, patched, state, kernel, 'aarch64', false)!
	mut argv := configured.command.clone()
	argv[argv.index('-m') + 1] = memory.str()
	if os.getenv('VINIX_QEMU_EXTRA') != '' {
		argv.insert(1, hosttest.shell_split(os.getenv('VINIX_QEMU_EXTRA'))!)
	}
	pass := options.value('--pass-marker', '')
	failures := ['FATAL EXCEPTION', 'KERNEL PANIC', ...options.values['--fail-marker']]
	receipt(state, guesthost.Launch{argv, configured.env}, kernel, init, patched, seconds)!
	if options.has('--build-only') {
		println('Prepared Docker controller: ' + state)
		return 0
	}
	result := guesthost.boot_session(argv, configured.env, state, guesthost.SessionPolicy{
		pass:      pass
		failures:  failures
		lookback:  262144
		settle:    5
		term_wait: 1
		kill_wait: 1
		log:       if options.has('--log') { resolve(options.value('--log', ''))! } else { '' }
	}, seconds, true)!
	if !result.passed {
		return error(if result.finished {
			'failure marker observed'
		} else if result.forced {
			'timeout'
		} else {
			'VM exited without a verdict'
		})
	}
	println('\n==> ' + pass)
	return 0
}
