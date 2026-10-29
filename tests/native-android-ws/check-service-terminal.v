// SPDX-License-Identifier: GPL-2.0-or-later
// Execute the production observer, including an exit inside exception reporting.
module main

import os

fn terminal_block(source string, name string) !string {
	start := source.index('fn ' + name + '(') or { return error('missing ' + name) }
	end := source[start..].index('\n}') or { return error('unclosed ' + name) }
	return source[start..start + end + 2]
}

fn terminal_contract(source string) bool {
	fail := terminal_block(source, 'ws_service_terminal_fail') or { return false }
	report := terminal_block(source, 'ws_service_failure') or { return false }
	main_fn := terminal_block(source, 'ws_service_main') or { return false }
	if !fail.contains('if !ws_service_terminal_recorded') || !fail.contains('C.write(2, buffer, usize(n))')
		|| !fail.contains('C.alloca(128)') || !fail.contains('n > 0 && n < 128') {
		return false
	}
	for forbidden in ['C.malloc', 'C.calloc', 'new_object(', 'obj(', 'call(', 'static_void(',
		'println(', 'C.puts(', 'C.printf(', 'C.getenv(', 'setThreadPolicy', '[]'] {
		if fail.contains(forbidden) { return false }
	}
	if !report.contains('if pending(e) { ws_service_terminal_fail(phase, reason) }')
		|| !report.ends_with('return ws_failure(e, stage)\n}') { return false }
	reset := main_fn.index('ws_service_terminal_recorded = false') or { return false }
	first_check := main_fn.index('ws_service_channel(control_fd)') or { return false }
	if reset >= first_check { return false }
	for name in ['ws_service_run', 'ws_service_shutdown', 'ws_service_main'] {
		body := terminal_block(source, name) or { return false }
		if body.contains('return 1') || body.contains('ws_failure(') { return false }
	}
	return true
}

fn main() {
	assert os.args.len == 2, 'usage: check-service-terminal FRESH_EXTERNAL_OUTPUT'
	root := os.args[1]
	assert os.is_abs_path(root) && !os.exists(root) && !os.is_link(root)
	assert os.real_path(os.dir(root)) == os.dir(root)
	assert !root.starts_with(os.real_path(os.getwd()) + '/')
	source := os.read_file('build-support/android/nativews/headless.v')!
	assert terminal_contract(source)
	for mutation in [source.replace('if !ws_service_terminal_recorded', 'if true'),
		source.replace('C.write(2, buffer, usize(n))', 'C.puts(buffer)'),
		source.replace('C.alloca(128)', 'C.malloc(128)'),
		source.replace('ws_service_terminal_recorded = false', 'ws_service_terminal_recorded = true'),
		source.replace('if pending(e) { ws_service_terminal_fail(phase, reason) }', '')] {
		assert mutation != source && !terminal_contract(mutation)
	}
	os.mkdir(root)!
	os.write_file(root + '/input-headless.v', source)!
	os.cp(@FILE, root + '/input-checker.v')!
	helpers := terminal_block(source, 'ws_service_terminal_fail')! + '\n' +
		terminal_block(source, 'ws_service_failure')!
	compiler := os.getenv_opt('VINIX_V_COMPILER') or { 'v' }
	for scenario in ['quiet', 'first', 'describe-exits', 'reset'] {
		folder := root + '/' + scenario
		os.mkdir(folder)!
		os.write_file(folder + '/main.v', terminal_model + helpers + '\nfn main() {\n' + match scenario {
			'quiet' { 'assert !ws_service_failure(nil, c"stage", 6, 1)\n' }
			'first' { 'assert ws_service_terminal_fail(2, 1) == 1\nassert ws_service_terminal_fail(4, 5) == 1\n' }
			'describe-exits' { 'probe_pending = true\nws_service_failure(nil, c"stage", 6, 1)\nassert false\n' }
			else { 'ws_service_terminal_fail(2, 4)\nws_service_terminal_recorded = false\nws_service_terminal_fail(3, 6)\n' }
		} + '\n}\n')!
		args := [compiler, '-w', '-n', '-enable-globals', '-cc', 'cc', '-o', folder + '/probe', folder + '/main.v']
		built := os.exec(args)
		os.write_file(folder + '/build.log', built.output)!
		assert built.exit_code == 0, 'probe build failed; see ${folder}/build.log'
		result := os.exec([folder + '/probe'])
		os.write_file(folder + '/command.log', result.output)!
		expected := match scenario {
			'quiet' { '' }
			'first' { 'ANDROID-SERVICE-EXIT phase=2 reason=1 status=1\n' }
			'describe-exits' { 'ANDROID-SERVICE-EXIT phase=6 reason=1 status=1\nDESCRIBE-EXITS\n' }
			else { 'ANDROID-SERVICE-EXIT phase=2 reason=4 status=1\nANDROID-SERVICE-EXIT phase=3 reason=6 status=1\n' }
		}
		assert result.output == expected, '${scenario}: unexpected output retained in ${folder}'
		assert result.exit_code == if scenario == 'describe-exits' { 73 } else { 0 }
	}
	println('SERVICE-TERMINAL-PASS quiet first-cause bounded-write reset describe-exits-status73 negative-mutations=5')
}

const terminal_model = '
module main
#include <alloca.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
fn C.alloca(usize) voidptr
fn C.exit(int)
__global ws_service_terminal_recorded bool
__global probe_pending bool
fn pending(e voidptr) bool { return probe_pending }
fn ws_failure(e voidptr, stage &char) bool {
 if !probe_pending { return false }
 C.write(2, c"DESCRIBE-EXITS\\n", 15)
 C.exit(73)
 return true
}
'
