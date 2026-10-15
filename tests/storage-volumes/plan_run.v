// SPDX-License-Identifier: GPL-2.0-or-later
// Native V qualification controller. QEMU runs directly; no Python transport.
module main

import os
import time
import encoding.hex
import bootcapture

#include <signal.h>
fn C.kill(i32, i32) i32
fn C.ftruncate(i32, u64) i32

// os.truncate opens with O_TRUNC. Keep the existing prefix of this disposable
// backing file by resizing its retained writable descriptor instead.
fn shrink_disk(path string, length u64) ! {
	mut disk := os.open_file(path, 'r+')!
	defer { disk.close() }
	if C.ftruncate(disk.fd, length) != 0 { return error('Cannot contract disposable backing disk') }
}

fn command(args []string) !string {
	result := os.exec(args)
	if result.exit_code != 0 { return error('Command failed: ${args[0]}\n${result.output}') }
	return result.output
}

fn generate(root string, source string, output string, arch string) ! {
	command(['sh', root + '/build-support/run-v-tool.sh', root + '/tests/linuxkpi/generate_module.v',
		source, output, '--arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' }])!
}

fn check_generated(path string) ! {
	text := os.read_file(path)!
	for symbol in ['memdup(', 'malloc(', 'calloc(', 'realloc(', 'new_array', 'v_fixed_index('] {
		if text.contains(symbol) { return error('Unexpected allocation/runtime dependency ${symbol} in ${path}') }
	}
}

fn host(root string, work string) ! {
	v := os.getenv_opt('V') or { @VEXE }
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true)
	volume_recovery_native_tests(root, work, v)!
	for entry in ['plan_test', 'plan_bundle_test', 'plan_growth_test', 'plan_check_test', 'plan_edit_test', 'plan_disks_test', 'plan_space_test', 'plan_capacity_test', 'plan_pool_test', 'plan_pool_growth_test', 'plan_pool_batch_test', 'plan_lock_test', 'plan_pool_grow_batch_test', 'plan_pool_expand_batch_test', 'plan_capacity_batch_test', 'plan_pool_members_batch_test', 'plan_pool_order_test', 'plan_remove_batch_test', 'plan_enroll_batch_test', 'plan_forget_batch_test', 'plan_add_batch_test', 'plan_grow_batch_test', 'plan_pool_contract_batch_test', 'plan_pool_resize_batch_test', 'plan_capacity_contract_batch_test', 'plan_multi_pool_batch_test', 'plan_multi_pool_grow_batch_test', 'data_manifest_test', 'data_scrub_test', 'crypt_test', 'recovery_test', 'sealed_test', 'sealed_rewrap_test', 'volume_seal_test', 'volume_rewrap_test', 'volume_discovery_test', 'volume_growth_test', 'volume_boot_test', 'volume_boot_set_test', 'volume_recovery_inspect_test', 'volume_inspect_test', 'volume_growth_preview_test', 'volume_ciphertext_test', 'volume_ciphertext_scrub_test', 'volume_scrub_compare_test', 'volume_scrub_auto_test', 'volume_ciphertext_auto_test', 'volume_reference_test', 'data_auto_test', 'data_reference_test', 'data_scrub_view_test', 'data_scrub_compare_test', 'data_scrub_reference_test', 'volume_scrub_reference_test', 'data_monitor_test', 'volume_monitor_test', 'data_monitor_verify_test', 'volume_monitor_verify_test', 'file_backup_test'] {
		binary := work + '/' + entry
		command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags',
			'-I' + root + '/tools/volumes/volumecli -fsanitize=address,undefined', '-ldflags',
			'-fsanitize=address,undefined', '-o', binary, root + '/tools/volumes/volumecli/' + entry + '.v'])!
		print(command([binary])!)
		println('PASS ' + entry + ': ASan/UBSan')
	}
	bundle_publication_tests(root, work, v)!
	growth_io_tests(root, work, v)!
	capacity_io_tests(root, work, v)!
	capacity_batch_io_tests(root, work, v)!
	data_io_tests(root, work, v)!
	data_scrub_view_io_tests(root, work, v)!
	data_scrub_history_io_tests(root, work, v)!
	scrub_reference_io_tests(root, work, v)!
	cipher_scrub_reference_io_tests(root, work, v)!
	data_monitor_io_tests(root, work, v)!
	cipher_monitor_io_tests(root, work, v)!
	data_monitor_verify_io_tests(root, work, v)!
	cipher_monitor_verify_io_tests(root, work, v)!
	crypt_io_tests(root, work, v)!
	recovery_io_tests(root, work, v)!
	sealed_io_tests(root, work, v)!
	volume_seal_io_tests(root, work, v)!
	volume_discovery_io_tests(root, work, v)!
	for arch in ['aarch64', 'x86_64'] {
		path := work + '/volume-' + arch + '.c'
		generate(root, root + '/tools/volumes/volumecli', path, arch)!
		check_generated(path)!
	}
	init_policy(root, work)!
	println('PASS host: plan format, identity, corruption, bounded plan sets, atomic publication and sanitizers')
}

fn recovery_unlock_host(root string, work string) ! {
	v := os.getenv_opt('V') or { @VEXE }
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true)
	volume_recovery_native_tests(root, work, v)!
	recovery_io_tests(root, work, v)!
	volume_discovery_io_tests(root, work, v)!
	binary := work + '/syntax-test'
	command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags',
		'-I' + root + '/tools/volumes/volumecli -O2 -fsanitize=address,undefined', '-ldflags',
		'-fsanitize=address,undefined', '-o', binary, root + '/tools/volumes/volumecli/volume_discovery_test.v'])!
	print(command([binary])!)
	for arch in ['aarch64', 'x86_64'] {
		path := work + '/volume-' + arch + '.c'
		generate(root, root + '/tools/volumes/volumecli', path, arch)!; check_generated(path)!
	}
	println('PASS recovery unlock native/model/syntax and both target allocation audits')
}

fn recovery_rewrap_host(root string, work string) ! {
	v := os.getenv_opt('V') or { @VEXE }; os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true)
	volume_recovery_native_tests(root, work, v)!
	recovery_io_tests(root, work, v)!
	binary := work + '/syntax-test'
	command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags',
		'-I' + root + '/tools/volumes/volumecli -O2 -fsanitize=address,undefined', '-ldflags',
		'-fsanitize=address,undefined', '-o', binary, root + '/tools/volumes/volumecli/volume_recovery_rewrap_test.v'])!
	print(command([binary])!)
	for arch in ['aarch64', 'x86_64'] {
		path := work + '/volume-' + arch + '.c'
		generate(root, root + '/tools/volumes/volumecli', path, arch)!; check_generated(path)!
	}
	println('PASS recovery rewrap native/model/syntax and both target allocation audits')
}

fn recovery_growth_host(root string, work string) ! {
	v := os.getenv_opt('V') or { @VEXE }; os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true)
	volume_recovery_native_tests(root, work, v)!; recovery_io_tests(root, work, v)!
	binary := work + '/syntax-test'
	command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags',
		'-I' + root + '/tools/volumes/volumecli -O2 -fsanitize=address,undefined', '-ldflags',
		'-fsanitize=address,undefined', '-o', binary, root + '/tools/volumes/volumecli/volume_recovery_growth_test.v'])!
	print(command([binary])!)
	for arch in ['aarch64', 'x86_64'] { path := work + '/volume-' + arch + '.c'; generate(root, root + '/tools/volumes/volumecli', path, arch)!; check_generated(path)! }
	println('PASS recovery growth native/model/syntax and both target allocation audits')
}

fn recovery_inspect_host(root string, work string) ! {
	v := os.getenv_opt('V') or { @VEXE }; os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true)
	volume_recovery_native_tests(root, work, v)!; volume_discovery_io_tests(root, work, v)!
	binary := work + '/syntax-test'
	command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags',
		'-I' + root + '/tools/volumes/volumecli -O2 -fsanitize=address,undefined', '-ldflags',
		'-fsanitize=address,undefined', '-o', binary, root + '/tools/volumes/volumecli/volume_recovery_inspect_test.v'])!
	print(command([binary])!)
	for arch in ['aarch64', 'x86_64'] { path := work + '/volume-' + arch + '.c'; generate(root, root + '/tools/volumes/volumecli', path, arch)!; check_generated(path)! }
	println('PASS recovery inspection native/model/syntax and both target allocation audits')
}

fn volume_inspect_host(root string, work string) ! {
	v := os.getenv_opt('V') or { @VEXE }; os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true)
	binary_codec := work + '/volume_seal_test'
	command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags', '-I' + root + '/tools/volumes/volumecli -O2 -fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined', '-o', binary_codec, root + '/tools/volumes/volumecli/volume_seal_test.v'])!
	print(command([binary_codec])!); println('PASS volume_seal_test: independent VC1 codec ASan/UBSan'); volume_discovery_io_tests(root, work, v)!
	binary := work + '/syntax-test'
	command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags',
		'-I' + root + '/tools/volumes/volumecli -O2 -fsanitize=address,undefined', '-ldflags',
		'-fsanitize=address,undefined', '-o', binary, root + '/tools/volumes/volumecli/volume_inspect_test.v'])!
	print(command([binary])!)
	for arch in ['aarch64', 'x86_64'] { path := work + '/volume-' + arch + '.c'; generate(root, root + '/tools/volumes/volumecli', path, arch)!; check_generated(path)! }
	println('PASS volume inspection native/model/syntax and both target allocation audits')
}

fn growth_preview_host(root string, work string) ! {
	v := os.getenv_opt('V') or { @VEXE }; os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true)
	volume_recovery_native_tests(root, work, v)!; recovery_io_tests(root, work, v)!
	for entry in ['volume_seal_test', 'volume_growth_preview_test'] {
		binary := work + '/' + entry
		command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags', '-I' + root + '/tools/volumes/volumecli -O2 -fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined', '-o', binary, root + '/tools/volumes/volumecli/' + entry + '.v'])!
		print(command([binary])!); println('PASS ' + entry + ': ASan/UBSan')
	}
	for arch in ['aarch64', 'x86_64'] { path := work + '/volume-' + arch + '.c'; generate(root, root + '/tools/volumes/volumecli', path, arch)!; check_generated(path)! }
	println('PASS growth preview native/model/syntax and both target allocation audits')
}

fn ciphertext_host(root string, work string) ! {
	v := os.getenv_opt('V') or { @VEXE }; os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true)
	volume_recovery_native_tests(root, work, v)!; recovery_io_tests(root, work, v)!
	for entry in ['volume_seal_test', 'volume_ciphertext_test'] {
		binary := work + '/' + entry
		command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags', '-I' + root + '/tools/volumes/volumecli -O2 -fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined', '-o', binary, root + '/tools/volumes/volumecli/' + entry + '.v'])!
		print(command([binary])!); println('PASS ' + entry + ': ASan/UBSan')
	}
	for arch in ['aarch64', 'x86_64'] { path := work + '/volume-' + arch + '.c'; generate(root, root + '/tools/volumes/volumecli', path, arch)!; check_generated(path)! }
	println('PASS ciphertext native/model/syntax and both target allocation audits')
}

fn ciphertext_scrub_host(root string, work string) ! {
	v := os.getenv_opt('V') or { @VEXE }; os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true)
	volume_recovery_native_tests(root, work, v)!; recovery_io_tests(root, work, v)!
	for entry in ['volume_seal_test', 'volume_ciphertext_scrub_test'] {
		binary := work + '/' + entry
		command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags', '-I' + root + '/tools/volumes/volumecli -O2 -fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined', '-o', binary, root + '/tools/volumes/volumecli/' + entry + '.v'])!
		print(command([binary])!); println('PASS ' + entry + ': ASan/UBSan')
	}
	for arch in ['aarch64', 'x86_64'] { path := work + '/volume-' + arch + '.c'; generate(root, root + '/tools/volumes/volumecli', path, arch)!; check_generated(path)! }
	println('PASS ciphertext scrub native/model/syntax and both target allocation audits')
}

fn sealed_io_tests(root string, work string, v string) ! {
	fixture := work + '/sealedio'; os.mkdir(fixture)!
	for file in os.ls(root + '/tools/volumes/volumecli')! {
		if !file.ends_with('.v') || file.ends_with('_test.v') { continue }
		mut source := os.read_file(root + '/tools/volumes/volumecli/' + file)!
		if file in ['recovery_io.v', 'crypt.v'] {
			for name in ['open', 'close', 'fstat', 'read', 'ioctl', 'openat', 'fchmod', 'write', 'fsync', 'linkat', 'unlinkat'] {
				source = source.replace('C.' + name + '(', 'sealed_mock_' + name + '(').replace('fn sealed_mock_' + name + '(', 'fn C.' + name + '(')
			}
		}
		if file == 'plan_lock.v' {
			for name in ['open', 'close', 'flock'] { source = source.replace('C.' + name + '(', 'sealed_mock_' + name + '(').replace('fn sealed_mock_' + name + '(', 'fn C.' + name + '(') }
		}
		if file == 'sealed_crypto.v' {
			for name in ['mmap', 'munmap'] { source = source.replace('C.' + name + '(', 'sealed_mock_' + name + '(').replace('fn sealed_mock_' + name + '(', 'fn C.' + name + '(') }
		}
		if file in ['sealed_io.v', 'sealed_rewrap.v'] { source = source.replace('sealed_derive(', 'sealed_mock_derive(') }
		if file == 'plan_check.v' { source = source.replace('C.fflush(', 'sealed_mock_fflush(') }
		if file in ['crypt.v', 'recovery_io.v', 'recovery_crypto.v', 'data_sha256.v', 'sealed_io.v', 'sealed_crypto.v', 'sealed_scrypt.v', 'sealed_rewrap.v'] {
			source = source.replace('erase_key(', 'sealed_mock_erase(').replace('fn sealed_mock_erase(', 'fn erase_key(')
		}
		os.write_file(fixture + '/' + file, source)!
	}
	os.cp(root + '/tests/storage-volumes/sealed_io_test.v', fixture + '/sealed_io_test.v')!
	binary := work + '/sealed-io-test'
	command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags',
		'-I' + root + '/tools/volumes/volumecli -O2 -fsanitize=address,undefined', '-ldflags',
		'-fsanitize=address,undefined', '-o', binary, fixture + '/sealed_io_test.v'])!
	print(command([binary])!)
	println('PASS sealed keys: source/entropy and publication faults, bounded memory allocation, complete vector erasure, release failure/EINTR, pre-KDF metadata validation, authentication before parent import and credential rewrap stage faults under ASan/UBSan')
}

fn volume_discovery_io_tests(root string, work string, v string) ! {
	fixture := work + '/volumediscoveryio'; os.mkdir(fixture)!
	for file in os.ls(root + '/tools/volumes/volumecli')! {
		if !file.ends_with('.v') || file.ends_with('_test.v') { continue }
		mut source := os.read_file(root + '/tools/volumes/volumecli/' + file)!
		if file in ['discovery.v', 'volume_discovery.v', 'volume_recovery_unlock.v', 'volume_recovery_inspect.v', 'volume_inspect.v', 'volume_boot.v', 'volume_boot_set.v', 'volume_seal_io.v', 'recovery_io.v', 'crypt.v', 'plan_io.v', 'plan_set.v'] {
			for name in ['open', 'close', 'openat', 'fstat', 'fstatat', 'fdopendir', 'closedir', 'readdir', 'ioctl', 'pread', 'read', 'geteuid', 'fcntl'] {
				if name == 'openat' && file !in ['discovery.v', 'volume_boot.v', 'volume_boot_set.v', 'plan_set.v'] { continue }
				source = source.replace('C.' + name + '(', 'volume_discovery_mock_' + name + '(').replace('fn volume_discovery_mock_' + name + '(', 'fn C.' + name + '(')
			}
		}
		if file in ['volume_seal_io.v', 'volume_boot.v'] { source = source.replace('sealed_derive(', 'volume_discovery_mock_derive(') }
		if file == 'plan_check.v' { source = source.replace('C.fflush(', 'volume_discovery_mock_fflush(').replace('C.ferror(', 'recovery_inspect_mock_ferror(').replace('fn recovery_inspect_mock_ferror(', 'fn C.ferror(') }
		if file in ['volume_recovery_inspect.v', 'volume_inspect.v'] {
			source = source.replace('unsafe { *work = VolumeSealFiles{} }', 'unsafe { *work = VolumeSealFiles{} }; recovery_inspect_record(work)')
			source = source.replace('finish_bundle_report(show_recovery_volume(', 'finish_bundle_report(recovery_inspect_mock_report(').replace('finish_bundle_report(show_sealed_volume(', 'finish_bundle_report(recovery_inspect_mock_report(')
		}
		if file in ['discovery.v', 'volume_discovery.v', 'volume_recovery_unlock.v', 'volume_recovery_inspect.v', 'volume_inspect.v', 'volume_boot.v', 'volume_boot_set.v', 'volume_seal_io.v'] { source = source.replace('erase_key(', 'volume_discovery_mock_erase(') }
		os.write_file(fixture + '/' + file, source)!
	}
	os.write_file(fixture + '/volume_discovery_io_test.v', os.read_file(root + '/tests/storage-volumes/volume_discovery_io_test.v')!
		+ '\n' + os.read_file(root + '/tests/storage-volumes/volume_recovery_unlock_io_test.v')!.all_after('import os\n')
		+ '\n' + os.read_file(root + '/tests/storage-volumes/volume_recovery_inspect_io_test.v')!.all_after('import os\n')
		+ '\n' + os.read_file(root + '/tests/storage-volumes/volume_inspect_io_test.v')!.all_after('import os\n'))!
	binary := work + '/volume-discovery-io-test'
	command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags',
		'-I' + root + '/tools/volumes/volumecli -O2 -fsanitize=address,undefined', '-ldflags',
		'-fsanitize=address,undefined', '-o', binary, fixture + '/volume_discovery_io_test.v'])!
	print(command([binary])!)
	println('PASS encrypted discovery: authentication before scan, erased credentials, aliases/duplicate disks, native geometry, pinned rechecks, enumeration/import faults and descriptor cleanup under ASan/UBSan')
}

fn volume_seal_io_tests(root string, work string, v string) ! {
	fixture := work + '/volumesealio'; os.mkdir(fixture)!
	for file in os.ls(root + '/tools/volumes/volumecli')! {
		if !file.ends_with('.v') || file.ends_with('_test.v') { continue }
		mut source := os.read_file(root + '/tools/volumes/volumecli/' + file)!
		if file in ['crypt.v', 'recovery_io.v', 'volume_seal_io.v', 'volume_growth.v', 'plan_io.v'] {
			for name in ['open', 'close', 'ioctl', 'pread', 'openat', 'write', 'fsync', 'linkat', 'unlinkat'] {
				source = source.replace('C.' + name + '(', 'volume_seal_mock_' + name + '(').replace('fn volume_seal_mock_' + name + '(', 'fn C.' + name + '(')
			}
		}
		if file == 'plan_lock.v' {
			for name in ['open', 'close', 'flock'] { source = source.replace('C.' + name + '(', 'volume_seal_mock_' + name + '(').replace('fn volume_seal_mock_' + name + '(', 'fn C.' + name + '(') }
		}
		if file in ['volume_seal_io.v', 'volume_rewrap.v', 'volume_growth.v'] { source = source.replace('sealed_derive(', 'volume_seal_mock_derive(') }
		if file == 'plan_check.v' { source = source.replace('C.fflush(', 'volume_seal_mock_fflush(') }
		if file in ['volume_seal_io.v', 'volume_seal_crypto.v', 'volume_rewrap.v', 'volume_growth.v', 'crypt.v', 'recovery_crypto.v', 'data_sha256.v', 'recovery_io.v'] {
			source = source.replace('erase_key(', 'volume_seal_mock_erase(').replace('fn volume_seal_mock_erase(', 'fn erase_key(')
		}
		os.write_file(fixture + '/' + file, source)!
	}
	os.cp(root + '/tests/storage-volumes/volume_seal_io_test.v', fixture + '/volume_seal_io_test.v')!
	binary := work + '/volume-seal-io-test'
	command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags',
		'-I' + root + '/tools/volumes/volumecli -O2 -fsanitize=address,undefined', '-ldflags',
		'-fsanitize=address,undefined', '-o', binary, fixture + '/volume_seal_io_test.v'])!
	print(command([binary])!)
	println('PASS sealed volume configurations: canonical authenticated metadata, pinned MBR/GPT identity, 512/4096-byte sectors, RW/RO downgrade, physical changes before publication/import, private recovery and fault cleanup under ASan/UBSan')
}

fn recovery_io_tests(root string, work string, v string) ! {
	fixture := work + '/recoveryio'; os.mkdir(fixture)!
	for file in os.ls(root + '/tools/volumes/volumecli')! {
		if !file.ends_with('.v') || file.ends_with('_test.v') { continue }
		mut source := os.read_file(root + '/tools/volumes/volumecli/' + file)!
		if file == 'recovery_io.v' {
			for name in ['open', 'close', 'fstat', 'read', 'flock', 'openat', 'fchmod', 'write', 'fsync', 'linkat', 'unlinkat'] {
				source = source.replace('C.' + name + '(', 'recovery_mock_' + name + '(').replace('fn recovery_mock_' + name + '(', 'fn C.' + name + '(')
			}
		}
		if file == 'plan_lock.v' {
			for name in ['open', 'close', 'flock'] { source = source.replace('C.' + name + '(', 'recovery_mock_' + name + '(').replace('fn recovery_mock_' + name + '(', 'fn C.' + name + '(') }
		}
		if file == 'plan_check.v' { source = source.replace('C.fflush(', 'recovery_mock_fflush(').replace('C.ferror(', 'growth_preview_mock_ferror(').replace('fn growth_preview_mock_ferror(', 'fn C.ferror(') }
		if file in ['volume_recovery.v', 'volume_seal_io.v'] { source = source.replace('sealed_derive(', 'volume_recovery_mock_derive(') }
		if file == 'volume_recovery_rewrap.v' { source = source.replace('unsafe { *work = VolumeSealFiles{} }', 'unsafe { *work = VolumeSealFiles{} }; recovery_rewrap_record(work)') }
		if file == 'volume_recovery_growth.v' {
			source = source.replace('unsafe { *work = VolumeSealFiles{} }', 'unsafe { *work = VolumeSealFiles{} }; recovery_growth_record(work)')
			for name in ['open', 'close'] { source = source.replace('C.' + name + '(', 'recovery_mock_' + name + '(') }
		}
		if file == 'volume_growth_preview.v' {
			source = source.replace('unsafe { *work = VolumeSealFiles{} }', 'unsafe { *work = VolumeSealFiles{} }; recovery_growth_record(work)')
			for name in ['open', 'close'] { source = source.replace('C.' + name + '(', 'recovery_mock_' + name + '(') }
			source = source.replace('finish_bundle_report(show_volume_growth_preview(', 'finish_bundle_report(growth_preview_report(').replace('erase_key(', 'recovery_mock_erase(')
		}
		if file == 'volume_ciphertext.v' {
			source = source.replace('unsafe { *work = VolumeSealFiles{} }', 'unsafe { *work = VolumeSealFiles{} }; recovery_growth_record(work)')
			for name in ['open', 'close'] { source = source.replace('C.' + name + '(', 'recovery_mock_' + name + '(') }
			source = source.replace('C.pread(', 'ciphertext_dispatch_pread(').replace('finish_bundle_report(show_volume_ciphertext(', 'finish_bundle_report(ciphertext_mock_report(').replace('erase_key(', 'recovery_mock_erase(')
		}
		if file == 'volume_ciphertext_scrub.v' {
			source = source.replace('unsafe { *work = VolumeSealFiles{} }', 'unsafe { *work = VolumeSealFiles{} }; recovery_growth_record(work)')
			for name in ['open', 'close'] { source = source.replace('C.' + name + '(', 'recovery_mock_' + name + '(') }
			source = source.replace('finish_bundle_report(show_volume_ciphertext_scrub(', 'finish_bundle_report(volume_scrub_mock_report(').replace('erase_key(', 'recovery_mock_erase(')
		}
		if file == 'volume_reference.v' { source = source.replace('finish_bundle_report(show_volume_reference(', 'finish_bundle_report(volume_reference_mock_report(') }
		if file == 'volume_scrub_compare.v' { source = source.replace('finish_bundle_report(show_volume_scrub_comparison(', 'finish_bundle_report(volume_scrub_compare_mock_report(') }
		if file == 'volume_scrub_auto.v' { source = source.replace('C.open(', 'recovery_mock_open(').replace('discover_disk_key(', 'auto_scrub_mock_discover(') }
		if file == 'plan_io.v' { for name in ['ioctl', 'pread'] { source = source.replace('C.' + name + '(', 'ciphertext_dispatch_' + name + '(').replace('fn ciphertext_dispatch_' + name + '(', 'fn C.' + name + '(') } }
		if file in ['recovery_io.v', 'recovery_crypto.v', 'data_sha256.v', 'volume_recovery.v', 'volume_recovery_rewrap.v', 'volume_recovery_growth.v', 'volume_recovery_crypto.v', 'volume_seal_io.v', 'volume_seal_crypto.v'] { source = source.replace('erase_key(', 'recovery_mock_erase(') }
		os.write_file(fixture + '/' + file, source)!
	}
	os.write_file(fixture + '/recovery_io_test.v', os.read_file(root + '/tests/storage-volumes/recovery_io_test.v')!
		+ '\n' + os.read_file(root + '/tests/storage-volumes/volume_recovery_io_test.v')!.all_after('import os\n')
		+ '\n' + os.read_file(root + '/tests/storage-volumes/volume_recovery_rewrap_io_test.v')!.all_after('import os\n')
		+ '\n' + os.read_file(root + '/tests/storage-volumes/volume_recovery_growth_io_test.v')!.all_after('import os\n')
		+ '\n' + os.read_file(root + '/tests/storage-volumes/volume_growth_preview_io_test.v')!.all_after('import os\n')
		+ '\n' + os.read_file(root + '/tests/storage-volumes/volume_ciphertext_io_test.v')!.all_after('import os\n').replace('import crypto.sha256\n', '').replace('import encoding.hex\n', '')
		+ '\n' + os.read_file(root + '/tests/storage-volumes/volume_ciphertext_scrub_io_test.v')!.all_after('import os\n')
		+ '\n' + os.read_file(root + '/tests/storage-volumes/volume_scrub_compare_io_test.v')!.all_after('import os\n')
		+ '\n' + os.read_file(root + '/tests/storage-volumes/volume_scrub_auto_io_test.v')!.all_after('import os\n')
		+ '\n' + os.read_file(root + '/tests/storage-volumes/volume_ciphertext_auto_io_test.v')!.all_after('import os\n')
		+ '\n' + os.read_file(root + '/tests/storage-volumes/volume_reference_io_test.v')!.all_after('import os\n'))!
	binary := work + '/recovery-io-test'
	command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags',
		'-I' + root + '/tools/volumes/volumecli -fsanitize=address,undefined', '-ldflags',
		'-fsanitize=address,undefined', '-o', binary, fixture + '/recovery_io_test.v'])!
	print(command([binary])!)
	println('PASS key recovery: source/nonce faults, complete erasure, no-overwrite publication, temporary ownership, durability/output failures and descriptor balance under ASan/UBSan')
}

fn volume_recovery_native_tests(root string, work string, v string) ! {
	binary := work + '/volume_recovery_test'
	command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags',
		'-I' + root + '/tools/volumes/volumecli -fsanitize=address,undefined', '-ldflags',
		'-fsanitize=address,undefined', '-o', binary, root + '/tools/volumes/volumecli/volume_recovery_test.v'])!
	print(command([binary])!)
	println('PASS volume_recovery_test: ASan/UBSan, independent crypto and complete authenticated metadata')
}

fn crypt_io_tests(root string, work string, v string) ! {
	fixture := work + '/cryptio'
	os.mkdir(fixture)!
	for file in os.ls(root + '/tools/volumes/volumecli')! {
		if !file.ends_with('.v') || file.ends_with('_test.v') { continue }
		mut source := os.read_file(root + '/tools/volumes/volumecli/' + file)!
		if file == 'crypt.v' {
			for name in ['open', 'close', 'read', 'fstat', 'ioctl'] {
				source = source.replace('C.' + name + '(', 'crypt_mock_' + name + '(')
			}
			source = source.replace('erase_key(', 'crypt_mock_bzero(').replace('fn crypt_mock_bzero(', 'fn erase_key(')
		}
		os.write_file(fixture + '/' + file, source)!
	}
	os.cp(root + '/tests/storage-volumes/crypt_io_test.v', fixture + '/crypt_io_test.v')!
	binary := work + '/crypt-io-test'
	command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags',
		'-I' + root + '/tools/volumes/volumecli -fsanitize=address,undefined', '-ldflags',
		'-fsanitize=address,undefined', '-o', binary, fixture + '/crypt_io_test.v'])!
	print(command([binary])!)
	println('PASS encrypted import: short/EINTR reads, owner checks, key growth, parent/ioctl failures, descriptor balance and full request erasure under ASan/UBSan')
}

fn data_io_tests(root string, work string, v string) ! {
	fixture := work + '/dataio'
	os.mkdir(fixture)!
	for file in os.ls(root + '/tools/volumes/volumecli')! {
		if !file.ends_with('.v') || file.ends_with('_test.v') { continue }
		mut source := os.read_file(root + '/tools/volumes/volumecli/' + file)!
		if file == 'data_reference.v' { source = source.replace('encode_data_reference_comparison(', 'data_reference_mock_encode(').replace('fn data_reference_mock_encode(', 'fn encode_data_reference_comparison(') }
		if file == 'data_manifest.v' { for name in ['read', 'fstat'] { source = source.replace('C.' + name + '(', if name == 'read' { 'data_reference_read(' } else { 'data_reference_stat(' }) } }
		if file == 'plan_lock.v' { for name in ['open', 'openat', 'close', 'flock'] { source = source.replace('C.' + name + '(', 'data_reference_' + name + '(').replace('fn data_reference_' + name + '(', 'fn C.' + name + '(') } }
		if file == 'plan_check.v' { source = source.replace('C.fflush(', 'data_reference_flush(').replace('C.ferror(', 'data_reference_ferror(').replace('fn data_reference_ferror(', 'fn C.ferror(') }
		if file == 'data_auto.v' { source = source.replace('discover_disk_key(', 'data_auto_mock_discover(') }
		if file == 'data_io.v' {
			source = source.replace('probe_disk(', 'data_auto_mock_probe(')
			for name in ['open', 'close', 'pread'] { source = source.replace('C.' + name + '(', 'data_mock_' + name + '(') }
		}
		if file == 'plan_io.v' {
			for name in ['ioctl', 'pread'] { source = source.replace('C.' + name + '(', 'data_mock_' + name + '(').replace('fn data_mock_' + name + '(', 'fn C.' + name + '(') }
			start := source.index('fn publish_bytes(') or { return error('Missing shared publisher') }
			end := source.index('\nfn volume_path(') or { return error('Missing publisher boundary') }
			mut publisher := source[start..end]
			for name in ['write', 'fsync', 'close', 'renameat'] { publisher = publisher.replace('C.' + name + '(', 'data_publish_' + name + '(') }
			source = source[..start] + publisher + source[end..]
		}
		os.write_file(fixture + '/' + file, source)!
	}
	os.write_file(fixture + '/data_io_test.v', os.read_file(root + '/tests/storage-volumes/data_io_test.v')! + '\n' + os.read_file(root + '/tests/storage-volumes/data_auto_io_test.v')!.all_after('import os\n') + '\n' + os.read_file(root + '/tests/storage-volumes/data_reference_io_test.v')!.all_after('import os\n'))!
	binary := work + '/data-io-test'
	command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags',
		'-I' + root + '/tools/volumes/volumecli -fsanitize=address,undefined', '-ldflags',
		'-fsanitize=address,undefined', '-o', binary, fixture + '/data_io_test.v'])!
	print(command([binary])!)
	println('PASS data checksums: all-device pinning/rechecks, streaming short reads, later corruption, atomic publication and output failures under ASan/UBSan')
}

fn capacity_batch_io_tests(root string, work string, v string) ! {
	fixture := work + '/capacitybatchio'
	os.mkdir(fixture)!
	for file in os.ls(root + '/tools/volumes/volumecli')! {
		if !file.ends_with('.v') || file.ends_with('_test.v') { continue }
		mut source := os.read_file(root + '/tools/volumes/volumecli/' + file)!
		if file in ['plan_capacity_batch.v', 'plan_capacity_contract_batch.v'] {
			for name in ['open', 'close'] { source = source.replace('C.' + name + '(', 'capacity_batch_mock_' + name + '(') }
		}
		if file == 'plan_io.v' {
			for name in ['ioctl', 'pread'] {
				source = source.replace('C.' + name + '(', 'capacity_batch_mock_' + name + '(')
					.replace('fn capacity_batch_mock_' + name + '(', 'fn C.' + name + '(')
			}
			start := source.index('fn publish_bytes(') or { return error('Missing shared publisher') }
			end := source.index('\nfn volume_path(') or { return error('Missing publisher boundary') }
			mut publisher := source[start..end]
			for name in ['write', 'fsync', 'close', 'renameat'] {
				publisher = publisher.replace('C.' + name + '(', 'capacity_batch_publish_' + name + '(')
			}
			source = source[..start] + publisher + source[end..]
		}
		os.write_file(fixture + '/' + file, source)!
	}
	os.cp(root + '/tests/storage-volumes/capacity_batch_io_test.v', fixture + '/capacity_batch_io_test.v')!
	binary := work + '/capacity-batch-io-test'
	command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags',
		'-I' + root + '/tools/volumes/volumecli -fsanitize=address,undefined', '-ldflags',
		'-fsanitize=address,undefined', '-o', binary, fixture + '/capacity_batch_io_test.v'])!
	print(command([binary])!)
	println('PASS capacity batches: all-device pinning/rechecks, complete rollback, previews, publication faults and output failure under ASan/UBSan')
}

// Keep filesystem reads/publication real, replacing only the physical device
// boundary and the shared publisher's synchronous fault-injection boundary.
fn capacity_io_tests(root string, work string, v string) ! {
	fixture := work + '/capacityio'
	os.mkdir(fixture)!
	for file in os.ls(root + '/tools/volumes/volumecli')! {
		if !file.ends_with('.v') || file.ends_with('_test.v') { continue }
		mut source := os.read_file(root + '/tools/volumes/volumecli/' + file)!
		if file == 'plan_capacity.v' {
			for name in ['open', 'close'] { source = source.replace('C.' + name + '(', 'capacity_mock_' + name + '(') }
		}
		if file == 'plan_io.v' {
			for name in ['ioctl', 'pread'] {
				source = source.replace('C.' + name + '(', 'capacity_mock_' + name + '(')
					.replace('fn capacity_mock_' + name + '(', 'fn C.' + name + '(')
			}
			start := source.index('fn publish_bytes(') or { return error('Missing shared publisher') }
			end := source.index('\nfn volume_path(') or { return error('Missing publisher boundary') }
			mut publisher := source[start..end]
			for name in ['write', 'fsync', 'close', 'renameat'] {
				publisher = publisher.replace('C.' + name + '(', 'capacity_publish_' + name + '(')
			}
			source = source[..start] + publisher + source[end..]
		}
		os.write_file(fixture + '/' + file, source)!
	}
	os.cp(root + '/tests/storage-volumes/capacity_io_test.v', fixture + '/capacity_io_test.v')!
	binary := work + '/capacity-io-test'
	command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags',
		'-I' + root + '/tools/volumes/volumecli -fsanitize=address,undefined', '-ldflags',
		'-fsanitize=address,undefined', '-o', binary, fixture + '/capacity_io_test.v'])!
	print(command([binary])!)
	println('PASS physical capacity adoption: pinned read-only probes, identity/geometry changes, atomic publication, durable no-op and output failure under ASan/UBSan')
}

fn growth_io_tests(root string, work string, v string) ! {
	fixture := work + '/growthio'
	os.mkdir(fixture)!
	for file in os.ls(root + '/tools/volumes/volumecli')! {
		if !file.ends_with('.v') || file.ends_with('_test.v') { continue }
		mut source := os.read_file(root + '/tools/volumes/volumecli/' + file)!
		if file == 'plan_io.v' {
			for name in ['open', 'close', 'ioctl', 'pread'] {
				source = source.replace('C.' + name + '(', 'growth_mock_' + name + '(')
					.replace('fn growth_mock_' + name + '(', 'fn C.' + name + '(')
			}
		}
		if file == 'plan_set.v' {
			source = source.replace('discover_disk(', 'growth_mock_discover(')
				.replace('C.close(', 'growth_mock_close(')
		}
		os.write_file(fixture + '/' + file, source)!
	}
	os.cp(root + '/tests/storage-volumes/growth_io_test.v', fixture + '/growth_io_test.v')!
	binary := work + '/growth-io-test'
	command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags',
		'-I' + root + '/tools/volumes/volumecli -fsanitize=address,undefined', '-ldflags',
		'-fsanitize=address,undefined', '-o', binary, fixture + '/growth_io_test.v'])!
	print(command([binary])!)
	println('PASS growth replay: preflight, generation/geometry recheck, failures, cleanup and resumable application under ASan/UBSan')
}

// Replace only the shared publisher's synchronous syscall boundary. The
// production encoder, cleanup and publication ordering are compiled unchanged.
fn bundle_publication_tests(root string, work string, v string) ! {
	fixture := work + '/bundleio'
	os.mkdir(fixture)!
	for file in os.ls(root + '/tools/volumes/volumecli')! {
		if !file.ends_with('.v') || file.ends_with('_test.v') { continue }
		mut source := os.read_file(root + '/tools/volumes/volumecli/' + file)!
		if file == 'plan_enroll_batch.v' {
			for name in ['open', 'close', 'fstat', 'pread'] { source = source.replace('C.' + name + '(', 'enrollment_mock_' + name + '(') }
		}
		if file == 'plan_io.v' {
			start := source.index('fn publish_bytes(') or { return error('Missing shared publisher') }
			end := source.index('\nfn volume_path(') or { return error('Missing publisher boundary') }
			mut publisher := source[start..end]
			for name in ['write', 'fsync', 'close', 'renameat'] {
				publisher = publisher.replace('C.' + name + '(', 'bundle_mock_' + name + '(')
			}
			source = source[..start] + publisher + source[end..]
		}
		os.write_file(fixture + '/' + file, source)!
	}
	os.cp(root + '/tests/storage-volumes/bundle_io_test.v', fixture + '/bundle_io_test.v')!
	binary := work + '/bundle-io-test'
	command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags',
		'-I' + root + '/tools/volumes/volumecli -fsanitize=address,undefined', '-ldflags',
		'-fsanitize=address,undefined', '-o', binary, fixture + '/bundle_io_test.v'])!
	print(command([binary])!)
	println('PASS bundle publication: interruption, short writes, file/directory flush, close and rename faults under ASan/UBSan')
}

fn init_policy(root string, work string) ! {
	generate(root, root + '/tests/init-policy/hostfixture', work + '/init-fixture.c', 'aarch64')!
	for variant in ['normal', 'echo'] {
		mut args := ['sh', root + '/build-support/run-v-tool.sh', root + '/build-support/init-aarch64/compile_init.v',
			'desktop', work + '/init-policy-' + variant + '.c', '--host']
		if variant == 'echo' { args << '--busybox-echo-test' }
		command(args)!
		check_generated(work + '/init-policy-' + variant + '.c')!
		binary := work + '/init-host-' + variant
		command(['clang', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function',
			'-Wno-unused-parameter', '-Wno-unused-label', '-D_GNU_SOURCE', '-DVINIX_INIT_HOST_TEST',
			'-fsanitize=address,undefined', '-I', root + '/build-support/init-aarch64',
			'-I', root + '/tests/init-policy/hostfixture', work + '/init-policy-' + variant + '.c',
			work + '/init-fixture.c', '-o', binary])!
		print(command(if variant == 'echo' { [binary, 'echo'] } else { [binary] })!)
	}
}

fn write_disk(path string, wrong bool) ! {
	mut file := os.create(path)!
	defer { file.close() }
	file.seek(16 * 1024 * 1024 - 1, .start)!
	file.write([u8(0)])!
	mut sector := [512]u8{}
	sector[440] = if wrong { u8(0x79) } else { u8(0x78) }; sector[441] = 0x56; sector[442] = 0x34; sector[443] = 0x12
	sector[510] = 0x55; sector[511] = 0xaa
	// An unformatted partition must not be mistaken for its whole parent.
	sector[450] = 0x83; sector[455] = 0x40; sector[459] = 8
	file.seek(0, .start)!
	file.write(sector[..])!
}

fn nvme_disk(path string, identity u8) ! {
	write_disk(path, false)!
	mut file := os.open_file(path, 'r+')!
	defer { file.close() }
	file.seek(440, .start)!
	file.write([identity])!
}

fn plan_filesystem(work string) ! {
	plan_filesystem_blocks(work, 2048)!
}

fn plan_filesystem_blocks(work string, blocks int) ! {
	tool := os.find_abs_path_of_executable('mke2fs') or {
		'/opt/homebrew/opt/e2fsprogs/sbin/mke2fs'
	}
	command([tool, '-q', '-F', '-t', 'ext2', '-b', '4096', '-I', '128', '-m', '0',
		'-d', work + '/seed', work + '/config.ext2', blocks.str()])!
	debugfs := os.join_path(os.dir(tool), 'debugfs')
	for path in ['/etc', '/etc/vinix', '/root'] {
		command([debugfs, '-w', '-R', 'set_inode_field ' + path + ' uid 0', work + '/config.ext2'])!
	}
}

fn compile_guest(root string, work string, arch string, nvme bool, recovery_mode string) ! {
	source := work + '/guest.c'
	if recovery_mode == 'file-backup' {
		command(['sh', root + '/build-support/run-v-tool.sh', root + '/tests/linuxkpi/generate_module.v', root + '/tests/storage-volumes/planguest', source, '--arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-d', 'file_backup_guest_test'])!
	} else if recovery_mode == 'cipher-monitor-verify' {
		command(['sh', root + '/build-support/run-v-tool.sh', root + '/tests/linuxkpi/generate_module.v', root + '/tests/storage-volumes/planguest', source, '--arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-d', 'cipher_monitor_verify_test'])!
	} else if recovery_mode == 'data-monitor-verify' {
		command(['sh', root + '/build-support/run-v-tool.sh', root + '/tests/linuxkpi/generate_module.v', root + '/tests/storage-volumes/planguest', source, '--arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-d', 'data_monitor_verify_test'])!
	} else if recovery_mode == 'cipher-monitor' {
		command(['sh', root + '/build-support/run-v-tool.sh', root + '/tests/linuxkpi/generate_module.v', root + '/tests/storage-volumes/planguest', source, '--arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-d', 'cipher_monitor_test'])!
	} else if recovery_mode == 'data-monitor' {
		command(['sh', root + '/build-support/run-v-tool.sh', root + '/tests/linuxkpi/generate_module.v', root + '/tests/storage-volumes/planguest', source, '--arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-d', 'data_monitor_test'])!
	} else if recovery_mode == 'cipher-scrub-reference' {
		command(['sh', root + '/build-support/run-v-tool.sh', root + '/tests/linuxkpi/generate_module.v', root + '/tests/storage-volumes/planguest', source, '--arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-d', 'cipher_scrub_reference_test'])!
	} else if recovery_mode == 'scrub-reference' {
		command(['sh', root + '/build-support/run-v-tool.sh', root + '/tests/linuxkpi/generate_module.v', root + '/tests/storage-volumes/planguest', source, '--arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-d', 'scrub_reference_test'])!
	} else if recovery_mode == 'data-scrub-history' {
		command(['sh', root + '/build-support/run-v-tool.sh', root + '/tests/linuxkpi/generate_module.v', root + '/tests/storage-volumes/planguest', source, '--arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-d', 'data_scrub_history_test'])!
	} else if recovery_mode == 'data-scrub-view' {
		command(['sh', root + '/build-support/run-v-tool.sh', root + '/tests/linuxkpi/generate_module.v', root + '/tests/storage-volumes/planguest', source, '--arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-d', 'data_scrub_view_test'])!
	} else if recovery_mode == 'data-reference' {
		command(['sh', root + '/build-support/run-v-tool.sh', root + '/tests/linuxkpi/generate_module.v', root + '/tests/storage-volumes/planguest', source, '--arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-d', 'data_reference_test'])!
	} else if recovery_mode == 'data-auto' {
		command(['sh', root + '/build-support/run-v-tool.sh', root + '/tests/linuxkpi/generate_module.v', root + '/tests/storage-volumes/planguest', source, '--arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-d', 'data_auto_test'])!
	} else if recovery_mode == 'reference' {
		command(['sh', root + '/build-support/run-v-tool.sh', root + '/tests/linuxkpi/generate_module.v', root + '/tests/storage-volumes/planguest', source, '--arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-d', 'volume_reference_test'])!
	} else if recovery_mode == 'ciphertext-auto' {
		command(['sh', root + '/build-support/run-v-tool.sh', root + '/tests/linuxkpi/generate_module.v', root + '/tests/storage-volumes/planguest', source, '--arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-d', 'volume_ciphertext_auto_test'])!
	} else if recovery_mode == 'auto-scrub' {
		command(['sh', root + '/build-support/run-v-tool.sh', root + '/tests/linuxkpi/generate_module.v', root + '/tests/storage-volumes/planguest', source, '--arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-d', 'volume_scrub_auto_test'])!
	} else if recovery_mode == 'scrub-compare' {
		command(['sh', root + '/build-support/run-v-tool.sh', root + '/tests/linuxkpi/generate_module.v', root + '/tests/storage-volumes/planguest', source, '--arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-d', 'volume_scrub_compare_test'])!
	} else if recovery_mode == 'ciphertext-scrub' {
		command(['sh', root + '/build-support/run-v-tool.sh', root + '/tests/linuxkpi/generate_module.v', root + '/tests/storage-volumes/planguest', source, '--arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-d', 'volume_ciphertext_scrub_test'])!
	} else if recovery_mode == 'ciphertext' {
		command(['sh', root + '/build-support/run-v-tool.sh', root + '/tests/linuxkpi/generate_module.v', root + '/tests/storage-volumes/planguest', source, '--arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-d', 'volume_ciphertext_test'])!
	} else if recovery_mode == 'growth-preview' {
		command(['sh', root + '/build-support/run-v-tool.sh', root + '/tests/linuxkpi/generate_module.v', root + '/tests/storage-volumes/planguest', source, '--arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-d', 'volume_growth_preview_test'])!
	} else if recovery_mode == 'volume-inspect' {
		command(['sh', root + '/build-support/run-v-tool.sh', root + '/tests/linuxkpi/generate_module.v', root + '/tests/storage-volumes/planguest', source, '--arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-d', 'volume_inspect_test'])!
	} else if recovery_mode == 'inspect' {
		command(['sh', root + '/build-support/run-v-tool.sh', root + '/tests/linuxkpi/generate_module.v',
			root + '/tests/storage-volumes/planguest', source, '--arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-d', 'volume_recovery_inspect_test'])!
	} else if recovery_mode == 'growth' {
		command(['sh', root + '/build-support/run-v-tool.sh', root + '/tests/linuxkpi/generate_module.v',
			root + '/tests/storage-volumes/planguest', source, '--arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-d', 'volume_recovery_growth_test'])!
	} else if recovery_mode == 'rewrap' {
		command(['sh', root + '/build-support/run-v-tool.sh', root + '/tests/linuxkpi/generate_module.v',
			root + '/tests/storage-volumes/planguest', source, '--arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-d', 'volume_recovery_rewrap_test'])!
	} else if recovery_mode == 'unlock' {
		command(['sh', root + '/build-support/run-v-tool.sh', root + '/tests/linuxkpi/generate_module.v',
			root + '/tests/storage-volumes/planguest', source, '--arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-d', 'volume_recovery_unlock_test'])!
	} else if recovery_mode == 'recovery' {
		command(['sh', root + '/build-support/run-v-tool.sh', root + '/tests/linuxkpi/generate_module.v',
			root + '/tests/storage-volumes/planguest', source, '--arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-d', 'volume_recovery_test'])!
	} else if nvme {
		command(['sh', root + '/build-support/run-v-tool.sh', root + '/tests/linuxkpi/generate_module.v',
			root + '/tests/storage-volumes/planguest', source, '--arch', 'amd64', '-d', 'nvme_health_test'])!
	} else { generate(root, root + '/tests/storage-volumes/planguest', source, arch)! }
	check_generated(source)!
	cc := if arch == 'aarch64' { 'aarch64-linux-musl-gcc' } else { 'x86_64-linux-musl-gcc' }
	command([cc, '-static', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror',
		'-Wno-unused-function', '-Wno-unused-parameter', '-Wno-unused-label', '-D_GNU_SOURCE',
		'-DVINIX_V_RUNTIME', '-I', root + '/tools/volumes/volumecli', source, '-o', work + '/init'])!
	os.mkdir_all(work + '/seed/sbin')!
	for name in ['dev', 'proc', 'tmp', 'root', 'run', 'sys'] { os.mkdir_all(work + '/seed/' + name)! }
	os.write_file(work + '/seed/.vinix-image-id', 'volume-plan-fixture\n')!
	os.cp(work + '/init', work + '/seed/sbin/init')!
	os.chmod(work + '/seed/sbin/init', 0o755)!
	if recovery_mode in ['cipher-monitor-verify', 'file-backup'] { stage_selected_volume(root, work, arch, cc)! }
	else { print(command(['sh', root + '/build-support/run-v-tool.sh', root + '/build-support/storage-tools/stage.v',
		'--arch', if arch == 'aarch64' { 'aarch64' } else { 'x86_64' }, '--staging', work + '/seed'])!) }
	os.mkdir_all(work + '/seed/etc/vinix')!
	os.write_file(work + '/seed/etc/vinix/volumes.vmap', 'deliberately invalid boot plan\n')!
	os.mkdir_all(work + '/seed/usr/bin')!
	os.cp(work + '/init', work + '/seed/usr/bin/vinix-desktop')!
	os.chmod(work + '/seed/usr/bin/vinix-desktop', 0o755)!
	if arch == 'aarch64' {
		command(['sh', root + '/build-support/run-v-tool.sh', root + '/build-support/init-aarch64/compile_init.v',
			'desktop', work + '/boot-init.c'])!
		check_generated(work + '/boot-init.c')!
		command(['clang', '--target=aarch64-linux-none', '-nostdlib', '-ffreestanding', '-O2',
			'-fno-stack-protector', '-fno-builtin', '-ffunction-sections', '-fdata-sections', '-c',
			'-I', root + '/build-support/init-aarch64', work + '/boot-init.c', '-o', work + '/boot-init.o'])!
		command(['clang', '--target=aarch64-linux-none', '-c', root + '/build-support/init-aarch64/syscall_abi.S', '-o', work + '/boot-abi.o'])!
		command(['ld.lld', '-m', 'aarch64elf', '--nostdlib', '-static', '--gc-sections',
			work + '/boot-init.o', work + '/boot-abi.o', '-o', work + '/seed/sbin/init'])!
	} else {
		cached := os.getenv_opt('VINIX_AMD64_USERLAND_ROOT') or { root + '/build-amd64-userland/staging' }
		os.mkdir_all(work + '/seed/bin')!; os.mkdir_all(work + '/seed/lib')!
		for path in ['bin/busybox', 'lib/ld-musl-x86_64.so.1'] { os.cp(cached + '/' + path, work + '/seed/' + path)! }
		os.symlink('busybox', work + '/seed/bin/sh')!
		// The V console adapter execs the unchanged packaged init as PID 1.
		os.mkdir_all(work + '/seed/usr/libexec')!
		os.cp(root + '/build-support/init-amd64/desktop-init', work + '/seed/usr/libexec/volume-test-init')!
	}
	os.chmod(work + '/seed/sbin/init', 0o755)!
}

fn pack(work string) ! {
	command(['tar', '--format=ustar', '-cf', work + '/initramfs.tar', '-C', work + '/seed', '.'])!
}

fn amd64_boot(root string, work string, kernel string, second bool, nvme bool) ![]string {
	iso := work + '/iso'
	os.mkdir_all(iso + '/boot')!
	os.mkdir_all(iso + '/EFI/BOOT')!
	os.cp(kernel, iso + '/boot/vinix')!
	os.cp(work + '/initramfs.tar', iso + '/boot/initramfs.tar')!
	os.cp(root + '/build-amd64-iso/limine/BOOTX64.EFI', iso + '/EFI/BOOT/BOOTX64.EFI')!
	os.cp(root + '/build-amd64-iso/limine/limine-uefi-cd.bin', iso + '/boot/limine-uefi-cd.bin')!
	os.write_file(iso + '/boot/limine.conf', os.read_file(root + '/build-support/limine.conf')! + '\n    cmdline: vinix.disk=auto\n')!
	command(['xorriso', '-as', 'mkisofs', '-iso-level', '3', '-R', '-r', '-J',
		'-e', 'boot/limine-uefi-cd.bin', '-no-emul-boot', iso, '-o', work + '/test.iso'])!
	qemu := os.find_abs_path_of_executable('qemu-system-x86_64')!
	firmware := os.getenv_opt('VINIX_OVMF_CODE_AMD64') or {
		os.dir(os.dir(os.real_path(qemu))) + '/share/qemu/edk2-x86_64-code.fd'
	}
	first_disk := work + if second { '/wrong.raw' } else { '/volume.raw' }
	second_disk := work + if second { '/volume.raw' } else { '/wrong.raw' }
	mut args := [qemu, '-machine', 'q35,smm=off', '-accel', 'tcg', '-cpu', 'max', '-m', '1024', '-smp', '2',
		'-drive', 'if=pflash,format=raw,unit=0,readonly=on,file=' + firmware,
		'-cdrom', work + '/test.iso', '-drive', 'if=ide,format=raw,cache=writeback,file=' + first_disk,
		'-drive', 'if=ide,format=raw,cache=writeback,file=' + second_disk,
		'-drive', 'if=ide,format=raw,cache=writeback,file=' + work + '/config.ext2',
		'-display', 'none', '-monitor', 'none', '-serial', 'stdio', '-nic', 'none', '-no-reboot']
	if nvme {
		args << ['-drive','if=none,format=raw,id=nvme-health,file=' + work + '/nvme.raw',
			'-device','nvme,drive=nvme-health,serial=VINIXHEALTH',
			'-drive','if=none,format=raw,id=nvme-warning,file=' + work + '/nvme-warning.raw',
			'-device','nvme,drive=nvme-warning,serial=VINIXWARNING,smart_critical_warning=8']
	}
	return args
}

fn arm_boot(root string, work string, kernel string, second bool) ![]string {
	boot_image := work + '/boot.img'
	if !os.exists(boot_image) {
		mut file := os.create(boot_image)!
		file.seek(64 * 1024 * 1024 - 1, .start)!; file.write([u8(0)])!; file.close()
		command(['mformat', '-F', '-i', boot_image, '::'])!
		for directory in ['::/EFI', '::/EFI/BOOT', '::/boot'] { command(['mmd', '-i', boot_image, directory])! }
		command(['mcopy', '-i', boot_image, root + '/boot-image/limine-bin/BOOTAA64.EFI', '::/EFI/BOOT/BOOTAA64.EFI'])!
	}
	os.write_file(work + '/limine.conf', os.read_file(root + '/build-support/limine.conf')! + '\n    cmdline: vinix.qemu_platform=1 vinix.qemu_persist=1 vinix.qemu_root=1\n')!
	for pair in [[kernel, '::/boot/vinix'], [work + '/initramfs.tar', '::/boot/initramfs.tar'], [work + '/limine.conf', '::/boot/limine.conf']] {
		command(['mcopy', '-o', '-i', boot_image, pair[0], pair[1]])!
	}
	qemu := os.find_abs_path_of_executable('qemu-system-aarch64')!
	share := os.dir(os.dir(os.real_path(qemu))) + '/share/qemu'
	os.cp(share + '/edk2-arm-vars.fd', work + '/vars.fd')!
	firmware := os.getenv_opt('VINIX_OVMF_CODE') or { root + '/boot-image/edk2-aarch64-code-2048x1536.fd' }
	first_disk := work + if second { '/wrong.raw' } else { '/volume.raw' }
	second_disk := work + if second { '/volume.raw' } else { '/wrong.raw' }
	return [qemu, '-machine', 'virt,gic-version=3', '-accel', if os.user_os() == 'macos' { 'hvf' } else { 'tcg' },
		'-cpu', if os.user_os() == 'macos' { 'host' } else { 'max' }, '-m', '1024', '-smp', '2',
		'-drive', 'if=pflash,format=raw,readonly=on,file=' + firmware,
		'-drive', 'if=pflash,format=raw,file=' + work + '/vars.fd', '-drive', 'format=raw,file=' + boot_image,
		'-drive', 'if=none,format=raw,id=config,file=' + work + '/config.ext2', '-device', 'virtio-blk-device,drive=config',
		'-drive', 'if=none,format=raw,id=wrong,file=' + second_disk, '-device', 'virtio-blk-device,drive=wrong',
		'-drive', 'if=none,format=raw,id=plan,file=' + first_disk, '-device', 'virtio-blk-device,drive=plan',
		'-object', 'rng-random,filename=/dev/urandom,id=storage-rng', '-device', 'virtio-rng-device,rng=storage-rng',
		'-device', 'virtio-keyboard-device', '-device', 'ramfb', '-display', 'none', '-monitor', 'none',
		'-serial', 'stdio', '-nic', 'none', '-no-reboot']
}

fn boot_timeout_seconds() !u64 {
	configured := os.getenv_opt('VINIX_STORAGE_BOOT_TIMEOUT') or { return 1800 }
	defer { unsafe { configured.free() } }
	if configured.len == 0 || configured.len > 8 { return error('VINIX_STORAGE_BOOT_TIMEOUT must be decimal seconds from 60 to 7200') }
	mut seconds := u64(0)
	for digit in configured {
		if digit < `0` || digit > `9` || seconds > 7200 { return error('VINIX_STORAGE_BOOT_TIMEOUT must be decimal seconds from 60 to 7200') }
		seconds = seconds * 10 + u64(digit - `0`)
	}
	if seconds < 60 || seconds > 7200 { return error('VINIX_STORAGE_BOOT_TIMEOUT must be decimal seconds from 60 to 7200') }
	return seconds
}

fn boot(args []string, log string) !string {
	timeout := boot_timeout_seconds()!
	mut capture := os.create(log)!
	defer { capture.close() }
	mut process := os.new_process(args[0])
	process.set_args(args[1..]); process.set_redirect_stdio(); process.run()
	if process.pid <= 0 { return error('Cannot start QEMU') }
	defer {
		if process.is_alive() { unsafe { C.kill(i32(process.pid), 9) }; process.wait() }
		process.close()
	}
	mut markers := bootcapture.Capture{}
	started := time.sys_mono_now()
	for process.is_alive() && time.sys_mono_now() - started < timeout * u64(time.second) {
		stdout := process.stdout_read()
		if stdout != '' { capture.write_string(stdout)!; markers.observe(stdout) }
		unsafe { stdout.free() }
		stderr := process.stderr_read()
		if stderr != '' { capture.write_string(stderr)!; markers.observe(stderr) }
		unsafe { stderr.free() }
		if markers.done { break }
		if markers.failed {
			// Let the kernel finish its diagnostic before terminating QEMU.
			time.sleep(time.second)
			break
		}
		time.sleep(10 * time.millisecond)
	}
	stdout := process.stdout_read()
	capture.write_string(stdout)!
	markers.observe(stdout)
	unsafe { stdout.free() }
	stderr := process.stderr_read()
	capture.write_string(stderr)!
	markers.observe(stderr)
	unsafe { stderr.free() }
	capture.flush()
	transcript := os.read_file(log)!
	if !transcript.contains('PLAN DONE') || markers.failed {
		return error('Guest qualification failed: see ${log}')
	}
	return transcript
}

fn guest(root string, work string, arch string, kernel string, nvme bool) ! {
	if kernel == '' || !os.is_file(kernel) { return error('Select an existing kernel with --kernel') }
	if work.contains(',') { return error('Work directory cannot contain QEMU option separators') }
	compile_guest(root, work, arch, nvme, '')!
	if nvme {
		nvme_disk(work + '/nvme.raw',0x81)!
		nvme_disk(work + '/nvme-warning.raw',0x82)!
	}
	write_disk(work + '/volume.raw', false)!
	write_disk(work + '/wrong.raw', true)!
	plan_filesystem(work)!
	pack(work)!
	args := if arch == 'aarch64' { arm_boot(root, work, kernel, false)! } else { amd64_boot(root, work, kernel, false, nvme)! }
	first := boot(args, work + '/first-boot.log')!
	if !first.contains('init: volume restore failed; continuing') { return error('Production init did not report its invalid boot plan and continue') }
	if !first.contains('PLAN SET PREFLIGHT PASSED') { return error('Missing multi-disk plan-set qualification') }
	if !first.contains('PLAN BUNDLE PASSED:') { return error('Missing atomic multi-disk bundle qualification') }
	if !first.contains('PLAN GROWTH PASSED:') { return error('Missing planned capacity growth qualification') }
	if !first.contains('PLAN CHECK PASSED:') { return error('Missing read-only bundle check qualification') }
	if !first.contains('PLAN EDIT PASSED:') { return error('Missing offline mapping edit qualification') }
	if !first.contains('PLAN DISKS PASSED:') { return error('Missing offline disk membership qualification') }
	if !first.contains('PLAN SPACE PASSED:') { return error('Missing bounded extent allocation qualification') }
	if !first.contains('PLAN POOLS PASSED:') { return error('Missing persistent allocation pool qualification') }
	if !first.contains('PLAN POOL GROWTH PASSED:') { return error('Missing pool expansion and bounded growth qualification') }
	if !first.contains('PLAN POOL BATCH PASSED:') { return error('Missing atomic pool batch qualification') }
	if !first.contains('PLAN POOL GROWTH BATCH PASSED:') { return error('Missing atomic pool growth batch qualification') }
	if !first.contains('PLAN POOL EXPANSION BATCH PASSED:') { return error('Missing atomic pool expansion batch qualification') }
	if !first.contains('PLAN CAPACITY BATCH PASSED:') { return error('Missing atomic physical capacity batch qualification') }
	if !first.contains('PLAN POOL MEMBERSHIP BATCH PASSED:') { return error('Missing atomic pool membership batch qualification') }
	if !first.contains('PLAN POOL PRIORITY PASSED:') { return error('Missing pool allocation priority qualification') }
	if !first.contains('PLAN REMOVAL BATCH PASSED:') { return error('Missing atomic mapping removal batch qualification') }
	if !first.contains('PLAN ENROLLMENT BATCH PASSED:') { return error('Missing atomic disk enrollment batch qualification') }
	if !first.contains('PLAN FORGET BATCH PASSED:') { return error('Missing atomic identity disk forget qualification') }
	if !first.contains('PLAN ADDITION BATCH PASSED:') { return error('Missing atomic explicit mapping addition qualification') }
	if !first.contains('PLAN EXPLICIT GROWTH BATCH PASSED:') { return error('Missing atomic explicit mapping growth qualification') }
	if !first.contains('PLAN POOL CONTRACTION BATCH PASSED:') { return error('Missing atomic pool contraction qualification') }
	if !first.contains('PLAN POOL RESIZE BATCH PASSED:') { return error('Missing atomic cross-pool resize qualification') }
	if !first.contains('PLAN CAPACITY CONTRACTION BATCH PASSED:') { return error('Missing identity-based physical contraction qualification') }
	if !first.contains('PLAN MULTI POOL BATCH PASSED:') { return error('Missing atomic multi-pool allocation qualification') }
	if !first.contains('PLAN MULTI POOL GROWTH PASSED:') { return error('Missing atomic multi-pool growth qualification') }
	if !first.contains('PLAN LOCK PASSED:') { return error('Missing saved-plan locking qualification') }
	if !first.contains('PLAN DATA PASSED:') { return error('Missing data checksum and corruption qualification') }
	if !first.contains('PLAN SCRUB PASSED:') { return error('Missing complete multi-corruption scrub report qualification') }
	if !first.contains('PLAN CRYPT PASSED:') || first.count('PLAN CRYPT CYCLES count=200') != 2 { return error('Missing encrypted volume IO and 400 import/remove cycles') }
	if !first.contains('PLAN RECOVERY PASSED:') || first.count('PLAN RECOVERY CYCLES count=200') != 2 { return error('Missing authenticated key recovery and 400 backup/recovery lifetimes') }
	if !first.contains('PLAN SEALED PASSED:') || first.count('PLAN SEALED CYCLES count=8') != 2
		|| !first.contains('PLAN SEALED LARGE ') || first.count('PLAN SEALED RETAIN ') == 0 { return error('Missing sealed-key unlock and full-cost scrypt retention qualification') }
	if !first.contains('PLAN REWRAP PASSED:') || first.count('PLAN REWRAP CYCLES count=4') != 2
		|| !first.contains('PLAN REWRAP LARGE ') || first.count('PLAN REWRAP RETAIN ') == 0 { return error('Missing credential rewrap and full-cost lifetime qualification') }
	if !first.contains('PLAN VOLUME SEAL PASSED:') || first.count('PLAN VOLUME SEAL CYCLES count=4') != 2
		|| !first.contains('PLAN VOLUME SEAL LARGE ') || first.count('PLAN VOLUME SEAL RETAIN ') == 0 { return error('Missing authenticated volume configuration and full-cost lifetimes') }
	if !first.contains('PLAN VOLUME REWRAP PASSED:') || first.count('PLAN VOLUME REWRAP CYCLES count=4') != 2
		|| !first.contains('PLAN VOLUME REWRAP LARGE ') || first.count('PLAN VOLUME REWRAP RETAIN ') == 0 { return error('Missing authenticated volume credential changes and full-cost lifetimes') }
	if !first.contains('PLAN VOLUME GROWTH PASSED:') || first.count('PLAN VOLUME GROWTH CYCLES count=4') != 2
		|| !first.contains('PLAN VOLUME GROWTH LARGE ') || first.count('PLAN VOLUME GROWTH RETAIN ') == 0 { return error('Missing authenticated encrypted growth and full-cost lifetimes') }
	if first.count('PLAN VOLUME BOOT CYCLES count=4') != 2 || !first.contains('PLAN VOLUME BOOT LARGE ')
		|| first.count('PLAN VOLUME BOOT RETAIN ') == 0 { return error('Missing full-cost encrypted boot unlock lifetimes') }
	if first.count('PLAN VOLUME BOOT SET CYCLES count=4') != 2 || !first.contains('PLAN VOLUME BOOT SET LARGE ')
		|| first.count('PLAN VOLUME BOOT SET RETAIN ') == 0 { return error('Missing full-cost encrypted boot set lifetimes') }
	if !first.contains('HEALTH QUERY PASSED') { return error('Missing physical health ABI qualification') }
	if !first.contains('STORAGE MONITOR PASSED:') { return error('Missing periodic storage monitor qualification') }
	if nvme && !first.contains('NVME HEALTH PASSED') { return error('Missing NVMe health ABI qualification') }
	if nvme && !first.contains('NVME MONITOR PASSED:') { return error('Missing NVMe monitor qualification') }
	mut encoded := ''
	for line in first.split_into_lines() { if line.starts_with('PLAN FILE ') { encoded = line.all_after('PLAN FILE ').trim_space() } }
	if encoded.len < 256 || encoded.len > 4224 { return error('Missing saved plan bytes in first boot') }
	os.write_file_array(work + '/saved-plan.vmap', hex.decode(encoded)!)!
	// The phase marker and plan stay on the guest's filesystem. No host copy
	// supplies either file to the second boot.
	second_args := if arch == 'aarch64' { arm_boot(root, work, kernel, true)! } else { amd64_boot(root, work, kernel, true, nvme)! }
	second := boot(second_args, work + '/second-boot.log')!
	if !second.contains('PLAN BOOT RESTORED') { return error('Production init did not restore before the application started') }
	if !second.contains('PLAN POOL BOOT PRESERVED') { return error('Pool configuration did not survive reordered boot') }
	if !second.contains('PLAN DATA BOOT VERIFIED') { return error('Data manifest did not verify across reordered boot') }
	if !second.contains('PLAN SCRUB REORDERED BOOT PRESERVED') { return error('Scrub report failed after physical device reorder') }
	if !second.contains('PLAN CRYPT REORDERED BOOT PRESERVED') { return error('Encrypted ciphertext/key reopen failed after physical device reorder') }
	if !second.contains('PLAN RECOVERY REORDERED BOOT PRESERVED') { return error('Key recovery failed after original key deletion and physical reorder') }
	if !second.contains('PLAN SEALED REORDERED BOOT PRESERVED') { return error('Passphrase unlock failed after raw key deletion and physical reorder') }
	if !second.contains('PLAN REWRAP REORDERED BOOT PRESERVED') { return error('Rewrapped passphrase unlock failed after raw key deletion and physical reorder') }
	if !second.contains('PLAN VOLUME SEAL REORDERED BOOT PRESERVED') { return error('Authenticated configuration failed after device reorder and raw-key deletion') }
	if !second.contains('PLAN VOLUME REWRAP REORDERED BOOT PRESERVED') { return error('Rewrapped configuration failed after device reorder and raw-key deletion') }
	if !second.contains('PLAN VOLUME GROWTH REORDERED BOOT PRESERVED') { return error('Grown encrypted configuration failed after device reorder') }
	if !second.contains('PLAN VOLUME BOOT INIT RESTORED: bytes=8192') || !second.contains('PLAN VOLUME BOOT PASSED:') { return error('Production init did not unlock the private encrypted boot configuration') }
	if !second.contains('PLAN VOLUME BOOT SET INIT RESTORED:') || !second.contains('PLAN VOLUME BOOT SET PASSED:') { return error('Production init did not restore independent encrypted boot volumes') }
	// Enlarge the existing disposable backing file without changing its MBR or
	// prior bytes. The saved bundle and all guest files remain guest-produced.
	mut disk := os.open_file(work + '/volume.raw', 'r+')!
	disk.seek(24 * 1024 * 1024 - 1, .start)!
	disk.write([u8(0)])!
	disk.close()
	third := boot(second_args, work + '/capacity-boot.log')!
	if !third.contains('init: volume restore failed; continuing') || !third.contains('PLAN CAPACITY PASSED:') {
		return error('Missing rejection of old geometry or explicit physical capacity adoption')
	}
	if !third.contains('PLAN VOLUME SEAL CHANGED CAPACITY REFUSED') { return error('Sealed configuration did not reject changed physical capacity') }
	if !third.contains('PLAN VOLUME REWRAP CHANGED CAPACITY REFUSED') { return error('Rewrapped configuration did not reject changed physical capacity') }
	if !third.contains('PLAN VOLUME GROWTH CAPACITY ADOPTED') { return error('Encrypted configuration did not adopt physical capacity preserving ciphertext') }
	if !third.contains('PLAN VOLUME BOOT CHANGED CAPACITY REFUSED') { return error('Encrypted boot configuration accepted changed physical capacity') }
	if !third.contains('PLAN VOLUME BOOT SET CHANGED CAPACITY REFUSED') { return error('Partial encrypted boot set accepted changed capacity') }
	fourth := boot(second_args, work + '/capacity-restored-boot.log')!
	if !fourth.contains('PLAN CAPACITY BOOT RESTORED:') || fourth.contains('init: volume restore failed; continuing') {
		return error('Production init did not restore the adopted physical capacity')
	}
	if !fourth.contains('PLAN POOL BOOT PRESERVED') { return error('Pool configuration did not survive capacity adoption and boot') }
	if !fourth.contains('PLAN VOLUME GROWTH CAPACITY BOOT PRESERVED') { return error('Encrypted capacity configuration did not survive reboot') }
	if !fourth.contains('PLAN VOLUME BOOT INIT RESTORED: bytes=12288') { return error('Production init did not unlock the adopted encrypted capacity') }
	if !fourth.contains('PLAN VOLUME BOOT SET INIT RESTORED:') { return error('Production init did not restore the unchanged second encrypted disk') }
	if !fourth.contains('PLAN POOL GROWTH BOOT PRESERVED') { return error('Expanded tail pool did not survive boot') }
	if !fourth.contains('PLAN POOL BATCH BOOT PRESERVED') { return error('Mixed batch tail mapping did not survive boot') }
	if !fourth.contains('PLAN POOL GROWTH BATCH BOOT PRESERVED') { return error('Growth batch tail mapping did not survive boot') }
	if !fourth.contains('PLAN POOL EXPANSION BATCH BOOT PRESERVED') { return error('Expansion batch tail region did not survive boot') }
	if !fourth.contains('PLAN CAPACITY BATCH BOOT PRESERVED') { return error('Capacity batch geometry did not survive boot') }
	if !fourth.contains('PLAN POOL MEMBERSHIP BATCH BOOT PRESERVED') { return error('Membership batch priority and desired state did not survive boot') }
	if !fourth.contains('PLAN POOL PRIORITY BOOT PRESERVED') { return error('Pool allocation priority did not survive boot') }
	if !third.contains('PLAN REMOVAL BATCH SAVED:') || !fourth.contains('PLAN REMOVAL BATCH BOOT PRESERVED') { return error('Desired mapping removals did not survive boot') }
	if !third.contains('PLAN ENROLLMENT BATCH SAVED:') || !fourth.contains('PLAN ENROLLMENT BATCH BOOT PRESERVED') { return error('Disk enrollment batch did not survive boot') }
	if !third.contains('PLAN FORGET BATCH SAVED:') || !fourth.contains('PLAN FORGET BATCH BOOT PRESERVED') { return error('Disk forget compaction did not survive boot') }
	if !third.contains('PLAN ADDITION BATCH SAVED:') || !fourth.contains('PLAN ADDITION BATCH BOOT PRESERVED') { return error('Explicit mapping additions did not survive boot') }
	if !third.contains('PLAN EXPLICIT GROWTH BATCH SAVED:') || !fourth.contains('PLAN EXPLICIT GROWTH BATCH BOOT PRESERVED') { return error('Explicit mapping growth did not survive boot') }
	if !third.contains('PLAN POOL CONTRACTION BATCH SAVED:') || !fourth.contains('PLAN POOL CONTRACTION BATCH BOOT PRESERVED') { return error('Pool contraction did not survive boot') }
	if !third.contains('PLAN POOL RESIZE BATCH SAVED:') || !fourth.contains('PLAN POOL RESIZE BATCH BOOT PRESERVED') { return error('Cross-pool resize did not survive boot') }
	if !fourth.contains('PLAN CAPACITY CONTRACTION PREPARED:') { return error('Missing bounded contraction candidate') }
	// Preserve the completed growth qualification before shrinking only the
	// disposable physical backing. Guest plans stay on their own filesystem.
	os.cp(work + '/config.ext2', work + '/expanded-config.ext2')!
	os.cp(work + '/volume.raw', work + '/volume-grown.raw')!
	shrink_disk(work + '/volume.raw', 20 * 1024 * 1024)!
	fifth := boot(second_args, work + '/capacity-contracted-boot.log')!
	if !fifth.contains('init: volume restore failed; continuing') || !fifth.contains('PLAN CAPACITY CONTRACTION SAVED:') {
		return error('Missing old-geometry rejection or verified physical contraction')
	}
	if !fifth.contains('PLAN VOLUME GROWTH PHYSICAL CONTRACTION REFUSED') { return error('Encrypted capacity configuration accepted physical contraction') }
	if !fifth.contains('PLAN VOLUME BOOT CHANGED CAPACITY REFUSED') { return error('Encrypted boot configuration accepted physical contraction') }
	if !fifth.contains('PLAN VOLUME BOOT SET CHANGED CAPACITY REFUSED') { return error('Partial encrypted boot set accepted physical contraction') }
	sixth := boot(second_args, work + '/capacity-contract-restored-boot.log')!
	if sixth.contains('init: volume restore failed; continuing') || !sixth.contains('PLAN CAPACITY CONTRACT BOOT RESTORED:')
		|| !sixth.contains('PLAN CAPACITY CONTRACTION BOOT PRESERVED') {
		return error('Production init did not restore contracted geometry and preserved mappings')
	}
	if !sixth.contains('PLAN MULTI POOL BATCH SAVED:') { return error('Missing persistent multi-pool placements') }
	// Retain the completed six-boot evidence before new rows become the boot plan.
	os.cp(work + '/config.ext2', work + '/contracted-config.ext2')!
	seventh := boot(second_args, work + '/multi-pool-restored-boot.log')!
	if seventh.contains('init: volume restore failed; continuing') || !seventh.contains('PLAN MULTI POOL BATCH BOOT PRESERVED') {
		return error('Production init did not restore the complete multi-pool allocation')
	}
	if !seventh.contains('PLAN MULTI POOL GROWTH SAVED:') { return error('Missing persistent multi-pool growth') }
	os.cp(work + '/config.ext2', work + '/multi-pool-config.ext2')!
	eighth := boot(second_args, work + '/multi-growth-restored-boot.log')!
	if eighth.contains('init: volume restore failed; continuing') || !eighth.contains('PLAN MULTI POOL GROWTH BOOT PRESERVED') {
		return error('Production init did not restore complete multi-pool growth')
	}
	if !eighth.contains('PLAN DATA SAVED:') { return error('Missing persisted nine-mapping checksum manifest') }
	if !eighth.contains('PLAN SCRUB SAVED:') { return error('Missing persisted nine-mapping scrub report') }
	os.cp(work + '/config.ext2', work + '/data-config.ext2')!
	ninth := boot(second_args, work + '/data-restored-boot.log')!
	if ninth.contains('init: volume restore failed; continuing') || !ninth.contains('PLAN DATA BOOT PRESERVED') { return error('Data checksum verification failed after production boot') }
	if !ninth.contains('PLAN SCRUB BOOT PRESERVED') { return error('Persistent scrub report failed after production boot') }
	println('PASS ${arch}: complete scrub findings, SHA-256 data manifests, atomic multi-pool allocation/growth, physical capacity/pool batches, previews/retries, saved-plan locks, complete preflight, nine-boot persistence and 200-cycle retention')
}

fn main() {
	mut options := map[string]string{}
	mut is_host := false
	mut nvme := false
	mut recovery := false
	mut recovery_unlock := false
	mut focused_host := false
	mut rewrap_host := false
	mut recovery_rewrap := false
	mut growth_host := false
	mut recovery_growth := false
	mut inspect_host := false
	mut recovery_inspect := false
	mut volume_inspect_host_only := false
	mut volume_inspect := false
	mut preview_host := false
	mut growth_preview := false
	mut ciphertext_host_only := false
	mut ciphertext := false
	mut ciphertext_scrub_host_only := false
	mut ciphertext_scrub := false
	mut scrub_compare_host_only := false
	mut scrub_compare := false
	mut auto_scrub_host_only := false
	mut auto_scrub := false
	mut ciphertext_auto_host_only := false
	mut ciphertext_auto := false
	mut reference_host_only := false
	mut reference := false
	mut data_auto_host_only := false
	mut data_auto := false
	mut data_reference_host_only := false
	mut data_reference := false
	mut data_scrub_view_host_only := false
	mut data_scrub_view := false
	mut data_scrub_history_host_only := false
	mut data_scrub_history := false
	mut scrub_reference_host_only := false
	mut scrub_reference := false
	mut cipher_scrub_reference_host_only := false
	mut cipher_scrub_reference := false
	mut data_monitor_host_only := false
	mut data_monitor := false
	mut cipher_monitor_host_only := false
	mut cipher_monitor := false
	mut data_monitor_verify_host_only := false
	mut data_monitor_verify := false
	mut cipher_monitor_verify_host_only := false
	mut cipher_monitor_verify := false
	mut file_backup_host_only := false
	mut file_backup := false
	mut index := 1
	for index < os.args.len {
		name := os.args[index]
		if name == '--host' { is_host = true; index++; continue }
		if name == '--host-recovery-unlock' { is_host = true; focused_host = true; index++; continue }
		if name == '--host-recovery-rewrap' { is_host = true; rewrap_host = true; index++; continue }
		if name == '--host-recovery-growth' { is_host = true; growth_host = true; index++; continue }
		if name == '--host-recovery-inspect' { is_host = true; inspect_host = true; index++; continue }
		if name == '--host-volume-inspect' { is_host = true; volume_inspect_host_only = true; index++; continue }
		if name == '--volume-inspect' { volume_inspect = true; index++; continue }
		if name == '--host-growth-preview' { is_host = true; preview_host = true; index++; continue }
		if name == '--growth-preview' { growth_preview = true; index++; continue }
		if name == '--host-ciphertext' { is_host = true; ciphertext_host_only = true; index++; continue }
		if name == '--ciphertext' { ciphertext = true; index++; continue }
		if name == '--host-ciphertext-scrub' { is_host = true; ciphertext_scrub_host_only = true; index++; continue }
		if name == '--ciphertext-scrub' { ciphertext_scrub = true; index++; continue }
		if name == '--host-scrub-compare' { is_host = true; scrub_compare_host_only = true; index++; continue }
		if name == '--scrub-compare' { scrub_compare = true; index++; continue }
		if name == '--host-auto-scrub' { is_host = true; auto_scrub_host_only = true; index++; continue }
		if name == '--auto-scrub' { auto_scrub = true; index++; continue }
		if name == '--host-ciphertext-auto' { is_host = true; ciphertext_auto_host_only = true; index++; continue }
		if name == '--ciphertext-auto' { ciphertext_auto = true; index++; continue }
		if name == '--host-reference' { is_host = true; reference_host_only = true; index++; continue }
		if name == '--reference' { reference = true; index++; continue }
		if name == '--host-data-auto' { is_host = true; data_auto_host_only = true; index++; continue }
		if name == '--data-auto' { data_auto = true; index++; continue }
		if name == '--host-data-reference' { is_host = true; data_reference_host_only = true; index++; continue }
		if name == '--data-reference' { data_reference = true; index++; continue }
		if name == '--host-data-scrub-view' { is_host = true; data_scrub_view_host_only = true; index++; continue }
		if name == '--data-scrub-view' { data_scrub_view = true; index++; continue }
		if name == '--host-data-scrub-history' { is_host = true; data_scrub_history_host_only = true; index++; continue }
		if name == '--data-scrub-history' { data_scrub_history = true; index++; continue }
		if name == '--host-scrub-reference' { is_host = true; scrub_reference_host_only = true; index++; continue }
		if name == '--scrub-reference' { scrub_reference = true; index++; continue }
		if name == '--host-cipher-scrub-reference' { is_host = true; cipher_scrub_reference_host_only = true; index++; continue }
		if name == '--cipher-scrub-reference' { cipher_scrub_reference = true; index++; continue }
		if name == '--host-data-monitor' { is_host = true; data_monitor_host_only = true; index++; continue }
		if name == '--data-monitor' { data_monitor = true; index++; continue }
		if name == '--host-cipher-monitor' { is_host = true; cipher_monitor_host_only = true; index++; continue }
		if name == '--cipher-monitor' { cipher_monitor = true; index++; continue }
		if name == '--host-data-monitor-verify' { is_host = true; data_monitor_verify_host_only = true; index++; continue }
		if name == '--data-monitor-verify' { data_monitor_verify = true; index++; continue }
		if name == '--host-cipher-monitor-verify' { is_host = true; cipher_monitor_verify_host_only = true; index++; continue }
		if name == '--cipher-monitor-verify' { cipher_monitor_verify = true; index++; continue }
		if name == '--host-file-backup' { is_host = true; file_backup_host_only = true; index++; continue }
		if name == '--file-backup' { file_backup = true; index++; continue }
		if name == '--nvme' { nvme = true; index++; continue }
		if name == '--volume-recovery' { recovery = true; index++; continue }
		if name == '--recovery-unlock' { recovery_unlock = true; index++; continue }
		if name == '--recovery-rewrap' { recovery_rewrap = true; index++; continue }
		if name == '--recovery-growth' { recovery_growth = true; index++; continue }
		if name == '--recovery-inspect' { recovery_inspect = true; index++; continue }
		if name !in ['--arch', '--work', '--kernel'] || index + 1 >= os.args.len || name in options {
			eprintln('Usage: plan_run.v --work NEW_DIRECTORY [--host | --host-recovery-unlock | --host-recovery-rewrap | --host-recovery-growth | --host-recovery-inspect | --host-volume-inspect | --host-growth-preview | --host-ciphertext | --host-ciphertext-scrub | --host-scrub-compare | --host-auto-scrub | --host-ciphertext-auto | --host-reference | --host-data-auto | --host-data-reference | --host-data-scrub-view | --host-data-scrub-history | --host-scrub-reference | --host-cipher-scrub-reference | --host-data-monitor | --host-cipher-monitor | --host-data-monitor-verify | --host-cipher-monitor-verify | --host-file-backup | --arch amd64|aarch64 --kernel KERNEL [--nvme | --volume-recovery | --recovery-unlock | --recovery-rewrap | --recovery-growth | --recovery-inspect | --volume-inspect | --growth-preview | --ciphertext | --ciphertext-scrub | --scrub-compare | --auto-scrub | --ciphertext-auto | --reference | --data-auto | --data-reference | --data-scrub-view | --data-scrub-history | --scrub-reference | --cipher-scrub-reference | --data-monitor | --cipher-monitor | --data-monitor-verify | --cipher-monitor-verify | --file-backup]]'); exit(2)
		}
		options[name] = os.args[index + 1]; index += 2
	}
	if (file_backup_host_only || file_backup) && (nvme || recovery || recovery_unlock || focused_host || rewrap_host || recovery_rewrap || growth_host || recovery_growth || inspect_host || recovery_inspect || volume_inspect_host_only || volume_inspect || preview_host || growth_preview || ciphertext_host_only || ciphertext || ciphertext_scrub_host_only || ciphertext_scrub || scrub_compare_host_only || scrub_compare || auto_scrub_host_only || auto_scrub || ciphertext_auto_host_only || ciphertext_auto || reference_host_only || reference || data_auto_host_only || data_auto || data_reference_host_only || data_reference || data_scrub_view_host_only || data_scrub_view || data_scrub_history_host_only || data_scrub_history || scrub_reference_host_only || scrub_reference || cipher_scrub_reference_host_only || cipher_scrub_reference || data_monitor_host_only || data_monitor || cipher_monitor_host_only || cipher_monitor || data_monitor_verify_host_only || data_monitor_verify || cipher_monitor_verify_host_only || cipher_monitor_verify || (file_backup && is_host) || (file_backup && file_backup_host_only)) { eprintln('Select exactly one file backup qualification mode'); exit(2) }
	work := os.abs_path(options['--work'])
	if options['--work'] == '' || os.exists(work) || (!is_host && options['--arch'] !in ['amd64', 'aarch64'])
		|| (nvme && (is_host || options['--arch'] != 'amd64')) || (recovery && (is_host || nvme))
		|| (recovery_unlock && (is_host || nvme || recovery))
		|| (recovery_rewrap && (is_host || nvme || recovery || recovery_unlock)) || (rewrap_host && focused_host)
		|| (recovery_growth && (is_host || nvme || recovery || recovery_unlock || recovery_rewrap)) || (growth_host && (rewrap_host || focused_host))
		|| (recovery_inspect && (is_host || nvme || recovery || recovery_unlock || recovery_rewrap || recovery_growth))
		|| (inspect_host && (focused_host || rewrap_host || growth_host))
		|| (volume_inspect && (is_host || nvme || recovery || recovery_unlock || recovery_rewrap || recovery_growth || recovery_inspect))
		|| (volume_inspect_host_only && (focused_host || rewrap_host || growth_host || inspect_host))
		|| (growth_preview && (is_host || nvme || recovery || recovery_unlock || recovery_rewrap || recovery_growth || recovery_inspect || volume_inspect))
		|| (preview_host && (focused_host || rewrap_host || growth_host || inspect_host || volume_inspect_host_only))
		|| (ciphertext && (is_host || nvme || recovery || recovery_unlock || recovery_rewrap || recovery_growth || recovery_inspect || volume_inspect || growth_preview))
		|| (ciphertext_host_only && (focused_host || rewrap_host || growth_host || inspect_host || volume_inspect_host_only || preview_host))
		|| (ciphertext_scrub && (is_host || nvme || recovery || recovery_unlock || recovery_rewrap || recovery_growth || recovery_inspect || volume_inspect || growth_preview || ciphertext))
		|| (ciphertext_scrub_host_only && (focused_host || rewrap_host || growth_host || inspect_host || volume_inspect_host_only || preview_host || ciphertext_host_only))
		|| (scrub_compare && (is_host || nvme || recovery || recovery_unlock || recovery_rewrap || recovery_growth || recovery_inspect || volume_inspect || growth_preview || ciphertext || ciphertext_scrub))
		|| (scrub_compare_host_only && (focused_host || rewrap_host || growth_host || inspect_host || volume_inspect_host_only || preview_host || ciphertext_host_only || ciphertext_scrub_host_only))
		|| (auto_scrub && (is_host || nvme || recovery || recovery_unlock || recovery_rewrap || recovery_growth || recovery_inspect || volume_inspect || growth_preview || ciphertext || ciphertext_scrub || scrub_compare))
		|| (auto_scrub_host_only && (focused_host || rewrap_host || growth_host || inspect_host || volume_inspect_host_only || preview_host || ciphertext_host_only || ciphertext_scrub_host_only || scrub_compare_host_only))
		|| (ciphertext_auto && (is_host || nvme || recovery || recovery_unlock || recovery_rewrap || recovery_growth || recovery_inspect || volume_inspect || growth_preview || ciphertext || ciphertext_scrub || scrub_compare || auto_scrub))
		|| (ciphertext_auto_host_only && (focused_host || rewrap_host || growth_host || inspect_host || volume_inspect_host_only || preview_host || ciphertext_host_only || ciphertext_scrub_host_only || scrub_compare_host_only || auto_scrub_host_only))
		|| (reference && (is_host || nvme || recovery || recovery_unlock || recovery_rewrap || recovery_growth || recovery_inspect || volume_inspect || growth_preview || ciphertext || ciphertext_scrub || scrub_compare || auto_scrub || ciphertext_auto))
		|| (reference_host_only && (focused_host || rewrap_host || growth_host || inspect_host || volume_inspect_host_only || preview_host || ciphertext_host_only || ciphertext_scrub_host_only || scrub_compare_host_only || auto_scrub_host_only || ciphertext_auto_host_only))
		|| (data_auto && (is_host || nvme || recovery || recovery_unlock || recovery_rewrap || recovery_growth || recovery_inspect || volume_inspect || growth_preview || ciphertext || ciphertext_scrub || scrub_compare || auto_scrub || ciphertext_auto || reference))
		|| (data_auto_host_only && (focused_host || rewrap_host || growth_host || inspect_host || volume_inspect_host_only || preview_host || ciphertext_host_only || ciphertext_scrub_host_only || scrub_compare_host_only || auto_scrub_host_only || ciphertext_auto_host_only || reference_host_only))
		|| (data_reference && (is_host || nvme || recovery || recovery_unlock || recovery_rewrap || recovery_growth || recovery_inspect || volume_inspect || growth_preview || ciphertext || ciphertext_scrub || scrub_compare || auto_scrub || ciphertext_auto || reference || data_auto))
		|| (data_reference_host_only && (focused_host || rewrap_host || growth_host || inspect_host || volume_inspect_host_only || preview_host || ciphertext_host_only || ciphertext_scrub_host_only || scrub_compare_host_only || auto_scrub_host_only || ciphertext_auto_host_only || reference_host_only || data_auto_host_only))
		|| (data_scrub_view && (is_host || nvme || recovery || recovery_unlock || recovery_rewrap || recovery_growth || recovery_inspect || volume_inspect || growth_preview || ciphertext || ciphertext_scrub || scrub_compare || auto_scrub || ciphertext_auto || reference || data_auto || data_reference))
		|| (data_scrub_view_host_only && (focused_host || rewrap_host || growth_host || inspect_host || volume_inspect_host_only || preview_host || ciphertext_host_only || ciphertext_scrub_host_only || scrub_compare_host_only || auto_scrub_host_only || ciphertext_auto_host_only || reference_host_only || data_auto_host_only || data_reference_host_only))
		|| (data_scrub_history && (is_host || nvme || recovery || recovery_unlock || recovery_rewrap || recovery_growth || recovery_inspect || volume_inspect || growth_preview || ciphertext || ciphertext_scrub || scrub_compare || auto_scrub || ciphertext_auto || reference || data_auto || data_reference || data_scrub_view))
		|| (data_scrub_history_host_only && (focused_host || rewrap_host || growth_host || inspect_host || volume_inspect_host_only || preview_host || ciphertext_host_only || ciphertext_scrub_host_only || scrub_compare_host_only || auto_scrub_host_only || ciphertext_auto_host_only || reference_host_only || data_auto_host_only || data_reference_host_only || data_scrub_view_host_only))
		|| (scrub_reference && (is_host || nvme || recovery || recovery_unlock || recovery_rewrap || recovery_growth || recovery_inspect || volume_inspect || growth_preview || ciphertext || ciphertext_scrub || scrub_compare || auto_scrub || ciphertext_auto || reference || data_auto || data_reference || data_scrub_view || data_scrub_history))
		|| (scrub_reference_host_only && (focused_host || rewrap_host || growth_host || inspect_host || volume_inspect_host_only || preview_host || ciphertext_host_only || ciphertext_scrub_host_only || scrub_compare_host_only || auto_scrub_host_only || ciphertext_auto_host_only || reference_host_only || data_auto_host_only || data_reference_host_only || data_scrub_view_host_only || data_scrub_history_host_only))
		|| (cipher_scrub_reference && (is_host || nvme || recovery || recovery_unlock || recovery_rewrap || recovery_growth || recovery_inspect || volume_inspect || growth_preview || ciphertext || ciphertext_scrub || scrub_compare || auto_scrub || ciphertext_auto || reference || data_auto || data_reference || data_scrub_view || data_scrub_history || scrub_reference))
		|| (cipher_scrub_reference_host_only && (focused_host || rewrap_host || growth_host || inspect_host || volume_inspect_host_only || preview_host || ciphertext_host_only || ciphertext_scrub_host_only || scrub_compare_host_only || auto_scrub_host_only || ciphertext_auto_host_only || reference_host_only || data_auto_host_only || data_reference_host_only || data_scrub_view_host_only || data_scrub_history_host_only || scrub_reference_host_only))
		|| (data_monitor && (is_host || nvme || recovery || recovery_unlock || recovery_rewrap || recovery_growth || recovery_inspect || volume_inspect || growth_preview || ciphertext || ciphertext_scrub || scrub_compare || auto_scrub || ciphertext_auto || reference || data_auto || data_reference || data_scrub_view || data_scrub_history || scrub_reference || cipher_scrub_reference))
		|| (data_monitor_host_only && (focused_host || rewrap_host || growth_host || inspect_host || volume_inspect_host_only || preview_host || ciphertext_host_only || ciphertext_scrub_host_only || scrub_compare_host_only || auto_scrub_host_only || ciphertext_auto_host_only || reference_host_only || data_auto_host_only || data_reference_host_only || data_scrub_view_host_only || data_scrub_history_host_only || scrub_reference_host_only || cipher_scrub_reference_host_only))
		|| (cipher_monitor && (is_host || nvme || recovery || recovery_unlock || recovery_rewrap || recovery_growth || recovery_inspect || volume_inspect || growth_preview || ciphertext || ciphertext_scrub || scrub_compare || auto_scrub || ciphertext_auto || reference || data_auto || data_reference || data_scrub_view || data_scrub_history || scrub_reference || cipher_scrub_reference || data_monitor))
		|| (cipher_monitor_host_only && (focused_host || rewrap_host || growth_host || inspect_host || volume_inspect_host_only || preview_host || ciphertext_host_only || ciphertext_scrub_host_only || scrub_compare_host_only || auto_scrub_host_only || ciphertext_auto_host_only || reference_host_only || data_auto_host_only || data_reference_host_only || data_scrub_view_host_only || data_scrub_history_host_only || scrub_reference_host_only || cipher_scrub_reference_host_only || data_monitor_host_only))
		|| (data_monitor_verify && (is_host || nvme || recovery || recovery_unlock || recovery_rewrap || recovery_growth || recovery_inspect || volume_inspect || growth_preview || ciphertext || ciphertext_scrub || scrub_compare || auto_scrub || ciphertext_auto || reference || data_auto || data_reference || data_scrub_view || data_scrub_history || scrub_reference || cipher_scrub_reference || data_monitor || cipher_monitor))
		|| (data_monitor_verify_host_only && (focused_host || rewrap_host || growth_host || inspect_host || volume_inspect_host_only || preview_host || ciphertext_host_only || ciphertext_scrub_host_only || scrub_compare_host_only || auto_scrub_host_only || ciphertext_auto_host_only || reference_host_only || data_auto_host_only || data_reference_host_only || data_scrub_view_host_only || data_scrub_history_host_only || scrub_reference_host_only || cipher_scrub_reference_host_only || data_monitor_host_only || cipher_monitor_host_only))
		|| (cipher_monitor_verify && (is_host || nvme || recovery || recovery_unlock || recovery_rewrap || recovery_growth || recovery_inspect || volume_inspect || growth_preview || ciphertext || ciphertext_scrub || scrub_compare || auto_scrub || ciphertext_auto || reference || data_auto || data_reference || data_scrub_view || data_scrub_history || scrub_reference || cipher_scrub_reference || data_monitor || cipher_monitor || data_monitor_verify))
		|| (cipher_monitor_verify_host_only && (focused_host || rewrap_host || growth_host || inspect_host || volume_inspect_host_only || preview_host || ciphertext_host_only || ciphertext_scrub_host_only || scrub_compare_host_only || auto_scrub_host_only || ciphertext_auto_host_only || reference_host_only || data_auto_host_only || data_reference_host_only || data_scrub_view_host_only || data_scrub_history_host_only || scrub_reference_host_only || cipher_scrub_reference_host_only || data_monitor_host_only || cipher_monitor_host_only || data_monitor_verify_host_only)) {
		eprintln('Select a new private work directory and supported architecture'); exit(2)
	}
	os.mkdir(work) or { eprintln(err); exit(1) }
	root := os.dir(os.dir(os.dir(@FILE)))
	if file_backup_host_only { file_backup_host(root, work) or { eprintln(err); exit(1) } }
	else if cipher_monitor_verify_host_only { cipher_monitor_verify_host(root, work) or { eprintln(err); exit(1) } }
	else if data_monitor_verify_host_only { data_monitor_verify_host(root, work) or { eprintln(err); exit(1) } }
	else if cipher_monitor_host_only { cipher_monitor_host(root, work) or { eprintln(err); exit(1) } }
	else if data_monitor_host_only { data_monitor_host(root, work) or { eprintln(err); exit(1) } }
	else if cipher_scrub_reference_host_only { cipher_scrub_reference_host(root, work) or { eprintln(err); exit(1) } }
	else if scrub_reference_host_only { scrub_reference_host(root, work) or { eprintln(err); exit(1) } }
	else if data_scrub_history_host_only { data_scrub_history_host(root, work) or { eprintln(err); exit(1) } }
	else if data_scrub_view_host_only { data_scrub_view_host(root, work) or { eprintln(err); exit(1) } }
	else if data_reference_host_only { data_reference_host(root, work) or { eprintln(err); exit(1) } }
	else if data_auto_host_only { data_auto_host(root, work) or { eprintln(err); exit(1) } }
	else if reference_host_only { reference_host(root, work) or { eprintln(err); exit(1) } }
	else if ciphertext_auto_host_only { ciphertext_auto_host(root, work) or { eprintln(err); exit(1) } }
	else if auto_scrub_host_only { auto_scrub_host(root, work) or { eprintln(err); exit(1) } }
	else if scrub_compare_host_only { scrub_compare_host(root, work) or { eprintln(err); exit(1) } }
	else if ciphertext_scrub_host_only { ciphertext_scrub_host(root, work) or { eprintln(err); exit(1) } }
	else if ciphertext_host_only { ciphertext_host(root, work) or { eprintln(err); exit(1) } }
	else if preview_host { growth_preview_host(root, work) or { eprintln(err); exit(1) } }
	else if volume_inspect_host_only { volume_inspect_host(root, work) or { eprintln(err); exit(1) } }
	else if inspect_host { recovery_inspect_host(root, work) or { eprintln(err); exit(1) } }
	else if growth_host { recovery_growth_host(root, work) or { eprintln(err); exit(1) } }
	else if rewrap_host { recovery_rewrap_host(root, work) or { eprintln(err); exit(1) } }
	else if focused_host { recovery_unlock_host(root, work) or { eprintln(err); exit(1) } }
	else if is_host { host(root, work) or { eprintln(err); exit(1) } }
	else if file_backup { file_backup_guest(root, work, options['--arch'], os.real_path(options['--kernel'])) or { eprintln(err); exit(1) } }
	else if cipher_monitor_verify { cipher_monitor_verify_guest(root, work, options['--arch'], os.real_path(options['--kernel'])) or { eprintln(err); exit(1) } }
	else if data_monitor_verify { data_monitor_verify_guest(root, work, options['--arch'], os.real_path(options['--kernel'])) or { eprintln(err); exit(1) } }
	else if cipher_monitor { cipher_monitor_guest(root, work, options['--arch'], os.real_path(options['--kernel'])) or { eprintln(err); exit(1) } }
	else if data_monitor { data_monitor_guest(root, work, options['--arch'], os.real_path(options['--kernel'])) or { eprintln(err); exit(1) } }
	else if cipher_scrub_reference { cipher_scrub_reference_guest(root, work, options['--arch'], os.real_path(options['--kernel'])) or { eprintln(err); exit(1) } }
	else if scrub_reference { scrub_reference_guest(root, work, options['--arch'], os.real_path(options['--kernel'])) or { eprintln(err); exit(1) } }
	else if data_scrub_history { data_scrub_history_guest(root, work, options['--arch'], os.real_path(options['--kernel'])) or { eprintln(err); exit(1) } }
	else if data_scrub_view { data_scrub_view_guest(root, work, options['--arch'], os.real_path(options['--kernel'])) or { eprintln(err); exit(1) } }
	else if data_reference { data_reference_guest(root, work, options['--arch'], os.real_path(options['--kernel'])) or { eprintln(err); exit(1) } }
	else if data_auto { data_auto_guest(root, work, options['--arch'], os.real_path(options['--kernel'])) or { eprintln(err); exit(1) } }
	else if reference { reference_guest(root, work, options['--arch'], os.real_path(options['--kernel'])) or { eprintln(err); exit(1) } }
	else if ciphertext_auto { ciphertext_auto_guest(root, work, options['--arch'], os.real_path(options['--kernel'])) or { eprintln(err); exit(1) } }
	else if auto_scrub { auto_scrub_guest(root, work, options['--arch'], os.real_path(options['--kernel'])) or { eprintln(err); exit(1) } }
	else if scrub_compare { scrub_compare_guest(root, work, options['--arch'], os.real_path(options['--kernel'])) or { eprintln(err); exit(1) } }
	else if ciphertext_scrub { ciphertext_scrub_guest(root, work, options['--arch'], os.real_path(options['--kernel'])) or { eprintln(err); exit(1) } }
	else if ciphertext { ciphertext_guest(root, work, options['--arch'], os.real_path(options['--kernel'])) or { eprintln(err); exit(1) } }
	else if growth_preview { growth_preview_guest(root, work, options['--arch'], os.real_path(options['--kernel'])) or { eprintln(err); exit(1) } }
	else if volume_inspect { volume_inspect_guest(root, work, options['--arch'], os.real_path(options['--kernel'])) or { eprintln(err); exit(1) } }
	else if recovery_inspect { recovery_inspect_guest(root, work, options['--arch'], os.real_path(options['--kernel'])) or { eprintln(err); exit(1) } }
	else if recovery_growth { recovery_growth_guest(root, work, options['--arch'], os.real_path(options['--kernel'])) or { eprintln(err); exit(1) } }
	else if recovery_rewrap { recovery_rewrap_guest(root, work, options['--arch'], os.real_path(options['--kernel'])) or { eprintln(err); exit(1) } }
	else if recovery_unlock { recovery_unlock_guest(root, work, options['--arch'], os.real_path(options['--kernel'])) or { eprintln(err); exit(1) } }
	else if recovery { volume_recovery_guest(root, work, options['--arch'], os.real_path(options['--kernel'])) or { eprintln(err); exit(1) } }
	else { guest(root, work, options['--arch'], os.real_path(options['--kernel']), nvme) or { eprintln(err); exit(1) } }
}

// Targeted recovery qualification uses the same production init, volume tool,
// pinned physical disks and QEMU transport, followed by reordered reboot.
fn volume_recovery_guest(root string, work string, arch string, kernel string) ! {
	if kernel == '' || !os.is_file(kernel) || work.contains(',') { return error('Select an existing kernel and safe work directory') }
	compile_guest(root, work, arch, false, 'recovery')!
	write_disk(work + '/volume.raw', false)!; write_disk(work + '/wrong.raw', true)!
	plan_filesystem(work)!; pack(work)!
	first_args := if arch == 'aarch64' { arm_boot(root, work, kernel, false)! } else { amd64_boot(root, work, kernel, false, false)! }
	first := boot(first_args, work + '/first-boot.log')!
	if !first.contains('PLAN VOLUME RECOVERY PASSED:') || first.count('PLAN VOLUME RECOVERY CYCLES count=4') != 2
		|| !first.contains('PLAN VOLUME RECOVERY LARGE ') || first.count('PLAN VOLUME RECOVERY RETAIN ') == 0 { return error('Missing complete volume recovery and retention qualification') }
	second_args := if arch == 'aarch64' { arm_boot(root, work, kernel, true)! } else { amd64_boot(root, work, kernel, true, false)! }
	second := boot(second_args, work + '/second-boot.log')!
	if !second.contains('PLAN VOLUME RECOVERY REORDERED BOOT PRESERVED') || second.contains('init: volume restore failed; continuing') { return error('Recovered configuration failed production boot replay') }
	println('PASS ' + arch + ': authenticated configuration recovery, full-cost retention and production reordered reboot')
}

fn recovery_unlock_guest(root string, work string, arch string, kernel string) ! {
	if kernel == '' || !os.is_file(kernel) || work.contains(',') { return error('Select an existing kernel and safe work directory') }
	compile_guest(root, work, arch, false, 'unlock')!
	write_disk(work + '/volume.raw', false)!; write_disk(work + '/wrong.raw', true)!
	plan_filesystem(work)!; pack(work)!
	first_args := if arch == 'aarch64' { arm_boot(root, work, kernel, false)! } else { amd64_boot(root, work, kernel, false, false)! }
	first := boot(first_args, work + '/first-boot.log')!
	if !first.contains('PLAN RECOVERY UNLOCK PASSED:') || first.count('PLAN RECOVERY UNLOCK CYCLES count=200') != 2
		|| !first.contains('PLAN RECOVERY UNLOCK LARGE ') || first.count('PLAN RECOVERY UNLOCK RETAIN ') == 0 { return error('Missing complete direct recovery unlock and retention qualification') }
	second_args := if arch == 'aarch64' { arm_boot(root, work, kernel, true)! } else { amd64_boot(root, work, kernel, true, false)! }
	second := boot(second_args, work + '/second-boot.log')!
	if !second.contains('PLAN RECOVERY UNLOCK REORDERED BOOT PRESERVED') || second.contains('init: volume restore failed; continuing') { return error('Recovery unlock failed after reordered boot') }
	println('PASS ' + arch + ': direct authenticated recovery unlock, exact RW/RO ciphertext, retention and reordered reboot without original credentials')
}

fn recovery_rewrap_guest(root string, work string, arch string, kernel string) ! {
	if kernel == '' || !os.is_file(kernel) || work.contains(',') { return error('Select an existing kernel and safe work directory') }
	compile_guest(root, work, arch, false, 'rewrap')!
	write_disk(work + '/volume.raw', false)!; write_disk(work + '/wrong.raw', true)!
	plan_filesystem(work)!; pack(work)!
	first_args := if arch == 'aarch64' { arm_boot(root, work, kernel, false)! } else { amd64_boot(root, work, kernel, false, false)! }
	first := boot(first_args, work + '/first-boot.log')!
	if !first.contains('PLAN RECOVERY REWRAP PASSED:') || first.count('PLAN RECOVERY REWRAP CYCLES count=200') != 2
		|| !first.contains('PLAN RECOVERY REWRAP LARGE ') || first.count('PLAN RECOVERY REWRAP RETAIN ') == 0 { return error('Missing complete recovery rewrap and retention qualification') }
	second_args := if arch == 'aarch64' { arm_boot(root, work, kernel, true)! } else { amd64_boot(root, work, kernel, true, false)! }
	second := boot(second_args, work + '/second-boot.log')!
	if !second.contains('PLAN RECOVERY REWRAP REORDERED BOOT PRESERVED') || second.contains('init: volume restore failed; continuing') { return error('Rewrapped recovery configuration failed after reordered boot') }
	println('PASS ' + arch + ': authenticated recovery credential changes, RW/RO ciphertext, retention and reordered reboot after old credential loss')
}

fn recovery_growth_guest(root string, work string, arch string, kernel string) ! {
	if kernel == '' || !os.is_file(kernel) || work.contains(',') { return error('Select an existing kernel and safe work directory') }
	compile_guest(root, work, arch, false, 'growth')!
	write_disk(work + '/volume.raw', false)!; write_disk(work + '/wrong.raw', true)!
	plan_filesystem(work)!; pack(work)!
	first_args := if arch == 'aarch64' { arm_boot(root, work, kernel, false)! } else { amd64_boot(root, work, kernel, false, false)! }
	first := boot(first_args, work + '/first-boot.log')!
	if !first.contains('PLAN RECOVERY GROWTH PASSED:') || first.count('PLAN RECOVERY GROWTH CYCLES count=200') != 2
		|| !first.contains('PLAN RECOVERY GROWTH LARGE ') || first.count('PLAN RECOVERY GROWTH RETAIN ') == 0 { return error('Missing complete recovery growth and retention qualification') }
	shrink_disk(work + '/volume.raw', 33554432)!
	second_args := if arch == 'aarch64' { arm_boot(root, work, kernel, true)! } else { amd64_boot(root, work, kernel, true, false)! }
	second := boot(second_args, work + '/second-boot.log')!
	if !second.contains('PLAN RECOVERY GROWTH CAPACITY BOOT PRESERVED') || second.contains('init: volume restore failed; continuing') { return error('Recovery capacity adoption failed after reordered boot') }
	println('PASS ' + arch + ': recovery extent growth, explicit physical capacity adoption, RW/RO ciphertext, retention and reordered reboot')
}

fn recovery_inspect_guest(root string, work string, arch string, kernel string) ! {
	if kernel == '' || !os.is_file(kernel) || work.contains(',') { return error('Select an existing kernel and safe work directory') }
	compile_guest(root, work, arch, false, 'inspect')!
	write_disk(work + '/volume.raw', false)!; write_disk(work + '/wrong.raw', true)!
	plan_filesystem(work)!; pack(work)!
	first_args := if arch == 'aarch64' { arm_boot(root, work, kernel, false)! } else { amd64_boot(root, work, kernel, false, false)! }
	first := boot(first_args, work + '/first-boot.log')!
	if !first.contains('PLAN RECOVERY INSPECTION PASSED:') || first.count('PLAN RECOVERY INSPECTION CYCLES count=200') != 2
		|| !first.contains('PLAN RECOVERY INSPECTION LARGE ') || first.count('PLAN RECOVERY INSPECTION RETAIN ') == 0 { return error('Missing complete recovery inspection and retention qualification') }
	second_args := if arch == 'aarch64' { arm_boot(root, work, kernel, true)! } else { amd64_boot(root, work, kernel, true, false)! }
	second := boot(second_args, work + '/second-boot.log')!
	if !second.contains('PLAN RECOVERY INSPECTION REORDERED BOOT PRESERVED') || second.contains('init: volume restore failed; continuing') { return error('Recovery inspection failed after reordered boot') }
	println('PASS ' + arch + ': authenticated offline reports, read-only identity discovery, unchanged live mappings/data, retention and reordered reboot')
}

fn volume_inspect_guest(root string, work string, arch string, kernel string) ! {
	if kernel == '' || !os.is_file(kernel) || work.contains(',') { return error('Select an existing kernel and safe work directory') }
	compile_guest(root, work, arch, false, 'volume-inspect')!
	write_disk(work + '/volume.raw', false)!; write_disk(work + '/wrong.raw', true)!
	plan_filesystem(work)!; pack(work)!
	first_args := if arch == 'aarch64' { arm_boot(root, work, kernel, false)! } else { amd64_boot(root, work, kernel, false, false)! }
	first := boot(first_args, work + '/first-boot.log')!
	if !first.contains('PLAN VOLUME INSPECTION PASSED:') || first.count('PLAN VOLUME INSPECTION CYCLES count=4') != 2
		|| !first.contains('PLAN VOLUME INSPECTION LARGE ') || first.count('PLAN VOLUME INSPECTION RETAIN ') == 0 { return error('Missing complete volume inspection and retention qualification') }
	second_args := if arch == 'aarch64' { arm_boot(root, work, kernel, true)! } else { amd64_boot(root, work, kernel, true, false)! }
	second := boot(second_args, work + '/second-boot.log')!
	if !second.contains('PLAN VOLUME INSPECTION REORDERED BOOT PRESERVED') || second.contains('init: volume restore failed; continuing') { return error('Recovery inspection failed after reordered boot') }
	println('PASS ' + arch + ': authenticated offline reports, read-only identity discovery, unchanged live mappings/data, retention and reordered reboot')
}

fn growth_preview_guest(root string, work string, arch string, kernel string) ! {
	if kernel == '' || !os.is_file(kernel) || work.contains(',') { return error('Select an existing kernel and safe work directory') }
	compile_guest(root, work, arch, false, 'growth-preview')!
	write_disk(work + '/volume.raw', false)!; write_disk(work + '/wrong.raw', true)!
	plan_filesystem(work)!; pack(work)!
	first_args := if arch == 'aarch64' { arm_boot(root, work, kernel, false)! } else { amd64_boot(root, work, kernel, false, false)! }
	first := boot(first_args, work + '/first-boot.log')!
	if !first.contains('PLAN GROWTH PREVIEW PASSED:') || first.count('PLAN GROWTH PREVIEW CYCLES count=4') != 2
		|| !first.contains('PLAN GROWTH PREVIEW LARGE ') || first.count('PLAN GROWTH PREVIEW RETAIN ') == 0 { return error('Missing complete growth preview and retention qualification') }
	shrink_disk(work + '/volume.raw', 33554432)!
	second_args := if arch == 'aarch64' { arm_boot(root, work, kernel, true)! } else { amd64_boot(root, work, kernel, true, false)! }
	second := boot(second_args, work + '/second-boot.log')!
	if !second.contains('PLAN GROWTH PREVIEW CAPACITY BOOT PRESERVED') || second.contains('init: volume restore failed; continuing') { return error('Growth preview failed after expansion and reordered boot') }
	println('PASS ' + arch + ': authenticated growth previews, exact RW/RO reports, unchanged live mappings/data, real-KDF retention and expanded/reordered reboot')
}

fn ciphertext_guest(root string, work string, arch string, kernel string) ! {
	if kernel == '' || !os.is_file(kernel) || work.contains(',') { return error('Select an existing kernel and safe work directory') }
	compile_guest(root, work, arch, false, 'ciphertext')!
	write_disk(work + '/volume.raw', false)!; write_disk(work + '/wrong.raw', true)!
	plan_filesystem(work)!; pack(work)!
	first := boot(if arch == 'aarch64' { arm_boot(root, work, kernel, false)! } else { amd64_boot(root, work, kernel, false, false)! }, work + '/first-boot.log')!
	if !first.contains('PLAN CIPHERTEXT PASSED:') || first.count('PLAN CIPHERTEXT CYCLES count=4') != 2
		|| !first.contains('PLAN CIPHERTEXT LARGE ') || first.count('PLAN CIPHERTEXT RETAIN ') == 0 { return error('Missing ciphertext and retention qualification') }
	second := boot(if arch == 'aarch64' { arm_boot(root, work, kernel, true)! } else { amd64_boot(root, work, kernel, true, false)! }, work + '/second-boot.log')!
	if !second.contains('PLAN CIPHERTEXT REORDERED BOOT PRESERVED') || second.contains('init: volume restore failed; continuing') { return error('Ciphertext verification failed after reordered boot') }
	println('PASS ' + arch + ': authenticated ciphertext scans, corruption/refusal/cleanup, real-KDF retention and reordered reboot')
}

fn ciphertext_scrub_guest(root string, work string, arch string, kernel string) ! {
	if kernel == '' || !os.is_file(kernel) || work.contains(',') { return error('Select an existing kernel and safe work directory') }
	compile_guest(root, work, arch, false, 'ciphertext-scrub')!
	write_disk(work + '/volume.raw', false)!; write_disk(work + '/wrong.raw', true)!
	plan_filesystem(work)!; pack(work)!
	first := boot(if arch == 'aarch64' { arm_boot(root, work, kernel, false)! } else { amd64_boot(root, work, kernel, false, false)! }, work + '/first-boot.log')!
	if !first.contains('PLAN CIPHERTEXT SCRUB PASSED:') || first.count('PLAN CIPHERTEXT SCRUB CYCLES count=4') != 2
		|| !first.contains('PLAN CIPHERTEXT SCRUB LARGE ') || first.count('PLAN CIPHERTEXT SCRUB RETAIN ') == 0 { return error('Missing complete ciphertext scrub and retention qualification') }
	second := boot(if arch == 'aarch64' { arm_boot(root, work, kernel, true)! } else { amd64_boot(root, work, kernel, true, false)! }, work + '/second-boot.log')!
	if !second.contains('PLAN CIPHERTEXT SCRUB REORDERED BOOT PRESERVED') || second.contains('init: volume restore failed; continuing') { return error('Ciphertext scrub reports failed after reordered boot') }
	println('PASS ' + arch + ': complete encrypted scrub findings/offline reports, fault cleanup, real-KDF retention and reordered reboot')
}

fn scrub_compare_host(root string, work string) ! {
	v := os.getenv_opt('V') or { @VEXE }; os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true)
	volume_recovery_native_tests(root, work, v)!; recovery_io_tests(root, work, v)!
	for entry in ['volume_seal_test', 'volume_ciphertext_scrub_test', 'volume_scrub_compare_test'] {
		binary := work + '/' + entry
		command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags', '-I' + root + '/tools/volumes/volumecli -O2 -fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined', '-o', binary, root + '/tools/volumes/volumecli/' + entry + '.v'])!
		print(command([binary])!); println('PASS ' + entry + ': ASan/UBSan')
	}
	for arch in ['aarch64', 'x86_64'] { path := work + '/volume-' + arch + '.c'; generate(root, root + '/tools/volumes/volumecli', path, arch)!; check_generated(path)! }
	println('PASS scrub comparison native/model/syntax and both target allocation audits')
}

fn scrub_compare_guest(root string, work string, arch string, kernel string) ! {
	if kernel == '' || !os.is_file(kernel) || work.contains(',') { return error('Select an existing kernel and safe work directory') }
	compile_guest(root, work, arch, false, 'scrub-compare')!
	write_disk(work + '/volume.raw', false)!; write_disk(work + '/wrong.raw', true)!
	plan_filesystem(work)!; pack(work)!
	first := boot(if arch == 'aarch64' { arm_boot(root, work, kernel, false)! } else { amd64_boot(root, work, kernel, false, false)! }, work + '/first-boot.log')!
	if !first.contains('PLAN SCRUB COMPARE PASSED:') || first.count('PLAN SCRUB COMPARE CYCLES count=100') != 2
		|| !first.contains('PLAN SCRUB COMPARE LARGE ') || first.count('PLAN SCRUB COMPARE RETAIN ') == 0 { return error('Missing complete scrub comparison and retention qualification') }
	second := boot(if arch == 'aarch64' { arm_boot(root, work, kernel, true)! } else { amd64_boot(root, work, kernel, true, false)! }, work + '/second-boot.log')!
	if !second.contains('PLAN SCRUB COMPARE REORDERED BOOT PRESERVED') || second.contains('init: volume restore failed; continuing') { return error('Scrub comparisons failed after reordered boot') }
	println('PASS ' + arch + ': offline ciphertext history comparisons, exact reference refusal, bounded lifetimes and reordered reboot')
}

fn auto_scrub_host(root string, work string) ! {
	v := os.getenv_opt('V') or { @VEXE }; os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true)
	volume_recovery_native_tests(root, work, v)!; recovery_io_tests(root, work, v)!; volume_discovery_io_tests(root, work, v)!
	for entry in ['volume_seal_test', 'volume_ciphertext_scrub_test', 'volume_scrub_compare_test', 'volume_scrub_auto_test'] {
		binary := work + '/' + entry
		command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags', '-I' + root + '/tools/volumes/volumecli -O2 -fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined', '-o', binary, root + '/tools/volumes/volumecli/' + entry + '.v'])!
		print(command([binary])!); println('PASS ' + entry + ': ASan/UBSan')
	}
	for arch in ['aarch64', 'x86_64'] { path := work + '/volume-' + arch + '.c'; generate(root, root + '/tools/volumes/volumecli', path, arch)!; check_generated(path)! }
	println('PASS automatic scrub native/model/discovery/syntax and both target allocation audits')
}

fn auto_scrub_guest(root string, work string, arch string, kernel string) ! {
	if kernel == '' || !os.is_file(kernel) || work.contains(',') { return error('Select an existing kernel and safe work directory') }
	compile_guest(root, work, arch, false, 'auto-scrub')!
	write_disk(work + '/volume.raw', false)!; write_disk(work + '/wrong.raw', true)!
	plan_filesystem(work)!; pack(work)!
	first := boot(if arch == 'aarch64' { arm_boot(root, work, kernel, false)! } else { amd64_boot(root, work, kernel, false, false)! }, work + '/first-boot.log')!
	if !first.contains('PLAN AUTO SCRUB PASSED:') || first.count('PLAN AUTO SCRUB CYCLES count=4') != 2
		|| !first.contains('PLAN AUTO SCRUB LARGE ') || first.count('PLAN AUTO SCRUB RETAIN ') == 0 { return error('Missing complete automatic scrub and retention qualification') }
	second := boot(if arch == 'aarch64' { arm_boot(root, work, kernel, true)! } else { amd64_boot(root, work, kernel, true, false)! }, work + '/second-boot.log')!
	if !second.contains('PLAN AUTO SCRUB REORDERED BOOT PRESERVED') || second.contains('init: volume restore failed; continuing') { return error('Automatic scrubs failed after reordered boot') }
	println('PASS ' + arch + ': authenticated read-only discovery, complete ciphertext scrubs, real-KDF lifetimes and reordered reboot')
}

fn ciphertext_auto_host(root string, work string) ! {
	v := os.getenv_opt('V') or { @VEXE }; os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true)
	volume_recovery_native_tests(root, work, v)!; recovery_io_tests(root, work, v)!; volume_discovery_io_tests(root, work, v)!
	for entry in ['volume_seal_test', 'volume_ciphertext_scrub_test', 'volume_scrub_compare_test', 'volume_scrub_auto_test', 'volume_ciphertext_auto_test'] {
		binary := work + '/' + entry
		command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags', '-I' + root + '/tools/volumes/volumecli -O2 -fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined', '-o', binary, root + '/tools/volumes/volumecli/' + entry + '.v'])!
		print(command([binary])!); println('PASS ' + entry + ': ASan/UBSan')
	}
	for arch in ['aarch64', 'x86_64'] { path := work + '/volume-' + arch + '.c'; generate(root, root + '/tools/volumes/volumecli', path, arch)!; check_generated(path)! }
	println('PASS automatic ciphertext native/model/discovery/syntax and both target allocation audits')
}

fn ciphertext_auto_guest(root string, work string, arch string, kernel string) ! {
	if kernel == '' || !os.is_file(kernel) || work.contains(',') { return error('Select an existing kernel and safe work directory') }
	compile_guest(root, work, arch, false, 'ciphertext-auto')!
	write_disk(work + '/volume.raw', false)!; write_disk(work + '/wrong.raw', true)!
	plan_filesystem(work)!; pack(work)!
	first := boot(if arch == 'aarch64' { arm_boot(root, work, kernel, false)! } else { amd64_boot(root, work, kernel, false, false)! }, work + '/first-boot.log')!
	if !first.contains('PLAN CIPHERTEXT AUTO PASSED:') || first.count('PLAN CIPHERTEXT AUTO CYCLES count=4') != 2
		|| !first.contains('PLAN CIPHERTEXT AUTO LARGE ') || first.count('PLAN CIPHERTEXT AUTO RETAIN ') == 0 { return error('Missing complete automatic ciphertext and retention qualification') }
	second := boot(if arch == 'aarch64' { arm_boot(root, work, kernel, true)! } else { amd64_boot(root, work, kernel, true, false)! }, work + '/second-boot.log')!
	if !second.contains('PLAN CIPHERTEXT AUTO REORDERED BOOT PRESERVED') || second.contains('init: volume restore failed; continuing') { return error('Automatic checksums failed after reordered boot') }
	println('PASS ' + arch + ': authenticated checksum discovery, exact references and complete verification, real-KDF lifetimes and reordered reboot')
}

fn reference_host(root string, work string) ! {
	v := os.getenv_opt('V') or { @VEXE }; os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true)
	volume_recovery_native_tests(root, work, v)!; recovery_io_tests(root, work, v)!; volume_discovery_io_tests(root, work, v)!
	for entry in ['volume_seal_test', 'volume_ciphertext_scrub_test', 'volume_scrub_compare_test', 'volume_scrub_auto_test', 'volume_ciphertext_auto_test', 'volume_reference_test'] {
		binary := work + '/' + entry
		command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags', '-I' + root + '/tools/volumes/volumecli -O2 -fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined', '-o', binary, root + '/tools/volumes/volumecli/' + entry + '.v'])!
		print(command([binary])!); println('PASS ' + entry + ': ASan/UBSan')
	}
	for arch in ['aarch64', 'x86_64'] { path := work + '/volume-' + arch + '.c'; generate(root, root + '/tools/volumes/volumecli', path, arch)!; check_generated(path)! }
	println('PASS offline reference native/model/syntax and both target allocation audits')
}

fn reference_guest(root string, work string, arch string, kernel string) ! {
	if kernel == '' || !os.is_file(kernel) || work.contains(',') { return error('Select an existing kernel and safe work directory') }
	compile_guest(root, work, arch, false, 'reference')!
	write_disk(work + '/volume.raw', false)!; write_disk(work + '/wrong.raw', true)!
	plan_filesystem(work)!; pack(work)!
	first := boot(if arch == 'aarch64' { arm_boot(root, work, kernel, false)! } else { amd64_boot(root, work, kernel, false, false)! }, work + '/first-boot.log')!
	if !first.contains('PLAN REFERENCE PASSED:') || first.count('PLAN REFERENCE CYCLES count=100') != 2
		|| !first.contains('PLAN REFERENCE LARGE ') || first.count('PLAN REFERENCE RETAIN ') == 0 { return error('Missing complete reference query and retention qualification') }
	second := boot(if arch == 'aarch64' { arm_boot(root, work, kernel, true)! } else { amd64_boot(root, work, kernel, true, false)! }, work + '/second-boot.log')!
	if !second.contains('PLAN REFERENCE REORDERED BOOT PRESERVED') || second.contains('init: volume restore failed; continuing') { return error('Reference queries failed after reordered boot') }
	println('PASS ' + arch + ': offline reference inspection/comparison, exact metadata and fingerprints, bounded lifetimes and reordered reboot')
}

fn data_auto_host(root string, work string) ! {
	v := os.getenv_opt('V') or { @VEXE }; os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true)
	data_io_tests(root, work, v)!; volume_discovery_io_tests(root, work, v)!
	for entry in ['data_manifest_test', 'data_scrub_test', 'data_auto_test'] {
		binary := work + '/' + entry
		command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags', '-I' + root + '/tools/volumes/volumecli -O2 -fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined', '-o', binary, root + '/tools/volumes/volumecli/' + entry + '.v'])!
		print(command([binary])!); println('PASS ' + entry + ': ASan/UBSan')
	}
	for arch in ['aarch64', 'x86_64'] { path := work + '/volume-' + arch + '.c'; generate(root, root + '/tools/volumes/volumecli', path, arch)!; check_generated(path)! }
	println('PASS automatic data native/model/discovery/syntax and both target allocation audits')
}

fn data_auto_guest(root string, work string, arch string, kernel string) ! {
	if kernel == '' || !os.is_file(kernel) || work.contains(',') { return error('Select an existing kernel and safe work directory') }
	compile_guest(root, work, arch, false, 'data-auto')!
	write_disk(work + '/volume.raw', false)!; write_disk(work + '/wrong.raw', true)!
	plan_filesystem(work)!; pack(work)!
	first := boot(if arch == 'aarch64' { arm_boot(root, work, kernel, false)! } else { amd64_boot(root, work, kernel, false, false)! }, work + '/first-boot.log')!
	if !first.contains('PLAN DATA AUTO PASSED:') || first.count('PLAN DATA AUTO CYCLES count=100') != 2
		|| !first.contains('PLAN DATA AUTO LARGE ') || first.count('PLAN DATA AUTO RETAIN ') == 0 { return error('Missing complete automatic data and retention qualification') }
	second := boot(if arch == 'aarch64' { arm_boot(root, work, kernel, true)! } else { amd64_boot(root, work, kernel, true, false)! }, work + '/second-boot.log')!
	if !second.contains('PLAN DATA AUTO REORDERED BOOT PRESERVED') || second.contains('init: volume restore failed; continuing') { return error('Automatic data operations failed after reordered boot') }
	println('PASS ' + arch + ': automatic all-disk checksums/scrubs, exact artifacts, bounded lifetimes and reordered reboot')
}

fn data_reference_host(root string, work string) ! {
	v := os.getenv_opt('V') or { @VEXE }; os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true)
	data_io_tests(root, work, v)!; volume_discovery_io_tests(root, work, v)!
	for entry in ['data_manifest_test', 'data_scrub_test', 'data_auto_test', 'data_reference_test'] {
		binary := work + '/' + entry
		command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags', '-I' + root + '/tools/volumes/volumecli -O2 -fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined', '-o', binary, root + '/tools/volumes/volumecli/' + entry + '.v'])!
		print(command([binary])!); println('PASS ' + entry + ': ASan/UBSan')
	}
	for arch in ['aarch64', 'x86_64'] { path := work + '/volume-' + arch + '.c'; generate(root, root + '/tools/volumes/volumecli', path, arch)!; check_generated(path)! }
	println('PASS offline data reference native/model/discovery/syntax and both target allocation audits')
}

fn data_reference_guest(root string, work string, arch string, kernel string) ! {
	if kernel == '' || !os.is_file(kernel) || work.contains(',') { return error('Select an existing kernel and safe work directory') }
	compile_guest(root, work, arch, false, 'data-reference')!
	write_disk(work + '/volume.raw', false)!; write_disk(work + '/wrong.raw', true)!
	plan_filesystem(work)!; pack(work)!
	first := boot(if arch == 'aarch64' { arm_boot(root, work, kernel, false)! } else { amd64_boot(root, work, kernel, false, false)! }, work + '/first-boot.log')!
	if !first.contains('PLAN DATA REFERENCE PASSED:') || first.count('PLAN DATA REFERENCE CYCLES count=100') != 2
		|| !first.contains('PLAN DATA REFERENCE LARGE ') || first.count('PLAN DATA REFERENCE RETAIN ') == 0 { return error('Missing complete data reference and retention qualification') }
	second := boot(if arch == 'aarch64' { arm_boot(root, work, kernel, true)! } else { amd64_boot(root, work, kernel, true, false)! }, work + '/second-boot.log')!
	if !second.contains('PLAN DATA REFERENCE REORDERED BOOT PRESERVED') || second.contains('init: volume restore failed; continuing') { return error('Automatic data operations failed after reordered boot') }
	println('PASS ' + arch + ': offline all-row comparisons, exact fingerprints/artifacts, bounded lifetimes and reordered reboot')
}

fn data_scrub_view_host(root string, work string) ! {
	v := os.getenv_opt('V') or { @VEXE }; os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true)
	data_io_tests(root, work, v)!; data_scrub_view_io_tests(root, work, v)!; volume_discovery_io_tests(root, work, v)!
	for entry in ['data_manifest_test', 'data_scrub_test', 'data_auto_test', 'data_reference_test', 'data_scrub_view_test'] {
		binary := work + '/' + entry
		command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags', '-I' + root + '/tools/volumes/volumecli -O2 -fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined', '-o', binary, root + '/tools/volumes/volumecli/' + entry + '.v'])!
		print(command([binary])!); println('PASS ' + entry + ': ASan/UBSan')
	}
	for arch in ['aarch64', 'x86_64'] { path := work + '/volume-' + arch + '.c'; generate(root, root + '/tools/volumes/volumecli', path, arch)!; check_generated(path)! }
	println('PASS offline scrub inspection native/model/discovery/syntax and both target allocation audits')
}

fn data_scrub_view_guest(root string, work string, arch string, kernel string) ! {
	if kernel == '' || !os.is_file(kernel) || work.contains(',') { return error('Select an existing kernel and safe work directory') }
	compile_guest(root, work, arch, false, 'data-scrub-view')!
	write_disk(work + '/volume.raw', false)!; write_disk(work + '/wrong.raw', true)!
	plan_filesystem(work)!; pack(work)!
	first := boot(if arch == 'aarch64' { arm_boot(root, work, kernel, false)! } else { amd64_boot(root, work, kernel, false, false)! }, work + '/first-boot.log')!
	if !first.contains('PLAN DATA SCRUB VIEW PASSED:') || first.count('PLAN DATA SCRUB VIEW CYCLES count=100') != 2
		|| !first.contains('PLAN DATA SCRUB VIEW LARGE ') || first.count('PLAN DATA SCRUB VIEW RETAIN ') == 0 { return error('Missing complete scrub inspection and retention qualification') }
	second := boot(if arch == 'aarch64' { arm_boot(root, work, kernel, true)! } else { amd64_boot(root, work, kernel, true, false)! }, work + '/second-boot.log')!
	if !second.contains('PLAN DATA SCRUB VIEW REORDERED BOOT PRESERVED') || second.contains('init: volume restore failed; continuing') { return error('Automatic data operations failed after reordered boot') }
	println('PASS ' + arch + ': offline complete scrub inspection, exact artifacts, bounded lifetimes and reordered reboot')
}

fn data_scrub_view_io_tests(root string, work string, v string) ! {
	fixture := work + '/scrubviewio'; os.mkdir(fixture)!
	for file in os.ls(root + '/tools/volumes/volumecli')! {
		if !file.ends_with('.v') || file.ends_with('_test.v') { continue }
		mut source := os.read_file(root + '/tools/volumes/volumecli/' + file)!
		if file == 'data_scrub_view.v' {
			source = source.replace('C.read(', 'scrub_view_read(').replace('C.fstat(', 'scrub_view_stat(').replace("C.printf(c'%s', &text[0])", 'scrub_view_print(&text[0])')
		}
		if file == 'plan_lock.v' { for name in ['open', 'openat', 'close', 'flock'] { source = source.replace('C.' + name + '(', 'scrub_view_' + name + '(').replace('fn scrub_view_' + name + '(', 'fn C.' + name + '(') } }
		if file == 'plan_check.v' { source = source.replace('C.fflush(', 'scrub_view_flush(').replace('C.ferror(', 'scrub_view_ferror(').replace('fn scrub_view_ferror(', 'fn C.ferror(') }
		os.write_file(fixture + '/' + file, source)!
	}
	os.cp(root + '/tests/storage-volumes/data_scrub_view_io_test.v', fixture + '/data_scrub_view_io_test.v')!
	binary := work + '/data-scrub-view-io-test'
	command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags', '-I' + root + '/tools/volumes/volumecli -fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined', '-o', binary, fixture + '/data_scrub_view_io_test.v'])!
	print(command([binary])!); println('PASS scrub inspection: complete ordinary readers, EOF/short/EINTR/error paths, descriptor balance, no locking and pinned stdout failures under ASan/UBSan')
}

fn data_scrub_history_host(root string, work string) ! {
	v := os.getenv_opt('V') or { @VEXE }; os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true)
	data_io_tests(root, work, v)!; data_scrub_view_io_tests(root, work, v)!; data_scrub_history_io_tests(root, work, v)!
	for entry in ['data_scrub_view_test', 'data_scrub_compare_test'] {
		binary := work + '/' + entry
		command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags', '-I' + root + '/tools/volumes/volumecli -O2 -fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined', '-o', binary, root + '/tools/volumes/volumecli/' + entry + '.v'])!
		print(command([binary])!); println('PASS ' + entry + ': ASan/UBSan')
	}
	for arch in ['aarch64', 'x86_64'] { path := work + '/volume-' + arch + '.c'; generate(root, root + '/tools/volumes/volumecli', path, arch)!; check_generated(path)! }
	println('PASS offline scrub history native/models/syntax and both target allocation audits')
}

fn data_scrub_history_guest(root string, work string, arch string, kernel string) ! {
	if kernel == '' || !os.is_file(kernel) || work.contains(',') { return error('Select an existing kernel and safe work directory') }
	compile_guest(root, work, arch, false, 'data-scrub-history')!
	write_disk(work + '/volume.raw', false)!; write_disk(work + '/wrong.raw', true)!
	plan_filesystem(work)!; pack(work)!
	first := boot(if arch == 'aarch64' { arm_boot(root, work, kernel, false)! } else { amd64_boot(root, work, kernel, false, false)! }, work + '/first-boot.log')!
	if !first.contains('PLAN DATA SCRUB HISTORY PASSED:') || first.count('PLAN DATA SCRUB HISTORY CYCLES count=100') != 2
		|| !first.contains('PLAN DATA SCRUB HISTORY LARGE ') || first.count('PLAN DATA SCRUB HISTORY RETAIN ') == 0 { return error('Missing complete scrub history and retention qualification') }
	second := boot(if arch == 'aarch64' { arm_boot(root, work, kernel, true)! } else { amd64_boot(root, work, kernel, true, false)! }, work + '/second-boot.log')!
	if !second.contains('PLAN DATA SCRUB HISTORY REORDERED BOOT PRESERVED') || second.contains('init: volume restore failed; continuing') { return error('Automatic data operations failed after reordered boot') }
	println('PASS ' + arch + ': offline complete scrub history, exact artifacts, bounded lifetimes and reordered reboot')
}

fn data_scrub_history_io_tests(root string, work string, v string) ! {
	fixture := work + '/scrubhistoryio'; os.mkdir(fixture)!
	for file in os.ls(root + '/tools/volumes/volumecli')! {
		if !file.ends_with('.v') || file.ends_with('_test.v') { continue }
		mut source := os.read_file(root + '/tools/volumes/volumecli/' + file)!
		if file == 'data_scrub_compare.v' { source = source.replace('C.read(', 'scrub_history_read(').replace('C.fstat(', 'scrub_history_stat(').replace("C.printf(c'%s', &text[0])", 'scrub_history_print(&text[0])').replace('encode_data_scrub_comparison(', 'scrub_history_mock_encode(').replace('fn scrub_history_mock_encode(', 'fn encode_data_scrub_comparison(') }
		if file == 'plan_lock.v' { for name in ['open', 'openat', 'close', 'flock'] { source = source.replace('C.' + name + '(', 'scrub_history_' + name + '(').replace('fn scrub_history_' + name + '(', 'fn C.' + name + '(') } }
		if file == 'plan_check.v' { source = source.replace('C.fflush(', 'scrub_history_flush(').replace('C.ferror(', 'scrub_history_ferror(').replace('fn scrub_history_ferror(', 'fn C.ferror(') }
		os.write_file(fixture + '/' + file, source)!
	}
	os.cp(root + '/tests/storage-volumes/data_scrub_compare_io_test.v', fixture + '/data_scrub_compare_io_test.v')!
	binary := work + '/data-scrub-history-io-test'
	command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags', '-I' + root + '/tools/volumes/volumecli -fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined', '-o', binary, fixture + '/data_scrub_compare_io_test.v'])!
	print(command([binary])!); println('PASS scrub history: complete two-input binding, short/EINTR/EOF/later-reader faults, balanced pinned owners, no locks and operational encoder/stdout failures under ASan/UBSan')
}

fn scrub_reference_host(root string, work string) ! {
	v := os.getenv_opt('V') or { @VEXE }; os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true)
	data_io_tests(root, work, v)!; scrub_reference_io_tests(root, work, v)!
	for entry in ['data_reference_test', 'data_scrub_compare_test', 'data_scrub_reference_test'] {
		binary := work + '/' + entry
		command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags', '-I' + root + '/tools/volumes/volumecli -O2 -fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined', '-o', binary, root + '/tools/volumes/volumecli/' + entry + '.v'])!
		print(command([binary])!); println('PASS ' + entry + ': ASan/UBSan')
	}
	for arch in ['aarch64', 'x86_64'] { path := work + '/volume-' + arch + '.c'; generate(root, root + '/tools/volumes/volumecli', path, arch)!; check_generated(path)! }
	println('PASS offline scrub reference native/models/syntax and both target allocation audits')
}

fn scrub_reference_guest(root string, work string, arch string, kernel string) ! {
	if kernel == '' || !os.is_file(kernel) || work.contains(',') { return error('Select an existing kernel and safe work directory') }
	compile_guest(root, work, arch, false, 'scrub-reference')!
	write_disk(work + '/volume.raw', false)!; write_disk(work + '/wrong.raw', true)!
	plan_filesystem(work)!; pack(work)!
	first := boot(if arch == 'aarch64' { arm_boot(root, work, kernel, false)! } else { amd64_boot(root, work, kernel, false, false)! }, work + '/first-boot.log')!
	if !first.contains('PLAN SCRUB REFERENCE PASSED:') || first.count('PLAN SCRUB REFERENCE CYCLES count=100') != 2
		|| !first.contains('PLAN SCRUB REFERENCE LARGE ') || first.count('PLAN SCRUB REFERENCE RETAIN ') == 0 { return error('Missing complete scrub reference and retention qualification') }
	second := boot(if arch == 'aarch64' { arm_boot(root, work, kernel, true)! } else { amd64_boot(root, work, kernel, true, false)! }, work + '/second-boot.log')!
	if !second.contains('PLAN SCRUB REFERENCE REORDERED BOOT PRESERVED') || second.contains('init: volume restore failed; continuing') { return error('Automatic data operations failed after reordered boot') }
	println('PASS ' + arch + ': offline full-reference binding, exact artifacts, bounded lifetimes and reordered reboot')
}

fn scrub_reference_io_tests(root string, work string, v string) ! {
	fixture := work + '/scrubreferenceio'; os.mkdir(fixture)!
	for file in os.ls(root + '/tools/volumes/volumecli')! {
		if !file.ends_with('.v') || file.ends_with('_test.v') { continue }
		mut source := os.read_file(root + '/tools/volumes/volumecli/' + file)!
		if file in ['data_manifest.v', 'data_scrub_compare.v'] { source = source.replace('C.read(', 'scrub_ref_read(').replace('C.fstat(', 'scrub_ref_stat(') }
		if file == 'data_scrub_reference.v' { source = source.replace("C.printf(c'%s', &text[0])", 'scrub_ref_print(&text[0])').replace('encode_data_scrub_reference(', 'scrub_ref_mock_encode(').replace('fn scrub_ref_mock_encode(', 'fn encode_data_scrub_reference(') }
		if file == 'plan_lock.v' { for name in ['open', 'openat', 'close', 'flock'] { source = source.replace('C.' + name + '(', 'scrub_ref_' + name + '(').replace('fn scrub_ref_' + name + '(', 'fn C.' + name + '(') } }
		if file == 'plan_check.v' { source = source.replace('C.fflush(', 'scrub_ref_flush(').replace('C.ferror(', 'scrub_ref_ferror(').replace('fn scrub_ref_ferror(', 'fn C.ferror(') }
		os.write_file(fixture + '/' + file, source)!
	}
	os.cp(root + '/tests/storage-volumes/scrub_reference_io_test.v', fixture + '/scrub_reference_io_test.v')!
	binary := work + '/scrub-reference-io-test'
	command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags', '-I' + root + '/tools/volumes/volumecli -fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined', '-o', binary, fixture + '/scrub_reference_io_test.v'])!
	print(command([binary])!); println('PASS scrub reference: real DH1/SR1 readers, exact binding, short/EINTR/EOF/later faults, balanced pinned owners, no locks and operational encoder/stdout failures under ASan/UBSan')
}

fn cipher_scrub_reference_host(root string, work string) ! {
	v := os.getenv_opt('V') or { @VEXE }; os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true)
	recovery_io_tests(root, work, v)!; cipher_scrub_reference_io_tests(root, work, v)!
	for entry in ['volume_reference_test', 'volume_ciphertext_scrub_test', 'volume_scrub_compare_test', 'volume_scrub_reference_test'] {
		binary := work + '/' + entry
		command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags', '-I' + root + '/tools/volumes/volumecli -O2 -fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined', '-o', binary, root + '/tools/volumes/volumecli/' + entry + '.v'])!
		print(command([binary])!); println('PASS ' + entry + ': ASan/UBSan')
	}
	for arch in ['aarch64', 'x86_64'] { path := work + '/volume-' + arch + '.c'; generate(root, root + '/tools/volumes/volumecli', path, arch)!; check_generated(path)! }
	println('PASS offline cipher scrub reference native/models/syntax and both target allocation audits')
}

fn cipher_scrub_reference_guest(root string, work string, arch string, kernel string) ! {
	if kernel == '' || !os.is_file(kernel) || work.contains(',') { return error('Select an existing kernel and safe work directory') }
	compile_guest(root, work, arch, false, 'cipher-scrub-reference')!
	write_disk(work + '/volume.raw', false)!; write_disk(work + '/wrong.raw', true)!
	plan_filesystem(work)!; pack(work)!
	first := boot(if arch == 'aarch64' { arm_boot(root, work, kernel, false)! } else { amd64_boot(root, work, kernel, false, false)! }, work + '/first-boot.log')!
	if !first.contains('PLAN CIPHER SCRUB REFERENCE PASSED:') || first.count('PLAN CIPHER SCRUB REFERENCE CYCLES count=100') != 2
		|| !first.contains('PLAN CIPHER SCRUB REFERENCE LARGE ') || first.count('PLAN CIPHER SCRUB REFERENCE RETAIN ') == 0 { return error('Missing complete cipher scrub reference and retention qualification') }
	second := boot(if arch == 'aarch64' { arm_boot(root, work, kernel, true)! } else { amd64_boot(root, work, kernel, true, false)! }, work + '/second-boot.log')!
	if !second.contains('PLAN CIPHER SCRUB REFERENCE REORDERED BOOT PRESERVED') || second.contains('init: volume restore failed; continuing') { return error('Automatic data operations failed after reordered boot') }
	println('PASS ' + arch + ': offline full-reference binding, exact artifacts, bounded lifetimes and reordered reboot')
}

fn cipher_scrub_reference_io_tests(root string, work string, v string) ! {
	fixture := work + '/cipherbindingio'; os.mkdir(fixture)!
	for file in os.ls(root + '/tools/volumes/volumecli')! {
		if !file.ends_with('.v') || file.ends_with('_test.v') { continue }
		mut source := os.read_file(root + '/tools/volumes/volumecli/' + file)!
		if file == 'recovery_io.v' { source = source.replace('C.read(', 'cipher_bind_read(').replace('C.fstat(', 'cipher_bind_stat(') }
		if file == 'volume_scrub_reference.v' { source = source.replace("C.printf(c'%s', &text[0])", 'cipher_bind_print(&text[0])').replace('encode_volume_scrub_reference(', 'cipher_bind_mock_encode(').replace('fn cipher_bind_mock_encode(', 'fn encode_volume_scrub_reference(') }
		if file == 'plan_lock.v' { for name in ['open', 'openat', 'close', 'flock'] { source = source.replace('C.' + name + '(', 'cipher_bind_' + name + '(').replace('fn cipher_bind_' + name + '(', 'fn C.' + name + '(') } }
		if file == 'plan_check.v' { source = source.replace('C.fflush(', 'cipher_bind_flush(').replace('C.ferror(', 'cipher_bind_ferror(').replace('fn cipher_bind_ferror(', 'fn C.ferror(') }
		os.write_file(fixture + '/' + file, source)!
	}
	os.cp(root + '/tests/storage-volumes/volume_scrub_reference_io_test.v', fixture + '/volume_scrub_reference_io_test.v')!
	binary := work + '/cipher-binding-io-test'
	command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags', '-I' + root + '/tools/volumes/volumecli -fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined', '-o', binary, fixture + '/volume_scrub_reference_io_test.v'])!
	print(command([binary])!); println('PASS cipher binding: real private CH1/CS1 readers, exact binding, read/EOF/post-read privacy and output faults, balanced pinned owners and no locks under ASan/UBSan')
}

fn data_monitor_host(root string, work string) ! {
	v := os.getenv_opt('V') or { @VEXE }; os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true)
	data_io_tests(root, work, v)!; data_monitor_io_tests(root, work, v)!
	for entry in ['data_scrub_test', 'data_monitor_test'] {
		binary := work + '/' + entry
		command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags', '-I' + root + '/tools/volumes/volumecli -O2 -fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined', '-o', binary, root + '/tools/volumes/volumecli/' + entry + '.v'])!
		print(command([binary])!); println('PASS ' + entry + ': ASan/UBSan')
	}
	for arch in ['aarch64', 'x86_64'] { path := work + '/volume-' + arch + '.c'; generate(root, root + '/tools/volumes/volumecli', path, arch)!; check_generated(path)! }
	println('PASS data monitor native/models/syntax and both target allocation audits')
}

fn data_monitor_guest(root string, work string, arch string, kernel string) ! {
	if kernel == '' || !os.is_file(kernel) || work.contains(',') { return error('Select an existing kernel and safe work directory') }
	compile_guest(root, work, arch, false, 'data-monitor')!
	write_disk(work + '/volume.raw', false)!; write_disk(work + '/wrong.raw', true)!
	plan_filesystem(work)!; pack(work)!
	first := boot(if arch == 'aarch64' { arm_boot(root, work, kernel, false)! } else { amd64_boot(root, work, kernel, false, false)! }, work + '/first-boot.log')!
	if !first.contains('PLAN DATA MONITOR PASSED:') || first.count('PLAN DATA MONITOR CYCLES count=100') != 2
		|| !first.contains('PLAN DATA MONITOR LARGE ') || first.count('PLAN DATA MONITOR RETAIN ') == 0 { return error('Missing complete data monitor and retention qualification') }
	second := boot(if arch == 'aarch64' { arm_boot(root, work, kernel, true)! } else { amd64_boot(root, work, kernel, true, false)! }, work + '/second-boot.log')!
	if !second.contains('PLAN DATA MONITOR REORDERED BOOT PRESERVED') || second.contains('init: volume restore failed; continuing') { return error('Automatic data operations failed after reordered boot') }
	println('PASS ' + arch + ': pinned checksum monitoring, exact artifacts, bounded lifetimes and reordered reboot')
}

fn data_monitor_io_tests(root string, work string, v string) ! {
	fixture := work + '/datamonitorio'; os.mkdir(fixture)!
	for file in os.ls(root + '/tools/volumes/volumecli')! {
		if !file.ends_with('.v') || file.ends_with('_test.v') { continue }
		mut source := os.read_file(root + '/tools/volumes/volumecli/' + file)!
		if file == 'data_manifest.v' { source = source.replace('C.read(', 'monitor_file_read(').replace('C.fstat(', 'monitor_file_stat(') }
		if file == 'data_auto.v' { source = source.replace('discover_disk_key(', 'monitor_mock_discover(') }
		if file == 'data_io.v' { for name in ['open', 'close'] { source = source.replace('C.' + name + '(', 'data_mock_' + name + '(') }; source = source.replace('C.pread(', 'monitor_mock_pread(') }
		if file == 'plan_io.v' { for name in ['ioctl', 'pread'] { source = source.replace('C.' + name + '(', 'monitor_mock_' + name + '(').replace('fn monitor_mock_' + name + '(', 'fn C.' + name + '(') } }
		if file == 'data_monitor.v' { source = source.replace("C.printf(c'%s', &text[0])", 'monitor_mock_print(&text[0])').replace('C.sleep(', 'monitor_mock_sleep(').replace('encode_data_monitor(', 'monitor_mock_encode(').replace('fn monitor_mock_encode(', 'fn encode_data_monitor(') }
		if file == 'plan_lock.v' { for name in ['open', 'openat', 'close', 'flock'] { source = source.replace('C.' + name + '(', 'monitor_file_' + name + '(').replace('fn monitor_file_' + name + '(', 'fn C.' + name + '(') } }
		if file == 'plan_check.v' { source = source.replace('C.fflush(', 'monitor_mock_flush(').replace('C.ferror(', 'monitor_mock_ferror(').replace('fn monitor_mock_ferror(', 'fn C.ferror(') }
		os.write_file(fixture + '/' + file, source)!
	}
	os.cp(root + '/tests/storage-volumes/data_monitor_io_test.v', fixture + '/data_monitor_io_test.v')!
	binary := work + '/data-monitor-io-test'
	command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags', '-I' + root + '/tools/volumes/volumecli -O2 -fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined', '-o', binary, fixture + '/data_monitor_io_test.v'])!
	print(command([binary])!); println('PASS data monitor: actual complete streams, one discovery per disk, held source/pins across sleeps, restored-data latch, late error precedence and 512 samples under ASan/UBSan')
}

fn cipher_monitor_host(root string, work string) ! {
	v := os.getenv_opt('V') or { @VEXE }; os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true)
	recovery_io_tests(root, work, v)!; cipher_monitor_io_tests(root, work, v)!
	for entry in ['volume_ciphertext_scrub_test', 'volume_monitor_test'] {
		binary := work + '/' + entry
		command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags', '-I' + root + '/tools/volumes/volumecli -O2 -fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined', '-o', binary, root + '/tools/volumes/volumecli/' + entry + '.v'])!
		print(command([binary])!); println('PASS ' + entry + ': ASan/UBSan')
	}
	for arch in ['aarch64', 'x86_64'] { path := work + '/volume-' + arch + '.c'; generate(root, root + '/tools/volumes/volumecli', path, arch)!; check_generated(path)! }
	println('PASS cipher monitor native/models/syntax and both target allocation audits')
}

fn cipher_monitor_guest(root string, work string, arch string, kernel string) ! {
	if kernel == '' || !os.is_file(kernel) || work.contains(',') { return error('Select an existing kernel and safe work directory') }
	compile_guest(root, work, arch, false, 'cipher-monitor')!
	write_disk(work + '/volume.raw', false)!; write_disk(work + '/wrong.raw', true)!
	plan_filesystem(work)!; pack(work)!
	first := boot(if arch == 'aarch64' { arm_boot(root, work, kernel, false)! } else { amd64_boot(root, work, kernel, false, false)! }, work + '/first-boot.log')!
	if !first.contains('PLAN CIPHER MONITOR PASSED:') || first.count('PLAN CIPHER MONITOR CYCLES count=4') != 2
		|| !first.contains('PLAN CIPHER MONITOR LARGE ') || first.count('PLAN CIPHER MONITOR RETAIN ') == 0 { return error('Missing complete cipher monitor and retention qualification') }
	second := boot(if arch == 'aarch64' { arm_boot(root, work, kernel, true)! } else { amd64_boot(root, work, kernel, true, false)! }, work + '/second-boot.log')!
	if !second.contains('PLAN CIPHER MONITOR REORDERED BOOT PRESERVED') || second.contains('init: volume restore failed; continuing') { return error('Automatic data operations failed after reordered boot') }
	println('PASS ' + arch + ': authenticated pinned ciphertext monitoring, exact artifacts, bounded lifetimes and reordered reboot')
}

fn cipher_monitor_io_tests(root string, work string, v string) ! {
	fixture := work + '/ciphermonitorio'; os.mkdir(fixture)!
	for file in os.ls(root + '/tools/volumes/volumecli')! {
		if !file.ends_with('.v') || file.ends_with('_test.v') { continue }; mut source := os.read_file(root + '/tools/volumes/volumecli/' + file)!
		if file == 'recovery_io.v' { for name in ['open', 'close', 'read', 'fstat'] { source = source.replace('C.' + name + '(', 'cipher_monitor_file_' + name + '(').replace('fn cipher_monitor_file_' + name + '(', 'fn C.' + name + '(') } }
		if file == 'plan_lock.v' { for name in ['open', 'openat', 'close', 'flock'] { source = source.replace('C.' + name + '(', 'cipher_monitor_file_' + name + '(').replace('fn cipher_monitor_file_' + name + '(', 'fn C.' + name + '(') } }
		if file == 'volume_seal_io.v' { source = source.replace('sealed_derive(', 'cipher_monitor_derive(') }
		if file == 'volume_scrub_auto.v' { source = source.replace('discover_disk_key(', 'cipher_monitor_discover(') }
		if file == 'plan_io.v' { for name in ['ioctl', 'pread'] { source = source.replace('C.' + name + '(', 'cipher_monitor_' + name + '(').replace('fn cipher_monitor_' + name + '(', 'fn C.' + name + '(') } }
		if file == 'volume_ciphertext.v' { source = source.replace('C.pread(', 'cipher_monitor_pread(') }
		if file == 'volume_monitor.v' { source = source.replace('unsafe { *work = VolumeSealFiles{} }', 'unsafe { *work = VolumeSealFiles{} }; cipher_monitor_record(work)').replace('C.close(', 'cipher_monitor_file_close(').replace('C.sleep(', 'cipher_monitor_sleep(').replace("C.printf(c'%s', &text[0])", 'cipher_monitor_print(&text[0])').replace('encode_ciphertext_monitor(', 'cipher_monitor_encode(').replace('fn cipher_monitor_encode(', 'fn encode_ciphertext_monitor(').replace('erase_key(', 'cipher_monitor_erase(') }
		if file == 'plan_check.v' { source = source.replace('C.fflush(', 'cipher_monitor_flush(').replace('C.ferror(', 'cipher_monitor_ferror(').replace('fn cipher_monitor_ferror(', 'fn C.ferror(') }
		os.write_file(fixture + '/' + file, source)!
	}
	os.cp(root + '/tests/storage-volumes/cipher_monitor_io_test.v', fixture + '/cipher_monitor_io_test.v')!
	binary := work + '/cipher-monitor-io-test'; command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags', '-I' + root + '/tools/volumes/volumecli -O2 -fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined', '-o', binary, fixture + '/cipher_monitor_io_test.v'])!
	print(command([binary])!); println('PASS cipher monitor: actual authentication/private reference/physical streaming, one KDF/discovery, erased secrets and retained owners across samples/output/sleeps, restored latch, late errors and 512 samples under ASan/UBSan')
}

fn data_monitor_verify_host(root string, work string) ! {
	v := os.getenv_opt('V') or { @VEXE }; os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true)
	scrub_reference_io_tests(root, work, v)!; data_monitor_verify_io_tests(root, work, v)!
	for entry in ['data_monitor_test', 'data_monitor_verify_test'] {
		binary := work + '/' + entry
		command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags', '-I' + root + '/tools/volumes/volumecli -O2 -fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined', '-o', binary, root + '/tools/volumes/volumecli/' + entry + '.v'])!
		print(command([binary])!); println('PASS ' + entry + ': ASan/UBSan')
	}
	for arch in ['aarch64', 'x86_64'] { path := work + '/volume-' + arch + '.c'; generate(root, root + '/tools/volumes/volumecli', path, arch)!; check_generated(path)! }
	println('PASS data monitor verification native/models/syntax and both target allocation audits')
}

fn data_monitor_verify_guest(root string, work string, arch string, kernel string) ! {
	if kernel == '' || !os.is_file(kernel) || work.contains(',') { return error('Select an existing kernel and safe work directory') }
	compile_guest(root, work, arch, false, 'data-monitor-verify')!
	write_disk(work + '/volume.raw', false)!; write_disk(work + '/wrong.raw', true)!
	plan_filesystem(work)!; pack(work)!
	first := boot(if arch == 'aarch64' { arm_boot(root, work, kernel, false)! } else { amd64_boot(root, work, kernel, false, false)! }, work + '/first-boot.log')!
	if !first.contains('PLAN DATA MONITOR VERIFY PASSED:') || first.count('PLAN DATA MONITOR VERIFY CYCLES count=100') != 2
		|| !first.contains('PLAN DATA MONITOR VERIFY LARGE ') || first.count('PLAN DATA MONITOR VERIFY RETAIN ') == 0 { return error('Missing complete data monitor verification and retention qualification') }
	second := boot(if arch == 'aarch64' { arm_boot(root, work, kernel, true)! } else { amd64_boot(root, work, kernel, true, false)! }, work + '/second-boot.log')!
	if !second.contains('PLAN DATA MONITOR VERIFY REORDERED BOOT PRESERVED') || second.contains('init: volume restore failed; continuing') { return error('Automatic data operations failed after reordered boot') }
	println('PASS ' + arch + ': offline complete transcript verification, exact artifacts, bounded lifetimes and reordered reboot')
}

fn data_monitor_verify_io_tests(root string, work string, v string) ! {
	fixture := work + '/datamonitorverifyio'; os.mkdir(fixture)!
	for file in os.ls(root + '/tools/volumes/volumecli')! {
		if !file.ends_with('.v') || file.ends_with('_test.v') { continue }; mut source := os.read_file(root + '/tools/volumes/volumecli/' + file)!
		if file == 'data_manifest.v' { source = source.replace('C.read(', 'scrub_ref_read(').replace('C.fstat(', 'scrub_ref_stat(') }
		if file == 'plan_lock.v' { for name in ['open', 'openat', 'close', 'flock'] { source = source.replace('C.' + name + '(', 'scrub_ref_' + name + '(').replace('fn scrub_ref_' + name + '(', 'fn C.' + name + '(') } }
		if file == 'data_monitor_verify.v' { source = source.replace('C.read(', 'monitor_verify_read(').replace('C.fstat(', 'monitor_verify_stat(').replace('accept_data_monitor_sample(', 'monitor_verify_accept(').replace('fn monitor_verify_accept(', 'fn accept_data_monitor_sample(').replace('encode_data_monitor_history(', 'monitor_verify_encode(').replace('fn monitor_verify_encode(', 'fn encode_data_monitor_history(').replace("C.printf(c'%s', &text[0])", 'scrub_ref_print(&text[0])') }
		if file == 'plan_check.v' { source = source.replace('C.fflush(', 'scrub_ref_flush(').replace('C.ferror(', 'scrub_ref_ferror(').replace('fn scrub_ref_ferror(', 'fn C.ferror(') }
		os.write_file(fixture + '/' + file, source)!
	}
	os.cp(root + '/tests/storage-volumes/data_monitor_verify_io_test.v', fixture + '/data_monitor_verify_io_test.v')!
	binary := work + '/data-monitor-verify-io-test'; command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags', '-I' + root + '/tools/volumes/volumecli -O2 -fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined', '-o', binary, fixture + '/data_monitor_verify_io_test.v'])!
	print(command([binary])!); println('PASS data monitor verification: actual buffered whole-file parser, canonical sample/counter/latch validation, complete reference binding, pinned inputs through output, error precedence and 512 frames under ASan/UBSan')
}

fn cipher_monitor_verify_host(root string, work string) ! {
	v := os.getenv_opt('V') or { @VEXE }; os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true)
	cipher_scrub_reference_io_tests(root, work, v)!; cipher_monitor_verify_io_tests(root, work, v)!
	for entry in ['volume_monitor_test', 'volume_monitor_verify_test'] {
		binary := work + '/' + entry
		command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags', '-I' + root + '/tools/volumes/volumecli -O2 -fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined', '-o', binary, root + '/tools/volumes/volumecli/' + entry + '.v'])!
		print(command([binary])!); println('PASS ' + entry + ': ASan/UBSan')
	}
	for arch in ['aarch64', 'x86_64'] { path := work + '/volume-' + arch + '.c'; generate(root, root + '/tools/volumes/volumecli', path, arch)!; check_generated(path)! }
	println('PASS cipher monitor verification native/models/syntax and both target allocation audits')
}

fn cipher_monitor_verify_guest(root string, work string, arch string, kernel string) ! {
	if kernel == '' || !os.is_file(kernel) || work.contains(',') { return error('Select an existing kernel and safe work directory') }
	compile_guest(root, work, arch, false, 'cipher-monitor-verify')!
	write_disk(work + '/volume.raw', false)!; write_disk(work + '/wrong.raw', true)!
	plan_filesystem(work)!; pack(work)!
	first := boot(if arch == 'aarch64' { arm_boot(root, work, kernel, false)! } else { amd64_boot(root, work, kernel, false, false)! }, work + '/first-boot.log')!
	if !first.contains('PLAN CIPHER MONITOR VERIFY PASSED:') || first.count('PLAN CIPHER MONITOR VERIFY CYCLES count=100') != 2
		|| !first.contains('PLAN CIPHER MONITOR VERIFY LARGE ') || first.count('PLAN CIPHER MONITOR VERIFY RETAIN ') == 0 { return error('Missing complete cipher monitor verification and retention qualification') }
	second := boot(if arch == 'aarch64' { arm_boot(root, work, kernel, true)! } else { amd64_boot(root, work, kernel, true, false)! }, work + '/second-boot.log')!
	if !second.contains('PLAN CIPHER MONITOR VERIFY REORDERED BOOT PRESERVED') || second.contains('init: volume restore failed; continuing') { return error('Automatic data operations failed after reordered boot') }
	println('PASS ' + arch + ': offline complete transcript verification, exact artifacts, bounded lifetimes and reordered reboot')
}

// Retain the selected utility's complete C and ABI checks alongside guest C.
// This disposable seed is private and unpublished until pack() completes.
fn stage_selected_volume(root string, work string, arch string, cc string) ! {
	source := work + '/staged-volume.c'; generate(root, root + '/tools/volumes/volumecli', source, arch)!; check_generated(source)!
	os.write_file(source, os.read_file(source)! + '\n_Static_assert(sizeof(volumecli__Request)==32, "V request ABI");\n_Static_assert(sizeof(volumecli__Status)==128, "V status ABI");\n_Static_assert(sizeof(volumecli__Health)==1088, "V health ABI");\n_Static_assert(offsetof(volumecli__Health,data)==576, "V health data ABI");\n')!
	binary := work + '/seed/usr/sbin/vinix-volume'; os.mkdir_all(os.dir(binary))!
	command([cc, '-static', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-parameter', '-Wno-unused-label', '-D_GNU_SOURCE', '-DVINIX_V_RUNTIME', '-I', root + '/tools/volumes/volumecli', source, '-o', binary])!
	bytes := os.read_bytes(binary)!
	if bytes.len < 20 || bytes[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1] || int(bytes[18]) + (int(bytes[19]) << 8) != if arch == 'aarch64' { 183 } else { 62 } { return error('Wrong selected utility ELF architecture') }
	os.chmod(binary, 0o755)!; println('Staged checked volume utility (' + arch + ').')
}

fn cipher_monitor_verify_io_tests(root string, work string, v string) ! {
	fixture := work + '/ciphermonitorverifyio'; os.mkdir(fixture)!
	for file in os.ls(root + '/tools/volumes/volumecli')! {
		if !file.ends_with('.v') || file.ends_with('_test.v') { continue }; mut source := os.read_file(root + '/tools/volumes/volumecli/' + file)!
		if file == 'recovery_io.v' { for name in ['read', 'fstat'] { source = source.replace('C.' + name + '(', 'cipher_bind_' + if name == 'fstat' { 'stat' } else { name } + '(').replace('fn cipher_bind_' + if name == 'fstat' { 'stat' } else { name } + '(', 'fn C.' + name + '(') } }
		if file == 'plan_lock.v' { for name in ['open', 'openat', 'close', 'flock'] { source = source.replace('C.' + name + '(', 'cipher_bind_' + name + '(').replace('fn cipher_bind_' + name + '(', 'fn C.' + name + '(') } }
		if file == 'data_monitor_verify.v' { source = source.replace('C.read(', 'cipher_verify_io_read(') }
		if file == 'volume_monitor_verify.v' { source = source.replace('C.read(', 'cipher_verify_io_read(').replace('C.fstat(', 'cipher_verify_io_stat(').replace('accept_ciphertext_monitor(', 'cipher_verify_io_accept(').replace('fn cipher_verify_io_accept(', 'fn accept_ciphertext_monitor(').replace('encode_ciphertext_monitor_history(', 'cipher_verify_io_encode(').replace('fn cipher_verify_io_encode(', 'fn encode_ciphertext_monitor_history(').replace("C.printf(c'%s', &text[0])", 'cipher_bind_print(&text[0])') }
		if file == 'plan_check.v' { source = source.replace('C.fflush(', 'cipher_bind_flush(').replace('C.ferror(', 'cipher_bind_ferror(').replace('fn cipher_bind_ferror(', 'fn C.ferror(') }
		os.write_file(fixture + '/' + file, source)!
	}
	os.cp(root + '/tests/storage-volumes/cipher_monitor_verify_io_test.v', fixture + '/cipher_monitor_verify_io_test.v')!
	binary := work + '/cipher-monitor-verify-io-test'; command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags', '-I' + root + '/tools/volumes/volumecli -O2 -fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined', '-o', binary, fixture + '/cipher_monitor_verify_io_test.v'])!
	print(command([binary])!); println('PASS cipher monitor verification: actual private CH1/public buffered transcript, complete canonical frames, stable source domain, pinned owners through output, fault precedence and 512 frames under ASan/UBSan')
}

fn file_backup_host(root string, work string) ! {
	v := os.getenv_opt('V') or { @VEXE }; os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true)
	for entry in ['file_backup_test', 'volume_monitor_verify_test', 'data_reference_test'] {
		binary := work + '/' + entry
		command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags', '-I' + root + '/tools/volumes/volumecli -O2 -fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined', '-o', binary, root + '/tools/volumes/volumecli/' + entry + '.v'])!
		print(command([binary])!); println('PASS ' + entry + ': ASan/UBSan')
	}
	fixture := work + '/filebackupio'; os.mkdir(fixture)!
	for name in os.ls(root + '/tools/volumes/volumecli')! {
		if !name.ends_with('.v') || name.ends_with('_test.v') { continue }; mut source := os.read_file(root + '/tools/volumes/volumecli/' + name)!
		if name in ['file_backup_io.v', 'plan_lock.v'] { for function in ['open', 'openat', 'close', 'fstat', 'pread', 'pwrite', 'fsync', 'linkat', 'unlinkat', 'fchmod', 'fchown', 'futimens'] { source = source.replace('C.' + function + '(', 'backup_fault_' + function + '(').replace('fn backup_fault_' + function + '(', 'fn C.' + function + '(') } }
		if name == 'file_backup_format.v' { source = source.replace('finish_bundle_report(', 'backup_fault_finish(') }
		os.write_file(fixture + '/' + name, source)!
	}
	os.cp(root + '/tests/storage-volumes/file_backup_io_test.v', fixture + '/file_backup_io_test.v')!
	binary := work + '/file-backup-io-test'; command([v, '-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags', '-I' + root + '/tools/volumes/volumecli -O2 -fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined', '-o', binary, fixture + '/file_backup_io_test.v'])!
	print(command([binary])!); println('PASS file backup actual IO faults and owners: ASan/UBSan')
	for arch in ['aarch64', 'x86_64'] { source := work + '/volume-' + arch + '.c'; generate(root, root + '/tools/volumes/volumecli', source, arch)!; check_generated(source)! }
	println('PASS file backup native/models/regressions and both target allocation audits')
}

fn file_backup_guest(root string, work string, arch string, kernel string) ! {
	if kernel == '' || !os.is_file(kernel) || work.contains(',') { return error('Select an existing kernel and safe work directory') }
	compile_guest(root, work, arch, false, 'file-backup')!
	os.rm(work + '/seed/etc/vinix/volumes.vmap')!
	write_disk(work + '/volume.raw', false)!; write_disk(work + '/wrong.raw', true)!; plan_filesystem_blocks(work, 16384)!; pack(work)!
	first := boot(if arch == 'aarch64' { arm_boot(root, work, kernel, false)! } else { amd64_boot(root, work, kernel, false, false)! }, work + '/first-boot.log')!
	if !first.contains('PLAN FILE BACKUP PASSED') || first.count('PLAN FILE BACKUP CYCLES count=20') != 2 || !first.contains('PLAN FILE BACKUP LARGE ') || !first.contains('PLAN FILE BACKUP RETAIN ') { return error('Missing full file backup qualification') }
	second := boot(if arch == 'aarch64' { arm_boot(root, work, kernel, true)! } else { amd64_boot(root, work, kernel, true, false)! }, work + '/second-boot.log')!
	if !second.contains('PLAN FILE BACKUP REBOOT PRESERVED') { return error('File backup restore failed after reordered reboot') }
	println('PASS file backup ' + arch + ': full/delta archives, new-file restoration, preserved metadata and bounded repeated processes across reboot')
}
