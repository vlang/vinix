// SPDX-License-Identifier: GPL-2.0-only
module main

import os
import json2
import hosttest

const scope = 'Execute unchanged formatted allocation, original typed Linux facades, instruction-only variadic capture, native formatter, rodata classifier and checked allocator through independent page/log transports. Native image placement and retained kernel allocations require separate guest evidence.'
const ordinary = ['native_test_bit', 'const_string_kfree', 'const_string_kstrdup', 'kstrdup', 'kstrndup',
	'strnlen', 'strchr', 'kmemdup_nul', 'is_null', 'require', 'runtime_gfp_supported',
	'runtime_alloc_gfp_pages', 'runtime_kmalloc', 'runtime_kfree', 'runtime_ksize',
	'page_allocation_size', 'native_kmalloc', 'native_kfree', 'native_warn', 'add_taint', 'test_taint',
	'get_taint', 'vkr_rotate', 'vkr_sipround', 'vkr_nested_parse', 'vkr_pointer_hash']
const exports = ['vkc_kfree_const', 'vkc_kstrdup_const', 'kstrdup', 'kstrndup', 'kmemdup_nul',
	'vinix_linuxkpi_gfp_supported', 'vinix_linuxkpi_alloc_gfp_pages', 'vkr_kmalloc', 'vkr_kfree',
	'vkr_ksize', 'vkr_page_allocation_size', 'kmalloc', 'kfree', 'vkf_kvasprintf',
	'vkf_kvasprintf_const', 'vinix_linuxkpi_kasprintf_entry', 'vinix_linuxkpi_warn_entry', 'add_taint',
	'test_taint', 'get_taint', 'vkr_nested_parse', 'vkr_pointer_hash', 'vkr_format_entry',
	'vkr_format_parse']

fn generation(argv []string, _log string, _timeout int, env map[string]string) !hosttest.Result {
	output := argv[argv.index('-o') + 1]
	os.cp_all(argv.last(), output + '.source', false)!
	mut child := env.clone()
	for key, name in {
		'VCACHE':  'vcache'
		'V3CACHE': 'v3cache'
		'VTMP':    'vtmp'
	} {
		child[key] = os.dir(output) + '/' + name
	}
	mut recorded := map[string]string{}
	for key in ['V', 'VEXE', 'V_MACOS_V3_CALLER_VEXE', 'VCACHE', 'V3CACHE', 'VTMP', 'TMPDIR'] {
		recorded[key] = child[key] or { '<unset>' }
	}
	hosttest.write_json(output + '.generation-environment.json', hosttest.string_map(recorded))!
	result := hosttest.capture(argv, output + '.generation.log', 180, child)!
	if result.code != 0 { return error('Generation failed: ' + output + '.generation.log') }
	return result
}

fn generate(source string, path string, arch string) ! {
	hosttest.generate_module_with_capture(source, path, arch, ['linuxkpi_host_test', 'linuxkpi',
		'nofloat'], generation)!
}

fn name(body string) string {
	return body.all_before('\n').all_before_last('(').all_after_last(' ').trim_left('*')
}

fn select_source(raw string, group string, full []string) !string {
	mut selected := []string{}
	for body in hosttest.c_bodies(raw) {
		symbol := name(body)
		if symbol in [group + '__vinit', group + '__vinit_caller', group + '__vno_main_init_caller']
			|| (group == 'compatcore' && (ordinary.map(group + '__' + it).contains(symbol) || symbol in exports || symbol.starts_with(group + '__vkrf_') || symbol.starts_with(group + '__vkr_arg_') || symbol.starts_with(group + '__vkr_resource_') || symbol.starts_with(group + '__format_alloc_') || symbol.starts_with(group + '__abiargs__') || symbol in [
				'compatcore__vkr_format_parse',
				'compatcore__vkr_format_entry',
			] || symbol.starts_with('vkr_arg_') || symbol.starts_with('vkr_resource_')))
			|| (group == 'headercore' && (symbol.starts_with(group + '__format_alloc_') || symbol in [
				'headercore__const_string_free',
				'headercore__const_string_dup',
				'kfree_const',
				'kstrdup_const',
				'kvasprintf',
				'kvasprintf_const',
			]))
			|| (group == 'linuxkpi' && symbol in ['linuxkpi__const_string_is_rodata',
				'vinix_linuxkpi_is_kernel_rodata'])
			|| (group == 'kasprintffixture' && (symbol.starts_with(group + '__') || symbol in [
				'main',
				'kph_rodata_start',
				'kph_rodata_end',
				'kph_log_entry',
				'vinix_linuxkpi_page_size',
				'vinix_linuxkpi_may_sleep',
				'vinix_linuxkpi_alloc_pages',
				'vinix_linuxkpi_free_pages',
				'vinix_linuxkpi_bug',
			])) {
			if full.len != 0 && symbol != group + '__vinit' {
				matches := full.filter(hosttest.named_body(it, symbol))
				if matches.len != 1 { return error('Missing full production body ' + symbol) }
				selected << matches[0]
			} else {
				selected << body
			}
		}
	}
	if selected.len == 0 { return error('No bodies ' + group) }
	joined := selected.join('\n\n')
	mut metadata := []string{}
	mut globals := []string{}
	mut constants := []string{}
	for line in raw.split_into_lines() {
		if line.starts_with('typedef ') && line.contains('Array_fixed_') && joined.contains(line.all_before(';').all_after_last(' ')) {
			metadata << line
		}
		if line.starts_with('#define ') && (line.starts_with('#define E_STRUCT ') || line.contains(group + '__')) {
			constants << line
		}
		if line.ends_with(';') && !line.starts_with('typedef ') && !line.starts_with('extern ') && !line.starts_with(' ') && !line.starts_with('\t') && !line.all_before('=').contains('(') && line.contains(group + '__') {
			globals << line
		}
	}
	if group == 'compatcore' {
		for record in ['FormatSpec', 'FormatOutput', 'VaDescriptor', 'ResourceView', 'RuntimeAllocation'] {
			metadata << 'typedef struct compatcore__' + record + ' compatcore__' + record + ';'
			metadata << hosttest.record(raw, 'compatcore__' + record)!
		}
	}
	if group == 'kasprintffixture' {
		metadata << 'typedef struct kasprintffixture__VaDescriptor kasprintffixture__VaDescriptor;'
		metadata << hosttest.record(raw, 'kasprintffixture__VaDescriptor')!
	}
	header := match group {
		'compatcore' {
			'#include "linuxkpi_v_primitives.h"\n#include "linuxkpi_runtime_v_primitives.h"\n#include "linuxkpi_const_string_v_primitives.h"\n#include "linuxkpi_kasprintf_v_primitives.h"\n#include <string.h>\nint _printk(const char *,...);\n'
		}
		'headercore' {
			'#include "linuxkpi_const_string_v_contract.h"\n#include "linuxkpi_kasprintf_v_contract.h"\n'
		}
		'linuxkpi' {
			'#include "linuxkpi_v_primitives.h"\n#include "linuxkpi_const_string_v_primitives.h"\n#include "symbols.h"\n'
		}
		else { '#include "contract.h"\n' }
	}
	unsigned := if group in ['compatcore', 'linuxkpi'] {
		'typedef uint8_t u8;typedef uint16_t u16;typedef uint32_t u32;typedef uint64_t u64;\n'
	} else {
		''
	}
	native_word := if group == 'kasprintffixture' { 'typedef uint64_t u64;\n' } else { '' }
	text := '#include <stdint.h>\n#include <stddef.h>\n#include <stdbool.h>\ntypedef int8_t i8;typedef int16_t i16;typedef int32_t i32;typedef int64_t i64;typedef size_t usize;typedef intptr_t isize;typedef void *voidptr;\n#define VNORETURN __attribute__((noreturn))\n' + unsigned + header + native_word + metadata.join('\n') + '\n' + constants.join('\n') + '\n' + globals.join('\n') + '\n' + selected.map(it.all_before('\n').all_before_last(' {') + ';').join('\n') + '\n' + joined + '\n'
	if hosttest.c_bodies(text) != selected { return error('Changed bodies ' + group) }
	return text
}

fn compile_input(argv []string, source string, object string, env map[string]string) !json2.Any {
	dep := object + '.d'
	hosttest.command([...argv, '-E', '-dD', '-MD', '-MF', dep, '-MT', object, source, '-o',
		object + '.i'], object + '.preprocess.log', 180, env)!
	before := hosttest.hashes(hosttest.dependency_paths(os.read_file(dep)!, object)!)!
	hosttest.command([...argv, '-c', source, '-o', object], object + '.compile.log', 180, env)!
	if before != hosttest.hashes(before.keys())! { return error('Changed compile input ' + object) }
	return {
		'source':            json2.Any(source)
		'object':            object
		'argv':              hosttest.strings(argv)
		'dependency_sha256': hosttest.string_map(before)
	}
}

fn flags(work string, linux string, standard string, optimization string, target string, host bool) ![]string {
	root := hosttest.root()
	mut argv := hosttest.shell_split(hosttest.env_default('CC', 'clang'))!
	if host {
		$if macos {
			argv << ['-arch', if target == 'amd64' { 'x86_64' } else { 'arm64' }]
		}
		argv << ['-iquote', work + '/include', '-g', '-fsanitize=address,undefined',
			'-fno-omit-frame-pointer', '-D_FORTIFY_SOURCE=0', '-DVINIX_LINUXKPI_HOST_TEST', '-include',
			root + '/tests/linuxkpi/host_types.h']
	} else {
		argv << [
			'--target=' + if target == 'amd64' {
				'x86_64-unknown-none'
			} else {
				'aarch64-unknown-none'
			},
			'-nostdinc',
			'-fno-stack-protector',
			'-fstack-usage',
			'-isystem',
			root + '/kernel/freestnd-c-hdrs',
			'-I',
			root + '/kernel/c',
		]
	}
	argv << ['-std=' + standard, '-' + optimization, '-ffreestanding', '-fno-builtin', '-fwrapv',
		'-fno-strict-aliasing', '-ffunction-sections', '-fdata-sections', '-Wall', '-Wextra', '-Werror',
		'-Wno-unused-function', '-Wno-unused-parameter', '-Wno-sign-compare', '-DVINIX_LINUXKPI',
		'-D__KERNEL__', '-include', 'linux/kconfig.h', '-include',
		linux + '/include/linux/compiler_types.h']
	for path in [work + '/include', os.dir(@FILE) + '/kasprintffixture',
		root + '/kernel/linuxkpi/include', linux + '/include', linux + '/include/uapi',
		linux + '/arch/x86/include', linux + '/arch/x86/include/uapi'] {
		argv << ['-I', path]
	}
	argv << ['-iquote', root + '/kernel/c']
	return argv
}

fn executable_arches() ![]string {
	machine := os.uname().machine
	$if macos {
		if machine in ['arm64', 'aarch64'] { return ['amd64', 'arm64'] }
	}
	if machine in ['x86_64', 'amd64'] { return ['amd64'] }
	if machine in ['arm64', 'aarch64'] { return ['arm64'] }
	return error('Unsupported native host ' + machine)
}

fn genuine_cursor_source(selected string) !string {
	mut text := '#include <stdbool.h>\n#include <stdint.h>\n#include <string.h>\n#include "linuxkpi_kasprintf_v_contract.h"\ntypedef uint64_t u64;\n#define E_STRUCT 0\nextern u32 kasprintffixture__call_mode;\nextern bool kasprintffixture__preserved;\nvoid kasprintffixture__check(bool);\nvoid kasprintffixture__verify(void *);\nvks_const_char *kasprintffixture__text(char *);\nsize_t kasprintffixture__abiargs__native_size(void);\nu32 kasprintffixture__abiargs__integer(void *);\n'
	text += 'typedef int32_t i32;\ntypedef struct kasprintffixture__VaDescriptor kasprintffixture__VaDescriptor;\n' + hosttest.record(selected, 'kasprintffixture__VaDescriptor')! + '\n'
	for symbol in ['kasprintffixture__origin', 'kasprintffixture__nested_count'] {
		body := hosttest.extract_body(selected, symbol)!
		text += body + '\n\n'
	}
	return text
}

fn overflow_source() string {
	zeros := []string{len: 257, init: 'u32(0)'}
	fmt := '%8388607u'.repeat(256)
	mut source := '@[translated]\nmodule kasprintffixture\nfn overflow_cases(){unsafe{\n'
	for mode := u32(0); mode < 4; mode++ {
		source += 'call_mode=${mode}\nfail_pages=true\nexpect(nil,0,0,nil,true,true)\nbefore_${mode}:=page_calls\n'
		source += "origin(3264,text(c'" + fmt + 'x'.repeat(254) + "')," + zeros[..256].join(',') + ',u32(0x425a6719))\n'
		source += 'check(page_calls==before_${mode}+1&&fail_pages&&live_pages==0)\n'
		source += "origin(3264,text(c'" + fmt + 'x'.repeat(255) + "')," + zeros[..256].join(',') + ',u32(0x425a6719))\n'
		source += 'check(page_calls==before_${mode}+1&&fail_pages&&live_pages==0)\n'
		source += "origin(3264,text(c'" + fmt + "%8388607u')," + zeros.join(',') + ',u32(0x425a6719))\n'
		source += 'check(page_calls==before_${mode}+1&&fail_pages&&live_pages==0)\nfail_pages=false\nscenarios++\n'
		// A modest first pass becomes a checked overflow only in the second
		// pass. Its original cursor must stop before the trailing sentinel.
		overflow_fmt := fmt + '%8388607u%u'
		source += "mut changing_${mode}:=[4096]char{}\nC.memcpy(&changing_${mode}[0],c'%u',3)\n"
		source += "mutation_pointer=&changing_${mode}[0]\nmutation_data=c'" + overflow_fmt + "'\nmutation_size=${overflow_fmt.len + 1}\n"
		source += 'expected_warning=c\'\\x01\\x34linuxkpi: warning at kernel/linuxkpi/compatcore/kasprintf.v:0: different return values (1 and 4294967295) from vsnprintf("' + overflow_fmt + '", ...)\'\n'
		source += "warning_before_${mode}:=warnings\nexpect(c' ',2,2,nil,false,false)\n"
		source += 'origin(3264,text(&changing_${mode}[0]),' + zeros.join(',') + ',u32(0x425a6719))\n'
		source += 'check(warnings==warning_before_${mode}+1&&mutation_pointer==nil&&page_calls==before_${mode}+2&&live_pages==0)\nexpected_warning=nil\nscenarios++\n'
		// A nested count inherits precisely the outer remaining count budget.
		source += 'fail_pages=true\nexpect(nil,0,0,nil,true,true)\n'
		source += "nested_count(c'" + 'x'.repeat(254) + "%pV',text(c'" + fmt + "')," + zeros[..256].join(',') + ')\n'
		source += 'check(page_calls==before_${mode}+3&&fail_pages&&live_pages==0)\n'
		source += "nested_count(c'" + 'x'.repeat(255) + "%pV',text(c'" + fmt + "')," + zeros[..256].join(',') + ')\n'
		source += 'check(page_calls==before_${mode}+3&&fail_pages&&live_pages==0)\nfail_pages=false\nscenarios++\n'
		// Overflow inside a nested second pass conservatively retains only
		// the preceding outer prefix; the inner genuine cursor stays borrowed.
		source += "mut inner_changing_${mode}:=[4096]char{}\nC.memcpy(&inner_changing_${mode}[0],c'%u',3)\n"
		source += "mutation_pointer=&inner_changing_${mode}[0]\nmutation_data=c'" + fmt + "%8388607u'\nmutation_size=${fmt.len + 10}\n"
		source += 'expected_warning=c\'\\x01\\x34linuxkpi: warning at kernel/linuxkpi/compatcore/kasprintf.v:0: different return values (5 and 4294967295) from vsnprintf("pre:%pV", ...)\'\n'
		source += "expect(c'pre:',5,6,nil,false,false)\nnested_count(c'pre:%pV',text(&inner_changing_${mode}[0])," + zeros.join(',') + ')\n'
		source += 'check(warnings==warning_before_${mode}+2&&mutation_pointer==nil&&page_calls==before_${mode}+4&&live_pages==0)\nexpected_warning=nil\nscenarios++\n'
	}
	return source + '}}\n'
}

fn run(keep string) ! {
	root := hosttest.root()
	linux := hosttest.env_default('LINUXKPI_SOURCE_DIR', root + '/third_party/linux-i915/linux-6.6.157')
	hosttest.verify_upstream(linux, hosttest.upstream_pin()!)!
	work := hosttest.work_dir(keep, 'vinix-kasprintf-')!
	defer { if keep == '' { hosttest.remove_work_dir(work) or { eprintln(err) } } }
	previous := os.getenv('TMPDIR')
	os.mkdir_all(work + '/generation-scratch')!
	os.setenv('TMPDIR', work + '/generation-scratch', true)
	defer { os.setenv('TMPDIR', previous, true) }
	mut inputs := [@FILE, os.executable(), root + '/kernel/linuxkpi/const_string_d_linuxkpi.v',
		os.dir(@FILE) + '/kasprintffixture/README.md', root + '/build-support/find-v.sh']
	for schema in ['atomic-exchange', 'overflow', 'spinlock'] {
		inputs << root + '/kernel/linuxkpi/abi/' + schema + '.json'
	}
	for directory in [root + '/kernel/linuxkpi/compatcore', root + '/kernel/linuxkpi/headercore',
		root + '/kernel/c', root + '/kernel/abiargs', root + '/tests/linuxkpi/hosttest',
		os.dir(@FILE) + '/kasprintffixture'] {
		for extension in ['.v', '.h'] { inputs << os.walk_ext(directory, extension) }
	}
	for arch in ['x86_64', 'aarch64'] {
		for file in ['varargs.inc', 'linuxkpi_varargs.S'] {
			inputs << root + '/kernel/asm/' + arch + '/' + file
		}
	}
	mut env := os.environ()
	env['ASAN_OPTIONS'] = 'detect_stack_use_after_return=1:abort_on_error=1'
	env['UBSAN_OPTIONS'] = 'halt_on_error=1'
	mut tools_proof := []json2.Any{}
	mut commands := map[string][]string{
		'cc':      hosttest.shell_split(hosttest.env_default('CC', 'clang'))!
		'nm':      [hosttest.tool('llvm-nm')]
		'objdump': [hosttest.tool('llvm-objdump')]
	}
	for key in ['V', 'VEXE'] {
		if command := env[key] {
			if command != '' { commands[key] = [command] }
		}
	}
	for key, argv in commands {
		path := os.find_abs_path_of_executable(argv[0])!
		inputs << path
		version := hosttest.command([...argv, if key in ['V', 'VEXE'] {
			'version'
		} else {
			'--version'
		}], work + '/tool-' + key + '.log', 30, env)!
		tools_proof << json2.Any({
			'name':    json2.Any(key)
			'path':    path
			'sha256':  hosttest.sha(path)!
			'version': version.stdout + version.stderr
		})
	}
	before := hosttest.hashes(inputs)!
	for group in ['compatcore', 'headercore', 'linuxkpi', 'kasprintffixture'] {
		os.mkdir_all(work + '/stage/' + group)!
	}
	for file in ['const_string.v', 'runtime.v', 'primitives.v', 'string.v', 'format.v', 'taint.v',
		'kasprintf.v'] {
		os.cp(root + '/kernel/linuxkpi/compatcore/' + file, work + '/stage/compatcore/' + file)!
	}
	os.write_file(work + '/stage/compatcore/native_runtime.v', os.read_file(root + '/kernel/linuxkpi/compatcore/native_runtime.v')!.all_before('struct PciMatch'))!
	warning := os.read_file(root + '/kernel/linuxkpi/compatcore/native_printk.v')!
	os.write_file(work + '/stage/compatcore/native_warn.v', '@[translated]\nmodule compatcore\nfn C._printk(&char,...voidptr) i32\n' + warning[warning.index("@[export: 'vinix_linuxkpi_warn_entry']") or { return error('Warning definition absent') }..])!
	for group in ['compatcore', 'headercore', 'linuxkpi'] {
		os.write_file(work + '/stage/' + group + '/anchor.v', '@[translated]\nmodule ' + group + '\n__global kph_guard_anchor i32=-1\n')!
	}
	for file in ['const_string.v', 'kasprintf.v'] {
		os.cp(root + '/kernel/linuxkpi/headercore/' + file, work + '/stage/headercore/' + file)!
	}
	os.cp(root + '/kernel/linuxkpi/const_string_d_linuxkpi.v', work + '/stage/linuxkpi/core.v')!
	os.cp(os.dir(@FILE) + '/kasprintffixture/core.v', work + '/stage/kasprintffixture/core.v')!
	os.write_file(work + '/stage/kasprintffixture/overflow.v', overflow_source())!
	for schema, file in {
		'atomic-exchange': 'atomic_exchange'
		'overflow':        'integer_policy'
		'spinlock':        'spinlock_adapters'
	} {
		hosttest.generate_abi(root + '/kernel/linuxkpi/abi/' + schema + '.json', root + '/kernel/linuxkpi', work + '/include/vinix/' + file + '.h')!
	}
	os.write_file(work + '/include/symbols.h', 'void *kph_rodata_start(void);\nvoid *kph_rodata_end(void);\n#define rodata_start (kph_rodata_start())\n#define rodata_end (kph_rodata_end())\n')!
	mut proofs := []json2.Any{}
	mut objects := []json2.Any{}
	mut runs := []json2.Any{}
	runnable := executable_arches()!
	for arch in ['amd64', 'arm64'] {
		for group in ['compatcore', 'headercore', 'linuxkpi', 'kasprintffixture'] {
			actual := work + '/' + arch + '-' + group + '-actual.c'
			generate(work + '/stage/' + group, actual, arch)!
			mut full := []string{}
			if group in ['compatcore', 'headercore'] {
				reference := work + '/' + arch + '-' + group + '-full.c'
				generate(root + '/kernel/linuxkpi/' + group, reference, arch)!
				full = hosttest.c_bodies(os.read_file(reference)!)
			}
			selected := select_source(os.read_file(actual)!, group, full)!
			os.write_file(work + '/' + arch + '-' + group + '-selected.c', selected)!
			mut hashes := map[string]string{}
			for body in hosttest.c_bodies(selected) { hashes[name(body)] = hosttest.text_sha(body) }
			if group in ['compatcore', 'headercore'] {
				for body in hosttest.c_bodies(selected) {
					if name(body) == group + '__vinit' { continue }
					matches := full.filter(hosttest.named_body(it, name(body)))
					if matches.len != 1 || matches[0] != body {
						return error('Production parity failed ' + name(body))
					}
				}
			}
			for forbidden in ['memdup(', 'new_array', 'new_map', 'v_malloc(', 'string__substr(',
				'box_to_interface', '__eq_lhs'] {
				if selected.contains(forbidden) {
					return error('Hidden allocation ' + group + ' ' + forbidden)
				}
			}
			if group == 'kasprintffixture' && !selected.contains('vkf_native_va ap = (vkf_native_va){E_STRUCT};') {
				return error('Genuine cursor moved off stack')
			}
			proofs << json2.Any({
				'arch':        json2.Any(arch)
				'module':      group
				'body_sha256': hosttest.string_map(hashes)
			})
		}
		os.write_file(work + '/' + arch + '-genuine-cursor.c', genuine_cursor_source(os.read_file(work + '/' + arch + '-kasprintffixture-selected.c')!)!)!
		assembly := work + '/' + arch + '-capture.S'
		architecture := if arch == 'amd64' { 'x86_64' } else { 'aarch64' }
		original := os.read_file(root + '/kernel/asm/' + architecture + '/linuxkpi_varargs.S')!
		kas := 'VINIX_VARIADIC ABI_SYMBOL(kasprintf), ABI_SYMBOL(vinix_linuxkpi_kasprintf_entry), 2'
		warn := 'VINIX_VARIADIC ABI_SYMBOL(vinix_linuxkpi_warn_format), ABI_SYMBOL(vinix_linuxkpi_warn_entry), 3'
		if !original.split_into_lines().contains(kas) || !original.split_into_lines().contains(warn) {
			return error('Changed original instruction-only entry')
		}
		os.write_file(assembly, '#include "' + root + '/kernel/asm/' + architecture + '/varargs.inc"\n.text\n' + kas + '\n' + warn + '\nVINIX_VARIADIC ABI_SYMBOL(_printk), ABI_SYMBOL(kph_log_entry), 1\n')!
		for standard in ['gnu99', 'gnu11'] {
			for optimization in ['O0', 'O1', 'O2'] {
				tag := arch + '-' + standard + '-' + optimization
				mut linked := []string{}
				for host in [false, true]! {
					if host && arch !in runnable { continue }
					for group in ['compatcore', 'headercore', 'linuxkpi', 'kasprintffixture'] {
						if !host && group == 'kasprintffixture' { continue }
						mut argv := flags(work, linux, standard, optimization, arch, host)!
						if group == 'compatcore' { argv << '-DVINIX_V_RUNTIME' }
						object := work + '/' + tag + '-' + group + if host {
							'-host.o'
						} else {
							'-native.o'
						}
						objects << compile_input(argv, work + '/' + arch + '-' + group + '-selected.c', object, env)!
						if host {
							linked << object
							continue
						}
						imports := hosttest.command([hosttest.tool('llvm-nm'), '--undefined-only',
							object], object + '.imports.log', 30, env)!.stdout
						mut allowed := match group {
							'compatcore' {
								['vinix_linuxkpi_is_kernel_rodata', 'vinix_linuxkpi_page_size',
									'vinix_linuxkpi_may_sleep', 'vinix_linuxkpi_alloc_pages',
									'vinix_linuxkpi_free_pages', 'vinix_linuxkpi_bug',
									'vinix_linuxkpi_warn_format', '_printk', 'memcpy', 'memmove',
									'memset']
							}
							'headercore' {
								['vkc_kfree_const', 'vkc_kstrdup_const', 'vkf_kvasprintf',
									'vkf_kvasprintf_const']
							}
							else { ['rodata_start', 'rodata_end'] }
						}
						mut actual_imports := hosttest.undefined_symbols(imports)
						actual_imports.sort()
						allowed.sort()
						if actual_imports != allowed {
							return error('Changed production imports ' + group + ': ' + imports)
						}
						stack := os.read_file(object[..object.len - 2] + '.su')!
						if stack == '' || stack.split_into_lines().any(it != '' && !it.ends_with('\tstatic')) {
							return error('Unbounded stack ' + object)
						}
						hosttest.command([hosttest.tool('llvm-objdump'), '-dr', '--no-show-raw-insn',
							object], object + '.disassembly.log', 60, env)!
					}
				}
				abiobject := work + '/' + tag + '-genuine-cursor-native.o'
				objects << compile_input(flags(work, linux, standard, optimization, arch, false)!, work + '/' + arch + '-genuine-cursor.c', abiobject, env)!
				imports := hosttest.command([hosttest.tool('llvm-nm'), '--undefined-only', abiobject], abiobject + '.imports.log', 30, env)!.stdout
				mut expected_imports := ['kasprintffixture__abiargs__integer',
					'kasprintffixture__abiargs__native_size', 'kasprintffixture__call_mode',
					'kasprintffixture__check', 'kasprintffixture__preserved', 'kasprintffixture__text',
					'kasprintffixture__verify', 'kvasprintf', 'kvasprintf_const', 'memcmp', 'memcpy',
					'memmove', 'vkf_kvasprintf', 'vkf_kvasprintf_const']
				mut actual_imports := hosttest.undefined_symbols(imports)
				// Clang lowers the genuine SysV aggregate cursor initialization
				// to memset at O0; other profiles initialize it with instructions.
				if arch == 'amd64' && optimization == 'O0' { expected_imports << 'memset' }
				expected_imports.sort()
				actual_imports.sort()
				if actual_imports != expected_imports {
					return error('Changed genuine cursor imports ' + imports)
				}
				stack := os.read_file(abiobject[..abiobject.len - 2] + '.su')!
				if stack == '' || stack.split_into_lines().any(it != '' && !it.ends_with('\tstatic')) {
					return error('Unbounded genuine cursor ' + abiobject)
				}
				hosttest.command([hosttest.tool('llvm-objdump'), '-dr', '--no-show-raw-insn',
					abiobject], abiobject + '.disassembly.log', 60, env)!
				if arch !in runnable { continue }
				asmobject := work + '/' + tag + '-capture.o'
				mut asmargv := hosttest.shell_split(hosttest.env_default('CC', 'clang'))!
				$if macos {
					asmargv << ['-arch', if arch == 'amd64' { 'x86_64' } else { 'arm64' }]
				}
				hosttest.command([
					...asmargv,
					'-x',
					'assembler-with-cpp',
					'-c',
					assembly,
					'-o',
					asmobject,
				], asmobject + '.compile.log', 60, env)!
				linked << asmobject
				executable := work + '/' + tag
				strip := $if macos { '-Wl,-dead_strip' } $else { '-Wl,--gc-sections' }
				hosttest.command([
					...flags(work, linux, standard, optimization, arch, true)!,
					...linked,
					strip,
					'-o',
					executable,
				], executable + '.link.log', 180, env)!
				passed := hosttest.command([executable], executable + '.run.log', 120, env)!
				if passed.stderr != '' || !passed.stdout.contains('PASS: original formatted allocation;') || !passed.stdout.contains('live_pages=0') {
					return error('Missing clean verdict ' + executable)
				}
				runs << json2.Any({
					'arch':         json2.Any(arch)
					'standard':     standard
					'optimization': optimization
					'exit_code':    passed.code
					'output':       passed.stdout
				})
				println(tag + ': ' + passed.stdout.trim_space())
			}
		}
	}
	if before != hosttest.hashes(before.keys())! {
		return error('Sources changed during formatted allocation checks')
	}
	hosttest.write_json(work + '/result.json', {
		'scope':                 json2.Any(scope)
		'source_sha256':         hosttest.string_map(before)
		'tools':                 tools_proof
		'generated_body_proofs': proofs
		'objects':               objects
		'runs':                  runs
		'artifact_sha256':       hosttest.string_map(hosttest.hashes(os.walk_ext(work, ''))!)
	})!
}

fn main() {
	keep := hosttest.parse_keep_dir(os.args[1..], 'Usage: kasprintf.v [--keep-dir NEW]', scope) or {
		eprintln(err)
		exit(2)
	}
	run(keep) or {
		eprintln(err)
		exit(1)
	}
}
