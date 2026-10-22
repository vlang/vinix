// SPDX-License-Identifier: GPL-2.0-or-later
// Boot the literal qualified ISO with only an unmatched QEMU mount tag.
module main

import os
import time

fn command(argv []string) ! {
	mut p := os.new_process(argv[0])
	p.set_args(argv[1..])
	p.run()
	p.wait()
	code := p.code
	p.close()
	if code != 0 { return error('command exit ${code}: ${argv}') }
}

fn qualify(iso string, out string) ! {
	if !os.is_file(iso) || os.exists(out) {
		return error('missing ISO or output directory already exists')
	}
	os.mkdir_all(out + '/share')!
	args := ['qemu-system-x86_64', '-name', 'm16a-bad-tag', '-M', 'q35,smm=off', '-enable-kvm',
		'-cpu', 'host', '-smp', '4', '-m', '2048', '-vga', 'std', '-drive',
		'if=pflash,format=raw,unit=0,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd', '-cdrom',
		iso, '-nic', 'none', '-virtfs',
		'local,path=' + out + '/share,mount_tag=not-share,security_model=mapped-xattr', '-display',
		'none', '-serial', 'file:' + out + '/serial.log', '-qmp',
		'unix:' + out + '/qmp.sock,server=on,wait=off', '-monitor', 'none', '-pidfile',
		out + '/qemu.pid', '-daemonize']
	os.write_file(out + '/qemu-argv.txt', args.join('\n') + '\n')!
	command(args)!
	defer {
		command(['/home/agent/build/vinix-net-rig/qmp', out + '/qmp.sock', 'raw', '{"execute":"quit"}']) or { eprintln('owned guest stop failed: ${err}') }
	}
	deadline := time.sys_mono_now() + u64(90 * time.second)
	for time.sys_mono_now() < deadline {
		serial := os.read_file(out + '/serial.log') or { '' }
		if serial.contains('KERNEL PANIC') || serial.contains('kpanic:') {
			return error('kernel panic')
		}
		if serial.contains('M16A:OUTCOME FAIL status=1') {
			if !serial.contains('M16A:negative-mount PASS case=unknown')
				|| !serial.contains('M16A:FAIL mount share on /mnt: errno=19') {
				return error('unexpected guest failure')
			}
			os.write_file(out + '/receipt.txt', 'BAD_TAG_BOOT:PASS\nEXPORT_TAG:not-share\nREQUESTED_TAG:share\nERRNO:19\nUSERSPACE_REACHED_PARKED_OUTCOME:true\n')!
			println(os.read_file(out + '/receipt.txt')!)
			return
		}
		time.sleep(250 * time.millisecond)
	}
	return error('timeout')
}

fn main() {
	if os.args.len != 3 {
		eprintln('usage: badtag QUALIFIED_ISO NEW_OUTPUT_DIRECTORY')
		exit(2)
	}
	qualify(os.abs_path(os.args[1]), os.abs_path(os.args[2])) or {
		eprintln('BAD_TAG_BOOT:FAIL ${err}')
		exit(1)
	}
}
