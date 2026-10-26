// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise the production start_helper argument/defer block on the host.
// No root permissions, helper process, guest or account data are required.
module main

import crypto.sha256
import os

fn quoted(value string) string {
	return "'" + value.replace("'", "'\\''") + "'"
}

fn checked(command string, log string) ! {
	result := os.execute(command)
	os.write_file(log, result.output)!
	if result.exit_code != 0 { return error('argument lifetime check failed; inspect ' + log) }
}

fn rejected(compiler string, flags string, state string, name string, block string, diagnostic string) ! {
	source := state + '/' + name + '.v'
	binary := state + '/' + name
	os.write_file(source, program(block))!
	checked(quoted(compiler) + flags + quoted(binary) + ' ' + quoted(source), state + '/' + name + '-build.log')!
	result := os.execute('ASAN_OPTIONS=detect_leaks=0 ' + quoted(binary))
	os.write_file(state + '/' + name + '-run.log', result.output)!
	if !result.output.contains(diagnostic) {
		return error(name + ' cleanup must produce its runtime lifetime diagnostic')
	}
	if diagnostic == 'AddressSanitizer' && (result.exit_code == 0
		|| (!result.output.contains('double-free') && !result.output.contains('heap-use-after-free'))) {
		return error(name + ' cleanup must fail with an AddressSanitizer lifetime error')
	}
}

fn argument_block(source string) !string {
	function := source.index('fn (c &Controller) start_helper(') or { return error('missing production helper') }
	body := source[function..]
	start := body.index('\targs := ') or { return error('missing production argument array') }
	end := body.index('\tenvironment := ') or { return error('missing production exec environment') }
	if end <= start { return error('invalid production argument block') }
	return body[start..end]
}

fn program(block string) string {
	return 'module main\n'
		+ 'struct Config { helper string; window_socket string }\n'
		+ 'struct Controller { config Config }\n'
		+ 'fn exercise(c &Controller, surface int, input int, lifetime int) !int {\n'
		+ block + '\treturn argv.len\n}\n'
		+ 'fn main() {\n'
		+ '\tc := Controller{config: Config{helper: "/test/helper".clone(), window_socket: "/test/socket".clone()}}\n'
		+ '\tdefer { unsafe { c.config.helper.free(); c.config.window_socket.free() } }\n'
		+ '\tfor i in 0 .. 256 { assert exercise(&c, i + 3, i + 4, i + 5)! == 10 }\n'
		+ '\tprintln("ARGV-LIFETIME-PASS 256 production argument blocks")\n}\n'
}

fn run() ! {
	if os.args.len != 3 { return error('usage: v run account-ui-argv-lifetime.v ABS_V ABS_FRESH_STATE_DIR') }
	compiler, state := os.args[1], os.args[2]
	if !os.is_abs_path(compiler) || !os.is_abs_path(state) || os.exists(state) {
		return error('compiler and fresh external state directory must be absolute')
	}
	os.mkdir_all(state)!
	source_path := 'build-support/android/accountuifd/control.c.v'
	source := os.read_file(source_path)!
	os.write_file(state + '/control.c.v', source)!
	os.cp('tests/native-android-ws/account-ui-argv-lifetime.v', state + '/checker.v')!
	block := argument_block(source)!
	if block.contains('args[2].free()') || block.contains('args[4].free()') || block.contains('args[6].free()') {
		return error('production argument block still contains redundant element frees')
	}
	if block.count('args.free()') != 1 { return error('production argument array must be released once') }
	if !block.contains('c.config.helper.clone()') || !block.contains('c.config.window_socket.clone()') {
		return error('argument array must own its config argument strings')
	}
	fixed_source := state + '/fixed.v'
	fixed := state + '/fixed'
	os.write_file(fixed_source, program(block))!
	flags := ' -g -gc none -manualfree -cc cc -cflags -fsanitize=address -ldflags -fsanitize=address -o '
	checked(quoted(compiler) + flags + quoted(fixed) + ' ' + quoted(fixed_source), state + '/fixed-build.log')!
	checked('ASAN_OPTIONS=detect_leaks=0 ' + quoted(fixed), state + '/fixed-run.log')!
	if os.read_file(state + '/fixed-run.log')!.trim_space() != 'ARGV-LIFETIME-PASS 256 production argument blocks' {
		return error('fixed runtime must complete without lifetime diagnostics')
	}
	// Restore the exact old redundant frees inside the extracted production
	// block. V detects the second free even when it suppresses libc's free.
	old_block := block.replace('\t\t\targs.free()', '\t\t\targs[2].free()\n\t\t\targs[4].free()\n\t\t\targs[6].free()\n\t\t\targs.free()')
	rejected(compiler, flags, state, 'old', old_block, 'double string.free() detected')!
	// The array recursively owns string elements. Borrowing the controller's
	// config values would free them after the first call and fail on reuse.
	borrowed := block.replace('c.config.helper.clone()', 'c.config.helper')
		.replace('c.config.window_socket.clone()', 'c.config.window_socket')
	rejected(compiler, flags, state, 'borrowed', borrowed, 'AddressSanitizer')!
	mut sums := ''
	for name in ['control.c.v', 'checker.v', 'fixed.v', 'old.v', 'borrowed.v', 'fixed', 'old', 'borrowed', 'fixed-build.log', 'fixed-run.log', 'old-build.log', 'old-run.log', 'borrowed-build.log', 'borrowed-run.log'] {
		sums += sha256.sum(os.read_bytes(state + '/' + name)!).hex() + '  ' + name + '\n'
	}
	os.write_file(state + '/SHA256SUMS', sums)!
	println('ACCOUNT-UI-ARGV-PASS 256 fixed runs; redundant frees and borrowed config rejected')
	println('SHA256SUMS ' + sha256.sum(sums.bytes()).hex())
}

fn main() {
	run() or { eprintln(err); exit(1) }
}
