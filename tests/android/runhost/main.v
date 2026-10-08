module runhost

import androidhost as ah
import json2

fn positive_integer(value ah.Value) bool {
	word := ah.encode(value)
	return !word.starts_with('-') && word.bytes().any(it in `1` .. `9` + 1)
}

fn main_policy(mut args map[string]ah.Value) !ah.Value {
	if !positive_integer(ah.field(args, 'observation_seconds')) {
		parser_error('--observation-seconds must be positive')!
	}
	interactive := truth(ah.field(args, 'interactive'))
	if interactive {
		if !truth(ah.field(args, 'observe')) || text(args, 'mode') != 'desktop' {
			parser_error('--interactive requires --observe and --mode desktop')!
		}
		if ah.field(args, 'screenshot') !is json2.Null {
			parser_error('--interactive disables automatic screenshots; capture explicitly through QMP')!
		}
	}
	if !truth(ah.field(args, 'prepare_only')) && !interactive {
		callback('import', {
			'name': ah.Value('PIL')
		}) or {
			if err is BindingError && text(err.value, 'kind') in ['ImportError', 'ModuleNotFoundError'] {
				return failure('Python Pillow is required to save the APK screenshot')
			}
			return err
		}
	}
	args_set(mut args, 'repo', ah.Value(resolve(text(args, 'repo'))!), 'path')!
	args_set(mut args, 'state_dir', ah.Value(resolve(text(args, 'state_dir'))!), 'path')!
	default_path(mut args, 'runtime', join([text(args, 'repo'), 'build-aarch64-android/aarch64/staging'])!)!
	if ah.field(args, 'runtime_arch') is json2.Null {
		mut architectures := []string{}
		for marker in list('glob', text(args, 'runtime'), [ah.Value('opt/vinix-android*/architecture')])! {
			// The caller's strip primitive preserves the exact Unicode table.
			architectures << callback('strip', {
				'data': path('read_text', marker, []ah.Value{}, map[string]ah.Value{})!
			})!.text()
		}
		args_set(mut args, 'runtime_arch', ah.Value(if 'x86_64' in architectures {
			'x86_64'
		} else {
			'aarch64'
		}), 'value')!
	}
	for flag in ['boot_probe', 'layout_probe', 'pointer_probe', 'lifecycle_probe', 'cookie_probe',
		'autofill_probe', 'location_probe', 'egl_queue_probe', 'split_probe', 'split_apk', 'egl_probe',
		'tls_probe', 'loader_probe'] {
		if truth(ah.field(args, flag)) && text(args, 'runtime_arch') != 'aarch64' {
			parser_error('--' + flag.replace('_', '-') + ' requires a native aarch64 runtime')!
		}
	}
	if text(args, 'launcher') == 'roblox' {
		if text(args, 'runtime_arch') != 'aarch64' || !truth(ah.field(args, 'observe')) || ah.field(args, 'apk') is json2.Null {
			parser_error('--launcher roblox requires --runtime-arch aarch64, --observe and --apk')!
		}
		if truth(ah.field(args, 'strace')) {
			parser_error('--strace applies to translated runtime diagnostics')!
		}
		if text(args, 'mode') == 'desktop' && truth(ah.field(args, 'runtime_arg')) {
			parser_error('--runtime-arg is supported by the Roblox launcher in --mode direct')!
		}
		default_path(mut args, 'roblox_staging', join([text(args, 'repo'),
			'build-aarch64-roblox/aarch64/staging'])!)!
	}
	default_path(mut args, 'desktop', join([text(args, 'repo'), 'build/vinix-desktop'])!)!
	default_path(mut args, 'kernel_dir', join([text(args, 'repo'), 'kernel'])!)!
	if truth(ah.field(args, 'initramfs')) {
		args_set(mut args, 'initramfs', ah.Value(resolve(text(args, 'initramfs'))!), 'path')!
	}
	default_path(mut args, 'apk', join([text(args, 'runtime'), 'usr/share/vinix/android/Arity-1.1.apk'])!)!
	mut splits := []string{}
	for item in ah.field(args, 'split_apk').items() { splits << resolve(item.text())! }
	args_set(mut args, 'split_apk', strings(splits), 'paths')!
	for flag in ['boot_probe', 'layout_probe', 'pointer_probe', 'lifecycle_probe', 'cookie_probe',
		'autofill_probe', 'location_probe', 'egl_queue_probe', 'split_probe', 'egl_probe', 'tls_probe',
		'loader_probe'] {
		if truth(ah.field(args, flag)) {
			args_set(mut args, flag, ah.Value(resolve(text(args, flag))!), 'path')!
		}
	}
	default_path(mut args, 'screenshot', join([text(args, 'state_dir'),
		if truth(ah.field(args, 'observe')) { 'application.png' } else { 'calculator.png' }])!)!
	if !truth(ah.field(args, 'input')) {
		args_set(mut args, 'input', ah.Value(if text(args, 'mode') == 'direct' {
			'xtest'
		} else {
			'qmp'
		}), 'value')!
	}
	base := if truth(ah.field(args, 'initramfs')) {
		text(args, 'initramfs')
	} else {
		join([text(args, 'repo'),
			'build-aarch64-userland/downloads/alpine-minirootfs-3.21.7-aarch64.tar.gz'])!
	}
	for value in [join([text(args, 'runtime'), 'usr/bin/run-android'])!, text(args, 'desktop'),
		join([text(args, 'kernel_dir'), 'bin/vinix'])!, base, text(args, 'apk')] {
		if !test('is_file', value)! { return failure('Missing Android smoke test input: ' + value) }
	}
	for value in splits {
		if !test('is_file', value)! { return failure('Missing split APK: ' + value) }
	}
	for flag, message in {
		'boot_probe':      'native Java bootclasspath'
		'layout_probe':    'native framework layout focus'
		'pointer_probe':   'native framework pointer capture'
		'lifecycle_probe': 'native framework activity lifecycle'
		'cookie_probe':    'native framework cookie'
		'autofill_probe':  'native framework disabled autofill'
		'location_probe':  'native framework unavailable location providers'
		'egl_queue_probe': 'native EGL buffer queue'
	} {
		if truth(ah.field(args, flag)) && !test('is_file', text(args, flag))! {
			return failure('Missing ' + message + ' probe: ' + text(args, flag))
		}
	}
	if truth(ah.field(args, 'split_probe')) {
		for name in ['android-split-probe.apk', 'config.arm64_v8a.apk', 'test-cases.json'] {
			value := join([text(args, 'split_probe'), name])!
			if !test('is_file', value)! {
				return failure('Missing native configuration split fixture: ' + value)
			}
		}
	}
	for flag, message in {
		'egl_probe': 'native EGL and GTK texture'
		'tls_probe': 'native Java HTTPS trust'
	} {
		if truth(ah.field(args, flag)) && !test('is_file', text(args, flag))! {
			return failure('Missing ' + message + ' probe: ' + text(args, flag))
		}
	}
	if truth(ah.field(args, 'loader_probe')) {
		for name in ['loader-test', 'packed-relocation-probe.so'] {
			value := join([text(args, 'loader_probe'), name])!
			if !test('is_file', value)! {
				return failure('Missing native Bionic loader probe: ' + value)
			}
		}
	}
	path('mkdir', text(args, 'state_dir'), []ah.Value{}, {
		'parents':  ah.Value(true)
		'exist_ok': ah.Value(true)
		'mode':     ah.Value(if interactive { 0o700 } else { 0o777 })
	})!
	if interactive { chmod(text(args, 'state_dir'), 0o700)! }
	if !interactive {
		mkdir(path('parent', text(args, 'screenshot'), []ah.Value{}, map[string]ah.Value{})!.text(), true, true)!
	}
	prepared := callback('api', {
		'name': ah.Value('prepare')
	})!.object()
	args = ah.field(prepared, 'args').object()
	if truth(ah.field(args, 'prepare_only')) {
		value := if truth(ah.field(args, 'initramfs')) {
			text(args, 'initramfs')
		} else {
			ah.field(prepared, 'value').text()
		}
		callback('print', {
			'data': ah.Value('Prepared Android smoke image: ' + value)
		})!
		return ah.Value(0)
	}
	overlay := ah.field(prepared, 'value')
	argument := [ah.Value(if overlay is json2.Null { 'value' } else { 'path' }), overlay]
	return ah.field(callback('api', {
		'name':      ah.Value('run')
		'arguments': ah.Value([ah.Value(argument)])
	})!.object(), 'value')
}

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	mut args := ah.field(row, 'arguments').object()
	return match text(row, 'operation') {
		'qmp' { qmp_policy(text(args, 'socket'), text(args, 'name'), ah.field(args, 'options'))! }
		'keyboard' { keyboard_policy(text(args, 'socket'), ah.field(args, 'text'), text(row, 'root'))! }
		'click' { click_policy(args)! }
		'screenshot' { screenshot_policy(args)! }
		'stop_vm' { stop_policy(args)! }
		'vm_plan' {
			vm_plan(ah.field(args, 'args').object(), ah.field(args, 'overlay'), text(row, 'root'))!
		}
		'finalize' { finalize(ah.field(args, 'args').object(), args)! }
		'main' { main_policy(mut args)! }
		'prepare' { prepare(mut args, text(row, 'root'))! }
		'copy_layer' {
			copy_layer(text(args, 'source'), text(args, 'destination'), false)!
			null()
		}
		'supply_host_libraries' {
			supply_host_libraries(text(args, 'repo'), text(args, 'root'), ah.field(args, 'base_libraries').items().map(it.text()))!
			null()
		}
		'archive_root' {
			archive_root(text(args, 'root'), text(args, 'destination'))!
			null()
		}
		'prepare_split_probe' { split_prepare(text(args, 'source'), text(args, 'destination'))! }
		'deployment_fields' {
			ah.Value(deployment_fields(ah.field(args, 'args').object(), ah.field(args, 'split_paths').items().map(it.text()))!)
		}
		else { return error('Unknown Android runner operation ' + text(row, 'operation')) }
	}
}
