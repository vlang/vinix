// SPDX-License-Identifier: GPL-2.0-only
module agxhost

import hosttest
import fixturehost
import os

#include <stdlib.h>
#include <errno.h>

fn C.mkdtemp(&char) &char

pub struct CommandFailure {
pub:
	argv   []string
	result hosttest.Result
}

pub fn (e CommandFailure) msg() string { return 'Command failed' }

pub fn (e CommandFailure) code() int { return e.result.code }

pub struct Transcript {
pub mut:
	stdout    string
	stderr    string
	inherit   bool
	host_arch string
	path_arguments []int
	path_executable string
}

fn (mut out Transcript) typed_arguments(argv []string, paths []int) {
	out.path_arguments = paths.clone()
	out.path_executable = if 0 in paths { argv[0] } else { '' }
}

fn (mut out Transcript) typed_done() {
	out.path_arguments = []int{}
	out.path_executable = ''
}

fn (mut out Transcript) command_typed(argv []string, environment map[string]string, paths []int) !string {
	out.typed_arguments(argv, paths)
	value := out.command(argv, environment)!
	out.typed_done()
	return value
}

fn (mut out Transcript) capture_typed(argv []string, environment map[string]string, paths []int) !string {
	out.typed_arguments(argv, paths)
	value := out.capture_output(argv, environment)!
	out.typed_done()
	return value
}

pub fn private_directory(base string, prefix string) !string {
	mut template := (os.join_path(base, prefix + 'XXXXXX') + '\x00').bytes()
	result := unsafe { C.mkdtemp(&char(template.data)) }
	if result == unsafe { nil } {
		return hosttest.ModuleFileError{base, int(C.errno), os.get_error_msg(int(C.errno))}
	}
	return unsafe { result.vstring().clone() }
}

fn (mut out Transcript) streams(stdout string, stderr string) {
	if out.inherit {
		print(stdout)
		eprint(stderr)
	} else {
		out.stdout += stdout
		out.stderr += stderr
	}
}

pub fn (mut out Transcript) command(argv []string, environment map[string]string) !string {
	if out.inherit {
		fixturehost.inherited_command_environment_preferred(argv, environment, out.host_arch)!
		return ''
	}
	result := hosttest.capture(argv, '', -1, environment)!
	out.streams(result.stdout, result.stderr)
	if result.code != 0 { return CommandFailure{argv, result} }
	return result.stdout
}

pub fn (mut out Transcript) capture_output(argv []string, environment map[string]string) !string {
	if out.inherit {
		text := fixturehost.capture_preferred(argv, '', environment, false, out.host_arch)!
		hosttest.module_decode_utf8(text)!
		return text
	}
	result := hosttest.capture(argv, '', -1, environment)!
	out.streams('', result.stderr)
	if result.code != 0 { return CommandFailure{argv, result} }
	return result.stdout
}

pub fn (mut out Transcript) generate_module(source string, output string, arch string, defines []string) ! {
	result := hosttest.generate_module_capture(source, output, arch, defines) or {
		if err is hosttest.ModuleCommandError {
			out.streams(err.result.stdout, err.result.stderr)
			return CommandFailure{err.argv, err.result}
		}
		return err
	}
	out.streams(result.stdout, result.stderr)
}

pub fn (mut out Transcript) compile_module(source string, output string, arch string, flags []string) ! {
	out.compile_module_environment(source, output, arch, flags, os.environ())!
}

fn (mut out Transcript) compile_module_environment(source string, output string, arch string, flags []string, environment map[string]string) ! {
	resolved := hosttest.module_resolve(source)!
	generated := hosttest.replace_suffix(output, '.c')
	out.generate_module(resolved, hosttest.module_resolve(generated)!, if arch == 'aarch64' {
		'arm64'
	} else {
		'amd64'
	}, ['nofloat'])!
	mut filtered := []string{}
	for flag in flags {
		if flag in ['-static', '-nostdlib', '-pie'] || flag.starts_with('-L') || flag.starts_with('-l') || flag.starts_with('-Wl,') || flag.starts_with('-fuse-ld=') {
			continue
		}
		filtered << flag
	}
	// Preserve the original fixture-only exceptions and module include policy.
	mut argv := filtered.clone()
	argv << ['-Wno-unused-function', '-Wno-unused-parameter', '-fPIC', '-I', resolved, '-c', generated,
		'-o', output]
	out.command(argv, environment)!
}
