// SPDX-License-Identifier: GPL-2.0-or-later
module campaignhost

import comparecore
import coreboot
import guesthost
import hosttest
import json2
import os
import sourcecommand

pub fn socket_footer(kind string) string {
	return if kind == 'recvmsg' { 'ARM-SOCKET-DONE result=0' } else if kind == 'settlement' { 'SOCKET-OPS-DONE result=0 completed=5' } else { 'SOCKET-OPS-DONE result=0 completed=17' }
}

pub fn socket_probe_verdict(raw []u8, done bool, kind string) map[string]json2.Any {
	output := guesthost.replacement_text(raw)
	markers := comparecore.lines(output).filter(it.starts_with('ARM-SOCKET') || it.starts_with('QEMU CORE') || it.starts_with('SOCKET-OPS'))
	passed := done && raw.bytestr().contains(socket_footer(kind)) && !['KERNEL PANIC', 'SOCKET-OPS-FAIL', 'QEMU CORE FAIL'].any(raw.bytestr().contains(it))
	return {'passed': json2.Any(passed), 'markers': json2.Any(markers.map(json2.Any(it)))}
}

pub fn run_socket_probe(context Context, kind string, kernel string) !int {
	source := context.root + '/third_party/useralloc-vm-next'
	mut environment := os.environ()
	for key, value in {
		'VINIX_INITRAMFS': context.state + '/initramfs.tar'
		'VINIX_KERNEL_DIR': kernel
		'VINIX_BOOT_DISK': context.state + '/boot.img'
		'VINIX_BOOT_DISK_SIZE_MB': '128'
		'VINIX_EFIVARS': context.state + '/vars.fd'
		'VINIX_QEMU_PACKAGE_STORE': context.state + '/packages.tar'
		'VINIX_QEMU_PERSIST': '0'
		'VINIX_QEMU_HOST_SOURCE': '0'
		'VINIX_QEMU_AUDIO': 'off'
		'VINIX_QEMU_SMP': '2'
		'VINIX_KEEP_TEMP_BOOT_DISK': '1'
		'USE_TCG': '0'
	} { environment[key] = value }
	mut recorded_env := map[string]json2.Any{}
	for key, value in environment { if key.starts_with('VINIX_') || key == 'USE_TCG' { recorded_env[key] = value } }
	original := [source + '/run-aarch64.sh', '--no-build', '--serial', '--mem=2048', '--guest-init=' + context.state + '/rootfs/sbin/init', '--no-persist']
	mut manifest := map[string]json2.Any{
		'command': json2.Any(original.map(json2.Any(it)))
		'environment': json2.Any(recorded_env)
		'kernel_sha256': json2.Any(digest(kernel + '/bin/vinix')!)
		'initramfs_sha256': json2.Any(digest(context.state + '/initramfs.tar')!)
		'started_utc': json2.Any(now())
	}
	write_json(context.state + '/run.json', manifest)!
	temporary := sourcecommand.temporary('vinix-socket-probe')!
	defer { hosttest.remove_work_dir(temporary) or {} }
	compiler := captured(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'find-v', hosttest.root()])!
	arch := $if amd64 { 'amd64' } $else { 'arm64' }
	captured([compiler, '-nocache', '-cc', 'cc', '-arch', arch, '-o', temporary + '/console', hosttest.root() + '/tests/native-campaign-tools/console-main.v'])!
	mut command := original.clone()
	mut adapter := ''
	defer { if adapter != '' { coreboot.remove(adapter) or {} } }
	if os.is_file(command[0]) && text(command[0])!.contains('python3') {
		captured([compiler, '-nocache', '-cc', 'cc', '-arch', arch, '-o', temporary + '/packages', hosttest.root() + '/tools/qemu-package-store.v'])!
		body := coreboot.translated(text(command[0])!, source, temporary + '/packages')!
		adapter = hosttest.work_dir('', 'vinix-socket-adapter')!
		os.write_file(adapter + '/run-aarch64.sh', body)!
		os.chmod(adapter + '/run-aarch64.sh', 0o755)!
		command[0] = adapter + '/run-aarch64.sh'
	}
	native := [temporary + '/console', '--probe', context.state + '/serial.log', temporary + '/capture.json', source, '900', socket_footer(kind), '--', ...command]
	manifest['native_command'] = native.map(json2.Any(it))
	manifest['native_console_sha256'] = digest(temporary + '/console')!
	write_json(context.state + '/run.json', manifest)!
	status := logged_grace(native, context.state + '/console.log', environment, '', '', 12)!
	if status != 0 { return status }
	capture := read_json(temporary + '/capture.json')!
	result := socket_probe_verdict(os.read_bytes(context.state + '/serial.log')!, capture['finished']!.bool(), kind)
	for key, value in result { manifest[key] = value }
	manifest['serial_sha256'] = digest(context.state + '/serial.log')!
	manifest['actual_qemu_ps'] = capture['actual_qemu_ps']!
	manifest['finished_utc'] = now()
	write_json(context.state + '/run.json', manifest)!
	for line in result['markers']!.as_array() { println(line.str()); flush_stdout() }
	return if result['passed']!.bool() { 0 } else { 1 }
}
