// SPDX-License-Identifier: GPL-2.0-or-later
module nativepolicy

import hosttest
import os
import policyhost
import time

#include <signal.h>
fn C.kill(i32, i32) i32

fn root() string { return hosttest.root() }
fn read(path string) !string { return hosttest.module_read_text(path)! }
fn write(path string, text string) ! { hosttest.module_write_text(path, text)! }
fn run(argv []string) ! { policyhost.inherited(argv)! }
fn output(argv []string) !string { return policyhost.capture(argv)! }

fn timed_inherited(argv []string, seconds int) ! {
	mut child := os.new_process(argv[0])
	child.set_args(argv[1..])
	child.set_environment(policyhost.environment())
	mut reaped := false
	defer {
		if !reaped && child.pid > 0 {
			C.kill(i32(child.pid), C.SIGKILL)
			child.wait()
		}
		child.close()
	}
	child.run()
	if child.pid <= 0 || child.status == .aborted { return error('Cannot start fixture') }
	started := time.sys_mono_now()
	for child.is_alive() {
		if time.sys_mono_now() - started >= u64(seconds) * u64(time.second) {
			return error('Fixture timed out after ' + seconds.str() + ' seconds')
		}
		time.sleep(time.millisecond)
	}
	child.wait()
	reaped = true
	if child.code != 0 { return error('Fixture failed: ' + child.code.str()) }
}
fn compiler() !string {
	return output(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'find-v', root()])!
}
fn arch() string { return policyhost.caller_arch() }
fn clang_arch(selected string) []string {
	$if macos { return ['-arch', if selected == 'arm64' { 'arm64' } else { 'x86_64' }] }
	return []string{}
}
fn private_work(prefix string) !string { return hosttest.work_dir('', prefix)! }
fn retire(work string) { hosttest.remove_work_dir(work) or { eprintln(err.msg()) } }

fn concat(groups ...[]string) []string {
	mut result := []string{}
	for group in groups { result << group }
	return result
}

// These producers stage complete standalone projects. Unlike the generic module
// producer, the historical artifacts keep the compiler's original init names.
fn generate_project(work string, destination string, selected string, prod bool, defines []string) ! {
	mut argv := [compiler()!, '-shared', '-no-builtin', '-no-closures', '-os', 'vinix']
	if selected != '' { argv << ['-arch', selected] }
	argv << ['-target-libc-headers', '-nofloat', '-gc', 'none', '-manualfree']
	if prod { argv << '-prod' }
	for define in defines { argv << ['-d', define] }
	argv << ['-o', destination, work]
	mut env := policyhost.environment()
	env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	policyhost.owned_inherited_environment(argv, env, arch(), '')!
}

fn generate_module(source string, destination string, selected string) ! {
	// Invoke the native command so its environment precedes the V runtime's VEXE
	// insertion, and retain the already qualified module/header transformation.
	run([root() + '/build-support/compile-v-module', source, destination,
		'--arch', selected, '-d', 'nofloat'])!
}

fn compile_module(source string, destination string, selected string, flags []string) ! {
	generated := destination.all_before_last('.') + '.c'
	generate_module(hosttest.module_resolve(source)!, hosttest.module_resolve(generated)!, selected)!
	mut compile_flags := flags.filter(it !in ['-static', '-nostdlib', '-pie']
		&& !it.starts_with('-L') && !it.starts_with('-l') && !it.starts_with('-Wl,')
		&& !it.starts_with('-fuse-ld='))
	compile_flags << ['-Wno-unused-function', '-Wno-unused-parameter', '-fPIC',
		'-I', hosttest.module_resolve(source)!, '-c', generated, '-o', destination]
	run(compile_flags)!
}

// Preserve Unicode word boundaries and each command's original allocator list.
pub fn allocator_imports(text string, names []string, prefixes []string) bool {
	mut word := []rune{}
	for ch in (text + ' ').runes() {
		if hosttest.module_word_rune(ch) { word << ch; continue }
		token := word.string()
		name := if token.starts_with('_') { token[1..] } else { token }
		if name in names || prefixes.any(name.starts_with(it)) { return true }
		word.clear()
	}
	return false
}

fn no_allocators(text string) ! {
	if allocator_imports(text, ['malloc', 'calloc', 'realloc', 'free', 'memdup'], ['new_array']) {
		return error('Unexpected allocator import:\n' + text)
	}
}

pub fn command(arguments []string, family string) int {
	if family == 'init' {
		return init_command(arguments)
	}
	if family == 'network' {
		parsed := hosttest.parse_arguments(arguments, []hosttest.Option{}, 2,
			'Usage: run-host SUITE FIXTURE', 'Run the independent network fixture with production V and lwIP.') or {
			eprintln(err.msg()); return 2
		}
		network(parsed.positional[0], parsed.positional[1]) or { eprintln(err.msg()); return 1 }
		return 0
	}
	if family == 'network-core' {
		parsed := hosttest.parse_arguments(arguments, []hosttest.Option{}, 1,
			'Usage: compile-core OUTPUT', 'Generate the production network core with native fixture hooks.') or {
			eprintln(err.msg()); return 2
		}
		network_core(hosttest.module_resolve(parsed.positional[0]) or { eprintln(err.msg()); return 1 }) or {
			eprintln(err.msg()); return 1
		}
		return 0
	}
	hosttest.parse_arguments(arguments, []hosttest.Option{}, 0,
		'Usage: ' + family, 'Exercise the production policy with its independent fixture.') or {
		eprintln(err.msg()); return 2
	}
	match family {
		'track' { tracker() or { eprintln(err.msg()); return 1 } }
		'print' { console() or { eprintln(err.msg()); return 1 } }
		'serial-console' { serial_console() or { eprintln(err.msg()); return 1 } }
		'diagnostic' { diagnostics() or { eprintln(err.msg()); return 1 } }
		'cpu' { cpu() or { eprintln(err.msg()); return 1 } }
		else { eprintln('Unknown policy command'); return 2 }
	}
	return 0
}
