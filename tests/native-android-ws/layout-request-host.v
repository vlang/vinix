// SPDX-License-Identifier: GPL-2.0-or-later
// Execute the production WS traversal with controlled JNI callbacks, not Android.
module main

import crypto.sha256
import json2
import os

fn extracted(source string, marker string, next string) string {
	assert source.count(marker) == 1, marker
	assert source.count(next) == 1, next
	return marker + source.all_after(marker).all_before(next)
}

fn structure(source string, name string) string {
	marker := 'struct ' + name + ' {'
	assert source.count(marker) == 1
	return marker + source.all_after(marker).all_before('\n}') + '\n}\n'
}

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn inventory(root string, relative string, mut pins map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		path := root + '/' + key
		match os.lstat(path)!.get_filetype() {
			.directory { inventory(root, key, mut pins)! }
			.regular { pins[key] = hash(path)! }
			else { return error('nonregular output: ' + path) }
		}
	}
}

struct Receipt {
	scope string
	source_directory string
	binding_path string
	inputs_before map[string]string
	inputs_after map[string]string
	runner_sha256 string
	compiler_sha256 string
	compiler_sha256_after string
	build_argv []string
	build_exit int
	run_argv []string
	run_exit int
}

fn main() {
	$if prod { panic('assertions required; compile without -prod') }
	repo := os.real_path(os.dir(@FILE) + '/../..')
	mut source := repo + '/build-support/android/nativews'
	mut out := ''
	mut binding_path := ''
	mut scenario := 'all'
	for arg in os.args[1..] {
		if arg.starts_with('source=') { source = os.abs_path(arg.all_after('source=')) }
		else if arg.starts_with('out=') { out = os.abs_path(arg.all_after('out=')) }
		else if arg.starts_with('case=') { scenario = arg.all_after('case=') }
		else if arg.starts_with('bindings=') { binding_path = os.abs_path(arg.all_after('bindings=')) }
		else { panic('usage: layout-request-host out=FRESH_DIR [source=NATIVEWS_DIR] [bindings=BINDINGS_TXT] [case=SCENARIO]') }
	}
	if binding_path == '' { binding_path = source + '/bindings.txt' }
	assert out != '' && !os.exists(out) && !os.is_link(out), 'fresh output required'
	assert !out.starts_with(repo + '/') || out.contains('/results/'), 'use external output or ignored results'
	os.mkdir_all(out + '/src')!
	os.mkdir_all(out + '/inputs')!
	mut pins := map[string]string{}
	for name in ['ws_views.v', 'ws_dialogs.v', 'runtime.v'] {
		pins[name] = hash(source + '/' + name)!
		os.cp(source + '/' + name, out + '/inputs/' + name)!
	}
	pins['bindings.txt'] = hash(binding_path)!
	os.cp(binding_path, out + '/inputs/bindings.txt')!
	harness_path := repo + '/tests/native-android-ws/layoutrequesthost/harness.v.txt'
	pins['harness.v.txt'] = hash(harness_path)!
	os.cp(harness_path, out + '/src/main.v')!
	os.cp(@FILE, out + '/runner.v')!
	views := os.read_file(out + '/inputs/ws_views.v')!
	dialogs := os.read_file(out + '/inputs/ws_dialogs.v')!
	runtime := os.read_file(out + '/inputs/runtime.v')!
	bindings := os.read_file(out + '/inputs/bindings.txt')!
	mut methods := extracted(views, 'fn ws_mark()', '\nfn ws_set_text(')
	methods += extracted(views, 'fn ws_dispatch_traversal(', '\nfn ws_debug_tree(')
	// Opt-in native diagnostics do not participate in traversal decisions.
	methods += '\nfn ws_trace_traversal(_ bool, _ bool) {}\nfn ws_trace_publication() {}\n'
	assert dialogs.count('fn ws_render_dialog(') == 1
	methods += 'fn ws_render_dialog(' + dialogs.all_after('fn ws_render_dialog(')
	// Read the native entry point from the selected production bindings too.
	entry := bindings.split_into_lines().filter(it.starts_with('android/view/View|native_requestLayout|'))
	assert entry.len == 1
	methods += '\nfn native_request_layout() { ' + entry[0].all_after('android/view/View|native_requestLayout|') + ' }\n'
	os.write_file(out + '/src/actual.v', 'module main\n' + structure(runtime, 'WsSurface') +
		structure(runtime, 'WsState') + methods)!
	compiler := os.real_path(os.getenv_opt('VINIX_V_COMPILER') or { @VEXE })
	compiler_before := hash(compiler)!
	// Keep compiler intermediates inside this fresh evidence directory too.
	os.mkdir_all(out + '/tmp')!
	os.setenv('VTMP', out + '/tmp', true)
	argv := [compiler, '-nocache', '-keepc', '-showcc', '-cc', 'cc', '-enable-globals', '-gc', 'none',
		'-o', out + '/host', out + '/src']
	build := os.exec(argv)
	os.write_file(out + '/build.log', build.output)!
	print(build.output)
	mut run_exit := -1
	if build.exit_code == 0 {
		run := os.exec([out + '/host', scenario])
		os.write_file(out + '/run.log', run.output)!
		print(run.output)
		run_exit = run.exit_code
	}
	mut after := map[string]string{}
	for name in ['ws_views.v', 'ws_dialogs.v', 'runtime.v'] {
		after[name] = hash(source + '/' + name)!
	}
	after['bindings.txt'] = hash(binding_path)!
	after['harness.v.txt'] = hash(harness_path)!
	os.write_file(out + '/receipt.json', json2.encode(Receipt{
		scope: 'Host execution of production native traversal with stubbed JNI and drawing; no ART or Maps qualification'
		source_directory: source
		binding_path: binding_path
		inputs_before: pins
		inputs_after: after
		runner_sha256: hash(@FILE)!
		compiler_sha256: compiler_before
		compiler_sha256_after: hash(compiler)!
		build_argv: argv
		build_exit: build.exit_code
		run_argv: [out + '/host', scenario]
		run_exit: run_exit
	}, prettify: true) + '\n')!
	assert pins == after, 'source changed during host test'
	assert compiler_before == hash(compiler)!, 'compiler changed'
	mut manifest := map[string]string{}
	inventory(out, '', mut manifest)!
	os.write_file(out + '/sha256.json', json2.encode(manifest, prettify: true) + '\n')!
	println('LAYOUT-REQUEST-HOST-SEAL ' + hash(out + '/sha256.json')!)
	if build.exit_code != 0 { exit(build.exit_code) }
	exit(run_exit)
}
