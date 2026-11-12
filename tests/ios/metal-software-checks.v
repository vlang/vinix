// SPDX-License-Identifier: GPL-2.0-or-later
// Software/default Metal runner checks; all generated output is external.
module main
import os
import tlsbuild
import frozenv
fn run(out string, label string, args []string, deterministic bool) {
	mut p := os.new_process(args[0]); p.set_args(args[1..]); p.set_redirect_stdio_merged()
	frozenv.configure(mut p, args[0]) or { panic(err) }
	mut env := os.environ()
	env['TMPDIR'] = out + '/tmp'
	env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'; env['V_MACOS_V3_NO_FALLBACK'] = '1'
	env['V_RESOURCE_PATH'] = out + '/toolchain'
	env['VEXE'] = env['V_RESOURCE_PATH'] + '/v'
	env['ASAN_OPTIONS'] = 'detect_leaks=0:halt_on_error=1'; env['UBSAN_OPTIONS'] = 'halt_on_error=1'
	env['VINIX_IOS_CHECK_NAME'] = 'notification-center-checks'
	if deterministic { env['SWIFT_DETERMINISTIC_HASHING'] = '1' } else { env.delete('SWIFT_DETERMINISTIC_HASHING') }
	p.set_environment(env); p.run(); output := p.stdout_slurp(); p.wait(); code := p.code; p.close()
	os.write_file(out + '/' + label + '.log', 'COMMAND: ' + args.map(os.quoted_path(it)).join(' ') + '\n' + output) or { panic(err) }
	os.write_file(out + '/' + label + '.status.txt', code.str() + '\n') or { panic(err) }
	if code != 0 || output.contains('runtime error:') || output.contains('ERROR: AddressSanitizer') || output.contains('V panic:') || output.contains('> assert ') {
		eprintln(output)
		exit(1)
	}
	println(label + ': PASS')
}
fn run_host_fixture(root string, old string, out string, fixture string) ! {
	cfile := out + '/payload/center-host.c'; bundle := out + "/NotificationChecks.app/Contents"
	os.mkdir_all(bundle + "/MacOS")!
	os.write_file(bundle + "/Info.plist", "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>org.vinix.notification-checks</string><key>CFBundleExecutable</key><string>center-host</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>")!
	binary := bundle + "/MacOS/center-host"
	mut generation := [old + '/v', '-enable-globals', '-nocache', '-gc', 'none', '-cc', 'clang', '-d', 'ios_video', '-d', 'ios_cxx', '-d', 'ios_sqlite', '-os', 'macos', '-arch', 'arm64', '-path', '@vlib|' + root + '/compat/ios|' + root + '/tests/ios|@vmodules', '-o', cfile, root + '/compat/ios/runner/' + fixture]
	if fixture == 'metal_software_test.v' { generation << ['-d', 'ios_metal_software'] }
	run(out, 'host-generate', generation, false)
	// This captured development compiler reloads headers through absolute paths
	// with compile-time lengths. Preserve its output, then substitute the complete
	// matching captured preambles; no generated program function is changed.
	os.cp(cfile, out + '/payload/generated-original.c')!
	mut text := os.read_file(cfile)!
	start := text.index('#if defined(_MSC_VER)\n#define V_INT128_STRUCT_ATTR') or { panic('missing int128 preamble') }
	end := text.index('/* Decimal text for the assert and panic printers.') or { panic('missing int128 decimal boundary') }
	assert end > start
	text = text[..start] + os.read_file(old + '/int128_helpers.h')! + '\n' + text[end..]
	manual_start := text.index('// GCC-compatible compilers also define __GNUC__') or { panic('missing captured manual preamble') }
	manual_end := text.index('#define V_MANUAL_STDLIB_HEADERS 1') or { panic('missing manual preamble boundary') }
	assert manual_end > manual_start
	text = text[..manual_start] + os.read_file(old + '/manual_stdlib_c_headers.h')! + '\n' + text[manual_end..]
	// The captured os binding's forward declaration conflicts with the SDK.
	// Use the real signal.h declaration already included by dispatch.h instead.
	assert text.count('i32 sigaction(i32, void*, i32);') == 1
	text = text.replace('i32 sigaction(i32, void*, i32);', '')
	os.write_file(cfile, text)!
	target := []string{}
	mut tls_cc := ['/usr/bin/clang', '-fsanitize=address,undefined', '-fno-omit-frame-pointer']
	tls_cc << target
	tls := tlsbuild.build(root, old, out + '/payload', tls_cc)
	mut objects := []string{}
	for i, source in [cfile, old + '/vlib/os/execute_capture_nix.c', old + '/vlib/builtin/segfault_handler_nix.c', root + '/compat/ios/runner/abi/dispatch.S']! {
		object := out + '/payload/host-' + i.str() + '.o'; objects << object
		mut compile := ['/usr/bin/clang', '-I/opt/homebrew/include', '-I/opt/homebrew/opt/freetype/include/freetype2', '-O0', '-g', '-w', '-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-c', source, '-o', object]
		compile << target
		compile << tlsbuild.includes(old)
		run(out, 'host-object-' + i.str(), compile, false)
	}
	mut link := ['/usr/bin/clang', '-g', '-fsanitize=address,undefined']; link << objects
	link << target
	link << tls
	link << ['-L/opt/homebrew/lib', '-lavcodec', '-lswscale', '-lavutil', '-framework', 'AppKit', '-lc++', '-lsqlite3', '-lresolv', '-framework', 'Foundation', '-framework', 'UserNotifications', '-framework', 'CoreFoundation', '-pthread', '-lproc', '-lm', '-o', binary]
	run(out, 'host-link', link, false)
	run(out, 'host', [binary], false); run(out, 'host-deterministic', [binary], true)
	expected := if fixture == 'metal_software_test.v' { 'IOS-SOFTWARE-METAL: Objective-C buffer/queue/command/blit ABI' } else { 'IOS-METAL-DEVICE: scoped no-argument import, nil without a Metal backend' }
	for label in ['host', 'host-deterministic'] { assert os.read_file(out + '/' + label + '.log')!.contains(expected), 'missing Metal test execution marker' }
	if fixture == 'metal_software_test.v' { for label in ['host', 'host-deterministic'] { assert os.read_file(out + '/' + label + '.log')!.contains('IOS-SOFTWARE-METAL-BUFFER-STORAGE:'), 'missing buffer storage marker' } }
	if fixture == 'metal_software_test.v' { for label in ['host', 'host-deterministic'] { assert os.read_file(out + '/' + label + '.log')!.contains('IOS-SOFTWARE-METAL-CPU-SLICES:'), 'missing CPU slice transfer marker' } }
	if fixture == 'metal_software_test.v' { for label in ['host', 'host-deterministic'] { assert os.read_file(out + '/' + label + '.log')!.contains('IOS-SOFTWARE-METAL-TEXTURES:'), 'missing texture test marker'; assert os.read_file(out + '/' + label + '.log')!.contains('IOS-SOFTWARE-METAL-VIEWS:'), 'missing texture view marker' } }
	if fixture == 'metal_software_test.v' { for label in ['host', 'host-deterministic'] { assert os.read_file(out + '/' + label + '.log')!.contains('IOS-SOFTWARE-METAL-TEXTURE-BLITS:'), 'missing texture blit test marker' } }
	if fixture == 'metal_software_test.v' { for label in ['host', 'host-deterministic'] { assert os.read_file(out + '/' + label + '.log')!.contains('IOS-SOFTWARE-METAL-BUFFER-TEXTURE:'), 'missing buffer/texture test marker' } }
	if fixture == 'metal_software_test.v' { for label in ['host', 'host-deterministic'] { assert os.read_file(out + '/' + label + '.log')!.contains('IOS-SOFTWARE-METAL-COMPLETION:'), 'missing completion test marker'; assert os.read_file(out + '/' + label + '.log')!.contains('IOS-SOFTWARE-METAL-SCHEDULED:'), 'missing scheduled test marker' } }
	if fixture == 'metal_software_test.v' { for label in ['host', 'host-deterministic'] { assert os.read_file(out + '/' + label + '.log')!.contains('IOS-SOFTWARE-METAL-FILL:'), 'missing buffer fill test marker' } }
	if fixture == 'metal_software_test.v' { for label in ['host', 'host-deterministic'] { assert os.read_file(out + '/' + label + '.log')!.contains('IOS-SOFTWARE-METAL-IOSURFACE:'), 'missing IOSurface test marker' } }
	if fixture == 'metal_software_test.v' { for label in ['host', 'host-deterministic'] { assert os.read_file(out + '/' + label + '.log')!.contains('IOS-SOFTWARE-METAL-LIBRARY:'), 'missing library test marker' } }
	if fixture == 'metal_software_test.v' { for label in ['host', 'host-deterministic'] { assert os.read_file(out + '/' + label + '.log')!.contains('IOS-SOFTWARE-METAL-LIBRARY-FILES:'), 'missing library file test marker' } }
	if fixture == 'metal_software_test.v' { for label in ['host', 'host-deterministic'] { assert os.read_file(out + '/' + label + '.log')!.contains('IOS-SOFTWARE-METAL-DEFAULT-LIBRARY:'), 'missing default library marker' } }
	if fixture == 'metal_software_test.v' { for label in ['host', 'host-deterministic'] { assert os.read_file(out + '/' + label + '.log')!.contains('IOS-SOFTWARE-METAL-SAMPLERS:'), 'missing sampler marker'; assert os.read_file(out + '/' + label + '.log')!.contains('IOS-SOFTWARE-METAL-VIEW-RANGES:'), 'missing texture view range marker' } }
}

fn main() {
 assert os.args.len == 3 && os.args[2] in ['software', 'default']
 root := os.real_path(os.getwd()); out := os.abs_path(os.args[1]); captured := root + "/build/ios/fortnite/ns-calendar-checks/toolchain"; old := out + '/toolchain'
 assert !os.exists(out) && !out.starts_with(root + "/")
 os.mkdir_all(out + "/payload")!; os.mkdir_all(out + "/tmp")!
 os.mkdir_all(old)!
 os.cp(captured + '/v', old + '/v')!
 os.chmod(old + '/v', 0o755)!
 for directory in ['vlib', 'thirdparty'] { os.symlink(captured + '/' + directory, old + '/' + directory)! }
 for header in ['int128_helpers.h', 'int128_string.h', 'manual_stdlib_c_headers.h'] { os.cp(captured + '/vlib/v/gen/c/' + header, old + '/' + header)! }
 run_host_fixture(root, old, out, if os.args[2] == 'software' { 'metal_software_test.v' } else { 'metal_device_test.v' })!
}
