// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import guesthost
import hosttest
import json2
import os

struct ReferenceReceipt {
	architecture string
	context string = 'Linux QEMU reference; same native musl probe ELF; portable mount lifecycle, pivot admission, teardown, alias, private-thread, bind policy, pathname truncation and mode/ownership checks; networking disabled'
	artifacts map[string]string
	command []string
	passed bool
	finished bool
	status int
}

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

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
		hosttest.Option{ name: '--kernel', value: true },
		hosttest.Option{ name: '--init', value: true },
		hosttest.Option{ name: '--state-dir', value: true },
	], [], 'Usage: reference.v --arch ARCH --kernel LINUX --init NATIVE-PROBE-ELF --state-dir FRESH-DIR')!
	for key in ['--arch', '--kernel', '--init', '--state-dir'] {
		if !options.has(key) { return error('missing ' + key) }
	}
	arch := options.value('--arch', '')
	state := os.abs_path(options.value('--state-dir', ''))
	if os.exists(state) { return error('state must be fresh') }
	probe := os.read_bytes(options.value('--init', ''))!
	machine := if arch == 'aarch64' { 183 } else { 62 }
	if probe.len < 20 || probe[..6] != [u8(127), `E`, `L`, `F`, 2, 1]
		|| int(probe[18]) + (int(probe[19]) << 8) != machine {
		return error('probe must be a matching little-endian ELF64')
	}
	os.mkdir_all(state + '/source/referencefixture')!
	os.write_file_array(state + '/probe', probe)!
	os.write_file_array(state + '/linux', os.read_bytes(options.value('--kernel', ''))!)!
	os.cp(@DIR + '/referencefixture/core.v', state + '/source/referencefixture/core.v')!
	launcher := guesthost.compile_init(state + '/source/referencefixture/core.v', state, arch, false)!
	mut archive := []u8{}
	for index, directory in ['.', 'dev', 'proc', 'tmp', 'sbin'] {
		entry(mut archive, directory, 0o040755, u32(index + 1), []u8{}, 0, 0)
	}
	entry(mut archive, 'dev/console', 0o020600, 6, []u8{}, 5, 1)
	entry(mut archive, 'sbin/probe', 0o100755, 7, probe, 0, 0)
	entry(mut archive, 'init', 0o100755, 8, os.read_bytes(launcher)!, 0, 0)
	entry(mut archive, 'mount-case', 0o100644, 9, 'move-reference'.bytes(), 0, 0)
	entry(mut archive, 'TRAILER!!!', 0, 10, []u8{}, 0, 0)
	os.write_file_array(state + '/initramfs.cpio', archive)!
	mut command := if arch == 'aarch64' {
		['qemu-system-aarch64', '-machine', 'virt', '-accel', 'hvf', '-cpu', 'host']
	} else { ['qemu-system-x86_64', '-machine', 'q35', '-accel', 'tcg', '-cpu', 'max'] }
	command[0] = os.find_abs_path_of_executable(command[0])!
	command << ['-m', '512', '-smp', '2', '-kernel', state + '/linux', '-initrd', state + '/initramfs.cpio',
		'-append', if arch == 'aarch64' { 'console=ttyAMA0 rdinit=/init panic=-1' } else { 'console=ttyS0 rdinit=/init panic=-1' },
		'-display', 'none', '-serial', 'mon:stdio', '-no-reboot', '-nic', 'none']
	result := guesthost.boot_session(command, os.environ(), state, guesthost.SessionPolicy{
		pass: 'MOUNT LIFECYCLE: PASS'
		failures: ['MOUNT LIFECYCLE FAIL:', 'MOUNT REFERENCE FAIL:', 'Kernel panic']
		settle: 1
		log: state + '/live.log'
	}, 180, true)!
	valid := result.finished && result.passed && result.status == 0
		&& result.text.contains('Linux version ') && result.text.contains('MOUNT MOVE CYCLES: PASS')
		&& result.text.contains('MOUNT REPARENTED HOLDERS: PASS')
		&& result.text.contains('MOUNT IDENTITIES: PASS')
		&& result.text.contains('MOUNT ADMISSION: PASS')
		&& result.text.contains('MOUNT PROPAGATION VALIDATION: PASS')
		&& result.text.contains('MOUNT PIVOT ADMISSION: PASS')
		&& result.text.contains('MOUNT PIVOT LIFECYCLE: PASS')
		&& result.text.contains('MOUNT PIVOT ALIASES: PASS')
		&& result.text.contains('MOUNT PIVOT THREADS: PASS')
		&& result.text.contains('MOUNT BIND POLICY: PASS')
		&& result.text.contains('MOUNT TRUNCATE: PASS')
		&& result.text.contains('MOUNT METADATA: PASS')
	mut cases_pass := true
	for kind in 0 .. 7 { cases_pass = cases_pass && result.text.contains('MOUNT IDENTITY CASE: ${kind} PASS') }
	for kind in 0 .. 8 { cases_pass = cases_pass && result.text.contains('MOUNT ADMISSION CASE: ${kind} PASS') }
	for kind in 0 .. 5 { cases_pass = cases_pass && result.text.contains('MOUNT PROPAGATION CASE: ${kind} PASS') }
	for kind in 0 .. 7 { cases_pass = cases_pass && result.text.contains('MOUNT PIVOT CASE: ${kind} PASS') }
	for kind in 0 .. 4 { cases_pass = cases_pass && result.text.contains('MOUNT PIVOT LIFE CASE: ${kind} PASS') }
	for kind in 0 .. 5 { cases_pass = cases_pass && result.text.contains('MOUNT PIVOT ALIAS CASE: ${kind} PASS') }
	for kind in 0 .. 7 { cases_pass = cases_pass && result.text.contains('MOUNT PIVOT THREAD CASE: ${kind} PASS') }
	for kind in 0 .. 5 { cases_pass = cases_pass && result.text.contains('MOUNT BIND POLICY CASE: ${kind} PASS') }
	for kind in 0 .. 6 { cases_pass = cases_pass && result.text.contains('MOUNT TRUNCATE CASE: ${kind} PASS') }
	for kind in 0 .. 7 { cases_pass = cases_pass && result.text.contains('MOUNT METADATA CASE: ${kind} PASS') }
	artifacts := {
		'kernel': digest(state + '/linux')!
		'probe': digest(state + '/probe')!
		'wrapper_source': digest(state + '/source/referencefixture/core.v')!
		'wrapper_elf': digest(launcher)!
		'wrapper_c': digest(state + '/fixture.c')!
		'initramfs': digest(state + '/initramfs.cpio')!
		'serial': digest(state + '/serial.log')!
		'controller_source': digest(@FILE)!
		'qemu': digest(command[0])!
	}
	os.write_file(state + '/receipt.json', json2.encode(ReferenceReceipt{
		architecture: arch, artifacts: artifacts, command: command,
		passed: valid && cases_pass, finished: result.finished, status: result.status
	}, prettify: true) + '\n')!
	if !valid || !cases_pass { return error('Linux mount reference failed: ' + state) }
	println('Linux mount reference: PASS')
}

fn main() { run() or { eprintln(err.msg()); exit(1) } }
