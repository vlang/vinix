// SPDX-License-Identifier: GPL-2.0-or-later
module androidrunfixtures

import androidhost as ah
import androidrun
import androidtools
import boothost
import cachecli
import encoding.binary
import hosttest
import os

const staging_cases = ['test_stage_contains_only_verified_native_launchers',
	'test_invalid_shared_runtime_keeps_previous_launchers',
	'test_changed_runtime_generation_requires_restage', 'test_framework_receipt_mismatch_is_rejected',
	'test_missing_or_stale_android_launcher_is_rejected',
	'test_foreign_loader_and_compatibility_library_are_rejected',
	'test_corrupt_or_nonexecutable_launcher_is_rejected', 'test_alternate_runtime_payload_is_rejected',
	'test_publish_failure_restores_previous_stage',
	'test_shared_runtime_cannot_be_replaced_by_launcher_stage']

fn elf(machine u16) []u8 {
	mut data := []u8{len: 120}
	copy(mut data, '\x7fELF\x02\x01\x01'.bytes())
	binary.little_endian_put_u16(mut data[16..18], 3)
	binary.little_endian_put_u16(mut data[18..20], machine)
	binary.little_endian_put_u32(mut data[20..24], 1)
	binary.little_endian_put_u64(mut data[32..40], 64)
	binary.little_endian_put_u16(mut data[54..56], 56)
	binary.little_endian_put_u16(mut data[56..58], 1)
	binary.little_endian_put_u32(mut data[64..68], 1)
	binary.little_endian_put_u32(mut data[68..72], 5)
	binary.little_endian_put_u64(mut data[96..104], 120)
	binary.little_endian_put_u64(mut data[104..112], 120)
	binary.little_endian_put_u64(mut data[112..120], 16384)
	return data
}

fn runtime_read(kind string, _ string, context ah.Value) !ah.Value {
	return ah.field(context.object(), kind)
}

fn pair_noop(_ ah.Value, _ ah.Value, _ ah.Value) ! {}

fn publication_failure(_ string, _ string, _ ah.Value) ! { return error('publication failed') }

fn refuse_stage(root string, build string, android string, hooks androidrun.RobloxHooks, expected string) ! {
	mut refused := false
	androidrun.stage_roblox_with(root, build, android, hooks) or {
		assert err.msg().contains(expected), err.msg()
		refused = true
	}
	assert refused
}

fn refuse_validation(root string, stage string, android string, hooks androidrun.RobloxHooks, expected string) ! {
	mut refused := false
	androidrun.validate_roblox_with(root, stage, android, hooks) or {
		assert err.msg().contains(expected), err.msg()
		refused = true
	}
	assert refused
}

fn staging_case(name string, root string, directory string) ! {
	android := directory + '/android/staging'
	runtime := android + '/' + androidrun.roblox_prefix
	build := directory + '/roblox'
	mut receipts := {
		'art':    ah.Value({
			'source_commit': ah.Value('art-source')
			'patch_sha256':  ah.Value('art-patch')
			'bootclasspath': ah.Value({
				'verified': ah.Value(true)
			})
		})
		'bionic': ah.Value({
			'source_commit': ah.Value('bionic-source')
			'patch_sha256':  ah.Value('bionic-patch')
		})
		'atl':    ah.Value({
			'source_commit':  ah.Value('atl-source')
			'builder_sha256': ah.Value('atl-builder')
		})
		'musl':   ah.Value({
			'libc_so_sha256': ah.Value('native-libc')
		})
	}
	mut manifest := {
		'architecture':   ah.Value('aarch64')
		'execution':      ah.Value('native')
		'page_size':      ah.Value(16384)
		'runtime_prefix': ah.Value('/' + androidrun.roblox_prefix)
		'art':            receipts['art']!
		'bionic':         receipts['bionic']!
		'atl':            receipts['atl']!
		'musl':           receipts['musl']!
	}
	hooks := androidrun.RobloxHooks{ context: ah.Value(receipts), read: runtime_read, pair: pair_noop }
	for relative in ['lib/ld-musl-aarch64.so.1', 'usr/lib/libvinix-android-compat.so'] {
		os.mkdir_all(os.dir(runtime + '/' + relative))!
		os.write_file_array(runtime + '/' + relative, elf(183))!
	}
	os.write_file(runtime + '/architecture', 'aarch64\n')!
	os.write_file(runtime + '/runtime-manifest.json', ah.encode(ah.Value(manifest)) + '\n')!
	os.mkdir_all(android + '/usr/bin')!
	os.cp(root + '/build-support/android/run-android', android + '/usr/bin/run-android')!
	os.chmod(android + '/usr/bin/run-android', 0o755)!
	stage := androidrun.stage_roblox_with(root, build, android, hooks)!
	previous := os.read_bytes(stage + '/' + androidrun.roblox_receipt)!
	match name {
		'test_stage_contains_only_verified_native_launchers' {
			result := androidrun.validate_roblox_with(root, stage, android, hooks)!.object()
			assert ah.field(result, 'architecture').text() == 'aarch64'
			assert ah.field(result, 'execution').text() == 'native'
			assert boothost.receipt_equal(ah.field(result, 'page_size'), ah.Value(16384))
			assert ah.field(result, 'apk_bundled') == ah.Value(false)
			for command in androidrun.roblox_commands {
				assert os.read_bytes(stage + '/usr/bin/' + command)! == os.read_bytes(root + '/build-support/roblox/' + command)!
			}
		}
		'test_invalid_shared_runtime_keeps_previous_launchers',
		'test_framework_receipt_mismatch_is_rejected' {
			if name == 'test_invalid_shared_runtime_keeps_previous_launchers' {
				manifest['architecture'] = ah.Value('x86_64')
			} else {
				manifest['atl'] = ah.Value({
					'source_commit': ah.Value('stale-framework')
				})
			}
			os.write_file(runtime + '/runtime-manifest.json', ah.encode(ah.Value(manifest)) + '\n')!
			refuse_stage(root, build, android, hooks, 'native ARM64')!
			assert os.read_bytes(stage + '/' + androidrun.roblox_receipt)! == previous
		}
		'test_changed_runtime_generation_requires_restage' {
			manifest['generation'] = ah.Value('updated runtime')
			os.write_file(runtime + '/runtime-manifest.json', ah.encode(ah.Value(manifest)) + '\n')!
			refuse_validation(root, stage, android, hooks, 'rebuild the Roblox layer')!
			fresh := androidrun.stage_roblox_with(root, build, android, hooks)!
			result := androidrun.validate_roblox_with(root, fresh, android, hooks)!.object()
			assert ah.field(result, 'android_runtime_manifest_sha256').text() == ah.digest(runtime + '/runtime-manifest.json')!
		}
		'test_missing_or_stale_android_launcher_is_rejected' {
			launcher := android + '/usr/bin/run-android'
			os.write_file(launcher, '#!/bin/sh\nexit 0\n')!
			refuse_stage(root, build, android, hooks, 'stale launcher')!
			os.rm(launcher)!
			refuse_stage(root, build, android, hooks, 'Build the native Android runtime')!
		}
		'test_foreign_loader_and_compatibility_library_are_rejected' {
			for relative in ['lib/ld-musl-aarch64.so.1', 'usr/lib/libvinix-android-compat.so'] {
				os.write_file_array(runtime + '/' + relative, elf(62))!
				refuse_stage(root, build, android, hooks, 'native ARM64 ELF')!
				os.write_file_array(runtime + '/' + relative, elf(183))!
			}
		}
		'test_corrupt_or_nonexecutable_launcher_is_rejected' {
			launcher := stage + '/usr/bin/run-roblox'
			os.write_file(launcher, '#!/bin/sh\nexit 0\n')!
			refuse_validation(root, stage, android, hooks, 'launcher is stale')!
			os.cp(root + '/build-support/roblox/run-roblox', launcher)!
			os.chmod(launcher, 0o644)!
			refuse_validation(root, stage, android, hooks, 'not executable')!
		}
		'test_alternate_runtime_payload_is_rejected' {
			os.write_file_array(stage + '/usr/bin/qemu-x86_64', elf(183))!
			refuse_validation(root, stage, android, hooks, 'only its native APK launchers')!
		}
		'test_publish_failure_restores_previous_stage' {
			failed_hooks := androidrun.RobloxHooks{ context: ah.Value(receipts), read: runtime_read, pair: pair_noop, publish: publication_failure }
			refuse_stage(root, build, android, failed_hooks, 'publication failed')!
			assert os.read_bytes(stage + '/' + androidrun.roblox_receipt)! == previous
			androidrun.validate_roblox_with(root, stage, android, hooks)!
		}
		'test_shared_runtime_cannot_be_replaced_by_launcher_stage' {
			refuse_stage(root, os.dir(android), android, hooks, 'separate from the shared Android')!
			assert os.is_file(runtime + '/runtime-manifest.json')
		}
		else { return error('unknown native staging fixture') }
	}
}

pub fn roblox_tests(root string, argv []string) !int {
	normalized := argv.map(if it == '-k' {
		'--filter'
	} else if it == '-v' {
		'--verbose'
	} else if it == '-q' {
		'--quiet'
	} else {
		it
	})
	args := cachecli.arguments(normalized, ['--filter', '--state-dir'], [], [
		'--verbose',
		'--quiet',
	], 0, -1, 'Native Roblox launcher fixtures.\nUsage: build-test [-v|-q] [-k FILTER] [StagingTest.test_NAME] [--state-dir NEW_DIRECTORY]') or { return androidtools.InputError{err.msg()} }
	for target in args.positional {
		if target != 'StagingTest' && target !in staging_cases && target !in staging_cases.map('StagingTest.' + it) {
			return error('unknown StagingTest selector: ' + target)
		}
	}
	directory := hosttest.work_dir(args.value('--state-dir', ''), 'vinix-roblox-staging-')!
	defer { if '--state-dir' !in args.options { hosttest.remove_work_dir(directory) or {} } }
	mut count := 0
	for name in staging_cases {
		if args.value('--filter', '') != '' && !name.contains(args.value('--filter', '')) {
			continue
		}
		if args.positional.len > 0 && !args.positional.any(it in ['StagingTest', name,
			'StagingTest.' + name]) {
			continue
		}
		staging_case(name, root, directory + '/' + name)!
		count++
		if '--quiet' !in args.options { eprintln(name + ' ... ok') }
	}
	os.write_file(directory + '/passed', 'PASS ' + count.str() + '\n')!
	eprintln('Ran ' + count.str() + ' native Roblox staging tests\nOK')
	return 0
}
