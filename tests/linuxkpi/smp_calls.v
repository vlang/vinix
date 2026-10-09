// SPDX-License-Identifier: GPL-2.0-or-later
// Actual generated V callbacks, original CSD records and independent transport.
module main

import os
import json2
import hosttest

const scope = 'Exercise production SMP callback queues with genuine original CSD records. Host transport models CPU/context and IPI delivery; native maskable interrupts, IRET retirement and retained kernel allocations require the separate kernel guest fixture.'

fn command(argv []string, log string, env map[string]string) !hosttest.Result {
	return hosttest.command(argv, log, 180, env)
}

fn compile_input(argv []string, source string, object string, log string, env map[string]string) !json2.Any {
	// Keep actual compiler-visible inputs and all native include dependencies.
	preprocessed := object + '.i'
	depfile := object + '.d'
	command([...argv, '-E', '-dD', '-MD', '-MF', depfile, '-MT', object, source, '-o', preprocessed], log + '.preprocess', env)!
	dependencies := hosttest.dependency_paths(os.read_file(depfile)!, object)!
	before := hosttest.hashes(dependencies)!
	command([...argv, '-c', source, '-o', object], log, env)!
	if before != hosttest.hashes(dependencies)! { return error('Compiler dependency changed during object build: ${object}') }
	return map[string]json2.Any{
		'object': json2.Any(object)
		'object_sha256': hosttest.sha(object)!
		'actual_source_sha256': hosttest.sha(source)!
		'compiler_visible_input_sha256': hosttest.sha(preprocessed)!
		'dependency_sha256': hosttest.string_map(before)
	}
}

fn selected_source(raw string, prefix string, header string, global_prefixes []string) !string {
	mut bodies := []string{}
	mut declarations := []string{}
	for body in hosttest.c_bodies(raw) {
		line := body.all_before('\n')
		if line.contains(prefix) || line.contains(' vks_smp_') || line.contains(' vkm_') ||
			line.contains(' smp_call_function') || line.contains(' on_each_cpu_cond_mask') ||
			line.contains(' __bitmap_weight(') || line.contains(' arch_atomic_read(') {
			bodies << body
			declarations << line[..line.len - 2] + ';'
		}
	}
	if bodies.len == 0 { return error('No actual generated production bodies') }
	mut globals := []string{}
	for line in raw.split_into_lines() {
		if !line.ends_with(';') || line.starts_with('extern ') || line.starts_with('typedef ') ||
			line.starts_with('\t') || line.starts_with(' ') { continue }
		declaration := if line.starts_with('__attribute__((visibility("default"))) ') {
			line.all_after('__attribute__((visibility("default"))) ')
		} else { line }
		if declaration.contains('(') { continue }
		if global_prefixes.any(line.contains(it)) || line.contains(prefix + 'v3_no_main_initialized') { globals << line }
	}
	mut callback_types := []string{}
	for line in raw.split_into_lines() {
		if line.starts_with('typedef ') && line.contains('(*_fn_ptr_') { callback_types << line }
	}
	mut zero_metadata := []string{}
	for line in raw.split_into_lines() { if line.starts_with('#define E_STRUCT ') { zero_metadata << line } }
	text := '#include <stdint.h>\n#include <stddef.h>\n#include <stdbool.h>\n' +
		(if prefix == 'headercore__' { 'typedef uint64_t u64;\n' } else { 'typedef uint32_t u32; typedef uint64_t u64; typedef uint16_t u16;\n' }) +
		'typedef int32_t i32; typedef int64_t i64; typedef size_t usize; typedef void *voidptr;\n' +
		header + zero_metadata.join('\n') + '\n' + callback_types.join('\n') + '\n' + globals.join('\n') + '\n' +
		declarations.join('\n') + '\n' + bodies.join('\n\n') + '\n'
	if hosttest.c_bodies(text) != bodies { return error('Metadata extraction changed an actual generated V body') }
	return text
}

fn stage_sources(work string) ![]string {
	root := hosttest.root()
	mut owned := []string{}
	for name in ['compatcore', 'headercore'] { os.mkdir(os.join_path(work, name))! }
	for module_name, paths in {
		'compatcore': ['smp_call.v', 'smp_masks.v']
		'headercore': ['smp_call.v', 'smp_masks.v', 'smp_masks_storage.v']
	} {
		for path in paths {
			original := os.join_path(root, 'kernel/linuxkpi', module_name, path)
			os.cp(original, os.join_path(work, module_name, path))!
			owned << original
		}
	}
	primitive := os.join_path(root, 'kernel/linuxkpi/compatcore/primitives.v')
	bitmap := os.join_path(root, 'kernel/linuxkpi/compatcore/bitmap.v')
	atomic_path := os.join_path(root, 'kernel/linuxkpi/headercore/primitive.v')
	owned << [primitive, bitmap, atomic_path]
	mut bindings := '@[translated]\nmodule compatcore\n#include "linuxkpi_smp_call_v_primitives.h"\n' +
		'fn C.kmalloc(usize,u32) voidptr\nfn C.kfree(voidptr)\nfn C.memset(voidptr,i32,usize) voidptr\n' +
		'fn C.vinix_linuxkpi_bug(&char,i32)\nfn C.vinix_linuxkpi_irq_flags() u64\n' +
		'fn C.vinix_linuxkpi_irq_save() u64\nfn C.vinix_linuxkpi_irq_restore(u64)\n' +
		'fn C.vinix_linuxkpi_preempt_count() u32\nfn C.vinix_linuxkpi_spin_wait()\n'
	for name in ['require', 'native_hweight_long'] { bindings += hosttest.v_function(os.read_file(primitive)!, name)! }
	bindings += hosttest.v_function(os.read_file(bitmap)!, 'bitmap_weight')!
	os.write_file(os.join_path(work, 'compatcore/bindings.v'), bindings)!
	os.write_file(os.join_path(work, 'headercore/bindings.v'), '@[translated]\nmodule headercore\n' +
		'#include "linuxkpi_header_primitive_v_contract.h"\n@[typedef]\nstruct C.atomic_t { counter i32 }\n' +
		'@[typedef]\nstruct C.vhp_const_atomicp {}\nfn C.test_bit(i32,voidptr) bool\n' +
		"@[c: '__atomic_load_n']\nfn C.vhp_load32(&i32,i32) i32\n" +
		hosttest.v_function(os.read_file(atomic_path)!, 'atomic_read')!)!
	return owned
}

fn profile(work string, linux string, compiler []string, standard string) []string {
	root := hosttest.root()
	mut argv := compiler.clone()
	$if macos { argv << ['-arch', 'x86_64'] }
	argv << ['-std=' + standard, '-O1', '-g', '-ffreestanding', '-fno-builtin', '-fwrapv',
		'-fno-strict-aliasing', '-ffunction-sections', '-fdata-sections', '-Wall', '-Wextra', '-Werror',
		'-Wno-unused-function', '-Wno-unused-parameter', '-Wno-sign-compare',
		'-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-D_FORTIFY_SOURCE=0',
		'-DVINIX_LINUXKPI', '-DVINIX_LINUXKPI_HOST_TEST', '-D__KERNEL__',
		'-include', os.join_path(root, 'tests/linuxkpi/host_types.h'), '-include', 'linux/kconfig.h',
		'-include', os.join_path(linux, 'include/linux/compiler_types.h')]
	for directory in [os.join_path(work, 'include'), os.join_path(root, 'tests/linuxkpi/smpcallfixture'),
		os.join_path(root, 'kernel/linuxkpi/include'),
		os.join_path(linux, 'include'), os.join_path(linux, 'include/uapi'),
		os.join_path(linux, 'arch/x86/include'), os.join_path(linux, 'arch/x86/include/uapi')] {
		argv << ['-I', directory]
	}
	argv << ['-iquote', os.join_path(root, 'kernel/c')]
	return argv
}

fn run_profile(keep string) ! {
	root := hosttest.root()
	linux := hosttest.env_default('LINUXKPI_SOURCE_DIR', os.join_path(root, 'third_party/linux-i915/linux-6.6.157'))
	compiler := hosttest.shell_split(hosttest.env_default('CC', 'clang'))!
	work := hosttest.work_dir(keep, 'vinix-smp-callbacks-')!
	defer { if keep == '' { hosttest.remove_work_dir(work) or { eprintln(err) } } }
	mut env := os.environ()
	env['VCACHE'] = os.join_path(work, 'vcache')
	env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	env['ASAN_OPTIONS'] = 'detect_stack_use_after_return=1:abort_on_error=1'
	env['UBSAN_OPTIONS'] = 'halt_on_error=1'
	stage := os.join_path(work, 'stage')
	os.mkdir(stage)!
	mut observed := stage_sources(stage)!
	observed << [@FILE, os.join_path(root, 'tests/linuxkpi/smpcallfixture/core.v'),
		os.join_path(root, 'tests/linuxkpi/smpcallfixture/smpcall_host_contract.h')]
	observed << os.walk_ext(os.join_path(root, 'tests/linuxkpi/hosttest'), '.v')
	for name in ['linuxkpi_smp_call_v_primitives.h', 'linuxkpi_smp_call_v_contract.h',
		'linuxkpi_smp_masks_v_primitives.h', 'linuxkpi_smp_masks_v_contract.h'] {
		observed << os.join_path(root, 'kernel/c', name)
	}
	initial := hosttest.hashes(observed)!
	compiler_path := os.real_path(os.find_abs_path_of_executable(compiler[0]) or { compiler[0] })
	v_selection := hosttest.env_default('V', 'v')
	v_path := os.real_path(os.find_abs_path_of_executable(v_selection) or { v_selection })
	tools := map[string]json2.Any{
		'V_path': json2.Any(v_path)
		'V_sha256': hosttest.file_digest(v_path)!
		'C_path': compiler_path
		'C_sha256': hosttest.file_digest(compiler_path)!
		'C_version': command([...compiler, '--version'], os.join_path(work, 'compiler-version.log'), env)!.stdout
	}
	pin := hosttest.upstream_pin()!
	hosttest.verify_upstream(linux, pin)!
	hosttest.write_json(os.join_path(work, 'initial-source-sha256.json'), hosttest.string_map(initial))!
	include := os.join_path(work, 'include')
	for schema, name in {'atomic-exchange': 'atomic_exchange', 'overflow': 'integer_policy', 'spinlock': 'spinlock_adapters'} {
		hosttest.generate_abi(os.join_path(root, 'kernel/linuxkpi/abi', schema + '.json'),
			os.join_path(root, 'kernel/linuxkpi'), os.join_path(include, 'vinix', name + '.h'))!
	}
	mut proofs := []json2.Any{}
	for name in ['compatcore', 'headercore'] {
		generated := os.join_path(work, name + '-actual.c')
		hosttest.generate_module(os.join_path(stage, name), generated, 'amd64', ['linuxkpi_host_test', 'nofloat'])!
		raw := os.read_file(generated)!
		header := if name == 'headercore' {
			'#include "linuxkpi_smp_call_v_contract.h"\n#include "linuxkpi_smp_masks_v_contract.h"\n' +
			'#include "linuxkpi_header_primitive_v_contract.h"\n' +
			'typedef struct cpumask cpumask;\n' +
			hosttest.scalar_metadata(os.join_path(stage, name), '')!
		} else { '#include "linuxkpi_smp_call_v_primitives.h"\n#include "linuxkpi_smp_masks_v_primitives.h"\n' +
			'void *kmalloc(size_t,uint32_t); void kfree(void *); void vinix_linuxkpi_bug(const char *,int32_t);\n#include <string.h>\n' }
		prefixes := if name == 'headercore' { ['cpu_bit_bitmap', 'cpu_all_bits', '__cpu_', '__num_online_cpus', 'nr_cpu_ids'] }
			else { ['compatcore__vks_smp_', 'compatcore__vkms_ready'] }
		selected := selected_source(raw, name + '__', header, prefixes)!
		os.write_file(os.join_path(work, name + '-selected.c'), selected)!
		proofs << map[string]json2.Any{'module': json2.Any(name), 'actual_generated_c_sha256': hosttest.sha(generated)!,
			'selected_c_sha256': hosttest.text_sha(selected), 'actual_body_count': hosttest.c_bodies(selected).len}
	}
	fixture_source := os.join_path(work, 'smpcallfixture')
	os.mkdir(fixture_source)!
	os.cp(os.join_path(root, 'tests/linuxkpi/smpcallfixture/core.v'), os.join_path(fixture_source, 'core.v'))!
	hosttest.generate_module(fixture_source, os.join_path(work, 'fixture.c'), 'amd64', ['nofloat'])!
	mut results := []json2.Any{}
	mut inputs := []json2.Any{}
	for standard in ['gnu99', 'gnu11'] {
		base := profile(work, linux, compiler, standard)
		mut objects := []string{}
		for group in ['compatcore', 'headercore'] {
			obj := os.join_path(work, standard + '-' + group + '.o')
			inputs << compile_input(base, os.join_path(work, group + '-selected.c'), obj,
				os.join_path(work, standard + '-' + group + '-compile.log'), env)!
			imports := command([hosttest.tool('llvm-nm'), '-u', obj], '', env)!.stdout
			os.write_file(os.join_path(work, standard + '-' + group + '-imports.txt'), imports)!
			if hosttest.allocation_symbols(imports) { return error('Implicit production allocator import') }
			objects << obj
		}
		// Fixture compiler metadata can repeat foreign declarations under GNU11;
		// the selected unaltered production functions above are strict in both.
		fixture := os.join_path(work, standard + '-fixture.o')
		fixture_flags := profile(work, linux, compiler, 'gnu11')
		inputs << compile_input(fixture_flags, os.join_path(work, 'fixture.c'), fixture,
			os.join_path(work, standard + '-fixture-compile.log'), env)!
		objects << fixture
		executable := os.join_path(work, standard + '-test')
		dead_strip := $if macos { '-Wl,-dead_strip' } $else { '-Wl,--gc-sections' }
		command([...base, ...objects, dead_strip, '-pthread', '-o', executable], os.join_path(work, standard + '-link.log'), env)!
		for count in [4, 63, 64, 65, 127, 128, 129, 191, 192, 193, 255, 256] {
			for mode in [0, 1, 2] {
				log := os.join_path(work, '${standard}-${count}-${mode}-run.log')
				passed := command([executable, count.str(), mode.str()], log, env)!
				if passed.stderr != '' || !passed.stdout.starts_with('PASS: ') { return error('Missing clean SMP callback verdict: ${log}') }
				results << map[string]json2.Any{'standard': json2.Any(standard), 'cpus': count, 'mode': mode,
					'output': passed.stdout.trim_space(), 'executable_sha256': hosttest.sha(executable)!}
			}
		}
	}
	if initial != hosttest.hashes(observed)! { return error('Production/test source changed during checks') }
	hosttest.verify_upstream(linux, pin)!
	hosttest.write_json(os.join_path(work, 'result.json'), map[string]json2.Any{
		'scope': json2.Any(scope), 'source_sha256': hosttest.string_map(initial),
		'actual_generated_body_proofs': proofs, 'runs': results,
		'compiler': tools, 'object_and_native_input_proofs': inputs,
		'upstream_pin': pin,
		'fixture_c_sha256': hosttest.sha(os.join_path(work, 'fixture.c'))!
	})!
	println('LinuxKPI SMP callbacks: actual V backend, original CSDs, strict GNU99/GNU11 and host ASan/UBSan scenarios passed')
}

fn main() {
	options := hosttest.parse_path_options(os.args[1..], ['--keep-directory'], 'Usage: smp_calls.v [--keep-directory DIRECTORY]', scope) or { eprintln(err); exit(2) }
	run_profile(options['--keep-directory']) or { eprintln(err); exit(1) }
}
