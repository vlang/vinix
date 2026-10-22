@[has_globals]
module main

import crypto.sha256
import guesthost
import json2
import os
import perfconsole
import perfrunner

fn digest_file(path string) string {
	return sha256.sum(os.read_bytes(path) or { panic(err) }).hex()
}

fn main() {
	area := '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
	root := '/Users/alex/code/vinix'
	work := area + '/dt'
	kernel := os.args[1]
	if os.exists(work) { panic('fresh desktop state required') }
	os.mkdir_all(work + '/kernel/bin')!
	os.cp(kernel + '/bin/vinix', work + '/kernel/bin/vinix')!
	os.mkdir_all(work + '/overlay/opt/vinix-perf')!
	os.mkdir_all(work + '/overlay/sbin')!
	base := root + '/build-amd64-desktop/initramfs-desktop.tar'
	desktop := root + '/logs/desktop-ram-fix/vinix-desktop-amd64'
	os.cp(desktop, work + '/overlay/opt/vinix-perf/vinix-desktop-new')!
	original_init := os.read_file(root + '/tests/desktop-perf/perf-init.sh')!
	os.write_file(work + '/overlay/sbin/init', original_init.replace('#!/bin/sh', '#!/bin/sh\nexec >/dev/com1 2>&1'))!
	os.mkdir_all(work + '/overlay/usr/bin')!
	os.symlink('vinix-desktop', work + '/overlay/usr/bin/vinix-activity-monitor')!
	os.chmod(work + '/overlay/sbin/init', 0o755)!
	guard := perfconsole.own_commands()
	defer { guard.close() }
	perfrunner.command(['x86_64-linux-musl-gcc', '-static', '-O2', '-Wall', root + '/tests/desktop-perf/measure.c', '-o', work + '/overlay/opt/vinix-perf/measure']) or { panic(err) }
	os.write_file(work + '/overlay/opt/vinix-perf/config', "VARIANTS='new'\nSCENARIOS='drag'\nROUNDS=1\nSETTLE=5\nMEASURE=10\nDESKTOP_ARGS='--stats'\n")!
	archive := work + '/initramfs.tar'
	perfrunner.command(['cp', '-c', base, archive]) or { panic(err) }
	os.setenv('COPYFILE_DISABLE', '1', true)
	perfrunner.command(['tar', '--format=ustar', '-rf', archive, '-C', work + '/overlay', '.']) or { panic(err) }
	os.mkdir_all(work + '/vm')!
	launch := guesthost.launch_from(work + '/overlay/sbin/init', archive, work + '/vm', work + '/kernel', 'x86_64', true, area + '/desktop-x86-launch') or { panic(err) }
	mut command := launch.command.clone()
	for at in 0 .. command.len - 1 {
		if command[at] == '-m' { command[at + 1] = '4096' }
		if command[at] == '-smp' { command[at + 1] = '4' }
	}
	command << ['-vga', 'std', '-usb', '-device', 'usb-tablet']
	os.write_file(work + '/receipt.json', json2.encode({
		'architecture': 'x86_64'
		'kernel_sha256': digest_file(work + '/kernel/bin/vinix')
		'base_sha256': digest_file(base)
		'desktop_sha256': digest_file(work + '/overlay/opt/vinix-perf/vinix-desktop-new')
		'desktop_source_sha256': digest_file(root + '/logs/desktop-ram-fix/source.tar')
		'init_source_sha256': digest_file(root + '/tests/desktop-perf/perf-init.sh')
		'init_sha256': digest_file(work + '/overlay/sbin/init')
		'measure_source_sha256': digest_file(root + '/tests/desktop-perf/measure.c')
		'measure_sha256': digest_file(work + '/overlay/opt/vinix-perf/measure')
		'archive_sha256': digest_file(archive)
		'iso_sha256': digest_file(work + '/vm/test.iso')
		'command': command.join(' ')
	}, prettify: true) + '\n')!
	plan := perfrunner.parse(['new=' + desktop, '--scenarios=drag', '--rounds=1', '--settle=5', '--seconds=10', '--mem=4096', '--timeout=2400', '--desktop-args=--stats', '--json=' + work + '/results.json', '--shots=' + work + '/shots'], root, root + '/tests/desktop-perf', '') or { panic(err) }
	status := perfrunner.drive(plan, perfrunner.Launch{command, launch.env, work + '/vm/qmp.sock'}, work, 10, true) or {
		eprintln(err)
		1
	}
	os.write_file(work + '/status', status.str() + '\n') or { panic(err) }
	exit(status)
}
