// SPDX-License-Identifier: GPL-2.0-or-later
// Genuine configured-header selection, inspected with compiler metadata only.
module main

import os
import json2
import hosttest

const scope = 'Validate original x86 ARCH_HAS_MEM_ENCRYPT selection, disabled SME/SEV masks and both include routes. Configured AMD/X86 encryption retains real unresolved state and initialization; this test implements no encryption service. A private --profile-header permits review before integrating the single configuration selection.'

fn require(condition bool, message string) ! {
	if !condition { return error(message) }
}

fn defines(text string, name string) bool {
	return text.split_into_lines().any(it.fields().len >= 2 && it.fields()[0] == '#define' && it.fields()[1] == name)
}

fn original_selection(work string, linux string, pin map[string]json2.Any) !json2.Any {
	archive := os.join_path(os.dir(linux), 'linux-' + pin['version']!.str() + '.tar.xz')
	require(hosttest.sha(archive)! == pin['sha256']!.str(), 'Pinned original archive changed')!
	name := 'linux-' + pin['version']!.str() + '/arch/x86/Kconfig'
	members := hosttest.archive_members(archive, [name])!
	bytes := members[name] or { return error('Missing original x86 Kconfig') }
	path := work + '/original-x86-Kconfig'
	os.write_file_array(path, bytes)!
	text := bytes.bytestr()
	start := text.index('\nconfig X86\n') or { return error('Missing original X86 configuration') }
	end := text.index_after('\nconfig ', start + 1) or { return error('Unterminated original X86 configuration') }
	selection := text[start..end].split_into_lines().filter(it.fields() == ['select',
		'ARCH_HAS_MEM_ENCRYPT'])
	require(selection.len == 1, 'ARCH_HAS_MEM_ENCRYPT is not the original unconditional X86 selection')!
	require(text.contains('config X86_MEM_ENCRYPT\n') && text.contains('config AMD_MEM_ENCRYPT\n'), 'Original service configuration changed')!
	return {
		'archive_sha256':     pin['sha256']!
		'kconfig_sha256':     hosttest.sha(path)!
		'original_selection': json2.Any(selection[0].trim_space())
	}
}

fn profile(work string, name string, header string) !string {
	path := work + '/' + name
	os.mkdir_all(path + '/generated')!
	os.write_file(path + '/generated/autoconf.h', header)!
	return path
}

fn run(keep string, requested_header string) ! {
	root := hosttest.root()
	linux := hosttest.env_default('LINUXKPI_SOURCE_DIR', root + '/third_party/linux-i915/linux-6.6.157')
	pin := hosttest.upstream_pin()!
	hosttest.verify_upstream(linux, pin)!
	header := if requested_header == '' {
		root + '/kernel/linuxkpi/include/generated/autoconf.h'
	} else {
		os.real_path(requested_header)
	}
	text := os.read_file(header)!
	require(defines(text, 'CONFIG_X86') && defines(text, 'CONFIG_X86_64') && defines(text, 'CONFIG_ARCH_HAS_MEM_ENCRYPT'), 'Profile must supply original x86 architecture selection')!
	for disabled in ['CONFIG_AMD_MEM_ENCRYPT', 'CONFIG_X86_MEM_ENCRYPT', 'CONFIG_ARCH_HAS_CC_PLATFORM'] {
		require(!defines(text, disabled), 'Unsupported native encryption configuration: ' + disabled)!
	}
	work := hosttest.work_dir(keep, 'vinix-mem-encrypt-policy-')!
	defer { if keep == '' { hosttest.remove_work_dir(work) or { eprintln(err) } } }
	contract := root + '/tests/linuxkpi/memencryptfixture/contract.h'
	compiler := os.real_path(os.find_abs_path_of_executable(hosttest.env_default('CC', 'clang'))!)
	object_tool := hosttest.tool('llvm-nm')
	mut inputs := [@FILE, contract, header, root + '/kernel/linuxkpi/upstream.json', compiler,
		object_tool, os.executable()]
	for path in os.walk_ext(root + '/tests/linuxkpi/hosttest', '.v') { inputs << path }
	for path in os.walk_ext(root + '/kernel/linuxkpi/abi', '.json') { inputs << path }
	for path in os.walk_ext(root + '/kernel/linuxkpi/headercore', '.v') { inputs << path }
	initial := hosttest.hashes(inputs)!
	selection := original_selection(work, linux, pin)!
	hosttest.audit_headers(work + '/abi')!
	active := profile(work, 'disabled-profile', text)!
	missing := profile(work, 'missing-selection-profile', text.split_into_lines().filter(!it.fields().contains('CONFIG_ARCH_HAS_MEM_ENCRYPT')).join('\n') + '\n')!
	configured := profile(work, 'configured-control-profile', text + '\n#define CONFIG_AMD_MEM_ENCRYPT 1\n#define CONFIG_X86_MEM_ENCRYPT 1\n#define CONFIG_ARCH_HAS_CC_PLATFORM 1\n#define CONFIG_DYNAMIC_PHYSICAL_MASK 1\n')!
	source := work + '/metadata.c'
	os.write_file(source, '#include "memencryptfixture/contract.h"\n')!
	mut results := []json2.Any{}
	mut environment := os.environ()
	for standard in ['gnu99', 'gnu11'] {
		for page_first in [false, true]! {
			for kind in ['disabled', 'configured', 'missing'] {
				name := standard + (if page_first { '-page-first-' } else { '-memory-first-' }) + kind
				selected := if kind == 'disabled' {
					active
				} else if kind == 'configured' {
					configured
				} else {
					missing
				}
				mut argv := [compiler, '--target=x86_64-unknown-none', '-std=' + standard, '-O2',
					'-ffreestanding', '-fno-builtin', '-fwrapv', '-Wall', '-Wextra', '-Werror',
					'-Wno-unused-parameter', '-Wno-unused-function', '-nostdinc', '-D__KERNEL__',
					'-DVINIX_LINUXKPI', '-include', 'linux/kconfig.h', '-include',
					linux + '/include/linux/compiler_types.h']
				if page_first { argv << '-DVINIX_MEM_ENCRYPT_PAGE_FIRST' }
				if kind == 'configured' { argv << '-DVINIX_MEM_ENCRYPT_CONFIGURED' }
				for path in [selected, work + '/abi', root + '/tests/linuxkpi',
					root + '/kernel/linuxkpi/include', linux + '/include', linux + '/include/uapi',
					linux + '/arch/x86/include', linux + '/arch/x86/include/uapi'] {
					argv << ['-I', path]
				}
				argv << ['-isystem', root + '/kernel/freestnd-c-hdrs']
				object := work + '/' + name + '.o'
				compile := [...argv, '-c', source, '-o', object]
				mut imports := []string{}
				mut object_hash := ''
				mut dependencies := map[string]string{}
				mut paths := []string{}
				mut preprocessed_hash := ''
				if kind != 'missing' {
					depfile := work + '/' + name + '.d'
					preprocessed := work + '/' + name + '.i'
					hosttest.command([...argv, '-E', '-dD', '-MD', '-MF', depfile, '-MT', object,
						source, '-o', preprocessed], work + '/' + name + '.preprocess.log', 120, environment)!
					paths = hosttest.dependency_paths(os.read_file(depfile)!, object)!
					dependencies = hosttest.hashes(paths)!
					preprocessed_hash = hosttest.sha(preprocessed)!
				}
				result := hosttest.capture(compile, work + '/' + name + '.compile.log', 120, environment)!
				if kind == 'missing' {
					require(result.code != 0 && result.stderr.contains('original X86 architecture selection is required'), 'Missing architecture selection unexpectedly compiled')!
				} else {
					require(result.code == 0, result.stderr)!
					undefined := hosttest.command([object_tool, '--undefined-only', object],
						work + '/' + name + '.imports.log', 30, environment)!.stdout
					for line in undefined.split_into_lines() { imports << line.fields().last() }
					imports.sort()
					expected := if kind == 'configured' {
						['cc_platform_has', 'mem_encrypt_init', 'sev_status', 'sme_me_mask']
					} else {
						[]string{}
					}
					require(imports == expected && !hosttest.allocation_symbols(undefined), 'Unexpected encryption runtime imports: ' + undefined)!
					object_hash = hosttest.sha(object)!
					require(dependencies == hosttest.hashes(paths)!, 'Compiler inputs changed during the profile')!
				}
				results << json2.Any({
					'standard':            json2.Any(standard)
					'page_first':          page_first
					'profile':             kind
					'actual_exit':         result.code
					'argv':                hosttest.strings(compile)
					'object_sha256':       object_hash
					'preprocessed_sha256': preprocessed_hash
					'unresolved':          hosttest.strings(imports)
					'dependency_sha256':   hosttest.string_map(dependencies)
				})
				println(name + ': expected compiler result ' + result.code.str())
			}
		}
	}
	require(initial == hosttest.hashes(inputs)!, 'Profile or test sources changed during validation')!
	hosttest.verify_upstream(linux, pin)!
	hosttest.write_json(work + '/result.json', {
		'scope':                    json2.Any(scope)
		'source_sha256':            hosttest.string_map(initial)
		'profile_header':           header
		'using_repository_profile': requested_header == ''
		'original_kconfig':         selection
		'compiler_metadata_only':   true
		'profiles':                 results
	})!
}

fn main() {
	options := hosttest.parse_path_options(os.args[1..], ['--keep-dir', '--profile-header'],
		'Usage: mem_encrypt_policy.v [--keep-dir NEW] [--profile-header FILE]', scope) or {
		eprintln(err)
		exit(2)
	}
	run(options['--keep-dir'], options['--profile-header']) or {
		eprintln(err)
		exit(1)
	}
}
