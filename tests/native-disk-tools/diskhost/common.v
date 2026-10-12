// SPDX-License-Identifier: GPL-2.0-or-later
module diskhost

import fixturehost
import guesthost
import hosttest
import json2
import os
import policyhost
import strconv
import tarcore

#include <unistd.h>

fn C.ftruncate(i32, u64) i32

fn argument(message string) IError { return error_with_code(message, 2) }

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
		'no-sync' { no_sync(args)! }
		'mapped' { mapped(args)! }
		'journal' { journal(args)! }
		'mounted' { mounted(args)! }
		'external' { external(args)! }
		'reboot' { reboot(args)! }
		else { return error('Unknown disk runner') }
	}
}

fn parse(args []string, options []hosttest.Option, usage string) !guesthost.Options {
	return guesthost.parse(args, options, [], usage) or { return argument(err.msg()) }
}

fn integer(options guesthost.Options, name string, fallback int) !int {
	return options.integer(name, fallback) or { return argument('invalid integer for ' + name) }
}

fn caller_timeout(options guesthost.Options, fallback int) !int {
	if options.has('--timeout') { return integer(options, '--timeout', fallback)! }
	return strconv.atoi(os.getenv_opt('VINIX_QEMU_TIMEOUT') or { fallback.str() }) or { return argument('invalid integer for --timeout') }
}

fn timeout() !int {
	value := strconv.atoi(os.getenv_opt('VINIX_QEMU_TIMEOUT') or { '300' })!
	if value <= 0 { return argument('timeout must be positive') }
	return value
}

fn root() string { return guesthost.root() }

fn resolve(path string) !string { return hosttest.module_resolve(path)! }

pub fn mkdir(path string) ! {
	if path.contains('\x00') { return error('embedded null byte') }
	if os.is_dir(path) { return }
	parent := path.trim_right('/').all_before_last('/')
	if parent != '' && parent != path { mkdir(parent)! }
	os.mkdir(path) or { if !os.is_dir(path) { return err } }
}

fn run(argv []string) ! { policyhost.inherited(argv)! }

fn capture(argv []string) !fixturehost.CapturedCommand {
	return fixturehost.capture_owned_bounded(argv, policyhost.environment(), policyhost.caller_arch(), '', -1,
		policyhost.command_interrupted, false)!
}

fn tool() !string {
	for candidate in ['debugfs', '/opt/homebrew/opt/e2fsprogs/sbin/debugfs',
		'/usr/local/opt/e2fsprogs/sbin/debugfs', '/sbin/debugfs'] {
		path := os.find_abs_path_of_executable(candidate) or { continue }
		if os.is_executable(path) { return path }
	}
	return error('e2fsprogs debugfs is required')
}

pub fn sparse_file(path string, bytes i64) ! {
	if bytes < 0 { return error('invalid sparse file size') }
	mut file := os.create(path)!
	defer { file.close() }
	if C.ftruncate(file.fd, u64(bytes)) != 0 { return os.error_posix() }
}

pub fn format_ext2(executable string, disk string, seed string, bytes i64) ! {
	sparse_file(disk, bytes)!
	run([os.dir(executable) + '/mke2fs', '-q', '-F', '-t', 'ext2', '-b', '4096', '-I', '128', '-O',
		'filetype,sparse_super,^has_journal,^resize_inode,^dir_index,^extent,^64bit,^metadata_csum',
		'-d', seed, disk])!
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
	return [...compiler(arch), '-static', '-O2', '-Wall', '-Wextra', '-Werror', '-fno-stack-protector']
}

fn kernel(work string, supplied string, arch string) !string {
	source := resolve(if supplied != '' {
		supplied
	} else if arch == 'aarch64' {
		os.getenv_opt('VINIX_KERNEL_DIR') or { root() + '/kernel' }
	} else {
		os.getenv_opt('VINIX_AMD64_KERNEL') or { root() + '/kernel/bin/vinix' }
	})!
	path := if os.is_dir(source) { source + '/bin/vinix' } else { source }
	data := os.read_bytes(path)!
	if data.len < 20 || data[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
		|| int(data[18]) + (int(data[19]) << 8) != if arch == 'aarch64' { 183 } else { 62 } {
		return argument('Kernel ELF architecture does not match --arch')
	}
	mkdir(work + '/kernel/bin')!
	if path == work + '/kernel/bin/vinix' {
		return argument('Kernel source must be outside the private snapshot')
	}
	hosttest.module_copy_file_preserving_stat(path, work + '/kernel/bin/vinix')!
	if os.read_bytes(work + '/kernel/bin/vinix')! != data {
		return error('Kernel changed while copying its snapshot')
	}
	return work + '/kernel'
}

// Small phase archives retain the original TarInfo defaults and 10 KiB
// record padding, without an interpreter or filesystem-dependent timestamps.
pub fn phase_archive(path string, phase string) ! {
	mut archive := tarcore.create_stream(path)!
	defer { archive.close() }
	for name in ['.', './root', './sbin'] {
		archive.add(tarcore.Member{ name: name, kind: `5`, mode: 0o755 }, []u8{})!
	}
	data := (phase + '\n').bytes()
	archive.add(tarcore.Member{ name: './no-sync-step', size: data.len }, data)!
	archive.finish()!
	archive.close_checked()!
}

fn extract(archive string, directory string) ! {
	mkdir(directory)!
	run(['tar', '-xf', archive, '-C', directory])!
}

fn seed_identity(seed string, archive string) ! {
	for name in ['dev', 'proc', 'tmp', 'run', 'root'] { mkdir(seed + '/' + name)! }
	os.write_file(seed + '/.vinix-image-id', hosttest.sha(archive)![..16] + '\n')!
}

fn x86_command(configured guesthost.Launch, disk string, memory int, reboot bool, network bool) []string {
	mut argv := configured.command.clone()
	argv[argv.index('-m') + 1] = memory.str()
	argv[argv.index('-serial') + 1] = 'stdio'
	argv[argv.index('-accel') + 1] = os.getenv_opt('VINIX_QEMU_ACCEL') or { 'tcg' }
	firmware := os.getenv_opt('VINIX_OVMF_CODE_AMD64') or { os.dir(os.dir(argv[0])) + '/share/qemu/edk2-x86_64-code.fd' }
	argv[argv.index('-drive') + 1] = 'if=pflash,format=raw,unit=0,readonly=on,file=' + firmware
	argv << ['-drive', 'if=ide,format=raw,file=' + disk + ',cache=writeback']
	if reboot { argv.delete(argv.index('-no-reboot')) }
	if !network && '-nic' !in argv { argv << ['-nic', 'none'] }
	if os.getenv('VINIX_TEST_QMP') != '' {
		argv[argv.index('-qmp') + 1] = 'unix:' + os.getenv('VINIX_TEST_QMP') + ',server=on,wait=off'
	}
	return argv
}

fn launch(init string, archive string, work string, kernel_dir string, arch string, memory int, disk string,
	reboot bool, no_network bool) !guesthost.Launch {
	return launch_mode(init, archive, work, kernel_dir, arch, memory, disk, reboot, no_network, true)!
}

fn launch_mode(init string, archive string, work string, kernel_dir string, arch string, memory int, disk string,
	reboot bool, no_network bool, overlay bool) !guesthost.Launch {
	runner := resolve(os.getenv_opt('VINIX_VM_RUNNER_ROOT') or { root() })!
	prior_network := os.getenv_opt('VINIX_QEMU_NETWORK')
	if no_network { os.setenv('VINIX_QEMU_NETWORK', '0', true) }
	defer {
		if no_network {
			if value := prior_network {
				os.setenv('VINIX_QEMU_NETWORK', value, true)
			} else {
				os.unsetenv('VINIX_QEMU_NETWORK')
			}
		}
	}
	configured := if arch == 'aarch64' && overlay {
		guesthost.serial_arm_launch_disk(init, archive, work, kernel_dir, runner, memory, '', disk)!
	} else {
		guesthost.launch_from(init, archive, work, kernel_dir, if arch == 'aarch64' {
			arch
		} else {
			'x86_64'
		}, no_network, runner)!
	}
	mut argv := if arch == 'aarch64' && !overlay {
		guesthost.arm_persist_launch(configured.command, disk, work, runner)!
	} else if arch == 'aarch64' {
		configured.command.clone()
	} else {
		x86_command(configured, disk, memory, reboot, !no_network)
	}
	argv[argv.index('-m') + 1] = memory.str()
	if reboot && arch == 'aarch64' { argv.delete(argv.index('-no-reboot')) }
	os.write_file(work + '/launch.json', json2.encode(json2.Any({
		'arch':                     json2.Any(arch)
		'memory_mib':               json2.Any(memory)
		'command':                  json2.Any(argv.map(json2.Any(it)))
		'disk':                     json2.Any(disk)
		'init_sha256':              json2.Any(hosttest.sha(init)!)
		'archive_sha256':           json2.Any(hosttest.sha(archive)!)
		'immutable_kernel_sha256':  json2.Any(hosttest.sha(kernel_dir + '/bin/vinix')!)
		'kernel_rebuilt_by_runner': json2.Any(false)
	})) + '\n')!
	return guesthost.Launch{argv, configured.env}
}

fn work_dir(options guesthost.Options, prefix string) !string {
	if !options.has('--state-dir') { return hosttest.work_dir('', prefix)! }
	work := resolve(options.value('--state-dir', ''))!
	mkdir(work)!
	return work
}

fn remove_private(work string, options guesthost.Options) {
	if !options.has('--state-dir') { hosttest.remove_work_dir(work) or { eprintln(err.msg()) } }
}

fn append_init(archive string, init string, work string) ! {
	tree := work + '/boot-seed'
	mkdir(tree + '/sbin')!
	hosttest.module_copy_file_preserving_stat(init, tree + '/sbin/init')!
	os.chmod(tree + '/sbin/init', 0o755)!
	mut env := policyhost.environment()
	env['COPYFILE_DISABLE'] = '1'
	policyhost.owned_inherited_environment(['tar', '--format=ustar', '-rf', archive, '-C', tree,
		'sbin/init'], env, policyhost.caller_arch(), '')!
}

fn checked_capture(argv []string) !string {
	result := capture(argv)!
	if result.status != 0 {
		return error('Command failed (' + result.status.str() + '): ' + argv.join(' ') + '\n' + result.stdout + result.stderr)
	}
	return result.stdout + result.stderr
}

fn text_capture(argv []string) !string {
	result := capture(argv)!
	hosttest.module_decode_utf8(result.stdout)!
	hosttest.module_decode_utf8(result.stderr)!
	return (result.stdout + result.stderr).replace('\r\n', '\n').replace('\r', '\n')
}

fn cut(configured guesthost.Launch, epoch string, policy guesthost.PowercutPolicy, seconds int, stream bool) !int {
	mkdir(epoch)!
	policyhost.command_checkpoint()!
	return guesthost.boot_powercut(configured.command, configured.env, epoch, policy, seconds, stream, true)!
}
