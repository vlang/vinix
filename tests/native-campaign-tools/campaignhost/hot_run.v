// SPDX-License-Identifier: GPL-2.0-or-later
module campaignhost

import allocationhost
import cachecli
import guesthost
import hosttest
import json2
import os
import sourcecommand
import time

struct DiagnosticWatch {
	context Context
	ordinal int
mut:
	checkpoint map[string]json2.Any
	record map[string]json2.Any
}

fn diagnostic_update(context Context, mut checkpoint map[string]json2.Any, stage string) ! {
	checkpoint['stage'] = stage
	checkpoint['updated_utc'] = now()
	atomic_json(context.state + '/checkpoint.json', checkpoint)!
}

pub fn diagnostic_boot_verdict(output string) !bool {
	if ['KERNEL PANIC', 'FATAL EXCEPTION', 'DIAG-FAIL', 'ALLOC-ERROR'].any(output.contains(it)) { return error('Guest failure in diagnostic serial log') }
	if !output.contains('DIAG-GUEST-DONE') { return false }
	if output.count('DIAG-SAMPLER-DONE') != 6 || output.count('DIAG-HOT ') != 84 || output.count('exit_code=0') != 6 { return error('Incomplete diagnostic records') }
	return true
}

fn diagnostic_collect(pid int, pointer voidptr) ! {
	mut watch := unsafe { &DiagnosticWatch(pointer) }
	directory := watch.context.state + '/boot-' + watch.ordinal.str()
	os.write_file(directory + '/qemu.pid', pid.str() + '\n')!
	watch.record['qemu_pid'] = pid
	mut boots := watch.checkpoint['boots']!.as_array().clone()
	boots[boots.len - 1] = watch.record.clone()
	watch.checkpoint['boots'] = boots
	diagnostic_update(watch.context, mut watch.checkpoint, 'collect-boot-' + watch.ordinal.str())!
	deadline := time.sys_mono_now() + u64(1800 * time.second)
	mut last_done := 0
	for time.sys_mono_now() < deadline {
		cachecli.checkpoint()!
		bytes := os.read_bytes(directory + '/serial.log') or { []u8{} }
		output := guesthost.replacement_text(bytes)
		done := output.count('DIAG-SAMPLER-DONE')
		if done != last_done {
			println(now() + ' boot ' + watch.ordinal.str() + ' samplers-completed ' + done.str())
			flush_stdout()
			watch.record['samplers_completed'] = done
			boots[boots.len - 1] = watch.record.clone()
			watch.checkpoint['boots'] = boots.clone()
			diagnostic_update(watch.context, mut watch.checkpoint, 'collect-boot-' + watch.ordinal.str())!
			last_done = done
		}
		if diagnostic_boot_verdict(output)! {
			watch.record['status'] = 'complete'
			watch.record['finished_utc'] = now()
			watch.record['raw_log_sha256'] = digest(directory + '/serial.log')!
			boots[boots.len - 1] = watch.record.clone()
			watch.checkpoint['boots'] = boots.clone()
			diagnostic_update(watch.context, mut watch.checkpoint, 'finished-boot-' + watch.ordinal.str())!
			return
		}
		if sourcecommand.child_exited(pid)! { return error('Own QEMU exited') }
		time.sleep(250 * time.millisecond)
	}
	return error('Guest diagnostic timeout')
}

// Observe the final signed status on both success and failure while the SDK
// still reserves the leader's identity. Interrupts cannot skip retirement.
fn diagnostic_observe(pid int, pointer voidptr) ! {
	mut watch := unsafe { &DiagnosticWatch(pointer) }
	mut failure := ''
	diagnostic_collect(pid, pointer) or { failure = err.msg() }
	if !sourcecommand.child_exited(pid)! { C.kill(-pid, C.SIGTERM) }
	until := time.sys_mono_now() + u64(5 * time.second)
	for !sourcecommand.child_exited(pid)! && time.sys_mono_now() < until { time.sleep(20 * time.millisecond) }
	if !sourcecommand.child_exited(pid)! { C.kill(-pid, C.SIGKILL) }
	for !sourcecommand.child_exited(pid)! { time.sleep(20 * time.millisecond) }
	watch.record['qemu_exit_code'] = sourcecommand.child_exit(pid)!.return_code
	if failure != '' { return error(failure) }
}

pub fn diagnostic_boot(context Context, ordinal int, mut checkpoint map[string]json2.Any) ! {
	diagnostic_update(context, mut checkpoint, 'prepare-boot-' + ordinal.str())!
	sysroot := context.root + '/third_party/useralloc-libc/build/useralloc/optimized-v5-final'
	kernel := context.root + '/build/useralloc-kernel-speed-v5/x86_64/vinix-x86_64'
	inputs := {kernel: '16140916ef5abca52cc6f0a8e80bb6dedc24b5e5f05efd747f57182523098e74', sysroot + '/lib/ld-musl-x86_64.so.1': '6cf9e5ead03671c57dc0661e0fc02a675a34a5cf57826a09452001ded8932b03', sysroot + '/usr/lib/libc.a': 'eb50810aa7d3583f6469e23fce4c2f464a86197cfb2a0cdf5293b75baaedd90c', context.state + '/bench.c': 'bd4a0d74f4f1e8d079d55877f8e90925e2622ce990120b54573a5dc94a9a54b9'}
	for path, expected in inputs { checked_hash(path, expected)! }
	directory := context.state + '/boot-' + ordinal.str()
	os.mkdir(directory)!
	mut record := map[string]json2.Any{'ordinal': json2.Any(ordinal), 'state_dir': json2.Any(directory), 'started_utc': json2.Any(now()), 'status': json2.Any('preparing')}
	mut boots := checkpoint['boots']!.as_array().clone()
	boots << json2.Any(record.clone())
	checkpoint['boots'] = boots.clone()
	diagnostic_update(context, mut checkpoint, 'copy-rootfs-' + ordinal.str())!
	rootfs := directory + '/rootfs'
	copy_tree(sysroot, rootfs)!
	for name in ['dev', 'proc', 'sys', 'tmp', 'root', 'sbin'] { mkdirs(rootfs + '/' + name)! }
	os.chmod(rootfs + '/tmp', 0o1777)!
	for mode in ['dynamic', 'static'] { copy_file(context.state + '/sampler-' + mode, rootfs + '/root/sampler-' + mode)!; os.chmod(rootfs + '/root/sampler-' + mode, 0o755)! }
	init := rootfs + '/sbin/init'
	os.rm(init) or { if os.exists(init) || os.is_link(init) { return err } }
	os.write_file(init, $embed_file('hot-init.txt').to_string())!
	os.chmod(init, 0o755)!
	timestamped_archive(rootfs, directory + '/initramfs.tar')!
	iso := directory + '/vinix.iso'
	mut env := os.environ()
	for key, value in {'VINIX_AMD64_ISO_BUILD_DIR': directory + '/iso-build', 'VINIX_AMD64_KERNEL': kernel, 'VINIX_AMD64_INITRAMFS': directory + '/initramfs.tar', 'VINIX_AMD64_ISO': iso} { env[key] = value }
	diagnostic_update(context, mut checkpoint, 'build-iso-' + ordinal.str())!
	checked([context.root + '/build-support/build-amd64-iso.sh'], '', env, directory + '/image-build.log')!
	extract := ['xorriso', '-osirrox', 'on', '-indev', iso, '-extract', '/boot/vinix', directory + '/boot-kernel']
	wait := Wait{started: time.sys_mono_now()}
	extraction := sourcecommand.run_logged_owned(extract, os.environ(), cachecli.cancelled, directory + '/image-build.log', true, '', wait_child, unsafe { &wait }, 0)!
	if extraction.status != 0 { return error('diagnostic ISO extraction failed') }
	checked_hash(directory + '/boot-kernel', inputs[kernel]!)!
	for path, expected in inputs { checked_hash(path, expected)! }
	checked_hash(rootfs + '/lib/ld-musl-x86_64.so.1', inputs[sysroot + '/lib/ld-musl-x86_64.so.1']!)!
	qemu := resolve(os.find_abs_path_of_executable('qemu-system-x86_64')!)!
	firmware := os.dir(os.dir(qemu)) + '/share/qemu/edk2-x86_64-code.fd'
	base := allocationhost.vm_command(qemu, firmware, iso, directory + '/serial.log', .saved_final, 2)
	command := [base[0], '-name', 'Vinix private hot v5 diagnostic ' + ordinal.str(), ...base[1..]]
	versions := captured([qemu, '--version'])!.split_into_lines()
	if versions.len == 0 { return error('QEMU version missing') }
	mut hashes := map[string]json2.Any{}
	for path, _ in inputs { hashes[path] = digest(path)! }
	mut executables := map[string]json2.Any{}
	for mode in ['dynamic', 'static'] { executables[mode] = digest(rootfs + '/root/sampler-' + mode)! }
	atomic_json(directory + '/config.json', {
		'argv': json2.Any(command.map(json2.Any(it)))
		'qemu_version': json2.Any(versions[0])
		'machine': json2.Any(allocationhost.machine)
		'accelerator': json2.Any(allocationhost.accelerator)
		'cpu': json2.Any(allocationhost.cpu)
		'smp': json2.Any('2,sockets=1,cores=2,threads=1')
		'memory_mb': json2.Any(4096)
		'input_sha256': json2.Any(hashes)
		'sampler_sha256': json2.Any(digest(context.state + '/sampler.c')!)
		'executables_sha256': json2.Any(executables)
		'kernel_verification': json2.Any('Extracted completed ISO kernel hash equals immutable v5 kernel.')
		'iterations': json2.Any(200000)
		'samples': json2.Any(7)
		'fresh_execs_per_mode': json2.Any(3)
		'limits': json2.Any('Private state probes run outside unchanged hot loops. Cross GCC executable differs from canonical guest GCC executable. CPU time is kernel accounting, not host process time.')
	})!
	record['status'] = 'booting'
	diagnostic_command(context, ordinal, command, record, mut checkpoint)!
}

// Shared owner path also permits controlled executable qualification without
// changing the production command, guest deadline, or marker policy.
pub fn diagnostic_command(context Context, ordinal int, command []string, record map[string]json2.Any, mut checkpoint map[string]json2.Any) ! {
	directory := context.state + '/boot-' + ordinal.str()
	mut watch := DiagnosticWatch{context: context, ordinal: ordinal, checkpoint: copy_record(checkpoint)!, record: record.clone()}
	mut failure := ''
	result := sourcecommand.run_logged_owned(command, os.environ(), cachecli.cancelled, directory + '/qemu.log', false, '', diagnostic_observe, unsafe { &watch }, 5) or {
		failure = err.msg()
		sourcecommand.Output{status: 1}
	}
	if 'qemu_exit_code' !in watch.record { watch.record['qemu_exit_code'] = result.status }
	watch.record['qemu_stopped_utc'] = now()
	mut boots := watch.checkpoint['boots']!.as_array().clone()
	boots[boots.len - 1] = watch.record.clone()
	watch.checkpoint['boots'] = boots.clone()
	checkpoint = copy_record(watch.checkpoint)!
	diagnostic_update(context, mut checkpoint, 'own-qemu-stopped-' + ordinal.str())!
	if failure != '' { return error(failure) }
}

pub fn run_diagnostic(context Context) !int {
	mut checkpoint := map[string]json2.Any{'started_utc': json2.Any(now()), 'driver_pid': json2.Any(os.getpid()), 'stage': json2.Any('verify-inputs'), 'boots': json2.Any([]json2.Any{})}
	diagnostic_update(context, mut checkpoint, 'started')!
	mut exit_code := 0
	for ordinal in [1, 2] {
		diagnostic_boot(context, ordinal, mut checkpoint) or {
			checkpoint['error'] = err.msg()
			diagnostic_update(context, mut checkpoint, 'failed')!
			eprintln(err)
			exit_code = 1
			break
		}
	}
	if exit_code == 0 { diagnostic_update(context, mut checkpoint, 'complete')! }
	atomic_json(context.state + '/driver.exit.json', {'exit_code': json2.Any(exit_code), 'finished_utc': json2.Any(now()), 'checkpoint': json2.Any(context.state + '/checkpoint.json')})!
	return exit_code
}
