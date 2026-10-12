// SPDX-License-Identifier: GPL-2.0-or-later
// Actual production V bridge/façade and original get_cycles with V observations.
module main

import os
import json2
import hosttest

const scope = 'Run unchanged native raw-TSC bridge and ULL facade with a V raw-read spy. Original tsc.h get_cycles runs against real feature IDs and configured masks, with CONFIG_X86_TSC absent/on and both include orders. This test does not execute hardware RDTSC or establish ordering/clock synchronization.'

fn require(valid bool, message string) ! {
	if !valid { return error(message) }
}

fn select_source(raw string) !string {
	mut bodies := []string{}
	for body in hosttest.c_bodies(raw) {
		line := body.all_before('\n')
		if hosttest.named_body(body, 'main') && !body.contains('rawtscfixture__run') { continue }
		if ['linuxkpi__', 'headercore__', 'cpu__', 'rawtscfixture__', 'rawtscspy__'].any(line.contains(it))
			|| ['rdtsc', 'vinix_linuxkpi_raw_tsc', 'vinix_linuxkpi_cpu_has', 'main',
				'_vno_main_init_caller'].any(hosttest.named_body(body, it)) {
			bodies << body
		}
	}
	require(bodies.len >= 15, 'Missing actual generated TSC/fixture bodies')!
	joined := bodies.join('\n')
	mut aliases := []string{}
	mut globals := []string{}
	mut constants := []string{}
	for line in raw.split_into_lines() {
		if line.starts_with('typedef ') && line.contains('(*_fn_ptr_') {
			name := line.all_after('(*').all_before(')')
			if joined.contains(name) { aliases << line }
		}
		if line.ends_with(';') && !line.contains('(') && !line.starts_with('typedef ')
			&& !line.starts_with('extern ') && !line.starts_with('\t') && !line.starts_with(' ')
			&& ['rawtscspy__', '_v3_no_main_initialized'].any(line.contains(it)) {
			globals << line
		}
		if line.starts_with('#define ') && (line.starts_with('#define _S(s) ') || line.contains('rawtscfixture__')) {
			constants << line
		}
	}
	decls := bodies.map(it.all_before('\n').all_before_last(' {') + ';')
	prefix := '#include "contract.h"\n' +
		'typedef uint64_t u64; typedef int32_t i32; typedef int64_t i64; typedef size_t usize; typedef void *voidptr;\n' +
		'#define VNORETURN __attribute__((noreturn))\n#define E_STRUCT 0\n' + constants.join('\n') + '\n' + aliases.join('\n') + '\n' +
		globals.join('\n') + '\n' + decls.join('\n') + '\n'
	selected := prefix + bodies.join('\n\n') + '\n'
	require(hosttest.c_bodies(selected) == bodies, 'Metadata selection changed a generated V body')!
	return selected
}

fn native_objects(work string, raw string, env map[string]string, compiler string) !json2.Any {
	names := ['cpu__rdtsc', 'linuxkpi__raw_tsc', 'vinix_linuxkpi_raw_tsc', 'headercore__rdtsc',
		'rdtsc']
	mut bodies := []string{}
	mut hashes := map[string]string{}
	for name in names {
		body := hosttest.extract_body(raw, name)!
		for allocator in ['malloc', 'calloc', 'realloc', 'memdup', 'v_malloc', 'new_array', 'array_push',
			'array_clone'] {
			require(!hosttest.has_word(body, allocator), 'Allocator in actual TSC body: ' + name)!
		}
		bodies << body
		hashes[name] = hosttest.text_sha(body)
	}
	decls := bodies.map(it.all_before('\n').all_before_last(' {') + ';')
	prefix := '#include <stdint.h>\n#include <stddef.h>\n#include <string.h>\n#include "linuxkpi_tsc_v_contract.h"\n' +
		'typedef uint32_t u32; typedef uint64_t u64;\n#define E_STRUCT 0\n' + decls.join('\n') + '\n'
	source := work + '/native-production.c'
	os.write_file(source, prefix + bodies.join('\n\n') + '\n')!
	require(hosttest.c_bodies(os.read_file(source)!) == bodies, 'Native selection changed production bodies')!
	mut objects := []json2.Any{}
	for standard in ['gnu99', 'gnu11'] {
		for optimization in ['O0', 'O2'] {
			object := work + '/native-' + standard + '-' + optimization + '.o'
			argv := [compiler, '--target=x86_64-unknown-none', '-std=' + standard, '-' + optimization,
				'-ffreestanding', '-fno-builtin', '-fwrapv', '-Wall', '-Wextra', '-Werror', '-nostdinc',
				'-I', hosttest.root() + '/kernel/c', '-isystem',
				hosttest.root() + '/kernel/freestnd-c-hdrs', '-c', source, '-o', object]
			hosttest.command(argv, object + '.compile.log', 120, env)!
			undefined := hosttest.command([hosttest.tool('llvm-nm'), '--undefined-only', object], object + '.imports.log', 30, env)!.stdout
			imports := undefined.split_into_lines().map(it.fields().last()).sorted()
			require(imports == ['memcpy'] && !hosttest.allocation_symbols(undefined), 'Unexpected production imports: ' + undefined)!
			objects << json2.Any({
				'standard':      json2.Any(standard)
				'optimization':  optimization
				'compiler_argv': hosttest.strings(argv)
				'object_sha256': hosttest.sha(object)!
				'unresolved':    hosttest.strings(imports)
			})
		}
	}
	return {
		'body_sha256': json2.Any(hosttest.string_map(hashes))
		'objects':     json2.Any(objects)
		'scope':       json2.Any('Actual native CPU instruction, bridge and facade bodies retain only memcpy import. These instruction objects are compiled without executing them; native caller-state/lifetime measurements are separate author/root evidence.')
	}
}

fn run(keep string, reference_receipt string) ! {
	root := hosttest.root()
	linux := hosttest.env_default('LINUXKPI_SOURCE_DIR', root + '/third_party/linux-i915/linux-6.6.157')
	pin := hosttest.upstream_pin()!
	hosttest.verify_upstream(linux, pin)!
	work := hosttest.work_dir(keep, 'vinix-raw-tsc-v-')!
	defer { if keep == '' { hosttest.remove_work_dir(work) or { eprintln(err) } } }
	production := ['kernel/linuxkpi/raw_tsc_amd64_d_linuxkpi.v', 'kernel/linuxkpi/headercore/tsc.v',
		'kernel/c/linuxkpi_tsc_v_contract.h', 'kernel/linuxkpi/include/asm/msr.h',
		'kernel/linuxkpi/include/asm/processor.h', 'kernel/linuxkpi/include/vinix/runtime.h',
		'kernel/linuxkpi/include/asm/cpufeature.h', 'kernel/linuxkpi/include/generated/autoconf.h',
		'kernel/linuxkpi/headercore/primitive.v', 'kernel/x86/cpu/cpu.v']
	mut inputs := [@FILE, root + '/kernel/linuxkpi/upstream.json']
	inputs << production.map(root + '/' + it)
	for directory in ['tests/linuxkpi/rawtscfixture', 'tests/linuxkpi/hosttest'] {
		for extension in ['.v', '.h'] { inputs << os.walk_ext(root + '/' + directory, extension) }
	}
	compiler := os.real_path(os.find_abs_path_of_executable(hosttest.env_default('CC', 'clang'))!)
	selected_v := hosttest.command(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"',
		'find-v', root], '', 30, os.environ())!.stdout
	compiler_v := os.real_path(selected_v)
	inputs << [compiler, compiler_v, os.executable(), hosttest.tool('llvm-nm')]
	if reference_receipt != '' { inputs << os.real_path(reference_receipt) }
	initial := hosttest.hashes(inputs)!
	require(os.read_file(root + '/kernel/linuxkpi/headercore/primitive.v')!.contains('fn C.memcpy(voidptr, voidptr, usize) voidptr'), 'Actual memcpy declaration changed')!
	stage := work + '/stage'
	for directory in ['linuxkpi', 'headercore', 'x86/cpu', 'rawtscfixture', 'rawtscspy'] {
		os.mkdir_all(stage + '/' + directory)!
	}
	os.cp(root + '/kernel/linuxkpi/raw_tsc_amd64_d_linuxkpi.v', stage + '/linuxkpi/raw_tsc_amd64_d_linuxkpi.v')!
	os.cp(root + '/kernel/linuxkpi/headercore/tsc.v', stage + '/headercore/tsc.v')!
	os.cp(root + '/tests/linuxkpi/rawtscfixture/staging/headercore.v', stage + '/headercore/declarations.v')!
	os.cp(root + '/tests/linuxkpi/rawtscfixture/staging/cpu.v', stage + '/x86/cpu/core.v')!
	os.cp(root + '/tests/linuxkpi/rawtscfixture/spy/core.v', stage + '/rawtscspy/core.v')!
	os.cp(root + '/tests/linuxkpi/rawtscfixture/core.v', stage + '/rawtscfixture/core.v')!
	os.write_file(stage + '/v.mod', "Module { name: 'raw_tsc_native_fixture' }\n")!
	os.write_file(stage + '/entry.v', 'module main\nimport rawtscfixture as _\nimport headercore as _\nimport linuxkpi as _\nfn main() {}\n')!
	mut env := os.environ()
	env['VCACHE'] = work + '/vcache'
	env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	env['ASAN_OPTIONS'] = 'detect_stack_use_after_return=1:abort_on_error=1'
	env['UBSAN_OPTIONS'] = 'halt_on_error=1'
	raw_path := work + '/generated.c'
	generation := [compiler_v, '-shared', '-no-builtin', '-no-closures', '-os', 'vinix', '-arch',
		'amd64', '-target-libc-headers', '-gc', 'none', '-manualfree', '-d', 'nofloat', '-d', 'linuxkpi',
		'-d', 'linuxkpi_host_test', '-o', raw_path, stage]
	hosttest.command(generation, work + '/generation.log', 120, env)!
	raw := os.read_file(raw_path)!
	source := work + '/selected.c'
	os.write_file(source, select_source(raw)!)!
	// Generate the genuine instruction module without any fixture globals,
	// detecting compiler name-resolution changes before host execution.
	reference := work + '/native-reference'
	for directory in ['linuxkpi', 'headercore', 'x86/cpu'] {
		os.mkdir_all(reference + '/' + directory)!
	}
	os.cp(root + '/kernel/linuxkpi/raw_tsc_amd64_d_linuxkpi.v', reference + '/linuxkpi/raw_tsc_amd64_d_linuxkpi.v')!
	os.cp(root + '/kernel/linuxkpi/headercore/tsc.v', reference + '/headercore/tsc.v')!
	os.cp(root + '/tests/linuxkpi/rawtscfixture/staging/headercore.v', reference + '/headercore/declarations.v')!
	actual_cpu := hosttest.v_function(os.read_file(root + '/kernel/x86/cpu/cpu.v')!, 'rdtsc')!
	os.write_file(reference + '/x86/cpu/core.v', 'module cpu\n' + actual_cpu)!
	os.write_file(reference + '/v.mod', "Module { name: 'raw_tsc_instruction_reference' }\n")!
	os.write_file(reference + '/entry.v', 'module main\nimport headercore as _\nimport linuxkpi as _\nfn main() {}\n')!
	reference_path := work + '/native-reference.c'
	mut reference_generation := generation.clone()
	reference_generation[reference_generation.len - 2] = reference_path
	reference_generation[reference_generation.len - 1] = reference
	hosttest.command(reference_generation, work + '/native-reference-generation.log', 120, env)!
	reference_raw := os.read_file(reference_path)!
	for name in ['linuxkpi__raw_tsc', 'vinix_linuxkpi_raw_tsc', 'headercore__rdtsc', 'rdtsc'] {
		require(hosttest.extract_body(raw, name)! == hosttest.extract_body(reference_raw, name)!,
			'Host generation changed actual isolated production body: ' + name)!
	}
	mut author_reference := map[string]json2.Any{}
	if reference_receipt != '' {
		path := os.real_path(reference_receipt)
		record := json2.decode[json2.Any](os.read_file(path)!)!.as_map()
		require(record['compiler_sha256']!.str() == hosttest.sha(compiler_v)!, 'Reference used a different native V compiler')!
		expected := record['actual_generated_bodies']!.as_map()
		for name in ['cpu__rdtsc', 'linuxkpi__raw_tsc', 'vinix_linuxkpi_raw_tsc', 'headercore__rdtsc',
			'rdtsc'] {
			require(hosttest.text_sha(hosttest.extract_body(reference_raw, name)!) == expected[name]!.str(),
				'Actual isolated body differs from independent author receipt: ' + name)!
			if name != 'cpu__rdtsc' {
				require(hosttest.text_sha(hosttest.extract_body(raw, name)!) == expected[name]!.str(),
					'Actual host body differs from independent author receipt: ' + name)!
			}
		}
		for item in record['inputs']!.as_array() {
			input := item.as_map()
			require(hosttest.sha(root + '/' + input['path']!.str())! == input['sha256']!.str(),
				'Author reference source changed: ' + input['path']!.str())!
		}
		author_reference = {
			'path':              json2.Any(path)
			'sha256':            hosttest.sha(path)!
			'exact_body_sha256': record['actual_generated_bodies']!
		}
	}
	hosttest.audit_headers(work + '/abi')!
	mut common := [compiler, '-O1', '-g', '-ffreestanding', '-fno-builtin', '-fwrapv',
		'-fno-strict-aliasing', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function',
		'-Wno-unused-parameter', '-fsanitize=address,undefined', '-fno-omit-frame-pointer']
	$if macos {
		common << ['-arch', 'x86_64']
	}
	mut includes := ['-D__KERNEL__', '-DVINIX_LINUXKPI', '-DVINIX_LINUXKPI_HOST_TEST', '-include',
		root + '/tests/linuxkpi/host_types.h', '-include', 'linux/kconfig.h', '-include',
		linux + '/include/linux/compiler_types.h']
	for path in [root + '/tests/linuxkpi/rawtscfixture', work + '/abi',
		root + '/kernel/linuxkpi/include', linux + '/include', linux + '/include/uapi',
		linux + '/arch/x86/include', linux + '/arch/x86/include/uapi'] {
		includes << ['-I', path]
	}
	includes << ['-idirafter', root + '/kernel/c']
	mut profiles := []json2.Any{}
	for standard in ['gnu99', 'gnu11'] {
		for configured in [false, true]! {
			// Four executions cover both standards, configurations and include orders.
			msr_first := (standard == 'gnu99') == configured
			name := standard + (if configured { '-configured' } else { '-guarded' })
			mut flags := [...common, '-std=' + standard, ...includes]
			if configured { flags << '-DCONFIG_X86_TSC=1' }
			if msr_first { flags << '-DVRT_MSR_FIRST' }
			object := work + '/' + name + '.o'
			depfile := work + '/' + name + '.d'
			preprocessed := work + '/' + name + '.i'
			hosttest.command([...flags, '-E', '-dD', '-MD', '-MF', depfile, '-MT', object, source,
				'-o', preprocessed], work + '/' + name + '.preprocess.log', 120, env)!
			dependencies := hosttest.dependency_paths(os.read_file(depfile)!, object)!
			before := hosttest.hashes(dependencies)!
			compile := [...flags, '-c', source, '-o', object]
			hosttest.command(compile, work + '/' + name + '.compile.log', 120, env)!
			require(before == hosttest.hashes(dependencies)!, 'Compiler inputs changed during profile')!
			undefined := hosttest.command(['nm', '-u', object], work + '/' + name + '.imports.log', 30, env)!.stdout
			require(!hosttest.allocation_symbols(undefined), 'Generated fixture imports an allocator: ' + undefined)!
			executable := work + '/' + name
			hosttest.command([...common, object, '-o', executable], work + '/' + name + '.link.log', 120, env)!
			result := hosttest.command([executable], work + '/' + name + '.run.log', 120, env)!
			require(result.stdout.starts_with('PASS: V raw TSC') && result.stderr == '', 'Incomplete or diagnosed native V fixture')!
			profiles << json2.Any({
				'standard':            json2.Any(standard)
				'configured':          configured
				'msr_first':           msr_first
				'compile_argv':        hosttest.strings(compile)
				'object_sha256':       hosttest.sha(object)!
				'executable_sha256':   hosttest.sha(executable)!
				'preprocessed_sha256': hosttest.sha(preprocessed)!
				'dependency_sha256':   hosttest.string_map(before)
				'output':              result.stdout
			})
			println(name + ': ' + result.stdout.trim_space())
		}
	}
	native := native_objects(work, reference_raw, env, compiler)!
	require(initial == hosttest.hashes(inputs)!, 'Actual production, fixture or compiler inputs changed')!
	hosttest.verify_upstream(linux, pin)!
	hosttest.write_json(work + '/result.json', {
		'scope':                            json2.Any(scope)
		'source_sha256':                    hosttest.string_map(initial)
		'generation_argv':                  hosttest.strings(generation)
		'generated_sha256':                 hosttest.sha(raw_path)!
		'selected_sha256':                  hosttest.sha(source)!
		'native_reference_sha256':          hosttest.sha(reference_path)!
		'native_reference_generation_argv': hosttest.strings(reference_generation)
		'author_reference':                 author_reference
		'profiles':                         profiles
		'production_only_objects':          native
		'cases_per_profile':                json2.Any(1160)
		'original_header':                  json2.Any({
			'tsc_sha256':     json2.Any(hosttest.sha(linux + '/arch/x86/include/asm/tsc.h')!)
			'feature_sha256': hosttest.sha(linux + '/arch/x86/include/asm/cpufeatures.h')!
		})
	})!
}

fn main() {
	options := hosttest.parse_path_options(os.args[1..], ['--keep-dir', '--reference-receipt'],
		'Usage: raw_tsc.v [--keep-dir NEW] [--reference-receipt AUTHOR-JSON]', scope) or {
		eprintln(err)
		exit(2)
	}
	run(options['--keep-dir'], options['--reference-receipt']) or {
		eprintln(err)
		exit(1)
	}
}
