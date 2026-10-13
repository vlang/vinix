// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import imagehost
import os
import sourcecommand
import time

fn native(argv []string, environment map[string]string) !sourcecommand.Output {
	result := sourcecommand.capture_full(argv, environment, 20, 4 * 1024 * 1024, cachecli.cancelled)!
	if result.status != 0 { return error(result.stderr) }
	return result
}

fn mocked() !bool {
	name := os.file_name(os.args[0])
	if name !in ['mformat', 'mmd', 'mcopy'] { return false }
	mode := os.getenv('VINIX_IMAGE_CASE')
	work := os.getenv('VINIX_IMAGE_WORK')
	if name == 'mformat' && mode == 'failure' { exit(23) }
	if name == 'mcopy' && mode == 'race' && os.args.last() == '::/boot/initramfs.tar' {
		os.write_file(work + '/image', 'concurrent owner')!
	}
	if name == 'mformat' && mode == 'interrupt' {
		os.write_file(work + '/child.pid', os.getpid().str())!
		for { time.sleep(10 * time.millisecond) }
	}
	return true
}

fn send_signal(work string) {
	deadline := time.sys_mono_now() + 5 * time.second
	for !os.exists(work + '/child.pid') && time.sys_mono_now() < deadline {
		time.sleep(time.millisecond)
	}
	C.kill(os.getpid(), C.SIGINT)
}

fn math_cases() ! {
	for input, expected in {
		'0':             '0 bytes'
		'1':             '1 bytes'
		'1023':          '1023 bytes'
		'1024':          '1.0 KiB'
		'1536':          '1.5 KiB'
		'1048576':       '1.0 MiB'
		'1073741824':    '1.0 GiB'
		'2147483647':    '2.0 GiB'
		'1099511627776': '1024.0 GiB'
		'0.5':           '0 bytes'
		'1.5':           '2 bytes'
		'1280':          '1.2 KiB'
		'1792':          '1.8 KiB'
	} {
		assert imagehost.human_size(input)! == expected, input
	}
	for input in ['nan', 'inf', '-1', 'invalid'] {
		mut failed := false
		imagehost.human_size(input) or {
			failed = true
			''
		}
		assert failed
	}
	for payload, expected in {
		u64(0):          u64(128)
		u64(1):          u64(129)
		u64(1048576):    u64(129)
		u64(1048577):    u64(130)
		u64(2147483648): u64(2176)
	} {
		assert imagehost.image_size([payload])! == expected
	}
	mut failed := false
	imagehost.image_size([u64(0xffffffffffffffff)]) or {
		failed = true
		u64(0)
	}
	assert failed
	println('PASS size boundaries, ties-to-even formatting and checked image arithmetic')
}

fn image_cases(work string) ! {
	os.mkdir_all(work + '/project/kernel/bin')!
	os.mkdir_all(work + '/project/boot-image/limine-bin')!
	os.mkdir(work + '/tmp')!
	os.setenv('TMPDIR', work + '/tmp', true)
	root := work + '/project'
	kernel := root + '/kernel/bin/vinix'
	limine := root + '/boot-image/limine-bin/BOOTAA64.EFI'
	initramfs := work + '/initramfs'
	os.write_file(kernel, '\x7fELFnative kernel')!
	os.write_file(limine, 'native firmware')!
	os.write_file(initramfs, 'native initramfs\n'.repeat(100))!
	baseline := os.ls('/dev/fd')!.len
	mask := C.umask(0o077)
	mut image := work + '/real image.img'
	assert imagehost.build(root, image, initramfs, os.environ())! == 129
	C.umask(mask)
	assert os.stat(image)!.size == 129 * 1024 * 1024 && os.stat(image)!.mode & 0o777 == 0o600
	assert os.ls(work + '/tmp')!.len == 0 && os.ls('/dev/fd')!.len == baseline
	boot := native(['mtype', '-i', image, '::/boot/limine.conf'], os.environ())!
	assert boot.stdout == imagehost.limine_config
	for path, member in {
		kernel:    '::/boot/vinix'
		limine:    '::/EFI/BOOT/BOOTAA64.EFI'
		initramfs: '::/boot/initramfs.tar'
	} {
		result := native(['mtype', '-i', image, member], os.environ())!
		assert result.stdout == os.read_file(path)!
	}
	mut failed := false
	imagehost.build(root, image, initramfs, os.environ()) or {
		failed = true
		u64(0)
	}
	assert failed
	os.write_file(kernel, '')!
	os.write_file(initramfs, '')!
	image = work + '/empty.img'
	assert imagehost.build(root, image, initramfs, os.environ())! == 128
	os.mkdir(work + '/sdk')!
	for name in ['mformat', 'mmd', 'mcopy'] { os.symlink(os.executable(), work + '/sdk/' + name)! }
	for mode in ['failure', 'race', 'interrupt', 'missing-tools', 'missing-input', 'broken-output-link'] {
		case := work + '/' + mode
		os.mkdir(case)!
		mut environment := os.environ()
		environment['PATH'] = if mode == 'missing-tools' { case } else { work + '/sdk' }
		environment['VINIX_IMAGE_CASE'] = mode
		environment['VINIX_IMAGE_WORK'] = case
		if mode == 'broken-output-link' { os.symlink(case + '/missing', case + '/image')! }
		guard := cachecli.own_commands()
		if mode == 'interrupt' {
			sender := spawn send_signal(case)
			failed = false
			imagehost.build(root, case + '/image', initramfs, environment) or {
				failed = true
				u64(0)
			}
			assert failed && cachecli.cancelled()
			sender.wait()
			pid := os.read_file(case + '/child.pid')!.int()
			assert C.kill(i32(pid), 0) != 0 && C.errno == C.ESRCH
		} else {
			failed = false
			imagehost.build(root, case + '/image', if mode == 'missing-input' {
				case + '/missing'
			} else {
				initramfs
			}, environment) or {
				failed = true
				u64(0)
			}
			assert failed, mode
		}
		guard.close()
		assert os.ls(case)!.all(it in ['image', 'child.pid']), mode
		assert os.ls(work + '/tmp')!.len == 0 && os.ls('/dev/fd')!.len == baseline, mode
		if mode == 'race' {
			assert os.read_file(case + '/image')! == 'concurrent owner'
		}
	}
	println('PASS two actual FAT32 images, exact boot members, umask, publication race, failures and signal retirement')
}

fn run() ! {
	if mocked()! { return }
	if os.args.len != 2 || os.exists(os.args[1]) { return error('expected new evidence directory') }
	math_cases()!
	image_cases(os.args[1])!
	os.write_file(os.args[1] + '/passed', 'PASS\n')!
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	run() or {
		eprintln(err)
		exit(1)
	}
}
