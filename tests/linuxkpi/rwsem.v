// SPDX-License-Identifier: GPL-2.0-or-later
// Actual rwsem production V, original Linux records and independent transport.
module main

import os
import json2
import hosttest

const scope = 'Execute unchanged native sleeping rwsem V and all11 original typed facades with original Linux records and independent V task/IRQ/spin/park transports. Host records are smaller explicit transports; native scheduling, IRQ entry, retained allocations and future MM services need separate guest evidence.'

fn generate_command(argv []string, _log string, timeout int, env map[string]string) !hosttest.Result {
	output := argv[(argv.index('-o')) + 1]
	mut child_env := env.clone()
	for name, directory in {'VCACHE': 'vcache', 'V3CACHE': 'v3cache', 'VTMP': 'vtmp'} {
		child_env[name] = os.dir(output) + '/' + directory
	}
	mut saved := map[string]json2.Any{}
	for name in ['V', 'VEXE', 'V_MACOS_V3_CALLER_VEXE', 'V_MACOS_V3_CALLER_VEXE_PRESENT',
		'V_MACOS_V3_CALLER_VCHILD_PRESENT', 'VCACHE', 'V3CACHE', 'VTMP', 'TMPDIR'] {
		saved[name] = child_env[name] or { '<unset>' }
	}
	hosttest.write_json(output + '.generation-environment.json', saved)!
	// The producer normally removes its private source tree on return. Keep an
	// exact copy, including failed compiler attempts, beside every generation.
	os.cp_all(argv.last(), output + '.generation-source', false)!
	gc_collect()
	result := hosttest.capture(argv, output + '.generation.log', if timeout < 0 { 180 } else { timeout }, child_env)!
	hosttest.write_json(output + '.generation-status.json', {
		'exit_code': json2.Any(result.code)
	})!
	if result.code != 0 {
		return error('V generation failed with exit ${result.code}: see ${output}.generation.log')
	}
	return result
}

fn generate(source string, output string) ! {
	hosttest.generate_module_with_capture(source, output, 'amd64', [
		'linuxkpi_host_test',
		'nofloat',
	], generate_command)!
}

fn compile_input(argv []string, source string, object string, env map[string]string) !json2.Any {
	dep := object + '.d'
	pre := object + '.i'
	hosttest.command([...argv, '-E', '-dD', '-MD', '-MF', dep, '-MT', object, source, '-o', pre], object + '.preprocess.log', 180, env)!
	before := hosttest.hashes(hosttest.dependency_paths(os.read_file(dep)!, object)!)!
	hosttest.command([...argv, '-c', source, '-o', object], object + '.compile.log', 180, env)!
	if before != hosttest.hashes(before.keys())! { return error('Compiler input changed') }
	return {
		'source':              json2.Any(source)
		'source_sha256':       hosttest.sha(source)!
		'object':              object
		'object_sha256':       hosttest.sha(object)!
		'preprocessed':        pre
		'preprocessed_sha256': hosttest.sha(pre)!
		'dependency_sha256':   hosttest.string_map(before)
		'argv':                hosttest.strings(argv)
	}
}

fn stage(work string) ![]string {
	root := hosttest.root()
	mut paths := []string{}
	for name in ['compatcore', 'headercore', 'rwsemfixture'] { os.mkdir_all(work + '/' + name)! }
	for name in ['compatcore', 'headercore'] {
		path := root + '/kernel/linuxkpi/' + name + '/rwsem.v'
		os.cp(path, work + '/' + name + '/rwsem.v')!
		paths << path
	}
	p := root + '/kernel/linuxkpi/compatcore/primitives.v'
	ww := root + '/kernel/linuxkpi/compatcore/ww_mutex.v'
	wait := root + '/kernel/linuxkpi/compatcore/wait_bit.v'
	paths << [p, ww, wait]
	mut bind := '@[translated]\nmodule compatcore\n#include "linuxkpi_rwsem_v_primitives.h"\nstruct C.vkw_list{mut:next &C.vkw_list,prev &C.vkw_list}\nfn C.vinix_linuxkpi_bug(&char,i32)\nfn C.vinix_linuxkpi_may_sleep()bool\nfn C.vkp_current()voidptr\nfn C.vkp_spin_init(voidptr)\nfn C.vkp_spin_lock_irqsave(voidptr)u64\nfn C.vkp_spin_unlock_irqrestore(voidptr,u64)\nfn C.vkw_signal_state(u32,voidptr)bool\nfn C.vkw_current_state(u32)\nfn C.vkw_wake_task(voidptr)i32\nfn C.vkp_schedule()\n@[c:"__atomic_load_n"]fn C.vkw_load_owner(&i64,i32)i64\n@[c:"__atomic_store_n"]fn C.vkw_store_owner(&i64,i64,i32)\n@[c:"__atomic_load_n"]fn C.vkw_load_pointer(&voidptr,i32)voidptr\n@[c:"__atomic_store_n"]fn C.vkw_store_pointer(&voidptr,voidptr,i32)\n'
	bind += hosttest.v_function(os.read_file(p)!, 'is_null')! + hosttest.v_function(os.read_file(wait)!, 'wait_list_init')!
	for name in ['ww_list_empty', 'ww_list_add_tail', 'ww_list_del_init'] {
		bind += hosttest.v_function(os.read_file(ww)!, name)!
	}
	bind += '\n__global rsh_guard_anchor i32=-1\n'
	os.write_file(work + '/compatcore/bindings.v', bind)!
	atomic_path := root + '/kernel/linuxkpi/headercore/primitive.v'
	paths << atomic_path
	mut atomics := '@[translated]\nmodule headercore\n#include "linuxkpi_header_primitive_v_contract.h"\n@[typedef]struct C.vkh_const_char_p{}\n@[typedef]struct C.vhp_const_atomic64p{}\n@[typedef]struct C.vhp_s64{}\n@[typedef]struct C.atomic64_t{counter i64}\nfn C.memcpy(voidptr,voidptr,usize)voidptr\n@[c:"__atomic_load_n"]fn C.vhp_load64(&i64,i32)i64\n'
	for name in ['native64', 'atomic64_read'] {
		atomics += hosttest.v_function(os.read_file(atomic_path)!, name)!
	}
	atomics += '\n__global rsh_guard_anchor i32=-1\n'
	os.write_file(work + '/headercore/bindings.v', atomics)!
	for name in ['core.v', 'contract.h'] {
		os.cp(root + '/tests/linuxkpi/rwsemfixture/' + name, work + '/rwsemfixture/' + name)!
	}
	return paths
}

fn select_source(raw string, group string) !string {
	prefix := group + '__'
	mut bodies := []string{}
	for body in hosttest.c_bodies(raw) {
		line := body.all_before('\n')
		if ['vinit_caller', 'vcleanup_caller'].any(hosttest.named_body(body, prefix + it))
			|| (group != 'rwsemfixture' && hosttest.named_body(body, prefix + 'vcleanup')) {
			continue
		}
		if line.contains(prefix) || (group == 'compatcore' && line.contains(' vrs_')) || (group == 'headercore' && [
			' __init_rwsem(',
			' down_read(',
			' down_read_interruptible(',
			' down_read_killable(',
			' down_read_trylock(',
			' down_write(',
			' down_write_killable(',
			' down_write_trylock(',
			' up_read(',
			' up_write(',
			' downgrade_write(',
			' arch_atomic64_read(',
		].any(line.contains(it))) || (group == 'rwsemfixture' && (line.contains(' vkp_') || line.contains(' vkw_') || line.contains(' vinix_linuxkpi_') || line.contains(' kmalloc(') || line.contains(' kzalloc(') || line.contains(' main('))) {
			bodies << body
		}
	}
	if bodies.len == 0 { return error('No actual generated bodies ' + group) }
	mut metadata := []string{}
	mut arrays := []string{}
	mut globals := []string{}
	mut constants := []string{}
	for line in raw.split_into_lines() {
		if line.starts_with('typedef ') && line.contains(prefix) && !line.contains('(*_fn_ptr_') && !line.contains('Array_fixed_') && !line.contains('enum ') && line !in metadata {
			metadata << line
		}
		if line.starts_with('typedef ') && line.contains('(*_fn_ptr_') && line !in metadata {
			metadata << line
		}
		if line.starts_with('typedef ') && line.contains('Array_fixed_') && line !in arrays {
			arrays << line
		}
		if group == 'rwsemfixture' && line.starts_with('static const string _str_') {
			constants << line
		}
		if line.starts_with('#define ') && (line.contains(prefix) || line.starts_with('#define E_STRUCT ')) {
			constants << line
		}
		if line.ends_with(';') && !line.starts_with('}') && !line.starts_with('typedef ') && !line.starts_with('extern ') && !line.starts_with(' ') && !line.starts_with('\t') && !line.contains('(') && line.contains(prefix) {
			globals << line
		}
	}
	mut records := []string{}
	if group == 'compatcore' { records << hosttest.record(raw, 'compatcore__RwsemWaiter')! }
	if group == 'rwsemfixture' {
		start := 'typedef enum {'
		end := '} rwsemfixture__Operation;'
		if !raw.contains(start) || !raw.contains(end) { return error('Missing operation enum') }
		enum_prefix := raw.all_before(end)
		records << start + enum_prefix.all_after_last(start) + end
		for name in ['Context', 'Ledger', 'Actor'] {
			records << hosttest.record(raw, prefix + name)!
		}
	}
	mut strings := ''
	if group == 'rwsemfixture' {
		start := 'typedef struct {\n\tchar* str;'
		end := '} string;'
		if !raw.contains(start) || !raw.contains(end) {
			return error('Missing actual string metadata')
		}
		strings = start + raw.all_after(start).all_before(end) + end + '\n'
	}
	header := if group == 'compatcore' {
		'#include "linuxkpi_rwsem_v_primitives.h"\n#include "linuxkpi_v_primitives.h"\n'
	} else if group == 'headercore' {
		'#include "linuxkpi_rwsem_v_contract.h"\n#include "linuxkpi_header_primitive_v_contract.h"\n'
	} else {
		'#include "rwsemfixture/contract.h"\n'
	}
	decl := bodies.map(it.all_before('\n').all_before_last(' {') + ';')
	scalars := if group == 'compatcore' { 'typedef uint8_t u8;typedef uint32_t u32;\n' } else { '' }
	selected := '#include <stdint.h>\n#include <stdbool.h>\n#include <stddef.h>\n' + header + scalars + 'typedef uint64_t u64;typedef int32_t i32;typedef int64_t i64;typedef size_t usize;typedef void *voidptr;\n#define VNORETURN __attribute__((noreturn))\n' + strings + metadata.join('\n') + '\n' + records.join('\n') + '\n' + arrays.join('\n') + '\n' + globals.join('\n') + '\n' + constants.join('\n') + '\n' + decl.join('\n') + '\n' + bodies.join('\n\n') + '\n'
	if hosttest.c_bodies(selected) != bodies {
		return error('Selected generated body changed ' + group)
	}
	return selected
}

fn symbol(body string) string {
	return body.all_before('\n').all_before_last('(').all_after_last(' ').trim_left('*')
}

fn parity(group string, selected string, work string) !json2.Any {
	path := work + '/' + group + '-full-reference.c'
	generate(hosttest.root() + '/kernel/linuxkpi/' + group, path)!
	reference := hosttest.c_bodies(os.read_file(path)!)
	mut hashes := map[string]string{}
	for body in hosttest.c_bodies(selected) {
		name := symbol(body)
		if name == group + '__vinit' { continue }
		matches := reference.filter(hosttest.named_body(it, name))
		if matches.len != 1 || matches[0] != body {
			return error('Full production module parity failed ' + name)
		}
		hashes[name] = hosttest.text_sha(body)
	}
	return {
		'reference':        json2.Any(path)
		'reference_sha256': hosttest.sha(path)!
		'body_sha256':      hosttest.string_map(hashes)
	}
}

fn production_bodies(work string) !json2.Any {
	mut hashes := map[string]string{}
	for group in ['compatcore', 'headercore'] {
		for body in hosttest.c_bodies(os.read_file(work + '/' + group + '-selected.c')!) {
			for forbidden in ['memdup(', 'new_array', 'new_map', 'string__substr(',
				'box_to_interface', 'v_malloc(', '__eq_lhs', '__eq_rhs'] {
				if body.contains(forbidden) { return error('Implicit production allocation/copy: ' + forbidden) }
			}
			hashes[symbol(body)] = hosttest.text_sha(body)
		}
	}
	backend := os.read_file(work + '/compatcore-selected.c')!
	acquire := hosttest.extract_body(backend, 'compatcore__vrs_acquire')!
	wake := hosttest.extract_body(backend, 'compatcore__vrs_wake_locked')!
	if !acquire.contains('compatcore__RwsemWaiter waiter = (compatcore__RwsemWaiter)')
		|| !acquire.contains('&waiter.entry') || !wake.contains('struct vkw_list grants = (struct vkw_list){0}')
		|| !wake.contains('&grants') {
		return error('Missing genuine stack waiter/reader-phase list')
	}
	for name in ['rwsem_up_read', 'rwsem_up_write', 'rwsem_downgrade'] {
		body := hosttest.extract_body(backend, 'compatcore__' + name)!
		tail := body.all_after_last('vkp_spin_unlock_irqrestore(').all_after(');')
		if !body.contains('vkp_spin_unlock_irqrestore(') || tail.contains('sem') {
			return error('Post-unlock semaphore access in ' + name)
		}
	}
	// The writer branch returns immediately after waking; the reader loop
	// repeats from its independent stack list, never the just-woken record.
	if wake.count('vkw_wake_task(task);') != 2
		|| !wake.contains('vkw_wake_task(task);\n\t\t\treturn;')
		|| wake.all_after_last('vkw_wake_task(task);').contains('waiter') {
		return error('Changed post-wake waiter lifetime')
	}
	return {
		'body_sha256': json2.Any(hosttest.string_map(hashes))
		'stack_waiter': 'compatcore__vrs_acquire: automatic RwsemWaiter waiter; address passed to intrusive queue'
		'stack_grants': 'compatcore__vrs_wake_locked: automatic vkw_list grants; wakes consume detached nodes'
		'lifetime': 'Generated release bodies end after final unlock; writer wake returns immediately and reader wake tail never reads its waiter. O2 disassembly retained separately.'
	}
}

fn freestanding(work string, linux string, env map[string]string) ![]json2.Any {
	root := hosttest.root()
	mut proofs := []json2.Any{}
	for standard in ['gnu99', 'gnu11'] {
		for optimization in ['O0', 'O1', 'O2'] {
			mut pair := []json2.Any{}
			for group in ['compatcore', 'headercore'] {
				object := work + '/freestanding-' + standard + '-' + optimization + '-' + group + '.o'
				mut argv := hosttest.shell_split(hosttest.env_default('CC', 'clang'))!
				argv << ['--target=x86_64-unknown-none', '-std=' + standard, '-' + optimization,
					'-ffreestanding', '-fno-builtin', '-fwrapv', '-fno-strict-aliasing', '-fno-stack-protector',
					'-fstack-usage', '-nostdinc', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function',
					'-Wno-unused-parameter', '-Wno-sign-compare', '-Wno-typedef-redefinition',
					'-DVINIX_LINUXKPI', '-D__KERNEL__', '-include', 'linux/kconfig.h', '-include',
					linux + '/include/linux/compiler_types.h', '-isystem', root + '/kernel/freestnd-c-hdrs']
				for directory in [work + '/include', root + '/kernel/linuxkpi/include', root + '/kernel/c',
					linux + '/include', linux + '/include/uapi', linux + '/arch/x86/include', linux + '/arch/x86/include/uapi'] {
					argv << ['-I', directory]
				}
				if group == 'compatcore' { argv << '-DVINIX_V_RUNTIME' }
				compiled := compile_input(argv, work + '/' + group + '-selected.c', object, env)!
				imports := hosttest.command([hosttest.tool('llvm-nm'), '--undefined-only', object], object + '.imports.log', 30, env)!.stdout
				mut actual := imports.split_into_lines().filter(it.fields().len > 0).map(it.fields().last())
				mut expected := if group == 'compatcore' {
					['vinix_linuxkpi_bug', 'vinix_linuxkpi_may_sleep', 'vkp_current', 'vkp_schedule',
						'vkp_spin_init', 'vkp_spin_lock_irqsave', 'vkp_spin_unlock_irqrestore',
						'vkw_current_state', 'vkw_signal_state', 'vkw_wake_task']
				} else {
					['memcpy', 'vrs_down_read', 'vrs_down_write', 'vrs_downgrade', 'vrs_init',
						'vrs_try_read', 'vrs_try_write', 'vrs_up_read', 'vrs_up_write']
				}
				if group == 'compatcore' && optimization == 'O0' { expected << 'memset' }
				actual.sort()
				expected.sort()
				if actual != expected || hosttest.allocation_symbols(imports) {
					return error('Unexpected production freestanding imports: ' + imports)
				}
				usage := object[..object.len - 2] + '.su'
				stack := os.read_file(usage)!
				if !stack.contains('compatcore__vrs_acquire') && group == 'compatcore' {
					return error('Missing actual stack-usage record')
				}
				if stack.split_into_lines().any(it != '' && !it.ends_with('\tstatic')) {
					return error('Unbounded production stack frame: ' + usage)
				}
				assembly := object + '.disassembly.log'
				hosttest.command([hosttest.tool('llvm-objdump'), '-dr', '--no-show-raw-insn', object], assembly, 60, env)!
				pair << json2.Any({
					'module': json2.Any(group)
					'compiled': compiled
					'imports': hosttest.strings(actual)
					'stack_usage': usage
					'stack_usage_sha256': hosttest.sha(usage)!
					'disassembly': assembly
					'disassembly_sha256': hosttest.sha(assembly)!
				})
			}
			proofs << json2.Any({
				'standard': json2.Any(standard)
				'optimization': optimization
				'production_objects': pair
			})
		}
	}
	return proofs
}

fn flags(work string, linux string, standard string, optimization string) []string {
	root := hosttest.root()
	mut result := hosttest.shell_split(hosttest.env_default('CC', 'clang')) or { panic(err) }
	$if macos {
		result << ['-arch', 'x86_64']
	}
	result << ['-std=' + standard, '-' + optimization, '-g', '-ffreestanding', '-fno-builtin',
		'-fwrapv', '-fno-strict-aliasing', '-ffunction-sections', '-fdata-sections', '-Wall', '-Wextra',
		'-Werror', '-Wno-unused-function', '-Wno-unused-parameter', '-Wno-sign-compare',
		'-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-D_FORTIFY_SOURCE=0',
		'-DVINIX_LINUXKPI', '-DVINIX_LINUXKPI_HOST_TEST', '-D__KERNEL__', '-include',
		root + '/tests/linuxkpi/host_types.h', '-include', 'linux/kconfig.h', '-include',
		linux + '/include/linux/compiler_types.h']
	for directory in [work + '/include', work + '/stage', root + '/tests/linuxkpi/rwsemfixture',
		root + '/kernel/linuxkpi/include', linux + '/include', linux + '/include/uapi',
		linux + '/arch/x86/include', linux + '/arch/x86/include/uapi'] {
		result << ['-I', directory]
	}
	result << ['-iquote', root + '/kernel/c']
	return result
}

fn tool_provenance(work string, env map[string]string) ![]json2.Any {
	mut requests := map[string][]string{
		'cc': hosttest.shell_split(hosttest.env_default('CC', 'clang'))!
		'nm': [hosttest.tool('llvm-nm')]
		'objdump': [hosttest.tool('llvm-objdump')]
	}
	for name in ['V', 'VEXE'] {
		if path := env[name] {
			if path != '' { requests[name] = [path] }
		}
	}
	mut proofs := []json2.Any{}
	for name, argv in requests {
		if argv.len == 0 { return error('Empty tool command: ' + name) }
		resolved := os.find_abs_path_of_executable(argv[0])!
		version := if name in ['V', 'VEXE'] { 'version' } else { '--version' }
		log := work + '/tool-' + name + '.log'
		result := hosttest.command([...argv, version], log, 30, env)!
		proofs << json2.Any({
			'name': json2.Any(name)
			'argv': hosttest.strings([...argv, version])
			'executable': resolved
			'executable_sha256': hosttest.sha(resolved)!
			'version': result.stdout + result.stderr
			'log': log
		})
	}
	return proofs
}

fn run(keep string) ! {
	root := hosttest.root()
	linux := hosttest.env_default('LINUXKPI_SOURCE_DIR', root + '/third_party/linux-i915/linux-6.6.157')
	hosttest.verify_upstream(linux, hosttest.upstream_pin()!)!
	work := hosttest.work_dir(keep, 'vinix-rwsem-')!
	defer { if keep == '' { hosttest.remove_work_dir(work) or { eprintln(err) } } }
	// Keep producer scratch private and preserve its exact inputs on every
	// generation, including failures. This is isolation, not a retry policy.
	previous_temp := os.getenv_opt('TMPDIR')
	os.mkdir(work + '/descriptive-generation-scratch')!
	os.setenv('TMPDIR', work + '/descriptive-generation-scratch', true)
	defer {
		if previous := previous_temp { os.setenv('TMPDIR', previous, true) }
		else { os.unsetenv('TMPDIR') }
	}
	mut inputs := stage(work + '/stage')!
	inputs << [@FILE, root + '/tests/linuxkpi/rwsemfixture/README.md']
	inputs << os.walk_ext(root + '/tests/linuxkpi/rwsemfixture', '.v')
	inputs << os.walk_ext(root + '/tests/linuxkpi/rwsemfixture', '.h')
	inputs << os.walk_ext(root + '/tests/linuxkpi/hosttest', '.v')
	inputs << os.walk_ext(root + '/kernel/linuxkpi/compatcore', '.v')
	inputs << os.walk_ext(root + '/kernel/linuxkpi/headercore', '.v')
	inputs << os.walk_ext(root + '/kernel/linuxkpi/include', '.h')
	inputs << os.walk_ext(root + '/kernel/c', '.h')
	inputs << root + '/build-support/find-v.sh'
	for schema in ['atomic-exchange', 'overflow', 'spinlock'] {
		inputs << root + '/kernel/linuxkpi/abi/' + schema + '.json'
	}
	before := hosttest.hashes(inputs)!
	mut env := os.environ()
	env['VCACHE'] = work + '/vcache'
	env['V3CACHE'] = work + '/v3cache'
	env['VTMP'] = work + '/vtmp'
	env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	env['ASAN_OPTIONS'] = 'detect_stack_use_after_return=1:abort_on_error=1'
	env['UBSAN_OPTIONS'] = 'halt_on_error=1'
	tools := tool_provenance(work, env)!
	for schema, name in {
		'atomic-exchange': 'atomic_exchange'
		'overflow':        'integer_policy'
		'spinlock':        'spinlock_adapters'
	} {
		hosttest.generate_abi(root + '/kernel/linuxkpi/abi/' + schema + '.json', root + '/kernel/linuxkpi', work + '/include/vinix/' + name + '.h')!
	}
	mut proofs := []json2.Any{}
	for group in ['compatcore', 'headercore', 'rwsemfixture'] {
		rawpath := work + '/' + group + '-actual.c'
		generate(work + '/stage/' + group, rawpath)!
		selected := select_source(os.read_file(rawpath)!, group)!
		path := work + '/' + group + '-selected.c'
		os.write_file(path, selected)!
		mut proof := map[string]json2.Any{
			'module':          json2.Any(group)
			'raw_sha256':      hosttest.sha(rawpath)!
			'selected_sha256': hosttest.sha(path)!
			'body_count':      hosttest.c_bodies(selected).len
		}
		if group != 'rwsemfixture' { proof['full_module_parity'] = parity(group, selected, work)! }
		proofs << json2.Any(proof)
	}
	mut generation_controls := []json2.Any{}
	fixture := os.read_file(work + '/rwsemfixture-selected.c')!
	for attempt in 1 .. 4 {
		path := work + '/rwsemfixture-repeated-' + attempt.str() + '.c'
		generate(work + '/stage/rwsemfixture', path)!
		if select_source(os.read_file(path)!, 'rwsemfixture')! != fixture {
			return error('Repeated generation changed actual fixture bodies')
		}
		generation_controls << json2.Any({
			'attempt': json2.Any(attempt)
			'raw': path
			'raw_sha256': hosttest.sha(path)!
			'unchanged_selection_sha256': hosttest.text_sha(fixture)
		})
	}
	body_proof := production_bodies(work)!
	production_objects := freestanding(work, linux, env)!
	mut runs := []json2.Any{}
	mut objects := []json2.Any{}
	for standard in ['gnu99', 'gnu11'] {
		for optimization in ['O0', 'O1', 'O2'] {
			tag := standard + '-' + optimization
			base := flags(work, linux, standard, optimization)
			mut linked := []string{}
			for group in ['compatcore', 'headercore', 'rwsemfixture'] {
				object := work + '/' + tag + '-' + group + '.o'
				mut argv := base.clone()
				if group == 'compatcore' { argv << '-DVINIX_V_RUNTIME' }
				proof := compile_input(argv, work + '/' + group + '-selected.c', object, env)!
				objects << proof
				imports := hosttest.command([hosttest.tool('llvm-nm'), '-u', object], object + '.imports.log', 30, env)!.stdout
				if group != 'rwsemfixture' && hosttest.allocation_symbols(imports) {
					return error('Production imports allocator ' + imports)
				}
				linked << object
			}
			exe := work + '/' + tag
			strip := $if macos { '-Wl,-dead_strip' } $else { '-Wl,--gc-sections' }
			hosttest.command([...base, ...linked, strip, '-pthread', '-o', exe], exe + '.link.log', 180, env)!
			passed := hosttest.command([exe, '0'], exe + '.safe.log', 240, env)!
			if passed.stderr != '' || !passed.stdout.contains('PASS: original rwsem') || !passed.stdout.contains('scenarios=11') || !passed.stdout.contains('allocations=0') {
				return error('Missing clean rwsem verdict ' + exe)
			}
			negative_log := exe + '.postunlock-negative.log'
			negative := hosttest.capture([exe, '1'], negative_log, 30, env)!
			if negative.code == 0 || !negative.stderr.contains('ERROR: AddressSanitizer: heap-use-after-free') {
				return error('Sanitizer missed explicit post-unlock freed-container read: ' + negative_log)
			}
			mut failures := []json2.Any{}
			for mode in 10 .. 25 {
				log := exe + '-fatal-' + mode.str() + '.log'
				failed := hosttest.capture([exe, mode.str()], log, 30, env)!
				diagnostic := failed.stdout + failed.stderr
				if failed.code != 85 || !diagnostic.contains('RWSEM invariant') || !diagnostic.contains('RWSEM fatal preserved semaphore') || diagnostic.contains('ERROR: AddressSanitizer') || diagnostic.contains('runtime error:') {
					return error('Invalid fatal control ' + log)
				}
				failures << json2.Any({
					'mode':      json2.Any(mode)
					'exit_code': failed.code
					'log':       log
					'log_sha256': hosttest.sha(log)!
				})
			}
			runs << json2.Any({
				'standard':          json2.Any(standard)
				'optimization':      optimization
				'executable':        exe
				'executable_sha256': hosttest.sha(exe)!
				'safe_exit_code': passed.code
				'output':            passed.stdout
				'safe_log_sha256':   hosttest.sha(exe + '.safe.log')!
				'postunlock_negative_exit_code': negative.code
				'postunlock_negative_log': negative_log
				'postunlock_negative_sha256': hosttest.sha(negative_log)!
				'fatal_controls':    failures
			})
			println(tag + ': ' + passed.stdout.trim_space())
		}
	}
	if before != hosttest.hashes(before.keys())! {
		return error('Sources changed during rwsem checks')
	}
	artifacts := hosttest.hashes(os.walk_ext(work, ''))!
	hosttest.write_json(work + '/result.json', {
		'scope':                        json2.Any(scope)
		'source_sha256':                hosttest.string_map(before)
		'tools':                        tools
		'artifact_sha256':              hosttest.string_map(artifacts)
		'actual_generated_body_proofs': proofs
		'repeated_fixture_generation_controls': generation_controls
		'production_body_lifetimes': body_proof
		'freestanding_production_matrix': production_objects
		'objects':                      objects
		'runs':                         runs
	})!
}

fn main() {
	keep := hosttest.parse_keep_dir(os.args[1..], 'Usage: rwsem.v [--keep-dir NEW]', scope) or {
		eprintln(err)
		exit(2)
	}
	run(keep) or {
		eprintln(err)
		exit(1)
	}
}
