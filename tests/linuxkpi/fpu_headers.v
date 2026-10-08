// SPDX-License-Identifier: GPL-2.0-or-later
// Compare the production FPU entry with its immutable C-header control.
module main

import os
import json2
import hosttest

const reference = '99162a3924e8fc12d6e2298ee46bfde6c2627269'
const scope = 'Compare the production FPU entry with its immutable C-header control.'

fn command(argv []string) !hosttest.Result {
	result := hosttest.capture(argv, '', -1, os.environ())!
	if result.code != 0 { return error(result.stdout + result.stderr) }
	return result
}

fn platform_description() !string {
	info := os.uname()
	$if macos {
		version := command(['/usr/bin/sw_vers', '-productVersion'])!.stdout.trim_space()
		processor := $if arm64 { 'arm' } $else { 'i386' }
		return 'macOS-' + version + '-' + info.machine + '-' + processor + '-64bit'
	} $else {
		// This is human-readable host provenance, as in platform.platform().
		processor := command(['uname', '-p'])!.stdout.trim_space()
		mut parts := [info.sysname, info.release, info.machine]
		if processor != '' && processor != 'unknown' && processor != info.machine { parts << processor }
		if info.sysname == 'Linux' {
			libc := hosttest.capture(['getconf', 'GNU_LIBC_VERSION'], '', -1, os.environ())!
			parts << 'with'
			parts << if libc.code == 0 { libc.stdout.trim_space().replace(' ', '') } else { '' }
		} else { parts << '64bit' }
		return parts.filter(it != '').join('-')
	}
}

fn run_profile(output_path string, selected_reference string) ! {
	root := hosttest.root()
	output := hosttest.work_dir(output_path, 'vinix-fpu-')!
	// An explicit output belongs to the caller and is retained even on failure.
	overlay := os.join_path(output, 'include/asm')
	os.mkdir_all(os.join_path(overlay, 'fpu'))!
	os.write_file(os.join_path(overlay, 'cpufeature.h'),
		'#ifndef __always_inline\n#define __always_inline inline __attribute__((always_inline))\n#endif\n' +
		'void vinix_linuxkpi_fpu_begin(void);\nvoid vinix_linuxkpi_fpu_end(void);\n')!
	header_path := 'kernel/linuxkpi/include/asm/fpu/api.h'
	original := hosttest.capture_in(['git', 'show', selected_reference + ':' + header_path], '', -1, os.environ(), root)!
	if original.code != 0 { return error(original.stderr) }
	production := os.read_bytes(os.join_path(root, header_path))!
	private := os.join_path(output, 'fpucore')
	os.mkdir(private)!
	os.write_file(os.join_path(private, 'fpu_amd64.v'),
		os.read_file(os.join_path(root, 'kernel/linuxkpi/headercore/fpu_amd64.v'))!.replace_once('module headercore', 'module fpucore'))!
	hosttest.generate_module(private, os.join_path(output, 'fpucore.c'), 'amd64', ['nofloat'])!
	hosttest.generate_module(os.join_path(root, 'tests/linuxkpi/fpufixture'), os.join_path(output, 'fixture.c'), 'amd64', ['nofloat'])!
	cc := hosttest.env_default('CC', 'clang')
	nm := hosttest.env_default('NM', 'nm')
	architecture := $if macos { ['-arch', 'x86_64'] } $else { ['-m64'] }
	common := [cc, ...architecture, '-O2', '-g', '-fno-strict-aliasing', '-Wall', '-Wextra', '-Werror',
		'-Wno-unused-function', '-Wno-unused-variable', '-Wno-unused-parameter',
		'-fsanitize=address,undefined', '-I', os.join_path(output, 'include')]
	command([...common, '-c', os.join_path(output, 'fpucore.c'), '-o', os.join_path(output, 'fpucore.o')])!
	imports := command([nm, '-u', os.join_path(output, 'fpucore.o')])!.stdout
	if ['malloc', 'calloc', 'realloc', 'memdup', 'new_array', 'string__'].any(imports.contains(it)) {
		return error('Implicit allocator import in FPU entry: ' + imports)
	}
	mut runs := map[string]json2.Any{}
	for tag in ['original', 'v'] {
		os.write_file_array(os.join_path(overlay, 'fpu/api.h'), if tag == 'original' { original.stdout.bytes() } else { production })!
		executable := os.join_path(output, tag)
		mut argv := [...common, os.join_path(output, 'fixture.c')]
		if tag == 'v' { argv << os.join_path(output, 'fpucore.o') }
		argv << ['-o', executable]
		command(argv)!
		mut env := os.environ()
		env['ASAN_OPTIONS'] = 'detect_leaks=0:halt_on_error=1'
		env['UBSAN_OPTIONS'] = 'halt_on_error=1:print_stacktrace=1'
		result := hosttest.capture([executable], '', -1, env)!
		os.write_file(os.join_path(output, tag + '.stdout'), result.stdout)!
		os.write_file(os.join_path(output, tag + '.stderr'), result.stderr)!
		if result.code != 0 || result.stderr != '' || result.stdout != 'LinuxKPI FPU header: PASS 1024 x87/MXCSR borrows\n' {
			return error(tag + ' FPU instruction comparison failed: ' + result.stdout + result.stderr)
		}
		runs[tag] = map[string]json2.Any{'sha256': json2.Any(hosttest.sha(executable)!), 'verdict': 'PASS'}
	}
	mut source_inputs := map[string]string{}
	for path in ['kernel/linuxkpi/headercore/fpu_amd64.v', header_path, 'tests/linuxkpi/fpufixture/core_amd64.v', @FILE[ root.len + 1.. ]] {
		source_inputs[path] = hosttest.sha(os.join_path(root, path))!
	}
	hosttest.write_json(os.join_path(output, 'validation.json'), map[string]json2.Any{
		'reference': json2.Any(selected_reference)
		'original_header_sha256': hosttest.text_sha(original.stdout)
		'production_header_sha256': hosttest.sha(os.join_path(root, header_path))!
		'runs': runs
		'compiler': command([cc, '--version'])!.stdout
		'compiler_flags': hosttest.strings(common)
		'host': platform_description()!
		'source_inputs': hosttest.string_map(source_inputs)
		'imports': imports
		'asan_ubsan_halt_on_error': true
		'limits': hosttest.strings(['x86 instructions; Darwin ARM hosts execute the binary through Rosetta; no ARM FPU API',
			'synchronous ownership model; full kernel guest verifies scheduler/FPU storage'])
	})!
	println('LinuxKPI FPU original/V instruction comparison: PASS')
}

fn parse_args(args []string) !(string, string) {
	mut output := ''
	mut has_output := false
	mut selected := reference
	mut unknown := []string{}
	mut index := 0
	mut positional := false
	for index < args.len {
		arg := args[index]
		if !positional && arg == '--' { positional = true; index++; continue }
		if !positional && arg == '-h=' { eprintln('argument -h/--help: ignored explicit argument'); exit(1) }
		if !positional && arg.starts_with('-h') && !arg[1..].bytes().all(it == `h`) { return error('argument -h/--help: ignored explicit argument') }
		name := arg.all_before('=')
		if !positional && ((arg.starts_with('-h') && arg[1..].bytes().all(it == `h`)) || (name.starts_with('--') && '--help'.starts_with(name))) {
			if arg.contains('=') { return error('argument --help: ignored explicit argument') }
			println('Usage: fpu_headers.v OUTPUT [--reference REVISION]\n\n' + scope); exit(0)
		}
		if !positional && name.starts_with('--') && '--reference'.starts_with(name) {
			if arg.contains('=') { selected = arg.all_after('=') }
			else {
				if index + 1 >= args.len || (args[index + 1].starts_with('-') && args[index + 1] != '-' && !negative_path(args[index + 1])) { return error('argument --reference: expected one argument') }
				index++; selected = args[index]
			}
		} else if !positional && arg.starts_with('-') && arg != '-' && !negative_path(arg) { unknown << arg }
		else if !has_output { output = if arg == '' { '.' } else { arg }; has_output = true }
		else { unknown << arg }
		index++
	}
	if !has_output { return error('the following arguments are required: output') }
	if unknown.len > 0 { return error('unrecognized arguments: ' + unknown.join(' ')) }
	return output, selected
}

fn negative_path(text string) bool {
	value := text[1..]
	if value != '' && value.bytes().all(it.is_digit()) { return true }
	return value.count('.') == 1 && value.all_before('.').bytes().all(it.is_digit()) &&
		value.all_after('.').len > 0 && value.all_after('.').bytes().all(it.is_digit())
}

fn main() {
	output, selected := parse_args(os.args[1..]) or { eprintln(err.msg()); exit(2) }
	run_profile(output, selected) or { eprintln(err.msg()); exit(1) }
}
