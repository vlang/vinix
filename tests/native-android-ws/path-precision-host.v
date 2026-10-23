// SPDX-License-Identifier: GPL-2.0-or-later
// Compile production path storage and animation sampling with checked allocators.
module main

import os
import crypto.sha256

fn path_function(body string, name string) string {
	marker := 'fn ' + name + '('
	start := body.index(marker) or { panic('missing ' + name) }
	tail := body[start..]
	end := tail.index('\nfn ') or { tail.len }
	return tail[..end] + '\n'
}

fn checked(args []string) {
	r := os.exec(args)
	print(r.output)
	if r.exit_code != 0 { exit(r.exit_code) }
}

fn main() {
	repo := os.real_path(os.dir(@FILE) + '/../..')
	mut source := repo + '/build-support/android/nativews'
	mut out := repo + '/build/android-path-precision-host'
	mut asan := false
	for arg in os.args[1..] {
		if arg.starts_with('source=') {
			source = os.abs_path(arg.all_after('source='))
		} else if arg.starts_with('out=') {
			out = os.abs_path(arg.all_after('out='))
		} else if arg == 'asan=true' {
			asan = true
		} else {
			panic('usage: path-precision-host [source=NATIVE_DIR] [out=OUTPUT_DIR] [asan=true]')
		}
	}
	os.mkdir_all(out + '/src')!
	mut hashes := ''
	for name in ['paths.v', 'path_curves.v', 'path_bounds.v', 'path_animation.v',
		'path_animation_curves.v', 'matrix.v'] {
		body := os.read_file(source + '/' + name)!
		mut actual := match name {
			'paths.v' { body.all_before('fn ws_path_round_rect(') }
			'path_bounds.v' { 'module main\n' + path_function(body, 'ws_path_control') }
			'matrix.v' {
				'module main\n' + body.all_after('module atlframework').all_before('type WsFloatRegion') + path_function(body, 'ws_matrix_map_point')
			}
			else { body }
		}
		actual = actual.replace('module atlframework', 'module main')
		for function in ['calloc', 'malloc', 'realloc', 'free'] {
			actual = actual.replace('C.' + function + '(', 'host_' + function + '(')
		}
		os.write_file(out + '/src/actual_' + name, actual)!
		os.write_file(out + '/' + name + '.txt', body)!
		hashes += sha256.sum(body.bytes()).hex() + '  ' + name + '\n'
	}
	os.write_file(out + '/source-sha256.txt', hashes)!
	os.cp(repo + '/tests/native-android-ws/pathprecisionhost/harness.v.txt', out + '/src/main.v')!
	println('PATH-PRECISION-HOST asan=' + asan.str())
	print(hashes)
	compiler := os.getenv_opt('VINIX_V_COMPILER') or { @VEXE }
	mut args := [compiler, '-nocache', '-cc', 'cc', '-enable-globals', '-gc', 'none']
	if asan {
		args << ['-cflags', '-fsanitize=address -fno-omit-frame-pointer', '-ldflags',
			'-fsanitize=address']
	}
	args << ['-o', out + '/host', out + '/src']
	checked(args)
	// V harness strings are unmanaged; production allocations have exact counters.
	if asan { os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true) }
	checked([out + '/host'])
}
