// SPDX-License-Identifier: GPL-2.0-or-later
// Compile the unchanged production encoder with allocation/JNI fault injection.
module main

import crypto.sha256
import os

fn checked(args []string, output string) {
	r := os.exec(args)
	os.write_file(output, r.output) or { panic(err) }
	print(r.output)
	if r.exit_code != 0 { exit(r.exit_code) }
}

fn main() {
	repo := os.real_path(os.dir(@FILE) + '/../..')
	mut source := repo + '/build-support/android/nativews'
	state := os.getenv('XDG_STATE_HOME')
	state_root := if state == '' { os.home_dir() + '/.local/state' } else { os.abs_path(state) }
	mut out := state_root + '/vinix/android/bitmap-png-host'
	mut asan := false
	for arg in os.args[1..] {
		if arg.starts_with('source=') { source = os.abs_path(arg.all_after('source=')) }
		else if arg.starts_with('out=') { out = os.abs_path(arg.all_after('out=')) }
		else if arg == 'asan=true' { asan = true }
		else { panic('usage: bitmap-png-host [source=NATIVE_DIR] [out=OUTPUT_DIR] [asan=true]') }
	}
	if os.exists(out) || os.is_link(out) { panic('output root already exists: ' + out) }
	os.mkdir_all(out + '/src')!
	mut hashes := ''
	mut files := ['runner.v.txt', 'runner', 'harness.v.txt', 'source-sha256.txt', 'compile.log', 'run.log', 'host', 'src/main.v', 'compiler']
	os.write_file(out + '/runner.v.txt', os.read_file(@FILE)!)!
	os.cp(os.executable(), out + '/runner')!
	for name in ['bitmap_png.v', 'bitmaps.v', 'bindings.txt'] {
		body := os.read_file(source + '/' + name)!
		os.write_file(out + '/' + name + '.txt', body)!
		files << name + '.txt'
		hashes += sha256.sum(body.bytes()).hex() + '  ' + name + '\n'
		if name == 'bitmap_png.v' {
			actual := body.replace('module atlframework', 'module main')
				.replace('C.malloc(', 'host_malloc(').replace('C.free(', 'host_free(')
			os.write_file(out + '/src/actual_bitmap_png.v', actual)!
			files << 'src/actual_bitmap_png.v'
		} else if name == 'bitmaps.v' {
			start := body.index('struct WsBitmap {') or { panic('WsBitmap missing') }
			tail := body[start..]
			end := tail.index('\n}') or { panic('WsBitmap unterminated') }
			os.write_file(out + '/src/actual_bitmap.v', 'module main\n' + tail[..end + 3] + '\n')!
			files << 'src/actual_bitmap.v'
		} else {
			assert body.split_into_lines().filter(it == 'android/graphics/Bitmap|native_save_to_png|return ws_bitmap_png(e,p0)').len == 1
		}
	}
	os.write_file(out + '/source-sha256.txt', hashes)!
	os.cp(repo + '/tests/native-android-ws/bitmappnghost/harness.v.txt', out + '/src/main.v')!
	os.cp(repo + '/tests/native-android-ws/bitmappnghost/harness.v.txt', out + '/harness.v.txt')!
	compiler := os.getenv_opt('VINIX_V_COMPILER') or { @VEXE }
	os.cp(compiler, out + '/compiler')!
	os.write_file(out + '/compiler-sha256.txt', sha256.sum(os.read_bytes(compiler)!).hex() + '  ' + compiler + '\n')!
	files << 'compiler-sha256.txt'
	mut args := [compiler, '-nocache', '-cc', 'cc', '-enable-globals', '-gc', 'none', '-cflags', '-O2']
	if asan { args << ['-cflags', '-fsanitize=address -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address'] }
	args << ['-o', out + '/host', out + '/src']
	os.write_file(out + '/compile-argv.txt', args.join('\n') + '\n')!
	files << 'compile-argv.txt'
	println('BITMAP-PNG-HOST asan=' + asan.str())
	print(hashes)
	checked(args, out + '/compile.log')
	if asan { os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true) }
	checked([out + '/host'], out + '/run.log')
	mut evidence := ''
	for name in files { evidence += sha256.sum(os.read_bytes(out + '/' + name)!).hex() + '  ' + name + '\n' }
	os.write_file(out + '/evidence-sha256.txt', evidence)!
	println('BITMAP-PNG-HOST evidence=' + sha256.sum(evidence.bytes()).hex())
}
