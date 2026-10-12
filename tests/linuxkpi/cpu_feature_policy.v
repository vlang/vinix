// SPDX-License-Identifier: GPL-2.0-or-later
// Exact production V policies and independent V fixture/transport execution.
module main

import os
import json2
import hosttest

const scope = 'Run genuine immutable MOVDIR/SHSTK/active-LA57 policies, the exact cpu_has frontend and the unchanged opt-in native CPU sampler block. V transports supply CPU records, paging geometry, CPUID observations and CR4. Genuine configured feature macros run unchanged. This host check does not boot CPUs, enter IRQ scopes, activate CET or execute MOVDIR.'

fn sampler_block(source string) !string {
	initialise := hosttest.v_function(source, 'initialise')!
	start := initialise.index('$if linuxkpi ? {') or { return error('Missing original native CPU sampler block') }
	mut end := start + '$if linuxkpi ? {'.len
	mut depth := 1
	for end < initialise.len && depth != 0 {
		if initialise[end] == `{` { depth++ }
		if initialise[end] == `}` { depth-- }
		end++
	}
	if depth != 0 { return error('Unterminated original native CPU sampler block') }
	return initialise[start..end]
}

fn macro(text string, name string) !string {
	lines := text.split_into_lines()
	for index, line in lines {
		if !line.starts_with('#define ' + name + '(') { continue }
		mut selected := [line]
		mut position := index
		for selected.last().ends_with('\\') {
			position++
			if position >= lines.len { return error('Unterminated macro ' + name) }
			selected << lines[position]
		}
		return selected.join('\n')
	}
	return error('Missing exact macro ' + name)
}

fn selected_source(raw string) !string {
	mut bodies := []string{}
	for body in hosttest.c_bodies(raw) {
		line := body.all_before('\n')
		if hosttest.named_body(body, 'array_get') && !body.contains('policytransport__borrowed_index') { continue }
		if hosttest.named_body(body, 'v_panic') && !body.contains('policytransport__unexpected_v_panic') { continue }
		if hosttest.named_body(body, 'main') && !body.contains('cpupolicyfixture__run') { continue }
		if ['linuxkpi__', 'samplefixture__', 'policytransport__', 'cpupolicyfixture__', 'katomic__', 'lib__', 'cpu__', 'memory__'].any(line.contains(it))
			|| ['vinix_linuxkpi_cpu_has', 'policy_configure', 'policy_initialize', 'policy_state', 'policy_seed_ready', 'policy_sample', 'array_get', 'v_panic', 'main', '_vno_main_init_caller'].any(hosttest.named_body(body, it)) {
			bodies << body
		}
	}
	if bodies.len < 20 { return error('Missing actual generated policy/fixture bodies') }
	mut metadata := []string{}
	mut late_metadata := []string{}
	body_text := bodies.join('\n')
	for line in raw.split_into_lines() {
		if !line.starts_with('typedef ') { continue }
		if line.contains('Array_fixed_') {
			name := line.fields().last().all_before('[').all_before(';')
			if body_text.contains(name) && line !in late_metadata { late_metadata << line }
		} else if line.contains('(*_fn_ptr_') {
			name := line.all_after('(*').all_before(')')
			if body_text.contains(name) && line !in late_metadata { late_metadata << line }
		} else if (line.contains('policytransport__Local') || line.contains('struct array ')
			|| line == 'typedef array Array;' || line.contains('struct string ')
			|| line.contains('multi_return_bool_u32_u32_u32_u32')) && line !in metadata {
			metadata << line
		}
	}
	mut records := []string{}
	for name in ['string', 'array', 'policytransport__Local', 'multi_return_bool_u32_u32_u32_u32'] {
		records << hosttest.record(raw, name)!
	}
	mut globals := []string{}
	for line in raw.split_into_lines() {
		if !line.ends_with(';') || line.contains('(') || line.starts_with('typedef ') || line.starts_with('extern ') { continue }
		if ['linuxkpi__', 'policytransport__', '_v3_no_main_initialized'].any(line.contains(it))
			&& !line.starts_with('\t') && !line.starts_with(' ') { globals << line }
	}
	mut constants := []string{}
	for line in raw.split_into_lines() {
		if line.starts_with('#define ') && (line.contains('linuxkpi__') || line.contains('cpupolicyfixture__')
			|| line.starts_with('#define E_STRUCT ') || line.starts_with('#define _S(s) ')) { constants << line }
	}
	decls := bodies.map(it.all_before('\n').all_before_last(' {') + ';')
	prefix := '#include "cpupolicyfixture/contract.h"\n' +
		'typedef int32_t i32; typedef int64_t i64; typedef uint64_t u64; typedef void *voidptr; typedef size_t usize;\n' +
		'#define VNORETURN __attribute__((noreturn))\n' + metadata.join('\n') + '\n' + records.join('\n') + '\n' + late_metadata.join('\n') + '\n' + globals.join('\n') + '\n' +
		constants.join('\n') + '\n' + decls.join('\n') + '\n'
	text := prefix + bodies.join('\n\n') + '\n'
	if hosttest.c_bodies(text) != bodies { return error('Metadata selection changed a generated V body') }
	return text
}

fn native_objects(work string, raw string, selected string, environment map[string]string) !json2.Any {
	names := ['linuxkpi__directstore_has', 'linuxkpi__initialise_cpu_features',
		'linuxkpi__cpu_infrastructure_has', 'linuxkpi__initialise_cpu_infrastructure_features',
		'linuxkpi__cpu_has', 'vinix_linuxkpi_cpu_has', 'samplefixture__sample']
	mut bodies := []string{}
	mut hashes := map[string]string{}
	for name in names {
		body := hosttest.extract_body(raw, name)!
		for allocator in ['malloc', 'calloc', 'realloc', 'memdup', 'v_malloc', 'new_array', 'array_clone', 'array_push'] {
			if hosttest.has_word(body, allocator) { return error('Allocation in genuine production function: ' + name) }
		}
		bodies << body
		hashes[name] = hosttest.text_sha(body)
	}
	mut records := []string{}
	for name in ['string', 'array', 'policytransport__Local', 'multi_return_bool_u32_u32_u32_u32'] { records << hosttest.record(raw, name)! }
	mut metadata := []string{}
	for line in raw.split_into_lines() {
		if line.starts_with('typedef ') && line.ends_with(' local__Local;') { metadata << line }
		if line.starts_with('#define ') && (line.contains('linuxkpi__') || line.starts_with('#define _S(s) ')) { metadata << line }
		if line.ends_with(';') && line.contains('linuxkpi__boot_') && !line.contains('(') && !line.starts_with('\t') { metadata << line }
		if line.starts_with('Array linuxkpi__cpu_locals ') && line.ends_with(';') { metadata << line }
	}
	mut declarations := bodies.map(it.all_before('\n').all_before_last(' {') + ';')
	for symbol in ['array_get', 'v_panic', 'cpu__cpuid', 'cpu__read_cr4', 'katomic__load_T_u32', 'katomic__load_T_u64', 'katomic__store_T_u32', 'lib__kpanic', 'memory__user_address_limit'] {
		body := hosttest.extract_body(selected, symbol)!
		declarations << body.all_before('\n').all_before_last(' {') + ';'
	}
	prefix := '#include <stdbool.h>\n#include <stdint.h>\n#include <stddef.h>\n' +
		'typedef uint8_t u8; typedef uint8_t byte; typedef uint32_t u32; typedef uint64_t u64; typedef int32_t i32; typedef int64_t i64; typedef size_t usize; typedef void *voidptr;\n' +
		'typedef struct string string; typedef struct array array; typedef array Array; typedef array vpp_array; typedef string vpp_string;\n' +
		'typedef struct policytransport__Local policytransport__Local; typedef policytransport__Local linuxkpi__Local;\n' +
		'typedef struct multi_return_bool_u32_u32_u32_u32 multi_return_bool_u32_u32_u32_u32;\n#define VNORETURN __attribute__((noreturn))\n' +
		records.join('\n') + '\n' + metadata.join('\n') + '\n' + declarations.join('\n') + '\n'
	source := work + '/native-production.c'
	os.write_file(source, prefix + bodies.join('\n\n') + '\n')!
	if hosttest.c_bodies(os.read_file(source)!) != bodies { return error('Native extraction changed production bodies') }
	mut results := []json2.Any{}
	for standard in ['gnu99', 'gnu11'] {
		for optimize in ['O0', 'O1', 'O2'] {
			object := work + '/native-' + standard + '-' + optimize + '.o'
			argv := [hosttest.env_default('CC', 'clang'), '--target=x86_64-unknown-none', '-std=' + standard, '-' + optimize,
				'-ffreestanding', '-fno-builtin', '-fwrapv', '-Wall', '-Wextra', '-Werror',
				'-Wno-unused-function', '-Wno-unused-parameter', '-nostdinc', '-isystem',
				os.join_path(hosttest.root(), 'kernel/freestnd-c-hdrs'), '-c', source, '-o', object]
			hosttest.command(argv, object + '.compile.log', 180, environment)!
			undefined := hosttest.command([hosttest.tool('llvm-nm'), '--undefined-only', object], object + '.imports.log', 30, environment)!.stdout
			mut actual := []string{}
			for line in undefined.split_into_lines() {
				actual << line.fields().last()
			}
			mut expected := ['array_get', 'cpu__cpuid', 'cpu__read_cr4', 'katomic__load_T_u32', 'katomic__load_T_u64',
				'katomic__store_T_u32', 'lib__kpanic', 'memory__user_address_limit']
			if optimize == 'O0' { expected << 'v_panic' }
			actual.sort(); expected.sort()
			if actual != expected || hosttest.allocation_symbols(undefined) { return error('Unexpected production-only imports: ' + undefined) }
			results << json2.Any({'standard': json2.Any(standard), 'optimization': optimize,
				'object_sha256': hosttest.sha(object)!, 'imports': hosttest.strings(actual), 'compiler_argv': hosttest.strings(argv)})
		}
	}
	return map[string]json2.Any{'body_sha256': json2.Any(hosttest.string_map(hashes)), 'objects': json2.Any(results),
		'scope': json2.Any('Exact generated production policy functions and unchanged native sampler block separately compiled for freestanding x86_64-unknown-none with actual compiler array descriptors and scalar host Local metadata. Only real protocol/CPU callees remain unresolved; no allocator is imported. Real native Local layout, CPU boot initialization and hardware operation are separate kernel-artifact evidence.')}
}

fn run_profile(keep string) ! {
	root := hosttest.root()
	linux := hosttest.env_default('LINUXKPI_SOURCE_DIR', root + '/third_party/linux-i915/linux-6.6.157')
	pin := hosttest.upstream_pin()!
	hosttest.verify_upstream(linux, pin)!
	work := hosttest.work_dir(keep, 'vinix-cpu-policy-v-')!
	defer { if keep == '' { hosttest.remove_work_dir(work) or { eprintln(err) } } }
	policies := ['cpu_features_amd64.v', 'cpu_features_enabled_amd64.v']
	mut inputs := [@FILE, root + '/kernel/linuxkpi/bridge_amd64.v', root + '/kernel/x86/cpu/local/local.v',
		root + '/kernel/x86/cpu/initialisation/initialisation.v',
		root + '/kernel/linuxkpi/include/asm/cpufeature.h', root + '/kernel/linuxkpi/include/generated/autoconf.h',
		root + '/kernel/linuxkpi/upstream.json', linux + '/arch/x86/include/asm/cpufeature.h',
		linux + '/arch/x86/include/asm/disabled-features.h', linux + '/arch/x86/include/asm/cpufeatures.h']
	inputs << policies.map(root + '/kernel/linuxkpi/' + it)
	for directory in ['tests/linuxkpi/cpupolicyfixture', 'tests/linuxkpi/policytransport', 'tests/linuxkpi/hosttest'] {
		for extension in ['.v', '.h'] { inputs << os.walk_ext(root + '/' + directory, extension) }
	}
	initial := hosttest.hashes(inputs)!
	for name in ['CHECK_BIT_IN_MASK_WORD', 'DISABLED_MASK_BIT_SET', 'cpu_feature_enabled'] {
		if macro(os.read_file(root + '/kernel/linuxkpi/include/asm/cpufeature.h')!, name)! != macro(os.read_file(linux + '/arch/x86/include/asm/cpufeature.h')!, name)! {
			return error('Compiler policy differs from pinned original: ' + name)
		}
	}
	stage := work + '/stage'
	for module_name in ['linuxkpi', 'katomic', 'lib', 'memory', 'samplefixture', 'x86/cpu/local'] { os.mkdir_all(stage + '/' + module_name)! }
	for module_name in ['cpupolicyfixture', 'policytransport'] {
		original := root + '/tests/linuxkpi/' + module_name
		for extension in ['.v', '.h'] {
			for path in os.walk_ext(original, extension) {
				copied := stage + '/' + module_name + '/' + os.path_rel(original, path)!
				os.mkdir_all(os.dir(copied))!
				os.cp(path, copied)!
			}
		}
	}
	for path in policies { os.cp(root + '/kernel/linuxkpi/' + path, stage + '/linuxkpi/' + path)! }
	frontend := hosttest.v_function(os.read_file(root + '/kernel/linuxkpi/bridge_amd64.v')!, 'cpu_has')!
	os.write_file(stage + '/linuxkpi/frontend.v', 'module linuxkpi\nimport x86.cpu\nimport lib\n' + frontend)!
	initialisation := os.read_file(root + '/kernel/x86/cpu/initialisation/initialisation.v')!
	native_block := sampler_block(initialisation)!
	sampled := 'module samplefixture\nimport x86.cpu\nimport x86.cpu.local as cpulocal\n' +
		'fn sample(mut cpu_local cpulocal.Local, directstore_available bool, directstore_ecx u32) {\n' + native_block + '\n}\n'
	if sampler_block('pub fn initialise() {\n' + native_block + '\n}\n')! != native_block {
		return error('Native sampler block selection changed original source bytes')
	}
	os.write_file(stage + '/samplefixture/selected.v', sampled)!
	for module_name in ['linuxkpi', 'katomic', 'lib', 'memory', 'cpu'] {
		directory := if module_name == 'cpu' { 'x86/cpu' } else { module_name }
		os.cp(root + '/tests/linuxkpi/policytransport/staging/' + module_name + '.v', stage + '/' + directory + '/fixture.v')!
	}
	os.cp(root + '/tests/linuxkpi/policytransport/staging/local.v', stage + '/x86/cpu/local/fixture.v')!
	os.cp(root + '/tests/linuxkpi/policytransport/staging/sampler.v', stage + '/samplefixture/fixture.v')!
	os.write_file(stage + '/v.mod', "Module { name: 'native_cpu_policy_fixture' }\n")!
	os.write_file(stage + '/entry.v', 'module main\nimport cpupolicyfixture as _\nimport linuxkpi as _\nimport samplefixture as _\nfn main() {}\n')!
	selection := hosttest.command(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'find-v', root], '', 30, os.environ())!.stdout
	compiler_v := os.real_path(selection)
	compiler_before := hosttest.sha(compiler_v)!
	array_source := os.dir(compiler_v) + '/vlib/builtin/array.v'
	array_before := hosttest.sha(array_source)!
	mut environment := os.environ()
	environment['VCACHE'] = work + '/vcache'
	environment['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	environment['UBSAN_OPTIONS'] = 'halt_on_error=1'
	environment['ASAN_OPTIONS'] = 'detect_stack_use_after_return=1:abort_on_error=1'
	raw_path := work + '/generated.c'
	argv := [compiler_v, '-no-closures', '-os', 'vinix', '-arch', 'amd64',
		'-target-libc-headers', '-gc', 'none', '-manualfree', '-d', 'nofloat', '-d', 'linuxkpi_host_test', '-d', 'linuxkpi', '-o', raw_path, stage]
	hosttest.command(argv, work + '/generation.log', 120, environment)!
	raw := os.read_file(raw_path)!
	selected := work + '/selected.c'
	os.write_file(selected, selected_source(raw)!)!
	mut includes := ['-D__KERNEL__', '-DVINIX_LINUXKPI', '-DVINIX_LINUXKPI_HOST_TEST',
		'-include', root + '/tests/linuxkpi/host_types.h', '-include', 'linux/kconfig.h',
		'-include', linux + '/include/linux/compiler_types.h']
	for directory in [root + '/tests/linuxkpi', root + '/kernel/linuxkpi/include', linux + '/include',
		linux + '/include/uapi', linux + '/arch/x86/include', linux + '/arch/x86/include/uapi'] { includes << ['-I', directory] }
	mut common := [hosttest.env_default('CC', 'clang'), '-g', '-ffreestanding', '-fno-builtin', '-fwrapv',
		'-fno-strict-aliasing', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-parameter',
		'-pthread', '-fsanitize=address,undefined', '-fno-omit-frame-pointer']
	$if macos { common << ['-arch', 'x86_64'] }
	mut profiles := []json2.Any{}
	for standard in ['gnu99', 'gnu11'] {
		for optimization in ['O0', 'O1', 'O2'] {
			name := standard + '-' + optimization
			object := work + '/' + name + '.o'
			compile := [...common, '-std=' + standard, '-' + optimization, ...includes, '-c', selected, '-o', object]
			hosttest.command(compile, work + '/' + name + '.compile.log', 180, environment)!
			symbols := hosttest.command(['nm', '-u', object], work + '/' + name + '.imports.log', 30, environment)!.stdout
			if hosttest.allocation_symbols(symbols) { return error('Generated CPU policy/fixture imports an allocator') }
			executable := work + '/' + name
			hosttest.command([...common, object, '-o', executable], work + '/' + name + '.link.log', 180, environment)!
			result := hosttest.command([executable], work + '/' + name + '.run.log', 180, environment)!
			if !result.stdout.contains('PASS: V CPU policy') || result.stderr != '' { return error('Incomplete or diagnosed native V policy fixture') }
			profiles << json2.Any({'standard': json2.Any(standard), 'optimization': optimization, 'object_sha256': hosttest.sha(object)!, 'output': result.stdout})
			println(name + ': ' + result.stdout.trim_space())
		}
	}
	native := native_objects(work, raw, os.read_file(selected)!, environment)!
	if initial != hosttest.hashes(inputs)! || hosttest.sha(compiler_v)! != compiler_before
		|| hosttest.sha(array_source)! != array_before { return error('Production, fixture or compiler sources changed during isolated validation') }
	hosttest.write_json(work + '/result.json', {'scope': json2.Any(scope), 'source_sha256': hosttest.string_map(initial),
		'compiler_sha256': hosttest.sha(compiler_v)!, 'generation_argv': hosttest.strings(argv),
		'generated_sha256': hosttest.sha(raw_path)!, 'selected_sha256': hosttest.sha(selected)!,
		'exact_frontend_sha256': hosttest.text_sha(frontend), 'profiles': profiles,
		'production_only_objects': native, 'builtin_array_sha256': array_before,
		'native_sampler': json2.Any({'initialise_function_sha256': json2.Any(hosttest.text_sha(hosttest.v_function(initialisation, 'initialise')!)),
			'original_block_sha256': hosttest.text_sha(native_block), 'wrapper_function_sha256': hosttest.text_sha(hosttest.v_function(sampled, 'sample')!),
			'generated_body_sha256': hosttest.text_sha(hosttest.extract_body(raw, 'samplefixture__sample')!),
			'cases': json2.Any(513), 'scope': json2.Any('Original opt-in block selected byte-for-byte from genuine native initialise(), parameterized only by its enclosing test wrapper. All five raw prerequisite flag patterns, three leaf acknowledgements and both CR4 modes run unchanged; explicit SSE-present row confirms it is a separate dependency branch. Real CPUID/CR4 instructions are V transport observations here.')})})!
}

fn main() {
	keep := hosttest.parse_keep_dir(os.args[1..], 'Usage: cpu_feature_policy.v [--keep-dir NEW]', scope) or { eprintln(err); exit(2) }
	run_profile(keep) or { eprintln(err); exit(1) }
}
