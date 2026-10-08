module androidhost

fn deployment_launch(row map[string]Value) string {
	flags := field(row, 'flags').object()
	observe := flag(flags, 'observe')
	android := field(row, 'launcher').text() == 'android'
	mut script := '#!/bin/sh\n. /opt/android-test/config.sh\nexport VINIX_ANDROID_EXPECTED_RESULT VINIX_ROBLOX_SPLIT_APKS\n[ "$TEST_STRACE" = 0 ] || export QEMU_STRACE=1\n'
	if !observe {
		script += 'export VINIX_ANDROID_TEST_PRELOAD=/opt/android-test/text-observer.so\n'
	}
	if field(row, 'runtime_arch').text() == 'aarch64' && !observe {
		script += 'export LD_PRELOAD="$VINIX_ANDROID_TEST_PRELOAD"\n'
	}
	script += if android {
		'exec /usr/bin/run-android "$TEST_APK" -l ' + split_quote(field(row, 'activity').text()) + ' -w 480 -h 640'
	} else {
		'exec /usr/bin/run-roblox "$TEST_APK"'
	}
	for argument in field(row, 'runtime_arg').items() {
		script += ' ' + split_quote(argument.text())
	}
	if android {
		for path in field(row, 'split_paths').items() {
			script += ' --split-apk ' + split_quote(path.text())
		}
	}
	return script + '\n'
}

pub fn deployment_query(row map[string]Value, operation string) !Value {
	fields := unpack_string_value(field(row, 'fields_encoded'))!.object()
	result := match operation {
		'runner_configuration' { Value(deployment_configuration(fields)) }
		'runner_optional' { deployment_optional(fields) }
		else { Value(deployment_launch(fields)) }
	}
	return pack_string_value(result)
}

fn deployment_configuration(row map[string]Value) string {
	flags := field(row, 'flags').object()
	configuration := map[string]string{
		'TEST_APK':                         '/opt/android-test/application.apk'
		'TEST_MODE':                        field(row, 'mode').text()
		'TEST_DESKTOP_APP':                 if field(row, 'launcher').text() == 'roblox' {
			'Roblox'
		} else {
			'Android Calculator'
		}
		'TEST_HOSTED_NAME':                 if field(row, 'launcher').text() == 'roblox' && field(row, 'mode').text() == 'desktop' {
			'roblox'
		} else {
			'android'
		}
		'TEST_GEOMETRY':                    if field(row, 'launcher').text() == 'roblox' {
			'1280x720x24'
		} else {
			'480x640x24'
		}
		'VINIX_ROBLOX_APK':                 '/opt/android-test/application.apk'
		'VINIX_ROBLOX_SPLIT_APKS':          if field(row, 'launcher').text() == 'roblox' {
			field(row, 'split_paths').items().map(it.text()).join(':')
		} else {
			''
		}
		'VINIX_ANDROID_LINKER_DIAGNOSTICS': if flag(flags, 'linker_diagnostics') {
			'1'
		} else {
			'0'
		}
		'TEST_BIONIC_LOADER_PROBE':         if flag(flags, 'loader_probe') {
			'/opt/android-test/loader'
		} else {
			''
		}
		'TEST_LAYOUT_PROBE':                if flag(flags, 'layout_probe') {
			'/opt/android-test/android-layout-focus-probe.jar'
		} else {
			''
		}
		'TEST_POINTER_PROBE':               if flag(flags, 'pointer_probe') {
			'/opt/android-test/android-pointer-capture-probe.jar'
		} else {
			''
		}
		'TEST_LIFECYCLE_PROBE':             if flag(flags, 'lifecycle_probe') {
			'/opt/android-test/android-activity-lifecycle-probe.apk'
		} else {
			''
		}
		'TEST_COOKIE_PROBE':                if flag(flags, 'cookie_probe') {
			'/opt/android-test/android-cookie-probe.apk'
		} else {
			''
		}
		'TEST_AUTOFILL_PROBE':              if flag(flags, 'autofill_probe') {
			'/opt/android-test/android-autofill-probe.apk'
		} else {
			''
		}
		'TEST_LOCATION_PROBE':              if flag(flags, 'location_probe') {
			'/opt/android-test/android-location-probe.apk'
		} else {
			''
		}
		'TEST_EGL_QUEUE_PROBE':             if flag(flags, 'egl_queue_probe') {
			'/opt/android-test/android-egl-queue-probe.apk'
		} else {
			''
		}
		'TEST_SPLIT_PROBE':                 if flag(flags, 'split_probe') {
			'/opt/android-test/split-probe'
		} else {
			''
		}
		'TEST_EGL_PROBE':                   if flag(flags, 'egl_probe') {
			'/opt/android-test/egl-interop-test'
		} else {
			''
		}
		'TEST_TLS_PROBE':                   if flag(flags, 'tls_probe') {
			'/opt/android-test/android-tls-probe.jar'
		} else {
			''
		}
		'TEST_ART_BOOT_PROBE':              if flag(flags, 'boot_probe') {
			'/opt/android-test/art-boot-probe.jar'
		} else {
			''
		}
		'TEST_INPUT':                       field(row, 'input').text()
		'TEST_KEYS':                        field(row, 'keys').text()
		'TEST_TITLE':                       field(row, 'title').text()
		'TEST_TIMEOUT':                     field(row, 'startup_timeout').text()
		'VINIX_ANDROID_EXPECTED_RESULT':    field(row, 'expect').text()
		'TEST_RUNTIME_ARCH':                field(row, 'runtime_arch').text()
		'TEST_STRACE':                      if flag(flags, 'strace') { '1' } else { '0' }
		'TEST_FOCUS_X':                     field(row, 'focus_0').text()
		'TEST_FOCUS_Y':                     field(row, 'focus_1').text()
		'TEST_WAIT_FOR_RESUME':             if field(row, 'apk_checksum').text() == '1928e65ced8cbe78be2ff3cb4c321e9e75d138e8e30ea1368fbb772a86827d1d' {
			'1'
		} else {
			'0'
		}
		'TEST_OBSERVE':                     if flag(flags, 'observe') { '1' } else { '0' }
		'TEST_INTERACTIVE':                 if flag(flags, 'interactive') { '1' } else { '0' }
		'TEST_OBSERVATION_SECONDS':         field(row, 'observation_seconds').text()
	}
	mut lines := []string{}
	for key, value in configuration { lines << key + '=' + split_quote(value) + '\n' }
	return lines.join('')
}

fn deployment_optional(row map[string]Value) Value {
	flags := field(row, 'flags').object()
	mut launches := []Value{}
	if flag(flags, 'lifecycle_probe') {
		launches << Value(map[string]Value{
			'name':   Value('lifecycle-launch')
			'script': Value('#!/bin/sh\n. /opt/android-test/config.sh\n/usr/bin/run-android "\$TEST_LIFECYCLE_PROBE" -l \'android/app/AndroidActivityLifecycleProbe\$BootstrapActivity\' -w 128 -h 128 -X "-Djava.class.path=/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar:/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/framework-res.apk:\$TEST_LIFECYCLE_PROBE"\nlifecycle_status=\$?\nprintf \'%s\\n\' "\$lifecycle_status" >/tmp/android-lifecycle-status\nexit "\$lifecycle_status"\n')
		})
	}
	if flag(flags, 'cookie_probe') {
		launches << Value(map[string]Value{
			'name':   Value('cookie-launch')
			'script': Value('#!/bin/sh\n. /opt/android-test/config.sh\n/usr/bin/run-android "\$TEST_COOKIE_PROBE" -l \'org/vinix/tests/AndroidCookieProbe\$BootstrapActivity\' -w 128 -h 128\ncookie_status=\$?\nprintf \'%s\\n\' "\$cookie_status" >/tmp/android-cookie-status\nexit "\$cookie_status"\n')
		})
		launches << Value(map[string]Value{
			'name':   Value('cookie-reload-launch')
			'script': Value('#!/bin/sh\n. /opt/android-test/config.sh\n/usr/bin/run-android "\$TEST_COOKIE_PROBE" -l \'org/vinix/tests/AndroidCookieProbe\$PersistenceActivity\' -w 128 -h 128\ncookie_status=\$?\nprintf \'%s\\n\' "\$cookie_status" >/tmp/android-cookie-reload-status\nexit "\$cookie_status"\n')
		})
	}
	if flag(flags, 'autofill_probe') {
		launches << Value(map[string]Value{
			'name':   Value('autofill-launch')
			'script': Value('#!/bin/sh\n. /opt/android-test/config.sh\n/usr/bin/run-android "\$TEST_AUTOFILL_PROBE" -l \'org/vinix/tests/AndroidAutofillProbe\$BootstrapActivity\' -w 128 -h 128\nautofill_status=\$?\nprintf \'%s\\n\' "\$autofill_status" >/tmp/android-autofill-status\nexit "\$autofill_status"\n')
		})
	}
	if flag(flags, 'location_probe') {
		launches << Value(map[string]Value{
			'name':   Value('location-launch')
			'script': Value('#!/bin/sh\n. /opt/android-test/config.sh\n/usr/bin/run-android "\$TEST_LOCATION_PROBE" -l \'org/vinix/tests/AndroidLocationProbe\$BootstrapActivity\' -w 128 -h 128\nlocation_status=\$?\nprintf \'%s\\n\' "\$location_status" >/tmp/android-location-status\nexit "\$location_status"\n')
		})
	}
	if flag(flags, 'egl_queue_probe') {
		launches << Value(map[string]Value{
			'name':   Value('egl-queue-launch')
			'script': Value('#!/bin/sh\n. /opt/android-test/config.sh\n/usr/bin/run-android "\$TEST_EGL_QUEUE_PROBE" -l \'org/vinix/tests/AndroidEglQueueProbe\$BootstrapActivity\' -w 128 -h 128\negl_queue_status=\$?\nprintf \'%s\\n\' "\$egl_queue_status" >/tmp/android-egl-queue-status\nexit "\$egl_queue_status"\n')
		})
	}
	if flag(flags, 'egl_probe') {
		launches << Value(map[string]Value{
			'name':   Value('egl-launch')
			'script': Value('#!/bin/sh\n. /opt/android-test/config.sh\n(\n runtime=/opt/vinix-android-aarch64\n unset LD_LIBRARY_PATH LD_PRELOAD\n export VINIX_ALLOW_WX=1 LD_LIBRARY_PATH="\$runtime/lib:\$runtime/usr/lib"\n export LD_PRELOAD="\$runtime/usr/lib/libvinix-android-compat.so"\n export GDK_BACKEND=x11 GDK_DISABLE="\${GDK_DISABLE:+\$GDK_DISABLE,}glx" GSK_RENDERER=cairo\n export GTK_A11Y=none GSETTINGS_BACKEND=memory\n export FONTCONFIG_PATH="\$runtime/etc/fonts" FONTCONFIG_FILE="\$runtime/etc/fonts/fonts.conf"\n export GSETTINGS_SCHEMA_DIR="\$runtime/usr/share/glib-2.0/schemas"\n export LIBGL_DRIVERS_PATH="\$runtime/usr/lib/dri"\n exec "\$runtime/lib/ld-musl-aarch64.so.1" --library-path "\$LD_LIBRARY_PATH" "\$TEST_EGL_PROBE"\n)\negl_status=\$?\nprintf \'%s\\n\' "\$egl_status" >/tmp/android-egl-status\nexit "\$egl_status"\n')
		})
	}
	return Value(launches)
}
