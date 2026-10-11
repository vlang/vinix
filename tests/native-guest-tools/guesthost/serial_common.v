// SPDX-License-Identifier: GPL-2.0-or-later
module guesthost

import hosttest
import os
import policyhost

struct SerialArgumentError {
	message string
}

fn (e SerialArgumentError) msg() string { return e.message }

fn (e SerialArgumentError) code() int { return 2 }

fn serial_report(e IError) int {
	eprintln(e.msg())
	if e is SerialArgumentError { return 2 }
	return if e.msg() in ['Guest run interrupted', 'Host test interrupted'] { 130 } else { 1 }
}

fn serial_timeout(options Options, fallback int) !int {
	value := options.integer('--timeout', fallback) or { return SerialArgumentError{'invalid integer for --timeout'} }
	if value <= 0 { return SerialArgumentError{'timeout must be positive'} }
	return value
}

fn mkdir_literal(path string) ! {
	if path.contains('\x00') { return error('embedded null byte') }
	if os.is_dir(path) { return }
	parent := path.trim_right('/').all_before_last('/')
	if parent != '' && parent != path { mkdir_literal(parent)! }
	os.mkdir(path) or { if !os.is_dir(path) { return err } }
}

pub fn archive_tree(tree string, destination string) !string {
	mut env := policyhost.environment()
	env['COPYFILE_DISABLE'] = '1'
	policyhost.owned_inherited_environment(['tar', '--format=ustar', '-cf', destination, '-C',
		tree, '.'], env, policyhost.caller_arch(), '')!
	return destination
}

// Preserve the base archive and replacement PID 1 as separate Limine modules.
// This also avoids copying a multi-gigabyte desktop image into each private run.
pub fn serial_arm_launch(init string, archive string, state string, kernel_dir string,
	runner_root string, memory int, module_iso string) !Launch {
	return serial_arm_launch_disk(init, archive, state, kernel_dir, runner_root, memory, module_iso, state + '/root.ext2')!
}

// Disk controllers supply their actual volume path, including private VJFS
// images; the existing serial interface keeps its default EXT2 home.
pub fn serial_arm_launch_disk(init string, archive string, state string, kernel_dir string,
	runner_root string, memory int, module_iso string, disk string) !Launch {
	mkdir_literal(state)!
	abi_validate_elf(init, 'aarch64')!
	abi_validate_elf(kernel_dir + '/bin/vinix', 'aarch64')!
	rootfs := state + '/init-overlay'
	for name in ['root', 'sbin', 'proc', 'sys', 'dev', 'tmp'] {
		mkdir_literal(rootfs + '/' + name)!
	}
	hosttest.module_copy_file_preserving_stat(init, rootfs + '/sbin/init')!
	os.chmod(rootfs + '/sbin/init', 0o755)!
	overlay := archive_tree(rootfs, state + '/test-init.tar')!
	configured := launch_from(init, if module_iso == '' { archive } else { overlay }, state,
		kernel_dir, 'aarch64', false, runner_root)!
	if (os.exists(disk) || os.is_link(disk)) && !os.is_file(disk) {
		return error('Persistent disk is not a regular file: ' + disk)
	}
	if disk != state + '/root.ext2' && !os.is_file(disk) {
		return error('Caller-supplied persistent disk must already exist: ' + disk)
	}
	mut command := if os.is_file(disk) {
		arm_persist_launch(configured.command, disk, state, runner_root)!
	} else {
		arm_home_launch(configured.command, state, runner_root)!
	}
	command[command.index('-m') + 1] = memory.str()
	config := state + '/limine.conf'
	mut text := os.read_file(config)!
	if module_iso != '' {
		if !os.is_file(module_iso) { return error('Missing module ISO: ' + module_iso) }
		mut lines := text.split_into_lines()
		mut replaced := false
		for index, line in lines {
			if !replaced && line.trim_space().starts_with('module_path:') {
				lines[index] = '    module_path: odd(1:):/boot/initramfs.tar'
				replaced = true
			}
		}
		if !replaced { return error('Limine base module entry missing') }
		text = lines.join('\n') + '\n'
		command << ['-drive',
			'if=none,id=vinix-module,media=cdrom,format=raw,readonly=on,file=' + module_iso, '-device',
			'virtio-scsi-device,id=vinix-module-scsi', '-device',
			'scsi-cd,bus=vinix-module-scsi.0,drive=vinix-module']
	}
	os.write_file(config, text + '    module_path: boot():/boot/test-init.tar\n')!
	patched := state + '/test-overlay.iso'
	run(['xorriso', '-indev', state + '/test.iso', '-outdev', patched, '-map', config,
		'/boot/limine.conf', '-map', overlay, '/boot/test-init.tar', '-boot_image', 'any', 'replay'])!
	os.mv(patched, state + '/test.iso')!
	return Launch{command, configured.env}
}

fn serial_x86_command(iso string, qemu string, firmware string, capture string) []string {
	return [qemu, '-machine', 'q35,smm=off', '-accel', os.getenv_opt('VINIX_QEMU_ACCEL') or { 'tcg' },
		'-cpu', 'max', '-m', '1024', '-smp', '2', '-drive',
		'if=pflash,format=raw,unit=0,readonly=on,file=' + firmware, '-cdrom', iso, '-display',
		'none', '-monitor', 'none', '-serial', 'stdio', '-no-reboot', '-netdev', 'user,id=net0',
		'-device', 'e1000,netdev=net0,mac=52:54:00:12:34:56', '-object',
		'filter-dump,id=vinixdump,netdev=net0,file=' + capture]
}
