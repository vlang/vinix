// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import androidhost as ah
import cachecli
import gamehost
import os
import runtimehost
import sourcecommand
import strconv

fn counter_text() string {
	return '100 frames rendered in 2.0 seconds = 50.0 fps\nDHEWM3-ELAPSED ns=2100000000 status=0\n100 frames rendered in 1.0 seconds = 100.0 fps\nDHEWM3-ELAPSED ns=1100000000 status=0\n100 frames rendered in 1.25 seconds = 80.0 fps\nDHEWM3-ELAPSED ns=1350000000 status=0\n100 frames rendered in 1.1 seconds = 90.0 fps\nDHEWM3-ELAPSED ns=1200000000 status=0\nDHEWM3-DONE\n'
}

fn numeric(value ah.Value) f64 { return strconv.atof64(ah.encode(value)) or { panic(err) } }

fn result_cases(work string) ! {
	options := runtimehost.DoomOptions{ work: work, selected: 'vinix' }
	result := runtimehost.doom_result(gamehost.Tools{}, options, counter_text(), 'vinix')!.object()
	assert ah.field(result, 'os').text() == 'vinix' && numeric(ah.field(result, 'median_fps')) == 90
	runs := ah.field(result, 'runs').items()
	assert runs.len == 3
	assert numeric(ah.field(runs[0].object(), 'process_seconds')) == 1.1
	assert numeric(ah.field(ah.field(result, 'warmup').object(), 'fps')) == 50
	for transcript in [
		counter_text().replace('100 frames', '101 frames').replace_once('101 frames', '100 frames'),
		counter_text().replace_once('DHEWM3-ELAPSED ns=1100000000 status=0', 'missing counter'),
		counter_text().replace('DHEWM3-DONE', 'DHEWM3-FAILED'),
	] {
		mut refused := false
		runtimehost.doom_result(gamehost.Tools{}, options, transcript, 'vinix') or { refused = true }
		assert refused
	}
	clock := runtimehost.DoomOptions{ work: work, clock_only: true }
	assert ah.field(runtimehost.doom_result(gamehost.Tools{}, clock, 'DHEWM3-DONE', 'debian')!.object(), 'clock_probe').text() == 'passed'
}

fn cpio_cases(work string) ! {
	root := work + '/cpio-root'
	gamehost.mkdir(root + '/bin')!
	os.write_file(root + '/bin/program', 'cpio payload')!
	os.chmod(root + '/bin/program', 0o751)!
	assert C.link((root + '/bin/program').str, (root + '/bin/hard').str) == 0
	os.symlink('program', root + '/bin/link')!
	archive := work + '/initrd.cpio'
	runtimehost.cpio(root, archive)!
	bytes := os.read_bytes(archive)!
	assert bytes.len % 512 == 0 && bytes[..6].bytestr() == '070701'
	extracted := work + '/cpio-extracted'
	gamehost.mkdir(extracted)!
	result := gamehost.Tools{}.output(['tar', '-xf', archive, '-C', extracted])!
	assert result == ''
	assert os.read_file(extracted + '/bin/program')! == 'cpio payload'
	assert os.read_file(extracted + '/bin/hard')! == 'cpio payload'
	assert os.stat(extracted + '/bin/hard')!.inode == os.stat(extracted + '/bin/program')!.inode
	assert os.readlink(extracted + '/bin/link')! == 'program'
	assert os.stat(extracted + '/bin/program')!.mode & 0o7777 == 0o751
}

fn compile_fixture(argv []string, _ bool, _ voidptr) !sourcecommand.Output {
	assert argv[0] == 'aarch64-linux-musl-gcc' && argv[1..5] == ['-O2', '-Wall', '-Wextra', '-static']
	assert argv[6] == '-o'
	os.write_file(argv[7], 'static helper')!
	return sourcecommand.Output{}
}

fn prepare_cases(root string, work string) ! {
	repo := work + '/repo'
	build := work + '/build'
	for directory in [build + '/staging/usr/bin', build + '/staging/lib', build + '/staging/usr/lib',
		repo + '/build-aarch64-x11/staging/usr/bin', repo + '/build-aarch64-userland/staging/bin',
		repo + '/build-aarch64-userland/staging/lib'] {
		gamehost.mkdir(directory)!
	}
	os.write_file(repo + '/build-aarch64-userland/staging/bin/busybox', 'busybox')!
	os.write_file(repo + '/build-aarch64-userland/staging/lib/ld-musl-aarch64.so.1', 'musl')!
	os.symlink('old', build + '/staging/lib/ld-musl-aarch64.so.1')!
	os.write_file(build + '/staging/usr/bin/dhewm3', 'engine')!
	options := runtimehost.DoomOptions{ repo: repo, build: build, work: work, selected: 'vinix', record: true }
	tools := gamehost.Tools{ root: root, command_hook: compile_fixture }
	private := runtimehost.prepare_doom(tools, options)!
	assert os.readlink(private + '/bin/sh')! == 'busybox'
	assert !os.is_link(private + '/lib/ld-musl-aarch64.so.1')
	assert os.read_file(private + '/lib/ld-musl-aarch64.so.1')! == 'musl'
	assert os.read_file(private + '/opt/dhewm3/config')! == 'MODE=record\nROUNDS=3\nCHECK_CLOCK=0\n'
	os.write_file(private + '/retained', 'retained')!
	runtimehost.prepare_doom(tools, options)!
	assert os.read_file(private + '/retained')! == 'retained'
	vinix := runtimehost.doom_plan(options, private, 'vinix')!
	assert vinix.command == [repo + '/scripts/run-aarch64.sh', '--no-build', '--serial', '--no-persist',
		'--mem=8192']
	assert vinix.environment['VINIX_INITRAMFS_COMPRESSED'] == '0' && vinix.environment['VINIX_QEMU_AUDIO'] == 'off'
	debian_root := work + '/debian'
	gamehost.mkdir(debian_root + '/usr/bin')!
	os.write_file(debian_root + '/usr/bin/busybox', 'Debian busybox')!
	linux_options := runtimehost.DoomOptions{ repo: repo, build: build, work: work, selected: 'debian', debian_root: debian_root, debian_kernel: 'private-kernel', record: true }
	linux_plan := runtimehost.doom_plan(linux_options, private, 'debian')!
	assert linux_plan.command[1..9] == ['-machine', 'virt,gic-version=3', '-accel', 'hvf', '-cpu',
		'host', '-smp', '4']
	assert 'private-kernel' in linux_plan.command && work + '/initrd.cpio' in linux_plan.command
	assert os.readlink(work + '/debian-root/init')! == 'sbin/init'
	assert os.read_file(work + '/debian-root/bin/busybox')! == 'Debian busybox'
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.args.len != 2 { exit(2) }
	root := os.real_path(os.dir(@FILE) + '/../..')
	work := os.args[1]
	gamehost.mkdir(work) or { panic(err) }
	result_cases(work) or {
		eprintln(err)
		exit(1)
	}
	cpio_cases(work) or {
		eprintln(err)
		exit(1)
	}
	prepare_cases(root, work) or {
		eprintln(err)
		exit(1)
	}
	os.write_file(work + '/passed', 'PASS\n') or { panic(err) }
	eprintln('NATIVE DHEWM / warmup and independent counter/median assertions, incomplete/failure guards, real newc extraction and hard links, prepare/rerun, exact ARM helper and both boot plans: PASS')
}
