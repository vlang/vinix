// SPDX-License-Identifier: GPL-2.0-or-later
module diskhost

import guesthost
import hosttest
import os
import policyhost
import strconv
import time

#include <unistd.h>
#include <signal.h>

fn C.link(&char, &char) i32
fn C.kill(i32, i32) i32
fn C.getpid() i32

pub fn check_child(args []string) ! {
	if args[0] == 'idle' {
		for { time.sleep(100 * time.millisecond) }
	}
	if args[0] == 'interrupt' {
		time.sleep(150 * time.millisecond)
		C.kill(args[1].int(), C.SIGINT)
		return
	}
	if args[0] == 'silent' {
		os.write_file(args[1] + '/silent.pid', C.getpid().str())!
		for { time.sleep(100 * time.millisecond) }
	}
	if args[0] == 'reboot' {
		for marker in ['START', 'WROTE MARKER, REBOOTING', 'SYNCING', 'START', 'SYNCING', 'PASS'] {
			println('VINIX REBOOT PERSISTENCE: ' + marker)
			time.sleep(15 * time.millisecond)
		}
		return
	}
	os.write_file(args[1] + '/child.pid', C.getpid().str())!
	println('START')
	mut child := os.new_process(os.executable())
	child.set_args(['--child', 'idle'])
	child.run()
	os.write_file(args[1] + '/descendant.pid', child.pid.str())!
	print('DONE phase ino=1844674407370955161')
	flush_stdout()
	time.sleep(80 * time.millisecond)
	print('6\r')
	flush_stdout()
	time.sleep(80 * time.millisecond)
	print('\n')
	flush_stdout()
	time.sleep(500 * time.millisecond)
	os.write_file(args[1] + '/too-late', 'writer still alive')!
	child.wait()
	child.close()
}

fn reference_crc(data []u8) u32 {
	mut table := [256]u32{}
	for index in 0 .. 256 {
		mut value := u32(index)
		for _ in 0 .. 8 {
			value = if value & 1 == 1 { 0x82f63b78 ^ (value >> 1) } else { value >> 1 }
		}
		table[index] = value
	}
	mut value := u32(0xffffffff)
	for byte in data { value = table[(value ^ byte) & 255] ^ (value >> 8) }
	return ~value
}

fn failed_export(source string, output string) ! {
	export_clean(source, output) or { return }
	return error('Unsafe journal inspection accepted')
}

// An explicitly selected host model exercises the complete controller case
// sequence. Physical kernel durability remains the separate real guest check.
pub fn check_vm() ! {
	if os.getenv('VINIX_DISK_TEST_MODEL') != '1' {
		return error('Host journal model was not selected')
	}
	mode := strconv.atoi(os.getenv('VINIX_CMDLINE').all_after('vinix.journal_mode='))!
	mut trace := os.open_append(os.getenv('VINIX_DISK_TEST_TRACE'))!
	trace.writeln(mode.str())!
	trace.close()
	println('JOURNAL START')
	if mode in [101, 102, 103, 104, 105, 5] {
		println('JOURNAL CUT stage=' + if mode == 5 { '2' } else { (mode - 100).str() })
	} else {
		println('JOURNAL DONE ' + mode.str() + ' ino=0')
	}
	flush_stdout()
	for { time.sleep(100 * time.millisecond) }
}

fn check_journal_sequence(work string) ! {
	variables := ['VINIX_QEMU_X86_64', 'VINIX_DISK_TEST_MODEL', 'VINIX_DISK_TEST_TRACE']
	mut previous := map[string]string{}
	for name in variables { if value := os.getenv_opt(name) { previous[name] = value } }
	defer { for name in variables {
		if value := previous[name] { os.setenv(name, value, true) } else { os.unsetenv(name) }
	}
	 }
	os.setenv(variables[0], os.executable(), true)
	os.setenv(variables[1], '1', true)
	os.setenv(variables[2], work + '/journal-modes', true)
	os.write_file(work + '/journal-modes', '')!
	mkdir(work + '/model-kernel/bin')!
	mut elf := []u8{len: 20}
	for index, byte in [u8(0x7f), `E`, `L`, `F`, 2, 1] { elf[index] = byte }
	elf[18] = 62
	os.write_file_array(work + '/model-kernel/bin/vinix', elf)!
	if journal(['--arch', 'amd64', '--state-dir', work + '/journal-model', '--kernel-dir',
		work + '/model-kernel'])! != 0 {
		return error('Controlled journal case sequence failed')
	}
	modes := os.read_file(work + '/journal-modes')!.split_into_lines().map(it.int())
	if modes != [1, 2, 101, 201, 102, 202, 103, 203, 104, 204, 105, 205, 3, 4, 5, 6, 8] {
		return error('Journal controller skipped or reordered an epoch')
	}
}

fn assert_alive_gone(path string) ! {
	pid := os.read_file(path)!.int()
	deadline := time.sys_mono_now() + i64(2 * time.second)
	for C.kill(pid, 0) == 0 && time.sys_mono_now() < deadline { time.sleep(10 * time.millisecond) }
	if C.kill(pid, 0) == 0 { return error('Owned writer survived power cut: ' + pid.str()) }
}

fn check_powercut(work string) ! {
	mkdir(work + '/cut')!
	policy := guesthost.PowercutPolicy{ start: 'START', done: 'DONE', phase: 'phase', failures: ['FAIL'] }
	if guesthost.boot_powercut([os.executable(), '--child', 'writer', work + '/cut'], policyhost.environment(),
		work + '/cut', policy, 5, false, false)! != 0 {
		return error('Fragmented marker did not finish')
	}
	text := os.read_file(work + '/cut/serial.log')!
	_, inode := guesthost.powercut_done(text, 'DONE') or { return error('Missing complete marker') }
	if inode != '18446744073709551616' || os.exists(work + '/cut/too-late') {
		return error('Power cut occurred at the wrong time')
	}
	assert_alive_gone(work + '/cut/child.pid')!
	assert_alive_gone(work + '/cut/descendant.pid')!
	mkdir(work + '/interrupted')!
	mut interrupter := os.new_process(os.executable())
	interrupter.set_args(['--child', 'interrupt', C.getpid().str()])
	interrupter.run()
	defer {
		interrupter.wait()
		interrupter.close()
	}
	start := time.sys_mono_now()
	guesthost.boot_powercut([os.executable(), '--child', 'silent', work + '/interrupted'], policyhost.environment(),
		work + '/interrupted', policy, 20, false, false) or {
		if err.msg() != 'Guest run interrupted' { return err }
		if time.sys_mono_now() - start > i64(time.second) {
			return error('Slow interrupt retirement')
		}
		assert_alive_gone(work + '/interrupted/silent.pid')!
		return
	}
	return error('Interrupt was not delivered')
}

fn check_images(work string, executable string) ! {
	if crc32c('123456789'.bytes()) != 0xe3069283 { return error('CRC32C vector changed') }
	uuid := []u8{len: 16, init: u8(index * 13)}
	config := journal_config(uuid, 64 * 1024 * 1024)!
	if config[..8].bytestr() != 'VNIXJNL1' || number(config, 8, 4) != 1 || number(config, 12, 4) != 4096
		|| number(config, 16, 8) != 64 * 1024 * 1024 || number(config, 24, 8) != 64 * 1024 * 1024
		|| number(config, 32, 8) != 4 * 1024 * 1024 || config[40..56] != uuid || config[60..].any(it != 0) {
		return error('Journal configuration layout changed')
	}
	stored := number(config, 56, 4)
	mut clear := config.clone()
	for index in 56 .. 60 { clear[index] = 0 }
	if stored != reference_crc(clear) { return error('Journal checksum changed') }
	seed := work + '/seed'
	mkdir(seed)!
	os.write_file(seed + '/source', 'payload')!
	source := work + '/test.vjfs'
	journal_fixture(source, seed, executable, 64)!
	before := hosttest.sha(source)!
	mut input := os.open(source)!
	if number(read_exact(mut input, 1080, 2)!, 0, 2) != 0x4a56 {
		return error('VJFS signature missing')
	}
	physical_config := read_exact(mut input, 64 * 1024 * 1024, 4096)!
	physical_uuid := read_exact(mut input, 1128, 16)!
	if physical_config != journal_config(physical_uuid, 64 * 1024 * 1024)! {
		return error('Serialized fixture UUID differs')
	}
	input.close()
	failed_export(source, source)!
	os.symlink(source, work + '/alias')!
	failed_export(source, work + '/alias')!
	if C.link(source.str, (work + '/hardlink').str) != 0 { return os.error_posix() }
	failed_export(source, work + '/hardlink')!
	exported := export_clean(source, work + '/inspection.ext2')!
	checked_capture([os.dir(executable) + '/e2fsck', '-f', '-n', exported])!
	checked_capture([executable, '-R', 'dump /source ' + work + '/dump', exported])!
	if os.read_file(work + '/dump')! != 'payload' || hosttest.sha(source)! != before {
		return error('Export modified the live volume')
	}
	mut write := os.open_file(source, 'r+')!
	write.seek(64 * 1024 * 1024 + 4096, .start)!
	write_exact(mut write, [u8(1)])!
	write.close()
	failed_export(source, work + '/dirty.ext2')!
	// A sparse 4 GiB volume exercises streaming and all sparse-super backup
	// groups without allocating 4 GiB of memory or host disk blocks.
	large := work + '/large.vjfs'
	sparse_file(large, i64(4) * 1024 * 1024 * 1024 + tail)!
	mut volume := os.open_file(large, 'r+')!
	mut sb := []u8{len: 1024}
	put(mut sb, 4, 1024 * 1024, 4)
	put(mut sb, 24, 2, 4)
	put(mut sb, 32, 32768, 4)
	put(mut sb, 100, 1, 4)
	volume.seek(1024, .start)!
	write_exact(mut volume, sb)!
	volume.seek(i64(4) * 1024 * 1024 * 1024 - 1, .start)!
	write_exact(mut volume, [u8(0xa5)])!
	volume.close()
	export_clean(large, work + '/large.ext2')!
	mut copied := os.open(work + '/large.ext2')!
	for group in 1 .. 32 {
		signature := read_exact(mut copied, i64(group) * 32768 * 4096 + 56, 2)!
		wanted := if group in [1, 3, 5, 7, 9, 25, 27] {
			[u8(0x53), 0xef]
		} else {
			[u8(0), 0]
		}
		if signature != wanted { return error('Wrong sparse backup signature: ' + group.str()) }
	}
	if read_exact(mut copied, i64(4) * 1024 * 1024 * 1024 - 1, 1)! != [u8(0xa5)] {
		return error('Sparse volume lost its final byte')
	}
	copied.close()
}

pub fn check() ! {
	work := hosttest.work_dir('', 'vinix-disk-check-')!
	defer { hosttest.remove_work_dir(work) or { eprintln(err.msg()) } }
	for text, wanted in {
		'Type: regular Mode: 0600 Links: 2':                 {
			'Type':  'regular'
			'Mode':  '0600'
			'Links': '2'
		}
		'αType: wrong ; Type:\u0085directory Links:\u20031': {
			'Type':  'directory'
			'Links': '1'
		}
		'xType: bad Type:regular Mode: ':                    map[string]string{}
	} {
		if inode_fields(text) != wanted { return error('Inode field match changed') }
	}
	for step in ['sync', 'private'] {
		mut data := []u8{len: if step == 'private' { 8 * 1024 * 1024 } else { 65536 }, init: u8((index * 37 + 11) & 255)}
		data[17], data[65536 - 9] = 0x82, 0x93
		verify_mapping(data, step)!
		data[data.len - 1] ^= 1
		mut rejected := false
		verify_mapping(data, step) or { rejected = true }
		if !rejected { return error('Complete payload check missed the final byte') }
	}
	partition := mbr(2048, 16384)
	if partition[450] != 0x83 || number(partition, 454, 4) != 2048 || number(partition, 458, 4) != 16384 || partition[510..] != [
		u8(0x55),
		0xaa,
	] {
		return error('Spare disk MBR changed')
	}
	check_images(work, tool()!)!
	check_powercut(work)!
	mkdir(work + '/reboot')!
	if guesthost.boot_reboot([os.executable(), '--child', 'reboot'], policyhost.environment(), work + '/reboot', 5, false)! != 0 {
		return error('Two-boot bracket capture rejected')
	}
	text := os.read_file(work + '/reboot/serial.log')!
	for damaged in [text.replace('SYNCING', ''), text.replace('WROTE MARKER, REBOOTING', ''),
		text + 'KERNEL PANIC'] {
		if guesthost.reboot_verdict(damaged) == 0 {
			return error('Reboot incomplete bracket accepted')
		}
	}
	check_journal_sequence(work)!
	println('PASS disk controller formats, complete payloads, read-only sparse export, fragmented markers, 17 journal epochs and owned writer retirement')
}
