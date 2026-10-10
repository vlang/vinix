// SPDX-License-Identifier: GPL-2.0-or-later
module boundarycheck

import hosttest
import os

const original = '8f7239d1fd4c593746279699f6ff25df5f4dd7bd'

// Darwin's assembler does not accept the ELF-only directives in this source.
// Keep the rest, including blank lines and the final newline, byte-for-byte.
pub fn darwin_assembly(source string) string {
	mut result := ''
	lines := source.split('\n')
	for index, line in lines {
		terminated := index + 1 < lines.len
		if terminated && (line.starts_with('.type ') || line.starts_with('.size ') || line.starts_with('.section .note')) {
			continue
		}
		result += line
		if terminated { result += '\n' }
	}
	return result.replace('read_current_sp', '_read_current_sp')
}

fn checked(argv []string, env map[string]string) !hosttest.Result {
	result := hosttest.capture(argv, '', -1, env)!
	if result.code != 0 {
		return error('Command failed (${result.code}): ${hosttest.shell_join(argv)}\n' + result.stdout + result.stderr)
	}
	return result
}

fn compile(flags []string, command_parts []string, env map[string]string) ! {
	mut argv := flags.clone()
	argv << command_parts
	checked(argv, env)!
}

fn generate(source string, output string) ! {
	result := hosttest.generate_module_capture(source, output, 'arm64', []string{})!
	eprint(result.stdout)
	eprint(result.stderr)
}

fn text_output(raw string) !string {
	hosttest.module_decode_utf8(raw)!
	return raw.replace('\r\n', '\n').replace('\r', '\n')
}

pub fn compare(root string, machine string, env map[string]string) !string {
	if machine !in ['arm64', 'aarch64'] {
		return error('This differential boundary fixture requires an ARM64 host')
	}
	work := hosttest.work_dir('', 'vinix-native-boundaries-')!
	defer { hosttest.remove_work_dir(work) or { eprintln(err) } }
	flags := [env['CC'] or { 'clang' }, '-O2', '-g', '-Wall', '-Wextra', '-Werror',
		'-Wno-unused-function', '-Wno-unused-parameter', '-ffreestanding', '-fno-builtin',
		'-fno-strict-aliasing', '-fsanitize=address,undefined', '-fno-omit-frame-pointer']
	mut results := []hosttest.Result{}
	for label in ['original', 'v'] {
		test := os.join_path(work, label)
		os.mkdir(test)!
		source := os.join_path(test, 'uart')
		hosttest.module_copy_tree(os.join_path(root, 'tests/native-boundaries/uart'), source)!
		for header in ['symbols.h', 'apple_smc.h'] {
			target := os.join_path(test, header)
			if label == 'original' {
				data := checked(['git', '-C', root, 'show', original + ':kernel/c/' + header], env)!.stdout
				os.write_file(target, data)!
			} else {
				hosttest.module_copy_file(os.join_path(root, 'kernel/c', header), target)!
			}
		}
		mut objects := []string{}
		if label == 'v' {
			hosttest.module_copy_file(os.join_path(root, 'kernel/aarch64/uart/trace_arm64.v'), os.join_path(source, 'trace.v'))!
			for name, production in {
				'lib': 'kernel/lib/callback_abi.v'
				'smc': 'kernel/apple/smc/counter_arm64.v'
			} {
				native := os.join_path(test, name)
				os.mkdir(native)!
				hosttest.module_copy_file(os.join_path(root, production), os.join_path(native, 'core.v'))!
				generated := os.join_path(test, name + '.c')
				generate(native, generated)!
				obj := os.join_path(test, name + '.o')
				compile(flags, ['-c', generated, '-o', obj], env)!
				imports := text_output(checked(['nm', '-u', obj], env)!.stdout)!
				if hosttest.allocation_symbols(imports) {
					return error('native boundary allocator import: ' + imports)
				}
				objects << obj
			}
			assembly := hosttest.module_read_text(os.join_path(root, 'kernel/asm/aarch64/stack_pointer.S'))!
			native_sp := os.join_path(test, 'stack_pointer.S')
			os.write_file(native_sp, darwin_assembly(assembly))!
			obj := os.join_path(test, 'stack_pointer.o')
			compile(flags, ['-c', native_sp, '-o', obj], env)!
			objects << obj
		}
		generated := os.join_path(test, 'fixture.c')
		generate(source, generated)!
		binary := os.join_path(test, 'fixture')
		mut command_parts := ['-I', test, generated]
		command_parts << objects
		command_parts << ['-o', binary]
		compile(flags, command_parts, env)!
		mut fixture_env := env.clone()
		fixture_env['ASAN_OPTIONS'] = 'detect_stack_use_after_return=1'
		result := hosttest.capture([binary], '', -1, fixture_env)!
		stdout := text_output(result.stdout)!
		stderr := text_output(result.stderr)!
		if result.code != 0 {
			return error(label + ' fixture failed: ' + stdout + stderr)
		}
		results << hosttest.Result{stdout, stderr, result.code}
	}
	if results[0].stdout != results[1].stdout || results[0].stderr != results[1].stderr {
		return error('native boundary differential output mismatch:\noriginal stdout:\n' +
			results[0].stdout + '\noriginal stderr:\n' + results[0].stderr +
			'\nV stdout:\n' + results[1].stdout + '\nV stderr:\n' + results[1].stderr)
	}
	return results[1].stdout + 'Frozen C / production V ASan/UBSan and stack-use-after-return: PASS\n'
}
