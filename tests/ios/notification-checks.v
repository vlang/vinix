// SPDX-License-Identifier: GPL-2.0-or-later
// Frozen-toolchain notification checks; all generated output is external.
module main
import os
import tlsbuild
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
fn run_host_fixture(root string, old string, out string, fixture string) ! {
	cfile := out + '/payload/center-host.c'; bundle := out + "/NotificationChecks.app/Contents"
	os.mkdir_all(bundle + "/MacOS")!
	os.write_file(bundle + "/Info.plist", "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>org.vinix.notification-checks</string><key>CFBundleExecutable</key><string>center-host</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>")!
	binary := bundle + "/MacOS/center-host"
	run(out, 'host-generate', [old + '/v', '-enable-globals', '-nocache', '-gc', 'none', '-cc', 'clang', '-d', 'ios_video', '-d', 'ios_cxx', '-d', 'ios_sqlite', '-os', 'macos', '-arch', 'arm64', '-path', '@vlib|' + root + '/compat/ios|' + root + '/tests/ios|@vmodules', '-o', cfile, root + '/compat/ios/runner/' + fixture], false)
	// Shared UIKit fixtures require Catalyst for native comparisons.
	target := if fixture in ['ui_responder_test.v', 'ui_view_tag_test.v', 'ui_alert_test.v', 'ui_application_badge_test.v'] { ['-target', 'arm64-apple-ios14.0-macabi'] } else { []string{} }
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
	if fixture == 'ns_data_http_test.v' {
		run(out, 'certificate', ['/usr/bin/openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost', '-days', '1', '-keyout', out + '/server.key', '-out', out + '/server.pem'], false)
		os.setenv('VINIX_IOS_HTTP_CERT', out + '/server.pem', true)
		os.setenv('VINIX_IOS_HTTP_KEY', out + '/server.key', true)
	}
	run(out, 'host', [binary], false); run(out, 'host-deterministic', [binary], true)
}

fn main() {
	if os.args.len != 3 { panic('usage: notification-checks MODE EXTERNAL_BUNDLE') }
	root := os.real_path(os.getwd()); out := os.abs_path(os.args[2]); old := root + '/build/ios/fortnite/ns-calendar-checks/toolchain'
	if out == root || out.starts_with(root + "/") { panic('notification evidence must be outside the repository') }
	os.mkdir_all(out + "/payload")!; os.mkdir_all(out + "/tmp")!
	if os.args[1] in ['string-get-cstring-host', 'dictionary-file-host', 'bundle-identifier-host', 'string-path-host', 'url-resource-host', 'number-bool-host', 'string-cstring-output-host', 'string-normalization-host', 'responder-host', 'view-tag-host', 'main-selector-host', 'application-badge-host', 'window-host', 'alert-host', 'string-float-host', 'string-cstring-host', 'bundle-receipt-host', 'cf-string-output-host', 'search-path-host', 'home-directory-host', 'inline-pthread-self-host', 'dictionary-snapshot-host', 'block-byref-host', 'block-imp-host', 'vm-probe-host', 'proc-memory-host', 'processinfo-host', 'data-url-host', 'data-http-host', 'connection-host'] {
		fixture := match os.args[1] {
			'string-get-cstring-host' { 'ns_string_get_cstring_test.v' }
			'dictionary-file-host' { 'ns_dictionary_file_test.v' }
			'bundle-identifier-host' { 'ns_bundle_identifier_test.v' }
			'string-path-host' { 'ns_string_path_test.v' }
			'url-resource-host' { 'ns_url_resource_test.v' }
			'number-bool-host' { 'ns_number_bool_test.v' }
			'string-cstring-output-host' { 'ns_string_cstring_output_test.v' }
			'string-normalization-host' { 'ns_string_normalization_test.v' }
			'responder-host' { 'ui_responder_test.v' }
			'view-tag-host' { 'ui_view_tag_test.v' }
			'main-selector-host' { 'ns_main_selector_test.v' }
			'application-badge-host' { 'ui_application_badge_test.v' }
			'window-host' { 'ui_window_test.v' }
			'alert-host' { 'ui_alert_test.v' }
			'string-float-host' { 'ns_string_float_test.v' }
			'string-cstring-host' { 'ns_string_cstring_test.v' }
			'bundle-receipt-host' { 'ns_bundle_receipt_test.v' }
			'cf-string-output-host' { 'cf_string_output_test.v' }
			'search-path-host' { 'ns_search_paths_test.v' }
			'home-directory-host' { 'ns_home_directory_test.v' }
			'inline-pthread-self-host' { 'inline_pthread_self_test.v' }
			'dictionary-snapshot-host' { 'objc_constant_dictionary_test.v' }
			'block-byref-host' { 'block_byref_test.v' }
			'block-imp-host' { 'objc_block_imp_test.v' }
			'vm-probe-host' { 'vm_probe_test.v' }
			'proc-memory-host' { 'proc_memory_test.v' }
			'processinfo-host' { 'ns_process_info_test.v' }
			'data-url-host' { 'ns_data_url_test.v' }
			'data-http-host' { 'ns_data_http_test.v' }
			else { 'ns_url_connection_test.v' }
		}
		run_host_fixture(root, old, out, fixture)!
	} else if os.args[1] == 'application-badge-inspector-build' {
		run(out, 'inspect-build', [old + '/v', '-nocache', '-gc', 'none', '-cc', 'clang', '-cflags', '-target arm64-apple-ios14.0-macabi', '-ldflags', '-target arm64-apple-ios14.0-macabi', '-o', out + '/inspect-application-badge', root + '/tests/ios/inspect-application-badge.v'], false)
	} else if os.args[1] == 'application-badge-inspect' {
		run(out, 'inspect', [out + '/inspect-application-badge', '--bundle', out], false)
	} else if os.args[1] == 'string-float-inspector-build' {
		run(out, 'inspect-build', [old + '/v', '-nocache', '-gc', 'none', '-cc', 'clang', '-path', '@vlib|' + root + '/compat/ios|@vmodules', '-o', out + '/inspect-string-float', root + '/tests/ios/inspect-string-float.v'], false)
	} else if os.args[1] == 'string-float-inspect' {
		run(out, 'inspect', [out + '/inspect-string-float'], false)
	} else if os.args[1] == 'string-cstring-inspector-build' {
		run(out, 'inspect-build', [old + '/v', '-nocache', '-gc', 'none', '-cc', 'clang', '-o', out + '/inspect-string-cstring', root + '/tests/ios/inspect-string-cstring.v'], false)
	} else if os.args[1] == 'string-cstring-inspect' {
		run(out, 'inspect', [out + '/inspect-string-cstring'], false)
	} else if os.args[1] == 'bundle-receipt-inspector-build' {
		run(out, 'inspect-build', [old + '/v', '-nocache', '-gc', 'none', '-cc', 'clang', '-o', out + '/inspect-bundle-receipt', root + '/tests/ios/inspect-bundle-receipt.v'], false)
	} else if os.args[1] == 'bundle-receipt-inspect' {
		run(out, 'inspect', [out + '/inspect-bundle-receipt'], false)
	} else if os.args[1] == 'driver-build' {
		run(out, 'driver-build', [old + '/v', '-nocache', '-prod', '-gc', 'none', '-cc', 'clang', '-o', out + '/native-checks', root + '/tests/ios/native-checks.v'], false)
	} else if os.args[1] == 'scene-notifications-inspector-build' {
		run(out, 'inspect-build', [old + '/v', '-nocache', '-gc', 'none', '-cc', 'clang', '-cflags', '-target arm64-apple-ios14.0-macabi', '-ldflags', '-target arm64-apple-ios14.0-macabi', '-o', out + '/inspect-scene-notifications', root + '/tests/ios/inspect-scene-notifications.v'], false)
	} else if os.args[1] == 'scene-notifications-inspect' {
		run(out, 'inspect', [out + '/inspect-scene-notifications'], false)
	} else if os.args[1] == 'haptic-dynamic-parameter-inspector-build' {
		run(out, 'inspect-build', [old + '/v', '-nocache', '-gc', 'none', '-cc', 'clang', '-o', out + '/inspect-ch-haptic-dynamic-parameter', root + '/tests/ios/inspect-ch-haptic-dynamic-parameter.v'], false)
	} else if os.args[1] == 'gk-match-request-inspector-build' {
		run(out, 'inspect-build', [old + '/v', '-nocache', '-gc', 'none', '-cc', 'clang', '-cflags', '-target arm64-apple-ios14.0-macabi', '-ldflags', '-target arm64-apple-ios14.0-macabi', '-o', out + '/inspect-gk-match-request', root + '/tests/ios/inspect-gk-match-request.v'], false)
	} else if os.args[1] == 'gk-achievement-inspector-build' {
		run(out, 'inspect-build', [old + '/v', '-nocache', '-gc', 'none', '-cc', 'clang', '-cflags', '-target arm64-apple-ios14.0-macabi', '-ldflags', '-target arm64-apple-ios14.0-macabi', '-o', out + '/inspect-gk-achievement', root + '/tests/ios/inspect-gk-achievement.v'], false)
	} else if os.args[1] == 'gk-turn-based-match-inspector-build' {
		run(out, 'inspect-build', [old + '/v', '-nocache', '-gc', 'none', '-cc', 'clang', '-cflags', '-target arm64-apple-ios14.0-macabi', '-ldflags', '-target arm64-apple-ios14.0-macabi', '-o', out + '/inspect-gk-turn-based-match', root + '/tests/ios/inspect-gk-turn-based-match.v'], false)
	} else if os.args[1] == 'gk-local-player-inspector-build' {
		run(out, 'inspect-build', [old + '/v', '-nocache', '-gc', 'none', '-cc', 'clang', '-cflags', '-target arm64-apple-ios14.0-macabi', '-ldflags', '-target arm64-apple-ios14.0-macabi', '-o', out + '/inspect-gk-local-player', root + '/tests/ios/inspect-gk-local-player.v'], false)
	} else if os.args[1] == 'gk-turn-based-matchmaker-inspector-build' {
		run(out, 'inspect-build', [old + '/v', '-nocache', '-gc', 'none', '-cc', 'clang', '-cflags', '-target arm64-apple-ios14.0-macabi', '-ldflags', '-target arm64-apple-ios14.0-macabi', '-o', out + '/inspect-gk-turn-based-matchmaker', root + '/tests/ios/inspect-gk-turn-based-matchmaker.v'], false)
	} else if os.args[1] == 'av-player-inspector-build' {
		run(out, 'inspect-build', [old + '/v', '-nocache', '-gc', 'none', '-cc', 'clang', '-cflags', '-target arm64-apple-ios14.0-macabi', '-ldflags', '-target arm64-apple-ios14.0-macabi', '-o', out + '/inspect-av-player', root + '/tests/ios/inspect-av-player.v'], false)
	} else if os.args[1] == 'ns-proxy-inspector-build' {
		run(out, 'inspect-build', [old + '/v', '-nocache', '-gc', 'none', '-cc', 'clang', '-cflags', '-target arm64-apple-ios14.0-macabi', '-ldflags', '-target arm64-apple-ios14.0-macabi', '-o', out + '/inspect-ns-proxy', root + '/tests/ios/inspect-ns-proxy.v'], false)
	} else if os.args[1] == 'swift-object-inspector-build' {
		run(out, 'inspect-build', [old + '/v', '-nocache', '-gc', 'none', '-cc', 'clang', '-cflags', '-target arm64-apple-ios14.0-macabi', '-ldflags', '-target arm64-apple-ios14.0-macabi', '-o', out + '/inspect-swift-object', root + '/tests/ios/inspect-swift-object.v'], false)
	} else if os.args[1] == 'storekit-purchase-inspector-build' {
		run(out, 'inspect-build', [old + '/v', '-nocache', '-gc', 'none', '-cc', 'clang', '-cflags', '-target arm64-apple-ios14.0-macabi', '-ldflags', '-target arm64-apple-ios14.0-macabi', '-o', out + '/inspect-storekit-purchase', root + '/tests/ios/inspect-storekit-purchase.v'], false)
	} else if os.args[1] == 'gk-leaderboard-inspector-build' {
		run(out, 'inspect-build', [old + '/v', '-nocache', '-gc', 'none', '-cc', 'clang', '-cflags', '-target arm64-apple-ios14.0-macabi', '-ldflags', '-target arm64-apple-ios14.0-macabi', '-o', out + '/inspect-gk-leaderboard', root + '/tests/ios/inspect-gk-leaderboard.v'], false)
	} else if os.args[1] == 'gk-turn-based-participant-inspector-build' {
		run(out, 'inspect-build', [old + '/v', '-nocache', '-gc', 'none', '-cc', 'clang', '-cflags', '-target arm64-apple-ios14.0-macabi', '-ldflags', '-target arm64-apple-ios14.0-macabi', '-o', out + '/inspect-gk-turn-based-participant', root + '/tests/ios/inspect-gk-turn-based-participant.v'], false)
	} else if os.args[1] == 'gk-player-inspector-build' {
		run(out, 'inspect-build', [old + '/v', '-nocache', '-gc', 'none', '-cc', 'clang', '-cflags', '-target arm64-apple-ios14.0-macabi', '-ldflags', '-target arm64-apple-ios14.0-macabi', '-o', out + '/inspect-gk-player', root + '/tests/ios/inspect-gk-player.v'], false)
	} else if os.args[1] == 'gk-achievement-description-inspector-build' {
		run(out, 'inspect-build', [old + '/v', '-nocache', '-gc', 'none', '-cc', 'clang', '-cflags', '-target arm64-apple-ios14.0-macabi', '-ldflags', '-target arm64-apple-ios14.0-macabi', '-o', out + '/inspect-gk-achievement-description', root + '/tests/ios/inspect-gk-achievement-description.v'], false)
	} else if os.args[1] == 'capture-audio-output-inspector-build' {
		run(out, 'inspect-build', [old + '/v', '-nocache', '-gc', 'none', '-cc', 'clang', '-cflags', '-target arm64-apple-ios14.0-macabi', '-ldflags', '-target arm64-apple-ios14.0-macabi', '-o', out + '/inspect-capture-audio-output', root + '/tests/ios/inspect-capture-audio-output.v'], false)
	} else if os.args[1] == 'capture-discovery-inspector-build' {
		run(out, 'inspect-build', [old + '/v', '-nocache', '-gc', 'none', '-cc', 'clang', '-cflags', '-target arm64-apple-ios14.0-macabi', '-ldflags', '-target arm64-apple-ios14.0-macabi', '-o', out + '/inspect-capture-discovery', root + '/tests/ios/inspect-capture-discovery.v'], false)
	} else if os.args[1] == 'app-attest-inspector-build' {
		run(out, 'inspect-build', [old + '/v', '-nocache', '-gc', 'none', '-cc', 'clang', '-cflags', '-target arm64-apple-ios14.0-macabi', '-ldflags', '-target arm64-apple-ios14.0-macabi', '-o', out + '/inspect-app-attest', root + '/tests/ios/inspect-app-attest.v'], false)
	} else if os.args[1] == 'gc-event-view-controller-inspector-build' {
		run(out, 'inspect-build', [old + '/v', '-nocache', '-gc', 'none', '-cc', 'clang', '-cflags', '-target arm64-apple-ios14.0-macabi', '-ldflags', '-target arm64-apple-ios14.0-macabi', '-o', out + '/inspect-gc-event-view-controller', root + '/tests/ios/inspect-gc-event-view-controller.v'], false)
	} else if os.args[1] == 'snapshot-configuration-inspector-build' {
		run(out, 'inspect-build', [old + '/v', '-nocache', '-gc', 'none', '-cc', 'clang', '-cflags', '-target arm64-apple-ios14.0-macabi', '-ldflags', '-target arm64-apple-ios14.0-macabi', '-o', out + '/inspect-wk-snapshot-configuration', root + '/tests/ios/inspect-wk-snapshot-configuration.v'], false)
	} else if os.args[1] == 'text-field-inspector-build' {
		run(out, 'inspect-build', [old + '/v', '-nocache', '-gc', 'none', '-cc', 'clang', '-cflags', '-target arm64-apple-ios14.0-macabi', '-ldflags', '-target arm64-apple-ios14.0-macabi', '-o', out + '/inspect-ui-text-field', root + '/tests/ios/inspect-ui-text-field.v'], false)
	} else if os.args[1] == 'haptic-pattern-inspector-build' {
		run(out, 'inspect-build', [old + '/v', '-nocache', '-gc', 'none', '-cc', 'clang', '-o', out + '/inspect-ch-haptic-pattern', root + '/tests/ios/inspect-ch-haptic-pattern.v'], false)
	} else if os.args[1] == 'haptic-event-inspector-build' {
		run(out, 'inspect-build', [old + '/v', '-nocache', '-gc', 'none', '-cc', 'clang', '-o', out + '/inspect-ch-haptic-event', root + '/tests/ios/inspect-ch-haptic-event.v'], false)
	} else if os.args[1] == 'haptic-dynamic-parameter-inspect' {
		run(out, 'inspect', [out + '/inspect-ch-haptic-dynamic-parameter'], false)
	} else if os.args[1] == 'gk-match-request-inspect' {
		run(out, 'inspect', [out + '/inspect-gk-match-request'], false)
	} else if os.args[1] == 'gk-achievement-inspect' {
		run(out, 'inspect', [out + '/inspect-gk-achievement'], false)
	} else if os.args[1] == 'gk-turn-based-match-inspect' {
		run(out, 'inspect', [out + '/inspect-gk-turn-based-match'], false)
	} else if os.args[1] == 'gk-local-player-inspect' {
		run(out, 'inspect', [out + '/inspect-gk-local-player'], false)
	} else if os.args[1] == 'gk-turn-based-matchmaker-inspect' {
		run(out, 'inspect', [out + '/inspect-gk-turn-based-matchmaker'], false)
	} else if os.args[1] == 'av-player-inspect' {
		run(out, 'inspect', [out + '/inspect-av-player'], false)
	} else if os.args[1] == 'ns-proxy-inspect' {
		run(out, 'inspect', [out + '/inspect-ns-proxy'], false)
	} else if os.args[1] == 'swift-object-inspect' {
		run(out, 'inspect', [out + '/inspect-swift-object'], false)
	} else if os.args[1] == 'storekit-purchase-inspect' {
		run(out, 'inspect', [out + '/inspect-storekit-purchase'], false)
	} else if os.args[1] == 'gk-leaderboard-inspect' {
		run(out, 'inspect', [out + '/inspect-gk-leaderboard'], false)
	} else if os.args[1] == 'gk-turn-based-participant-inspect' {
		run(out, 'inspect', [out + '/inspect-gk-turn-based-participant'], false)
	} else if os.args[1] == 'gk-player-inspect' {
		run(out, 'inspect', [out + '/inspect-gk-player'], false)
	} else if os.args[1] == 'gk-achievement-description-inspect' {
		run(out, 'inspect', [out + '/inspect-gk-achievement-description'], false)
	} else if os.args[1] == 'capture-audio-output-inspect' {
		run(out, 'inspect', [out + '/inspect-capture-audio-output'], false)
	} else if os.args[1] == 'capture-discovery-inspect' {
		run(out, 'inspect', [out + '/inspect-capture-discovery'], false)
	} else if os.args[1] == 'app-attest-inspect' {
		run(out, 'inspect', [out + '/inspect-app-attest'], false)
	} else if os.args[1] == 'gc-event-view-controller-inspect' {
		run(out, 'inspect', [out + '/inspect-gc-event-view-controller'], false)
	} else if os.args[1] == 'snapshot-configuration-inspect' {
		run(out, 'inspect', [out + '/inspect-wk-snapshot-configuration'], false)
	} else if os.args[1] == 'text-field-inspect' {
		run(out, 'inspect', [out + '/inspect-ui-text-field'], false)
	} else if os.args[1] == 'haptic-pattern-inspect' {
		run(out, 'inspect', [out + '/inspect-ch-haptic-pattern'], false)
	} else if os.args[1] == 'haptic-event-inspect' {
		run(out, 'inspect', [out + '/inspect-ch-haptic-event'], false)
	} else if os.args[1] == 'haptic-event-parameter-inspector-build' {
		run(out, 'inspect-build', [old + '/v', '-nocache', '-gc', 'none', '-cc', 'clang', '-o', out + '/inspect-ch-haptic-event-parameter', root + '/tests/ios/inspect-ch-haptic-event-parameter.v'], false)
	} else if os.args[1] == 'haptic-event-parameter-inspect' {
		run(out, 'inspect', [out + '/inspect-ch-haptic-event-parameter'], false)
	} else if os.args[1] == 'inspect' {
		run(out, 'inspect', [out + '/inspect-user-notifications', '--bundle', out], false)
	} else if os.args[1] == 'content-inspect' {
		run(out, 'inspect', [out + '/inspect-notification-content'], false)
	} else if os.args[1] == 'sound-inspect' {
		run(out, 'inspect', [out + '/inspect-notification-sound'], false)
	} else if os.args[1] == 'sound-metadata-inspect' {
		run(out, 'inspect-metadata', [out + '/inspect-user-notifications', 'UNNotificationSound'], false)
	} else if os.args[1] == 'cache-inspect' {
		run(out, 'inspect', [out + '/inspect-cache'], false)
	} else if os.args[1] == 'game-controller-inspect' {
		run(out, 'GCController-metadata', [out + '/inspect-user-notifications', 'GCController'], false)
		run(out, 'inspect', [out + '/inspect-game-controller'], false)
	} else if os.args[1] == 'gamepad-inspect' {
		for name in ['GCPhysicalInputProfile', 'GCExtendedGamepad', 'GCDualShockGamepad', 'GCDualSenseGamepad']! {
			run(out, name + '-metadata', [out + '/inspect-user-notifications', name], false)
		}
	} else if os.args[1] == 'gc-color-inspect' {
		run(out, 'GCColor-metadata', [out + '/inspect-user-notifications', 'GCColor'], false)
		run(out, 'gc-color-inspect', [out + '/inspect-gc-color'], false)
	} else if os.args[1] == 'audio-application-inspect' {
		run(out, 'AVAudioApplication-metadata', [out + '/inspect-user-notifications', 'AVAudioApplication'], false)
		run(out, 'audio-application-inspect', [out + '/inspect-audio-application'], false)
	} else if os.args[1] == 'gc-mouse-inspect' {
		run(out, 'GCMouse-metadata', [out + '/inspect-user-notifications', 'GCMouse'], false)
		run(out, 'gc-mouse-inspect', [out + '/inspect-gc-mouse'], false)
	} else if os.args[1] == 'session-task-inspect' {
		for name in ['NSURLSessionTask', 'NSURLSessionDownloadTask', 'NSURLSessionDataTask', 'NSURLSessionUploadTask']! {
			run(out, name + '-metadata', [out + '/inspect-user-notifications', name], false)
			for mode in ['new', 'init', 'copy', 'copyWithZone:', 'priority', 'description', 'lifecycle', 'counts', 'originalRequest', 'currentRequest', 'response', 'error', 'state', 'taskIdentifier']! {
				run(out, name + '-' + mode.replace(':', ''), [out + '/inspect-session-task', name, mode], false)
			}
		}
	} else if os.args[1] == 'cache-metadata-inspect' {
		run(out, 'inspect-metadata', [out + '/inspect-user-notifications', 'NSCache'], false)
	} else if os.args[1] == 'adsupport-metadata-inspect' {
		run(out, 'inspect-metadata', [out + '/inspect-user-notifications', 'ASIdentifierManager'], false)
	} else if os.args[1] == 'bundle-resource-metadata-inspect' {
		run(out, 'inspect-metadata', [out + '/inspect-user-notifications', 'NSBundleResourceRequest'], false)
	} else if os.args[1] == 'bundle-resource-inspect' {
		for mode in ['tags', 'empty', 'nil', 'bundle', 'nil-bundle']! { run(out, 'inspect-' + mode, [out + '/inspect-bundle-resource', mode], false) }
	} else if os.args[1] == 'number-formatter-metadata-inspect' {
		run(out, 'inspect-metadata', [out + '/inspect-user-notifications', 'NSNumberFormatter'], false)
	} else if os.args[1] == 'lock-metadata-inspect' {
		run(out, 'inspect-metadata', [out + '/inspect-user-notifications', 'NSLock'], false)
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
	} else if os.args[1] in ['host', 'content-host', 'sound-host', 'attachment-host', 'cache-host', 'telephony-host', 'credential-host', 'map-table-host', 'lock-host', 'recursive-lock-host', 'number-formatter-host', 'date-formatter-host', 'bundle-resource-host', 'adsupport-host', 'feedback-host', 'session-task-host', 'game-controller-host', 'haptic-dynamic-parameter-host', 'image-initializers-host', 'class-update-host', 'singleton-metadata-host', 'native-value-host', 'unknown-value-host', 'bridge-value-host', 'capture-audio-output-host', 'gk-match-request-host', 'gk-achievement-host', 'gk-achievement-description-host', 'gk-player-host', 'gk-turn-based-participant-host', 'gk-turn-based-match-host', 'gk-local-player-host', 'gk-leaderboard-host', 'capture-discovery-host', 'app-attest-host', 'gc-event-view-controller-host', 'snapshot-configuration-host', 'text-field-host', 'haptic-pattern-host', 'haptic-event-host', 'haptic-event-parameter-host', 'long-press-gesture-host', 'tap-gesture-host', 'rotation-gesture-host', 'pinch-gesture-host', 'pan-gesture-host', 'text-input-host', 'game-center-host', 'av-player-host', 'ns-proxy-host', 'swift-object-host', 'probe-no-ads-host', 'storekit-purchase-host', 'storyboard-host', 'audio-application-host', 'string-character-search-host', 'scene-notifications-host']! {
		content := os.args[1] == 'content-host'
		fixture := if os.args[1] == 'scene-notifications-host' { 'scene_notifications_test.v' } else if os.args[1] == 'string-character-search-host' { 'ns_string_character_search_test.v' } else if os.args[1] == 'image-initializers-host' { 'image_initializers_test.v' } else if os.args[1] == 'singleton-metadata-host' { 'swift_singleton_metadata_test.v' } else if os.args[1] == 'class-update-host' { 'swift_class_update_test.v' } else if os.args[1] == 'native-value-host' { 'swift_native_value_test.v' } else if os.args[1] == 'unknown-value-host' { 'swift_unknown_value_test.v' } else if os.args[1] == 'bridge-value-host' { 'swift_bridge_value_test.v' } else if os.args[1] == 'gk-match-request-host' { 'gk_match_request_test.v' } else if os.args[1] == 'gk-achievement-host' { 'gk_achievement_test.v' } else if os.args[1] == 'gk-player-host' { 'gk_player_test.v' } else if os.args[1] == 'gk-turn-based-participant-host' { 'gk_turn_based_participant_test.v' } else if os.args[1] == 'gk-turn-based-match-host' { 'gk_turn_based_match_test.v' } else if os.args[1] == 'gk-local-player-host' { 'gk_local_player_test.v' } else if os.args[1] == 'gk-leaderboard-host' { 'gk_leaderboard_test.v' } else if os.args[1] == 'gk-achievement-description-host' { 'gk_achievement_description_test.v' } else if os.args[1] == 'capture-audio-output-host' { 'capture_audio_output_test.v' } else if os.args[1] == 'capture-discovery-host' { 'capture_discovery_test.v' } else if os.args[1] == 'app-attest-host' { 'app_attest_test.v' } else if os.args[1] == 'gc-event-view-controller-host' { 'gc_event_view_controller_test.v' } else if os.args[1] == 'snapshot-configuration-host' { 'wk_snapshot_configuration_test.v' } else if os.args[1] == 'text-field-host' { 'ui_text_field_test.v' } else if os.args[1] == 'haptic-dynamic-parameter-host' { 'ch_haptic_dynamic_parameter_test.v' } else if os.args[1] == 'haptic-pattern-host' { 'ch_haptic_pattern_test.v' } else if os.args[1] == 'haptic-event-host' { 'ch_haptic_event_test.v' } else if os.args[1] == 'haptic-event-parameter-host' { 'ch_haptic_event_parameter_test.v' } else if os.args[1] == 'long-press-gesture-host' { 'ui_long_press_gesture_test.v' } else if os.args[1] == 'tap-gesture-host' { 'ui_tap_gesture_test.v' } else if os.args[1] == 'rotation-gesture-host' { 'ui_rotation_gesture_test.v' } else if os.args[1] == 'pinch-gesture-host' { 'ui_pinch_gesture_test.v' } else if os.args[1] == 'pan-gesture-host' { 'ui_pan_gesture_test.v' } else if os.args[1] == 'text-input-host' { 'ui_text_input_test.v' } else if os.args[1] == 'game-center-host' { 'game_center_test.v' } else if os.args[1] == 'av-player-host' { 'av_player_test.v' } else if os.args[1] == 'ns-proxy-host' { 'ns_proxy_test.v' } else if os.args[1] == 'swift-object-host' { 'swift_object_test.v' } else if os.args[1] == 'probe-no-ads-host' { 'probe_no_ads_test.v' } else if os.args[1] == 'storekit-purchase-host' { 'storekit_purchase_test.v' } else if os.args[1] == 'storyboard-host' { 'ui_storyboard_test.v' } else if os.args[1] == 'audio-application-host' { 'audio_application_test.v' } else if os.args[1] == 'game-controller-host' { 'game_controller_test.v' } else if os.args[1] == 'session-task-host' { 'ns_url_session_task_test.v' } else if os.args[1] == 'feedback-host' { 'ui_feedback_test.v' } else if os.args[1] == 'adsupport-host' { 'adsupport_test.v' } else if os.args[1] == 'bundle-resource-host' { 'ns_bundle_resource_test.v' } else if os.args[1] == 'number-formatter-host' { 'ns_number_formatter_test.v' } else if os.args[1] == 'date-formatter-host' { 'date_formatter_test.v' } else if os.args[1] == 'lock-host' { 'ns_lock_test.v' } else if os.args[1] == 'recursive-lock-host' { 'ns_recursive_lock_test.v' } else if os.args[1] == 'map-table-host' { 'ns_map_table_test.v' } else if os.args[1] == 'credential-host' { 'ns_url_credential_test.v' } else if os.args[1] == 'telephony-host' { 'coretelephony_test.v' } else if os.args[1] == 'cache-host' { 'ns_cache_test.v' } else if content { 'un_notification_content_test.v' } else if os.args[1] == 'sound-host' { 'un_notification_sound_test.v' } else if os.args[1] == 'attachment-host' { 'un_notification_attachment_test.v' } else { 'un_notification_center_test.v' }
		run_host_fixture(root, old, out, fixture)!
	} else { run(out, os.args[1], [out + "/notification-vm", os.args[1], out], false) }
}
