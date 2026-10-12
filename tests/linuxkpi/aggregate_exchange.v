// SPDX-License-Identifier: GPL-2.0-or-later
// V runtime/controller and exact original Linux aggregate exchange routes.
module main

import os
import json2
import hosttest

const scope = 'Run the unchanged V 1/2/4/8-byte exchange/CAS backend through original Linux xchg/cmpxchg, natural records/unions, pmd_t/pte_t and volatile storage. Observe bit patterns, single evaluation and pthread token/CAS ownership; reject unsupported compiler types. This supplies no MM service or new 128-bit guarantee.'
const production_names = ['exchangecore__exchange', 'exchangecore__compare_exchange',
	'vinix_arch_exchange_bits', 'vinix_arch_compare_exchange_bits']

fn require(valid bool, message string) ! {
	if !valid { return error(message) }
}

fn metadata_prefix() string {
	return '#include "contract.h"\n' +
		'typedef uint64_t u64; typedef int32_t i32; typedef int64_t i64; typedef size_t usize; typedef void *voidptr;\n' +
		'#define E_STRUCT 0\n#define VNORETURN __attribute__((noreturn))\n'
}

fn select_source(raw string, fixture bool) !string {
	mut bodies := []string{}
	for body in hosttest.c_bodies(raw) {
		line := body.all_before('\n')
		if hosttest.named_body(body, 'main') && !body.contains('aggregatefixture__run') { continue }
		if production_names.any(hosttest.named_body(body, it))
			|| (fixture && (line.contains('aggregatefixture__') || ['main', '_vno_main_init_caller'].any(hosttest.named_body(body, it)))) {
			bodies << body
		}
	}
	require(bodies.len >= (if fixture { 18 } else { 4 }), 'Missing actual generated aggregate bodies')!
	joined := bodies.join('\n')
	mut aliases := []string{}
	mut globals := []string{}
	mut constants := []string{}
	for line in raw.split_into_lines() {
		if line.starts_with('typedef ') && !line.contains('{') && (line.contains('Array_fixed_') || line.contains('(*_fn_ptr_')) {
			aliases << line
		}
		if line.ends_with(';') && !line.contains('(') && !line.starts_with('typedef ')
			&& !line.starts_with('extern ') && !line.starts_with('\t') && !line.starts_with(' ')
			&& ['aggregatefixture__', '_v3_no_main_initialized'].any(line.contains(it)) {
			globals << line
		}
		if line.starts_with('#define ') && (line.starts_with('#define _S(s) ') || line.contains('aggregatefixture__')) {
			constants << line
		}
	}
	decls := bodies.map(it.all_before('\n').all_before_last(' {') + ';')
	text := metadata_prefix() + constants.join('\n') + '\n' + aliases.join('\n') + '\n' +
		globals.join('\n') + '\n' + decls.join('\n') + '\n' + joined + '\n'
	require(hosttest.c_bodies(text) == bodies, 'Selection changed actual generated V bodies')!
	for body in bodies {
		for name in ['malloc', 'calloc', 'realloc', 'memdup', 'v_malloc', 'new_array', 'array_push',
			'array_clone'] {
			require(!hosttest.has_word(body, name), 'Allocation in selected backend/fixture body')!
		}
	}
	return text
}

fn generation(compiler_v string, stage string, output string) []string {
	return [compiler_v, '-shared', '-no-builtin', '-no-closures', '-os', 'vinix', '-arch', 'amd64',
		'-target-libc-headers', '-gc', 'none', '-manualfree', '-d', 'nofloat', '-d',
		'linuxkpi_host_test', '-o', output, stage]
}

fn stage_backend(stage string) ! {
	os.mkdir_all(stage + '/exchangecore')!
	os.cp(hosttest.root() + '/kernel/linuxkpi/exchangecore/core.v', stage + '/exchangecore/core.v')!
	os.write_file(stage + '/v.mod', "Module { name: 'aggregate_exchange_proof' }\n")!
	os.write_file(stage + '/entry.v', 'module main\nimport exchangecore as _\nfn main() {}\n')!
}

fn native_objects(work string, raw string, compiler string, env map[string]string) ![]json2.Any {
	bodies := production_names.map(hosttest.extract_body(raw, it)!)
	decls := bodies.map(it.all_before('\n').all_before_last(' {') + ';')
	text := '#include <stdint.h>\n#include <stddef.h>\n#include <stdbool.h>\n#include <string.h>\n' +
		'typedef uint8_t u8; typedef uint16_t u16; typedef uint32_t u32; typedef uint64_t u64; typedef int32_t i32; typedef size_t usize; typedef void *voidptr;\n' +
		decls.join('\n') + '\n' + bodies.join('\n\n') + '\n'
	source := work + '/native-production.c'
	os.write_file(source, text)!
	require(hosttest.c_bodies(text) == bodies, 'Native object selection changed actual bodies')!
	mut result := []json2.Any{}
	for standard in ['gnu99', 'gnu11'] {
		for optimization in ['O0', 'O2'] {
			object := work + '/native-' + standard + '-' + optimization + '.o'
			argv := [compiler, '--target=x86_64-unknown-none', '-std=' + standard, '-' + optimization,
				'-ffreestanding', '-fno-builtin', '-fwrapv', '-fno-strict-aliasing', '-Wall', '-Wextra',
				'-Werror', '-nostdinc', '-I', hosttest.root() + '/kernel/c', '-isystem',
				hosttest.root() + '/kernel/freestnd-c-hdrs', '-c', source, '-o', object]
			depfile := object + '.d'
			preprocessed := object + '.i'
			hosttest.command([...argv[..argv.len - 4], '-E', '-MD', '-MF', depfile, '-MT', object,
				source, '-o', preprocessed], object + '.preprocess.log', 120, env)!
			dependencies := hosttest.dependency_paths(os.read_file(depfile)!, object)!
			dependency_hashes := hosttest.hashes(dependencies)!
			hosttest.command(argv, object + '.compile.log', 120, env)!
			require(dependency_hashes == hosttest.hashes(dependencies)!, 'Native object compiler inputs changed')!
			imports := hosttest.command([hosttest.tool('llvm-nm'), '--undefined-only', object], object + '.imports.log', 30, env)!.stdout
			require(imports.split_into_lines().map(it.fields().last()).sorted() == ['memcpy']
				&& !hosttest.allocation_symbols(imports), 'Unexpected production imports: ' + imports)!
			result << json2.Any({
				'standard':            json2.Any(standard)
				'optimization':        optimization
				'compile_argv':        hosttest.strings(argv)
				'object_sha256':       hosttest.sha(object)!
				'preprocessed_sha256': hosttest.sha(preprocessed)!
				'dependency_sha256':   hosttest.string_map(dependency_hashes)
				'unresolved':          json2.Any('memcpy')
			})
		}
	}
	return result
}

fn controls(work string, flags []string, env map[string]string, compiler_v string) ![]json2.Any {
	stage := work + '/controls-stage'
	os.mkdir_all(stage + '/aggregatecontrols')!
	os.cp(hosttest.root() + '/tests/linuxkpi/aggregatefixture/controls.v', stage + '/aggregatecontrols/core.v')!
	os.write_file(stage + '/v.mod', "Module { name: 'aggregate_exchange_controls' }\n")!
	os.write_file(stage + '/entry.v', 'module main\nimport aggregatecontrols as _\nfn main() {}\n')!
	generated := work + '/controls-generated.c'
	argv := generation(compiler_v, stage, generated)
	hosttest.command(argv, work + '/controls-generation.log', 120, env)!
	generated_raw := os.read_file(generated)!
	bodies := ['aggregatecontrols__exchange', 'aggregatecontrols__compare', 'vag_probe_exchange',
		'vag_probe_compare'].map(hosttest.extract_body(generated_raw, it)!)
	decls := bodies.map(it.all_before('\n').all_before_last(' {') + ';')
	mut result := []json2.Any{}
	for control, ctype in {
		'const':       'vag_const_record8'
		'float':       'vag_float'
		'double':      'vag_double'
		'array':       'vag_array8'
		'width3':      'vag_record3'
		'packed':      'vag_packed8'
		'aggregate16': 'vag_record16'
		'scalar16':    'vag_integer16'
	} {
		text := metadata_prefix() + 'typedef ' + ctype + ' vag_control_type;\n' +
			decls.join('\n') + '\n' + bodies.join('\n\n') + '\n'
		path := work + '/control-' + control + '.c'
		os.write_file(path, text)!
		require(hosttest.c_bodies(text) == bodies, 'Control changed actual generated V call bodies')!
		for standard in ['gnu99', 'gnu11'] {
			name := control + '-' + standard
			object := work + '/control-' + name + '.o'
			depfile := object + '.d'
			preprocessed := object + '.i'
			hosttest.command([...flags, '-std=' + standard, '-E', '-dD', '-MD', '-MF', depfile,
				'-MT', object, path, '-o', preprocessed], object + '.preprocess.log', 120, env)!
			dependencies := hosttest.dependency_paths(os.read_file(depfile)!, object)!
			dependency_hashes := hosttest.hashes(dependencies)!
			compile := [...flags, '-std=' + standard, '-c', path, '-o', object]
			compiled := hosttest.capture(compile, work + '/control-' + name + '.log', 120, env)!
			require(dependency_hashes == hosttest.hashes(dependencies)!, 'Actual control compiler inputs changed')!
			diagnostic := compiled.stdout + compiled.stderr
			mut unresolved := ''
			if control == 'scalar16' {
				require(compiled.code == 0, 'Previous scalar16 dispatch was rejected: ' + diagnostic)!
				imports := hosttest.command(['nm', '-u', object], object + '.imports.log', 30, env)!.stdout
				unresolved = imports
				require(imports.contains('vinix_arch_exchange_128') && imports.contains('vinix_arch_compare_exchange_128')
					&& !imports.contains('vinix_arch_exchange_bits') && !hosttest.allocation_symbols(imports),
					'Scalar16 did not retain its separate prior dispatch')!
			} else {
				require(compiled.code != 0 && !os.exists(object), 'Unsupported control compiled: ' + name)!
				expected := if control == 'const' {
					'atomic storage must be writable'
				} else if control == 'width3' {
					'unsupported native atomic width'
				} else if control == 'array' {
					'__atomic_load'
				} else {
					'atomic storage must be integer, pointer or naturally aligned word aggregate'
				}
				require(diagnostic.contains(expected), 'Control failed outside its actual atomic boundary: ' + diagnostic)!
			}
			result << json2.Any({
				'name':                json2.Any(name)
				'compile_argv':        hosttest.strings(compile)
				'exit_code':           compiled.code
				'generated_sha256':    hosttest.sha(generated)!
				'selected_sha256':     hosttest.sha(path)!
				'diagnostic_sha256':   hosttest.text_sha(diagnostic)
				'unresolved':          unresolved
				'object_sha256':       if control == 'scalar16' {
					hosttest.sha(object)!
				} else {
					''
				}
				'preprocessed_sha256': hosttest.sha(preprocessed)!
				'dependency_sha256':   hosttest.string_map(dependency_hashes)
				'scope':               if control == 'scalar16' {
					'Prior separate wide helper imports only; no execution or hardware guarantee'
				} else {
					'Actual generated V calls rejected by candidate compiler boundary'
				}
			})
		}
	}
	return result
}

fn run(keep string, header string) ! {
	root := hosttest.root()
	linux := hosttest.env_default('LINUXKPI_SOURCE_DIR', root + '/third_party/linux-i915/linux-6.6.157')
	pin := hosttest.upstream_pin()!
	hosttest.verify_upstream(linux, pin)!
	work := hosttest.work_dir(keep, 'vinix-aggregate-exchange-v-')!
	defer { if keep == '' { hosttest.remove_work_dir(work) or { eprintln(err) } } }
	mut inputs := [@FILE, root + '/kernel/linuxkpi/exchangecore/core.v',
		root + '/kernel/linuxkpi/exchange128core/core.v',
		root + '/kernel/linuxkpi/abi/atomic-exchange.json', root + '/kernel/linuxkpi/upstream.json',
		root + '/tests/linuxkpi/host_types.h', root + '/kernel/c/string.h']
	for directory in ['tests/linuxkpi/aggregatefixture', 'tests/linuxkpi/hosttest',
		'kernel/linuxkpi/include'] {
		for extension in ['.v', '.h'] { inputs << os.walk_ext(root + '/' + directory, extension) }
	}
	if header != '' { inputs << os.real_path(header) }
	compiler := os.real_path(os.find_abs_path_of_executable(hosttest.env_default('CC', 'clang'))!)
	compiler_v := os.real_path(hosttest.command(['sh', '-c',
		'. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'find-v', root], '', 30, os.environ())!.stdout)
	inputs << [compiler, compiler_v, os.executable(), hosttest.tool('llvm-nm')]
	before := hosttest.hashes(inputs)!
	mut env := os.environ()
	env['VCACHE'] = work + '/vcache'
	env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	env['ASAN_OPTIONS'] = 'detect_stack_use_after_return=1:abort_on_error=1'
	env['UBSAN_OPTIONS'] = 'halt_on_error=1'
	stage := work + '/stage'
	stage_backend(stage)!
	os.mkdir_all(stage + '/aggregatefixture')!
	os.cp(root + '/tests/linuxkpi/aggregatefixture/core.v', stage + '/aggregatefixture/core.v')!
	os.write_file(stage + '/entry.v', 'module main\nimport aggregatefixture as _\nimport exchangecore as _\nfn main() {}\n')!
	generated := work + '/generated.c'
	argv := generation(compiler_v, stage, generated)
	hosttest.command(argv, work + '/generation.log', 120, env)!
	raw := os.read_file(generated)!
	source := work + '/selected.c'
	os.write_file(source, select_source(raw, true)!)!
	reference := work + '/reference'
	stage_backend(reference)!
	reference_c := work + '/reference.c'
	hosttest.command(generation(compiler_v, reference, reference_c), work + '/reference-generation.log', 120, env)!
	reference_raw := os.read_file(reference_c)!
	mut body_hashes := map[string]string{}
	for name in production_names {
		body := hosttest.extract_body(raw, name)!
		require(body == hosttest.extract_body(reference_raw, name)!, 'Fixture changed an actual isolated production body: ' + name)!
		body_hashes[name] = hosttest.text_sha(body)
	}
	hosttest.audit_headers(work + '/abi')!
	if header != '' { os.cp(header, work + '/abi/vinix/atomic_exchange.h')! }
	mut flags := [compiler, '-O1', '-g', '-ffreestanding', '-fno-builtin', '-fwrapv',
		'-fno-strict-aliasing', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function',
		'-Wno-unused-parameter', '-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-pthread']
	$if macos {
		flags << ['-arch', 'x86_64']
	}
	flags << ['-D__KERNEL__', '-DVINIX_LINUXKPI', '-DVINIX_LINUXKPI_HOST_TEST', '-include',
		root + '/tests/linuxkpi/host_types.h', '-include', 'linux/kconfig.h', '-include',
		linux + '/include/linux/compiler_types.h']
	for directory in [root + '/tests/linuxkpi/aggregatefixture', work + '/abi',
		root + '/kernel/linuxkpi/include', linux + '/include', linux + '/include/uapi',
		linux + '/arch/x86/include', linux + '/arch/x86/include/uapi'] {
		flags << ['-I', directory]
	}
	flags << ['-idirafter', root + '/kernel/c']
	mut profiles := []json2.Any{}
	for standard in ['gnu99', 'gnu11'] {
		object := work + '/' + standard + '.o'
		depfile := object + '.d'
		preprocessed := object + '.i'
		profile_flags := [...flags, '-std=' + standard]
		hosttest.command([...profile_flags, '-E', '-dD', '-MD', '-MF', depfile, '-MT', object,
			source, '-o', preprocessed], object + '.preprocess.log', 120, env)!
		dependencies := hosttest.dependency_paths(os.read_file(depfile)!, object)!
		dependency_hashes := hosttest.hashes(dependencies)!
		compile := [...profile_flags, '-c', source, '-o', object]
		hosttest.command(compile, object + '.compile.log', 120, env)!
		require(dependency_hashes == hosttest.hashes(dependencies)!, 'Actual profile compiler inputs changed')!
		imports := hosttest.command(['nm', '-u', object], object + '.imports.log', 30, env)!.stdout
		require(!hosttest.allocation_symbols(imports) && !imports.contains('vinix_arch_exchange_128')
			&& !imports.contains('vinix_arch_compare_exchange_128'), 'Small aggregate fixture gained allocator or wide imports')!
		executable := work + '/' + standard
		mut link := [compiler, '-fsanitize=address,undefined', '-pthread']
		$if macos {
			link << ['-arch', 'x86_64']
		}
		link << [object, '-o', executable]
		hosttest.command(link, object + '.link.log', 120, env)!
		result := hosttest.command([executable], object + '.run.log', 120, env)!
		require(result.stdout.starts_with('PASS: V aggregate exchange') && result.stderr == '', 'Diagnosed/incomplete aggregate fixture')!
		profiles << json2.Any({
			'standard':            json2.Any(standard)
			'compile_argv':        hosttest.strings(compile)
			'object_sha256':       hosttest.sha(object)!
			'executable_sha256':   hosttest.sha(executable)!
			'preprocessed_sha256': hosttest.sha(preprocessed)!
			'dependency_sha256':   hosttest.string_map(dependency_hashes)
			'output':              result.stdout
		})
		println(standard + ': ' + result.stdout.trim_space())
	}
	control_results := controls(work, flags, env, compiler_v)!
	native := native_objects(work, reference_raw, compiler, env)!
	require(before == hosttest.hashes(inputs)!, 'Actual production, fixture or compiler source changed')!
	hosttest.verify_upstream(linux, pin)!
	hosttest.write_json(work + '/result.json', {
		'scope':                   json2.Any(scope)
		'head':                    hosttest.command(['git', '-C', root, 'rev-parse', 'HEAD'], '', 30, env)!.stdout.trim_space()
		'source_sha256':           hosttest.string_map(before)
		'generation_argv':         hosttest.strings(argv)
		'generated_sha256':        hosttest.sha(generated)!
		'selected_sha256':         hosttest.sha(source)!
		'reference_sha256':        hosttest.sha(reference_c)!
		'production_body_sha256':  hosttest.string_map(body_hashes)
		'atomic_header_sha256':    hosttest.sha(work + '/abi/vinix/atomic_exchange.h')!
		'private_header_override': header != ''
		'profiles':                profiles
		'compiler_controls':       control_results
		'production_only_objects': native
		'original_pgtable_sha256': hosttest.sha(linux + '/arch/x86/include/asm/pgtable_64_types.h')!
		'original_atomic_sha256':  hosttest.sha(linux + '/include/linux/atomic/atomic-instrumented.h')!
	})!
}

fn main() {
	options := hosttest.parse_path_options(os.args[1..], ['--keep-dir', '--header'],
		'Usage: aggregate_exchange.v [--keep-dir NEW] [--header PRIVATE-CANDIDATE]', scope) or {
		eprintln(err)
		exit(2)
	}
	run(options['--keep-dir'], options['--header']) or {
		eprintln(err)
		exit(1)
	}
}
