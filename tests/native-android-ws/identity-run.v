// SPDX-License-Identifier: GPL-2.0-or-later
// Private ARM64 Vinix image; does not alter an active Maps image or runtime.
module main

import crypto.sha256
import json2
import os
import time

fn checked(args []string) ! {
	result := os.exec(args)
	if result.exit_code != 0 { return error(args[0] + ': ' + result.output) }
}

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		count := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if count == 0 { break }
		hash.write(buffer[..count])!
	}
	return hash.sum([]u8{}).hex()
}

fn compile_argv(compiler string, output string) []string {
	return [compiler, '-os', 'linux', '-arch', 'arm64', '-cc', 'aarch64-linux-musl-gcc', '-gc',
		'none', '-path', '@vlib|@vmodules|' + output + '/sources/build-support/android', '-o',
		output + '/module/sbin/init', output + '/sources/tests/native-android-ws/identity-fixture.v']
}

fn qemu_argv(qemu string, firmware string, output string) []string {
	return [qemu, '-machine', 'virt,gic-version=3', '-accel', 'hvf', '-cpu', 'host', '-m', '2048',
		'-smp', '2', '-object', 'rng-random,filename=/dev/urandom,id=vinix-rng', '-device',
		'virtio-rng-device', '-drive', 'if=pflash,format=raw,readonly=on,file=' + firmware, '-drive',
		'if=pflash,format=raw,file=' + output + '/efivars.fd', '-drive',
		'format=raw,file=' + output + '/boot.img', '-device', 'virtio-keyboard-device', '-device',
		'virtio-tablet-device', '-device', 'ramfb', '-netdev', 'user,id=net0', '-device',
		'virtio-net-device,netdev=net0', '-display', 'none', '-monitor', 'none', '-serial',
		'file:' + output + '/serial.log']
}

struct ExecutionReceipt {
	recorded_after_run bool
	scope              string
	compile_argv       []string
	qemu_argv          []string
	tool_sha256        map[string]string
	v_version          string
	cc_version         string
	qemu_version       string
}

fn execution_receipt(output string, compiler string, qemu string, firmware string, after bool) ! {
	mut hashes := map[string]string{}
	for tool in [compiler, 'aarch64-linux-musl-gcc', qemu, firmware] {
		path := if os.is_abs_path(tool) || tool.contains('/') {
			os.abs_path(tool)
		} else {
			os.find_abs_path_of_executable(tool)!
		}
		hashes[path] = digest(path)!
	}
	receipt := ExecutionReceipt{
		recorded_after_run: after
		scope:              if after {
			'Supplemental capture after execution: argv uses the recorder configuration and must be compared with the preserved tested runner; hashes and versions identify tools at capture time, not a historical tool freeze. Original inputs.json and tested source copies remain unchanged.'
		} else {
			'Captured before fixture compilation and QEMU execution.'
		}
		compile_argv:       compile_argv(compiler, output)
		qemu_argv:          qemu_argv(qemu, firmware, output)
		tool_sha256:        hashes
		v_version:          os.exec([compiler, '-version']).output.trim_space()
		cc_version:         os.exec(['aarch64-linux-musl-gcc', '--version']).output.trim_space()
		qemu_version:       os.exec([qemu, '--version']).output.trim_space()
	}
	name := if after { '/execution-supplement.json' } else { '/execution.json' }
	os.write_file(output + name, json2.encode(receipt, prettify: true) + '\n')!
}

fn run() ! {
	$if prod { return error('identity runner requires assertions; compile without -prod') }
	compiler := os.getenv_opt('VINIX_V_COMPILER') or { 'v' }
	qemu_path := os.getenv_opt('VINIX_IDENTITY_QEMU') or { 'build/qemu-horizontal/bin/qemu-system-aarch64' }
	firmware := os.getenv_opt('VINIX_IDENTITY_FIRMWARE') or { '/opt/homebrew/share/qemu/edk2-aarch64-code.fd' }
	if os.args.len == 3 && os.args[1] == '--capture-metadata' {
		output := os.abs_path(os.args[2])
		if !os.is_file(output + '/inputs.json') { return error('missing original inputs.json') }
		if os.exists(output + '/execution-supplement.json') {
			return error('supplement already exists')
		}
		execution_receipt(output, compiler, qemu_path, firmware, true)!
		println('ANDROID-IDENTITY-SUPPLEMENT ' + output + '/execution-supplement.json')
		return
	}
	if os.args.len != 4 {
		return error('usage: identity-run BASE_BOOT_IMAGE BASE_EFIVARS NEW_OUTPUT_DIRECTORY (run from repository root)')
	}
	output := os.abs_path(os.args[3])
	if os.exists(output) { return error('output already exists: ' + output) }
	mut identities := map[string]string{}
	for path in ['build-support/android/nativeidentity/identity.v',
		'tests/native-android-ws/identity-fixture.v', 'tests/native-android-ws/identity-run.v'] {
		frozen := output + '/sources/' + path
		os.mkdir_all(os.dir(frozen))!
		os.cp(path, frozen)!
		identities[path] = digest(frozen)!
	}
	os.mkdir_all(output + '/module/sbin')!
	os.mkdir_all(output + '/module/etc')!
	// Provision only the private guest overlay; never edit the host's account
	// database or allocate accounts inside the production launcher.
	os.write_file(output + '/module/etc/passwd', 'root:x:0:0:root:/root:/bin/sh\nvinix-app:x:10000:10000:Android fixture:/tmp:/bin/false\n')!
	os.write_file(output + '/module/etc/group', 'root:x:0:\nvinix-app:x:10000:\n')!
	os.setenv('COPYFILE_DISABLE', '1', true)
	execution_receipt(output, compiler, qemu_path, firmware, false)!
	checked(compile_argv(compiler, output))!
	os.chmod(output + '/module/sbin/init', 0o755)!
	checked(['cp', '-c', os.abs_path(os.args[1]), output + '/boot.img'])!
	os.cp(os.abs_path(os.args[2]), output + '/efivars.fd')!
	checked(['tar', '--format=ustar', '-cf', output + '/runtime.tar', '-C', output + '/module',
		'.'])!
	checked(['mcopy', '-o', '-i', output + '/boot.img', output + '/runtime.tar',
		'::/boot/qemu-runtime.tar'])!
	for path in [os.abs_path(os.args[1]), os.abs_path(os.args[2])] {
		identities[path] = digest(path)!
	}
	for path in [output + '/module/sbin/init', output + '/runtime.tar'] {
		identities[path] = digest(path)!
	}
	os.write_file(output + '/inputs.json', json2.encode(identities, prettify: true) + '\n')!
	mut qemu := os.new_process(qemu_path)
	qemu.set_args(qemu_argv(qemu_path, firmware, output)[1..])
	qemu.run()
	defer {
		if qemu.is_alive() { qemu.signal_term() }
		qemu.wait()
	}
	println('ANDROID-IDENTITY-VM started private_image=' + output + '/boot.img')
	deadline := time.now().unix() + 120
	for time.now().unix() < deadline {
		serial := os.read_file(output + '/serial.log') or { '' }
		if serial.contains('ANDROID-IDENTITY-SUITE PASS cases=18') {
			assert serial.count('ANDROID-IDENTITY-DISABLED PASS ') == 1
			assert serial.count('ANDROID-IDENTITY-SCHED PASS ') == 3
			assert serial.count('ANDROID-IDENTITY-EXEC PASS ') == 3
			assert serial.count('ANDROID-IDENTITY-REJECT ') == 15
			if qemu.is_alive() { qemu.signal_term() }
			qemu.wait()
			os.write_file(output + '/result.txt', 'PASS cases=18\nserial_sha256=' + digest(output + '/serial.log')! + '\n')!
			println('ANDROID-IDENTITY-VM PASS cases=18 evidence=' + output)
			return
		}
		if serial.contains('ANDROID-IDENTITY-SUITE FAIL') || !qemu.is_alive() {
			return error('identity VM failed; inspect ' + output + '/serial.log')
		}
		time.sleep(200 * time.millisecond)
	}
	return error('identity VM timed out; inspect ' + output + '/serial.log')
}

fn main() {
	run() or {
		eprintln('ANDROID-IDENTITY-VM FAIL ${err}')
		exit(1)
	}
}
