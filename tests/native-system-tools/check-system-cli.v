// SPDX-License-Identifier: GPL-2.0-or-later
module main

import diskhost
import fixturehost
import guesthost
import hosttest
import json2
import os
import policyhost
import time

// A controlled serial process exercises the entire CLI/SDK/PTY path. It does
// not execute the guest kernel or stand in for guest security/storage evidence.
fn machine() ! {
	os.write_file(os.getenv('VINIX_SYSTEM_MODEL_ARGV'), os.args[1..].join('\n'))!
	mode := os.getenv('VINIX_SYSTEM_MODEL')
	if mode == 'root' {
		for _ in 0 .. 2 {
			println('VINIX DISK ROOT: START\nVINIX DISK ROOT: ON VOLUME\nVINIX DISK ROOT: LARGE FILE OK')
		}
		println('VINIX DISK ROOT: WROTE /etc MARKER, REBOOTING\nVINIX DISK ROOT: PASS')
	} else if mode == 'failure' {
		println('MODEL FAILURE')
	} else if mode != 'empty' {
		print('MODEL ')
		flush_stdout()
		time.sleep(20 * time.millisecond)
		println('PASS')
	}
	flush_stdout()
	if mode == 'late' {
		time.sleep(50 * time.millisecond)
		println('MODEL FAILURE')
		flush_stdout()
	}
	time.sleep(150 * time.millisecond)
	if mode == 'nonzero' { exit(7) }
}

fn capture(argv []string, env map[string]string) !fixturehost.CapturedCommand {
	return fixturehost.capture_owned_bounded(argv, env, policyhost.caller_arch(), '', -1,
		policyhost.command_interrupted, false)!
}

fn run(argv []string) !string {
	result := capture(argv, policyhost.environment())!
	if result.status != 0 { return error(result.stdout + result.stderr) }
	return result.stdout
}

fn check_command(command string, args []string, env map[string]string, status int, log string) ! {
	result := capture([command, ...args], env)!
	os.write_file(log, result.stdout + result.stderr)!
	if result.status != status {
		return error('Expected ' + status.str() + ', got ' + result.status.str() + '; inspect ' + log + '\n' + result.stdout + result.stderr)
	}
}

fn checked() ! {
	if os.args.len != 4 { return error('check-system-cli CONTROLLER-PREFIX PROFILE KERNEL-DIR') }
	prefix, profile, kernel := os.args[1], os.args[2], os.args[3]
	work := hosttest.work_dir('', 'vinix-system-cli-')!
	defer { hosttest.remove_work_dir(work) or { eprintln(err) } }
	qemu := os.find_abs_path_of_executable('qemu-system-aarch64')!
	share := os.dir(os.dir(qemu)) + '/share/qemu'
	mut env := policyhost.environment()
	env['VINIX_QEMU_BIN'] = os.executable()
	env['VINIX_OVMF_CODE'] = share + '/edk2-aarch64-code.fd'
	env['VINIX_OVMF_VARS'] = share + '/edk2-arm-vars.fd'
	env['USE_TCG'] = '1'
	env['VINIX_QEMU_EXTRA'] = "-name 'model extra'"
	env['VINIX_SYSTEM_MODEL_ARGV'] = work + '/model-argv'
	diskhost.mkdir(work + '/base/sbin')!
	os.write_file(work + '/base/sbin/init', 'old init')!
	os.write_file(work + '/provided-init', '#!/bin/sh\nexit 0\n')!
	archive := guesthost.archive_tree(work + '/base', work + '/base.tar')!
	for mode in ['pass', 'nonzero', 'late', 'failure', 'empty'] {
		state := work + '/docker-' + mode
		diskhost.mkdir(state)!
		env['VINIX_SYSTEM_MODEL'] = mode
		check_command(prefix + 'docker-' + profile, ['--init', work + '/provided-init', '--initramfs',
			archive, '--kernel-dir', kernel, '--state-dir', state, '--mem', '1234', '--pass-marker',
			'MODEL PASS', '--fail-marker', 'MODEL FAILURE', '--fail-marker', 'OTHER FAIL', '--log',
			state + '/raw.log', '--no-build'], env,
			if mode in ['failure', 'empty'] { 1 } else { 0 }, state + '/controller.log')!
		assert os.read_file(state + '/init-overlay/sbin/init')! == os.read_file(work + '/provided-init')!
		assert os.read_file(state + '/raw.log')! == os.read_file(state + '/serial.log')!
		assert os.read_file(work + '/model-argv')!.contains('-m\n1234\n')
		assert os.read_file(work + '/model-argv')!.starts_with('-name\nmodel extra\n-machine\n')
		if mode == 'late' {
			assert os.read_file(state + '/serial.log')!.contains('MODEL FAILURE')
		}
		hosttest.remove_work_dir(state)!
	}
	println('PASS full Docker CLI: init overlay, memory, raw log, first verdict, nonzero exit and late failure')

	env['VINIX_SYSTEM_MODEL'] = 'root'
	state := work + '/root-state'
	diskhost.mkdir(state)!
	for dir in ['sbin', 'root', 'etc'] { diskhost.mkdir(work + '/system/' + dir)! }
	os.write_file(work + '/system/sbin/init', 'controlled init')!
	os.write_file(work + '/system/root/seed', 'seed')!
	os.write_file(work + '/system/etc/version', 'one')!
	image := guesthost.archive_tree(work + '/system', work + '/system.tar')!
	diskhost.mkdir(work + '/overlay/etc')!
	os.write_file(work + '/overlay/etc/package-marker', 'merged package')!
	guesthost.archive_tree(work + '/overlay', state + '/packages.tar')!
	args := ['--image', image, '--kernel-dir', kernel, '--state-dir', state]
	command := prefix + 'disk-root-' + profile
	check_command(command, args, env, 0, state + '/first.log')!
	debugfs := os.find_abs_path_of_executable('/opt/homebrew/opt/e2fsprogs/sbin/debugfs')!
	disk := state + '/root.ext2'
	assert run([debugfs, '-R', 'cat /etc/package-marker', disk])! == 'merged package'
	assert run([debugfs, '-R', 'cat /etc/version', disk])! == 'one'
	os.write_file(work + '/home-user', 'user data')!
	run([debugfs, '-w', '-R', 'write ' + work + '/home-user /root/user-file', disk])!
	before := hosttest.sha(disk)!
	check_command(command, args, env, 0, state + '/same-image.log')!
	assert hosttest.sha(disk)! == before
	os.write_file(work + '/system/etc/version', 'two'.repeat(20000))!
	guesthost.archive_tree(work + '/system', image)!
	check_command(command, args, env, 0, state + '/new-image.log')!
	assert run([debugfs, '-R', 'cat /root/user-file', disk])! == 'user data'
	assert run([debugfs, '-R', 'cat /etc/version', disk])! == 'two'.repeat(20000)
	assert run([debugfs, '-R', 'cat /etc/package-marker', disk])! == 'merged package'
	assert os.read_file(work + '/model-argv')!.contains('id=system-root,cache=writeback')
	assert !os.read_file(work + '/model-argv')!.contains('-no-reboot')
	println('PASS full root installer: unchanged-image reuse, changed-image home carry and ext2-only package merge')
	diskhost.mkdir(work + '/guest-fixture')!
	guest_init := guesthost.compile_init(guesthost.root() + '/tests/numa/test.c', work + '/guest-fixture', 'aarch64', false)!
	for family in ['numa', 'security'] {
		target := work + '/extra-' + family
		mut options := ['--init', guest_init, '--initramfs', archive, '--kernel-dir', kernel,
			'--state-dir', target, '--build-only']
		if family == 'security' {
			options << ['--arch', 'aarch64', '--capture', target + '/net.pcap']
		}
		check_command(prefix + family + '-' + profile, options, env, 0, work + '/extra-' + family + '.log')!
		launch := json2.decode[json2.Any](os.read_file(target + '/launch.json')!)!.as_map()
		argv := launch['command']!.as_array().map(it.str())
		assert argv[1..3] == ['-name', 'model extra']
		assert argv.count(it == '-name') == 1
		hosttest.remove_work_dir(target)!
	}
	println('PASS quoted extra QEMU arguments through Docker, root, NUMA and security CLIs')
}

fn main() {
	if os.args.contains('-machine') && os.getenv('VINIX_SYSTEM_MODEL') != '' {
		machine() or { panic(err) }
		return
	}
	guard := policyhost.own_commands()
	defer { guard.close() }
	checked() or {
		eprintln(err)
		exit(1)
	}
}
