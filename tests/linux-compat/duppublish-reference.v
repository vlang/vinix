// SPDX-License-Identifier: GPL-2.0-or-later
// Boot the unchanged native duppublish probe ELF against a supplied Linux kernel.
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
	if arch !in ['aarch64', 'x86_64'] || !text.contains('LINUX DUPPUBLISH REFERENCE: PASS') || !text.contains('Linux version ')
		|| text.contains('LINUX DUPPUBLISH FAIL') || text.contains('Kernel panic') { return error('Linux reference verdict failed') }
	rows := text.split_into_lines().filter(it.starts_with('LINUX DUPPUBLISH FLAGS:')); if rows.len != 12 { return error('Missing reference flag rows') }
	mut seen := map[string]bool{}
	for row in rows {
		fields := row.fields(); if fields.len != 13 { return error('Malformed flag row') }
		group := fields[3].all_after('='); method := fields[4].all_after('='); key := group + '-' + method
		if !fields[3].starts_with('ordinary=') || !fields[4].starts_with('method=') || group !in ['0', '1'] || method !in ['0', '1', '2', '3', '4', '5'] || key in seen { return error('Invalid flag cohort') }; seen[key] = true
		if !fields[6].starts_with('samples=') || fields[6].all_after('=') == '' || !fields[6].all_after('=').bytes().all(it.is_digit()) { return error('Malformed sample count') }
		if fields[5] != 'calls=128' || fields[6].all_after('=').u64() < 128 || fields[7] != 'bad=0' || fields[8] != 'forks=16' || fields[9] != 'fork_bad=0' || fields[10] != 'post_bad=0' || fields[11] != 'producer_bad=0' || fields[12] != 'PASS' { return error('Reference flag failure') }
	}
	closes := text.split_into_lines().filter(it.starts_with('LINUX DUPPUBLISH CLOSE:')); if closes.len != 2 { return error('Missing reference close rows') }
	mut groups := map[string]bool{}
	for row in closes {
		fields := row.fields(); if fields.len != 8 { return error('Malformed close row') }; group := fields[3].all_after('=')
		if !fields[3].starts_with('ordinary=') || group !in ['0', '1'] || group in groups || fields[4] != 'calls=200' || !fields[5].starts_with('during=') || fields[5].all_after('=') == '' || !fields[5].all_after('=').bytes().all(it.is_digit()) || fields[5].all_after('=').int() > 200 || fields[6] != 'bad=0' || fields[7] != 'PASS' { return error('Reference close failure') }; groups[group] = true
	}
}
fn run() ! {
	options := guesthost.parse(os.args[1..], [
		hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'x86_64'] },
		hosttest.Option{ name: '--kernel', value: true }, hosttest.Option{ name: '--init', value: true }, hosttest.Option{ name: '--state-dir', value: true },
	], [], 'Usage: duppublish-reference.v --arch aarch64|x86_64 --kernel LINUX --init NATIVE-PROBE-ELF --state-dir FRESH-DIR')!
	for key in ['--arch', '--kernel', '--init', '--state-dir'] { if !options.has(key) { return error('missing ' + key) } }
	arch := options.value('--arch', ''); state := options.value('--state-dir', '')
	if os.exists(state) { return error('state directory must be fresh') }; os.mkdir_all(state)!
	work := os.real_path(state); init := options.value('--init', ''); probe := os.read_bytes(init)!
	machine := if probe.len >= 20 { int(probe[18]) + (int(probe[19]) << 8) } else { 0 }
	if probe.len < 20 || probe[..6] != [u8(127), `E`, `L`, `F`, 2, 1] || machine != if arch == 'aarch64' { 183 } else { 62 } { return error('probe must be a matching little-endian ELF64') }
	os.write_file_array(work + '/probe', probe)!; os.write_file_array(work + '/linux', os.read_bytes(options.value('--kernel', ''))!)!
	root := os.real_path(os.dir(@FILE) + '/../..'); wrapper := root + '/tests/linux-compat/duppublishreferenceinit/core.v'
	os.mkdir_all(work + '/source/duppublishreferenceinit')!; os.write_file(work + '/source/duppublishreferenceinit/core.v', os.read_file(wrapper)!)!
	launcher := guesthost.compile_init(work + '/source/duppublishreferenceinit/core.v', work, arch, false)!
	mut archive := []u8{}
	for index, directory in ['.', 'dev', 'tmp', 'sbin'] { entry(mut archive, directory, 0o040755, u32(index + 1), []u8{}, 0, 0) }
	entry(mut archive, 'dev/console', 0o020600, 5, []u8{}, 5, 1)
	entry(mut archive, 'sbin/probe', 0o100755, 6, os.read_bytes(work + '/probe')!, 0, 0)
	entry(mut archive, 'init', 0o100755, 7, os.read_bytes(launcher)!, 0, 0)
	entry(mut archive, 'TRAILER!!!', 0, 8, []u8{}, 0, 0); os.write_file_array(work + '/initramfs.cpio', archive)!
	mut command := if arch == 'aarch64' { ['qemu-system-aarch64', '-machine', 'virt', '-accel', 'hvf', '-cpu', 'host'] } else { ['qemu-system-x86_64', '-machine', 'q35', '-accel', 'tcg', '-cpu', 'max'] }
	command[0] = os.find_abs_path_of_executable(command[0])!
	command << ['-m', '512', '-smp', '2', '-kernel', work + '/linux', '-initrd', work + '/initramfs.cpio', '-append', if arch == 'aarch64' { 'console=ttyAMA0 rdinit=/init panic=-1' } else { 'console=ttyS0 rdinit=/init panic=-1' }, '-display', 'none', '-serial', 'mon:stdio', '-no-reboot']
	result := guesthost.boot_session(command, os.environ(), work, guesthost.SessionPolicy{pass: 'LINUX DUPPUBLISH REFERENCE: PASS', failures: ['LINUX DUPPUBLISH FAIL', 'LINUX DUPPUBLISH REFERENCE FAIL', 'Kernel panic'], settle: 1, log: work + '/live.log'}, 180, true)!
	mut artifacts := {'kernel': digest(work + '/linux'), 'probe': digest(work + '/probe'), 'wrapper_source': digest(work + '/source/duppublishreferenceinit/core.v'), 'wrapper_c': digest(work + '/fixture.c'), 'wrapper_elf': digest(launcher), 'initramfs': digest(work + '/initramfs.cpio'), 'serial': digest(work + '/serial.log'), 'controller_source': digest(@FILE)}
	artifacts['serial_adapter_c'] = digest(work + '/serial.c')
	artifacts['qemu'] = digest(command[0])
	mut reason := ''; verify(result.text, arch) or { reason = err.msg() }
	valid := reason == '' && result.finished && result.passed && result.status == 0
	os.write_file(work + '/receipt.json', json2.encode(ReferenceReceipt{architecture: arch, artifacts: artifacts, command: command, passed: valid, finished: result.finished, forced: result.forced, status: result.status}, prettify: true) + '\n')!
	if !valid { return error(if reason != '' { reason } else { 'Linux reference session failed' }) }; println('Linux duppublish reference: PASS')
}
fn main() { run() or { eprintln(err.msg()); exit(1) } }
