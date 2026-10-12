// SPDX-License-Identifier: GPL-2.0-or-later
module campaignhost

import cachekey
import crypto.sha256
import json2
import os
import strconv

pub fn audited_qemu(observations []json2.Any, mode string) ![]json2.Any {
	mut result := []json2.Any{}
	for item in observations {
		row := item.as_map()
		words := cachekey.shell_words(row['ps']!.str())!
		if words.len < 3 || !os.base(words[2]).starts_with('qemu-system-') { continue }
		pid := strconv.parse_int(words[0], 10, 64)!
		parent := strconv.parse_int(words[1], 10, 64)!
		argv := words[2..].clone()
		for option, wanted in {'-smp': '2', '-accel': if mode == 'aarch64' { 'hvf' } else { 'tcg' }} {
			index := argv.index(option)
			if index < 0 || index + 1 >= argv.len || argv[index + 1] != wanted { return error('observed QEMU policy differs: ' + option) }
		}
		if mode != 'aarch64' {
			index := argv.index('-cpu')
			if index < 0 || index + 1 >= argv.len || argv[index + 1] != if mode.ends_with('four-level') { 'max,-la57' } else { 'max' } { return error('observed QEMU paging policy differs') }
		}
		result << json2.Any({'pid': json2.Any(pid), 'parent_pid': json2.Any(parent), 'argv': json2.Any(argv.map(json2.Any(it))), 'captured_utc': row['captured_utc']!})
	}
	if result.len != if mode == 'aarch64' { 2 } else { 1 } { return error('actual QEMU process count differs') }
	return result
}

pub fn core_evidence_audit(context Context) !int {
	mut audit := map[string]json2.Any{'captured_utc': json2.Any(now())}
	mut modes := map[string]json2.Any{}
	for mode in ['x86_64', 'x86_64-four-level', 'aarch64'] {
		state := context.state + '/core-' + mode
		mut manifest := read_json(state + '/run.json')!
		if !is_zero(manifest['exit_code']!) { return error('completed core mode did not pass: ' + mode) }
		checked_hash(state + '/serial.log', manifest['serial_sha256']!.str())!
		manifest = core_validate(context, state, mode, manifest)!
		compiled := context.state + '/core-' + if mode == 'aarch64' { 'aarch64' } else { 'x86_64' }
		config := read_json(compiled + '/compile.json')!
		exact := read_json(compiled + '/compile-exact-flags.json')!
		if !gate_passed(exact['diagnostic_and_exact_flags_binary_identical']!, json2.Any(true)) || exact['init_sha256']!.str() != config['init_sha256']!.str() { return error('exact original core flags do not reproduce the diagnostic binary') }
		stage := config['stage']!.str()
		checked_hash(stage + '/usr/lib/libc.a', config['static_libc_sha256']!.str())!
		checked_hash(compiled + '/test.c', core_test)!
		checked_hash(compiled + '/pagetable.c', core_table)!
		mut crt := map[string]json2.Any{}
		for path in text(compiled + '/compile.log')!.split_into_lines() {
			if os.base(path).starts_with('crt') && path.ends_with('.o') && os.exists(path) { crt[resolve(path)!] = digest(path)! }
		}
		observed := read_json(state + '/qemu-observed.json')!
		actual := audited_qemu(observed['observations']!.as_array(), mode)!
		manifest['core_source_bundle_sha256_method'] = 'SHA256 of test.c raw bytes followed by pagetable.c raw bytes'
		manifest['previous_v5_bundle_sha256'] = read_json(context.root + '/build/useralloc-kernel-speed-v5/core-' + mode + '/run.json')!['core_source_bundle_sha256']!
		manifest['exact_flags_binary_identical'] = true
		manifest['actual_crt_sha256'] = crt.clone()
		manifest['actual_qemu_argv'] = actual
		if mode == 'aarch64' {
			vm := state + '/vm'
			loader := state + '/embedded-arm-loader'
			runtime := state + '/embedded-arm-runtime.tar'
			base := state + '/embedded-arm-initramfs.tar'
			for target, remote in {loader: '::/EFI/BOOT/BOOTAA64.EFI', runtime: '::/boot/qemu-runtime.tar', base: '::/boot/initramfs.tar'} {
				if !os.exists(target) { checked(['mcopy', '-i', vm + '/boot.img', remote, target], context.root, os.environ(), state + '/embedded-arm-runtime-check.log')! }
			}
			manifest['loader_sha256'] = checked_hash(loader, '0088bfbce37414d13cdbe4c078a13d6b279d727b821e36bbf8044505325e7c02')!
			checked_hash(base, config['initramfs_sha256']!.str())!
			init := archive_bytes(runtime, './sbin/init')!
			init_sha := sha256.sum(init).hex()
			if init_sha != config['init_sha256']!.str() { return error('independent ARM runtime init differs') }
			manifest['embedded_init_sha256'] = init_sha
			manifest['embedded_initramfs_sha256'] = digest(base)!
			manifest['embedded_runtime_sha256'] = digest(runtime)!
			manifest['independent_completed_boot_disk_extraction'] = true
			write_json(state + '/embedded-input-check.json', {
				'kernel_sha256': manifest['embedded_kernel_sha256']!
				'init_sha256': json2.Any(init_sha)
				'loader_sha256': manifest['loader_sha256']!
				'base_initramfs_sha256': json2.Any(digest(base)!)
				'runtime_tar_sha256': json2.Any(digest(runtime)!)
				'boot_disk_sha256': json2.Any(digest(vm + '/boot.img')!)
				'captured_after_actual_second_persistent_boot': json2.Any(true)
				'validated_utc': json2.Any(now())
			})!
		}
		write_json(state + '/run.json', manifest)!
		modes[mode] = json2.Any({
			'exit_code': json2.Any(0)
			'serial_sha256': manifest['serial_sha256']!
			'all_source_core_pass_marker_count': manifest['all_source_core_pass_marker_count']!
			'pagetable_check_pass_count': manifest['pagetable_check_pass_count']!
			'exact_flags_binary_identical': json2.Any(true)
			'actual_qemu_process_count': json2.Any(u64(actual.len))
			'static_archive_sha256': config['static_libc_sha256']!
			'actual_crt_sha256': json2.Any(crt.clone())
			'source_sha256': json2.Any({'test.c': json2.Any(core_test), 'pagetable.c': json2.Any(core_table)})
			'actual_run_command': manifest['run_command']!
		})
	}
	audit['modes'] = modes.clone()
	write_json(context.state + '/evidence-audit.json', audit)!
	mut gates := read_json(context.state + '/final-gates.json')!
	gates['evidence_audit_sha256'] = digest(context.state + '/evidence-audit.json')!
	gates['exact_original_compile_flags_binary_identical'] = true
	gates['all_source_core_markers_pass'] = true
	mut core := gates['core']!.as_map().clone()
	for mode, item in modes {
		mut row := copy_record(core[mode]!.as_map())!
		row['all_source_core_pass_marker_count'] = item.as_map()['all_source_core_pass_marker_count']!
		core[mode] = row.clone()
	}
	gates['core'] = core.clone()
	write_json(context.state + '/final-gates.json', gates)!
	println('Evidence audit PASS: all source markers, exact compile flags, actual processes, final ARM payload pins')
	return 0
}
