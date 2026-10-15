// SPDX-License-Identifier: GPL-2.0-or-later
module vmcore

import devcore
import json2
import net.unix
import os
import sourcecommand
import time

fn startup_command(args []string) !sourcecommand.Output {
	return sourcecommand.capture(args, os.environ(), 120, 65536, unsafe { nil })
}

fn startup_pin(path string) !devcore.Pin {
	return devcore.Pin{os.real_path(path), devcore.file_hash(path)!}
}

fn startup_wait(mut owner os.Process) ! {
	deadline := time.sys_mono_now() + u64(15 * time.second)
	for owner.is_alive() {
		if time.sys_mono_now() >= deadline { return error('VM manager failed to retire') }
		time.sleep(10 * time.millisecond)
	}
	owner.wait()
}

fn startup_case(root string, state string, kind string) ! {
	for name in ['emulator.ready', 'emulator.release', 'emulator.fail'] {
		if os.exists(root + '/' + name) { os.rm(root + '/' + name)! }
	}
	if kind == 'fail' { os.write_file(root + '/emulator.fail', '')! }
	mut owner := os.new_process(root + '/vinix-vm')
	owner.set_args(['start', state])
	owner.set_redirect_stdio()
	owner.run()
	defer {
		control('stop', state) or {}
		owner.signal_kill()
		owner.wait()
		owner.close()
	}
	deadline := time.sys_mono_now() + u64(30 * time.second)
	for !os.exists(root + '/emulator.ready') {
		assert owner.is_alive(), owner.stdout_read() + owner.stderr_read()
		assert time.sys_mono_now() < deadline, 'emulator fixture did not start'
		time.sleep(10 * time.millisecond)
	}
	assert !os.exists(state + '/qmp.sock') && !os.exists(state + '/agent.sock')
	query := startup_command([root + '/vinix-vm', 'guest-ping', state])!
	assert query.status != 0 && query.stderr.contains('VM startup'), query.stderr
	if kind == 'cancel' { owner.signal_term() }
	else { os.write_file(root + '/emulator.release', '')! }
	if kind == 'ready' {
		for {
			control('status', state) or {
				assert time.sys_mono_now() < deadline, err.msg()
				time.sleep(10 * time.millisecond)
				continue
			}
			break
		}
		for {
			mut channel := guest_lease(state) or {
				assert time.sys_mono_now() < deadline, 'startup must release the channel lease while the VM is running'
				time.sleep(10 * time.millisecond)
				continue
			}
			channel.release()
			break
		}
		assert os.lstat(state + '/agent.sock')!.get_filetype() == .socket
		assert owner.is_alive(), 'releasing the query lease must not retire the live VM'
		control('stop', state)!
	}
	startup_wait(mut owner)!
	assert (owner.code == 0) == (kind == 'ready'), owner.stdout_read() + owner.stderr_read()
	mut channel := guest_lease(state)!
	channel.release()
	mut run := lease(state)!
	run.release()
}

fn test_start_serializes_channel_replacement_and_releases_leases_on_every_exit() {
	qemu := os.find_abs_path_of_executable('qemu-system-aarch64') or {
		println('SKIP: startup channel checks require QEMU')
		return
	}
	image_tool := os.find_abs_path_of_executable('qemu-img')!
	root := '/tmp/vinix-vm-startup-${os.getpid()}'
	devcore.fresh_directory(root)!
	defer { os.rmdir_all(root) or {} }
	os.write_file(root + '/emulator.path', qemu)!
	for binary, source in {'emulator': 'vmfixture/emulator.v', 'vinix-vm': 'vm.v'} {
		build := startup_command([@VEXE, '-enable-globals', '-gc', 'none', '-cc', 'cc',
			'-o', root + '/' + binary, os.dir(os.dir(@FILE)) + '/' + source])!
		assert build.status == 0, build.stderr
	}
	firmware := os.getenv_opt('VINIX_VM_TEST_FIRMWARE') or {
		if os.is_dir('/opt/homebrew/share/qemu') { '/opt/homebrew/share/qemu' } else { '/usr/share/qemu' }
	}
	os.write_file(root + '/raw.img', '\x00'.repeat(1024 * 1024))!
	state := root + '/vm'
	initialise(json2.encode(Config{
		architecture: 'aarch64'
		memory_mib: 128
		cpus: 2
		guest_agent: true
		start_paused: true
		qemu: startup_pin(root + '/emulator')!
		qemu_img: startup_pin(image_tool)!
		disk: startup_pin(root + '/raw.img')!
		firmware_code: startup_pin(firmware + '/edk2-aarch64-code.fd')!
		firmware_vars: startup_pin(firmware + '/edk2-arm-vars.fd')!
	}), state)!
	// Refuse a current query before unlinking either abandoned socket or
	// opening the VM log. Use another process to contend with this record lock.
	for endpoint in ['qmp.sock', 'agent.sock'] {
		mut listener := unix.listen_stream(state + '/' + endpoint)!
		listener.sock.close()!
	}
	qmp_inode := os.lstat(state + '/qmp.sock')!.inode
	agent_inode := os.lstat(state + '/agent.sock')!.inode
	vars := devcore.file_hash(state + '/vars.fd')!
	disk := devcore.file_hash(state + '/disk.qcow2')!
	os.write_file(state + '/qemu.log', 'preserve-log')!
	mut query := guest_lease(state)!
	refused := startup_command([root + '/vinix-vm', 'start', state])!
	assert refused.status != 0 && refused.stderr.contains('guest agent query'), refused.stderr
	assert os.lstat(state + '/qmp.sock')!.inode == qmp_inode
	assert os.lstat(state + '/agent.sock')!.inode == agent_inode
	assert os.read_file(state + '/qemu.log')! == 'preserve-log'
	assert !os.exists(root + '/emulator.ready') && !os.exists(state + '/exit.json')
	assert devcore.file_hash(state + '/vars.fd')! == vars && devcore.file_hash(state + '/disk.qcow2')! == disk
	query.release()
	for kind in ['fail', 'cancel', 'ready'] { startup_case(root, state, kind)! }
	// A spawn error occurs before the startup observer can release the lease.
	os.chmod(root + '/emulator', 0o600)!
	failed := startup_command([root + '/vinix-vm', 'start', state])!
	assert failed.status != 0
	mut channel := guest_lease(state)!
	channel.release()
	mut run := lease(state)!
	run.release()
}
