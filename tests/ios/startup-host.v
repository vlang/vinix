// SPDX-License-Identifier: GPL-2.0-or-later
// ARM64 host startup diagnostics; generated files and command logs stay external.
module main

import os
import strings
import time
import tlsbuild

fn capture(out string, label string, args []string) int {
	mut p := os.new_process(args[0])
	p.set_args(args[1..])
	p.set_redirect_stdio_merged()
	p.run()
	mut output := strings.new_builder(4096)
	watch := time.new_stopwatch()
	mut timed_out := false
	for p.is_alive() {
		output.write_string(p.stdout_read())
		if watch.elapsed().seconds() > 300 {
			timed_out = true
			p.signal_kill()
			break
		}
		time.sleep(20 * time.millisecond)
	}
	output.write_string(p.stdout_slurp())
	p.wait()
	code := if timed_out { 124 } else { p.code }
	p.close()
	if timed_out { output.write_string('\nHOST-TIMEOUT: killed after 300 seconds\n') }
	os.write_file(out + '/' + label + '.log', 'COMMAND: ' + args.map(os.quoted_path(it)).join(' ') + '\n' + output.str()) or { panic(err) }
	unsafe { output.free() }
	os.write_file(out + '/' + label + '.status.txt', code.str() + '\n') or { panic(err) }
	println('${label}: ${code}')
	return code
}

fn checked(out string, label string, args []string) {
	if capture(out, label, args) != 0 { panic('see ' + out + '/' + label + '.log') }
}

fn main() {
	if os.args.len < 3 || os.args[1] !in ['build', 'probe-no-ads'] {
		panic('usage: startup-host build OUT | probe-no-ads OUT APP_EXECUTABLE')
	}
	root := os.real_path(os.getwd())
	out := os.abs_path(os.args[2])
	if out == root || out.starts_with(root + '/') { panic('startup evidence must be external') }
	os.mkdir_all(out + '/tmp')!
	os.setenv('TMPDIR', out + '/tmp', true)
	old := root + '/build/ios/fortnite/ns-calendar-checks/toolchain'
	os.setenv('V_RESOURCE_PATH', old, true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0:halt_on_error=1', true)
	os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
	if os.args[1] == 'build' {
		if os.args.len != 3 { panic('build takes only OUT') }
		generated := out + '/startup-host.c'
		checked(out, 'generate', [old + '/v', '-enable-globals', '-nocache', '-gc', 'none', '-cc', 'clang', '-d', 'ios_video', '-d', 'ios_cxx', '-d', 'ios_sqlite', '-d', 'ios_gles', '-d', 'ios_text', '-os', 'macos', '-arch', 'arm64', '-path', '@vlib|' + root + '/compat/ios|@vmodules', '-o', generated, root + '/compat/ios/runner'])
		mut objects := []string{}
		tls := tlsbuild.build(root, old, out, ['/usr/bin/clang', '-fsanitize=address,undefined', '-fno-omit-frame-pointer'])
		for i, source in [generated, old + '/vlib/os/execute_capture_nix.c', old + '/vlib/builtin/segfault_handler_nix.c', root + '/compat/ios/runner/abi/dispatch.S']! {
			object := out + '/host-' + i.str() + '.o'
			objects << object
			mut compile := ['/usr/bin/clang', '-I/opt/homebrew/include', '-I/opt/homebrew/opt/freetype/include/freetype2', '-O0', '-g', '-w', '-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-c', source, '-o', object]
			compile << tlsbuild.includes(old)
			checked(out, 'object-' + i.str(), compile)
		}
		mut link := ['/usr/bin/clang', '-g', '-fsanitize=address,undefined', '-Wl,-rpath,/opt/homebrew/lib']
		link << objects
		link << tls
		link << ['-L/opt/homebrew/lib', '-lavcodec', '-lswscale', '-lavutil', '-lEGL', '-lGLESv2', '-lfreetype', '-framework', 'AppKit', '-lc++', '-lsqlite3', '-lresolv', '-framework', 'Foundation', '-framework', 'UserNotifications', '-framework', 'CoreFoundation', '-pthread', '-lproc', '-lm', '-o', out + '/run-ios-host']
		checked(out, 'link', link)
	} else {
		if os.args.len != 4 { panic('probe-no-ads requires APP_EXECUTABLE') }
		os.setenv('VINIX_IOS_TRACE', '1', true)
		// A nonzero guest status is a diagnostic result, never a passing launch.
		code := capture(out, 'probe-no-ads', [out + '/run-ios-host', '--probe-no-ads', os.abs_path(os.args[3])])
		exit(code)
	}
}
