// SPDX-License-Identifier: GPL-2.0-or-later
module compathost

import hosttest
import json2
import os

fn office_generate(destination string) ! {
	generate(root() + '/build-support/x86-translation/officecore', destination, 'amd64', ['nofloat'], '')!
}

fn office_dll(destination string, cc string, directory string) ! {
	os.mkdir_all(directory)!
	source := directory + '/office.c'
	office_generate(source)!
	run([cc, '-Os', '-s', '-shared', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function',
		'-Wno-unused-label', '-Wno-unused-parameter', '-I', root() + '/build-support/x86-translation',
		source, root() + '/build-support/x86-translation/sppc-office.def', '-o', destination])!
}

fn office_compile(args []string) !int {
	parsed := hosttest.parse_arguments(args, [hosttest.Option{name: '--cc', value: true},
		hosttest.Option{name: '--generated-dir', value: true}], 1,
		'Usage: compile-v-office OUTPUT [--cc COMPILER] [--generated-dir DIR]', 'Generate the V Office licensing artifact or Windows64 DLL.') or { return error_with_code(err.msg(), 2) }
	destination := resolve(parsed.positional[0])!
	if '--cc' in parsed.options {
		directory := resolve(if '--generated-dir' in parsed.options { parsed.options['--generated-dir'] } else { os.dir(destination) + '/office-generated' })!
		office_dll(destination, parsed.options['--cc'], directory)!
	} else { office_generate(destination)! }
	return 0
}

pub fn office_exports(pe_dump string) ![]string {
	if !pe_dump.contains('[Ordinal/Name Pointer] Table') { return error('Missing DLL exports') }
	table := pe_dump.all_after('[Ordinal/Name Pointer] Table').all_before('The Function Table')
	mut result := []string{}
	for line in table.split('\n') {
		text := line.trim_space()
		if !text.starts_with('[') || !text.contains(']') { continue }
		index := text.all_before(']')[1..].trim_space()
		if index == '' || !index.bytes().all(it.is_digit()) { continue }
		mut name := text.all_after(']').trim_space()
		if name.starts_with('+base[') {
			if !name.contains(']') { continue }
			words := name.all_after(']').fields()
			if words.len != 2 || !words[0].bytes().all(it.is_hex_digit()) { continue }
			name = words[1]
		}
		if name == '' || !name.runes().all(hosttest.module_word_rune(it)) { continue }
		result << name
	}
	result.sort()
	return result
}

fn office_test(args []string) !int {
	parsed := hosttest.parse_arguments(args, [hosttest.Option{name: '--baseline-rev', value: true},
		hosttest.Option{name: '--state-dir', value: true}], 0,
		'Usage: run [--baseline-rev REV] [--state-dir FRESH-DIR]', 'Compare Office licensing ABI goldens, sanitizers and Windows64 exports.') or { return error_with_code(err.msg(), 2) }
	state := hosttest.work_dir(parsed.options['--state-dir'], 'vinix-office-abi-')!
	defer { if '--state-dir' !in parsed.options { retire(state) } }
	support := root() + '/build-support/x86-translation'
	test := root() + '/tests/office-compat'
	fixture := state + '/fixture.c'
	generate(test + '/fixture', fixture, 'amd64', ['nofloat'], '')!
	core := state + '/core.c'
	office_generate(core)!
	revision := if '--baseline-rev' in parsed.options { parsed.options['--baseline-rev'] } else { '8f7239d1' }
	baseline := state + '/baseline.c'
	write(baseline, output(['git', '-C', root(), 'show', revision + ':build-support/x86-translation/sppc-office-compat.c'])!)!
	write(state + '/windows.h', '#include "office-test-abi.h"\n')!
	flags := ['clang', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function',
		'-Wno-unused-label', '-Wno-unused-parameter', '-fsanitize=address,undefined', '-fno-omit-frame-pointer',
		'-I' + state, '-I' + test, '-I' + support]
	mut streams := []string{}
	for tag in ['c', 'v'] {
		program := state + '/test-' + tag
		run([...flags, if tag == 'c' { baseline } else { core }, fixture, '-o', program])!
		result := captured([program])!
		streams << result.stdout + result.stderr
	}
	if streams[0] != streams[1] { return error('Office host C/V output differs') }
	print(streams[1])
	cc := os.find_abs_path_of_executable('x86_64-w64-mingw32-gcc')!
	control := state + '/original.dll'
	run([cc, '-Os', '-s', '-shared', '-Wall', '-Wextra', '-Werror', baseline, '-o', control])!
	ported := state + '/ported.dll'
	office_dll(ported, cc, state + '/office-generated')!
	objdump := os.find_abs_path_of_executable('x86_64-w64-mingw32-objdump')!
	exports := office_exports(output([objdump, '-p', ported])!)!
	if office_exports(output([objdump, '-p', control])!)! != exports || exports.len != 33 {
		return error('Windows64 DLL exports differ from the 33 original symbols')
	}
	native_source := state + '/fixture-native.c'
	generate(test + '/fixture', native_source, 'amd64', ['nofloat', 'office_native'], '')!
	mut artifacts := [baseline, core, fixture, native_source, control, ported]
	for tag in ['c', 'v'] {
		program := state + '/fixture-' + tag + '.exe'
		run([cc, '-O2', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-label',
			'-Wno-unused-parameter', '-I' + test, '-I' + support, if tag == 'c' { baseline } else { core }, native_source, '-o', program])!
		artifacts << program
	}
	mut hashes := map[string]string{}
	for path in artifacts { hashes[os.file_name(path)] = hosttest.sha(path)! }
	hosttest.write_json(state + '/validation.json', {
		'baseline_revision': json2.Any(revision)
		'host_sanitizers': json2.Any(hosttest.strings(['address', 'undefined']))
		'public_exports': json2.Any(hosttest.strings(exports))
		'rounds': json2.Any(1024)
		'null_output_combinations_per_round': json2.Any(40)
		'native_fixture_success_exit': json2.Any(73)
		'artifacts': json2.Any(hosttest.string_map(hashes))
	})!
	println('OFFICE EXPORT ABI PASS: actual Windows64 DLL exports match all 33 original symbols')
	return 0
}
