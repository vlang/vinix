// SPDX-License-Identifier: GPL-2.0-or-later
// Run the existing observer controls in both normal and production builds.
module main

import crypto.sha256
import json2
import os

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn execute(args []string, prefix string) !string {
	os.write_file(prefix + '.argv.json', json2.encode(args) + '\n')!
	result := os.exec(args)
	os.write_file(prefix + '.log', result.output)!
	os.write_file(prefix + '.status', result.exit_code.str() + '\n')!
	if result.exit_code != 0 { return error('failed command: ' + prefix + '\n' + result.output) }
	return result.output
}

fn run() ! {
	if os.args.len !in [1, 4] { return error('usage: heap-build-check [COMPILER ROOT FRESH_STATE]') }
	compiler := if os.args.len == 4 { os.real_path(os.args[1]) } else { @VEXE }
	root := if os.args.len == 4 { os.real_path(os.args[2]) } else { os.dir(os.dir(os.dir(@FILE))) }
	state := if os.args.len == 4 { os.abs_path(os.args[3]) } else {
		os.join_path(os.temp_dir(), 'vinix-heap-build-' + os.getpid().str())
	}
	if os.exists(state) || os.is_link(state) { return error('heap build state must be fresh') }
	os.mkdir_all(state)!
	mut inputs := map[string]string{}
	for name in ['heap-build-check.v', 'heap-selfcheck.v', 'heap-full-check.v',
		'heap-placement-check.v', 'reader-warm-check.v', 'stage-source.v', 'perfreport/core.v'] {
		path := root + '/tests/desktop-perf/' + name
		inputs[path] = digest(path)!
	}
	for folder in ['perfheap', 'heapfull', 'perfprotocol', 'perfsources'] {
		for path in os.walk_ext(root + '/tests/desktop-perf/' + folder, '.v') { inputs[path] = digest(path)! }
	}
	inputs[compiler] = digest(compiler)!
	os.write_file(state + '/inputs.json', json2.encode(inputs, prettify: true) + '\n')!
	// A failed selected compiler must fail the check, rather than trying a fallback.
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
	os.setenv('V_MACOS_V3_CALLER_NO_FALLBACK', '1', true)
	for schema in ['4k', '16k'] {
	for profile in ['normal', 'production'] {
		for target in ['heap-selfcheck', 'heap-full-check', 'heap-placement-check', 'reader-warm-check', 'stage-source'] {
			name := schema + '-' + profile + '-' + target
			binary := state + '/' + name
			mut args := [compiler, '-cc', 'cc']
			if schema == '16k' { args << ['-d', 'perf_slab16k'] }
			if profile == 'production' { args << '-prod' }
			args << ['-o', binary, root + '/tests/desktop-perf/' + target + '.v']
			execute(args, state + '/' + name + '-compile')!
			argument := if target == 'heap-selfcheck' { state + '/reader-' + schema + '-' + profile } else { 'selfcheck' }
			run_args := if target == 'stage-source' { [binary, 'selfcheck', state + '/source-' + schema + '-' + profile] } else { [binary, argument] }
			output := execute(run_args, state + '/' + name + '-run')!
			expected := if target == 'heap-selfcheck' {
				'PERF HEAP explicit parser/reader controls PASS ' + if schema == '4k' { '373' } else { '479' }
			} else if target == 'heap-full-check' {
				'PERF FULL HEAP explicit controls PASS ' + if schema == '4k' { '57' } else { '72' }
			} else if target == 'heap-placement-check' {
				'Placement checker controls PASS ' + if schema == '4k' { '156' } else { '187' }
			} else if target == 'reader-warm-check' {
				'PERF READER WARM controls PASS ' + if schema == '4k' { '94' } else { '93' }
			} else { 'PERF SOURCE snapshot controls PASS' }
			if output.trim_space() != expected { return error('incomplete observer controls: ' + name) }
			println(schema + ' ' + profile + ': ' + expected)
		}
	}
	}
	for profile in ['normal', 'production'] {
		for schema in ['4k', '16k'] {
			binary := state + '/' + schema + '-' + profile + '-heap-full-check'
			fixture := state + '/' + schema + '-' + profile + '.fixture'
			execute([binary, 'fixture', fixture], fixture + '-create')!
			execute([binary, 'check', fixture], fixture + '-check')!
			for count in [2, 3] {
				console := fixture + '-cr' + count.str()
				os.write_file(console, os.read_file(fixture)!.replace('\n', '\r'.repeat(count) + '\n'))!
				args := [binary, 'check', console]
				os.write_file(console + '.argv.json', json2.encode(args) + '\n')!
				result := os.exec(args)
				os.write_file(console + '.log', result.output)!
				os.write_file(console + '.status', result.exit_code.str() + '\n')!
				if (result.exit_code == 0) != (schema == '16k' && count == 2) { return error('console terminal sequence policy differs') }
			}
			other := state + '/' + if schema == '4k' { '16k' } else { '4k' } + '-' + profile + '-heap-full-check'
			args := [other, 'check', fixture]
			os.write_file(fixture + '-foreign.argv.json', json2.encode(args) + '\n')!
			result := os.exec(args)
			os.write_file(fixture + '-foreign.log', result.output)!
			os.write_file(fixture + '-foreign.status', result.exit_code.str() + '\n')!
			if result.exit_code == 0 { return error('foreign schema accepted') }
		}
	}
	for path, pin in inputs { if digest(path)! != pin { return error('changed build input: ' + path) } }
	os.write_file(state + '/result', 'PASS both schemas, normal/production observer controls and foreign-schema refusals\n')!
	println('PERF HEAP BUILD PASS; retained state: ' + state)
}

fn main() { run() or { eprintln(err); exit(1) } }
