// SPDX-License-Identifier: GPL-2.0-or-later
module systemhost

import guesthost
import hosttest
import os

pub fn numa_verdict(result guesthost.SessionResult) []string {
	mut failures := []string{}
	for marker in [...features('numa'), 'VINIX QEMU NUMA: PASS'] {
		if result.text.count(marker) != 1 { failures << 'missing expected QEMU result: ' + marker }
	}
	for marker in numa_kernel_markers() {
		if !result.text.contains(marker) { failures << 'missing expected QEMU result: ' + marker }
	}
	for marker in ['VINIX QEMU NUMA: FAIL', 'QEMU NUMA FAIL:', 'FATAL EXCEPTION', 'KERNEL PANIC'] {
		if result.text.contains(marker) { failures << 'observed QEMU failure: ' + marker }
	}
	if result.status != 0 { failures << 'VM runner exit status ' + result.status.str() }
	if result.forced { failures << 'VM did not exit after the test' }
	return failures
}

pub fn numa_topology() []string {
	return ['-object', 'memory-backend-ram,id=vinix-numa0,size=1024M', '-object',
		'memory-backend-ram,id=vinix-numa1,size=1024M', '-numa',
		'node,nodeid=0,cpus=0-1,memdev=vinix-numa0', '-numa',
		'node,nodeid=1,cpus=2-3,memdev=vinix-numa1', '-numa', 'dist,src=0,dst=1,val=20']
}

fn numa(args []string) !int {
	options := parse(args, [hosttest.Option{ name: '--init', value: true },
		hosttest.Option{ name: '--initramfs', value: true },
		hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--timeout', value: true },
		hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--build-fixture' }, hosttest.Option{ name: '--build-only' }], [],
		'Usage: run_vm --init ELF --initramfs TAR --state-dir DIR [--timeout 300] [--kernel-dir DIR]\n       run.sh [--state-dir DIR] [--build-only]')!
	build := options.has('--build-fixture')
	if build && (options.has('--init') || options.has('--initramfs')) {
		return argument('choose --build-fixture or --init with --initramfs')
	}
	if !build { required(options, ['--init', '--initramfs', '--state-dir'])! }
	seconds := if build { env_timeout(options, 300)! } else { positive(options, '--timeout', 300)! }
	state := state_dir(options, 'vinix-numa-')!
	defer { private_cleanup(state, options) }
	init := if build { state + '/init' } else { resolve(options.value('--init', ''))! }
	if build {
		run([...flags('aarch64'), '-fno-stack-protector', root() + '/tests/numa/test.c', '-o',
			init])!
	}
	archive := if build {
		archive_root('', state, ['root', 'sbin', 'sys'])!
	} else {
		resolve(options.value('--initramfs', ''))!
	}
	kernel := snapshot(state, kernel_source(options, 'aarch64'), 'aarch64')!
	runner := resolve(os.getenv_opt('VINIX_VM_RUNNER_ROOT') or { root() })!
	configured := guesthost.serial_arm_launch(init, archive, state, kernel, runner, 2048, '')!
	mut argv := configured.command.clone()
	argv << numa_topology()
	receipt(state, guesthost.Launch{argv, configured.env}, kernel, init, archive, seconds)!
	if options.has('--build-only') {
		println('Prepared NUMA: ' + state)
		return 0
	}
	println('==> Starting AArch64 QEMU boot with two NUMA nodes')
	result := guesthost.boot_session(argv, configured.env, state, guesthost.SessionPolicy{
		pass:              'VINIX QEMU NUMA: PASS'
		failures:          ['VINIX QEMU NUMA: FAIL', 'QEMU NUMA FAIL:', 'FATAL EXCEPTION',
			'KERNEL PANIC']
		settle:            10
		monitor_at_marker: true
	}, seconds, true)!
	failures := numa_verdict(result)
	for failure in failures { eprintln('ERROR: ' + failure) }
	if failures.len != 0 { return 1 }
	println('==> AArch64 QEMU NUMA regression passed')
	return 0
}
