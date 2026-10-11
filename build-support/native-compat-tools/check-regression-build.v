// SPDX-License-Identifier: GPL-2.0-or-later
module main

import fixturehost
import hosttest
import json2
import os
import policyhost

fn values(item json2.Any) []string { return item.as_array().map(it.str()) }

fn elf(path string, arch string, dynamic bool) ! {
	data := os.read_bytes(path)!
	if data.len < 64 || data[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1] { return error('Invalid ELF: ' + path) }
	if int(data[18]) + (int(data[19]) << 8) != if arch == 'aarch64' { 183 } else { 62 } { return error('Wrong ELF architecture') }
	if !dynamic { return }
	if data[16] != 3 || data[17] != 0 { return error('PIE is not ET_DYN') }
	mut offset := u64(0)
	for index in 0 .. 8 { offset |= u64(data[32 + index]) << (8 * index) }
	width := int(data[54]) + (int(data[55]) << 8)
	count := int(data[56]) + (int(data[57]) << 8)
	mut interpreter := false
	mut table := false
	for index in 0 .. count {
		start := int(offset) + index * width
		if start < 0 || width < 56 || start + width > data.len { return error('Invalid ELF program headers') }
		kind := int(data[start]) + (int(data[start + 1]) << 8)
		if kind == 3 { interpreter = true }
		if kind == 2 { table = true }
	}
	if !interpreter || !table { return error('PIE lacks actual interpreter or dynamic table') }
}

fn qualify(binary string, profile string, cache string) ! {
	mut env := policyhost.environment()
	env['ASAN_OPTIONS'] = 'detect_leaks=0'
	for family in ['kernel-cpu', 'kernel-job-control', 'kernel-sysvmsg', 'kernel-retention', 'elf-text', 'userland-demo', 'uname'] {
		arches := if family in ['kernel-cpu', 'kernel-job-control', 'kernel-sysvmsg', 'uname'] { ['aarch64'] } else { ['aarch64', 'x86_64'] }
		for arch in arches {
			kernel := os.getenv_opt(if arch == 'aarch64' { 'VINIX_PROCESS_TEST_ARM_KERNEL' } else { 'VINIX_PROCESS_TEST_X86_KERNEL' }) or {
				hosttest.root() + if arch == 'aarch64' { '/build-aarch64-kernel' } else { '/build-amd64-kernel' }
			}
			work := cache + '/' + profile + '-' + family + '-' + arch
			mut argv := [binary, family, '--state-dir', work, '--build-only']
			if family.starts_with('kernel-') && family != 'kernel-retention' { argv << ['--kernel', kernel] } else { argv << ['--kernel-dir', kernel] }
			if family !in ['kernel-cpu', 'kernel-job-control', 'kernel-sysvmsg', 'uname'] { argv << ['--arch', arch] }
			if family == 'kernel-retention' { argv << ['--guest-state-dir', work + '-guest'] }
			result := fixturehost.capture_both_preferred(argv, env, policyhost.caller_arch())!
			os.write_file(work + '.log', result.stdout + result.stderr)!
			if result.status != 0 { return error('Cross-build failed: ' + work + '\n' + result.stderr) }
			mut programs := []string{}
			if family == 'kernel-retention' {
				programs = ['original-init', 'v-init']
				data := hosttest.decode_json(os.read_file(work + '/validation.json')!)!.as_map()
				original := policyhost.capture(['git', '-C', hosttest.root(), 'show', '94143cac914e30d8dc14871eb3163a9e2e31cded:tests/kernel-retention/test.c'])!
				if os.read_file(work + '/original.c')! != original || hosttest.text_sha(original) != (data['original_sha256'] or { return error('Missing control hash') }).str() { return error('Immutable retention C control differs') }
				flags := values(data['compiler_flags'] or { return error('Missing retention recipe') })
				mut recipe := flags[..flags.index('-std=gnu11')].clone()
				if arch == 'aarch64' { recipe << '-fuse-ld=lld' }
				recipe << ['-static', work + '/original.o', work + '/serial.o', '-o', work + '/original-recipe']
				fixturehost.inherited_command_environment_preferred(recipe, env, policyhost.caller_arch())!
				if os.read_bytes(work + '/original-init')! != os.read_bytes(work + '/original-recipe')! { return error('Retention C link bytes differ') }
			} else {
				data := hosttest.decode_json(os.read_file(work + '/inputs.json')!)!.as_map()
				programs = match family {
					'kernel-cpu' { ['cpu-check'] }
					'kernel-job-control' { ['job-check'] }
					'kernel-sysvmsg' { ['msg-check'] }
					'elf-text' { ['rootfs/sbin/init', 'rootfs/elf-pie'] }
					'uname' { ['rootfs/bin/busybox'] }
					else { ['init'] }
				}
				if family != 'uname' {
					commands := if family == 'elf-text' { (data['commands'] or { return error('Missing ELF recipes') }).as_array() } else { [data['compile_command'] or { return error('Missing compiler recipe') }] }
					for item in commands {
						mut recipe := values(item)
						before := recipe.last()
						recipe[recipe.len - 1] = before + '-recipe'
						fixturehost.inherited_command_environment_preferred(recipe, env, policyhost.caller_arch())!
						if os.read_bytes(before)! != os.read_bytes(before + '-recipe')! { return error('Original recipe replay bytes differ: ' + before) }
					}
				}
				if family == 'userland-demo' && os.read_file(work + '/stdout')! != 'Hello world\nHello from Alpine GCC on Vinix!\nHello from Alpine GCC on Vinix/amd64!\nUSERLAND DEMO V PASS\n' { return error('Host greeting differs') }
			}
			for name in programs { elf(work + '/' + name, arch, name == 'rootfs/elf-pie')! }
			println('Native ELF/control and original recipe replay PASS: ' + profile + ' ' + family + ' ' + arch)
		}
	}
}

fn main() {
	if os.args.len != 4 { eprintln('Usage: check-regression-build.v CONTROLLER PROFILE CACHE'); exit(2) }
	qualify(os.args[1], os.args[2], os.args[3]) or { eprintln(err.msg()); exit(1) }
}
