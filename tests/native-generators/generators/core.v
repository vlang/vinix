// SPDX-License-Identifier: GPL-2.0-or-later
module generators

import cachecli
import crypto.sha256
import hosttest
import json2
import os
import sourcecommand

pub fn root() string { return hosttest.root() }

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn absolute(path string) !string {
	return hosttest.module_resolve(if path == '' { '.' } else { path })!
}

fn captured(argv []string, _log string, timeout int, env map[string]string) !hosttest.Result {
	cachecli.checkpoint()!
	result := sourcecommand.capture(argv, env, f64(timeout), 64 * 1024 * 1024, cachecli.cancelled)!
	cachecli.checkpoint()!
	return hosttest.Result{result.stdout, result.stderr, result.status}
}

fn checked(argv []string) !hosttest.Result {
	mut env := os.environ()
	env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	result := captured(argv, '', -1, env)!
	if result.code != 0 { return hosttest.ModuleCommandError{argv, result} }
	return result
}

fn compiler() !string {
	return checked(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'find-v', root()])!.stdout
}

fn show(result hosttest.Result) {
	print(result.stdout)
	eprint(result.stderr)
}

fn report_failure(failure IError) {
	if failure is hosttest.ModuleCommandError {
		show(failure.result)
		eprintln('native compiler command failed')
	} else {
		eprintln(failure.msg())
	}
}

pub fn generate_module(source string, output string, arch string, defines []string) ! {
	show(hosttest.generate_module_with_capture(source, output, arch, defines, captured)!)
}

// Keep the original independent fixture's linker arguments out of its object
// compilation. The two warning exceptions apply only to compiler output.
pub fn fixture_compile_flags(flags []string) []string {
	return flags.filter(it !in ['-static', '-nostdlib', '-pie']
		&& !it.starts_with('-L') && !it.starts_with('-l') && !it.starts_with('-Wl,') && !it.starts_with('-fuse-ld='))
}

pub fn compile_fixture(source string, output string, arch string, flags []string) !string {
	generated := hosttest.replace_suffix(output, '.c')
	generate_module(absolute(source)!, absolute(generated)!, if arch == 'aarch64' {
		'arm64'
	} else {
		'amd64'
	}, ['nofloat'])!
	mut command := fixture_compile_flags(flags)
	command << ['-Wno-unused-function', '-Wno-unused-parameter', '-fPIC', '-I', absolute(source)!,
		'-c', generated, '-o', output]
	show(checked(command)!)
	return output
}

fn project(kind string, output string, arch string, host_clock bool) ! {
	selected := compiler()!
	work := hosttest.work_dir('', 'vinix-' + kind + '-')!
	defer { hosttest.remove_work_dir(work) or { eprintln(err) } }
	name := if kind == 'compat' { 'compatcore' } else { 'heapbench' }
	hosttest.module_copy_tree(root() + if kind == 'compat' {
		'/kernel/linuxkpi/compatcore'
	} else {
		'/kernel/heapbench'
	},
		work + '/' + name)!
	if kind == 'compat' {
		hosttest.module_copy_tree(root() + '/kernel/abiargs', work + '/abiargs')!
		mut text := os.read_file(work + '/compatcore/string.v')!
		for export_name in ['strchr', 'strpbrk', 'strsep'] {
			text = text.replace("@[export: '" + export_name + "']", "@[export: 'vinix_linuxkpi_host_" + export_name + "']")
		}
		os.write_file(work + '/compatcore/string.v', text)!
		path := work + '/compatcore/native_runtime.v'
		if os.exists(path) {
			mut runtime := os.read_file(path)!
			for export_name in ['vsnprintf', 'vscnprintf', 'vsprintf', 'snprintf', 'scnprintf',
				'sprintf'] {
				runtime = runtime.replace("@[export: '" + export_name + "']", "@[export: 'vinix_linuxkpi_format_test_" + export_name + "']")
			}
			os.write_file(path, runtime)!
		}
	} else if host_clock {
		os.write_file(work + '/heapbench/ticks_' + arch + '.v', 'module heapbench\nfn C.vkb_test_ticks() u64\nfn ticks() u64 { return C.vkb_test_ticks() }\n')!
	}
	os.write_file(work + '/v.mod', if kind == 'compat' {
		"Module {name: 'compat_test'}\n"
	} else {
		"Module { name: 'kernel_sampler' }\n"
	})!
	os.write_file(work + '/entry.v', 'module main\nimport ' + name + ' as _\n')!
	mut argv := [selected]
	if kind == 'compat' && arch != '' { argv << ['-arch', arch] }
	argv << ['-shared', '-no-builtin', '-no-closures', '-os', 'vinix']
	if kind != 'compat' { argv << ['-arch', arch] }
	argv << ['-target-libc-headers', '-nofloat', '-gc', 'none', '-manualfree', '-o', output, work]
	show(checked(argv)!)
	if kind != 'compat' {
		os.write_file(output, '#pragma GCC diagnostic ignored "-Wunused-function"\n' + os.read_file(output)!)!
	}
}

pub fn generate_compat(output string, arch string) ! { project('compat', output, arch, false)! }

pub fn generate_sampler(output string, arch string, host_clock bool) ! {
	project('kalloc-v', output, arch, host_clock)!
}

pub fn generate_bench(output_path string, arch string) !map[string]json2.Any {
	output := absolute(output_path)!
	source := root() + '/tests/alloc-bench/benchcore'
	generate_module(source, output, arch, []string{})!
	os.write_file(output, '#pragma GCC diagnostic ignored "-Wunused-function"\n#pragma GCC diagnostic ignored "-Wunused-parameter"\n' + os.read_file(output)!)!
	header := os.dir(output) + '/bench-native-abi.h'
	os.cp(source + '/bench-native-abi.h', header)!
	selected := compiler()!
	mut paths := os.ls(source)!
	paths.sort()
	mut sources := map[string]json2.Any{}
	for path in paths.filter(it.ends_with('.v')) {
		sources['tests/alloc-bench/benchcore/' + path] = digest(source + '/' + path)!
	}
	manifest := {
		'arch':                 json2.Any(arch)
		'v_compiler':           json2.Any(selected)
		'v_compiler_version':   json2.Any(checked([selected, 'version'])!.stdout.trim_space())
		'v_compiler_sha256':    json2.Any(digest(selected)!)
		'v_sources':            json2.Any(sources)
		'source_sha256':        json2.Any(digest(output)!)
		'native_header_sha256': json2.Any(digest(header)!)
	}
	os.write_file(hosttest.replace_suffix(output, '.json'), json2.encode(manifest,
		prettify:      true
		indent_string: '  '
	) + '\n')!
	return manifest
}

pub fn cli(argv []string, kind string) int {
	scalar := if kind == 'fixture' {
		['--arch', '--module']
	} else if kind == 'sampler' {
		['--arch', '--header']
	} else {
		['--arch']
	}
	flags := if kind == 'sampler' { ['--host-clock'] } else { []string{} }
	usage := match kind {
		'fixture' { 'usage: compile-v-fixture OUTPUT --arch aarch64|x86_64 [--module SOURCE]' }
		'sampler' {
			'usage: compile-v-sampler OUTPUT [--arch amd64|arm64] [--host-clock] [--header HEADER]'
		}
		else { 'usage: ' + kind + ' OUTPUT [--arch amd64|arm64]' }
	}
	args := cachecli.arguments(argv, scalar, []string{}, flags, 1, 1, usage) or {
		eprintln(err)
		return 2
	}
	arch := args.value('--arch', if kind == 'compat' { '' } else { 'amd64' })
	if kind == 'fixture' {
		if '--arch' !in args.options || arch !in ['aarch64', 'x86_64'] {
			eprintln('--arch requires aarch64 or x86_64')
			return 2
		}
	} else if arch !in ['arm64', 'amd64'] && !(kind == 'compat' && '--arch' !in args.options) {
		eprintln('invalid architecture')
		return 2
	}
	if kind == 'sampler' && arch == 'arm64' && '--host-clock' !in args.options {
		eprintln('the native TSC benchmark is x86-only; ARM is a fixture clock target')
		return 2
	}
	guard := cachecli.own_commands()
	defer { guard.close() }
	perform(args, kind, arch) or {
		report_failure(err)
		return if cachecli.cancelled() { cachecli.interrupt_status() } else { 1 }
	}
	return 0
}

fn perform(args cachecli.Arguments, kind string, arch string) ! {
	output := args.positional[0]
	match kind {
		'fixture' {
			generate_module(absolute(args.value('--module', root() + '/tests/kernel-gaps/serialcore'))!, absolute(output)!, if arch == 'aarch64' {
				'arm64'
			} else {
				'amd64'
			}, ['nofloat'])!
		}
		'compat' { generate_compat(output, arch)! }
		'bench' { generate_bench(output, arch)! }
		'sampler' {
			generate_sampler(output, arch, '--host-clock' in args.options)!
			if '--header' in args.options {
				hosttest.emit_module_header(root() + '/kernel/heapbench', output, args.value('--header', ''))!
			}
		}
		'metadata' { generate_metadata(absolute(output)!, arch)! }
		else { return error('unknown generator') }
	}
}
