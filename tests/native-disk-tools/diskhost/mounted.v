// SPDX-License-Identifier: GPL-2.0-or-later
module diskhost

import guesthost
import hosttest
import json2
import os

pub fn mbr(start u32, sectors u32) []u8 {
	mut data := []u8{len: 512}
	data[450] = 0x83
	put(mut data, 454, start, 4)
	put(mut data, 458, sectors, 4)
	data[510], data[511] = 0x55, 0xaa
	return data
}

fn write_mbr(path string, start u32, sectors u32) ! {
	mut file := os.open_file(path, 'r+')!
	defer { file.close() }
	write_exact(mut file, mbr(start, sectors))!
}

fn evidence_write(path string, row map[string]json2.Any) ! {
	os.write_file(path, json2.encode(json2.Any(row)) + '\n')!
}

fn mounted(args []string) !int {
	options := parse(args, [
		hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'amd64'] },
		hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--source', value: true },
		hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--build-only' },
	],
		'Usage: run [--arch aarch64|amd64] [--state-dir DIR] [--source independent.c] [--kernel-dir DIR] [--build-only]')!
	arch := options.value('--arch', 'aarch64')
	seconds := timeout()!
	executable := tool()!
	if options.has('--state-dir') {
		state := resolve(options.value('--state-dir', ''))!
		if ['init', 'root.ext2', 'spare.raw', 'kernel', 'evidence.json'].any(os.exists(state + '/' + it) || os.is_link(state + '/' + it)) {
			return argument('Use a fresh state directory for independent guest disks and evidence')
		}
	}
	work := work_dir(options, 'vinix-securedisk-')!
	defer { remove_private(work, options) }
	kernel_dir := kernel(work, options.value('--kernel-dir', ''), arch)!
	link := [...flags(arch), '-pthread']
	module_path := root() + '/tests/mounted-disk-policy/diskfixture'
	fixture := if options.has('--source') {
		resolve(options.value('--source', ''))!
	} else {
		work + '/fixture.o'
	}
	if !options.has('--source') {
		guesthost.compile_module(module_path, fixture, if arch == 'aarch64' {
			arch
		} else {
			'x86_64'
		}, link)!
	}
	run([...link, fixture, '-o', work + '/init'])!
	mut sources := map[string]json2.Any{}
	for name in os.ls(module_path)!.sorted() {
		if os.is_file(module_path + '/' + name) {
			sources[name] = hosttest.sha(module_path + '/' + name)!
		}
	}
	mut evidence := {
		'arch':                     json2.Any(arch)
		'timeout':                  json2.Any(seconds)
		'independent_C_control':    json2.Any(options.has('--source'))
		'source_sha256':            if options.has('--source') {
			json2.Any(hosttest.sha(fixture)!)
		} else {
			json2.Any(sources)
		}
		'fixture_elf_sha256':       json2.Any(hosttest.sha(work + '/init')!)
		'native_link_flags':        json2.Any(link.map(json2.Any(it)))
		'runner_sha256':            json2.Any(hosttest.sha(root() + '/tests/native-disk-tools/diskhost/mounted.v')!)
		'immutable_kernel_sha256':  json2.Any(hosttest.sha(kernel_dir + '/bin/vinix')!)
		'kernel_rebuilt_by_runner': json2.Any(false)
	}
	evidence_write(work + '/evidence.json', evidence)!
	println('Guest artifacts: ' + work)
	spare := work + '/spare.raw'
	sparse_file(spare, 16 * 1024 * 1024)!
	write_mbr(spare, 2048, 16384)!
	archive, disk := work + '/initramfs.tar', work + '/root.ext2'
	phase_archive(archive, 'pass')!
	if arch == 'amd64' {
		append_init(archive, work + '/init', work)!
		extract(archive, work + '/seed')!
		seed_identity(work + '/seed', archive)!
		format_ext2(executable, disk, work + '/seed', 64 * 1024 * 1024)!
		write_mbr(disk, 0, 64 * 1024 * 1024 / 512)!
	}
	prior_extra := os.getenv_opt('VINIX_QEMU_EXTRA')
	if arch == 'aarch64' { os.unsetenv('VINIX_QEMU_EXTRA') }
	defer {
		if arch == 'aarch64' {
			if value := prior_extra {
				os.setenv('VINIX_QEMU_EXTRA', value, true)
			} else {
				os.unsetenv('VINIX_QEMU_EXTRA')
			}
		}
	}
	configured := launch(work + '/init', archive, work, kernel_dir, arch, if arch == 'aarch64' {
		2048
	} else {
		1024
	}, disk, false, false)!
	mut argv := configured.command.clone()
	if arch == 'aarch64' {
		// A CD transport keeps the boot ISO out of /dev/vd*. QEMU allocates
		// VirtIO MMIO slots in reverse creation order, so create the spare
		// before the root to retain mounted=/dev/vda and spare=/dev/vdb.
		for index, value in argv {
			if value.contains(',id=guest-iso') {
				argv[index] = value.replace(',id=guest-iso', ',media=cdrom,id=guest-iso')
			}
			if value == 'virtio-blk-device,drive=guest-iso' {
				argv[index] = 'virtio-scsi-device,id=policy-boot-scsi'
			}
		}
		argv << ['-device', 'scsi-cd,bus=policy-boot-scsi.0,drive=guest-iso']
		argv.insert(1, ['-drive', 'if=none,format=raw,file=' + spare + ',id=policy-spare', '-device',
			'virtio-blk-device,drive=policy-spare'])
	} else {
		argv << ['-drive', 'if=none,format=raw,file=' + spare + ',id=policy-spare,cache=writeback',
			'-device', 'ide-hd,drive=policy-spare,bus=ide.5']
	}
	os.write_file(work + '/command.json', json2.encode(json2.Any(argv.map(json2.Any(it)))) + '\n')!
	if options.has('--build-only') {
		println('Prepared mounted-disk guest: ' + work)
		return 0
	}
	if cut(guesthost.Launch{argv, configured.env}, work, guesthost.PowercutPolicy{
		start:           'SECUREDISK START'
		done:            'SECUREDISK DONE'
		phase:           'pass'
		failures:        ['FAIL END', 'FATAL EXCEPTION', 'KERNEL PANIC']
		failure_newline: arch == 'amd64'
		lookback:        if arch == 'aarch64' { 8192 } else { 0 }
	}, seconds, arch == 'amd64')! != 0 {
		return 1
	}
	fsck := capture([os.dir(executable) + '/e2fsck', '-f', '-n', disk])!
	os.write_file(work + '/e2fsck.log', fsck.stdout + fsck.stderr)!
	if fsck.status != 0 { return error('EXT2 check after guest:\n' + fsck.stdout + fsck.stderr) }
	payload := work + '/writeback.bin'
	text := checked_capture([executable, '-R',
		'dump ' + if arch == 'aarch64' { '/policy-writeback' } else { '/root/policy-writeback' } + ' ' + payload,
		disk])!
	os.write_file(work + '/debugfs.log', text)!
	data := os.read_bytes(payload)!
	if data.len != 65536 || data.any(it != 0x59) {
		return error('filesystem writeback did not persist its complete payload')
	}
	evidence['complete_native_verdict'] = true
	evidence['e2fsck_returncode'] = fsck.status
	evidence['persisted_payload_sha256'] = hosttest.sha(payload)!
	evidence['persisted_payload_bytes'] = data.len
	evidence_write(work + '/evidence.json', evidence)!
	println('PASS ' + arch + ': mounted-disk capabilities, denial retention, persisted writeback and EXT2 consistency')
	return 0
}
