// SPDX-License-Identifier: GPL-2.0-or-later
module campaignhost

import comparecore
import coreboot
import guesthost
import hosttest
import json2
import os
import sourcecommand

pub fn arm_verdict(raw []u8, done bool, socket bool) map[string]json2.Any {
	output := guesthost.replacement_text(raw)
	markers := comparecore.lines(output).filter(if socket { it.starts_with('ARM-SOCKET') || it.starts_with('QEMU CORE') } else { it.starts_with('UALLOC-') })
	passed := done && if socket {
		output.contains('ARM-SOCKET-DONE result=0') && !output.contains('KERNEL PANIC')
	} else {
		output.count('UALLOC-DONE checks=') == 4 && output.count('UALLOC-ARM-PASS program=') == 9 && output.count('UALLOC-SUPPLEMENT-DONE checks=') == 4 && output.count('UALLOC-ALL-CLASSES ') == 4 && output.count('UALLOC-THREAD-TRANSITIONS ') == 4 && output.contains('CLOCK-DONE') && !['UALLOC-FAIL', 'UALLOC-ARM-FAIL', 'CLOCK-FAIL', 'KERNEL PANIC'].any(output.contains(it))
	}
	mut record := map[string]json2.Any{'passed': json2.Any(passed), 'completed_cases': json2.Any(u64(output.count('UALLOC-DONE checks='))), 'markers': json2.Any(markers.map(json2.Any(it)))}
	if !socket { record['supplemental_cases'] = u64(output.count('UALLOC-SUPPLEMENT-DONE checks=')) }
	return record
}

pub fn run_arm_saved(context Context, version string, socket bool) !int {
	if version !in ['v4', 'v5', 'v6'] { return error('invalid saved ARM version') }
	source := context.root + '/third_party/useralloc-vm-next'
	state := if context.state == os.dir(context.origin) {
		context.root + '/build/' + if socket { 'useralloc-arm-socket-baseline-v3' } else { 'useralloc-arm-' + version + '-final' }
	} else { context.state }
	kernel := if socket { context.root + '/third_party/useralloc-audit-baseline-v3/kernel' } else { state + '/kernel' }
	mut env := os.environ()
	for key, value in {'VINIX_INITRAMFS': state + '/initramfs.tar', 'VINIX_KERNEL_DIR': kernel, 'VINIX_BOOT_DISK': state + '/boot.img', 'VINIX_BOOT_DISK_SIZE_MB': '128', 'VINIX_EFIVARS': state + '/vars.fd', 'VINIX_QEMU_PACKAGE_STORE': state + '/packages.tar', 'VINIX_QEMU_PERSIST': '0', 'VINIX_QEMU_HOST_SOURCE': '0', 'VINIX_QEMU_AUDIO': 'off', 'VINIX_QEMU_SMP': '2', 'VINIX_KEEP_TEMP_BOOT_DISK': '1', 'USE_TCG': '0'} { env[key] = value }
	mut environment := map[string]string{}
	for key, value in env { if key.starts_with('VINIX_') || key == 'USE_TCG' { environment[key] = value } }
	original := [source + if version == 'v6' { '/run-aarch64.sh' } else { '/scripts/run-aarch64.sh' }, '--no-build', '--serial', '--mem=2048', '--guest-init=' + state + '/rootfs/sbin/init', '--no-persist']
	mut manifest := map[string]json2.Any{'command': json2.Any(original.map(json2.Any(it))), 'environment': json2.Any(hosttest.string_map(environment)), 'kernel_sha256': json2.Any(digest(kernel + '/bin/vinix')!), 'initramfs_sha256': json2.Any(digest(state + '/initramfs.tar')!)}
	write_json(state + '/run.json', manifest)!
	temporary := sourcecommand.temporary('vinix-saved-arm')!
	defer { hosttest.remove_work_dir(temporary) or {} }
	compiler := captured(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'find-v', hosttest.root()])!
	arch := $if amd64 { 'amd64' } $else { 'arm64' }
	captured([compiler, '-nocache', '-cc', 'cc', '-arch', arch, '-o', temporary + '/console', hosttest.root() + '/tests/native-campaign-tools/console-main.v'])!
	// Preserve the historical missing scripts path. An explicitly prepared
	// modern tree remains runnable; it must use native host services.
	mut command := original.clone()
	mut adapter := ''
	defer { if adapter != '' { coreboot.remove(adapter) or {} } }
	if os.is_file(command[0]) {
		body := text(command[0])!
		if body.contains('python3') {
			captured([compiler, '-nocache', '-cc', 'cc', '-arch', arch, '-o', temporary + '/packages', hosttest.root() + '/tools/qemu-package-store.v'])!
			translated := coreboot.translated(body, source, temporary + '/packages')!
			adapter = hosttest.work_dir('', 'vinix-arm-adapter')!
			os.write_file(adapter + '/run-aarch64.sh', translated)!
			os.chmod(adapter + '/run-aarch64.sh', 0o755)!
			command[0] = adapter + '/run-aarch64.sh'
		}
	}
	marker := if socket { 'ARM-SOCKET-DONE' } else { 'UALLOC-ARM-DONE' }
	native := [temporary + '/console', state + '/serial.log', temporary + '/capture.json', source, '900', marker, '--', ...command]
	manifest['native_command'] = native.map(json2.Any(it))
	manifest['native_console_sha256'] = digest(temporary + '/console')!
	write_json(state + '/run.json', manifest)!
	status := logged_grace(native, state + '/console.log', env, '', '', 10)!
	if status != 0 { return status }
	capture := read_json(temporary + '/capture.json')!
	raw := os.read_bytes(state + '/serial.log')!
	mut result := arm_verdict(raw, capture['finished']!.bool() && raw.bytestr().contains(marker), socket)
	if version == 'v6' {
		output := guesthost.replacement_text(raw)
		mut strict := result['passed']!.bool()
		for required in ['UALLOC-GROUP-REFILLS requests=18 rounds=129', 'UALLOC-ATFORK-ALLOCATIONS phases=2 forks=8', 'UALLOC-DONE checks=1910', 'UALLOC-SUPPLEMENT-DONE checks=30942'] { if output.count(required) != 4 { strict = false } }
		result['passed'] = strict
	}
	for key, value in result { manifest[key] = value }
	manifest['serial_sha256'] = digest(state + '/serial.log')!
	write_json(state + '/run.json', manifest)!
	for line in result['markers']!.as_array() { println(line.str()) }
	return if result['passed']!.bool() { 0 } else { 1 }
}
