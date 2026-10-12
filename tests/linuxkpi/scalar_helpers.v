// SPDX-License-Identifier: GPL-2.0-or-later
// Independent V tests for actual production scalar/type helpers.
module main

import os
import json2
import hosttest

fn require(condition bool, message string) ! {
	if !condition { return error(message) }
}

fn command(argv []string, log string, cwd string, env map[string]string) !hosttest.Result {
	result := hosttest.capture_in(argv, '', 180, env, cwd)!
	os.write_file(log, result.stdout + result.stderr)!
	if result.code != 0 { return error(result.stdout + result.stderr) }
	return result
}

fn entry(path string, variable string, name string) !bool {
	for line in os.read_file(path)!.split_into_lines() {
		words := line.fields()
		if words.len == 3 && words[0] == variable && words[1] == '+=' && words[2] == name {
			return true
		}
	}
	return false
}

fn definition(text string, name string) !string {
	lines := text.split_into_lines().filter(it.starts_with('#define ' + name + '('))
	require(lines.len == 1, 'Expected one original compiler macro: ' + name)!
	return lines[0]
}

fn uncomment(text string) !string {
	mut remaining := text
	for remaining.trim_left(' \t\r\n').starts_with('/*') {
		remaining = remaining.trim_left(' \t\r\n')
		end := remaining.index('*/') or { return error('Unterminated wrapper comment') }
		remaining = remaining[end + 2..]
	}
	return remaining.trim_left(' \t\r\n')
}

fn resource_wrapper(work string, linux string, pin map[string]json2.Any, env map[string]string) !json2.Any {
	uapi := os.join_path(linux, 'include/uapi/asm-generic/Kbuild')
	arch := os.join_path(linux, 'arch/x86/include/uapi/asm/Kbuild')
	internal := os.join_path(linux, 'include/asm-generic/Kbuild')
	require(entry(uapi, 'mandatory-y', 'resource.h')!, 'resource.h is not a pinned UAPI mandatory header')!
	require(!entry(internal, 'mandatory-y', 'resource.h')!, 'resource.h unexpectedly belongs to non-UAPI mandatory-y')!
	require(!entry(arch, 'generated-y', 'resource.h')!, 'x86 now generates its own resource.h')!
	for path in ['arch/x86/include/asm/resource.h', 'arch/x86/include/uapi/asm/resource.h'] {
		require(!os.exists(os.join_path(linux, path)), 'x86 now owns resource.h: ' + path)!
	}
	archive := os.join_path(os.dir(linux), 'linux-' + pin['version']!.str() + '.tar.xz')
	require(hosttest.file_digest(archive)! == pin['sha256']!.str(), 'Original Kbuild archive hash changed')!
	reference := os.join_path(work, 'original-uapi-kbuild')
	scripts := ['scripts/Kbuild.include', 'scripts/Makefile.asm-generic']
	prefix := 'linux-' + pin['version']!.str() + '/'
	members := hosttest.archive_members(archive, scripts.map(prefix + it))!
	for script in scripts {
		path := os.join_path(reference, script)
		os.mkdir_all(os.dir(path))!
		os.write_file_array(path, members[prefix + script] or { return error('Missing original script: ' + script) })!
	}
	os.symlink(os.join_path(linux, 'include'), os.join_path(reference, 'include'))!
	x86 := os.join_path(reference, 'arch/x86/include/uapi')
	os.mkdir_all(x86)!
	os.symlink(os.join_path(linux, 'arch/x86/include/uapi/asm'), os.join_path(x86, 'asm'))!
	argv := [hosttest.env_default('MAKE', 'make'), '-f', 'scripts/Makefile.asm-generic',
		'srctree=' + reference, 'obj=arch/x86/include/generated/uapi/asm',
		'generic=include/uapi/asm-generic', 'SRCARCH=x86']
	command(argv, os.join_path(work, 'original-uapi-kbuild.log'), reference, env)!
	generated := os.join_path(reference, 'arch/x86/include/generated/uapi/asm/resource.h')
	overlay := os.join_path(hosttest.upstream_here(), 'include/asm/resource.h')
	require(uncomment(os.read_file(overlay)!)!.bytes() == os.read_bytes(generated)!, 'resource.h differs from the exact original Kbuild wrapper')!
	return map[string]json2.Any{
		'argv':           hosttest.strings(argv)
		'archive_sha256': pin['sha256']!
		'script_sha256':  hosttest.string_map(hosttest.hashes(scripts.map(os.join_path(reference, it)))!)
		'wrapper':        json2.Any(os.read_file(generated)!)
		'wrapper_sha256': hosttest.sha(generated)!
	}
}

fn production_source(work string) !string {
	root := hosttest.root()
	primitive := os.join_path(root, 'kernel/linuxkpi/headercore/primitive.v')
	contract := os.join_path(root, 'kernel/c/linuxkpi_header_primitive_v_contract.h')
	alias := 'typedef const void *vhp_const_voidp;'
	require(os.read_file(contract)!.split_into_lines().contains(alias), 'Native const-pointer owner changed')!
	stage := os.join_path(work, 'errorcore')
	os.mkdir(stage)!
	mut text := '@[translated]\nmodule errorcore\n#include "linuxkpi_header_primitive_v_contract.h"\n@[typedef]\nstruct C.vhp_const_voidp {}\n'
	for name in ['error_pointer', 'pointer_error', 'error_cast', 'is_error'] {
		text += hosttest.v_function(os.read_file(primitive)!, name)!
	}
	os.write_file(os.join_path(stage, 'core.v'), text)!
	generated := os.join_path(work, 'production-generated.c')
	hosttest.generate_module(stage, generated, 'amd64', ['nofloat', 'linuxkpi_host_test'])!
	raw := os.read_file(generated)!
	mut bodies := []string{}
	symbols := ['ERR_PTR', 'PTR_ERR', 'ERR_CAST', 'IS_ERR', 'errorcore__error_pointer',
		'errorcore__pointer_error', 'errorcore__error_cast', 'errorcore__is_error',
		'errorcore__vno_main_init_caller']
	for symbol in symbols {
		bodies << hosttest.extract_body(raw, symbol)!
	}
	globals := raw.split_into_lines().filter(it.starts_with('static bool errorcore__v3_no_main_initialized ='))
	require(globals.len == 1, 'Missing unique actual generated module initialization owner')!
	selected := '#include <stdbool.h>\n#include <stddef.h>\n#include <stdint.h>\ntypedef size_t usize; typedef long isize; typedef void *voidptr;\n' +
		alias + '\n' + globals.join('\n') + '\n' + hosttest.c_declarations(raw, symbols)! + '\n' + bodies.join('\n\n') + '\n'
	require(hosttest.c_bodies(selected) == bodies, 'Selected source changed an actual production body')!
	result := os.join_path(work, 'production-selected.c')
	os.write_file(result, selected)!
	return result
}

fn fixture_source(raw_path string, selected_path string, name string, header string, public_only bool) ! {
	raw := os.read_file(raw_path)!
	bodies := hosttest.c_bodies(raw).filter(it.all_before('\n').contains(name + '__') || hosttest.named_body(it, 'main'))
	require(bodies.len > 1, 'Missing actual generated fixture bodies')!
	mut declarations := []string{}
	for body in bodies { declarations << body.all_before('\n').all_before_last(' {') + ';' }
	globals := raw.split_into_lines().filter(it.starts_with('static bool ' + name + '__v3_no_main_initialized ='))
	require(globals.len == 1, 'Missing actual generated fixture initialization owner')!
	selected := '#include <stdint.h>\n#include <stdbool.h>\n#include <stddef.h>\n#include <string.h>\n' +
		'typedef uint64_t u64; typedef int32_t i32; typedef int64_t i64; typedef void *voidptr;\n' +
		(if public_only { 'typedef uint32_t u32;\n' } else { '' }) +
		'#define E_STRUCT 0\n#include "' + header + '"\n' + globals.join('\n') + '\n' +
		declarations.join('\n') + '\n' + bodies.join('\n\n') + '\n'
	require(hosttest.c_bodies(selected) == bodies, 'Metadata selection changed an actual generated fixture body')!
	os.write_file(selected_path, selected)!
}

fn compile_input(argv []string, source string, object string, log string, env map[string]string) !json2.Any {
	preprocessed := object + '.i'
	depfile := object + '.d'
	command([...argv, '-E', '-dD', '-MD', '-MF', depfile, '-MT', object, source, '-o', preprocessed], log + '.preprocess', '', env)!
	dependencies := hosttest.dependency_paths(os.read_file(depfile)!, object)!
	before := hosttest.hashes(dependencies)!
	command([...argv, '-c', source, '-o', object], log, '', env)!
	require(before == hosttest.hashes(dependencies)!, 'Compiler-visible input changed during build')!
	imports := command(['nm', '-u', object], log + '.imports', '', env)!.stdout
	require(!hosttest.allocation_symbols(imports), 'Generated helper/fixture imports an allocator:\n' + imports)!
	return map[string]json2.Any{
		'argv':                    hosttest.strings(argv)
		'generated_source_sha256': hosttest.sha(source)!
		'compiler_visible_sha256': hosttest.sha(preprocessed)!
		'object_sha256':           hosttest.sha(object)!
		'dependency_sha256':       hosttest.string_map(before)
		'unresolved_symbols':      json2.Any(imports)
	}
}

fn resource_inputs(compiled json2.Any, linux string, wrapper string, public_only bool) ! {
	inputs := compiled.as_map()['dependency_sha256']!.as_map().keys()
	for path in [wrapper, os.join_path(linux, 'include/uapi/linux/resource.h'),
		os.join_path(linux, 'include/uapi/asm-generic/resource.h')] {
		require(os.real_path(path) in inputs, 'Compiler omitted the selected original resource header: ' + path)!
	}
	internal := os.real_path(os.join_path(linux, 'include/asm-generic/resource.h'))
	require((internal in inputs) == !public_only, 'Compiler selected the wrong generic resource namespace')!
	if public_only {
		require(!inputs.any(it.starts_with(os.join_path(hosttest.root(), 'kernel/linuxkpi/include') + '/')),
			'Public UAPI compiler fixture unexpectedly used a kernel compatibility header')!
	}
}

fn run_profile(keep string) ! {
	root := hosttest.root()
	linux := hosttest.env_default('LINUXKPI_SOURCE_DIR', os.join_path(root, 'third_party/linux-i915/linux-6.6.157'))
	pin := hosttest.upstream_pin()!
	hosttest.verify_upstream(linux, pin)!
	work := hosttest.work_dir(keep, 'vinix-scalar-helpers-')!
	defer { if keep == '' { hosttest.remove_work_dir(work) or { eprintln(err) } } }
	compiler := hosttest.shell_split(hosttest.env_default('CC', 'clang'))!
	compiler_path := os.real_path(os.find_abs_path_of_executable(compiler[0]) or { return error('Missing compiler executable') })
	// Use the same maintained compiler selector as the V module producer.
	native_v := hosttest.capture(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"',
		'find-v', root], '', 30, os.environ())!
	require(native_v.code == 0, 'Native V compiler selection failed:\n' + native_v.stderr)!
	native_v_path := os.real_path(native_v.stdout)
	mut guarded := [@FILE, os.join_path(root, 'kernel/linuxkpi/headercore/primitive.v'),
		os.join_path(root, 'kernel/c/linuxkpi_header_primitive_v_contract.h'),
		os.join_path(root, 'kernel/linuxkpi/upstream.json'), compiler_path, native_v_path,
		os.join_path(root, 'build-support/find-v.sh')]
	for path in ['include/linux/kernel.h', 'include/linux/types.h', 'include/linux/err.h',
		'include/uapi/asm-generic/Kbuild', 'include/asm-generic/Kbuild',
		'arch/x86/include/uapi/asm/Kbuild'] {
		guarded << os.join_path(linux, path)
	}
	for directory in ['tests/linuxkpi/scalarfixture', 'tests/linuxkpi/resourcefixture',
		'tests/linuxkpi/hosttest', 'kernel/linuxkpi/include'] {
		for extension in ['.v', '.h'] {
			guarded << os.walk_ext(os.join_path(root, directory), extension)
		}
	}
	initial := hosttest.hashes(guarded)!
	for name in ['upper_32_bits', 'lower_32_bits'] {
		require(definition(os.read_file(os.join_path(root, 'kernel/linuxkpi/include/linux/kernel.h'))!, name)! ==
			definition(os.read_file(os.join_path(linux, 'include/linux/kernel.h'))!, name)!, 'Extractor differs from the exact pinned macro')!
	}
	mut env := os.environ()
	env['VCACHE'] = os.join_path(work, 'vcache')
	env['ASAN_OPTIONS'] = 'detect_stack_use_after_return=1:abort_on_error=1'
	env['UBSAN_OPTIONS'] = 'halt_on_error=1'
	// Producers read os.environ directly; publish the private compiler cache there too.
	os.setenv('VCACHE', env['VCACHE'], true)
	compiler_version := command([...compiler, '--version'], os.join_path(work, 'compiler-version.log'), '', env)!
	v_version := command([native_v_path, 'version'], os.join_path(work, 'native-v-version.log'), '', env)!
	kbuild := resource_wrapper(work, linux, pin, env)!
	include := os.join_path(work, 'include')
	hosttest.audit_headers(include)!
	production := production_source(work)!
	scalar_raw := os.join_path(work, 'scalar-generated.c')
	resource_raw := os.join_path(work, 'resource-generated.c')
	hosttest.generate_module(os.join_path(root, 'tests/linuxkpi/scalarfixture'), scalar_raw, 'amd64', [
		'nofloat',
		'linuxkpi_host_test',
	])!
	hosttest.generate_module(os.join_path(root, 'tests/linuxkpi/resourcefixture'), resource_raw, 'amd64', [
		'nofloat',
		'linuxkpi_host_test',
	])!
	scalar := os.join_path(work, 'scalar-selected.c')
	resource := os.join_path(work, 'resource-selected.c')
	fixture_source(scalar_raw, scalar, 'scalarfixture', 'scalar_v_contract.h', false)!
	fixture_source(resource_raw, resource, 'resourcefixture', 'resource_v_contract.h', true)!
	mut common := [...compiler, '-O1', '-g', '-ffreestanding', '-fno-builtin', '-fwrapv',
		'-fno-strict-aliasing', '-ffunction-sections', '-fdata-sections', '-Wall', '-Wextra', '-Werror',
		'-Wno-unused-function', '-Wno-unused-parameter', '-fsanitize=address,undefined',
		'-fno-omit-frame-pointer', '-D_FORTIFY_SOURCE=0']
	$if macos {
		common << ['-arch', 'x86_64']
	}
	link_gc := $if macos { '-Wl,-dead_strip' } $else { '-Wl,--gc-sections' }
	generated_uapi := os.join_path(work, 'original-uapi-kbuild/arch/x86/include/generated/uapi')
	mut results := []json2.Any{}
	for standard in ['gnu99', 'gnu11'] {
		production_object := os.join_path(work, standard + '-production.o')
		production_result := compile_input([...common, '-std=' + standard], production, production_object,
			os.join_path(work, standard + '-production.log'), env)!
		for first in ['kernel-first', 'uapi-first'] {
			for wrapper in ['overlay', 'original-kbuild'] {
				tag := standard + '-' + first + '-' + wrapper
				mut argv := [...common, '-std=' + standard, '-DVINIX_LINUXKPI',
					'-DVINIX_LINUXKPI_HOST_TEST', '-D__KERNEL__', '-include',
					os.join_path(root, 'tests/linuxkpi/scalarfixture/scalar_host_resource.h'),
					'-include', os.join_path(root, 'tests/linuxkpi/host_types.h'), '-include',
					'linux/kconfig.h', '-include',
					os.join_path(linux, 'include/linux/compiler_types.h'), '-iquote',
					os.join_path(root, 'tests/linuxkpi/scalarfixture')]
				if first == 'uapi-first' { argv << '-DVSH_UAPI_FIRST' }
				if wrapper == 'original-kbuild' { argv << ['-I', generated_uapi] }
				for path in [include, os.join_path(root, 'kernel/linuxkpi/include'),
					os.join_path(linux, 'include'), os.join_path(linux, 'include/uapi'),
					os.join_path(linux, 'arch/x86/include'),
					os.join_path(linux, 'arch/x86/include/uapi')] {
					argv << ['-I', path]
				}
				object := os.join_path(work, tag + '.o')
				compiled := compile_input(argv, scalar, object, os.join_path(work, tag + '.compile.log'), env)!
				selected_wrapper := if wrapper == 'overlay' {
					os.join_path(root, 'kernel/linuxkpi/include/asm/resource.h')
				} else {
					os.join_path(generated_uapi, 'asm/resource.h')
				}
				resource_inputs(compiled, linux, selected_wrapper, false)!
				executable := os.join_path(work, tag)
				command([...common, object, production_object, link_gc, '-o', executable], executable + '.link.log', '', env)!
				ran := command([executable], executable + '.run.log', '', env)!
				require(ran.stdout.contains('PASS: native scalar'), 'Missing scalar fixture completion marker')!
				results << json2.Any(map[string]json2.Any{
					'profile':           json2.Any(tag)
					'production':        production_result
					'fixture':           compiled
					'executable_sha256': hosttest.sha(executable)!
					'stdout':            ran.stdout
				})
				println(tag + ': actual V helpers and original macro/type ABI passed ASan/UBSan')
			}
		}
		tag := standard + '-original-uapi-only'
		// Source UAPI headers retain their original compiler-annotation include;
		// use the original annotation owner as a fallback, with no kernel overlay.
		mut argv := [...common, '-std=' + standard, '-D__EXPORTED_HEADERS__', '-iquote',
			os.join_path(root, 'tests/linuxkpi/resourcefixture')]
		for path in [generated_uapi, os.join_path(linux, 'include/uapi'),
			os.join_path(linux, 'arch/x86/include/uapi')] {
			argv << ['-I', path]
		}
		argv << ['-idirafter', os.join_path(linux, 'include')]
		object := os.join_path(work, tag + '.o')
		compiled := compile_input(argv, resource, object, os.join_path(work, tag + '.compile.log'), env)!
		resource_inputs(compiled, linux, os.join_path(generated_uapi, 'asm/resource.h'), true)!
		executable := os.join_path(work, tag)
		command([...common, object, link_gc, '-o', executable], executable + '.link.log', '', env)!
		ran := command([executable], executable + '.run.log', '', env)!
		require(ran.stdout.contains('PASS: original UAPI resource'), 'Missing public resource completion marker')!
		results << json2.Any(map[string]json2.Any{
			'profile':           json2.Any(tag)
			'fixture':           compiled
			'executable_sha256': hosttest.sha(executable)!
			'stdout':            ran.stdout
		})
		println(tag + ': original generated wrapper, public constants and records passed ASan/UBSan')
	}
	require(initial == hosttest.hashes(guarded)!, 'Helper/controller sources changed during isolated checks')!
	hosttest.write_json(os.join_path(work, 'result.json'), map[string]json2.Any{
		'scope':                       json2.Any('Exact original umode/extractor compiler contracts and actual generated V ERR_CAST identity. Original UAPI resource wrapper is separately derived through pinned Kbuild and compiled without kernel overlays. No task/MM or resource-limit enforcement is supplied.')
		'linux_version':               pin['version']!
		'input_sha256':                hosttest.string_map(initial)
		'host_machine':                json2.Any(os.uname().machine)
		'native_v_compiler':           map[string]json2.Any{
			'path':    json2.Any(native_v_path)
			'sha256':  hosttest.sha(native_v_path)!
			'version': v_version.stdout
		}
		'c_compiler':                  map[string]json2.Any{
			'path':    json2.Any(compiler_path)
			'sha256':  hosttest.sha(compiler_path)!
			'version': compiler_version.stdout
		}
		'production_generated_sha256': hosttest.sha(os.join_path(work, 'production-generated.c'))!
		'production_selected_sha256':  hosttest.sha(production)!
		'scalar_generated_sha256':     hosttest.sha(scalar_raw)!
		'resource_generated_sha256':   hosttest.sha(resource_raw)!
		'kbuild':                      kbuild
		'results':                     results
	})!
}

fn main() {
	keep := hosttest.parse_keep_dir(os.args[1..], 'Usage: scalar_helpers.v [--keep-dir DIRECTORY]',
		'Check original scalar/type macros and actual generated V error-pointer casts.') or {
		eprintln(err.msg())
		exit(2)
	}
	run_profile(keep) or {
		eprintln(err.msg())
		exit(1)
	}
}
