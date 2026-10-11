// SPDX-License-Identifier: GPL-2.0-or-later
module nativehost

import guesthost
import hosttest
import json2
import os
import transcriptcore

pub struct Runtime {
pub:
	root   string
	libc   Pin
	loader Pin
}

pub fn runtime_inputs(source string) !Runtime {
	runtime := resolve(source)!
	mut pins := []Pin{}
	for alternatives in [
		['lib/x86_64-linux-gnu/libc.so.6', 'usr/lib/x86_64-linux-gnu/libc.so.6'],
		['lib64/ld-linux-x86-64.so.2', 'usr/lib64/ld-linux-x86-64.so.2',
			'lib/x86_64-linux-gnu/ld-linux-x86-64.so.2', 'usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2'],
	] {
		mut found := false
		for name in alternatives {
			if os.is_file(runtime + '/' + name) {
				pins << elf_input(runtime + '/' + name, 62, 4 * 1024 * 1024)!
				found = true
				break
			}
		}
		if !found { return argument('Missing matching glibc libc or loader in ' + runtime) }
	}
	return Runtime{runtime, pins[0], pins[1]}
}

fn environment(args []string) !int {
	options := parse(args, [hosttest.Option{ name: '--work', value: true },
		hosttest.Option{ name: '--old-glibc-root', value: true },
		hosttest.Option{ name: '--new-glibc-root', value: true },
		hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--translator', value: true },
		hosttest.Option{ name: '--native-cc', value: true },
		hosttest.Option{ name: '--cc', value: true },
		hosttest.Option{ name: '--timeout', value: true }, hosttest.Option{ name: '--prepare-only' }], [], 'Usage: env-run --work NEW_DIR --old-glibc-root DIR --new-glibc-root DIR [--prepare-only]')!
	required(options, ['--work', '--old-glibc-root', '--new-glibc-root'])!
	seconds := positive(options, '--timeout', 240)!
	work := resolve(options.value('--work', ''))!
	old := runtime_inputs(options.value('--old-glibc-root', ''))!
	new := runtime_inputs(options.value('--new-glibc-root', ''))!
	if old.libc.sha256 == new.libc.sha256 {
		return argument('Old and new libc must differ for the paired control')
	}
	kernel_dir := resolve(options.value('--kernel-dir', root() + '/kernel'))!
	separate(work, [old.root, new.root, kernel_dir])!
	translator := elf_input(options.value('--translator', root() + '/build/dota2-qemu/staging/usr/bin/qemu-x86_64'), 183, 32 * 1024 * 1024)!
	kernel := elf_input(kernel_dir + '/bin/vinix', 183, 64 * 1024 * 1024)!
	native_cc := os.find_abs_path_of_executable(options.value('--native-cc', root() + '/build/dota2-qemu/aarch64-cc')) or { return argument(err.msg()) }
	cc := os.find_abs_path_of_executable(options.value('--cc', 'clang')) or { return argument(err.msg()) }
	fresh(work)!
	rootfs := work + '/root'
	directories(rootfs, ['sbin', 'usr/bin', 'dev', 'proc', 'sys', 'tmp', 'root', 'opt/glibc-old/lib64',
		'opt/glibc-new/lib64'])!
	for label, runtime in {
		'old': old
		'new': new
	} {
		install_pin(runtime.libc, rootfs + '/opt/glibc-' + label + '/lib/libc.so.6')!
		install_pin(runtime.loader, rootfs + '/opt/glibc-' + label + '/lib64/ld-linux-x86-64.so.2')!
	}
	install_pin(translator, rootfs + '/usr/bin/qemu-x86_64')!
	install_pin(kernel, work + '/kernel/bin/vinix')!
	native := work + '/init'
	native_command := [native_cc, '-static', '-O2', '-Wall', '-Wextra', '-Werror',
		here() + '/env-native-wait.c', '-o', native]
	run(native_command)!
	install(native, rootfs + '/sbin/init')!
	mut commands := map[string][]string{}
	mut pins := map[string]Pin{}
	for label in ['old', 'new'] {
		binary := work + '/env-test-' + label
		argv := [cc, '--target=x86_64-linux-gnu', '-fPIE', '-pie', '-O2', '-fno-stack-protector',
			'-nostdlib', '-fuse-ld=lld', '-Wall', '-Wextra', '-Werror',
			'-Wl,--dynamic-linker=/lib64/ld-linux-x86-64.so.2', '-Wl,-e,_start', '-Wl,-z,now',
			here() + '/env-test.c', rootfs + '/opt/glibc-' + label + '/lib/libc.so.6', '-o', binary]
		run(argv)!
		commands[label] = argv
		pins[label] = elf_input(binary, 62, 4 * 1024 * 1024)!
	}
	if pins['old']!.sha256 != pins['new']!.sha256 {
		return error('Both libc links must produce the same test ELF')
	}
	install(work + '/env-test-old', rootfs + '/usr/bin/env-test')!
	tar := archive(rootfs, work, false)!
	mut report := json2.decode[json2.Any](json2.encode({
		'old': old
		'new': new
	}))!.as_map()
	runtime_pins := json2.Any(report.clone())
	report = {
		'runtime_pins':                       runtime_pins
		'translator':                         json2.decode[json2.Any](json2.encode(translator))!
		'kernel':                             json2.decode[json2.Any](json2.encode(kernel))!
		'test_build_commands':                json2.decode[json2.Any](json2.encode(commands))!
		'test_ELF_sha256':                    json2.Any(pins['old']!.sha256)
		'test_source_sha256':                 json2.Any(hosttest.sha(here() + '/env-test.c')!)
		'native_source_sha256':               json2.Any(hosttest.sha(here() + '/env-native-wait.c')!)
		'native_init_sha256':                 json2.Any(hosttest.sha(native)!)
		'native_build_command':               json2.Any(hosttest.strings(native_command))
		'archive_sha256':                     json2.Any(hosttest.sha(tar)!)
		'guest_memory_mib':                   json2.Any(2048)
		'guest_cpus':                         json2.Any(4)
		'guest_watchdog_seconds_per_variant': json2.Any(110)
		'host_timeout_seconds':               json2.Any(seconds)
		'compatibility_preloads':             json2.Any([]json2.Any{})
		'native_translator_environment':      json2.Any({
			'VINIX_ALLOW_WX': json2.Any('1')
		})
		'vm_started':                         json2.Any(false)
		'proof_scope':                        json2.Any('Only concurrent glibc environment synchronization; no game-root-cause claim or game execution.')
	}
	write_json(work + '/provenance.json', json2.Any(report))!
	if options.has('--prepare-only') {
		print_json(json2.Any(report))
		return 0
	}
	configured := launch(work, tar, 2048, 4, root(), false)!
	report['boot_command'] = json2.Any(hosttest.strings(configured.command))
	status := guesthost.boot(configured.command, configured.env, work, ['VINIX-DOTA2-ENV-PAIR-END'], [
		'KERNEL PANIC',
		'FATAL EXCEPTION',
		'VINIX-DOTA2-ENV-PAIR-ABORT',
	], seconds, true)!
	verdict := transcriptcore.environment_verdict(guesthost.replacement_text(os.read_bytes(work + '/serial.log')!), status == 0)
	report['vm_started'] = json2.Any(true)
	report['host_harness_status'] = json2.Any(status)
	report['log'] = json2.Any(work + '/serial.log')
	report['log_sha256'] = json2.Any(hosttest.sha(work + '/serial.log')!)
	output := merge_report(report, environment_json(verdict))
	os.write_file(work + '/results.json', output + '\n')!
	println(output)
	return if verdict.passed { 0 } else { 1 }
}
