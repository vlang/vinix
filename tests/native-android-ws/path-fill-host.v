// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise the production path rasterizer and Canvas composition on host pixels.
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

fn checked(args []string, output string) {
	r := os.exec(args)
	os.write_file(output, r.output) or { panic(err) }
	print(r.output)
	if r.exit_code != 0 { exit(r.exit_code) }
}

fn main() {
	repo := os.real_path(os.dir(@FILE) + '/../..')
	mut source := repo + '/build-support/android/nativews'
	mut out := repo + '/build/android-path-fill-host'
	mut asan := false
	for arg in os.args[1..] {
		if arg.starts_with('source=') {
			source = os.abs_path(arg.all_after('source='))
		} else if arg.starts_with('out=') {
			out = os.abs_path(arg.all_after('out='))
		} else if arg == 'asan=true' {
			asan = true
		} else {
			panic('usage: path-fill-host [source=NATIVE_DIR] [out=OUTPUT_DIR] [asan=true]')
		}
	}
	os.mkdir_all(out + '/src')!
	mut hashes := ''
	mut files := ['runner.v.txt', 'source-sha256.txt', 'compile.log', 'run.log', 'host', 'src/main.v']
	os.write_file(out + '/runner.v.txt', os.read_file(@FILE)!)!
	for name in ['paths.v', 'graphics.v', 'canvases.v', 'affine.v', 'path_clipping.v', 'bitmaps.v'] {
		body := os.read_file(source + '/' + name)!
		mut actual := 'module main\n'
		match name {
			'paths.v' {
				actual += body.all_after('module atlframework').all_before('fn ws_path_new(')
				for symbol in ['ws_path_new', 'ws_path_unref', 'ws_path_point', 'ws_path_close',
					'ws_path_rect', 'ws_draw_path'] {
					actual += function(body, symbol)
				}
			}
			'graphics.v' {
				actual += structure(body, 'WsTransform') + structure(body, 'WsPaint')
				for symbol in ['ws_blend', 'ws_rect', 'ws_canvas_line', 'ws_save', 'ws_restore',
					'ws_clip'] {
					actual += function(body, symbol)
				}
			}
			'canvases.v' { actual += structure(body, 'WsDrawState') }
			'affine.v' {
				actual += structure(body, 'WsClipQuad')
				for symbol in ['ws_affine_point', 'ws_affine_inverse', 'ws_affine_bounds',
					'ws_affine_clip'] {
					actual += function(body, symbol)
				}
			}
			'path_clipping.v' { actual += body.all_after('module atlframework') }
			'bitmaps.v' { actual += structure(body, 'WsBitmap') }
			else {}
		}
		// Count only production allocations, including both temporary fill buffers.
		for allocation in ['malloc', 'calloc', 'realloc', 'free'] {
			actual = actual.replace('C.' + allocation + '(', 'host_' + allocation + '(')
		}
		os.write_file(out + '/src/actual_' + name, actual)!
		os.write_file(out + '/' + name + '.txt', body)!
		files << ['src/actual_' + name, name + '.txt']
		hashes += sha256.sum(body.bytes()).hex() + '  ' + name + '\n'
	}
	os.write_file(out + '/source-sha256.txt', hashes)!
	os.cp(repo + '/tests/native-android-ws/pathfillhost/harness.v.txt', out + '/src/main.v')!
	println('PATH-FILL-HOST asan=' + asan.str())
	print(hashes)
	compiler := os.getenv_opt('VINIX_V_COMPILER') or { @VEXE }
	mut args := [compiler, '-nocache', '-cc', 'cc', '-enable-globals', '-gc', 'none']
	if asan {
		args << ['-cflags', '-fsanitize=address -fno-omit-frame-pointer', '-ldflags',
			'-fsanitize=address']
	}
	args << ['-o', out + '/host', out + '/src']
	checked(args, out + '/compile.log')
	if asan { os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true) }
	checked([out + '/host'], out + '/run.log')
	mut evidence := ''
	for name in files {
		evidence += sha256.sum(os.read_bytes(out + '/' + name)!).hex() + '  ' + name + '\n'
	}
	os.write_file(out + '/evidence-sha256.txt', evidence)!
	println('PATH-FILL-HOST evidence=' + sha256.sum(evidence.bytes()).hex())
}
