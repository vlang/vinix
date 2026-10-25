// SPDX-License-Identifier: GPL-2.0-or-later
// Standalone V build, staging and VM orchestration for native ABI checks.
module main

import os
import time

const llvm = '/opt/homebrew/opt/llvm/bin/clang'

fn checked(args []string) {
	println('IOS-BUILD-COMMAND: ' + args.join(' '))
	mut p := os.new_process(args[0])
	p.set_args(args[1..])
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
		'haptic-event-checks' { 'ch_haptic_event_test.v' }
		'haptic-event-parameter-checks' { 'ch_haptic_event_parameter_test.v' }
		'long-press-gesture-checks' { 'ui_long_press_gesture_test.v' }
		'tap-gesture-checks' { 'ui_tap_gesture_test.v' }
		'rotation-gesture-checks' { 'ui_rotation_gesture_test.v' }
		'pinch-gesture-checks' { 'ui_pinch_gesture_test.v' }
		'pan-gesture-checks' { 'ui_pan_gesture_test.v' }
		'text-input-checks' { 'ui_text_input_test.v' }
		'game-center-checks' { 'game_center_test.v' }
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
	if only !in ['haptic-event-checks', 'haptic-event-parameter-checks', 'long-press-gesture-checks', 'tap-gesture-checks', 'rotation-gesture-checks', 'pinch-gesture-checks', 'pan-gesture-checks', 'text-input-checks', 'game-center-checks', 'storyboard-checks', 'audio-application-checks', 'game-controller-checks', 'session-task-checks', 'feedback-checks', 'adsupport-checks', 'bundle-resource-checks', 'number-formatter-checks', 'date-formatter-checks', 'lock-checks', 'recursive-lock-checks', 'map-table-checks', 'credential-checks', 'telephony-checks', 'cache-checks', 'notification-attachment-checks', 'notification-sound-checks', 'notification-content-checks', 'notification-center-checks', 'notification-request-checks', 'calendar-trigger-checks', 'calendar-checks','native-init','run-ios','run-ios-gles']! { panic('unknown notification build target') }
	for item in ['haptic-event-checks', 'haptic-event-parameter-checks', 'long-press-gesture-checks', 'tap-gesture-checks', 'rotation-gesture-checks', 'pinch-gesture-checks', 'pan-gesture-checks', 'text-input-checks', 'game-center-checks', 'storyboard-checks', 'audio-application-checks', 'game-controller-checks', 'session-task-checks', 'feedback-checks', 'adsupport-checks', 'bundle-resource-checks', 'number-formatter-checks', 'date-formatter-checks', 'lock-checks', 'recursive-lock-checks', 'map-table-checks', 'credential-checks', 'telephony-checks', 'cache-checks', 'notification-attachment-checks', 'notification-sound-checks', 'notification-content-checks', 'notification-center-checks', 'notification-request-checks', 'calendar-trigger-checks', 'calendar-checks','native-init','run-ios','run-ios-gles']! {
		if only != '' && item != only { continue }
		generated := out + '/' + item + '.c'
		if item == 'native-init' {
			checked([root + '/build/ios/fortnite/ns-calendar-checks/toolchain/v', '-enable-globals','-nocache', '-cc', 'clang', '-os', 'linux', '-arch', 'arm64', '-gc', 'none', '-prod', '-d', 'no_backtrace',
				'-o', generated, root + '/tests/ios/native-init.v'])
		} else {
			mut args := [root + '/build/ios/fortnite/ns-calendar-checks/toolchain/v', '-enable-globals','-nocache', '-cc', 'clang', '-os', 'linux', '-arch', 'arm64', '-enable-globals', '-gc', 'none',
				'-prod', '-d', 'ios_video', '-d', 'glibc', '-d', 'no_backtrace', '-d', 'ios_cxx', '-d', 'ios_sqlite', '-path',
				'@vlib|' + root + '/compat/ios|@vmodules', '-o', generated]
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

fn await_checks(mut p os.Process, log string, marker string) ! {
	for _ in 0 .. 1200 {
		text := os.read_file(log) or { '' }
		if text.contains('iOS FAIL:') || text.contains('IOS-NATIVE: FAIL')
			|| text.contains('> assert ')
			|| text.contains('KERNEL PANIC') || text.contains('FATAL EXCEPTION')
			|| (text.contains('EXCEPTION') && text.contains('pc=0xffffffff'))
			|| (marker in ['VINIX iOS HAPTICEVENT: PASS', 'VINIX iOS HAPTICEVENTPARAMETER: PASS', 'VINIX iOS LONGPRESSGESTURE: PASS', 'VINIX iOS TAPGESTURE: PASS', 'VINIX iOS ROTATIONGESTURE: PASS', 'VINIX iOS PINCHGESTURE: PASS', 'VINIX iOS PANGESTURE: PASS', 'VINIX iOS TEXTINPUT: PASS', 'VINIX iOS GAMECENTER: PASS', 'VINIX iOS STORYBOARD: PASS', 'VINIX iOS AUDIOAPPLICATION: PASS', 'VINIX iOS NOTIFICATIONS: PASS', 'VINIX iOS FEEDBACK: PASS', 'VINIX iOS SESSIONTASK: PASS', 'VINIX iOS GAMECONTROLLER: PASS'] && text.contains('V panic:')) {
			return error(text)
		}
		if text.contains(marker) { return }
		if !p.is_alive() { return error('QEMU exited before ' + marker + ': ' + p.stderr_slurp()) }
		time.sleep(200 * time.millisecond)
	}
	return error('VM timeout: ' + log)
}

fn vm(root string, out string, mode string) {
	if mode !in ['haptic-event', 'haptic-event-parameter', 'long-press-gesture', 'tap-gesture', 'rotation-gesture', 'pinch-gesture', 'pan-gesture', 'text-input', 'game-center', 'storyboard', 'audio-application', 'game-controller', 'session-task', 'feedback', 'notifications', 'probe', 'audit', 'static-audit'] {
		panic('invalid check mode: ' + mode)
	}
	require_arm64_elf(out + '/native-init')
	if mode == 'haptic-event' {
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
		for item in ['haptic-event-checks', 'haptic-event-parameter-checks', 'long-press-gesture-checks', 'tap-gesture-checks', 'rotation-gesture-checks', 'pinch-gesture-checks', 'pan-gesture-checks', 'text-input-checks', 'game-center-checks', 'storyboard-checks', 'audio-application-checks', 'game-controller-checks', 'session-task-checks', 'feedback-checks', 'adsupport-checks', 'bundle-resource-checks', 'number-formatter-checks', 'date-formatter-checks', 'lock-checks', 'recursive-lock-checks', 'map-table-checks', 'credential-checks', 'telephony-checks', 'cache-checks', 'notification-attachment-checks', 'notification-sound-checks', 'notification-content-checks', 'notification-center-checks', 'notification-request-checks', 'calendar-trigger-checks', 'calendar-checks'] {
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
	if mode == 'haptic-event' {
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
		copy_file(out + '/haptic-event-checks', fs + '/opt/ios/haptic-event-checks')
		copy_file(out + '/haptic-event-parameter-checks', fs + '/opt/ios/haptic-event-parameter-checks')
		copy_file(out + '/long-press-gesture-checks', fs + '/opt/ios/long-press-gesture-checks')
		copy_file(out + '/tap-gesture-checks', fs + '/opt/ios/tap-gesture-checks')
		copy_file(out + '/rotation-gesture-checks', fs + '/opt/ios/rotation-gesture-checks')
		copy_file(out + '/pinch-gesture-checks', fs + '/opt/ios/pinch-gesture-checks')
		copy_file(out + '/pan-gesture-checks', fs + '/opt/ios/pan-gesture-checks')
		copy_file(out + '/text-input-checks', fs + '/opt/ios/text-input-checks')
		copy_file(out + '/game-center-checks', fs + '/opt/ios/game-center-checks')
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
		tree(root + '/build/ios/fortnite/staging/usr/lib/vinix/ios-gles', fs + '/usr/lib/vinix/ios-gles')
	}
	copy_file(out + '/native-init', fs + '/sbin/init')
	if mode == 'notifications' {
		os.mkdir_all(fs + '/etc') or { panic(err) }
		os.write_file(fs + '/etc/resolv.conf', 'nameserver 127.0.0.1\noptions timeout:1 attempts:1\n') or { panic(err) }
	}
	os.write_file(fs + '/opt/ios/check-mode', if mode.contains('audit') { 'audit' } else { mode }) or { panic(err) }
	archive := state + '/initramfs.tar.gz'
	if mode in ['probe', 'audit', 'static-audit'] {
		// This Mac's libarchive copies the preserved IPA executable directly
		// between archives. Omit its old runner; the overlay path starts ./
		// and supplies exactly one current replacement. No large extraction.
		checked(['tar', '--format=ustar', '--options', 'gzip:compression-level=1', '-czf', archive, '-s', ',^opt/ios/run-ios$,,',
			'@' + root + '/build/ios/fortnite/probe-initramfs.tar.gz', '-C', fs, '.'])
	} else {
		checked(['tar', '--format=ustar', '--options', 'gzip:compression-level=1', '-czf', archive, '-C', fs, '.'])
	}
	// Release staged files once the complete archive is ready.
	os.rmdir_all(fs) or { panic(err) }
	disk := state + '/boot.img'
	checked(['mkfile', '-n', '384m', disk])
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
	vars := state + '/efivars.fd'
	checked(['mkfile', '-n', '64m', vars])
	log := state + '/serial.log'
	mut p := os.new_process('/opt/homebrew/bin/qemu-system-aarch64')
	p.set_args(['-machine', 'virt,gic-version=3', '-accel', 'hvf', '-cpu', 'host', '-m', '4096',
		'-smp', '4', '-device', 'ramfb', '-display', 'none', '-monitor', 'none', '-serial',
		'file:' + log, '-drive',
		'if=pflash,format=raw,readonly=on,file=/opt/homebrew/share/qemu/edk2-aarch64-code.fd',
		'-drive', 'if=pflash,format=raw,file=' + vars, '-drive', 'format=raw,file=' + disk, '-device',
		'virtio-keyboard-device', '-device', 'virtio-tablet-device'])
	p.set_redirect_stdio()
	p.run()
	marker := if mode == 'haptic-event' { 'VINIX iOS HAPTICEVENT: PASS' } else if mode == 'haptic-event-parameter' { 'VINIX iOS HAPTICEVENTPARAMETER: PASS' } else if mode == 'long-press-gesture' { 'VINIX iOS LONGPRESSGESTURE: PASS' } else if mode == 'tap-gesture' { 'VINIX iOS TAPGESTURE: PASS' } else if mode == 'rotation-gesture' { 'VINIX iOS ROTATIONGESTURE: PASS' } else if mode == 'pinch-gesture' { 'VINIX iOS PINCHGESTURE: PASS' } else if mode == 'pan-gesture' { 'VINIX iOS PANGESTURE: PASS' } else if mode == 'text-input' { 'VINIX iOS TEXTINPUT: PASS' } else if mode == 'game-center' { 'VINIX iOS GAMECENTER: PASS' } else if mode == 'storyboard' { 'VINIX iOS STORYBOARD: PASS' } else if mode == 'audio-application' { 'VINIX iOS AUDIOAPPLICATION: PASS' } else if mode == 'game-controller' { 'VINIX iOS GAMECONTROLLER: PASS' } else if mode == 'session-task' { 'VINIX iOS SESSIONTASK: PASS' } else if mode == 'feedback' { 'VINIX iOS FEEDBACK: PASS' } else if mode == 'notifications' { 'VINIX iOS NOTIFICATIONS: PASS' } else { 'FORTNITE PROBE COMPLETE' }
	mut failure := ''
	await_checks(mut p, log, marker) or { failure = err.msg() }
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
	println('${mode}: ${if mode in ['haptic-event', 'haptic-event-parameter', 'long-press-gesture', 'tap-gesture', 'rotation-gesture', 'pinch-gesture', 'pan-gesture', 'text-input', 'game-center', 'storyboard', 'audio-application', 'game-controller', 'session-task', 'feedback', 'notifications'] {
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
	if mode !in ['build', 'build-init', 'build-feedback', 'build-haptic-event', 'build-haptic-event-parameter', 'build-long-press-gesture', 'build-tap-gesture', 'build-rotation-gesture', 'build-pinch-gesture', 'build-pan-gesture', 'build-text-input', 'build-game-center', 'build-storyboard', 'build-audio-application', 'build-game-controller', 'build-session-task', 'build-run-ios-gles', 'haptic-event', 'haptic-event-parameter', 'long-press-gesture', 'tap-gesture', 'rotation-gesture', 'pinch-gesture', 'pan-gesture', 'text-input', 'game-center', 'storyboard', 'audio-application', 'game-controller', 'session-task', 'feedback', 'notifications', 'probe', 'audit', 'static-audit']! { panic('invalid notification mode') }
	if mode == 'build' {
		mut jobs := []thread{}
		for item in ['haptic-event-checks', 'haptic-event-parameter-checks', 'long-press-gesture-checks', 'tap-gesture-checks', 'rotation-gesture-checks', 'pinch-gesture-checks', 'pan-gesture-checks', 'text-input-checks', 'game-center-checks', 'storyboard-checks', 'audio-application-checks', 'game-controller-checks', 'session-task-checks', 'feedback-checks', 'adsupport-checks', 'bundle-resource-checks', 'number-formatter-checks', 'date-formatter-checks', 'lock-checks', 'recursive-lock-checks', 'map-table-checks', 'credential-checks', 'telephony-checks', 'cache-checks', 'notification-attachment-checks', 'notification-sound-checks', 'notification-content-checks', 'notification-center-checks', 'notification-request-checks', 'calendar-trigger-checks', 'calendar-checks', 'native-init', 'run-ios', 'run-ios-gles']! {
			jobs << spawn build(root, out, item)
			if jobs.len == 4 { jobs.wait(); jobs.clear() }
		}
		jobs.wait()
	} else if mode == 'build-init' {
		build(root, out, 'native-init')
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
