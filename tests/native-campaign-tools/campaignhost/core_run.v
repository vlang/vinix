// SPDX-License-Identifier: GPL-2.0-or-later
module campaignhost

import cachecli
import cachekey
import hosttest
import json2
import os
import sourcecommand
import time

struct CoreWatch {
	context Context
	state string
	mode string
	command []string
}

pub fn create_capture(path string) ! {
	fd := unsafe { C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_CLOEXEC, 0o666) }
	if fd < 0 { return os.error_posix() }
	C.close(fd)
}

pub fn qemu_observations(raw string, state string, mode string, compiled string) ![]string {
	mut result := []string{}
	for line in raw.split_into_lines() {
		if !line.contains('qemu-system-') || !line.contains(if mode == 'aarch64' { state } else { compiled }) { continue }
		words := cachekey.shell_words(line)!
		if words.len >= 3 && os.base(words[2]).starts_with('qemu-system-') { result << line.trim_space() }
	}
	return result
}

fn observe_core(pid int, pointer voidptr) ! {
	context := unsafe { &CoreWatch(pointer) }
	atomic_json(context.state + '/harness-process.json', {
		'pid': json2.Any(u64(pid))
		'parent_pid': json2.Any(u64(os.getpid()))
		'started_utc': json2.Any(now())
		'command': json2.Any(context.command.map(json2.Any(it)))
	})!
	for !sourcecommand.child_exited(pid)! {
		cachecli.checkpoint()!
		output := sourcecommand.capture(['ps', '-axo', 'pid=,ppid=,command='], os.environ(), -1, 64 * 1024 * 1024, cachecli.cancelled)!
		if output.status == 0 {
			observed := qemu_observations(output.stdout, context.state, context.mode, context.context.state + '/core-x86_64')!
			if observed.len > 0 {
				path := context.state + '/qemu-observed.json'
				mut record := if os.is_file(path) { read_json(path)! } else { map[string]json2.Any{'provenance': json2.Any('Live ps capture during the actual frozen harness execution'), 'observations': json2.Any([]json2.Any{})} }
				mut rows := record['observations']!.as_array().clone()
				for line in observed { if !rows.any(it.as_map()['ps']!.str() == line) { rows << json2.Any({'captured_utc': json2.Any(now()), 'ps': json2.Any(line)}) } }
				record['observations'] = rows
				atomic_json(path, record)!
			}
		}
		time.sleep(500 * time.millisecond)
	}
}

pub fn run_core_mode(context Context, mode string, base map[string]json2.Any, image map[string]json2.Any) !map[string]json2.Any {
	if mode !in ['x86_64', 'x86_64-four-level', 'aarch64'] { return error('invalid core mode') }
	state := context.state + '/core-' + mode
	mkdirs(state)!
	if os.is_file(state + '/run.json') {
		manifest := read_json(state + '/run.json')!
		if 'exit_code' in manifest && is_zero(manifest['exit_code']!) {
			checked_hash(state + '/serial.log', manifest['serial_sha256']!.str())!
			result := core_validate(context, state, mode, manifest)!
			core_checkpoint(context, 'mode_already_passed', mode, {})!
			return result
		}
		if 'exit_code' in manifest { return error('Prior invalid completed run retained at ' + state + '; choose a new attempt directory explicitly, never overwrite') }
		if os.exists(state + '/serial.log') { return error('Incomplete run retained at ' + state + '; choose a new attempt directory explicitly, never overwrite') }
	}
	private := context.root + '/third_party/useralloc-speed-v5'
	harness := private + '/tests/qemu-core/run_vm.py'
	four := context.root + '/build/useralloc-kernel-speed-v5/core-x86_64-four-level/run_vm.py'
	checked_hash(harness, '3f3d4852c58548bc7ade08a1c8f4850c259f592f3816f71d78fda8c45d38eb8c')!
	checked_hash(four, '5f3c543bffefc67219a30d5837042ef6a2a34f9850c0588132878d205792a797')!
	temporary := sourcecommand.temporary('vinix-final-core')!
	defer { hosttest.remove_work_dir(temporary) or {} }
	native := compile_core_harness(temporary, mode == 'aarch64')!
	mut manifest := copy_record(base)!
	manifest['mode'] = mode
	manifest['notes'] = 'Final v6 static musl allocator with the unchanged v5 kernel and immutable full core/pagetable source; SMP2.'
	manifest['started_utc'] = now()
	mut command := []string{}
	mut environment := map[string]string{}
	if mode != 'aarch64' {
		cpu := if mode.ends_with('four-level') { 'max,-la57' } else { 'max' }
		command = [native, private, cpu, '--arch', 'amd64', '--iso', context.state + '/core-x86_64/test.iso', '--qemu', '/opt/homebrew/Cellar/qemu/11.1.1/bin/qemu-system-x86_64', '--firmware', '/opt/homebrew/Cellar/qemu/11.1.1/share/qemu/edk2-x86_64-code.fd', '--timeout', '900', '--cpus', '2']
		manifest['harness_sha256'] = if mode.ends_with('four-level') { '5f3c543bffefc67219a30d5837042ef6a2a34f9850c0588132878d205792a797' } else { '3f3d4852c58548bc7ade08a1c8f4850c259f592f3816f71d78fda8c45d38eb8c' }
		manifest['iso_sha256'] = image['iso_sha256']!
		manifest['embedded_initramfs_sha256'] = image['embedded_initramfs_sha256']!
		manifest['qemu_cpu'] = cpu
		manifest['qemu_accelerator'] = 'tcg'
	} else {
		checked_hash(private + '/kernel/bin/vinix', core_kernel('aarch64')!)!
		command = [native, private, 'max', '--init', state + '/init', '--initramfs', state + '/initramfs.tar', '--state-dir', state + '/vm', '--timeout', '900']
		environment = {'VINIX_KERNEL_DIR': private + '/kernel', 'VINIX_QEMU_CORE_NO_BUILD': '1', 'VINIX_QEMU_HOST_SOURCE': '0', 'VINIX_QEMU_AUDIO': 'off', 'VINIX_QEMU_SMP': '2', 'VINIX_BOOT_DISK_SIZE_MB': '128', 'USE_TCG': '0', 'VINIX_CAMPAIGN_PACKAGE_SERVER': temporary + '/packages'}
		manifest['loader_sha256'] = checked_hash(private + '/boot-image/limine-bin/BOOTAA64.EFI', '0088bfbce37414d13cdbe4c078a13d6b279d727b821e36bbf8044505325e7c02')!
	}
	manifest['run_command'] = command.map(json2.Any(it))
	manifest['run_environment'] = hosttest.string_map(environment)
	manifest['native_harness_sha256'] = digest(native)!
	manifest['native_harness_source_sha256'] = digest(hosttest.root() + '/tests/native-campaign-tools/core-main.v')!
	atomic_json(state + '/run.json', manifest)!
	core_checkpoint(context, 'running_mode', mode, {'run_path': json2.Any(state + '/run.json')})!
	// Preserve exclusive capture creation before starting any harness child.
	if os.exists(state + '/serial.log') || os.is_link(state + '/serial.log') { return error('core serial capture already exists') }
	create_capture(state + '/serial.log')!
	mut env := os.environ()
	for key, value in environment { env[key] = value }
	watch := CoreWatch{context, state, mode, command}
	output := sourcecommand.run_logged_owned(command, env, cachecli.cancelled, state + '/serial.log', false, context.root, observe_core, unsafe { &watch }, 10)!
	manifest['harness_exit_code'] = output.status
	manifest['finished_utc'] = now()
	manifest['serial_sha256'] = digest(state + '/serial.log')!
	mut validated := core_validate(context, state, mode, manifest) or {
		manifest['exit_code'] = if output.status == 0 { 1 } else { output.status }
		manifest['validation_error'] = err.msg()
		atomic_json(state + '/run.json', manifest)!
		atomic_json(state + '/exit.json', {'exit_code': manifest['exit_code']!, 'finished_utc': manifest['finished_utc']!})!
		return error(mode + ' failed: ' + err.msg())
	}
	validated['exit_code'] = output.status
	atomic_json(state + '/run.json', validated)!
	atomic_json(state + '/exit.json', {'exit_code': validated['exit_code']!, 'finished_utc': validated['finished_utc']!})!
	core_checkpoint(context, 'mode_passed', mode, {'run_path': json2.Any(state + '/run.json')})!
	return validated
}

fn core_driver_body(context Context) !int {
	os.write_file(context.state + '/driver.pid', os.getpid().str() + '\n')!
	core_checkpoint(context, 'checking_pins', '', {})!
	checked_hash(context.root + '/build-support/musl/malloc-retain.patch', core_patch)!
	for arch in ['x86_64', 'aarch64'] { checked_hash(context.root + '/build/useralloc-kernel-speed-v5/' + arch + '/vinix-' + arch, core_kernel(arch)!)! }
	checked_hash(context.root + '/third_party/useralloc-speed-v5/tests/qemu-core/run_vm.py', '3f3d4852c58548bc7ade08a1c8f4850c259f592f3816f71d78fda8c45d38eb8c')!
	checked_hash(context.root + '/build/useralloc-kernel-speed-v5/core-x86_64-four-level/run_vm.py', '5f3c543bffefc67219a30d5837042ef6a2a34f9850c0588132878d205792a797')!
	core_checkpoint(context, 'compiling_static_v6', '', {})!
	x86 := compile_core(context, 'x86_64')!
	arm := compile_core(context, 'aarch64')!
	core_checkpoint(context, 'building_frozen_x86_iso', '', {})!
	image := core_image(context, x86)!
	mut results := map[string]json2.Any{}
	for mode in ['x86_64', 'x86_64-four-level', 'aarch64'] {
		base := if mode == 'aarch64' { arm } else { x86 }
		manifest := run_core_mode(context, mode, base, image)!
		mut result := map[string]json2.Any{}
		for key in ['exit_code', 'serial_sha256', 'started_utc', 'finished_utc', 'boundary_supplement_pass', 'all_core_markers_pass', 'pagetable_check_pass_count', 'static_libc_sha256', 'init_sha256', 'kernel_sha256', 'archive_linkage_verified', 'static_elf_verified'] { result[key] = manifest[key]! }
		results[mode] = result
	}
	atomic_json(context.state + '/final-gates.json', {
		'captured_utc': json2.Any(now())
		'allocator_patch_sha256': json2.Any(core_patch)
		'kernels': json2.Any({'x86_64': json2.Any(core_kernel('x86_64')!), 'aarch64': json2.Any(core_kernel('aarch64')!)})
		'test_source_sha256': json2.Any(core_test)
		'boundary_supplement_sha256': json2.Any(core_table)
		'core': json2.Any(results)
		'owned_jobs_running': json2.Any([]json2.Any{})
		'all_three_modes_pass': json2.Any(true)
		'owned_directory': json2.Any(context.state)
		'notes': json2.Any('No kernel rebuilds, tracked changes or benchmarks. Final v6 static archives linked and executed on identical frozen v5 kernels. Completed x86 ISO independently extracted; ARM disk kernel independently extracted.')
	})!
	core_checkpoint(context, 'complete', '', {'final_gates': json2.Any(context.state + '/final-gates.json'), 'owned_jobs_running': json2.Any([]json2.Any{})})!
	atomic_json(context.state + '/exit.json', {'exit_code': json2.Any(0), 'finished_utc': json2.Any(now()), 'owned_jobs_running': json2.Any([]json2.Any{})})!
	println('Final v6 core all three modes PASS')
	flush_stdout()
	return 0
}

pub fn core_driver(context Context) !int {
	return core_driver_body(context) or {
		eprintln(err)
		checkpoint := read_json(context.state + '/checkpoint.json') or { map[string]json2.Any{} }
		active := checkpoint['active_mode'] or { json2.Any(json2.Null{}) }
		core_checkpoint(context, 'failed', if active is string { active } else { '' }, {'error': json2.Any(err.msg())})!
		atomic_json(context.state + '/exit.json', {'exit_code': json2.Any(1), 'finished_utc': json2.Any(now()), 'error': json2.Any(err.msg())})!
		return err
	}
}
