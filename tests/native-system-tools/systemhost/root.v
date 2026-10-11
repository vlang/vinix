// SPDX-License-Identifier: GPL-2.0-or-later
module systemhost

import diskhost
import guesthost
import hosttest
import os
import strconv

pub fn root_verdict(text string, family string) ! {
	failures := root_failures(family)
	if failures.any(text.contains(it)) { return error('guest reported a failure') }
	if family == 'disk-writeback' {
		if !text.contains('VINIX WRITEBACK: START') {
			return error('the guest never started the test')
		}
		if !text.contains('VINIX WRITEBACK: PASS') {
			return error('the guest did not finish; a wait that never ended looks like this')
		}
		return
	}
	for marker, explanation in {
		'VINIX DISK ROOT: START':         'the guest did not come back up after reboot(2)'
		'VINIX DISK ROOT: ON VOLUME':     'the guest did not boot from the volume both times'
		'VINIX DISK ROOT: LARGE FILE OK': 'a host-written file past the direct blocks did not read back'
	} {
		if text.count(marker) < 2 { return error(explanation) }
	}
	if !text.contains('VINIX DISK ROOT: WROTE /etc MARKER, REBOOTING') {
		return error('the guest never wrote the marker')
	}
	if text.contains('Loading saved package overlay') {
		return error('the package overlay was loaded as a boot module')
	}
	if !text.contains('VINIX DISK ROOT: PASS') {
		return error('the file written outside /root did not survive the restart')
	}
}

fn root_failures(family string) []string {
	return [
		if family == 'disk-root' { 'VINIX DISK ROOT: FAIL' } else { 'VINIX WRITEBACK: FAIL' },
		'does not carry a bootable system',
		'using the initramfs root',
		'FATAL EXCEPTION',
		'KERNEL PANIC',
	]
}

fn debugfs_quote(path string) string {
	return '"' + path.replace('\\', '\\\\').replace('"', '\\"') + '"'
}

// The public image/state interface keeps an installed disk when the original
// size/mtime identity is unchanged. Image changes merge the old /root over the
// new tree and preserve capacity, as the previous desktop installer did.
fn install_root(image string, state string, requested int) ! {
	disk := state + '/root.ext2'
	identity := os.file_size(image).str() + '-' + os.file_last_mod_unix(image).str()
	mut capacity := i64(os.file_size(image)) * 2 / 1024 / 1024 + 512
	if requested > capacity { capacity = requested }
	executable := ext2_tool('debugfs')!
	mut carried := ''
	if os.exists(disk) {
		capacity = if i64((os.file_size(disk) + 1024 * 1024 - 1) / 1024 / 1024) > capacity {
			i64((os.file_size(disk) + 1024 * 1024 - 1) / 1024 / 1024)
		} else {
			capacity
		}
		found := capture([executable, '-R', 'cat /.vinix-image-id', disk])!
		installed := found.stdout.replace('\r', '').all_before('\n')
		if installed == identity { return }
		if installed == '' {
			return error('Persistent disk is not a Vinix system volume; use a fresh state directory')
		}
		carried = state + '/carried-home'
		if os.exists(carried) { hosttest.remove_work_dir(carried)! }
		diskhost.mkdir(carried)!
		result := capture([executable, '-R', 'rdump /root ' + debugfs_quote(carried), disk])!
		if result.status != 0 || !os.is_dir(carried + '/root') {
			eprintln('WARNING: could not read the old /root; installing without it')
			carried = ''
		}
	}
	seed := state + '/system-seed'
	if os.exists(seed) { hosttest.remove_work_dir(seed)! }
	diskhost.mkdir(seed)!
	run(['tar', '-xf', image, '-C', seed])!
	for name in ['dev', 'proc', 'tmp', 'run', 'root'] { diskhost.mkdir(seed + '/' + name)! }
	os.chmod(seed + '/tmp', 0o1777)!
	if os.is_file(state + '/packages.tar') && os.file_size(state + '/packages.tar') > 0 {
		run(['tar', '-xf', state + '/packages.tar', '-C', seed])!
	}
	if carried != '' {
		home := carried + '/root'
		if (os.is_dir(home + '/desktop') || os.is_dir(home + '/vmodules')) && !os.is_file(home + '/.vinix-desktop-dev-version') {
			if os.exists(seed + '/root/.vinix-desktop-dev-version') {
				os.rm(seed + '/root/.vinix-desktop-dev-version')!
			}
		}
		run(['cp', '-a', home + '/.', seed + '/root/'])!
	}
	os.write_file(seed + '/.vinix-image-id', identity + '\n')!
	temporary := state + '/replacement.ext2'
	diskhost.format_ext2(executable, temporary, seed, capacity * 1024 * 1024)!
	run([
		os.getenv_opt('VINIX_EXT2_ROOT_OWNER_TOOL') or { root() + '/build-support/ext2-set-root-owner' },
		temporary,
	])!
	os.mv(temporary, disk)!
}

fn root_fixture(state string, family string) !string {
	init := state + '/init'
	run([...flags('aarch64'), '-fno-stack-protector', root() + '/tests/' + family + '/test.c',
		'-o', init])!
	for name in ['sbin', 'etc', 'usr/share'] { diskhost.mkdir(state + '/system/' + name)! }
	os.cp(init, state + '/system/sbin/init')!
	os.chmod(state + '/system/sbin/init', 0o755)!
	if family == 'disk-root' {
		run([root() + '/tests/disk-root/make-large-file', state + '/system/usr/share/vinix-large'])!
		os.symlink('vinix-large', state + '/system/usr/share/vinix-large-link')!
		diskhost.mkdir(state + '/package-overlay/etc')!
		os.write_file(state + '/package-overlay/etc/vinix-package-overlay', 'disk-overlay\n')!
		guesthost.archive_tree(state + '/package-overlay', state + '/packages.tar')!
	}
	return guesthost.archive_tree(state + '/system', state + '/system.tar')!
}

fn root_command(family string, args []string) !int {
	options := parse(args, [hosttest.Option{ name: '--image', value: true },
		hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--timeout', value: true },
		hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--build-fixture' }, hosttest.Option{ name: '--build-only' }], [],
		'Usage: run_vm --image TAR --state-dir DIR [--timeout 240] [--kernel-dir DIR]\n       run.sh [--state-dir DIR] [--build-only]')!
	if options.has('--image') == options.has('--build-fixture') {
		return argument('choose --image or --build-fixture')
	}
	if !options.has('--build-fixture') { required(options, ['--state-dir'])! }
	seconds := if options.has('--build-fixture') {
		env_timeout(options, if family == 'disk-root' { 300 } else { 900 })!
	} else {
		positive(options, '--timeout', 240)!
	}
	state := state_dir(options, 'vinix-' + family + '-')!
	defer { private_cleanup(state, options) }
	image := if options.has('--build-fixture') {
		root_fixture(state, family)!
	} else {
		resolve(options.value('--image', ''))!
	}
	kernel := snapshot(state, kernel_source(options, 'aarch64'), 'aarch64')!
	requested := strconv.atoi(os.getenv_opt('VINIX_QEMU_PERSIST_SIZE_MB') or { if family == 'disk-root' {
		'64'
	} else {
		'8192'
	} })!
	if requested <= 0 { return argument('persistent capacity must be positive') }
	install_root(image, state, requested)!
	runner := resolve(os.getenv_opt('VINIX_VM_RUNNER_ROOT') or { root() })!
	base := guesthost.launch_from('', image, state, kernel, 'aarch64', false, runner)!
	arm_config(state, runner, 'vinix.qemu_platform=1 vinix.qemu_persist=1 vinix.qemu_root=1 ' + os.getenv('VINIX_CMDLINE'))!
	mut argv := base.command.clone()
	argv[argv.index('-m') + 1] = '2048'
	argv.delete(argv.index('-no-reboot'))
	if os.getenv('VINIX_QEMU_EXTRA') != '' {
		argv.insert(1, hosttest.shell_split(os.getenv('VINIX_QEMU_EXTRA'))!)
	}
	argv << ['-drive',
		'if=none,format=raw,file=' + state + '/root.ext2,id=system-root,cache=writeback', '-device',
		'virtio-blk-device,drive=system-root']
	configured := guesthost.Launch{argv, base.env}
	receipt(state, configured, kernel, '', image, seconds)!
	if options.has('--build-only') {
		println('Prepared ' + family + ': ' + state)
		return 0
	}
	println('==> Installing the system on a volume and ' + if family == 'disk-root' {
		'booting from it'
	} else {
		'streaming to it'
	})
	result := guesthost.boot_session(argv, base.env, state, guesthost.SessionPolicy{
		pass:     if family == 'disk-root' {
			'VINIX DISK ROOT: PASS'
		} else {
			'VINIX WRITEBACK: PASS'
		}
		failures: root_failures(family)
		lookback: 8192
	}, seconds, true)!
	root_verdict(result.text, family)!
	println('==> AArch64 ' + if family == 'disk-root' {
		'disk-root persistence passed'
	} else {
		'disk writeback kept the machine responsive'
	})
	return 0
}
