// SPDX-License-Identifier: GPL-2.0-or-later
module systemhost

import diskhost
import fixturehost
import guesthost
import hosttest
import json2
import os
import policyhost
import strconv

fn root() string { return guesthost.root() }

fn policy_environment() map[string]string { return policyhost.environment() }

fn resolve(path string) !string { return hosttest.module_resolve(path)! }

fn argument(message string) IError { return error_with_code(message, 2) }

fn run(argv []string) ! { policyhost.inherited(argv)! }

fn parse(args []string, options []hosttest.Option, repeated []string, usage string) !guesthost.Options {
	return guesthost.parse(args, options, repeated, usage) or { return argument(err.msg()) }
}

fn required(options guesthost.Options, names []string) ! {
	for name in names { if !options.has(name) { return argument('missing required ' + name) } }
}

fn positive(options guesthost.Options, name string, fallback int) !int {
	n := options.integer(name, fallback) or { return argument('invalid integer for ' + name) }
	if n <= 0 { return argument(name + ' must be positive') }
	return n
}

fn env_timeout(options guesthost.Options, fallback int) !int {
	value := strconv.atoi(os.getenv_opt('VINIX_QEMU_TIMEOUT') or { fallback.str() }) or { return argument('invalid VINIX_QEMU_TIMEOUT') }
	return positive(options, '--timeout', value)!
}

fn state_dir(options guesthost.Options, prefix string) !string {
	state := if options.has('--state-dir') {
		resolve(options.value('--state-dir', ''))!
	} else {
		hosttest.work_dir('', prefix)!
	}
	diskhost.mkdir(state)!
	return state
}

fn private_cleanup(state string, options guesthost.Options) {
	if !options.has('--state-dir') { hosttest.remove_work_dir(state) or { eprintln(err.msg()) } }
}

fn compiler(arch string) []string {
	if arch == 'aarch64' {
		sdk := os.getenv_opt('VINIX_AARCH64_SYSROOT') or { root() + '/build-aarch64-userland/sysroot' }
		return [os.getenv_opt('CC') or { 'clang' }, '--target=aarch64-linux-musl', '--sysroot=' + sdk,
			'-L' + sdk + '/lib', '-fuse-ld=lld']
	}
	return [os.getenv_opt('CC_AMD64') or { 'x86_64-linux-musl-gcc' }]
}

fn flags(arch string) []string {
	return [...compiler(arch), '-static', '-O2', '-Wall', '-Wextra', '-Werror']
}

fn capture(argv []string) !fixturehost.CapturedCommand {
	return fixturehost.capture_owned_bounded(argv, policyhost.environment(), policyhost.caller_arch(), '', -1,
		policyhost.command_interrupted, false)!
}

fn checked_capture(argv []string) !string {
	result := capture(argv)!
	if result.status != 0 {
		return error('Command failed: ' + hosttest.shell_join(argv) + '\n' + result.stdout + result.stderr)
	}
	return result.stdout + result.stderr
}

fn ext2_tool(name string) !string {
	for path in [os.getenv(name.to_upper()), name, '/opt/homebrew/opt/e2fsprogs/sbin/' + name,
		'/usr/local/opt/e2fsprogs/sbin/' + name, '/sbin/' + name] {
		if path == '' { continue }
		executable := os.find_abs_path_of_executable(path) or { continue }
		return executable
	}
	return error('e2fsprogs ' + name + ' is required')
}

fn snapshot(state string, path string, arch string) !string {
	source := resolve(path)!
	binary := if os.is_dir(source) { source + '/bin/vinix' } else { source }
	bytes := os.read_bytes(binary)!
	if bytes.len < 20 || bytes[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
		|| u16(bytes[18]) + (u16(bytes[19]) << 8) != if arch == 'aarch64' { 183 } else { 62 } {
		return argument('Kernel ELF architecture does not match --arch')
	}
	target := state + '/kernel/bin/vinix'
	if os.real_path(binary) == os.real_path(target) {
		return argument('Kernel source must be outside its private snapshot')
	}
	diskhost.mkdir(state + '/kernel/bin')!
	hosttest.module_copy_file_preserving_stat(binary, target)!
	if os.read_bytes(target)! != bytes { return error('Kernel changed while copying its snapshot') }
	return state + '/kernel'
}

fn kernel_source(options guesthost.Options, arch string) string {
	return options.value('--kernel-dir', if arch == 'aarch64' {
		os.getenv_opt('VINIX_KERNEL_DIR') or { root() + '/kernel' }
	} else {
		os.getenv_opt('VINIX_AMD64_KERNEL') or { root() + '/kernel/bin/vinix' }
	})
}

fn archive_root(init string, state string, directories []string) !string {
	for name in directories { diskhost.mkdir(state + '/rootfs/' + name)! }
	if init != '' {
		hosttest.module_copy_file_preserving_stat(init, state + '/rootfs/sbin/init')!
		os.chmod(state + '/rootfs/sbin/init', 0o755)!
	}
	return guesthost.archive_tree(state + '/rootfs', state + '/initramfs.tar')!
}

fn arm_config(state string, runner string, cmdline string) ! {
	if cmdline.contains('\n') || cmdline.contains('\r') {
		return error('Kernel command line must fit one line')
	}
	os.write_file(state + '/limine.conf', os.read_file(runner + '/build-support/limine.conf')! + '    cmdline: ' + cmdline + '\n')!
	run(['xorriso', '-indev', state + '/test.iso', '-outdev', state + '/configured.iso', '-map',
		state + '/limine.conf', '/boot/limine.conf', '-boot_image', 'any', 'replay'])!
	os.mv(state + '/configured.iso', state + '/test.iso')!
}

fn receipt(state string, configured guesthost.Launch, kernel string, init string, archive string, seconds int) ! {
	hosttest.write_json(state + '/launch.json', json2.Any({
		'command':                  json2.Any(hosttest.strings(configured.command))
		'timeout':                  json2.Any(seconds)
		'kernel_sha256':            json2.Any(hosttest.sha(kernel + '/bin/vinix')!)
		'kernel_rebuilt_by_runner': json2.Any(false)
		'init_sha256':              json2.Any(if init != '' { hosttest.sha(init)! } else { '' })
		'archive_sha256':           json2.Any(hosttest.sha(archive)!)
	}))!
}

pub fn command(family string, args []string) int {
	guard := policyhost.own_commands()
	defer { guard.close() }
	return dispatch(family, args) or {
		eprintln(err.msg())
		return if err.msg() in ['Guest run interrupted', 'Host test interrupted'] {
			130
		} else if err.code() == 2 {
			2
		} else {
			1
		}
	}
}

fn dispatch(family string, args []string) !int {
	return match family {
		'disk-root', 'disk-writeback' { root_command(family, args)! }
		'docker' { docker(args)! }
		'security', 'mount', 'ipv6' { security(family, args)! }
		'numa' { numa(args)! }
		'paging' { paging(args)! }
		'securelevel' { securelevel(args)! }
		'securelevel-ext2' { securelevel_ext2(args)! }
		'fsync-scope', 'virtio-ro', 'export-read' { storage_guest(family, args)! }
		'sound' { sound(args)! }
		'pci-arm' { pci_arm(args)! }
		'ext2-export' { ext2_export(args)! }
		else { return error('Unknown system controller') }
	}
}
