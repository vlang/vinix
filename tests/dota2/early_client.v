// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise production V constructor ABI and environment/library lifetimes.
module main

import hosttest
import os

struct Case {
	value    string
	set      bool
	mode     string
	expected int
}

fn run(baseline string, has_baseline bool) ! {
	root := hosttest.root()
	work := hosttest.work_dir('', 'vinix-dota-early-')!
	defer { os.rmdir_all(work) or { eprintln(err) } }
	arch := if os.uname().machine in ['arm64', 'aarch64'] { 'arm64' } else { 'amd64' }
	flags := [hosttest.env_default('CC', 'clang'), '-O2', '-g', '-Wall', '-Wextra', '-Werror',
		'-Wno-unused-function', '-Wno-unused-label', '-Wno-unused-parameter',
		'-fsanitize=address,undefined', '-fno-omit-frame-pointer']
	aliases := ['-Ddlopen=fixture_dlopen', '-Ddlerror=fixture_dlerror', '-Dunsetenv=fixture_unsetenv']
	hosttest.generate_module(root + '/tests/dota2/earlyfixture', work + '/fixture.c', arch, []string{})!
	hosttest.command([...flags, '-c', work + '/fixture.c', '-o', work + '/fixture.o'], '', -1, os.environ())!
	mut artifacts := [work + '/production.c']
	hosttest.generate_module(root + '/build-support/dota2/earlycore', artifacts[0], arch, ['nofloat'])!
	if has_baseline { artifacts << hosttest.module_resolve(baseline)! }
	cases := [Case{'', false, 'skip', 0}, Case{'', true, 'skip', 0},
		Case{'/actual/client.so', true, 'ok', 0}, Case{'/' + 'a'.repeat(4094), true, 'ok', 0},
		Case{'/' + 'a'.repeat(4095), true, 'ok', 127}, Case{'relative/client.so', true, 'ok', 127},
		Case{'/actual/client.so', true, 'unsetfail', 127}, Case{'/actual/client.so', true, 'loadfail', 127},
		Case{'/actual/client.so', true, 'nullerror', 127}]
	mut results := [][]hosttest.Result{}
	for index, source in artifacts {
		object := work + '/production-' + index.str() + '.o'
		hosttest.command([...flags, ...aliases, '-I', root + '/build-support/dota2', '-c', source, '-o', object], '', -1, os.environ())!
		imports := hosttest.command(['nm', '-u', object], '', -1, os.environ())!.stdout
		if hosttest.allocation_symbols(imports) { return error(imports) }
		executable := work + '/test-' + index.str()
		hosttest.command([...flags, work + '/fixture.o', object, '-o', executable], '', -1, os.environ())!
		mut observed := []hosttest.Result{}
		for item in cases {
			mut env := os.environ()
			env['EARLY_FIXTURE_MODE'] = item.mode
			env['EARLY_FIXTURE_PATH'] = item.value
			env.delete('VINIX_DOTA2_EARLY_STEAMCLIENT')
			if item.set { env['VINIX_DOTA2_EARLY_STEAMCLIENT'] = item.value }
			result := hosttest.capture([executable], '', -1, env)!
			if result.code != item.expected { return error('${index} ${item.mode}: ${result.code}\n${result.stderr}') }
			if item.expected == 0 && item.mode != 'skip' {
				loader := result.stderr.index('loader before main') or { return error('Missing loader marker') }
				client := result.stderr.index('EARLY-CLIENT') or { return error('Missing client marker') }
				main_marker := result.stderr.index('EARLY-FIXTURE: main') or { return error('Missing main marker') }
				if !(loader < client && client < main_marker) { return error('Invalid pre-main order') }
			} else if item.expected == 127 && result.stderr.contains('EARLY-FIXTURE: main') {
				return error('Failed constructor reached main')
			}
			observed << result
		}
		results << observed
	}
	if results.len == 2 && results[0] != results[1] { return error('Production V and frozen original C differ') }
	println('Early Steam loader: 9 constructor/path/error cases, overwritten environment storage, fixed NODELETE flags and pre-main order PASS')
}

fn main() {
	args := hosttest.parse_arguments(os.args[1..], [hosttest.Option{'--baseline', true, []string{}}],
		0, 'Usage: early_client.v [--baseline SOURCE]',
		'Exercise production V constructor ABI and environment/library lifetimes.') or { eprintln(err); exit(2) }
	run(args.options['--baseline'] or { '' }, '--baseline' in args.options) or { eprintln(err); exit(1) }
}
