// SPDX-License-Identifier: GPL-2.0-or-later
module compathost

import hosttest
import json2
import os
import policyhost

struct SecurityBuild {
	work string
mut:
	commands []json2.Any
}

fn (mut build SecurityBuild) invoke(command []string) ! {
	build.commands << hosttest.strings(command)
	write(build.work + '/commands.json', json2.encode(json2.Any(build.commands)) + '\n')!
	run(command)!
}

fn audit_fixture_allocator(imports string) bool {
	for line in imports.split_into_lines() {
		for word in line.fields() {
			name := word.trim_left('_')
			if name in ['malloc', 'calloc', 'realloc', 'memdup'] || name.starts_with('new_array') || name.starts_with('array_new') {
				return true
			}
		}
	}
	return false
}

fn security_host(args []string, tool string) !int {
	parsed := hosttest.parse_arguments(args, [
		hosttest.Option{ name: '--source', value: true },
		hosttest.Option{ name: '--keep-dir', value: true },
		hosttest.Option{ name: '--arch', value: true, choices: ['arm64', 'aarch64', 'x86_64', 'amd64'] },
	], 0,
		'Usage: host-test [--source ORIGINAL-C] [--keep-dir FRESH-DIR] [--arch arm64|x86_64]',
		'Exercise the production security core and independent native caller under ASan/UBSan.') or { return error_with_code(err.msg(), 2) }
	selected := if '--arch' in parsed.options {
		parsed.options['--arch']
	} else {
		policyhost.caller_arch()
	}
	v_arch := if selected in ['arm64', 'aarch64'] { 'arm64' } else { 'amd64' }
	arch := if v_arch == 'arm64' { 'arm64' } else { 'x86_64' }
	mut arch_flags := []string{}
	$if macos {
		arch_flags = ['-arch', arch]
	} $else {
		if v_arch != policyhost.caller_arch() {
			return error('Requested host architecture requires a native runner')
		}
	}
	work := hosttest.work_dir(parsed.options['--keep-dir'], 'vinix-' + tool + '-host-')!
	defer { if '--keep-dir' !in parsed.options { retire(work) } }
	mut build := SecurityBuild{ work: work }
	mut defines := ['-d', 'security_no_main']
	if tool != 'audit' { defines << ['-d', 'security_fixture'] }
	build.invoke([root() + '/build-support/security-tools/compile-v-core', tool, work + '/core.c',
		'--arch', v_arch, ...defines])!
	cc := compiler_prefix('CC', 'cc')!
	common := [...cc, ...arch_flags, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror',
		'-fsanitize=address,undefined']
	tool_directory := root() + match tool {
		'mac' { '/tools/security-mac' }
		'sandbox' { '/tools/sandbox' }
		else { '/tools/security-audit' }
	}
	mut core_flags := [...common, '-D_GNU_SOURCE', '-DVINIX_V_RUNTIME']
	if tool != 'audit' { core_flags << '-DVINIX_SECURITY_FIXTURE' }
	if tool == 'mac' {
		core_flags << ['-Dprctl=mock_prctl', '-Dlsetxattr=mock_lsetxattr', '-Dexecvp=mock_execvp']
	}
	build.invoke([...core_flags, '-I', tool_directory, '-c', work + '/core.c', '-o', work + '/core.o'])!
	fixture_directory := root() + match tool {
		'mac' { '/tests/security-mac/clifixture' }
		'sandbox' { '/tests/application-sandbox/hostfixture' }
		else { '/tests/security-audit/collectorhostfixture' }
	}
	control := if '--source' in parsed.options { resolve(parsed.options['--source'])! } else { '' }
	fixture := if control == '' { work + '/fixture.c' } else { control }
	mut objects := [work + '/fixture.o', work + '/core.o']
	if control != '' {
		if !os.is_file(control) { return error('Control source is not a file') }
		build.invoke([...common,
			...if tool == 'sandbox' {
				['-I', root() + '/tests/application-sandbox']
			} else {
				[]string{}
			}, '-c', fixture, '-o', work + '/fixture.o'])!
	} else {
		build.invoke([root() + '/build-support/compile-v-module', fixture_directory, fixture, '--arch',
			v_arch, '-d', 'nofloat'])!
		mut fixture_flags := [...common, '-Wno-unused-function', '-Wno-unused-parameter', '-fPIC',
			'-I', fixture_directory]
		if tool != 'audit' { fixture_flags << ['-I', tool_directory] }
		build.invoke([...fixture_flags, '-c', fixture, '-o', work + '/fixture.o'])!
		if tool == 'mac' {
			assembly := fixture_directory + if v_arch == 'arm64' {
				'/variadic-arm.S'
			} else {
				'/variadic-x86.S'
			}
			build.invoke([...cc, ...arch_flags, '-c', assembly, '-o', work + '/variadic.o'])!
			objects << work + '/variadic.o'
		} else if tool == 'audit' {
			imports := output(['nm', '-u', work + '/fixture.o'])!
			write(work + '/fixture-imports.txt', imports)!
			if audit_fixture_allocator(imports) {
				return error('Implicit audit fixture allocator import:\n' + imports)
			}
		}
	}
	build.invoke([...common, ...objects, '-o', work + '/host'])!
	if tool == 'audit' {
		build.invoke([root() + '/build-support/security-tools/compile-v-core', tool,
			work + '/collector.c', '--arch', v_arch])!
		build.invoke([...common, '-D_GNU_SOURCE', '-DVINIX_V_RUNTIME', '-I', tool_directory,
			work + '/collector.c', '-o', work + '/collector'])!
	}
	front := root() + match tool {
		'mac' { '/tests/security-mac/host-run.sh' }
		'sandbox' { '/tests/application-sandbox/test-host.sh' }
		else { '/tests/security-audit/collector-run.sh' }
	}
	mut paths := [front, tool_directory + '/core/core.v', tool_directory + '/core/native.v',
		root() + '/build-support/find-v.sh', root() + '/build-support/compile-v-module',
		root() + '/tests/linuxkpi/generate_module.v',
		root() + '/build-support/security-tools/compile-v-core',
		root() + '/build-support/native-compat-tools/compathost/project.v',
		root() + '/build-support/native-compat-tools/compathost/security_host.v', work + '/core.c',
		fixture, ...objects, work + '/host']
	paths << tool_directory + match tool {
		'mac' { '/mac.h' }
		'sandbox' { '/sandbox_v.h' }
		else { '/collector_v.h' }
	}
	if tool == 'mac' { paths << tool_directory + '/mac_v.h' }
	if tool == 'audit' { paths << [work + '/collector.c', work + '/collector'] }
	if control == '' {
		mut names := os.ls(fixture_directory)!
		names.sort()
		for name in names {
			if os.is_file(fixture_directory + '/' + name) {
				paths << fixture_directory + '/' + name
			}
		}
	}
	mut inputs := map[string]json2.Any{}
	for path in paths {
		inputs[path] = json2.Any({
			'bytes':  json2.Any(os.file_size(path))
			'sha256': json2.Any(hosttest.sha(path)!)
		})
	}
	v := output(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'find-v', root()])!
	mut env := policyhost.environment()
	env['ASAN_OPTIONS'] = os.getenv_opt('ASAN_OPTIONS') or { 'detect_leaks=0:halt_on_error=1' }
	env['UBSAN_OPTIONS'] = os.getenv_opt('UBSAN_OPTIONS') or { 'halt_on_error=1' }
	mut record := {
		'fixture':       json2.Any(if control == '' { 'maintained-V' } else { 'original-C' })
		'host':          json2.Any(output(['uname', '-m'])!.trim_space())
		'target_arch':   json2.Any(arch)
		'v_version':     json2.Any(output([v, 'version'])!.trim_space())
		'cc_version':    json2.Any(output([...cc, '--version'])!.split_into_lines()[0])
		'sanitizers':    json2.Any(hosttest.strings(['address', 'undefined']))
		'asan_options':  json2.Any(env['ASAN_OPTIONS'])
		'ubsan_options': json2.Any(env['UBSAN_OPTIONS'])
		'inputs':        json2.Any(inputs)
	}
	if tool == 'mac' {
		record['native_entry'] = if control == '' {
			'instruction-only variadic transport; not sanitizer instrumented'
		} else {
			'original va_list'
		}
	}
	if tool == 'audit' {
		record['native_entry'] = if control == '' {
			'exported native fixture main; sanitizer instrumented'
		} else {
			'original fixed-argument fixture main'
		}
	}
	hosttest.write_json(work + '/inputs.json', record)!
	result := hosttest.capture([work + '/host'], '', -1, env)!
	write(work + '/host.log', result.stdout)!
	write(work + '/failures.log', result.stderr)!
	print(result.stdout)
	eprint(result.stderr)
	if result.code != 0 { return result.code }
	if tool == 'audit' && os.getuid() != 0 {
		denied := hosttest.capture([work + '/collector', '--once'], '', -1, env)!
		write(work + '/output', denied.stdout + denied.stderr)!
		if denied.code == 0 || !(denied.stdout + denied.stderr).contains('root required') {
			return error('Non-root audit collector contract failed')
		}
	}
	return 0
}
