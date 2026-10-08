// SPDX-License-Identifier: GPL-2.0-or-later
// Pinned static-key declarations and existing boolean branch compiler/runtime fixtures.
module main

import os
import json2
import hosttest
import typefixture

fn require(condition bool, message string) ! {
	if !condition { return error(message) }
}

fn tool(name string) !string {
	path := hosttest.tool(name)
	if !os.is_file(path) { return error('Missing object inspection tool: ' + name) }
	return path
}

fn execute(argv []string, log string) !hosttest.Result {
	result := hosttest.capture(argv, '', -1, os.environ())!
	os.write_file(log, result.stdout + result.stderr)!
	require(result.code == 0, 'Command failed: ' + argv.join(' ') + '\n' + result.stderr)!
	return result
}

fn inspect(argv []string) !string {
	result := hosttest.capture(argv, '', -1, os.environ())!
	require(result.code == 0, result.stderr)!
	return result.stdout
}

fn macro(text string, name string) !string {
	lines := text.split_into_lines()
	prefix := '#define ' + name + '(name)'
	for index, line in lines {
		if !line.starts_with(prefix) { continue }
		mut body := line[prefix.len..]
		mut next := index + 1
		for body.trim_right(' \t\r\n\v\f').ends_with('\\') {
			if next >= lines.len { return error('Truncated declaration macro: ' + name) }
			body = body.trim_right(' \t\r\n\v\f').all_before_last('\\') + ' ' + lines[next]
			next++
		}
		return body.fields().join(' ')
	}
	return error('Missing declaration macro: ' + name)
}

fn symbols(output string) []string {
	mut names := []string{}
	for line in output.split_into_lines() {
		words := line.fields()
		if words.len > 0 && words.last() !in names { names << words.last() }
	}
	names.sort()
	return names
}

fn run_profile(keep string) ! {
	root := hosttest.root()
	here := hosttest.upstream_here()
	pin := hosttest.upstream_pin()!
	linux := hosttest.resolve_path(hosttest.env_default('LINUXKPI_SOURCE_DIR', os.join_path(hosttest.upstream_default(), 'linux-' + pin['version']!.str())))!
	hosttest.verify_upstream(linux, pin)!
	original := os.join_path(linux, 'include/linux/jump_label.h')
	header := os.join_path(here, 'include/linux/jump_label.h')
	expected := {
		'DECLARE_STATIC_KEY_FALSE': 'extern struct static_key_false name'
		'DECLARE_STATIC_KEY_TRUE':  'extern struct static_key_true name'
	}
	for name, declaration in expected {
		require(macro(os.read_file(original)!, name)! == declaration && macro(os.read_file(header)!, name)! == declaration, 'Declaration differs from the pinned compiler contract: ' + name)!
	}
	compiler := hosttest.shell_split(hosttest.env_default('CC', 'clang'))!
	work := hosttest.work_dir(keep, 'vinix-static-key-declaration-')!
	defer { if keep == '' { os.rmdir_all(work) or { eprintln(err) } } }
	include := os.join_path(work, 'include')
	hosttest.audit_headers(include)!
	for name, code in {
		'declarations': typefixture.declarations
		'definitions':  typefixture.definitions
		'consumer':     typefixture.consumer
		'runner':       typefixture.runner
	} { os.write_file(os.join_path(work, name + '.c'), code)! }
	mut common := ['-O2', '-ffreestanding', '-fwrapv', '-nostdinc', '-fno-common', '-Wall',
		'-Wextra', '-Werror', '-Wno-unused-parameter', '-Wno-unused-function', '-D__KERNEL__',
		'-include', 'linux/kconfig.h', '-include', os.join_path(linux, 'include/linux/compiler_types.h'),
		'-isystem', os.join_path(root, 'kernel/freestnd-c-hdrs')]
	for path in [include, os.join_path(here, 'include'), os.join_path(root, 'kernel/c'),
		os.join_path(linux, 'include'), os.join_path(linux, 'include/uapi'),
		os.join_path(linux, 'arch/x86/include'), os.join_path(linux, 'arch/x86/include/uapi')] {
		common << ['-I', path]
	}
	mut results := []json2.Any{}
	for standard in ['gnu99', 'gnu11'] {
		flags := [...common, '-std=' + standard]
		native := ['--target=x86_64-unknown-none', '-mno-red-zone', '-mcmodel=kernel', '-fno-PIC']
		mut objects := map[string]string{}
		mut commands := []json2.Any{}
		for name in ['declarations', 'definitions', 'consumer'] {
			obj := os.join_path(work, standard + '-' + name + '.o')
			argv := [...compiler, ...native, ...flags, '-c', os.join_path(work, name + '.c'), '-o', obj]
			execute(argv, os.join_path(work, standard + '-' + name + '-compile.log'))!
			objects[name] = obj
			commands << json2.Any(hosttest.strings(argv))
		}
		declarations := inspect([tool('llvm-nm')!, objects['declarations']])!
		require(declarations.trim_space() == '', 'Declarations emitted storage or imports:\n' + declarations)!
		imports := inspect([tool('llvm-nm')!, '-u', objects['consumer']])!
		require(symbols(imports) == ['declared_false', 'declared_true'], 'Consumer did not import only its real extern keys:\n' + imports)!
		defined := inspect([tool('llvm-nm')!, '--defined-only', '-S', objects['definitions']])!
		mut records := map[string][]string{}
		for line in defined.split_into_lines() {
			words := line.fields()
			if words.len >= 3 { records[words.last()] = words[1..3].clone() }
		}
		require(records == {
			'declared_false': ['0000000000000004', 'B']
			'declared_true':  ['0000000000000004', 'D']
		}, 'Definitions changed type/storage/layout:\n' + defined)!
		combined := os.join_path(work, standard + '-combined.o')
		execute([tool('ld.lld')!, '-r', objects['definitions'], objects['consumer'], '-o', combined], os.join_path(work, standard + '-link.log'))!
		closed := inspect([tool('llvm-nm')!, '-u', combined])!
		require(closed.trim_space() == '', 'Boolean branches require an unexpected runtime:\n' + closed)!
		for kind in ['false', 'true'] {
			opposite := if kind == 'false' { 'true' } else { 'false' }
			invalid := os.join_path(work, standard + '-wrong-' + kind + '.c')
			os.write_file(invalid, '#include <linux/jump_label.h>\nDECLARE_STATIC_KEY_' + kind.to_upper() + '(wrong_type);\nDEFINE_STATIC_KEY_' + opposite.to_upper() + '(wrong_type);\n')!
			rejected := hosttest.capture([...compiler, ...native, ...flags, '-fsyntax-only', invalid], '', -1, os.environ())!
			os.write_file(os.join_path(work, standard + '-wrong-' + kind + '.log'), rejected.stderr)!
			require(rejected.code != 0 && rejected.stderr.contains('different type'), 'Wrong declaration type was not rejected:\n' + rejected.stderr)!
		}
		executable := os.join_path(work, standard + '-runtime')
		argv := [...compiler, ...flags, '-O1', '-g', '-fsanitize=address,undefined', '-fno-omit-frame-pointer',
			os.join_path(work, 'definitions.c'), os.join_path(work, 'consumer.c'), os.join_path(work, 'runner.c'), '-o', executable]
		execute(argv, os.join_path(work, standard + '-runtime-compile.log'))!
		mut environment := os.environ()
		environment['UBSAN_OPTIONS'] = 'halt_on_error=1'
		environment['ASAN_OPTIONS'] = 'detect_stack_use_after_return=1'
		runtime := hosttest.capture([executable], '', 30, environment)!
		os.write_file(os.join_path(work, standard + '-run.log'), runtime.stdout + runtime.stderr)!
		require(runtime.code == 0 && runtime.stderr == '', 'Existing boolean branch execution failed:\n' + runtime.stderr)!
		mut object_hashes := map[string]string{}
		for name, path in objects { object_hashes[name] = hosttest.file_digest(path)! }
		results << json2.Any(map[string]json2.Any{
			'standard':                           json2.Any(standard)
			'native_compile_commands':            commands
			'declaration_symbols':                declarations
			'consumer_imports':                   imports
			'definition_symbols':                 defined
			'combined_imports':                   closed
			'object_sha256':                      hosttest.string_map(object_hashes)
			'runtime_compile_command':            hosttest.strings(argv)
			'runtime_exit':                       runtime.code
			'wrong_wrapper_definitions_rejected': 2
		})
		println(standard + ': typed extern declarations, storage/link closure and 4001 boolean branch checks passed')
	}
	mut input_hashes := map[string]string{}
	for path in ['include/generated/autoconf.h', 'include/linux/types.h', 'include/asm/atomic.h'] {
		file := os.join_path(here, path)
		input_hashes[os.path_rel(root, file)!] = hosttest.file_digest(file)!
	}
	mut adapters := map[string]string{}
	for path in os.walk_ext(include, '.h') { adapters[os.path_rel(include, path)!] = hosttest.file_digest(path)! }
	hosttest.write_json(os.join_path(work, 'result.json'), map[string]json2.Any{
		'scope':                  json2.Any('Two pinned compiler declaration macros and existing boolean API only; no text-patching, static-key refcounting, allocation or GPU runtime is added.')
		'header_sha256':          hosttest.file_digest(header)!
		'test_sha256':            hosttest.file_digest(@FILE)!
		'pinned_header_sha256':   hosttest.file_digest(original)!
		'pinned_macros':          hosttest.string_map(expected)
		'profile_input_sha256':   hosttest.string_map(input_hashes)
		'compiler_adapters':      hosttest.string_map(adapters)
		'results':                results
	})!
}

fn main() {
	keep := hosttest.parse_keep_dir(os.args[1..], 'Usage: static_key_declarations.v [--keep-dir DIRECTORY]', scope) or { eprintln(err.msg()); exit(2) }
	run_profile(keep) or { eprintln(err.msg()); exit(1) }
}

const scope = 'Check pinned static-key declarations against the real compiler profile. Declaration-only objects own no storage or imports. Separate definitions and consumers prove the existing boolean branch API without replacing its atomics.'
