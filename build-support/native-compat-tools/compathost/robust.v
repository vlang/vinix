// SPDX-License-Identifier: GPL-2.0-or-later
module compathost

import hosttest
import os

fn c_type(name string) !string {
	return match name {
		'voidptr' { 'void *' }
		'&char' { 'char *' }
		'i32' { 'int' }
		else { return error('Unknown diagnostic V type: ' + name) }
	}
}

// Derive the bare scaffold declarations from the production V imports.
pub fn diagnostic_declarations() !string {
	source := read(root() + '/build-support/steam/robustcore/core.v')!
	mut parameters := []string{}
	mut result_type := ''
	mut global_type := ''
	for line in source.split('\n') {
		if line.starts_with('fn C.fprintf(') {
			for parameter in line.all_after('fn C.fprintf(').all_before(')').split(',') {
				words := parameter.fields()
				if words.len != 2 { return error('Invalid fprintf declaration') }
				parameters << if words[0].starts_with('...') { '...' } else { c_type(words[1])! + ' ' + words[0] }
			}
			result_type = c_type(line.all_after(') ').trim_space())!
		}
		if line.starts_with('__global C.stderr ') { global_type = c_type(line.all_after('__global C.stderr ').trim_space())! }
	}
	if parameters.len == 0 || result_type == '' || global_type == '' { return error('Missing diagnostic declarations') }
	return '#if __has_include(<stdio.h>)\n#include <stdio.h>\n#else\n' + result_type +
		' fprintf(' + parameters.join(', ') + ');\nextern ' + global_type + ' stderr;\n#endif\n'
}

pub fn robust_generate(destination string, i386 bool, host bool) ! {
	work := hosttest.work_dir('', 'vinix-steam-robust-')!
	defer { retire(work) }
	source := work + '/robustcore'
	hosttest.module_copy_tree(root() + '/build-support/steam/robustcore', source)!
	if !i386 { os.rm(source + '/mapping.v')! }
	generate(source, destination, if i386 && !host { 'i386' } else { 'amd64' },
		if i386 { ['steam_i386'] } else { []string{} }, '')!
	mut layout := '\n_Static_assert(sizeof(size_t) == sizeof(void *) && sizeof(intptr_t) == sizeof(void *), "native pointer and C long ABI");\n'
	if i386 {
		layout += '_Static_assert(sizeof(robustcore__Mapping) == 3 * sizeof(void *) && offsetof(robustcore__Mapping, requested) == sizeof(void *) && offsetof(robustcore__Mapping, padded) == 2 * sizeof(void *), "mapping record ABI");\n'
	}
	write(destination, diagnostic_declarations()! + read(destination)!.replace('#include <inttypes.h>\n', '') + layout)!
}

fn robust_compile(args []string) !int {
	parsed := hosttest.parse_arguments(args, [hosttest.Option{name: '--i386'}, hosttest.Option{name: '--host'}], 1,
		'Usage: compile-v-robust OUTPUT [--i386] [--host]', 'Generate the translated Steam preload with V.') or { return error_with_code(err.msg(), 2) }
	robust_generate(resolve(parsed.positional[0])!, '--i386' in parsed.options, '--host' in parsed.options)!
	return 0
}

fn robust_remaps() []string {
	return ['-Ddlsym=robust_fixture_dlsym', '-Dpthread_self=robust_fixture_pthread_self',
		'-Dsyscall=robust_subject_syscall', '-Dmmap=robust_subject_mmap', '-Dmmap64=robust_subject_mmap64',
		'-Dmunmap=robust_subject_munmap', '-Duname=robust_subject_uname']
}

fn robust_original(destination string, arch string) ! {
	write(destination, output(['git', '-C', root(), 'show', original + ':build-support/steam/robust-list-' + arch + '.c'])!)!
}

pub fn robust_native(work string) ! {
	for i386 in [false, true] {
		name := if i386 { 'i386' } else { 'x86_64' }
		arch := if i386 { 'i386' } else { 'amd64' }
		directory := work + '/' + name + '-native'
		os.mkdir_all(directory)!
		source := directory + '/robustfixture'
		if os.exists(source) { retire(source) }
		hosttest.module_copy_tree(root() + '/tests/steam/robustfixture', source)!
		os.rm(source + '/concurrency.v')!
		mut text := read(source + '/core.v')!
		for header in ['assert.h', 'stdio.h', 'string.h'] { text = text.replace('#include <' + header + '>', '') }
		for symbol in ['assert', 'puts', 'strcmp'] {
			text = text.replace('fn C.' + symbol + '(', '@[c_extern]\nfn C.robust_bare_' + symbol + '(')
			text = text.replace('C.' + symbol + '(', 'C.robust_bare_' + symbol + '(')
		}
		write(source + '/core.v', text)!
		fixture := directory + '/fixture.c'
		generate(source, fixture, arch, if i386 { ['steam_i386', 'steam_robust_bare'] } else { ['steam_robust_bare'] }, '')!
		helpers := directory + '/helpers.c'
		generate(root() + '/tests/steam/robustbare', helpers, arch, []string{}, directory + '/helpers.h')!
		write(fixture, '#include "helpers.h"\n' + read(fixture)!)!
		for artifact in [fixture, helpers] { write(artifact, diagnostic_declarations()! + read(artifact)!.replace('#include <inttypes.h>\n', ''))! }
		production := directory + '/production.c'
		robust_generate(production, i386, false)!
		control := directory + '/original.c'
		robust_original(control, name)!
		flags := ['clang', '--target=' + name + '-linux-gnu', '-ffreestanding', '-fno-builtin',
			'-fno-stack-protector', '-O2', '-ffunction-sections', '-fdata-sections', '-Wall', '-Wextra', '-Werror',
			'-Wno-unused-function', '-Wno-unused-label', '-Wno-unused-parameter']
		mut common := []string{}
		for artifact in [fixture, helpers, root() + '/tests/steam/robust-bare-start.S'] {
			object := directory + '/' + os.file_name(artifact).all_before_last('.') + '.o'
			run([...flags, '-c', artifact, '-o', object])!
			common << object
		}
		for label in ['v', 'original'] {
			object := directory + '/' + label + '.o'
			run([...flags, ...robust_remaps(), '-c', if label == 'v' { production } else { control }, '-o', object])!
			abi := directory + '/' + label + '-abi.o'
			mut options := flags.clone()
			if label == 'original' { options << '-DSTEAM_ROBUST_ORIGINAL' }
			run([...options, '-c', root() + '/tests/steam/robust-fixture-abi.S', '-o', abi])!
			mut extra := []string{}
			if label == 'v' {
				forward := directory + '/forward-abi.o'
				run([...flags, '-c', root() + '/build-support/steam/robust-syscall.S', '-o', forward])!
				extra << forward
			}
			run([os.getenv_opt('VINIX_LD_LLD') or { '/opt/homebrew/bin/ld.lld' }, '-m', if i386 { 'elf_i386' } else { 'elf_x86_64' },
				'-static', '--gc-sections', '-e', '_start', '-o', directory + '/' + label, ...common, object, abi, ...extra])!
		}
		println(name + ' actual native ABI fixtures linked')
	}
}

fn robust_test(args []string) !int {
	parsed := hosttest.parse_arguments(args, [hosttest.Option{name: '--output-dir', value: true}, hosttest.Option{name: '--native'}], 0,
		'Usage: test-robust-list [--output-dir DIR] [--native]', 'Compare both V preload policies with immutable original C.') or { return error_with_code(err.msg(), 2) }
	work := hosttest.work_dir(parsed.options['--output-dir'], 'vinix-steam-robust-proof-')!
	defer { if '--output-dir' !in parsed.options { retire(work) } }
	flags := ['clang', '-O1', '-g', '-fno-builtin', '-fsanitize=address,undefined', '-fno-omit-frame-pointer',
		'-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-label', '-Wno-unused-parameter']
	for i386 in [false, true] {
		name := if i386 { 'i386' } else { 'x86_64' }
		fixture := work + '/' + name + '-fixture.c'
		generate(root() + '/tests/steam/robustfixture', fixture, 'amd64', if i386 { ['steam_i386'] } else { []string{} }, '')!
		production := work + '/' + name + '-v.c'
		robust_generate(production, i386, true)!
		control := work + '/' + name + '-original.c'
		robust_original(control, name)!
		mut streams := []string{}
		for label in ['v', 'original'] {
			subject := work + '/' + name + '-' + label + '.o'
			run([...flags, ...robust_remaps(), '-c', if label == 'v' { production } else { control }, '-o', subject])!
			executable := work + '/' + name + '-' + label
			mut options := flags.clone()
			if label == 'original' { options << '-DSTEAM_ROBUST_ORIGINAL' }
			options << [fixture, subject, root() + '/tests/steam/robust-fixture-abi.S']
			if label == 'v' { options << root() + '/build-support/steam/robust-syscall.S' }
			run([...options, '-o', executable])!
			result := captured([executable])!
			streams << [result.stdout, result.stderr]
		}
		if streams[0] != streams[2] || streams[1] != streams[3] { return error('Steam C/V output differs: ' + name) }
		println(name + ' sanitizer/native ABI differential PASS')
	}
	if '--native' in parsed.options { robust_native(work)! }
	return 0
}
