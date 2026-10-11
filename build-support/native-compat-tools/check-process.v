// SPDX-License-Identifier: GPL-2.0-or-later
module main

import fixturehost
import hosttest
import json2
import os
import policyhost

const families = ['process-smp', 'scheduler-qos', 'tlb', 'memory-retention', 'listen-backlog',
	'resource-open', 'proc-thread-lock', 'proc-map-lookup', 'aarch64-sigreturn']

fn verify_elf(path string, arch string) ! {
	bytes := os.read_bytes(path)!
	if bytes.len < 20 || bytes[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
		|| int(bytes[18]) + (int(bytes[19]) << 8) != if arch == 'aarch64' { 183 } else { 62 } {
		return error('Incorrect native ELF architecture: ' + path)
	}
}

fn values(value json2.Any) []string { return value.as_array().map(it.str()) }

fn qualify(binary string, profile string, selected string) ! {
	mut env := policyhost.environment()
	env['V'] = os.getenv_opt('V') or { '/tmp/vinix-native-v-compiler/v' }
	env['VEXE'] = env['V']
	env['V_MACOS_V3_NO_FALLBACK'] = '1'
	env['ASAN_OPTIONS'] = 'detect_leaks=0'
	for family in families {
		if selected != '' && selected != family { continue }
		for option, status in {'--help': 0, '--unknown': 2} {
			result := fixturehost.capture_both_preferred([binary, family, option], env, policyhost.caller_arch())!
			if result.status != status { return error('Incorrect CLI status: ' + family + ' ' + option) }
		}
	}
	for family in families {
		if selected != '' && selected != family { continue }
		for arch in if family == 'aarch64-sigreturn' { ['aarch64'] } else { ['aarch64', 'x86_64'] } {
			work := (os.getenv_opt('VINIX_PROCESS_TEST_BUILD_PREFIX') or { '/tmp/vinix-process-build-' }) + profile + '-' + family + '-' + arch
			kernel := if arch == 'aarch64' {
				os.getenv_opt('VINIX_PROCESS_TEST_ARM_KERNEL') or { '/tmp/vinix-volume-guest-arm-final/kernel' }
			} else {
				os.getenv_opt('VINIX_PROCESS_TEST_X86_KERNEL') or { '/tmp/vinix-xinput-guest-x86/kernel' }
			}
			mut argv := [binary, family, '--state-dir', work, '--kernel-dir', kernel, '--build-only']
			if family != 'aarch64-sigreturn' { argv << ['--arch', arch] }
			if family in ['resource-open', 'proc-thread-lock', 'proc-map-lookup'] { argv << ['--guest-state-dir', work + '-guest'] }
			result := fixturehost.capture_both_preferred(argv, env, policyhost.caller_arch())!
			os.write_file(work + '.log', result.stdout + result.stderr)!
			if result.status != 0 { return error('Native cross-build failed: ' + work + '\n' + result.stderr) }
			mut executables := []string{}
			if family in ['resource-open', 'proc-thread-lock', 'proc-map-lookup'] {
				executables = ['original-init', 'v-init']
				data := hosttest.decode_json(os.read_file(work + '/validation.json')!)!.as_map()
				original := policyhost.capture(['git', '-C', hosttest.root(), 'show',
					(data['original_revision'] or { return error('Missing control revision') }).str() + ':tests/' + family + '/test.c'])!
				if os.read_file(work + '/original.c')! != original { return error('Original C bytes differ') }
				if hosttest.text_sha(original) != (data['original_sha256'] or { return error('Missing control hash') }).str() { return error('Original C hash differs') }
				variants := (data['variants'] or { return error('Missing variants') }).as_map()
				for variant in ['original', 'v'] {
					item := (variants[variant] or { return error('Missing variant') }).as_map()
					if hosttest.sha(work + '/' + variant + '-init')! != (item['program_sha256'] or { return error('Missing ELF hash') }).str() { return error('ELF receipt differs') }
				}
				// Independently replay the original link recipe using its unchanged
				// C/serial objects; output names cannot affect the linked bytes.
				flags := values(data['compiler_flags'] or { return error('Missing compiler flags') })
				end := flags.index('-std=gnu11')
				mut recipe := flags[..end].clone()
				if arch == 'aarch64' { recipe << '-fuse-ld=lld' }
				recipe << '-static'
				if family != 'resource-open' { recipe << '-pthread' }
				recipe << [work + '/original.o', work + '/serial.o', '-o', work + '/original-recipe']
				fixturehost.inherited_command_environment_preferred(recipe, env, policyhost.caller_arch())!
				if os.read_bytes(work + '/original-init')! != os.read_bytes(work + '/original-recipe')! { return error('Original C link bytes differ') }
			} else if family == 'aarch64-sigreturn' {
				executables = ['init', 'signal-return-probe']
				data := hosttest.decode_json(os.read_file(work + '/build.json')!)!.as_map()
				commands := (data['commands'] or { return error('Missing compiler recipes') }).as_array()
				for item in commands {
					mut recipe := values(item)
					before := recipe.last()
					recipe[recipe.len - 1] = before + '-recipe'
					fixturehost.inherited_command_environment_preferred(recipe, env, policyhost.caller_arch())!
					if os.read_bytes(before)! != os.read_bytes(before + '-recipe')! { return error('Signal C recipe bytes differ') }
				}
				for section in ['inputs', 'outputs'] {
					for name, hash in (data[section] or { return error('Missing build hashes') }).as_map() {
						if hosttest.sha(if section == 'inputs' { name } else { work + '/' + name })! != hash.str() { return error('Signal build hash differs') }
					}
				}
			} else {
				executables = ['init']
				data := hosttest.decode_json(os.read_file(work + '/inputs.json')!)!.as_map()
				if hosttest.sha(work + '/init')! != (data['init_sha256'] or { return error('Missing init hash') }).str() { return error('Init hash differs') }
				if family != 'listen-backlog' {
					mut recipe := values(data['compile_command'] or { return error('Missing process recipe') })
					recipe[recipe.len - 1] = work + '/original-recipe'
					fixturehost.inherited_command_environment_preferred(recipe, env, policyhost.caller_arch())!
					if os.read_bytes(work + '/init')! != os.read_bytes(work + '/original-recipe')! { return error('Process recipe bytes differ') }
				}
			}
			for name in executables { verify_elf(work + '/' + name, arch)! }
			println('Native cross-build, original recipe/control hashes and ELF PASS: ' + profile + ' ' + family + ' ' + arch)
		}
	}
}

fn main() {
	if os.args.len !in [3, 4] { eprintln('Usage: check-process.v CONTROLLER PROFILE [FAMILY]'); exit(2) }
	selected := if os.args.len == 4 { os.args[3] } else { '' }
	if selected != '' && selected !in families { eprintln('Unknown process family'); exit(2) }
	qualify(os.args[1], os.args[2], selected) or { eprintln(err.msg()); exit(1) }
}
