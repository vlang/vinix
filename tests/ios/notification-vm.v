// SPDX-License-Identifier: GPL-2.0-or-later
// Standalone V build, staging and VM orchestration for native ABI checks.
module main

import os
import frozenv
import probebudget
import time
import tlsbuild

const llvm = '/opt/homebrew/opt/llvm/bin/clang'

fn checked(args []string) {
	println('IOS-BUILD-COMMAND: ' + args.join(' '))
	mut p := os.new_process(args[0])
	p.set_args(args[1..])
	frozenv.configure(mut p, args[0]) or { panic(err) }
	p.run()
	p.wait()
	defer { p.close() }
	if p.code != 0 { panic('${args[0]} exited ${p.code}') }
}

fn copy_file(source string, destination string) {
	os.mkdir_all(os.dir(destination)) or { panic(err) }
	checked(['/bin/cp', '-p', source, destination])
}

fn tree(source string, destination string) {
	os.mkdir_all(destination) or { panic(err) }
	checked(['/bin/cp', '-a', source + '/.', destination])
}

fn require_arm64_elf(path string) {
	mut file := os.open(path) or { panic(err) }
	defer { file.close() }
	mut header := []u8{len: 64}
	count := file.read(mut header) or { panic(err) }
	if count != 64 || header[..7] != [u8(0x7f), `E`, `L`, `F`, 2, 1, 1]
		|| header[16] !in [u8(2), 3] || header[17] != 0
		|| header[18] != 183 || header[19] != 0 {
		panic('invalid ARM64 ELF executable: ' + path)
	}
}

fn compile_c(root string, generated string, output string, gles bool) {
	sysroot := root + '/build/ios/fortnite/date-encoding-checks/sdk'
	gcc := root + '/build/useralloc-pipe/static-desktop-v5/sysroot/usr/lib/gcc/aarch64-alpine-linux-musl/14.2.0'
	mesa := root + '/build/ios/fortnite/date-encoding-checks/sdk'
	mut args := [llvm, '--target=aarch64-linux-musl', '-nostdinc', '-nostdlib', '-isystem',
		root + '/build-support/aarch64-cc-shim', '-isystem', gcc + '/include', '-isystem',
		sysroot + '/usr/include', '-O2', '-D_GNU_SOURCE', '-fno-stack-protector', '-w']
	args << ['-I'+root+'/build/ios/sqlite/source']
	args << ['-I'+root+'/build/ios/fortnite/video-decode-deps/arm64','-I'+root+'/build/ios/fortnite/video-decode-deps/source']
	if gles {
		args << ['-no-pie', '-isystem', mesa + '/usr/include', '-isystem',
			mesa + '/usr/include/freetype2']
	} else {
		args << '-static'
	}
	args << [sysroot + '/usr/lib/crt1.o', sysroot + '/usr/lib/crti.o',
		gcc + if gles { '/crtbegin.o' } else { '/crtbeginT.o' }, generated]
	// Newer V toolchains keep these runtime helpers outside generated C.
	vroot := root + '/build/ios/fortnite/ns-calendar-checks/toolchain'
	if !generated.ends_with('/native-init.c') {
		args << tlsbuild.includes(vroot)
		// TLS uses ARM intrinsics: pair clang with its own intrinsic headers.
		resource := os.exec([llvm, '--print-resource-dir'])
		if resource.exit_code != 0 { panic(resource.output) }
		args << tlsbuild.build(root, vroot, os.dir(output), [llvm, '--target=aarch64-linux-musl', '-nostdinc', '-isystem', root + '/build-support/aarch64-cc-shim', '-isystem', resource.output.trim_space() + '/include', '-isystem', sysroot + '/usr/include', '-D_GNU_SOURCE', '-ffixed-x18'])
	}
	for helper in ['os/execute_capture_nix.c', 'builtin/segfault_handler_nix.c']! {
		path := vroot + '/vlib/' + helper
		if os.exists(path) { args << path }
	}
	args << '-DCUSTOM_DEFINE_no_backtrace'
	if !generated.ends_with('/native-init.c') { args << root + '/compat/ios/runner/abi/dispatch.S' }
	args << ['-ffixed-x18', '-L' + sysroot + '/usr/lib', '-L' + gcc,
		root + '/build/ios/cxx/libcxx-ios.a', root + '/build/ios/cxx/sysroot/usr/lib/libc++abi.a',
		root + '/build/ios/cxx/sysroot/usr/lib/libunwind.a']
	if gles {
		args << ['-L' + root + '/build/ios/fortnite/staging/usr/lib/vinix/ios-gles', '-lEGL', '-lGLESv2',
			'-lfreetype', '-Wl,--dynamic-linker=/usr/lib/vinix/ios-gles/ld-musl-aarch64.so.1',
			'-Wl,-rpath,/usr/lib/vinix/ios-gles',
			'-Wl,-rpath-link,' + root + '/build/ios/fortnite/staging/usr/lib/vinix/ios-gles']
	}
	args << [root+'/build/ios/fortnite/video-decode-deps/arm64/libavcodec/libavcodec.a',root+'/build/ios/fortnite/video-decode-deps/arm64/libswscale/libswscale.a',root+'/build/ios/fortnite/video-decode-deps/arm64/libavutil/libavutil.a']
	args << root+'/build/ios/sqlite/arm64/libsqlite3.a'
	args << ['-lgcc_eh', '-lc', '-lgcc', '-lm', gcc + '/crtend.o', sysroot + '/usr/lib/crtn.o',
		'-fuse-ld=lld', '-B/opt/homebrew/opt/llvm/bin', '-o', output]
	checked(args)
	require_arm64_elf(output)
}

fn native_fixture_source(item string) string {
	return match item {
		'metal-device-checks' { 'metal_device_test.v' }
		'locale-preferred-checks' { 'ns_locale_preferred_test.v' }
		'bundle-info-checks' { 'ns_bundle_info_test.v' }
		'string-get-cstring-checks' { 'ns_string_get_cstring_test.v' }
		'dictionary-file-checks' { 'ns_dictionary_file_test.v' }
		'bundle-identifier-checks' { 'ns_bundle_identifier_test.v' }
		'string-path-checks' { 'ns_string_path_test.v' }
		'url-resource-checks' { 'ns_url_resource_test.v' }
		'number-bool-checks' { 'ns_number_bool_test.v' }
		'string-cstring-output-checks' { 'ns_string_cstring_output_test.v' }
		'string-normalization-checks' { 'ns_string_normalization_test.v' }
		'responder-checks' { 'ui_responder_test.v' }
		'view-tag-checks' { 'ui_view_tag_test.v' }
		'main-selector-checks' { 'ns_main_selector_test.v' }
		'application-badge-checks' { 'ui_application_badge_test.v' }
		'window-checks' { 'ui_window_test.v' }
		'string-float-checks' { 'ns_string_float_test.v' }
		'string-cstring-checks' { 'ns_string_cstring_test.v' }
		'bundle-receipt-checks' { 'ns_bundle_receipt_test.v' }
		'cf-string-output-checks' { 'cf_string_output_test.v' }
		'search-path-checks' { 'ns_search_paths_test.v' }
		'home-directory-checks' { 'ns_home_directory_test.v' }
		'inline-pthread-self-checks' { 'inline_pthread_self_test.v' }
		'dictionary-snapshot-checks' { 'objc_constant_dictionary_test.v' }
		'block-byref-checks' { 'block_byref_test.v' }
		'processinfo-checks' { 'ns_process_info_test.v' }
		'vm-probe-checks' { 'vm_probe_test.v' }
		'class-update-checks' { 'swift_class_update_test.v' }
		'native-value-checks' { 'swift_native_value_test.v' }
		'gk-match-request-checks' { 'gk_match_request_test.v' }
		'gk-achievement-checks' { 'gk_achievement_test.v' }
		'gk-player-checks' { 'gk_player_test.v' }
		'gk-turn-based-participant-checks' { 'gk_turn_based_participant_test.v' }
		'gk-turn-based-match-checks' { 'gk_turn_based_match_test.v' }
		'gk-local-player-checks' { 'gk_local_player_test.v' }
		'gk-leaderboard-checks' { 'gk_leaderboard_test.v' }
		'gk-achievement-description-checks' { 'gk_achievement_description_test.v' }
		'capture-audio-output-checks' { 'capture_audio_output_test.v' }
		'capture-discovery-checks' { 'capture_discovery_test.v' }
		'app-attest-checks' { 'app_attest_test.v' }
		'gc-event-view-controller-checks' { 'gc_event_view_controller_test.v' }
		'snapshot-configuration-checks' { 'wk_snapshot_configuration_test.v' }
		'text-field-checks' { 'ui_text_field_test.v' }
		'haptic-dynamic-parameter-checks' { 'ch_haptic_dynamic_parameter_test.v' }
		'haptic-pattern-checks' { 'ch_haptic_pattern_test.v' }
		'haptic-event-checks' { 'ch_haptic_event_test.v' }
		'haptic-event-parameter-checks' { 'ch_haptic_event_parameter_test.v' }
		'long-press-gesture-checks' { 'ui_long_press_gesture_test.v' }
		'tap-gesture-checks' { 'ui_tap_gesture_test.v' }
		'rotation-gesture-checks' { 'ui_rotation_gesture_test.v' }
		'pinch-gesture-checks' { 'ui_pinch_gesture_test.v' }
		'pan-gesture-checks' { 'ui_pan_gesture_test.v' }
		'text-input-checks' { 'ui_text_input_test.v' }
		'game-center-checks' { 'game_center_test.v' }
		'av-player-checks' { 'av_player_test.v' }
		'ns-proxy-checks' { 'ns_proxy_test.v' }
		'swift-object-checks' { 'swift_object_test.v' }
		'storekit-purchase-checks' { 'storekit_purchase_test.v' }
		'storyboard-checks' { 'ui_storyboard_test.v' }
		'audio-application-checks' { 'audio_application_test.v' }
		'game-controller-checks' { 'game_controller_test.v' }
		'session-task-checks' { 'ns_url_session_task_test.v' }
		'feedback-checks' { 'ui_feedback_test.v' }
		'adsupport-checks' { 'adsupport_test.v' }
		'bundle-resource-checks' { 'ns_bundle_resource_test.v' }
		'number-formatter-checks' { 'ns_number_formatter_test.v' }
		'date-formatter-checks' { 'date_formatter_test.v' }
		'lock-checks' { 'ns_lock_test.v' }
		'recursive-lock-checks' { 'ns_recursive_lock_test.v' }
		'map-table-checks' { 'ns_map_table_test.v' }
		'credential-checks' { 'ns_url_credential_test.v' }
		'telephony-checks' { 'coretelephony_test.v' }
		'cache-checks' { 'ns_cache_test.v' }
		'notification-attachment-checks' { 'un_notification_attachment_test.v' }
		'notification-sound-checks' { 'un_notification_sound_test.v' }
		'notification-content-checks' { 'un_notification_content_test.v' }
		'notification-center-checks' { 'un_notification_center_test.v' }
		'notification-request-checks' { 'un_notification_request_test.v' }
		'calendar-trigger-checks' { 'un_calendar_trigger_test.v' }
		'calendar-checks' { 'ns_calendar_test.v' }
		else { panic('unknown calendar regression fixture') }
	}
}

fn build(root string, out string, only string) {
	if only !in ['metal-device-checks', 'locale-preferred-checks', 'bundle-info-checks', 'string-get-cstring-checks', 'dictionary-file-checks', 'bundle-identifier-checks', 'string-path-checks', 'url-resource-checks', 'number-bool-checks', 'string-cstring-output-checks', 'string-normalization-checks', 'responder-checks', 'view-tag-checks', 'main-selector-checks', 'application-badge-checks', 'window-checks', 'string-float-checks', 'string-cstring-checks', 'bundle-receipt-checks', 'cf-string-output-checks', 'search-path-checks', 'home-directory-checks', 'inline-pthread-self-checks', 'dictionary-snapshot-checks', 'block-byref-checks', 'processinfo-checks', 'vm-probe-checks', 'class-update-checks', 'native-value-checks', 'capture-audio-output-checks', 'gk-match-request-checks', 'gk-achievement-checks', 'gk-achievement-description-checks', 'gk-player-checks', 'gk-turn-based-participant-checks', 'gk-turn-based-match-checks', 'gk-local-player-checks', 'gk-leaderboard-checks', 'capture-discovery-checks', 'app-attest-checks', 'gc-event-view-controller-checks', 'snapshot-configuration-checks', 'text-field-checks', 'haptic-dynamic-parameter-checks', 'haptic-pattern-checks', 'haptic-event-checks', 'haptic-event-parameter-checks', 'long-press-gesture-checks', 'tap-gesture-checks', 'rotation-gesture-checks', 'pinch-gesture-checks', 'pan-gesture-checks', 'text-input-checks', 'game-center-checks', 'av-player-checks', 'ns-proxy-checks', 'swift-object-checks', 'storekit-purchase-checks', 'storyboard-checks', 'audio-application-checks', 'game-controller-checks', 'session-task-checks', 'feedback-checks', 'adsupport-checks', 'bundle-resource-checks', 'number-formatter-checks', 'date-formatter-checks', 'lock-checks', 'recursive-lock-checks', 'map-table-checks', 'credential-checks', 'telephony-checks', 'cache-checks', 'notification-attachment-checks', 'notification-sound-checks', 'notification-content-checks', 'notification-center-checks', 'notification-request-checks', 'calendar-trigger-checks', 'calendar-checks','native-init','run-ios','run-ios-gles']! { panic('unknown notification build target') }
	for item in ['metal-device-checks', 'locale-preferred-checks', 'bundle-info-checks', 'string-get-cstring-checks', 'dictionary-file-checks', 'bundle-identifier-checks', 'string-path-checks', 'url-resource-checks', 'number-bool-checks', 'string-cstring-output-checks', 'string-normalization-checks', 'responder-checks', 'view-tag-checks', 'main-selector-checks', 'application-badge-checks', 'window-checks', 'string-float-checks', 'string-cstring-checks', 'bundle-receipt-checks', 'cf-string-output-checks', 'search-path-checks', 'home-directory-checks', 'inline-pthread-self-checks', 'dictionary-snapshot-checks', 'block-byref-checks', 'processinfo-checks', 'vm-probe-checks', 'class-update-checks', 'native-value-checks', 'capture-audio-output-checks', 'gk-match-request-checks', 'gk-achievement-checks', 'gk-achievement-description-checks', 'gk-player-checks', 'gk-turn-based-participant-checks', 'gk-turn-based-match-checks', 'gk-local-player-checks', 'gk-leaderboard-checks', 'capture-discovery-checks', 'app-attest-checks', 'gc-event-view-controller-checks', 'snapshot-configuration-checks', 'text-field-checks', 'haptic-dynamic-parameter-checks', 'haptic-pattern-checks', 'haptic-event-checks', 'haptic-event-parameter-checks', 'long-press-gesture-checks', 'tap-gesture-checks', 'rotation-gesture-checks', 'pinch-gesture-checks', 'pan-gesture-checks', 'text-input-checks', 'game-center-checks', 'av-player-checks', 'ns-proxy-checks', 'swift-object-checks', 'storekit-purchase-checks', 'storyboard-checks', 'audio-application-checks', 'game-controller-checks', 'session-task-checks', 'feedback-checks', 'adsupport-checks', 'bundle-resource-checks', 'number-formatter-checks', 'date-formatter-checks', 'lock-checks', 'recursive-lock-checks', 'map-table-checks', 'credential-checks', 'telephony-checks', 'cache-checks', 'notification-attachment-checks', 'notification-sound-checks', 'notification-content-checks', 'notification-center-checks', 'notification-request-checks', 'calendar-trigger-checks', 'calendar-checks','native-init','run-ios','run-ios-gles']! {
		if only != '' && item != only { continue }
		generated := out + '/' + item + '.c'
		if item == 'native-init' {
			checked([root + '/build/ios/fortnite/ns-calendar-checks/toolchain/v', '-enable-globals','-nocache', '-cc', 'clang', '-os', 'linux', '-arch', 'arm64', '-gc', 'none', '-prod', '-d', 'no_backtrace',
				'-path', '@vlib|' + root + '/compat/ios|' + root + '/tests/ios|@vmodules',
				'-o', generated, root + '/tests/ios/native-init.v'])
		} else {
			mut args := [root + '/build/ios/fortnite/ns-calendar-checks/toolchain/v', '-enable-globals','-nocache', '-cc', 'clang', '-os', 'linux', '-arch', 'arm64', '-enable-globals', '-gc', 'none',
				'-prod', '-d', 'ios_video', '-d', 'glibc', '-d', 'no_backtrace', '-d', 'ios_cxx', '-d', 'ios_sqlite', '-path',
				'@vlib|' + root + '/compat/ios|' + root + '/tests/ios|@vmodules', '-o', generated]
			if item.ends_with('-checks') { args = args.filter(it != '-prod') }
			if item in ['run-ios-gles']! { args << ['-d', 'ios_gles', '-d', 'ios_text'] }
			args << root + if item.ends_with('-checks') {
				'/compat/ios/runner/' + native_fixture_source(item)
			} else {
				'/compat/ios/runner'
			}
			checked(args)
		}
		compile_c(root, generated, out + '/' + item, item in ['run-ios-gles']!)
		println('Built ${item}')
	}
}

fn await_checks(mut p os.Process, log string, marker string, timeout_seconds int) ! {
	for _ in 0 .. timeout_seconds * 5 {
		text := os.read_file(log) or { '' }
		if text.contains('iOS FAIL:') || text.contains('IOS-NATIVE: FAIL')
			|| text.contains('> assert ')
			|| text.contains('KERNEL PANIC') || text.contains('FATAL EXCEPTION')
			|| (text.contains('EXCEPTION') && text.contains('pc=0xffffffff'))
			|| (marker in ['VINIX iOS CLASSUPDATE: PASS', 'VINIX iOS NATIVEVALUE: PASS', 'VINIX iOS CAPTUREDISCOVERY: PASS', 'VINIX iOS APPATTEST: PASS', 'VINIX iOS GCEVENT: PASS', 'VINIX iOS HAPTICEVENT: PASS', 'VINIX iOS HAPTICEVENTPARAMETER: PASS', 'VINIX iOS LONGPRESSGESTURE: PASS', 'VINIX iOS TAPGESTURE: PASS', 'VINIX iOS ROTATIONGESTURE: PASS', 'VINIX iOS PINCHGESTURE: PASS', 'VINIX iOS PANGESTURE: PASS', 'VINIX iOS TEXTINPUT: PASS', 'VINIX iOS GAMECENTER: PASS', 'VINIX iOS STORYBOARD: PASS', 'VINIX iOS AUDIOAPPLICATION: PASS', 'VINIX iOS NOTIFICATIONS: PASS', 'VINIX iOS FEEDBACK: PASS', 'VINIX iOS SESSIONTASK: PASS', 'VINIX iOS GAMECONTROLLER: PASS'] && text.contains('V panic:')) {
			return error(text)
		}
		if text.contains(marker) { return }
		if !p.is_alive() { return error('QEMU exited before ' + marker + ': ' + p.stderr_slurp()) }
		time.sleep(200 * time.millisecond)
	}
	return error('VM timeout: ' + log)
}

fn vm(root string, out string, mode string) {
	desktop := os.getenv('VINIX_IOS_PROBE_DESKTOP')
	if desktop !in ['', '1'] || (desktop == '1' && mode != 'probe-no-ads') {
		panic('VINIX_IOS_PROBE_DESKTOP=1 requires probe-no-ads')
	}
	cooked := os.getenv('VINIX_IOS_COOKED_BUNDLE')
	if cooked != '' && (mode != 'probe-no-ads' || !os.is_file(cooked + '/uecommandline.txt')
		|| !os.is_dir(cooked + '/cookeddata')) {
		panic('VINIX_IOS_COOKED_BUNDLE requires probe-no-ads and an extracted cooked bundle')
	}
	mut budget := ''
	if configured := os.getenv_opt('VINIX_IOS_PROBE_MEMORY_MAX') {
		if mode != 'probe-no-ads' { panic('VINIX_IOS_PROBE_MEMORY_MAX requires probe-no-ads') }
		bytes := probebudget.parse(configured) or { panic(err) }
		budget = bytes.str()
	}
	if mode !in ['class-update', 'native-value', 'capture-audio-output', 'gk-match-request', 'gk-achievement', 'gk-achievement-description', 'gk-player', 'gk-turn-based-participant', 'gk-turn-based-match', 'gk-local-player', 'gk-leaderboard', 'capture-discovery', 'app-attest', 'gc-event-view-controller', 'snapshot-configuration', 'text-field', 'haptic-dynamic-parameter', 'haptic-pattern', 'haptic-event', 'haptic-event-parameter', 'long-press-gesture', 'tap-gesture', 'rotation-gesture', 'pinch-gesture', 'pan-gesture', 'text-input', 'game-center', 'av-player', 'ns-proxy', 'swift-object', 'storekit-purchase', 'storyboard', 'audio-application', 'game-controller', 'session-task', 'feedback', 'notifications', 'probe', 'probe-no-ads', 'audit', 'static-audit'] {
		panic('invalid check mode: ' + mode)
	}
	require_arm64_elf(out + '/native-init')
	if mode == 'class-update' {
		require_arm64_elf(out + '/class-update-checks')
	} else if mode == 'native-value' {
		require_arm64_elf(out + '/native-value-checks')
	} else if mode == 'gk-match-request' {
		require_arm64_elf(out + '/gk-match-request-checks')
	} else if mode == 'gk-achievement' {
		require_arm64_elf(out + '/gk-achievement-checks')
	} else if mode == 'gk-turn-based-match' {
		require_arm64_elf(out + '/gk-turn-based-match-checks')
	} else if mode == 'gk-local-player' {
		require_arm64_elf(out + '/gk-local-player-checks')
	} else if mode == 'gk-leaderboard' {
		require_arm64_elf(out + '/gk-leaderboard-checks')
	} else if mode == 'gk-turn-based-participant' {
		require_arm64_elf(out + '/gk-turn-based-participant-checks')
	} else if mode == 'gk-player' {
		require_arm64_elf(out + '/gk-player-checks')
	} else if mode == 'gk-achievement-description' {
		require_arm64_elf(out + '/gk-achievement-description-checks')
	} else if mode == 'capture-audio-output' {
		require_arm64_elf(out + '/capture-audio-output-checks')
	} else if mode == 'capture-discovery' {
		require_arm64_elf(out + '/capture-discovery-checks')
	} else if mode == 'app-attest' {
		require_arm64_elf(out + '/app-attest-checks')
	} else if mode == 'gc-event-view-controller' {
		require_arm64_elf(out + '/gc-event-view-controller-checks')
	} else if mode == 'snapshot-configuration' {
		require_arm64_elf(out + '/snapshot-configuration-checks')
	} else if mode == 'text-field' {
		require_arm64_elf(out + '/text-field-checks')
	} else if mode == 'haptic-dynamic-parameter' {
		require_arm64_elf(out + '/haptic-dynamic-parameter-checks')
	} else if mode == 'haptic-pattern' {
		require_arm64_elf(out + '/haptic-pattern-checks')
	} else if mode == 'haptic-event' {
		require_arm64_elf(out + '/haptic-event-checks')
	} else if mode == 'haptic-event-parameter' {
		require_arm64_elf(out + '/haptic-event-parameter-checks')
	} else if mode == 'long-press-gesture' {
		require_arm64_elf(out + '/long-press-gesture-checks')
	} else if mode == 'tap-gesture' {
		require_arm64_elf(out + '/tap-gesture-checks')
	} else if mode == 'rotation-gesture' {
		require_arm64_elf(out + '/rotation-gesture-checks')
	} else if mode == 'pinch-gesture' {
		require_arm64_elf(out + '/pinch-gesture-checks')
	} else if mode == 'pan-gesture' {
		require_arm64_elf(out + '/pan-gesture-checks')
	} else if mode == 'text-input' {
		require_arm64_elf(out + '/text-input-checks')
	} else if mode == 'game-center' {
		require_arm64_elf(out + '/game-center-checks')
	} else if mode == 'av-player' {
		require_arm64_elf(out + '/av-player-checks')
	} else if mode == 'ns-proxy' {
		require_arm64_elf(out + '/ns-proxy-checks')
	} else if mode == 'swift-object' {
		require_arm64_elf(out + '/swift-object-checks')
	} else if mode == 'storekit-purchase' {
		require_arm64_elf(out + '/storekit-purchase-checks')
	} else if mode == 'storyboard' {
		require_arm64_elf(out + '/storyboard-checks')
	} else if mode == 'audio-application' {
		require_arm64_elf(out + '/audio-application-checks')
	} else if mode == 'game-controller' {
		require_arm64_elf(out + '/game-controller-checks')
	} else if mode == 'session-task' {
		require_arm64_elf(out + '/session-task-checks')
	} else if mode == 'feedback' {
		require_arm64_elf(out + '/feedback-checks')
	} else if mode == 'notifications' {
		for item in ['class-update-checks', 'native-value-checks', 'capture-audio-output-checks', 'gk-match-request-checks', 'gk-achievement-checks', 'gk-achievement-description-checks', 'gk-player-checks', 'gk-turn-based-participant-checks', 'gk-turn-based-match-checks', 'gk-local-player-checks', 'gk-leaderboard-checks', 'capture-discovery-checks', 'app-attest-checks', 'gc-event-view-controller-checks', 'snapshot-configuration-checks', 'text-field-checks', 'haptic-dynamic-parameter-checks', 'haptic-pattern-checks', 'haptic-event-checks', 'haptic-event-parameter-checks', 'long-press-gesture-checks', 'tap-gesture-checks', 'rotation-gesture-checks', 'pinch-gesture-checks', 'pan-gesture-checks', 'text-input-checks', 'game-center-checks', 'av-player-checks', 'ns-proxy-checks', 'swift-object-checks', 'storekit-purchase-checks', 'storyboard-checks', 'audio-application-checks', 'game-controller-checks', 'session-task-checks', 'feedback-checks', 'adsupport-checks', 'bundle-resource-checks', 'number-formatter-checks', 'date-formatter-checks', 'lock-checks', 'recursive-lock-checks', 'map-table-checks', 'credential-checks', 'telephony-checks', 'cache-checks', 'notification-attachment-checks', 'notification-sound-checks', 'notification-content-checks', 'notification-center-checks', 'notification-request-checks', 'calendar-trigger-checks', 'calendar-checks'] {
			require_arm64_elf(out + '/' + item)
		}
	} else {
		require_arm64_elf(out + if mode == 'static-audit' { '/run-ios' } else { '/run-ios-gles' })
	}
	state := out + '/' + mode + '-' + time.sys_mono_now().str()
	if os.exists(state) { panic('VM state already exists') }
	os.write_file(out + '/' + mode + '-state.txt', state) or { panic(err) }
	os.mkdir_all(state) or { panic(err) }
	payload := state
	os.mkdir_all(payload + '/rootfs') or { panic(err) }
	fs := payload + '/rootfs'
	copy_file('/etc/ssl/cert.pem', fs + '/etc/ssl/cert.pem')
	if mode == 'class-update' {
		copy_file(out + '/class-update-checks', fs + '/opt/ios/class-update-checks')
	} else if mode == 'native-value' {
		copy_file(out + '/native-value-checks', fs + '/opt/ios/native-value-checks')
	} else if mode == 'gk-match-request' {
		copy_file(out + '/gk-match-request-checks', fs + '/opt/ios/gk-match-request-checks')
	} else if mode == 'gk-achievement' {
		copy_file(out + '/gk-achievement-checks', fs + '/opt/ios/gk-achievement-checks')
	} else if mode == 'gk-turn-based-match' {
		copy_file(out + '/gk-turn-based-match-checks', fs + '/opt/ios/gk-turn-based-match-checks')
	} else if mode == 'gk-local-player' {
		copy_file(out + '/gk-local-player-checks', fs + '/opt/ios/gk-local-player-checks')
	} else if mode == 'gk-leaderboard' {
		copy_file(out + '/gk-leaderboard-checks', fs + '/opt/ios/gk-leaderboard-checks')
	} else if mode == 'gk-turn-based-participant' {
		copy_file(out + '/gk-turn-based-participant-checks', fs + '/opt/ios/gk-turn-based-participant-checks')
	} else if mode == 'gk-player' {
		copy_file(out + '/gk-player-checks', fs + '/opt/ios/gk-player-checks')
	} else if mode == 'gk-achievement-description' {
		copy_file(out + '/gk-achievement-description-checks', fs + '/opt/ios/gk-achievement-description-checks')
	} else if mode == 'capture-audio-output' {
		copy_file(out + '/capture-audio-output-checks', fs + '/opt/ios/capture-audio-output-checks')
	} else if mode == 'capture-discovery' {
		copy_file(out + '/capture-discovery-checks', fs + '/opt/ios/capture-discovery-checks')
	} else if mode == 'app-attest' {
		copy_file(out + '/app-attest-checks', fs + '/opt/ios/app-attest-checks')
	} else if mode == 'gc-event-view-controller' {
		copy_file(out + '/gc-event-view-controller-checks', fs + '/opt/ios/gc-event-view-controller-checks')
	} else if mode == 'snapshot-configuration' {
		copy_file(out + '/snapshot-configuration-checks', fs + '/opt/ios/snapshot-configuration-checks')
	} else if mode == 'text-field' {
		copy_file(out + '/text-field-checks', fs + '/opt/ios/text-field-checks')
	} else if mode == 'haptic-dynamic-parameter' {
		copy_file(out + '/haptic-dynamic-parameter-checks', fs + '/opt/ios/haptic-dynamic-parameter-checks')
	} else if mode == 'haptic-pattern' {
		copy_file(out + '/haptic-pattern-checks', fs + '/opt/ios/haptic-pattern-checks')
	} else if mode == 'haptic-event' {
		copy_file(out + '/haptic-event-checks', fs + '/opt/ios/haptic-event-checks')
	} else if mode == 'haptic-event-parameter' {
		copy_file(out + '/haptic-event-parameter-checks', fs + '/opt/ios/haptic-event-parameter-checks')
	} else if mode == 'long-press-gesture' {
		copy_file(out + '/long-press-gesture-checks', fs + '/opt/ios/long-press-gesture-checks')
	} else if mode == 'tap-gesture' {
		copy_file(out + '/tap-gesture-checks', fs + '/opt/ios/tap-gesture-checks')
	} else if mode == 'rotation-gesture' {
		copy_file(out + '/rotation-gesture-checks', fs + '/opt/ios/rotation-gesture-checks')
	} else if mode == 'pinch-gesture' {
		copy_file(out + '/pinch-gesture-checks', fs + '/opt/ios/pinch-gesture-checks')
	} else if mode == 'pan-gesture' {
		copy_file(out + '/pan-gesture-checks', fs + '/opt/ios/pan-gesture-checks')
	} else if mode == 'text-input' {
		copy_file(out + '/text-input-checks', fs + '/opt/ios/text-input-checks')
	} else if mode == 'game-center' {
		copy_file(out + '/game-center-checks', fs + '/opt/ios/game-center-checks')
	} else if mode == 'av-player' {
		copy_file(out + '/av-player-checks', fs + '/opt/ios/av-player-checks')
	} else if mode == 'ns-proxy' {
		copy_file(out + '/ns-proxy-checks', fs + '/opt/ios/ns-proxy-checks')
	} else if mode == 'swift-object' {
		copy_file(out + '/swift-object-checks', fs + '/opt/ios/swift-object-checks')
	} else if mode == 'storekit-purchase' {
		copy_file(out + '/storekit-purchase-checks', fs + '/opt/ios/storekit-purchase-checks')
	} else if mode == 'storyboard' {
		copy_file(out + '/storyboard-checks', fs + '/opt/ios/storyboard-checks')
	} else if mode == 'audio-application' {
		copy_file(out + '/audio-application-checks', fs + '/opt/ios/audio-application-checks')
	} else if mode == 'game-controller' {
		copy_file(out + '/game-controller-checks', fs + '/opt/ios/game-controller-checks')
	} else if mode == 'session-task' {
		copy_file(out + '/session-task-checks', fs + '/opt/ios/session-task-checks')
	} else if mode == 'feedback' {
		copy_file(out + '/feedback-checks', fs + '/opt/ios/feedback-checks')
	} else if mode == 'notifications' {
		copy_file(out + '/class-update-checks', fs + '/opt/ios/class-update-checks')
		copy_file(out + '/native-value-checks', fs + '/opt/ios/native-value-checks')
		copy_file(out + '/gk-match-request-checks', fs + '/opt/ios/gk-match-request-checks')
		copy_file(out + '/gk-achievement-checks', fs + '/opt/ios/gk-achievement-checks')
		copy_file(out + '/gk-player-checks', fs + '/opt/ios/gk-player-checks')
		copy_file(out + '/gk-turn-based-participant-checks', fs + '/opt/ios/gk-turn-based-participant-checks')
		copy_file(out + '/gk-turn-based-match-checks', fs + '/opt/ios/gk-turn-based-match-checks')
		copy_file(out + '/gk-local-player-checks', fs + '/opt/ios/gk-local-player-checks')
		copy_file(out + '/gk-leaderboard-checks', fs + '/opt/ios/gk-leaderboard-checks')
		copy_file(out + '/gk-achievement-description-checks', fs + '/opt/ios/gk-achievement-description-checks')
		copy_file(out + '/capture-audio-output-checks', fs + '/opt/ios/capture-audio-output-checks')
		copy_file(out + '/capture-discovery-checks', fs + '/opt/ios/capture-discovery-checks')
		copy_file(out + '/app-attest-checks', fs + '/opt/ios/app-attest-checks')
		copy_file(out + '/gc-event-view-controller-checks', fs + '/opt/ios/gc-event-view-controller-checks')
		copy_file(out + '/snapshot-configuration-checks', fs + '/opt/ios/snapshot-configuration-checks')
		copy_file(out + '/text-field-checks', fs + '/opt/ios/text-field-checks')
		copy_file(out + '/haptic-dynamic-parameter-checks', fs + '/opt/ios/haptic-dynamic-parameter-checks')
		copy_file(out + '/haptic-pattern-checks', fs + '/opt/ios/haptic-pattern-checks')
		copy_file(out + '/haptic-event-checks', fs + '/opt/ios/haptic-event-checks')
		copy_file(out + '/haptic-event-parameter-checks', fs + '/opt/ios/haptic-event-parameter-checks')
		copy_file(out + '/long-press-gesture-checks', fs + '/opt/ios/long-press-gesture-checks')
		copy_file(out + '/tap-gesture-checks', fs + '/opt/ios/tap-gesture-checks')
		copy_file(out + '/rotation-gesture-checks', fs + '/opt/ios/rotation-gesture-checks')
		copy_file(out + '/pinch-gesture-checks', fs + '/opt/ios/pinch-gesture-checks')
		copy_file(out + '/pan-gesture-checks', fs + '/opt/ios/pan-gesture-checks')
		copy_file(out + '/text-input-checks', fs + '/opt/ios/text-input-checks')
		copy_file(out + '/game-center-checks', fs + '/opt/ios/game-center-checks')
		copy_file(out + '/av-player-checks', fs + '/opt/ios/av-player-checks')
		copy_file(out + '/ns-proxy-checks', fs + '/opt/ios/ns-proxy-checks')
		copy_file(out + '/swift-object-checks', fs + '/opt/ios/swift-object-checks')
		copy_file(out + '/storekit-purchase-checks', fs + '/opt/ios/storekit-purchase-checks')
		copy_file(out + '/storyboard-checks', fs + '/opt/ios/storyboard-checks')
		copy_file(out + '/audio-application-checks', fs + '/opt/ios/audio-application-checks')
		for directory in ['sbin', 'proc', 'sys', 'dev', 'tmp', 'opt/ios'] {
			os.mkdir_all(fs + '/' + directory) or { panic(err) }
		}
		copy_file(out + '/calendar-checks', fs + '/opt/ios/calendar-checks')
		copy_file(out + '/session-task-checks', fs + '/opt/ios/session-task-checks')
		copy_file(out + '/game-controller-checks', fs + '/opt/ios/game-controller-checks')
		copy_file(out + '/adsupport-checks', fs + '/opt/ios/adsupport-checks')
		copy_file(out + '/feedback-checks', fs + '/opt/ios/feedback-checks')
		copy_file(out + '/bundle-resource-checks', fs + '/opt/ios/bundle-resource-checks')
		copy_file(out + '/number-formatter-checks', fs + '/opt/ios/number-formatter-checks')
		copy_file(out + '/date-formatter-checks', fs + '/opt/ios/date-formatter-checks')
		copy_file(out + '/calendar-trigger-checks', fs + '/opt/ios/calendar-trigger-checks')
		copy_file(out + '/notification-request-checks', fs + '/opt/ios/notification-request-checks')
		copy_file(out + '/notification-center-checks', fs + '/opt/ios/notification-center-checks')
		copy_file(out + '/notification-content-checks', fs + '/opt/ios/notification-content-checks')
		copy_file(out + '/notification-sound-checks', fs + '/opt/ios/notification-sound-checks')
		copy_file(out + '/cache-checks', fs + '/opt/ios/cache-checks')
		copy_file(out + '/lock-checks', fs + '/opt/ios/lock-checks')
		copy_file(out + '/recursive-lock-checks', fs + '/opt/ios/recursive-lock-checks')
		copy_file(out + '/map-table-checks', fs + '/opt/ios/map-table-checks')
		copy_file(out + '/credential-checks', fs + '/opt/ios/credential-checks')
		copy_file(out + '/telephony-checks', fs + '/opt/ios/telephony-checks')
		copy_file(out + '/notification-attachment-checks', fs + '/opt/ios/notification-attachment-checks')
		tree(root+'/build/ios/fortnite/staging/usr/lib/vinix/ios-gles',fs+'/usr/lib/vinix/ios-gles')
	} else {
		os.mkdir_all(fs + '/opt/ios') or { panic(err) }
		tree(root + '/build/ios/fortnite/local/Payload/FortniteClient-IOS-Shipping.app/Frameworks', fs + '/opt/ios/Frameworks')
		copy_file(out + '/' + if mode == 'static-audit' { 'run-ios' } else { 'run-ios-gles' }, fs + '/opt/ios/run-ios')
		if mode == 'probe-no-ads' {
			// Keep full cooked game content opt-in: historical checkpoints only
			// supplied the launch screen. Paths are relative to NSBundle's root.
			if cooked != '' {
				copy_file(cooked + '/uecommandline.txt', fs + '/opt/ios/uecommandline.txt')
				tree(cooked + '/cookeddata', fs + '/opt/ios/cookeddata')
			}
			// Opt-in resource overlay for the compiled launch-screen checkpoint.
			// The preserved base archive and historical probes stay reproducible.
			if bundle := os.getenv_opt('VINIX_IOS_STORYBOARD_BUNDLE') {
				for resource in ['Info.plist', 'LaunchScreen.storyboardc/Info.plist',
					'LaunchScreen.storyboardc/LaunchScreen.nib',
					'LaunchScreen.storyboardc/01J-lp-oVM-view-Ze5-6b-2t3.nib', 'LaunchScreenIOS.png']! {
					copy_file(bundle + '/' + resource, fs + '/opt/ios/' + resource)
				}
			}
			copy_file(out + '/responder-checks', fs + '/opt/ios/responder-checks')
			if os.exists(out + '/dictionary-file-checks') {
				copy_file(out + '/dictionary-file-checks', fs + '/opt/ios/dictionary-file-checks')
			}
			if os.exists(out + '/metal-device-checks') {
				copy_file(out + '/metal-device-checks', fs + '/opt/ios/metal-device-checks')
			}
			if os.exists(out + '/locale-preferred-checks') {
				copy_file(out + '/locale-preferred-checks', fs + '/opt/ios/locale-preferred-checks')
			}
			if os.exists(out + '/bundle-info-checks') {
				copy_file(out + '/bundle-info-checks', fs + '/opt/ios/bundle-info-checks')
			}
			if os.exists(out + '/bundle-identifier-checks') {
				copy_file(out + '/bundle-identifier-checks', fs + '/opt/ios/bundle-identifier-checks')
			}
			if os.exists(out + '/string-get-cstring-checks') {
				copy_file(out + '/string-get-cstring-checks', fs + '/opt/ios/string-get-cstring-checks')
			}
			if os.exists(out + '/string-path-checks') {
				copy_file(out + '/string-path-checks', fs + '/opt/ios/string-path-checks')
			}
			if os.exists(out + '/url-resource-checks') {
				copy_file(out + '/url-resource-checks', fs + '/opt/ios/url-resource-checks')
			}
			if os.exists(out + '/number-bool-checks') {
				copy_file(out + '/number-bool-checks', fs + '/opt/ios/number-bool-checks')
			}
			if os.exists(out + '/string-cstring-output-checks') {
				copy_file(out + '/string-cstring-output-checks', fs + '/opt/ios/string-cstring-output-checks')
			}
			if os.exists(out + '/string-normalization-checks') {
				copy_file(out + '/string-normalization-checks', fs + '/opt/ios/string-normalization-checks')
			}
			copy_file(out + '/view-tag-checks', fs + '/opt/ios/view-tag-checks')
			copy_file(out + '/main-selector-checks', fs + '/opt/ios/main-selector-checks')
			copy_file(out + '/application-badge-checks', fs + '/opt/ios/application-badge-checks')
			copy_file(out + '/window-checks', fs + '/opt/ios/window-checks')
			copy_file(out + '/string-float-checks', fs + '/opt/ios/string-float-checks')
			copy_file(out + '/string-cstring-checks', fs + '/opt/ios/string-cstring-checks')
			copy_file(out + '/bundle-receipt-checks', fs + '/opt/ios/bundle-receipt-checks')
			copy_file(out + '/cf-string-output-checks', fs + '/opt/ios/cf-string-output-checks')
			copy_file(out + '/search-path-checks', fs + '/opt/ios/search-path-checks')
			copy_file(out + '/home-directory-checks', fs + '/opt/ios/home-directory-checks')
			copy_file(out + '/processinfo-checks', fs + '/opt/ios/processinfo-checks')
			copy_file(out + '/vm-probe-checks', fs + '/opt/ios/vm-probe-checks')
			copy_file(out + '/block-byref-checks', fs + '/opt/ios/block-byref-checks')
			copy_file(out + '/inline-pthread-self-checks', fs + '/opt/ios/inline-pthread-self-checks')
			copy_file(out + '/dictionary-snapshot-checks', fs + '/opt/ios/dictionary-snapshot-checks')
		}
		tree(root + '/build/ios/fortnite/staging/usr/lib/vinix/ios-gles', fs + '/usr/lib/vinix/ios-gles')
	}
	copy_file(out + '/native-init', fs + '/sbin/init')
	if mode == 'notifications' {
		os.mkdir_all(fs + '/etc') or { panic(err) }
		os.write_file(fs + '/etc/resolv.conf', 'nameserver 127.0.0.1\noptions timeout:1 attempts:1\n') or { panic(err) }
	}
	os.write_file(fs + '/opt/ios/check-mode', if mode.contains('audit') { 'audit' } else { mode }) or { panic(err) }
	// Explicitly overlay an empty value for unmanaged runs, even if the base
	// archive was made from a previous budgeted probe.
	os.write_file(fs + '/opt/ios/probe-memory-max', budget) or { panic(err) }
	os.write_file(fs + '/opt/ios/probe-desktop', desktop) or { panic(err) }
	println('VM probe memory.max: ' + if budget == '' { 'unmanaged' } else { budget })
	archive := state + '/initramfs.tar.gz'
	// Higher compression lets full-IPA audits preserve complete guest media
	// on hosts with little free space. Keep the level in the captured log.
	compression := os.getenv_opt('VINIX_IOS_VM_GZIP_LEVEL') or { '1' }
	if compression !in ['1', '2', '3', '4', '5', '6', '7', '8', '9'] {
		panic('VINIX_IOS_VM_GZIP_LEVEL must be 1 through 9')
	}
	println('VM initramfs gzip compression level: ' + compression)
	gzip_option := 'gzip:compression-level=' + compression
	if mode in ['probe', 'probe-no-ads', 'audit', 'static-audit'] {
		// This Mac's libarchive copies the preserved IPA executable directly
		// between archives. Omit its old runner; the overlay path starts ./
		// and supplies exactly one current replacement. No large extraction.
		checked(['tar', '--format=ustar', '--options', gzip_option, '-czf', archive, '-s', ',^opt/ios/run-ios$,,',
			'@' + root + '/build/ios/fortnite/probe-initramfs.tar.gz', '-C', fs, '.'])
	} else {
		checked(['tar', '--format=ustar', '--options', gzip_option, '-czf', archive, '-C', fs, '.'])
	}
	// Release staged files once the complete archive is ready.
	os.rmdir_all(fs) or { panic(err) }
	disk := state + '/boot.img'
	// Cooked content can exceed the old fixed 384 MiB FAT image. Include
	// filesystem overhead and the kernel; retain the old size for small probes.
	archive_mb := (os.file_size(archive) + 1024 * 1024 - 1) / (1024 * 1024)
	boot_mb := if archive_mb + 128 > 384 { ((archive_mb + 128 + 63) / 64) * 64 } else { u64(384) }
	checked(['mkfile', '-n', boot_mb.str() + 'm', disk])
	checked(['mformat', '-F', '-i', disk, '::'])
	for path in ['::/EFI', '::/EFI/BOOT', '::/boot'] { checked(['mmd', '-i', disk, path]) }
	conf := state + '/limine.conf'
	os.write_file(conf, 'timeout: 0\nverbose: yes\n/Vinix\n    protocol: limine\n    kernel_path: boot():/boot/vinix\n    module_path: \$boot():/boot/initramfs.tar.gz\n    resolution: 1024x768x32\n    kbacktracer: no\n') or { panic(err) }
	for source, target in {
		root + '/boot-image/limine-bin/BOOTAA64.EFI':               '::/EFI/BOOT/BOOTAA64.EFI'
		conf:                                                       '::/boot/limine.conf'
		root + '/build/ios/fortnite/socket-kernel-arm64/bin/vinix': '::/boot/vinix'
		archive:                                                    '::/boot/initramfs.tar.gz'
	} {
		checked(['mcopy', '-i', disk, source, target])
	}
	run_vm(mode, state, if cooked != '' { '8192' } else { '4096' },
		if cooked != '' { 1800 } else { 240 })
}

fn run_vm(mode string, state string, guest_mb string, timeout_seconds int) {
	disk := state + '/boot.img'
	vars := state + '/efivars.fd'
	checked(['mkfile', '-n', '64m', vars])
	log := state + '/serial.log'
	mut p := os.new_process('/opt/homebrew/bin/qemu-system-aarch64')
	println('VM startup limit: ${timeout_seconds} seconds; guest memory: ${guest_mb} MiB')
	p.set_args(['-machine', 'virt,gic-version=3', '-accel', 'hvf', '-cpu', 'host', '-m', guest_mb,
		'-smp', '4', '-device', 'ramfb', '-display', 'none', '-monitor', 'none', '-serial',
		'file:' + log, '-drive',
		'if=pflash,format=raw,readonly=on,file=/opt/homebrew/share/qemu/edk2-aarch64-code.fd',
		'-drive', 'if=pflash,format=raw,file=' + vars, '-drive', 'format=raw,file=' + disk, '-device',
		'virtio-keyboard-device', '-device', 'virtio-tablet-device'])
	p.set_redirect_stdio()
	p.run()
	marker := if mode == 'class-update' { 'VINIX iOS CLASSUPDATE: PASS' } else if mode == 'native-value' { 'VINIX iOS NATIVEVALUE: PASS' } else if mode == 'gk-match-request' { 'VINIX iOS GKMATCHREQUEST: PASS' } else if mode == 'gk-achievement' { 'VINIX iOS GKACHIEVEMENT: PASS' } else if mode == 'gk-player' { 'VINIX iOS GKPLAYER: PASS' } else if mode == 'gk-turn-based-participant' { 'VINIX iOS GKTURNBASEDPARTICIPANT: PASS' } else if mode == 'gk-turn-based-match' { 'VINIX iOS GKTURNBASEDMATCH: PASS' } else if mode == 'gk-local-player' { 'VINIX iOS GKLOCALPLAYER: PASS' } else if mode == 'gk-leaderboard' { 'VINIX iOS GKLEADERBOARD: PASS' } else if mode == 'gk-achievement-description' { 'VINIX iOS GKACHIEVEMENTDESCRIPTION: PASS' } else if mode == 'capture-audio-output' { 'VINIX iOS CAPTUREAUDIOOUTPUT: PASS' } else if mode == 'capture-discovery' { 'VINIX iOS CAPTUREDISCOVERY: PASS' } else if mode == 'app-attest' { 'VINIX iOS APPATTEST: PASS' } else if mode == 'gc-event-view-controller' { 'VINIX iOS GCEVENT: PASS' } else if mode == 'snapshot-configuration' { 'VINIX iOS WKSNAPSHOT: PASS' } else if mode == 'text-field' { 'VINIX iOS UITEXTFIELD: PASS' } else if mode == 'haptic-dynamic-parameter' { 'VINIX iOS HAPTICDYNAMICPARAMETER: PASS' } else if mode == 'haptic-pattern' { 'VINIX iOS HAPTICPATTERN: PASS' } else if mode == 'haptic-event' { 'VINIX iOS HAPTICEVENT: PASS' } else if mode == 'haptic-event-parameter' { 'VINIX iOS HAPTICEVENTPARAMETER: PASS' } else if mode == 'long-press-gesture' { 'VINIX iOS LONGPRESSGESTURE: PASS' } else if mode == 'tap-gesture' { 'VINIX iOS TAPGESTURE: PASS' } else if mode == 'rotation-gesture' { 'VINIX iOS ROTATIONGESTURE: PASS' } else if mode == 'pinch-gesture' { 'VINIX iOS PINCHGESTURE: PASS' } else if mode == 'pan-gesture' { 'VINIX iOS PANGESTURE: PASS' } else if mode == 'text-input' { 'VINIX iOS TEXTINPUT: PASS' } else if mode == 'game-center' { 'VINIX iOS GAMECENTER: PASS' } else if mode == 'av-player' { 'VINIX iOS AVPLAYER: PASS' } else if mode == 'ns-proxy' { 'VINIX iOS NSPROXY: PASS' } else if mode == 'swift-object' { 'VINIX iOS SWIFTOBJECT: PASS' } else if mode == 'storekit-purchase' { 'VINIX iOS STOREKITPURCHASE: PASS' } else if mode == 'storyboard' { 'VINIX iOS STORYBOARD: PASS' } else if mode == 'audio-application' { 'VINIX iOS AUDIOAPPLICATION: PASS' } else if mode == 'game-controller' { 'VINIX iOS GAMECONTROLLER: PASS' } else if mode == 'session-task' { 'VINIX iOS SESSIONTASK: PASS' } else if mode == 'feedback' { 'VINIX iOS FEEDBACK: PASS' } else if mode == 'notifications' { 'VINIX iOS NOTIFICATIONS: PASS' } else { 'FORTNITE PROBE COMPLETE' }
	mut failure := ''
	await_checks(mut p, log, marker, timeout_seconds) or { failure = err.msg() }
	// V panics do not unwind defers. Close our VM before reporting failure.
	if p.is_alive() {
		p.signal_term()
		for _ in 0 .. 40 {
			if !p.is_alive() { break }
			time.sleep(50 * time.millisecond)
		}
		// HVF can leave the completed guest stuck while QEMU shuts down.
		if p.is_alive() { p.signal_kill() }
		p.wait()
	}
	p.close()
	if failure != '' { panic(failure) }
	println('${mode}: ${if mode in ['class-update', 'native-value', 'capture-audio-output', 'gk-match-request', 'gk-achievement', 'gk-achievement-description', 'gk-player', 'gk-turn-based-participant', 'gk-turn-based-match', 'gk-local-player', 'gk-leaderboard', 'capture-discovery', 'app-attest', 'gc-event-view-controller', 'snapshot-configuration', 'text-field', 'haptic-dynamic-parameter', 'haptic-pattern', 'haptic-event', 'haptic-event-parameter', 'long-press-gesture', 'tap-gesture', 'rotation-gesture', 'pinch-gesture', 'pan-gesture', 'text-input', 'game-center', 'av-player', 'ns-proxy', 'swift-object', 'storekit-purchase', 'storyboard', 'audio-application', 'game-controller', 'session-task', 'feedback', 'notifications'] {
		'PASS'
	} else {
		'COMPLETE (see guest process status)'
	}}')
}


fn main() {
	if os.args.len != 3 { panic('usage: notification-vm MODE EXTERNAL_BUNDLE') }
	root := os.real_path(os.getwd())
	if os.getenv('VINIX_IOS_CHECK_NAME') != 'notification-center-checks' { panic('run through notification-checks') }
	out := os.abs_path(os.args[2])
	if out == root || out.starts_with(root + "/") { panic('notification evidence must be outside the repository') }
	os.mkdir_all(out) or { panic(err) }
	mode := os.args[1]
	if mode == 'replay-probe-no-ads' {
		// Retry only preserved, complete media. The checkpoint caller archives
		// the failed attempt before replacing its serial log and firmware state.
		state := os.read_file(out + '/probe-no-ads-state.txt') or { panic(err) }
		path := state.trim_space()
		if os.dir(path) != out || !os.file_name(path).starts_with('probe-no-ads-') {
			panic('unsafe replay state pointer')
		}
		for item in ['boot.img', 'initramfs.tar.gz', 'limine.conf'] {
			if !os.is_file(path + '/' + item) { panic('incomplete replay media') }
		}
		if os.exists(path + '/efivars.fd') { os.rm(path + '/efivars.fd') or { panic(err) } }
		run_vm('probe-no-ads', path, '8192', 1800)
		return
	}
	if mode !in ['build', 'build-metal-device', 'build-locale-preferred', 'build-bundle-info', 'build-string-get-cstring', 'build-dictionary-file', 'build-bundle-identifier', 'build-string-path', 'build-url-resource', 'build-number-bool', 'build-string-cstring-output', 'build-string-normalization', 'build-responder', 'build-view-tag', 'build-main-selector', 'build-application-badge', 'build-window', 'build-string-float', 'build-string-cstring', 'build-bundle-receipt', 'build-cf-string-output', 'build-search-path', 'build-home-directory', 'build-inline-pthread-self', 'build-dictionary-snapshot', 'build-block-byref', 'build-processinfo', 'build-vm-probe', 'build-init', 'build-feedback', 'build-class-update', 'build-native-value', 'build-capture-audio-output', 'build-gk-match-request', 'build-gk-achievement', 'build-gk-achievement-description', 'build-gk-player', 'build-gk-turn-based-participant', 'build-gk-turn-based-match', 'build-gk-local-player', 'build-gk-leaderboard', 'build-capture-discovery', 'build-app-attest', 'build-gc-event-view-controller', 'build-snapshot-configuration', 'build-text-field', 'build-haptic-dynamic-parameter', 'build-haptic-pattern', 'build-haptic-event', 'build-haptic-event-parameter', 'build-long-press-gesture', 'build-tap-gesture', 'build-rotation-gesture', 'build-pinch-gesture', 'build-pan-gesture', 'build-text-input', 'build-game-center', 'build-av-player', 'build-ns-proxy', 'build-swift-object', 'build-storekit-purchase', 'build-storyboard', 'build-audio-application', 'build-game-controller', 'build-session-task', 'build-run-ios-gles', 'class-update', 'native-value', 'capture-audio-output', 'gk-match-request', 'gk-achievement', 'gk-achievement-description', 'gk-player', 'gk-turn-based-participant', 'gk-turn-based-match', 'gk-local-player', 'gk-leaderboard', 'capture-discovery', 'app-attest', 'gc-event-view-controller', 'snapshot-configuration', 'text-field', 'haptic-dynamic-parameter', 'haptic-pattern', 'haptic-event', 'haptic-event-parameter', 'long-press-gesture', 'tap-gesture', 'rotation-gesture', 'pinch-gesture', 'pan-gesture', 'text-input', 'game-center', 'av-player', 'ns-proxy', 'swift-object', 'storekit-purchase', 'storyboard', 'audio-application', 'game-controller', 'session-task', 'feedback', 'notifications', 'probe', 'probe-no-ads', 'audit', 'static-audit']! { panic('invalid notification mode') }
	if mode == 'build' {
		mut jobs := []thread{}
		for item in ['metal-device-checks', 'locale-preferred-checks', 'bundle-info-checks', 'string-get-cstring-checks', 'dictionary-file-checks', 'bundle-identifier-checks', 'string-path-checks', 'url-resource-checks', 'number-bool-checks', 'string-cstring-output-checks', 'string-normalization-checks', 'responder-checks', 'view-tag-checks', 'main-selector-checks', 'application-badge-checks', 'window-checks', 'string-float-checks', 'string-cstring-checks', 'bundle-receipt-checks', 'cf-string-output-checks', 'search-path-checks', 'home-directory-checks', 'inline-pthread-self-checks', 'dictionary-snapshot-checks', 'block-byref-checks', 'processinfo-checks', 'vm-probe-checks', 'class-update-checks', 'native-value-checks', 'capture-audio-output-checks', 'gk-match-request-checks', 'gk-achievement-checks', 'gk-achievement-description-checks', 'gk-player-checks', 'gk-turn-based-participant-checks', 'gk-turn-based-match-checks', 'gk-local-player-checks', 'gk-leaderboard-checks', 'capture-discovery-checks', 'app-attest-checks', 'gc-event-view-controller-checks', 'snapshot-configuration-checks', 'text-field-checks', 'haptic-dynamic-parameter-checks', 'haptic-pattern-checks', 'haptic-event-checks', 'haptic-event-parameter-checks', 'long-press-gesture-checks', 'tap-gesture-checks', 'rotation-gesture-checks', 'pinch-gesture-checks', 'pan-gesture-checks', 'text-input-checks', 'game-center-checks', 'av-player-checks', 'ns-proxy-checks', 'swift-object-checks', 'storekit-purchase-checks', 'storyboard-checks', 'audio-application-checks', 'game-controller-checks', 'session-task-checks', 'feedback-checks', 'adsupport-checks', 'bundle-resource-checks', 'number-formatter-checks', 'date-formatter-checks', 'lock-checks', 'recursive-lock-checks', 'map-table-checks', 'credential-checks', 'telephony-checks', 'cache-checks', 'notification-attachment-checks', 'notification-sound-checks', 'notification-content-checks', 'notification-center-checks', 'notification-request-checks', 'calendar-trigger-checks', 'calendar-checks', 'native-init', 'run-ios', 'run-ios-gles']! {
			jobs << spawn build(root, out, item)
			if jobs.len == 4 { jobs.wait(); jobs.clear() }
		}
		jobs.wait()
	} else if mode == 'build-responder' {
		build(root, out, 'responder-checks')
	} else if mode == 'build-dictionary-file' {
		build(root, out, 'dictionary-file-checks')
	} else if mode == 'build-bundle-identifier' {
		build(root, out, 'bundle-identifier-checks')
	} else if mode == 'build-metal-device' {
		build(root, out, 'metal-device-checks')
	} else if mode == 'build-locale-preferred' {
		build(root, out, 'locale-preferred-checks')
	} else if mode == 'build-bundle-info' {
		build(root, out, 'bundle-info-checks')
	} else if mode == 'build-string-get-cstring' {
		build(root, out, 'string-get-cstring-checks')
	} else if mode == 'build-string-path' {
		build(root, out, 'string-path-checks')
	} else if mode == 'build-url-resource' {
		build(root, out, 'url-resource-checks')
	} else if mode == 'build-number-bool' {
		build(root, out, 'number-bool-checks')
	} else if mode == 'build-string-cstring-output' {
		build(root, out, 'string-cstring-output-checks')
	} else if mode == 'build-string-normalization' {
		build(root, out, 'string-normalization-checks')
	} else if mode == 'build-view-tag' {
		build(root, out, 'view-tag-checks')
	} else if mode == 'build-main-selector' {
		build(root, out, 'main-selector-checks')
	} else if mode == 'build-init' {
		build(root, out, 'native-init')
	} else if mode == 'build-application-badge' {
		build(root, out, 'application-badge-checks')
	} else if mode == 'build-window' {
		build(root, out, 'window-checks')
	} else if mode == 'build-string-float' {
		build(root, out, 'string-float-checks')
	} else if mode == 'build-string-cstring' {
		build(root, out, 'string-cstring-checks')
	} else if mode == 'build-bundle-receipt' {
		build(root, out, 'bundle-receipt-checks')
	} else if mode == 'build-cf-string-output' {
		build(root, out, 'cf-string-output-checks')
	} else if mode == 'build-search-path' {
		build(root, out, 'search-path-checks')
	} else if mode == 'build-home-directory' {
		build(root, out, 'home-directory-checks')
	} else if mode == 'build-inline-pthread-self' {
		build(root, out, 'inline-pthread-self-checks')
	} else if mode == 'build-dictionary-snapshot' {
		build(root, out, 'dictionary-snapshot-checks')
	} else if mode == 'build-block-byref' {
		build(root, out, 'block-byref-checks')
	} else if mode == 'build-vm-probe' {
		build(root, out, 'vm-probe-checks')
	} else if mode == 'build-processinfo' {
		build(root, out, 'processinfo-checks')
	} else if mode == 'build-class-update' {
		build(root, out, 'class-update-checks')
	} else if mode == 'build-native-value' {
		build(root, out, 'native-value-checks')
	} else if mode == 'build-gk-match-request' {
		build(root, out, 'gk-match-request-checks')
	} else if mode == 'build-gk-achievement' {
		build(root, out, 'gk-achievement-checks')
	} else if mode == 'build-gk-turn-based-match' {
		build(root, out, 'gk-turn-based-match-checks')
	} else if mode == 'build-gk-local-player' {
		build(root, out, 'gk-local-player-checks')
	} else if mode == 'build-gk-leaderboard' {
		build(root, out, 'gk-leaderboard-checks')
	} else if mode == 'build-gk-turn-based-participant' {
		build(root, out, 'gk-turn-based-participant-checks')
	} else if mode == 'build-gk-player' {
		build(root, out, 'gk-player-checks')
	} else if mode == 'build-gk-achievement-description' {
		build(root, out, 'gk-achievement-description-checks')
	} else if mode == 'build-capture-audio-output' {
		build(root, out, 'capture-audio-output-checks')
	} else if mode == 'build-capture-discovery' {
		build(root, out, 'capture-discovery-checks')
	} else if mode == 'build-app-attest' {
		build(root, out, 'app-attest-checks')
	} else if mode == 'build-gc-event-view-controller' {
		build(root, out, 'gc-event-view-controller-checks')
	} else if mode == 'build-snapshot-configuration' {
		build(root, out, 'snapshot-configuration-checks')
	} else if mode == 'build-text-field' {
		build(root, out, 'text-field-checks')
	} else if mode == 'build-haptic-dynamic-parameter' {
		build(root, out, 'haptic-dynamic-parameter-checks')
	} else if mode == 'build-haptic-pattern' {
		build(root, out, 'haptic-pattern-checks')
	} else if mode == 'build-haptic-event' {
		build(root, out, 'haptic-event-checks')
	} else if mode == 'build-haptic-event-parameter' {
		build(root, out, 'haptic-event-parameter-checks')
	} else if mode == 'build-long-press-gesture' {
		build(root, out, 'long-press-gesture-checks')
	} else if mode == 'build-tap-gesture' {
		build(root, out, 'tap-gesture-checks')
	} else if mode == 'build-rotation-gesture' {
		build(root, out, 'rotation-gesture-checks')
	} else if mode == 'build-pinch-gesture' {
		build(root, out, 'pinch-gesture-checks')
	} else if mode == 'build-pan-gesture' {
		build(root, out, 'pan-gesture-checks')
	} else if mode == 'build-text-input' {
		build(root, out, 'text-input-checks')
	} else if mode == 'build-game-center' {
		build(root, out, 'game-center-checks')
	} else if mode == 'build-av-player' {
		build(root, out, 'av-player-checks')
	} else if mode == 'build-ns-proxy' {
		build(root, out, 'ns-proxy-checks')
	} else if mode == 'build-swift-object' {
		build(root, out, 'swift-object-checks')
	} else if mode == 'build-storekit-purchase' {
		build(root, out, 'storekit-purchase-checks')
	} else if mode == 'build-storyboard' {
		build(root, out, 'storyboard-checks')
	} else if mode == 'build-audio-application' {
		build(root, out, 'audio-application-checks')
	} else if mode == 'build-game-controller' {
		build(root, out, 'game-controller-checks')
	} else if mode == 'build-session-task' {
		build(root, out, 'session-task-checks')
	} else if mode == 'build-feedback' {
		build(root, out, 'feedback-checks')
	} else if mode == 'build-run-ios-gles' {
		build(root, out, 'run-ios-gles')
	} else { vm(root, out, mode) }
}
