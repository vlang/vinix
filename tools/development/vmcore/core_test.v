// SPDX-License-Identifier: GPL-2.0-or-later
module vmcore

import devcore
import json2
import os
import sourcecommand
import time

fn test_vm_arguments_keep_acceleration_and_permissions_explicit() {
	config := Config{
		architecture:     'aarch64'
		accelerator:      'kvm'
		memory_mib:       8192
		cpus:             8
		network:          true
		ssh_port:         2222
		shared_directory: '/home/developer/shared files'
		guest_agent:      true
	}
	args := arguments(config, '/home/developer/vm')!
	assert args[args.index('-accel') + 1] == 'kvm'
	assert args[args.index('-smp') + 1] == '8'
	assert args[args.index('-m') + 1] == '8192'
	assert args.contains('user,id=net,hostfwd=tcp:127.0.0.1:2222-:22')
	assert args.contains('local,id=share,path=/home/developer/shared files,security_model=none,readonly=on')
	assert !args.contains('-enable-kvm') && !args.contains('-daemonize')
	option_path('/tmp/has,comma') or { return }
	assert false
}

fn pin(path string) !devcore.Pin {
	return devcore.Pin{os.real_path(path), devcore.file_hash(path)!}
}

fn test_real_qemu_lifecycle_isolated_state_offline_snapshots_and_locking() {
	qemu := os.find_abs_path_of_executable('qemu-system-aarch64') or {
		println('SKIP: real QEMU lifecycle requires qemu-system-aarch64')
		return
	}
	image_tool := os.find_abs_path_of_executable('qemu-img')!
	io_tool := os.find_abs_path_of_executable('qemu-io')!
	firmware_dir := os.getenv_opt('VINIX_VM_TEST_FIRMWARE') or {
		if os.is_dir('/opt/homebrew/share/qemu') {
			'/opt/homebrew/share/qemu'
		} else {
			'/usr/share/qemu'
		}
	}
	root := '/tmp/vinix-vm-test-${os.getpid()}'
	devcore.fresh_directory(root)!
	defer { os.rmdir_all(root) or {} }
	os.write_file(root + '/raw.img', '\x00'.repeat(1024 * 1024))!
	config := Config{
		architecture:  'aarch64'
		memory_mib:    128
		cpus:          2
		start_paused:  true
		qemu:          pin(qemu)!
		qemu_img:      pin(image_tool)!
		disk:          pin(root + '/raw.img')!
		firmware_code: pin(firmware_dir + '/edk2-aarch64-code.fd')!
		firmware_vars: pin(firmware_dir + '/edk2-arm-vars.fd')!
	}
	state := root + '/vm'
	initialise(json2.encode(config), state)!
	initialise(json2.encode(config), root + '/other')!
	assert (os.stat(state)!.mode & 0o077) == 0
	// Compile the real entry point so the run lock is held by another process.
	build_result := sourcecommand.capture([@VEXE, '-enable-globals', '-gc', 'none', '-cc', 'cc',
		'-o', root + '/vinix-vm', os.dir(os.dir(@FILE)) + '/vm.v'], os.environ(), 120, 65536, unsafe { nil })!
	assert build_result.status == 0, build_result.stderr
	mut owner := os.new_process(root + '/vinix-vm')
	owner.set_args(['start', state])
	owner.set_redirect_stdio()
	owner.run()
	defer {
		control('stop', state) or {}
		owner.wait()
		owner.close()
	}
	deadline := time.sys_mono_now() + u64(30 * time.second)
	for {
		control('status', state) or {
			assert time.sys_mono_now() < deadline, owner.stdout_read() + owner.stderr_read() + (os.read_file(state + '/qemu.log') or { '' })
			time.sleep(20 * time.millisecond)
			continue
		}
		break
	}
	assert !control('status', state)!.as_map()['running']!.bool()
	control('resume', state)!
	assert control('status', state)!.as_map()['running']!.bool()
	control('pause', state)!
	assert !control('status', state)!.as_map()['running']!.bool()
	for command in [['start', state], ['snapshot-create', state, 'live'], ['snapshot-recover', state]] {
		refused := sourcecommand.capture([root + '/vinix-vm', ...command], os.environ(), 10, 4096, unsafe { nil })!
		assert refused.status != 0 && refused.stderr.contains('running'), refused.stderr
	}
	control('stop', state)!
	owner.wait()
	assert owner.code == 0, owner.stdout_read() + owner.stderr_read()
	snapshot('snapshot-create', state, 'baseline')!
	baseline_vars := devcore.file_hash(state + '/vars.fd')!
	write := sourcecommand.capture([io_tool, '-f', 'qcow2', '-c', 'write -P 0x56 0 4096',
		state + '/disk.qcow2'], os.environ(), 10, 4096, unsafe { nil })!
	assert write.status == 0, write.stderr
	os.write_file(state + '/vars.fd', 'changed-vars')!
	snapshot('snapshot-restore', state, 'baseline')!
	assert devcore.file_hash(state + '/vars.fd')! == baseline_vars
	assert devcore.file_hash(root + '/other/vars.fd')! == config.firmware_vars.sha256
	converted := sourcecommand.capture([image_tool, 'convert', '-f', 'qcow2', '-O', 'raw',
		state + '/disk.qcow2', root + '/restored.raw'], os.environ(), 10, 4096, unsafe { nil })!
	assert converted.status == 0, converted.stderr
	assert os.read_bytes(root + '/restored.raw')![..4096].all(it == 0)
	snapshot('snapshot-delete', state, 'baseline')!
	assert !os.exists(state + '/snapshots/baseline.json')
	os.write_file(state + '/snapshot.pending.json', '{}')!
	start(state) or {
		assert err.msg().contains('incomplete')
		return
	}
	assert false
}
