// SPDX-License-Identifier: GPL-2.0-only
module nativepolicy

import hosttest
import os

const init_warnings = '#pragma GCC diagnostic ignored "-Wunused-function"\n#pragma GCC diagnostic ignored "-Wunused-label"\n#pragma GCC diagnostic ignored "-Wunused-parameter"\n'
const init_layout = '\n_Static_assert(sizeof(initcore__SignalAction) == 32 && offsetof(initcore__SignalAction, flags) == 8 && offsetof(initcore__SignalAction, restorer) == 16 && offsetof(initcore__SignalAction, mask) == 24, "raw ARM signal ABI");\n_Static_assert(sizeof(initcore__Delay) == 16 && offsetof(initcore__Delay, nanoseconds) == 8, "raw ARM time ABI");\n'

pub fn generate_init(tool string, destination string, host bool, echo bool, wifi bool) ! {
	if tool !in ['shell', 'full', 'desktop'] { return error('Unknown init policy') }
	work := private_work('vinix-init-v-')!
	defer { retire(work) }
	hosttest.module_copy_tree(root() + '/build-support/init-aarch64/initcore', work + '/initcore')!
	if host {
		for name in os.ls(work + '/initcore')! {
			if !name.ends_with('.v') { continue }
			path := work + '/initcore/' + name
			mut text := read(path)!
			for symbol in ['memcpy', 'memset', 'memmove', '_start'] {
				text = text.replace("@[export: '" + symbol + "']", "@[export: 'vinix_init_host_" + symbol + "']")
			}
			write(path, text)!
		}
	}
	write(work + '/v.mod', "Module { name: 'init_bridge' }\n")!
	write(work + '/entry.v', 'module main\nimport initcore as _\n')!
	mut defines := []string{}
	if tool != 'shell' { defines << 'init_' + tool }
	if host { defines << 'init_host' }
	if wifi { defines << 'init_wifi_bundle' }
	if echo { defines << 'init_busybox_echo_test' }
	generate_project(work, destination, '', false, defines)!
	text := without_unused_stdio_printers(read(destination)!)
	if pri_token(text) { return error('Unsupported native PRI format macro') }
	write(destination, init_warnings + text.replace('#include <inttypes.h>\n', '') + init_layout)!
}

// Newer V emits these stdio helpers even for -no-builtin projects that never
// print through V. Freestanding init provides its own console; retain any
// live or unfamiliar compiler block rather than deleting required code.
fn without_unused_stdio_printers(text string) string {
	block := 'static FILE* v3_eprint_begin(void) {\n\tfflush(stdout);\n\tfflush(stderr);\n\treturn stderr;\n}\nstatic void v3_eprint_end(void) {\n\tfflush(stderr);\n}\n#define v3_eprintf(...) do { fprintf(v3_eprint_begin(), __VA_ARGS__); v3_eprint_end(); } while (0)\nstatic void v3_eprint_lit(const char* s) {\n\tv3_eprintf("%s", s);\n}\nstatic void v3_eprintln_string(string s) {\n\tv3_eprintf("%.*s\\n", s.len, (char*)s.str);\n}\n'
	if text.count(block) != 1 { return text }
	remaining := text.replace(block, '')
	return if remaining.contains('v3_eprint') { text } else { remaining }
}

fn pri_token(text string) bool {
	mut token := []rune{}
	for ch in (text + ' ').runes() {
		if hosttest.module_word_rune(ch) { token << ch; continue }
		word := token.string()
		if word.starts_with('PRI') && word.len > 3 && word[3..].bytes().all(it.is_alnum()) { return true }
		token.clear()
	}
	return false
}

pub fn allocator_call(text string) bool {
	runes := text.runes()
	mut index := 0
	for index < runes.len {
		if !hosttest.module_word_rune(runes[index]) { index++; continue }
		begin := index
		for index < runes.len && hosttest.module_word_rune(runes[index]) { index++ }
		name := runes[begin..index].string()
		if name !in ['memdup', 'malloc', 'realloc', 'calloc'] && !name.starts_with('new_array') { continue }
		mut after := index
		for after < runes.len && unicode_space(runes[after]) { after++ }
		if after < runes.len && runes[after] == `(` { return true }
	}
	return false
}

fn unicode_space(ch rune) bool {
	return ch in [` `, `\t`, `\r`, `\n`, `\v`, `\f`, 0x1c, 0x1d, 0x1e, 0x1f, 0x85, 0xa0, 0x1680,
		0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200a,
		0x2028, 0x2029, 0x202f, 0x205f, 0x3000]
}

fn validate_init(work string, arguments hosttest.Arguments) ! {
	init := root() + '/build-support/init-aarch64'
	selected := arguments.options['--arch'] or { arch() }
	mut source := arguments.options['--reference-fixture'] or { '' }
	if source == '' && '--reference-fixture' !in arguments.options {
		source = work + '/fixture.c'
		generate_module(root() + '/tests/init-policy/hostfixture', source, selected)!
	} else { source = if source == '' { '.' } else { source } }
	common := concat(['clang'], clang_arch(selected), ['-O1', '-g', '-fsanitize=address,undefined',
		'-fno-omit-frame-pointer', '-fno-builtin', '-Wno-incompatible-pointer-types',
		'-Wno-incompatible-library-redeclaration'])
	mut strict := concat(['clang'], clang_arch(selected), ['-std=gnu11', '-Wall', '-Wextra', '-Werror',
		'-fno-builtin', '-O1', '-g', '-fsanitize=address,undefined', '-fno-omit-frame-pointer'])
	if '--reference-fixture' !in arguments.options {
		strict << ['-Wno-unused-function', '-Wno-unused-parameter', '-I' + root() + '/tests/init-policy/hostfixture']
	}
	fixture := work + '/fixture.o'
	run(concat(strict, ['-c', source, '-o', fixture]))!
	for echo in [false, true] {
		generated := work + '/init.c'
		generate_init('desktop', generated, true, echo, false)!
		defines := concat(['-DVINIX_INIT_HOST_TEST'], if echo { ['-DVINIX_BUSYBOX_ECHO_TEST'] } else { []string{} })
		executable := work + if echo { '/echo-test' } else { '/test' }
		run(concat(common, defines, ['-I' + init, generated, fixture, '-o', executable]))!
		run(concat([executable], if echo { ['echo'] } else { []string{} }))!
		if '--reference-dir' in arguments.options {
			mut originals := []string{}
			for row in [['desktop', 'desktop-init.c'], ['shell', 'init.c'], ['full', 'full-init.c']] {
				kind, name := row[0], row[1]
				out := work + '/reference-' + kind + '.c'
				base := arguments.options['--reference-dir']
				path := if base == '' { name } else { base.trim_right('/') + '/' + name }
				write(out, reference_init(read(path)!, kind)!)!
				originals << out
			}
			reference_exe := work + if echo { '/reference-echo-test' } else { '/reference-test' }
			run(concat(common, defines, originals, [fixture, '-o', reference_exe]))!
			run(concat([reference_exe], if echo { ['echo'] } else { []string{} }))!
		}
	}
	for tool in ['shell', 'full', 'desktop'] {
		source_c := work + '/' + tool + '.c'
		obj, elf, abi := work + '/' + tool + '.o', work + '/' + tool, work + '/' + tool + '-abi.o'
		generate_init(tool, source_c, false, false, false)!
		run(['clang', '--target=aarch64-linux-none', '-nostdlib', '-ffreestanding', '-O2',
			'-fno-stack-protector', '-fno-builtin', '-ffunction-sections', '-fdata-sections',
			'-I' + init, '-c', source_c, '-o', obj])!
		linker := hosttest.env_default('LD_AARCH64', if os.exists('/opt/homebrew/bin/ld.lld') {
			'/opt/homebrew/bin/ld.lld'
		} else { 'ld.lld' })
		run(['clang', '--target=aarch64-linux-none', '-c', init + '/syscall_abi.S', '-o', abi])!
		run([linker, '-m', 'aarch64elf', '--nostdlib', '-static', '--gc-sections', '-o', elf, obj, abi])!
		undefined := output(['nm', '-u', elf])!
		if undefined.trim_space() != '' { return error(undefined) }
		text := read(source_c)!
		if allocator_call(text) { return error('Implicit allocator in init policy') }
		for record in ['initcore__SignalAction action =', 'initcore__Delay delay =', 'char buffer[256]'] {
			if !text.contains(record) { return error(record) }
		}
	}
}

fn init_command(arguments []string) int {
	parsed := hosttest.parse_arguments(arguments, [
		hosttest.Option{'--reference-dir', true, []string{}},
		hosttest.Option{'--reference-fixture', true, []string{}},
		hosttest.Option{'--arch', true, ['arm64', 'amd64']},
		hosttest.Option{'--work-dir', true, []string{}},
	], 0, 'Usage: run [--arch arm64|amd64] [--work-dir FRESH] [--reference-dir DIR] [--reference-fixture C]',
		'Compare freestanding V init policies against independent syscall traces.') or {
		eprintln(err.msg()); return 2
	}
	keep := parsed.options['--work-dir'] or { '' }
	work := hosttest.work_dir(if '--work-dir' in parsed.options && keep == '' { '.' } else { keep },
		'vinix-init-fixture-') or { eprintln(err.msg()); return 1 }
	defer { if '--work-dir' !in parsed.options { retire(work) } }
	validate_init(work, parsed) or { eprintln(err.msg()); return 1 }
	println('INIT POLICY HOST/ARM LINK TEST: PASS')
	return 0
}
