// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise the production pipe decoder with stubbed JNI dispatch and local frames.
module main

import os
import crypto.sha256

fn checked(args []string) {
	r := os.exec(args)
	print(r.output)
	if r.exit_code != 0 { exit(r.exit_code) }
}

fn protocol_struct(body string, name string) string {
	marker := 'struct ' + name + ' {'
	assert body.count(marker) == 1
	return marker + body.all_after(marker).all_before('\n}') + '\n}\n'
}

fn main() {
	repo := os.real_path(os.dir(@FILE) + '/../..')
	mut source := repo + '/build-support/android/nativews/ws_views.v'
	mut out := repo + '/build/android-input-batch-host'
	mut asan := false
	for arg in os.args[1..] {
		if arg.starts_with('source=') {
			source = os.abs_path(arg.all_after('source='))
		} else if arg.starts_with('out=') {
			out = os.abs_path(arg.all_after('out='))
		} else if arg == 'asan=true' {
			asan = true
		} else {
			panic('usage: input-batch-host [source=WS_VIEWS_SOURCE] [out=OUTPUT_DIR] [asan=true]')
		}
	}
	compiler := os.getenv_opt('VINIX_V_COMPILER') or { @VEXE }
	body := os.read_file(source)!
	start := body.index('fn ws_input(e voidptr) {') or { panic('missing production ws_input') }
	actual := body[start..]
	assert actual.count('fn ws_input(') == 1
	assert actual.count('C.read(ws.input, &event, sizeof(WsEvent))') == 1
	runtime := os.read_file(repo + '/build-support/android/nativews/runtime.v')!
	os.mkdir_all(out + '/src')!
	os.write_file(out + '/src/actual_input.v', 'module main\n' + actual)!
	os.write_file(out + '/src/actual_protocol.v', 'module main\n' + protocol_struct(runtime, 'WsPoll') + protocol_struct(runtime, 'WsEvent'))!
	os.cp(repo + '/tests/native-android-ws/inputbatchhost/harness.v.txt', out + '/src/main.v')!
	os.write_file(out + '/ws_views.v.txt', body)!
	os.write_file(out + '/source-sha256.txt', sha256.sum(body.bytes()).hex() + '\n')!
	println('INPUT-HOST source=' + sha256.sum(body.bytes()).hex() + ' asan=' + asan.str())
	mut args := [compiler, '-nocache', '-cc', 'cc', '-enable-globals', '-gc', 'none']
	if asan {
		args << ['-cflags', '-fsanitize=address -fno-omit-frame-pointer', '-ldflags',
			'-fsanitize=address']
	}
	args << ['-o', out + '/host', out + '/src']
	checked(args)
	// Disable leak checks for unmanaged V harness allocations.
	if asan { os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true) }
	checked([out + '/host'])
}
