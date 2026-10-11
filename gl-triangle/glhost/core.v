// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module glhost

import crypto.sha256
import hosttest
import os
import policyhost

#include <stdlib.h>

fn C.mkdtemp(&char) &char

pub fn root() string { return os.real_path(@DIR + '/../..') }

fn here() string { return os.real_path(@DIR + '/..') }

pub struct ArgumentError {
pub:
	message string
}

pub fn (e ArgumentError) msg() string { return e.message }

pub fn (e ArgumentError) code() int { return 2 }

pub fn argument_error(message string) IError { return ArgumentError{message} }

pub fn private_directory(prefix string) !string {
	base := os.getenv_opt('TMPDIR') or { os.temp_dir() }
	mut template := (os.join_path(base, prefix + 'XXXXXX') + '\x00').bytes()
	if isnil(C.mkdtemp(&char(template.data))) { return os.error_posix() }
	return template[..template.len - 1].bytestr().clone()
}

pub fn run(argv []string) ! { policyhost.inherited(argv)! }

pub fn output(argv []string) !string { return policyhost.capture(argv)! }

pub fn command(arguments []string, kind string) int {
	guard := policyhost.own_commands()
	defer { guard.close() }
	checked(arguments, kind) or {
		eprintln(err.msg())
		return if err is ArgumentError {
			2
		} else if err.msg() == 'Host test interrupted' {
			130
		} else {
			1
		}
	}
	return 0
}

fn checked(arguments []string, operation string) ! {
	match operation {
		'compile' {
			args := hosttest.parse_arguments(arguments, [
				hosttest.Option{'--kind', true, ['egl', 'glut', 'legacy']},
				hosttest.Option{'--arch', true, ['amd64', 'arm64']},
				hosttest.Option{'--source', true, []string{}},
			], 1, 'usage: compile-v OUTPUT [--kind egl|glut|legacy] [--arch amd64|arm64] [--source MODULE.v]',
				'Generate maintained native V triangle sources.') or { return argument_error(err.msg()) }
			generate(args.positional[0], args.options['--kind'] or { 'egl' },
				args.options['--arch'] or { 'arm64' }, args.options['--source'] or { '' })!
		}
		'stage' {
			args := hosttest.parse_arguments(arguments, [hosttest.Option{'--arch', true, [
				'amd64',
				'arm64',
			]}],
				1, 'usage: stage DESTINATION [--arch amd64|arm64]', 'Stage native V, ABI bindings and generated guest artifacts.') or { return argument_error(err.msg()) }
			stage(args.positional[0], args.options['--arch'] or { 'arm64' })!
		}
		'fixture' {
			if arguments in [['--help'], ['-h']] {
				println('usage: run\n\nSanitize native rendering against independent EGL/GL/framebuffer fixtures.')
				return
			}
			if arguments.len != 0 { return argument_error('usage: run') }
			fixture()!
		}
		else { return error('unknown GL tool') }
	}
}

fn compiler() !string {
	finder := root() + '/build-support/find-v.sh'
	if os.is_file(finder) {
		return output(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'find-v',
			root()])!
	}
	if value := os.getenv_opt('V') {
		if value != '' { return value }
	}
	return os.find_abs_path_of_executable('v') or { return error('V is required to regenerate the triangle source') }
}

pub fn generate(destination string, kind string, arch string, alternate string) ! {
	if kind !in ['egl', 'glut', 'legacy'] || arch !in ['amd64', 'arm64'] {
		return error('invalid triangle target')
	}
	work := private_directory('vinix-gl-v-')!
	defer { os.rmdir_all(work) or {} }
	name := {
		'egl':    'egltri'
		'glut':   'gluttri'
		'legacy': 'legacytri'
	}[kind]
	source := here() + '/' + {
		'egl':    'eglcore'
		'glut':   'glutcore'
		'legacy': 'legacycore'
	}[kind]
	hosttest.module_copy_tree(source, work + '/' + name)!
	if alternate != '' {
		hosttest.module_copy_file_preserving_stat(alternate, work + '/' + name + '/core.v')!
	}
	mut files := os.ls(work + '/' + name)!.filter(it.ends_with('.v'))
	files.sort()
	mut hash := sha256.new()
	for file in files { hash.write(os.read_bytes(work + '/' + name + '/' + file)!)! }
	hash.write(os.read_bytes(here() + '/gl_v.h')!)!
	os.write_file(work + '/v.mod', "Module {name: 'gl_triangle'}\n")!
	os.write_file(work + '/entry.v', 'module main\nimport ' + name + ' as _\n')!
	mut env := policyhost.environment()
	env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	policyhost.owned_inherited_environment([compiler()!, '-shared', '-no-builtin', '-no-closures',
		'-os', 'vinix', '-arch', arch, '-target-libc-headers', '-gc', 'none', '-manualfree', '-o',
		work + '/output.c', work], env, policyhost.caller_arch(), '')!
	prefix := '/* Generated from maintained V; source SHA256 ' + hash.sum([]u8{}).hex() + ' */\n' +
		(if kind != 'egl' { '#define VINIX_GLUT_TRIANGLE 1\n' } else { '' }) +
		'#pragma GCC diagnostic ignored "-Wunused-function"\n#pragma GCC diagnostic ignored "-Wunused-parameter"\n' +
		'#pragma GCC diagnostic ignored "-Wunused-label"\n#pragma GCC diagnostic ignored "-Wpointer-sign"\n'
	hosttest.module_write_text(destination, prefix + hosttest.module_read_text(work + '/output.c')!)!
}

fn merge_tree(source string, destination string) ! {
	os.mkdir_all(destination)!
	for name in os.ls(source)! {
		from, to := source + '/' + name, destination + '/' + name
		if os.is_dir(from) {
			merge_tree(from, to)!
		} else {
			hosttest.module_copy_file_preserving_stat(from, to)!
		}
	}
	hosttest.module_copy_directory_stat(source, destination)!
}

pub fn stage(destination string, arch string) ! {
	os.mkdir_all(destination)!
	for pair in [['egl', 'egl_triangle.c'], ['glut', 'triangle.c'], ['legacy', 'legacy_triangle.c']] {
		generate(destination + '/' + pair[1], pair[0], arch, '')!
	}
	for name in ['eglcore', 'glutcore', 'legacycore'] {
		merge_tree(here() + '/' + name, destination + '/' + name)!
	}
	// A guest can rebuild using the maintained front and its complete native closure.
	for name in ['gl_v.h', 'compile-v', 'compile-v.v'] {
		hosttest.module_copy_file_preserving_stat(here() + '/' + name, destination + '/' + name)!
	}
	for name in ['glhost', 'hosttest', 'fixturehost', 'policyhost'] {
		source, target := here() + '/' + name, destination + '/' + name
		os.mkdir_all(target)!
		// Modules need maintained source and SDK headers. Build products and
		// checkout-local aliases are not part of the portable source closure.
		for file in os.ls(source)! {
			if (file.ends_with('.v') && !file.ends_with('_test.v')) || file.ends_with('.h') {
				hosttest.module_copy_file_preserving_stat(source + '/' + file, target + '/' + file)!
			}
		}
	}
}
