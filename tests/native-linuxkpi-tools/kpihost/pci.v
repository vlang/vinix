// SPDX-License-Identifier: GPL-2.0-or-later
module kpihost

import cachecli
import crypto.sha256
import gamehost
import hosttest
import json2
import os
import sourcecommand

fn normalize_pci_typedefs(raw string) !(string, []string) {
	allowed := ['Actor', 'CommandCase', 'Interior', 'Observed', 'TestDevice']
	mut seen := map[string]bool{}
	mut removed := []string{}
	mut kept := []string{}
	for row in raw.split('\n') {
		name := row.all_after('typedef struct configfixture__').all_before(' ')
		if name in allowed && row == 'typedef struct configfixture__' + name + ' configfixture__' + name + ';' {
			if row in seen {
				if row in removed {
					return error('unexpected repeated V forward typedef scaffolding')
				}
				removed << row
				continue
			}
			seen[row] = true
		}
		kept << row
	}
	if removed.len > allowed.len {
		return error('unexpected repeated V forward typedef scaffolding')
	}
	return kept.join('\n'), removed
}

pub fn pci_cli(tools Tools, argv []string) !int {
	args := cachecli.arguments(argv, ['--source', '--keep-dir'], [], [], 0, 0, 'Compile the actual PCI config core and independent oracle with native sanitizers.\nUsage: pci-config [--source IMMUTABLE_C --keep-dir NEW_DIRECTORY]') or { return error_with_code(err.msg(), 2) }
	temporary := '--keep-dir' !in args.options
	work := if temporary {
		sourcecommand.temporary('vinix-pci-config-')!
	} else {
		hosttest.module_resolve(args.required('--keep-dir')!)!
	}
	if !temporary { os.mkdir(work)! }
	defer { if temporary { gamehost.remove(work) or {} } }
	exercise_pci(tools, work, args.value('--source', ''))!
	return 0
}

pub fn exercise_pci(tools Tools, work string, original string) ! {
	gamehost.mkdir(work)!
	selection := tools.command(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"',
		'selected-v', tools.root], os.environ())!
	if selection.status != 0 { return error(selection.stderr) }
	selected := selection.stdout
	mut environment := os.environ()
	environment['VEXE'] = selected
	environment['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	tools.checked([selected, '-shared', '-no-builtin', '-os', 'vinix', '-target-libc-headers',
		'-nofloat', '-gc', 'none', '-manualfree', '-o', work + '/core.c',
		tools.root + '/kernel/pci/config_core.v'], environment)!
	arch := host_arch()!
	mut fixture := ''
	if original == '' {
		fixture = work + '/fixture.c'
		tools.generate_module(tools.root + '/tests/pci-config/configfixture', fixture, arch, ['nofloat'])!
		raw := os.read_file(fixture)!
		os.write_file(work + '/fixture-raw.c', raw)!
		normalized, removed := normalize_pci_typedefs(raw)!
		os.write_file(fixture, normalized)!
		os.write_file(work + '/typedef-normalization.json', json2.encode(json2.Any({
			'removed_byte_identical_lines': json2.Any(removed.map(json2.Any(it)))
			'raw_sha256':                   json2.Any(sha256.hexhash(raw))
			'normalized_sha256':            json2.Any(sha256.hexhash(normalized))
		}),
			prettify: true
		) + '\n')!
	} else {
		fixture = hosttest.module_resolve(original)!
		if !os.is_file(fixture) || os.lstat(fixture)!.get_filetype() != .regular {
			return error('control source is not a file')
		}
	}
	compiler := gamehost.env('CC', 'clang')
	cc := [compiler, ...clang_host_flags(arch)]
	mut paths := ['kernel/pci/config_core.v', 'kernel/c/pci_config.h', 'tests/pci-config/run.sh',
		'build-support/find-v.sh', 'build-support/compile-v-module',
		'tests/native-linuxkpi-tools/kpihost/pci.v'].map(tools.root + '/' + it)
	paths << [work + '/core.c', fixture]
	if original == '' { paths << gamehost.files(tools.root + '/tests/pci-config/configfixture')! }
	mut inputs := map[string]json2.Any{}
	for path in paths {
		if os.lstat(path)!.get_filetype() == .regular {
			inputs[path] = json2.Any({
				'sha256': json2.Any(gamehost.digest(path)!)
				'bytes':  json2.Any(os.file_size(path))
			})
		}
	}
	version := tools.command([selected, 'version'], environment)!
	cc_version := tools.command([compiler, '--version'], environment)!
	if version.status != 0 || cc_version.status != 0 {
		return error('compiler version query failed')
	}
	environment['ASAN_OPTIONS'] = gamehost.env('ASAN_OPTIONS', 'detect_leaks=0:halt_on_error=1')
	environment['UBSAN_OPTIONS'] = gamehost.env('UBSAN_OPTIONS', 'halt_on_error=1')
	receipt := json2.Any({
		'fixture':       json2.Any(if original == '' { 'maintained-V' } else { 'original-C' })
		'host':          json2.Any(os.uname().machine)
		'v_version':     json2.Any(version.stdout.trim_space())
		'cc_version':    json2.Any(cc_version.stdout.split_into_lines()[0])
		'sanitizers':    json2.Any(['address', 'undefined'].map(json2.Any(it)))
		'asan_options':  json2.Any(environment['ASAN_OPTIONS'])
		'ubsan_options': json2.Any(environment['UBSAN_OPTIONS'])
		'inputs':        json2.Any(inputs)
	})
	os.write_file(work + '/inputs.json', json2.encode(receipt, prettify: true) + '\n')!
	for dialect in ['gnu99', 'gnu11'] {
		flags := [...cc, '-std=' + dialect, '-O1', '-g', '-Wall', '-Wextra', '-Werror', '-pthread',
			'-fsanitize=address,undefined', '-fno-omit-frame-pointer']
		tools.checked([...flags, '-Wno-unused-function', '-I', tools.root + '/kernel/c',
			'-ffreestanding', '-fno-builtin', '-fno-strict-aliasing', '-Dmalloc=vinix_pci_test_malloc',
			'-Dcalloc=vinix_pci_test_calloc', '-Drealloc=vinix_pci_test_realloc',
			'-Dfree=vinix_pci_test_free', '-c', work + '/core.c', '-o',
			work + '/core-' + dialect + '.o'], environment)!
		mut input := fixture
		if original == '' {
			input = work + '/fixture-' + dialect + '.o'
			tools.checked([...flags, '-Wno-unused-function', '-Wno-unused-parameter', '-fPIC',
				'-idirafter', tools.root + '/kernel/c', '-I',
				tools.root + '/tests/pci-config/configfixture', '-c', fixture, '-o', input], environment)!
		}
		tools.checked([...flags, input, work + '/core-' + dialect + '.o', '-o',
			work + '/test-' + dialect], environment)!
		result := tools.command([work + '/test-' + dialect], environment)!
		os.write_file(work + '/test-' + dialect + '.log', result.stdout + result.stderr)!
		if result.status != 0 {
			return error_with_code('PCI native oracle failed: ' + result.stdout + result.stderr, if result.status > 0 {
				result.status
			} else {
				1
			})
		}
		print(result.stdout + result.stderr)
	}
}
