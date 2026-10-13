// SPDX-License-Identifier: GPL-2.0-or-later
// Boot the unchanged native lockrange probe ELF against a supplied Linux kernel.
module main

import crypto.sha256
import guesthost
import hosttest
import json2
import os

struct ReferenceReceipt {
	architecture string
	context string = 'Linux QEMU reference; same native musl probe ELF; semantic checks only'
	artifacts map[string]string
	command []string
	passed bool
	finished bool
	forced bool
	status int
}
fn digest(path string) string { return sha256.sum(os.read_bytes(path) or { panic(err) }).hex() }
fn entry(mut archive []u8, name string, mode u32, inode u32, data []u8, major u32, minor u32) {
	mut header := '070701'
	for value in [inode, mode, u32(0), 0, 1, 0, u32(data.len), 0, 0, major, minor, u32(name.len + 1), 0]! { header += '${value:08x}' }
	archive << header.bytes(); archive << name.bytes(); archive << u8(0)
	for archive.len % 4 != 0 { archive << u8(0) }; archive << data
	for archive.len % 4 != 0 { archive << u8(0) }
}
fn verify(text string, arch string) ! {
	if arch !in ['aarch64', 'x86_64'] || !text.contains('LINUX LOCKRANGE REFERENCE: PASS') || !text.contains('Linux version ')
		|| text.contains('LINUX LOCKRANGE DETAIL:') || text.contains('LINUX LOCKRANGE FAIL') || text.contains('Kernel panic') { return error('Linux reference verdict failed') }
	rows := text.split_into_lines().filter(it.starts_with('LINUX LOCKRANGE CASES:')); if rows.len != 10 { return error('Missing reference case rows') }
	mut seen := map[string]bool{}
	for row in rows {
		fields := row.fields(); if fields.len != 7 { return error('Malformed reference case row') }
		group := fields[3].all_after('='); kind := fields[4].all_after('='); key := group + '-' + kind
		if !fields[3].starts_with('ordinary=') || !fields[4].starts_with('kind=') || group !in ['0', '1'] || kind !in ['0', '1', '2', '3', '4'] || key in seen || fields[6] != 'failures=0' { return error('Invalid reference outcomes') }; seen[key] = true
		if !fields[5].starts_with('calls=') || fields[5].all_after('=').int() <= 0 { return error('Unexpected reference case count') }
	}
}
fn run() ! {
	options := guesthost.parse(os.args[1..], [
		hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'x86_64'] },
		hosttest.Option{ name: '--kernel', value: true }, hosttest.Option{ name: '--init', value: true }, hosttest.Option{ name: '--state-dir', value: true },
	], [], 'Usage: lockrange-reference.v --arch aarch64|x86_64 --kernel LINUX --init NATIVE-PROBE-ELF --state-dir FRESH-DIR')!
	for key in ['--arch', '--kernel', '--init', '--state-dir'] { if !options.has(key) { return error('missing ' + key) } }
	arch := options.value('--arch', ''); state := options.value('--state-dir', '')
	if os.exists(state) { return error('state directory must be fresh') }; os.mkdir_all(state)!
	work := os.real_path(state); init := options.value('--init', ''); probe := os.read_bytes(init)!
	machine := if probe.len >= 20 { int(probe[18]) + (int(probe[19]) << 8) } else { 0 }
	if probe.len < 20 || probe[..6] != [u8(127), `E`, `L`, `F`, 2, 1] || machine != if arch == 'aarch64' { 183 } else { 62 } { return error('probe must be a matching little-endian ELF64') }
	os.write_file_array(work + '/probe', probe)!; os.write_file_array(work + '/linux', os.read_bytes(options.value('--kernel', ''))!)!
	root := os.real_path(os.dir(@FILE) + '/../..'); wrapper := root + '/tests/linux-compat/lockrangereferenceinit/core.v'
	os.mkdir_all(work + '/source/lockrangereferenceinit')!; os.write_file(work + '/source/lockrangereferenceinit/core.v', os.read_file(wrapper)!)!
	launcher := guesthost.compile_init(work + '/source/lockrangereferenceinit/core.v', work, arch, false)!
	mut archive := []u8{}
	for index, directory in ['.', 'dev', 'tmp', 'sbin', 'proc'] { entry(mut archive, directory, 0o040755, u32(index + 1), []u8{}, 0, 0) }
	entry(mut archive, 'dev/console', 0o020600, 5, []u8{}, 5, 1)
	entry(mut archive, 'sbin/probe', 0o100755, 6, os.read_bytes(work + '/probe')!, 0, 0)
	entry(mut archive, 'init', 0o100755, 7, os.read_bytes(launcher)!, 0, 0)
	entry(mut archive, 'TRAILER!!!', 0, 8, []u8{}, 0, 0); os.write_file_array(work + '/initramfs.cpio', archive)!
	mut command := if arch == 'aarch64' { ['qemu-system-aarch64', '-machine', 'virt', '-accel', 'hvf', '-cpu', 'host'] } else { ['qemu-system-x86_64', '-machine', 'q35', '-accel', 'tcg', '-cpu', 'max'] }
	command[0] = os.find_abs_path_of_executable(command[0])!
	command << ['-m', '512', '-smp', '2', '-kernel', work + '/linux', '-initrd', work + '/initramfs.cpio', '-append', if arch == 'aarch64' { 'console=ttyAMA0 rdinit=/init panic=-1' } else { 'console=ttyS0 rdinit=/init panic=-1' }, '-display', 'none', '-serial', 'mon:stdio', '-no-reboot']
	result := guesthost.boot_session(command, os.environ(), work, guesthost.SessionPolicy{pass: 'LINUX LOCKRANGE REFERENCE: PASS', failures: ['LINUX LOCKRANGE FAIL', 'LINUX LOCKRANGE REFERENCE FAIL', 'Kernel panic'], settle: 1, log: work + '/live.log'}, 180, true)!
	mut artifacts := {'kernel': digest(work + '/linux'), 'probe': digest(work + '/probe'), 'wrapper_source': digest(work + '/source/lockrangereferenceinit/core.v'), 'wrapper_c': digest(work + '/fixture.c'), 'wrapper_elf': digest(launcher), 'initramfs': digest(work + '/initramfs.cpio'), 'serial': digest(work + '/serial.log'), 'controller_source': digest(@FILE)}
	artifacts['serial_adapter_c'] = digest(work + '/serial.c')
	artifacts['qemu'] = digest(command[0])
	mut reason := ''; verify(result.text, arch) or { reason = err.msg() }
	valid := reason == '' && result.finished && result.passed && result.status == 0
	os.write_file(work + '/receipt.json', json2.encode(ReferenceReceipt{architecture: arch, artifacts: artifacts, command: command, passed: valid, finished: result.finished, forced: result.forced, status: result.status}, prettify: true) + '\n')!
	if !valid { return error(if reason != '' { reason } else { 'Linux reference session failed' }) }; println('Linux lockrange reference: PASS')
}
fn main() { run() or { eprintln(err.msg()); exit(1) } }
