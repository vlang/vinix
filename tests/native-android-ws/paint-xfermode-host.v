// SPDX-License-Identifier: GPL-2.0-or-later
// Compile the production bitmap compositor against an in-memory host Canvas.
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

fn checked(args []string, log string) {
	r := os.exec(args)
	os.write_file(log, r.output) or { panic(err) }
	print(r.output)
	if r.exit_code != 0 { exit(r.exit_code) }
}

fn main() {
	repo := os.real_path(os.dir(@FILE) + '/../..')
	mut source := repo + '/build-support/android/nativews'
	mut out := repo + '/tests/native-android-ws/results/paint-xfermode-host'
	mut asan := false
	for arg in os.args[1..] {
		if arg.starts_with('source=') { source = os.abs_path(arg.all_after('source=')) }
		else if arg.starts_with('out=') { out = os.abs_path(arg.all_after('out=')) }
		else if arg == 'asan=true' { asan = true }
		else { panic('usage: paint-xfermode-host [source=NATIVE_DIR] [out=OUTPUT_DIR] [asan=true]') }
	}
	os.mkdir_all(out + '/src')!
	mut hashes := ''
	mut files := ['source-sha256.txt', 'compile.log', 'run.log', 'src/main.v']
	for name in ['graphics.v', 'bitmaps.v', 'canvases.v', 'affine.v', 'paths.v', 'path_clipping.v'] {
		body := os.read_file(source + '/' + name)!
		mut actual := '@[translated]\nmodule main\n'
		match name {
			'graphics.v' {
				actual += structure(body, 'WsTransform') + structure(body, 'WsPaint')
				// Older captured graphics inputs predate the clipped bound helper.
				if body.contains('fn ws_rect_bound(') { actual += function(body, 'ws_rect_bound') }
				for symbol in ['ws_blend', 'ws_rect', 'ws_round_inset', 'ws_canvas_round_rect', 'ws_paint_new', 'ws_paint_clone'] {
					actual += function(body, symbol)
				}
			}
			'bitmaps.v' {
				actual += structure(body, 'WsBitmap')
				for symbol in ['ws_bitmap_dst_in', 'ws_draw_bitmap_region', 'ws_draw_bitmap_paint', 'ws_draw_bitmap'] {
					actual += function(body, symbol)
				}
			}
			'canvases.v' { actual += structure(body, 'WsDrawState') }
			'affine.v' {
				actual += structure(body, 'WsClipQuad')
				for symbol in ['ws_affine_point', 'ws_affine_inverse', 'ws_affine_bounds', 'ws_affine_clip'] {
					actual += function(body, symbol)
				}
			}
			'paths.v' { actual += structure(body, 'WsVertex') }
			'path_clipping.v' {
				actual += structure(body, 'WsPathClip')
				for symbol in ['ws_path_clip_contains', 'ws_path_clip_crossing'] { actual += function(body, symbol) }
			}
			else {}
		}
		os.write_file(out + '/src/actual_' + name, actual)!
		os.write_file(out + '/' + name + '.txt', body)!
		files << ['src/actual_' + name, name + '.txt']
		hashes += sha256.sum(body.bytes()).hex() + '  ' + name + '\n'
	}
	os.write_file(out + '/source-sha256.txt', hashes)!
	os.cp(repo + '/tests/native-android-ws/xfermodehost/harness.v.txt', out + '/src/main.v')!
	println('PAINT-XFERMODE-HOST asan=' + asan.str())
	print(hashes)
	compiler := os.getenv_opt('VINIX_V_COMPILER') or { @VEXE }
	mut args := [compiler, '-nocache', '-cc', 'cc', '-enable-globals', '-gc', 'none']
	if asan { args << ['-cflags', '-fsanitize=address -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address'] }
	args << ['-o', out + '/host', out + '/src']
	checked(args, out + '/compile.log')
	if asan { os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true) }
	checked([out + '/host'], out + '/run.log')
	mut evidence := ''
	for name in files {
		evidence += sha256.sum(os.read_bytes(out + '/' + name)!).hex() + '  ' + name + '\n'
	}
	os.write_file(out + '/evidence-sha256.txt', evidence)!
	println('PAINT-XFERMODE-HOST evidence=' + sha256.sum(evidence.bytes()).hex())
}
