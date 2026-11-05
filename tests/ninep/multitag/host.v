// Boot a prepared private ISO containing multitag/guest.v as /init.
// Stop only this controller's QEMU process and check both host exports.
module main

import os
import time

fn qualify(iso string, out string) ! {
	if !os.is_file(iso) || os.exists(out) { return error('need an existing ISO and a new output directory') }
	qemu := os.find_abs_path_of_executable('qemu-system-x86_64')!
	os.mkdir_all(out + '/a')!
	os.mkdir_all(out + '/b')!
	args := ['-M', 'q35,smm=off', '-accel', 'tcg', '-m', '2048', '-smp', '2',
		'-cdrom', iso, '-nic', 'none', '-display', 'none', '-monitor', 'none',
		'-serial', 'file:' + out + '/serial.log', '-no-reboot',
		'-virtfs', 'local,path=' + out + '/a,mount_tag=tag-a,security_model=mapped-xattr',
		'-virtfs', 'local,path=' + out + '/b,mount_tag=tag-b,security_model=mapped-xattr']
	os.write_file(out + '/qemu-argv.txt', qemu + '\n' + args.join('\n') + '\n')!
	mut p := os.new_process(qemu)
	p.set_args(args)
	p.run()
	defer {
		if p.is_alive() { p.signal_kill() }
		p.wait()
		p.close()
	}
	deadline := time.sys_mono_now() + u64(120 * time.second)
	for time.sys_mono_now() < deadline {
		serial := os.read_file(out + '/serial.log') or { '' }
		if serial.contains('G3-MULTITAG:OUTCOME FAIL') || serial.contains('KERNEL PANIC') || serial.contains('kpanic:') {
			return error('guest failed; inspect serial.log')
		}
		if serial.contains('G3-MULTITAG:OUTCOME PASS status=0') {
			for stage in ['two-mounts', 'independent-io', 'unknown-enodev', 'unmount-isolation', 'same-tag-remount'] {
				if !serial.contains('G3-MULTITAG:${stage} PASS') { return error('missing stage ' + stage) }
			}
			if os.read_file(out + '/a/value')! != 'AAA\n' || os.read_file(out + '/b/value')! != 'CCC\n' {
				return error('host export content mismatch')
			}
			os.write_file(out + '/receipt.txt', 'MULTITAG-GUEST-PASS: two exports, independent IO, ENODEV, detach isolation, remount; host contents AAA/CCC\n')!
			println(os.read_file(out + '/receipt.txt')!)
			return
		}
		if !p.is_alive() { return error('QEMU exited before outcome') }
		time.sleep(100 * time.millisecond)
	}
	return error('guest timeout')
}

fn main() {
	if os.args.len != 3 { eprintln('usage: host PREPARED_MULTITAG_ISO NEW_OUTPUT_DIRECTORY'); exit(2) }
	qualify(os.abs_path(os.args[1]), os.abs_path(os.args[2])) or { eprintln(err); exit(1) }
}
