// SPDX-License-Identifier: GPL-2.0-or-later
// Compile the production polygon operation with checked native allocations.
module main

import crypto.sha256
import os

fn function(body string, name string) string {
	start := body.index('fn ' + name + '(') or { panic('missing function ' + name) }
	tail := body[start..]
	end := tail.index('\nfn ') or { tail.len }
	return tail[..end] + '\n'
}

fn structure(body string, name string) string {
	start := body.index('struct ' + name + ' {') or { panic('missing struct ' + name) }
	tail := body[start..]
	end := tail.index('\n}') or { panic('unterminated struct ' + name) }
	return tail[..end + 3] + '\n'
}

fn checked(args []string, output string) int {
	r := os.exec(args)
	os.write_file(output, r.output) or { panic(err) }
	print(r.output)
	return r.exit_code
}

fn inventory(root string, relative string, mut entries map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		path := root + '/' + key
		match os.lstat(path)!.get_filetype() {
			.regular { entries[key] = sha256.sum(os.read_bytes(path)!).hex() }
			.directory { inventory(root, key, mut entries)! }
			else { return error('unexpected artifact: ' + path) }
		}
	}
}

fn manifest(root string) !string {
	mut entries := map[string]string{}
	inventory(root, '', mut entries)!
	entries.delete('evidence-sha256.txt')
	mut names := entries.keys()
	names.sort()
	mut result := ''
	for name in names { result += entries[name] + '  ' + name + '\n' }
	return result
}

fn seal(root string) ! {
	assert !os.exists(root + '/evidence-sha256.txt'), 'bundle already sealed'
	evidence := manifest(root)!
	os.write_file(root + '/evidence-sha256.txt', evidence)!
	println('PATH-OPS-HOST evidence=' + sha256.sum(evidence.bytes()).hex())
}

fn main() {
	// Readback is read-only and checks every regular artifact, including extras.
	if os.args.len == 3 && os.args[1].starts_with('verify=') && os.args[2].starts_with('pin=') {
		root, pin := os.args[1].all_after('verify='), os.args[2].all_after('pin=')
		evidence := os.read_file(root + '/evidence-sha256.txt')!
		assert pin.len == 64 && sha256.sum(evidence.bytes()).hex() == pin, 'wrong evidence pin'
		assert manifest(root)! == evidence, 'bundle does not match complete inventory'
		println('PATH-OPS-HOST READBACK PASS ' + pin)
		return
	}
	// Preserve failed reproducer bundles using the same complete inventory.
	if os.args.len == 2 && os.args[1].starts_with('seal=') {
		seal(os.args[1].all_after('seal='))!
		return
	}
	repo := os.real_path(os.dir(@FILE) + '/../..')
	mut source := repo + '/build-support/android/nativews'
	state := os.getenv('XDG_STATE_HOME')
	state_root := if state == '' { os.home_dir() + '/.local/state' } else { os.abs_path(state) }
	mut out := state_root + '/vinix/android/path-ops-host'
	mut asan := false
	for arg in os.args[1..] {
		if arg.starts_with('source=') { source = os.abs_path(arg.all_after('source=')) }
		else if arg.starts_with('out=') { out = os.abs_path(arg.all_after('out=')) }
		else if arg == 'asan=true' { asan = true }
		else { panic('usage: path-ops-host [source=NATIVE_DIR] [out=OUTPUT_DIR] [asan=true]') }
	}
	if os.exists(out) || os.is_link(out) { panic('fresh output root required: ' + out) }
	os.mkdir_all(out + '/src')!
	os.write_file(out + '/runner.v.txt', os.read_file(@FILE)!)!
	os.cp(os.executable(), out + '/runner')!
	mut hashes := ''
	for name in ['paths.v', 'path_curves.v', 'path_bounds.v', 'path_animation_curves.v', 'path_ops.v'] {
		body := os.read_file(source + '/' + name)!
		os.write_file(out + '/' + name + '.txt', body)!
		hashes += sha256.sum(body.bytes()).hex() + '  ' + name + '\n'
		mut actual := 'module main\n'
		match name {
			'paths.v' {
				actual += structure(body, 'WsVertex') + structure(body, 'WsPath')
				for symbol in ['ws_path_new', 'ws_path_unref', 'ws_path_ref', 'ws_path_point',
					'ws_path_close', 'ws_path_rect'] { actual += function(body, symbol) }
			}
			'path_curves.v' {
				for symbol in ['ws_path_last', 'ws_cubic_segment', 'ws_path_cubic', 'ws_path_quad'] {
					actual += function(body, symbol)
				}
			}
			'path_bounds.v' { actual += function(body, 'ws_path_control') }
			'path_animation_curves.v' {
				actual += structure(body, 'WsPathCurve') + function(body, 'ws_path_curve_append')
			}
			'path_ops.v' { actual += body.all_after('module atlframework') }
			else {}
		}
		for allocation in ['malloc', 'calloc', 'realloc', 'free'] {
			actual = actual.replace('C.' + allocation + '(', 'host_' + allocation + '(')
		}
		os.write_file(out + '/src/actual_' + name, actual)!
	}
	os.write_file(out + '/source-sha256.txt', hashes)!
	harness := repo + '/tests/native-android-ws/pathopshost/harness.v.txt'
	os.cp(harness, out + '/src/main.v')!
	os.cp(harness, out + '/harness.v.txt')!
	compiler := os.getenv_opt('VINIX_V_COMPILER') or { @VEXE }
	os.cp(compiler, out + '/compiler')!
	os.write_file(out + '/compiler-sha256.txt', sha256.sum(os.read_bytes(compiler)!).hex() + '  ' + compiler + '\n')!
	mut args := [compiler, '-nocache', '-keepc', '-cc', 'cc', '-enable-globals', '-gc', 'none', '-cflags', '-O2']
	if asan { args << ['-cflags', '-fsanitize=address -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address'] }
	args << ['-o', out + '/host', out + '/src']
	os.write_file(out + '/compile-argv.txt', args.join('\n') + '\n')!
	println('PATH-OPS-HOST asan=' + asan.str())
	print(hashes)
	compile_exit := checked(args, out + '/compile.log')
	if asan { os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true) }
	run_exit := if compile_exit == 0 { checked([out + '/host'], out + '/run.log') } else { -1 }
	os.write_file(out + '/result.txt', 'compile_exit=${compile_exit}\nrun_exit=${run_exit}\n')!
	seal(out)!
	if compile_exit != 0 { exit(compile_exit) }
	if run_exit != 0 { exit(run_exit) }
}
