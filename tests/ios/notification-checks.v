// SPDX-License-Identifier: GPL-2.0-or-later
// Frozen-toolchain notification checks; all generated output is external.
module main
import os
fn run(out string, label string, args []string, deterministic bool) {
	mut p := os.new_process(args[0]); p.set_args(args[1..]); p.set_redirect_stdio_merged()
	mut env := os.environ()
	env['TMPDIR'] = out + '/tmp'
	env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'; env['V_MACOS_V3_NO_FALLBACK'] = '1'
	env['V_RESOURCE_PATH'] = os.getwd() + '/build/ios/fortnite/ns-calendar-checks/toolchain'
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
fn main() {
	if os.args.len != 3 { panic('usage: notification-checks MODE EXTERNAL_BUNDLE') }
	root := os.real_path(os.getwd()); out := os.abs_path(os.args[2]); old := root + '/build/ios/fortnite/ns-calendar-checks/toolchain'
	if out == root || out.starts_with(root + "/") { panic('notification evidence must be outside the repository') }
	os.mkdir_all(out + "/payload")!; os.mkdir_all(out + "/tmp")!
	if os.args[1] == 'inspect' {
		run(out, 'inspect', [out + '/inspect-user-notifications', '--bundle', out], false)
	} else if os.args[1] == 'content-inspect' {
		run(out, 'inspect', [out + '/inspect-notification-content'], false)
	} else if os.args[1] == 'sound-inspect' {
		run(out, 'inspect', [out + '/inspect-notification-sound'], false)
	} else if os.args[1] == 'sound-metadata-inspect' {
		run(out, 'inspect-metadata', [out + '/inspect-user-notifications', 'UNNotificationSound'], false)
	} else if os.args[1] == 'cache-inspect' {
		run(out, 'inspect', [out + '/inspect-cache'], false)
	} else if os.args[1] == 'cache-metadata-inspect' {
		run(out, 'inspect-metadata', [out + '/inspect-user-notifications', 'NSCache'], false)
	} else if os.args[1] == 'map-table-metadata-inspect' {
		run(out, 'inspect-metadata', [out + '/inspect-user-notifications', 'NSMapTable'], false)
	} else if os.args[1] == 'map-table-inspect' {
		run(out, 'inspect', [out + '/inspect-map-table'], false)
	} else if os.args[1] == 'credential-metadata-inspect' {
		run(out, 'inspect-metadata', [out + '/inspect-user-notifications', 'NSURLCredential'], false)
	} else if os.args[1] == 'credential-inspect' {
		for mode in ['password', 'empty', 'nil-user', 'nil-password', 'invalid-persistence']! { run(out, 'inspect-' + mode, [out + '/inspect-credential', mode], false) }
	} else if os.args[1] == 'telephony-metadata-inspect' {
		run(out, 'inspect-metadata', [out + '/inspect-user-notifications', 'CTTelephonyNetworkInfo'], false)
	} else if os.args[1] == 'attachment-inspect' {
		run(out, 'inspect', [out + '/inspect-notification-attachment'], false)
	} else if os.args[1] == 'attachment-metadata-inspect' {
		run(out, 'inspect-metadata', [out + '/inspect-user-notifications', 'UNNotificationAttachment'], false)
	} else if os.args[1] in ['host', 'content-host', 'sound-host', 'attachment-host', 'cache-host', 'telephony-host', 'credential-host', 'map-table-host']! {
		content := os.args[1] == 'content-host'
		fixture := if os.args[1] == 'map-table-host' { 'ns_map_table_test.v' } else if os.args[1] == 'credential-host' { 'ns_url_credential_test.v' } else if os.args[1] == 'telephony-host' { 'coretelephony_test.v' } else if os.args[1] == 'cache-host' { 'ns_cache_test.v' } else if content { 'un_notification_content_test.v' } else if os.args[1] == 'sound-host' { 'un_notification_sound_test.v' } else if os.args[1] == 'attachment-host' { 'un_notification_attachment_test.v' } else { 'un_notification_center_test.v' }
		cfile := out + '/payload/center-host.c'; bundle := out + "/NotificationChecks.app/Contents"
		os.mkdir_all(bundle + "/MacOS")!
		os.write_file(bundle + "/Info.plist", "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>org.vinix.notification-checks</string><key>CFBundleExecutable</key><string>center-host</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>")!
		binary := bundle + "/MacOS/center-host"
		run(out, 'host-generate', [old + '/v', '-enable-globals', '-nocache', '-gc', 'none', '-cc', 'clang', '-d', 'ios_video', '-d', 'ios_cxx', '-d', 'ios_sqlite', '-os', 'macos', '-arch', 'arm64', '-path', '@vlib|' + root + '/compat/ios|@vmodules', '-o', cfile, root + '/compat/ios/runner/' + fixture], false)
		mut objects := []string{}
		for i, source in [cfile, old + '/vlib/os/execute_capture_nix.c', old + '/vlib/builtin/segfault_handler_nix.c', root + '/compat/ios/runner/abi/dispatch.S']! {
			object := out + '/payload/host-' + i.str() + '.o'; objects << object
			run(out, 'host-object-' + i.str(), ['/usr/bin/clang', '-I/opt/homebrew/include', '-I/opt/homebrew/opt/freetype/include/freetype2', '-O0', '-g', '-w', '-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-c', source, '-o', object], false)
		}
		mut link := ['/usr/bin/clang', '-g', '-fsanitize=address,undefined']; link << objects
		link << ['-L/opt/homebrew/lib', '-lavcodec', '-lswscale', '-lavutil', '-framework', 'AppKit', '-lc++', '-lsqlite3', '-lresolv', '-framework', 'Foundation', '-framework', 'UserNotifications', '-framework', 'CoreFoundation', '-pthread', '-lproc', '-lm', '-o', binary]
		run(out, 'host-link', link, false)
		run(out, 'host', [binary], false); run(out, 'host-deterministic', [binary], true)
	} else { run(out, os.args[1], [out + "/notification-vm", os.args[1], out], false) }
}
