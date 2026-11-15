// SPDX-License-Identifier: GPL-2.0-or-later
// Keep refusal checks live under -prod; mutations touch only private fixtures.
module main

import os
import json2
import crypto.sha256

struct Helper {
	name string
	file string
	before string
	after string
}

fn digest(path string) !string { return sha256.hexhash(os.read_file(path)!) }

fn invoke(args []string, env map[string]string, directory string, log string) !(int, string) {
	os.write_file(log + '.argv.json', json2.encode(args) + '\n')!
	mut child := os.new_process(args[0])
	defer { child.close() }
	child.set_args(args[1..]); child.set_environment(env); child.set_work_folder(directory)
	child.set_redirect_stdio_merged(); child.run()
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	output := child.stdout_slurp(); child.wait()
	os.write_file(log, output)!
	return child.code, output
}

fn run() ! {
	$if prod {} $else { return error('compile helper control driver with -prod') }
	if digest(@FILE)! != sha256.hexhash($embed_file('wine-helper-controls-check.v').to_string()) {
		return error('compiled helper control driver source differs')
	}
	if os.args.len !in [3, 4] { return error('usage: CHECK V FRESH_OUTPUT [REAL_LINK_ARGV_JSON]') }
	tool := os.real_path(os.args[1])
	root := os.real_path(os.dir(@FILE) + '/../..')
	out := os.abs_path(os.args[2])
	if os.exists(out) || os.is_link(out) { return error('fresh helper control output required') }
	if !os.is_file('/opt/homebrew/opt/llvm/bin/clang') || !os.is_file('/opt/homebrew/bin/ld.lld') {
		return error('real pinned Clang/LLD controls are required')
	}
	helpers := [
		Helper{'winesource', 'closure', 'if path !in inputs || inputs[path] != value', 'if false'},
		Helper{'wineheaders', 'headers', 'if path !in inputs || inputs[path] != hash', 'if false'},
		Helper{'winecsource', 'closure', "if text.contains('\\r') || text.contains('\\x00')", 'if false'},
		Helper{'winelink', 'link', "return error('link response contains unsupported argument')", 'continue'},
		Helper{'winehostimages', 'images', 'else if image.path !in known || image != known[image.path]', 'else if false'},
	]
	os.mkdir_all(out)!
	mut pins := {os.real_path(@FILE): digest(@FILE)!, tool: digest(tool)!}
	fixture := out + '/fixture'
	for helper in helpers {
		for suffix in ['.v', '_test.v'] {
			relative := 'tests/packages/' + helper.name + '/' + helper.file + suffix
			path := root + '/' + relative
			text := os.read_file(path)!
			if suffix == '_test.v' {
				for line in text.split_into_lines() {
					if line.trim_space().starts_with('assert ') { return error('helper controls must use explicit checks: ' + path) }
				}
			}
			pins[path] = digest(path)!
			os.mkdir_all(os.dir(fixture + '/' + relative))!
			os.write_file(fixture + '/' + relative, text)!
		}
	}
	if os.args.len == 4 { pins[os.real_path(os.args[3])] = digest(os.args[3])! }
	os.write_file(out + '/inputs-before.json', json2.encode(pins) + '\n')!
	mut env := os.environ()
	env.delete('VFLAGS'); env.delete('VINIX_HOST_IMAGE_TEST_STATE'); env.delete('VINIX_V_HOST_TEST_STATE')
	env.delete('VINIX_LINK_PROBE_ARGV'); env.delete('VINIX_LINK_PROBE_OUTPUT')
	env['VEXE'] = tool; env['V_MACOS_V3_CALLER_VEXE'] = tool
	env['V_MACOS_V3_CALLER_VEXE_PRESENT'] = '1'; env['V_MACOS_V3_CALLER_VCHILD_PRESENT'] = '0'
	env['V_MACOS_V3_NO_FALLBACK'] = '1'
	mut passed := []string{}
	for helper in helpers {
		for mode in ['normal', 'prod', 'mutant-prod'] {
			directory := out + '/' + helper.name + '-' + mode
			os.mkdir_all(directory)!
			mut selected := fixture
			if mode == 'mutant-prod' {
				selected = directory + '/fixture'
				os.cp_all(fixture, selected, false)!
				path := selected + '/tests/packages/' + helper.name + '/' + helper.file + '.v'
				original := os.read_file(path)!
				if original.count(helper.before) != 1 { return error('helper mutation anchor differs: ' + helper.name) }
				os.write_file(path, original.replace(helper.before, helper.after))!
			}
			mut args := [tool, '-backend', 'c', '-gc', 'none', '-manualfree', '-cflags', '-fno-lto',
				'-path', '@vlib|' + selected + '|@vmodules', '-o', directory + '/check',
				selected + '/tests/packages/' + helper.name + '/' + helper.file + '_test.v']
			if mode != 'normal' { args.insert(1, '-prod') }
			code, _ := invoke(args, env, selected, directory + '/compile.log')!
			if code != 0 { return error('helper control compilation failed: ' + directory) }
			mut test_env := env.clone()
			test_env['VINIX_HOST_IMAGE_TEST_STATE'] = directory + '/clang-state'
			test_env['VINIX_V_HOST_TEST_COMPILER'] = tool
			test_env['VINIX_V_HOST_TEST_STATE'] = directory + '/v-state'
			if os.args.len == 4 && mode != 'mutant-prod' {
				test_env['VINIX_LINK_PROBE_ARGV'] = os.real_path(os.args[3])
				test_env['VINIX_LINK_PROBE_OUTPUT'] = directory + '/link-state'
			}
			status, output := invoke([directory + '/check'], test_env, selected, directory + '/run.log')!
			if mode == 'mutant-prod' {
				if status == 0 || !output.contains('WINE helper expected refusal') {
					return error('helper safety mutation was not detected at its explicit refusal check: ' + directory)
				}
			} else if status != 0 { return error('helper controls failed: ' + directory) }
			passed << helper.name + '-' + mode
			println('WINE HELPER CONTROL PASS ' + passed.last())
		}
	}
	for path, expected in pins { if digest(path)! != expected { return error('helper control input changed: ' + path) } }
	os.write_file(out + '/inputs-verified.json', json2.encode(pins) + '\n')!
	os.write_file(out + '/result.json', json2.encode(passed) + '\n')!
	println('WINE HELPER CONTROLS PASS ten normal/production suites and five production safety mutations')
}

fn main() { run() or { eprintln(err); exit(1) } }
