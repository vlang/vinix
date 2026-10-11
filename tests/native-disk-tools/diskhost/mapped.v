// SPDX-License-Identifier: GPL-2.0-or-later
module diskhost

import guesthost
import hosttest
import os

const mapped_steps = ['sync', 'syncfs', 'background', 'churn', 'private', 'pageout', 'pressure']

pub fn verify_mapping(data []u8, step string) ! {
	size := if step in ['pressure', 'private'] { 8 * 1024 * 1024 } else { 65536 }
	if data.len != size { return error(step + ': live mapping was not on disk at power cut') }
	for index, byte in data {
		wanted := if index == 17 {
			u8(0x82)
		} else if index == 65536 - 9 {
			u8(0x93)
		} else {
			u8((index * 37 + 11) & 255)
		}
		if byte != wanted {
			return error(step + ': live mapping was not on disk at power cut (byte ' + index.str() + ')')
		}
	}
}

fn mapped(args []string) !int {
	options := parse(args, [
		hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'amd64'] },
		hosttest.Option{ name: '--steps', value: true },
		hosttest.Option{ name: '--memory', value: true },
		hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--build-only' },
	],
		'Usage: run [--arch aarch64|amd64] [--steps sync,syncfs,background,churn,private,pageout] [--memory 1024] [--state-dir DIR] [--kernel-dir DIR] [--build-only]')!
	arch := options.value('--arch', 'aarch64')
	memory := integer(options, '--memory', 1024)!
	steps := options.value('--steps', 'sync,syncfs,background,churn,private,pageout').split(',')
	if steps.any(it !in mapped_steps) { return argument('unknown step') }
	if memory < 128 || ('pressure' in steps && memory > 512) {
		return argument('pressure needs 128–512 MiB')
	}
	seconds := timeout()!
	executable := tool()!
	work := work_dir(options, 'vinix-mapped-writeback-')!
	defer { remove_private(work, options) }
	kernel_dir := kernel(work, options.value('--kernel-dir', ''), arch)!
	init := work + '/init'
	run([...flags(arch), root() + '/tests/mapped-writeback/guest.c',
		'-DVINIX_TEST_MEMORY_MIB=' + memory.str(), '-pthread', '-o', init])!
	preseed := work + '/preseed'
	mkdir(preseed + '/many')!
	for index in 0 .. 1200 {
		os.write_file(preseed + '/many/f' + '0'.repeat(4 - index.str().len) + index.str(), '')!
	}
	disk := work + '/root.ext2'
	archive := work + '/initramfs.tar'
	if arch == 'aarch64' { format_ext2(executable, disk, preseed, 64 * 1024 * 1024)! }
	for step in steps {
		phase_archive(archive, step)!
		if arch == 'amd64' {
			append_init(archive, init, work)!
			seed := work + '/disk-seed'
			if os.is_dir(seed) { hosttest.remove_work_dir(seed)! }
			mkdir(seed + '/root')!
			hosttest.module_copy_tree(preseed + '/many', seed + '/root/many')!
			extract(archive, seed)!
			seed_identity(seed, archive)!
			format_ext2(executable, disk, seed, 64 * 1024 * 1024)!
		}
		configured := launch(init, archive, work, kernel_dir, arch, memory, disk, false, false)!
		if options.has('--build-only') {
			println('Prepared mapped-writeback guest: ' + work)
			return 0
		}
		if cut(configured, work + '/epochs/' + step, guesthost.PowercutPolicy{
			start:           'MAPPED WRITEBACK START'
			done:            'MAPPED WRITEBACK DONE'
			phase:           step
			failures:        ['FAIL END', 'FATAL EXCEPTION', 'KERNEL PANIC']
			failure_newline: true
		}, seconds, true)! != 0 {
			return 1
		}
		if step != 'churn' {
			observed := work + '/observed.bin'
			checked_capture([executable, '-R',
				'dump ' + if arch == 'amd64' { '/root' } else { '' } + '/mapped-' + step + ' ' + observed,
				disk])!
			verify_mapping(os.read_bytes(observed)!, step)!
		}
		println('PASS ' + arch + ' ' + step + ': verified after power cut')
	}
	return 0
}
