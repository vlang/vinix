// SPDX-License-Identifier: GPL-2.0-or-later
// Boot an unchanged native linux-compat probe ELF on a supplied Linux kernel,
// so the probe's expectations are checked against Linux itself. The probe
// prints `LINUX <CASE> REFERENCE: PASS` when run with --reference.
module main

import crypto.sha256
import guesthost
import hosttest
import json2
import os

struct ReferenceReceipt {
	architecture string
	case_name    string
	context      string = 'Linux QEMU reference; same native musl probe ELF; semantic checks only'
	artifacts    map[string]string
	command      []string
	summary      string
	passed       bool
	finished     bool
	forced       bool
	status       int
}

fn digest(path string) string { return sha256.sum(os.read_bytes(path) or { panic(err) }).hex() }

fn entry(mut archive []u8, name string, mode u32, inode u32, data []u8, major u32, minor u32) {
	mut header := '070701'
	for value in [inode, mode, u32(0), 0, 1, 0, u32(data.len), 0, 0, major, minor, u32(name.len + 1), 0]! {
		header += '${value:08x}'
	}
	archive << header.bytes()
	archive << name.bytes()
	archive << u8(0)
	for archive.len % 4 != 0 { archive << u8(0) }
	archive << data
	for archive.len % 4 != 0 { archive << u8(0) }
}

fn run() ! {
	options := guesthost.parse(os.args[1..], [
		hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'x86_64'] },
		hosttest.Option{ name: '--case', value: true },
		hosttest.Option{ name: '--kernel', value: true },
		hosttest.Option{ name: '--init', value: true },
		hosttest.Option{ name: '--source', value: true },
		hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--numa' },
	], [], 'Usage: syscall-reference.v --arch aarch64|x86_64 --case NAME --kernel LINUX (--init NATIVE-PROBE-ELF | --source PROBE.v) --state-dir FRESH-DIR [--numa]')!
	for key in ['--arch', '--case', '--kernel', '--state-dir'] {
		if !options.has(key) { return error('missing ' + key) }
	}
	if options.has('--init') == options.has('--source') { return error('give one of --init or --source') }
	arch := options.value('--arch', '')
	name := options.value('--case', '').to_upper()
	if name == '' || !name.bytes().all(it.is_letter() || it.is_digit()) { return error('invalid case name') }
	state := options.value('--state-dir', '')
	if os.exists(state) { return error('state directory must be fresh') }
	os.mkdir_all(state)!
	work := os.real_path(state)
	// --source compiles a probe module the way the Vinix controller does.
	probe_path := if options.has('--source') {
		os.mkdir_all(work + '/probe-build')!
		guesthost.compile_init(os.real_path(options.value('--source', '')), work + '/probe-build', arch, false)!
	} else {
		options.value('--init', '')
	}
	probe := os.read_bytes(probe_path)!
	machine := if probe.len >= 20 { int(probe[18]) + (int(probe[19]) << 8) } else { 0 }
	if probe.len < 20 || probe[..6] != [u8(127), `E`, `L`, `F`, 2, 1] || machine != if arch == 'aarch64' { 183 } else { 62 } {
		return error('probe must be a matching little-endian ELF64')
	}
	os.write_file_array(work + '/probe', probe)!
	os.write_file_array(work + '/linux', os.read_bytes(options.value('--kernel', ''))!)!
	root := os.real_path(os.dir(@FILE) + '/../..')
	wrapper := root + '/tests/linux-compat/syscallreferenceinit/core.v'
	os.mkdir_all(work + '/source/syscallreferenceinit')!
	os.write_file(work + '/source/syscallreferenceinit/core.v', os.read_file(wrapper)!)!
	launcher := guesthost.compile_init(work + '/source/syscallreferenceinit/core.v', work, arch, false)!
	mut archive := []u8{}
	for index, directory in ['.', 'dev', 'tmp', 'sbin', 'proc'] {
		entry(mut archive, directory, 0o040755, u32(index + 1), []u8{}, 0, 0)
	}
	entry(mut archive, 'dev/console', 0o020600, 5, []u8{}, 5, 1)
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
	command << ['-m', '512', '-smp', '2', '-kernel', work + '/linux', '-initrd', work + '/initramfs.cpio',
		'-append', if arch == 'aarch64' { 'console=ttyAMA0 rdinit=/init panic=-1' } else { 'console=ttyS0 rdinit=/init panic=-1' },
		'-display', 'none', '-serial', 'mon:stdio', '-no-reboot']
	if options.has('--numa') {
		command = guesthost.two_node_command(command)
		command[command.index('-append') + 1] += ' numa_balancing=disable'
	}
	pass := 'LINUX ' + name + ' REFERENCE: PASS'
	result := guesthost.boot_session(command, os.environ(), work, guesthost.SessionPolicy{
		pass: pass
		failures: ['LINUX ' + name + ' FAIL', 'LINUX REFERENCE FAIL', 'Kernel panic']
		settle: 1
		log: work + '/live.log'
	}, 300, true)!
	summary := result.text.split_into_lines().filter(it.starts_with('LINUX ' + name + ' SUMMARY:'))
	valid := result.finished && result.passed && result.status == 0 && result.text.contains(pass)
		&& result.text.contains('Linux version ') && summary.len == 1
	artifacts := {
		'kernel':            digest(work + '/linux')
		'probe':             digest(work + '/probe')
		'wrapper_source':    digest(work + '/source/syscallreferenceinit/core.v')
		'wrapper_elf':       digest(launcher)
		'initramfs':         digest(work + '/initramfs.cpio')
		'serial':            digest(work + '/serial.log')
		'controller_source': digest(@FILE)
		'qemu':              digest(command[0])
	}
	os.write_file(work + '/receipt.json', json2.encode(ReferenceReceipt{
		architecture: arch
		case_name: name.to_lower()
		artifacts: artifacts
		command: command
		summary: if summary.len == 1 { summary[0] } else { '' }
		passed: valid
		finished: result.finished
		forced: result.forced
		status: result.status
	}, prettify: true) + '\n')!
	if !valid { return error('Linux reference session failed; see ' + work) }
	println(summary[0])
	println('Linux ' + name.to_lower() + ' reference: PASS')
}

fn main() {
	run() or {
		eprintln(err.msg())
		exit(1)
	}
}
