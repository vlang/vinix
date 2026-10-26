// SPDX-License-Identifier: GPL-2.0-or-later
// Boot the unchanged native pidfdwait probe ELF against a supplied Linux kernel.
module main

import crypto.sha256
import guesthost
import hosttest
import json2
import os

struct ReferenceReceipt {
	architecture string
	context      string = 'Linux QEMU reference; unchanged native musl probe ELF; semantic log validation'
	artifacts    map[string]string
	command      []string
	passed       bool
	finished     bool
	forced       bool
	status       int
	validation   string
}

fn digest(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn entry(mut archive []u8, name string, mode u32, inode u32, data []u8, major u32, minor u32) {
	mut header := '070701'
	for value in [inode, mode, u32(0), 0, 1, 0, u32(data.len), 0, 0, major, minor, u32(name.len + 1),
		0]! {
		header += '${value:08x}'
	}
	archive << header.bytes()
	archive << name.bytes()
	archive << u8(0)
	for archive.len % 4 != 0 { archive << u8(0) }
	archive << data
	for archive.len % 4 != 0 { archive << u8(0) }
}

fn verify(log_path string, checker string) ! {
	// Invoke the retained checker, so native and reference acceptance use one
	// semantic oracle. Its exit status is checked explicitly in every build mode.
	mut process := os.new_process(checker)
	process.set_args(['--log', log_path, '--mode', 'reference'])
	process.set_redirect_stdio_merged()
	process.run()
	output := process.stdout_slurp()
	process.wait()
	status := process.code
	process.close()
	if status != 0 {
		return error('Linux reference semantic validation failed: ' + output.trim_space())
	}
}

fn compile_checker(source string, output string) ! {
	compiler := os.getenv_opt('VINIX_V_COMPILER') or {
		os.getenv_opt('V') or { os.find_abs_path_of_executable('v')! }
	}
	mut process := os.new_process(if os.is_dir(compiler) { compiler + '/v' } else { compiler })
	process.set_args(['-o', output, source])
	process.set_redirect_stdio_merged()
	process.run()
	text := process.stdout_slurp()
	process.wait()
	status := process.code
	process.close()
	if status != 0 {
		return error('could not build retained semantic checker: ' + text.trim_space())
	}
}

fn run() ! {
	options := guesthost.parse(os.args[1..], [
		hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'x86_64'] },
		hosttest.Option{ name: '--kernel', value: true },
		hosttest.Option{ name: '--init', value: true },
		hosttest.Option{ name: '--state-dir', value: true },
	], [], 'Usage: pidfdwait-reference.v --arch aarch64|x86_64 --kernel LINUX --init NATIVE-PROBE-ELF --state-dir FRESH-DIR')!
	for key in ['--arch', '--kernel', '--init', '--state-dir'] {
		if !options.has(key) { return error('missing ' + key) }
	}
	arch := options.value('--arch', '')
	state := options.value('--state-dir', '')
	if os.exists(state) { return error('state directory must be fresh') }
	os.mkdir_all(state)!
	work := os.real_path(state)
	probe := os.read_bytes(options.value('--init', ''))!
	machine := if probe.len >= 20 { int(probe[18]) + (int(probe[19]) << 8) } else { 0 }
	if probe.len < 20 || probe[..6] != [u8(127), `E`, `L`, `F`, 2, 1] || machine != if arch == 'aarch64' {
		183
	} else {
		62
	} {
		return error('probe must be a matching little-endian ELF64')
	}
	os.write_file_array(work + '/probe', probe)!
	os.write_file_array(work + '/linux', os.read_bytes(options.value('--kernel', ''))!)!
	root := os.real_path(os.dir(@FILE) + '/../..')
	wrapper := root + '/tests/linux-compat/pidfdwaitreferenceinit/core.v'
	os.mkdir_all(work + '/source/pidfdwaitreferenceinit')!
	os.write_file(work + '/source/pidfdwaitreferenceinit/core.v', os.read_file(wrapper)!)!
	os.write_file(work + '/source/pidfdwait-reference.v', os.read_file(@FILE)!)!
	os.write_file(work + '/source/pidfdwait-check.v', os.read_file(root + '/tests/linux-compat/pidfdwait-check.v')!)!
	checker := work + '/pidfdwait-check'
	compile_checker(work + '/source/pidfdwait-check.v', checker)!
	launcher := guesthost.compile_init(work + '/source/pidfdwaitreferenceinit/core.v', work, arch, false)!
	mut archive := []u8{}
	for index, directory in ['.', 'dev', 'tmp', 'sbin', 'proc'] {
		entry(mut archive, directory, 0o040755, u32(index + 1), []u8{}, 0, 0)
	}
	entry(mut archive, 'dev/console', 0o020600, 5, []u8{}, 5, 1)
	entry(mut archive, 'dev/null', 0o020666, 9, []u8{}, 1, 3)
	entry(mut archive, 'sbin/probe', 0o100755, 6, probe, 0, 0)
	entry(mut archive, 'init', 0o100755, 7, os.read_bytes(launcher)!, 0, 0)
	entry(mut archive, 'TRAILER!!!', 0, 8, []u8{}, 0, 0)
	os.write_file_array(work + '/initramfs.cpio', archive)!
	mut command := if arch == 'aarch64' {
		['qemu-system-aarch64', '-machine', 'virt', '-accel', 'hvf', '-cpu', 'host']
	} else {
		['qemu-system-x86_64', '-machine', 'q35', '-accel', 'tcg', '-cpu', 'max']
	}
	command[0] = os.find_abs_path_of_executable(command[0])!
	command << ['-m', '512', '-smp', '2', '-kernel', work + '/linux', '-initrd',
		work + '/initramfs.cpio', '-append', if arch == 'aarch64' {
			'console=ttyAMA0 rdinit=/init panic=-1'
		} else {
			'console=ttyS0 rdinit=/init panic=-1'
		}, '-display', 'none', '-serial', 'mon:stdio', '-no-reboot']
	result := guesthost.boot_session(command, os.environ(), work, guesthost.SessionPolicy{
		pass:     'LINUX PIDFDWAIT REFERENCE: PASS'
		failures: [
			'LINUX PIDFDWAIT DETAIL:',
			'LINUX PIDFDWAIT FAIL',
			'LINUX PIDFDWAIT REFERENCE FAIL',
			'Kernel panic',
		]
		settle:   1
		log:      work + '/live.log'
	}, 600, true)!
	mut artifacts := {
		'kernel':            digest(work + '/linux')!
		'probe':             digest(work + '/probe')!
		'wrapper_source':    digest(work + '/source/pidfdwaitreferenceinit/core.v')!
		'wrapper_c':         digest(work + '/fixture.c')!
		'wrapper_elf':       digest(launcher)!
		'initramfs':         digest(work + '/initramfs.cpio')!
		'serial':            digest(work + '/serial.log')!
		'controller_source': digest(work + '/source/pidfdwait-reference.v')!
		'checker_source':    digest(work + '/source/pidfdwait-check.v')!
		'checker':           digest(checker)!
	}
	artifacts['serial_adapter_c'] = digest(work + '/serial.c')!
	artifacts['qemu'] = digest(command[0])!
	mut reason := ''
	verify(work + '/serial.log', checker) or { reason = err.msg() }
	valid := reason == '' && result.finished && result.passed && result.status == 0
	os.write_file(work + '/receipt.json', json2.encode(ReferenceReceipt{
		architecture: arch
		artifacts:    artifacts
		command:      command
		passed:       valid
		finished:     result.finished
		forced:       result.forced
		status:       result.status
		validation:   reason
	}, prettify: true) + '\n')!
	if !valid { return error(if reason != '' { reason } else { 'Linux reference session failed' }) }
	println('Linux pidfdwait reference: PASS')
}

fn main() {
	run() or {
		eprintln(err.msg())
		exit(1)
	}
}
