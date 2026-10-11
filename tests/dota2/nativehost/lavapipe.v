// SPDX-License-Identifier: GPL-2.0-or-later
module nativehost

import buildcore
import guesthost
import hosttest
import json2
import os

pub const lava_modes = ['bound', 'null-set', 'absent-layout', 'absent-first-set']

pub fn runtime_closure(readelf string, runtime string, roots []string) !map[string]Pin {
	mut pins := map[string]Pin{}
	mut queue := roots.clone()
	for queue.len > 0 {
		current := queue.pop()
		for name in buildcore.needed(capture([readelf, '-d', current])!) {
			if name in pins { continue }
			mut found := ''
			for directory in ['usr/lib/x86_64-linux-gnu', 'lib/x86_64-linux-gnu'] {
				candidate := if name.starts_with('/') {
					name
				} else {
					runtime + '/' + directory + '/' + name
				}
				if os.is_file(candidate) {
					found = candidate
					break
				}
			}
			if found == '' { return argument('Private runtime lacks ' + name) }
			pin := elf_input(found, 62, 256 * 1024 * 1024)!
			pins[name] = pin
			queue << pin.resolved_source
		}
	}
	return pins
}

fn lavapipe(args []string) !int {
	options := parse(args, [hosttest.Option{ name: '--work', value: true },
		hosttest.Option{ name: '--fixed', value: true },
		hosttest.Option{ name: '--control', value: true },
		hosttest.Option{ name: '--runtime-root', value: true },
		hosttest.Option{ name: '--vulkan-include', value: true },
		hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--translator', value: true },
		hosttest.Option{ name: '--native-cc', value: true },
		hosttest.Option{ name: '--cc', value: true },
		hosttest.Option{ name: '--readelf', value: true },
		hosttest.Option{ name: '--memory-mib', value: true },
		hosttest.Option{ name: '--timeout', value: true }, hosttest.Option{ name: '--prepare-only' }], ['--control'], 'Usage: lavapipe-run --work NEW_DIR --fixed ELF --control ELF [--control ELF ...] [--prepare-only]')!
	required(options, ['--work', '--fixed', '--control'])!
	seconds := positive(options, '--timeout', 1800)!
	memory := positive(options, '--memory-mib', 4096)!
	if memory < 1024 { return argument('the guest needs at least 1 GiB') }
	work := resolve(options.value('--work', ''))!
	runtime := resolve(options.value('--runtime-root', root() + '/build/dota2-runtime/staging/usr/libexec/vinix-dota2/root'))!
	kernel_dir := resolve(options.value('--kernel-dir', root() + '/kernel'))!
	separate(work, [runtime, kernel_dir])!
	mut drivers := []string{}
	mut libraries := map[string]Pin{}
	mut digests := []string{}
	for index, source in [...options.values['--control'], options.value('--fixed', '')] {
		label := if index == options.values['--control'].len {
			'fixed'
		} else {
			'control-' + (index + 1).str()
		}
		pin := elf_input(source, 62, 256 * 1024 * 1024)!
		if pin.sha256 in digests {
			return argument('Every control must differ from the fixed driver and each other')
		}
		digests << pin.sha256
		libraries[label] = pin
		drivers << label
	}
	loader := elf_input(runtime + '/lib64/ld-linux-x86-64.so.2', 62, 256 * 1024 * 1024)!
	vulkan := elf_input(runtime + '/usr/lib/x86_64-linux-gnu/libvulkan.so.1', 62, 256 * 1024 * 1024)!
	readelf := options.value('--readelf', os.find_abs_path_of_executable('llvm-readelf') or { '/opt/homebrew/opt/llvm/bin/llvm-readelf' })
	closure := runtime_closure(readelf, runtime, [vulkan.resolved_source,
		...libraries.values().map(it.resolved_source)])!
	if 'libc.so.6' !in closure { return argument('Private runtime closure lacks libc.so.6') }
	translator := elf_input(options.value('--translator', root() + '/build/dota2-qemu/staging/usr/bin/qemu-x86_64'), 183, 32 * 1024 * 1024)!
	kernel := elf_input(kernel_dir + '/bin/vinix', 183, 64 * 1024 * 1024)!
	include := resolve(options.value('--vulkan-include', root() + '/build/dota2-runtime/mesa/source/include'))!
	if !os.is_file(include + '/vulkan/vulkan.h') {
		return argument('Missing Vulkan headers: ' + include)
	}
	native_cc := os.find_abs_path_of_executable(options.value('--native-cc', root() + '/build/dota2-qemu/aarch64-cc')) or { return argument(err.msg()) }
	cc := os.find_abs_path_of_executable(options.value('--cc', 'clang')) or { return argument(err.msg()) }
	fresh(work)!
	rootfs := work + '/root'
	directories(rootfs, ['sbin', 'etc', 'usr/bin', 'dev', 'proc', 'sys', 'tmp', 'root', 'runtime/icd'])!
	install_pin(loader, rootfs + '/runtime/lib64/ld-linux-x86-64.so.2')!
	install_pin(vulkan, rootfs + '/runtime/lib/libvulkan.so.1')!
	for name, pin in closure { install_pin(pin, rootfs + '/runtime/lib/' + name)! }
	for label, pin in libraries {
		install_pin(pin, rootfs + '/runtime/lib/libvulkan_lvp-' + label + '.so')!
		write_json(rootfs + '/runtime/icd/' + label + '.json', json2.Any({
			'file_format_version': json2.Any('1.0.0')
			'ICD':                 json2.Any({
				'library_path': json2.Any('/runtime/lib/libvulkan_lvp-' + label + '.so')
				'api_version':  json2.Any('1.3.230')
			})
		}))!
	}
	mut plan := ''
	for driver in drivers {
		for mode in lava_modes { plan += driver + ' ' + mode + '\n' }
	}
	os.write_file(rootfs + '/etc/vinix-lavapipe-plan', plan)!
	install_pin(translator, rootfs + '/usr/bin/qemu-x86_64')!
	install_pin(kernel, work + '/kernel/bin/vinix')!
	native := work + '/init'
	native_command := [native_cc, '-static', '-O2', '-Wall', '-Wextra', '-Werror',
		here() + '/lavapipe-native-wait.c', '-o', native]
	run(native_command)!
	install(native, rootfs + '/sbin/init')!
	probe := work + '/lavapipe-null-sets'
	probe_command := [cc, '--target=x86_64-linux-gnu', '-ffreestanding', '-nostdlibinc',
		'-I' + include, '-fPIE', '-pie', '-O2', '-fno-stack-protector', '-nostdlib', '-fuse-ld=lld',
		'-Wall', '-Wextra', '-Werror', '-Wl,--dynamic-linker=/lib64/ld-linux-x86-64.so.2',
		'-Wl,-e,_start', '-Wl,-z,now', here() + '/lavapipe-null-sets.c',
		closure['libc.so.6']!.resolved_source, vulkan.resolved_source, '-o', probe]
	run(probe_command)!
	install(probe, rootfs + '/usr/bin/lavapipe-null-sets')!
	tar := archive(rootfs, work, true)!
	mut report := {
		'probe_source_sha256':  json2.Any(hosttest.sha(here() + '/lavapipe-null-sets.c')!)
		'native_source_sha256': json2.Any(hosttest.sha(here() + '/lavapipe-native-wait.c')!)
		'probe_ELF_sha256':     json2.Any(hosttest.sha(probe)!)
		'probe_build_command':  json2.Any(hosttest.strings(probe_command))
		'native_init_sha256':   json2.Any(hosttest.sha(native)!)
		'native_build_command': json2.Any(hosttest.strings(native_command))
		'drivers':              json2.decode[json2.Any](json2.encode(libraries))!
		'loader':               json2.decode[json2.Any](json2.encode(loader))!
		'vulkan_loader':        json2.decode[json2.Any](json2.encode(vulkan))!
		'runtime_closure':      json2.decode[json2.Any](json2.encode(closure))!
		'translator':           json2.decode[json2.Any](json2.encode(translator))!
		'kernel':               json2.decode[json2.Any](json2.encode(kernel))!
		'modes':                json2.Any(hosttest.strings(lava_modes))
		'archive_sha256':       json2.Any(hosttest.sha(tar)!)
		'guest_memory_mib':     json2.Any(memory)
		'guest_cpus':           json2.Any(4)
		'host_timeout_seconds': json2.Any(seconds)
		'vm_started':           json2.Any(false)
		'proof_scope':          json2.Any('Lavapipe compute descriptor-set binding only; no game execution.')
	}
	write_json(work + '/provenance.json', json2.Any(report))!
	if options.has('--prepare-only') {
		print_json(json2.Any(report))
		return 0
	}
	configured := launch(work, tar, memory, 4, root(), false)!
	report['boot_command'] = json2.Any(hosttest.strings(configured.command))
	status := guesthost.boot(configured.command, configured.env, work, ['VINIX-DOTA2-LVP-PAIR-END'], [
		'KERNEL PANIC',
		'FATAL EXCEPTION',
		'VINIX-DOTA2-LVP-PAIR-ABORT',
	], seconds, true)!
	verdict := lava_verdict(guesthost.replacement_text(os.read_bytes(work + '/serial.log')!), status, drivers)!
	report['vm_started'] = json2.Any(true)
	report['host_harness_status'] = json2.Any(status)
	report['log'] = json2.Any(work + '/serial.log')
	report['log_sha256'] = json2.Any(hosttest.sha(work + '/serial.log')!)
	output := merge_report(report, verdict.json())
	os.write_file(work + '/results.json', output + '\n')!
	println(output)
	return if verdict.passed { 0 } else { 1 }
}
