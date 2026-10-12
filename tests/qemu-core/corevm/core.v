// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module corevm

import hosttest
import net
import os
import strconv

pub struct Options {
pub:
	arch       string = 'aarch64'
	root       string
	guest_init string
	initramfs  string
	state_dir  string
	iso        string
	qemu       string = 'qemu-system-x86_64'
	firmware   string = 'None'
	timeout    int    = 300
	cpus       int    = 4
	cpu        string = 'max'
}

pub fn parse(arguments []string, root string, cpu string) !Options {
	args := hosttest.parse_arguments(arguments, [
		hosttest.Option{'--arch', true, ['aarch64', 'amd64']},
		hosttest.Option{'--root', true, []string{}},
		hosttest.Option{'--init', true, []string{}},
		hosttest.Option{'--initramfs', true, []string{}},
		hosttest.Option{'--state-dir', true, []string{}},
		hosttest.Option{'--iso', true, []string{}},
		hosttest.Option{'--qemu', true, []string{}},
		hosttest.Option{'--firmware', true, []string{}},
		hosttest.Option{'--timeout', true, []string{}},
		hosttest.Option{'--cpus', true, []string{}},
	], 0, 'usage: run-vm [--arch aarch64|amd64] [boot options] [--timeout SECONDS] [--cpus 1..64]',
		'ARM: --init FILE --initramfs FILE --state-dir DIRECTORY [--root REPOSITORY]\namd64: --iso FILE --qemu PROGRAM --firmware FILE')!
	seconds := strconv.atoi(args.options['--timeout'] or { '300' }) or { return error('invalid integer for --timeout') }
	cpus := strconv.atoi(args.options['--cpus'] or { '4' }) or { return error('invalid integer for --cpus') }
	if seconds <= 0 { return error('--timeout must be positive') }
	if cpus < 1 || cpus > 64 { return error('--cpus must be 1..64') }
	arch := args.options['--arch'] or { 'aarch64' }
	for key in if arch == 'amd64' { ['--iso'] } else { ['--init', '--initramfs', '--state-dir'] } {
		if key !in args.options { return error('missing required ' + key) }
	}
	return Options{
		arch:       arch
		root:       hosttest.module_resolve(args.options['--root'] or { root })!
		guest_init: if arch == 'aarch64' {
			hosttest.module_resolve(args.options['--init'])!
		} else {
			''
		}
		initramfs:  if arch == 'aarch64' {
			hosttest.module_resolve(args.options['--initramfs'])!
		} else {
			''
		}
		state_dir:  if arch == 'aarch64' {
			hosttest.module_resolve(args.options['--state-dir'])!
		} else {
			''
		}
		iso:        if arch == 'amd64' {
			hosttest.module_resolve(args.options['--iso'])!
		} else {
			''
		}
		qemu:       args.options['--qemu'] or { 'qemu-system-x86_64' }
		firmware:   args.options['--firmware'] or { 'None' }
		timeout:    seconds
		cpus:       cpus
		cpu:        cpu
	}
}

pub fn available_port() !string {
	mut listener := net.listen_tcp(.ip, '127.0.0.1:0')!
	defer { listener.close() or {} }
	return listener.addr()!.port()!.str()
}

pub fn arm_environment(options Options, original map[string]string, system string) !map[string]string {
	mut env := original.clone()
	env['VINIX_INITRAMFS'] = options.initramfs
	env['VINIX_BOOT_DISK'] = options.state_dir + '/boot.img'
	env['VINIX_EFIVARS'] = options.state_dir + '/efivars.fd'
	env['VINIX_QEMU_PACKAGE_STORE'] = options.state_dir + '/packages.tar'
	env['VINIX_QEMU_PERSIST_DISK'] = options.state_dir + '/root.ext2'
	env['VINIX_QEMU_PERSIST_SIZE_MB'] = '64'
	env.delete('VINIX_QEMU_PERSIST')
	env['VINIX_KEEP_TEMP_BOOT_DISK'] = '1'
	// The original setdefault evaluates the allocator even if the key exists.
	port := available_port()!
	if 'VINIX_QEMU_PACKAGE_STORE_PORT' !in env { env['VINIX_QEMU_PACKAGE_STORE_PORT'] = port }
	if system != 'Darwin' && 'USE_TCG' !in env { env['USE_TCG'] = '1' }
	return env
}

pub fn arm_command(options Options, verification bool, no_build string) []string {
	mut command := [options.root + '/scripts/run-aarch64.sh', '--serial', '--mem=2048',
		'--guest-init=' + options.guest_init]
	if verification || no_build == '1' { command.insert(1, '--no-build') }
	return command
}

pub fn amd64_command(options Options, original map[string]string) []string {
	return [options.qemu, '-machine', 'q35,smm=off', '-accel',
		original['VINIX_QEMU_ACCEL'] or { 'tcg' }, '-cpu', options.cpu, '-m', '2048', '-smp',
		options.cpus.str(), '-drive',
		'if=pflash,format=raw,unit=0,readonly=on,file=' + options.firmware, '-cdrom', options.iso,
		'-display', 'none', '-monitor', 'none', '-serial', 'stdio', '-no-reboot']
}

fn verdict(run Run, verification bool, amd64 bool) int {
	missing, failures := results(run, verification, amd64)
	for marker in missing { eprintln('ERROR: missing expected QEMU result: ' + marker) }
	for marker in failures { eprintln('ERROR: observed QEMU failure: ' + marker) }
	return if missing.len + failures.len == 0 { 0 } else { 1 }
}

pub fn phase(options Options, verification bool) !int {
	label := if verification { 'persistence verification' } else { 'core feature' }
	println('==> Starting AArch64 QEMU ' + label + ' boot')
	flush_stdout()
	system := $if darwin { 'Darwin' } $else { 'Linux' }
	env := arm_environment(options, os.environ(), system)!
	command := arm_command(options, verification, os.getenv('VINIX_QEMU_CORE_NO_BUILD'))
	run := capture(command, env, options.root, options.timeout, verification, false, true)!
	status := verdict(run, verification, false)
	if status == 0 { println('==> AArch64 QEMU ' + label + ' boot passed') }
	return status
}

pub fn run_vm(options Options) !int {
	if options.arch == 'amd64' {
		mut command := amd64_command(options, os.environ())
		command[0] = os.find_abs_path_of_executable(command[0])!
		println('==> Starting amd64 QEMU core feature boot')
		flush_stdout()
		run := capture(command, os.environ(), '', options.timeout, false, true, true)!
		status := verdict(run, false, true)
		if status == 0 { println('==> amd64 QEMU core regression passed') }
		return status
	}
	os.mkdir_all(options.state_dir)!
	first := phase(options, false)!
	if first != 0 { return first }
	second := phase(options, true)!
	if second == 0 { println('==> AArch64 QEMU core regression passed across reboot') }
	return second
}

pub fn cli(arguments []string, root string, cpu string) int {
	options := parse(arguments, root, cpu) or {
		eprintln(err.msg())
		return 2
	}
	guard := own_commands()
	defer { guard.close() }
	return run_vm(options) or {
		eprintln(err.msg())
		if err.msg() == 'Core guest run interrupted' { return err.code() }
		return 1
	}
}
