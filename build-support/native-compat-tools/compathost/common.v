// SPDX-License-Identifier: GPL-2.0-or-later
module compathost

import fixturehost
import hosttest
import os
import policyhost

const original = '8f7239d1fd4c593746279699f6ff25df5f4dd7bd'

fn root() string { return hosttest.root() }
fn read(path string) !string { return hosttest.module_read_text(path)! }
fn write(path string, value string) ! { hosttest.module_write_text(path, value)! }
fn resolve(path string) !string { return hosttest.module_resolve(path)! }
fn run(argv []string) ! { policyhost.inherited(argv)! }
fn output(argv []string) !string { return policyhost.capture(argv)! }
fn captured(argv []string) !fixturehost.CapturedCommand {
	result := fixturehost.capture_both_preferred(argv, policyhost.environment(), policyhost.caller_arch())!
	if result.status != 0 {
		eprint(result.stderr)
		return error('Command exited ' + result.status.str() + ': ' + argv[0])
	}
	return result
}

fn generate(source string, destination string, arch string, defines []string, header string) ! {
	mut argv := [root() + '/build-support/compile-v-module', resolve(source)!, resolve(destination)!, '--arch', arch]
	for define in defines { argv << ['-d', define] }
	if header != '' { argv << ['--header', resolve(header)!] }
	run(argv)!
}

fn compiler_prefix(name string, fallback string) ![]string {
	value := os.getenv_opt(name) or { fallback }
	words := hosttest.shell_split(value)!
	if words.len == 0 { return error('Empty compiler: ' + name) }
	return words
}

fn retire(work string) { hosttest.remove_work_dir(work) or { eprintln(err.msg()) } }
fn needed(parsed hosttest.Arguments, names []string) ! {
	for name in names {
		if name !in parsed.options { return error_with_code('missing required ' + name, 2) }
	}
}

pub fn command(args []string, family string) int {
	result := command_checked(args, family) or { eprintln(err.msg()); return if err.code() == 2 { 2 } else { 1 } }
	return result
}

fn command_checked(args []string, family string) !int {
	match family {
		'robust-compile' { return robust_compile(args)! }
		'robust-test' { return robust_test(args)! }
		'robust-guest' { return robust_guest(args)! }
		'office-compile' { return office_compile(args)! }
		'office-test' { return office_test(args)! }
		'office-guest' { return office_guest(args)! }
		'net-random' { return random_command(args)! }
		'n64-bridge' { return n64_bridge(args)! }
		else { return error_with_code('Unknown compatibility command', 2) }
	}
}
