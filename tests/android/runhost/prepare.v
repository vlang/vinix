module runhost

import androidhost as ah
import json2

fn tar_extract(source string, destination string) ! {
	owner := callback('tar_open', {
		'path': ah.Value(source)
		'mode': ah.Value('r:gz')
	})!
	mut failed := false
	mut cause := IError(none)
	callback('tar_extract', {
		'id':   owner
		'path': ah.Value(destination)
	}) or {
		failed = true
		cause = err
	}
	suppressed := retire('tar_exit', owner, failed, cause)!
	if failed && !suppressed { return cause }
}

fn base_libraries_body(owner ah.Value) ![]string {
	mut names := []string{}
	for {
		member := callback('tar_next', {
			'id': owner
		})!
		if member is json2.Null { break }
		value := member.text().trim_left('./')
		parent := path('parent', value, []ah.Value{}, map[string]ah.Value{})!.text()
		if parent in ['lib', 'usr/lib', 'usr/lib/xorg/legacy-glx'] {
			names << path('name', value, []ah.Value{}, map[string]ah.Value{})!.text()
		}
	}
	return names
}

fn base_libraries(source string) ![]string {
	owner := callback('tar_open', {
		'path': ah.Value(source)
		'mode': ah.Value('r:*')
	})!
	mut failed := false
	mut cause := IError(none)
	result := base_libraries_body(owner) or {
		failed = true
		cause = err
		[]string{}
	}
	suppressed := retire('tar_exit', owner, failed, cause)!
	if failed && !suppressed { return cause }
	return result
}

fn command(arguments []string) ! {
	callback('run', {
		'arguments': strings(arguments)
	})!
}

fn deployment_fields(args map[string]ah.Value, split_paths []string) !map[string]ah.Value {
	mode := attribute(args, 'mode')!
	launcher := attribute(args, 'launcher')!
	mut flags := map[string]ah.Value{}
	for name in ['linker_diagnostics', 'loader_probe', 'layout_probe', 'pointer_probe',
		'lifecycle_probe', 'cookie_probe', 'autofill_probe', 'location_probe', 'egl_queue_probe',
		'split_probe', 'egl_probe', 'tls_probe', 'boot_probe'] {
		flags[name] = ah.Value(truth(attribute(args, name)!))
	}
	mut row := {
		'mode':        mode
		'launcher':    launcher
		'split_paths': strings(split_paths)
		'flags':       ah.Value(flags)
	}
	row['input'] = attribute(args, 'input')!
	row['keys'] = attribute(args, 'keys')!
	row['title'] = attribute(args, 'title')!
	row['startup_timeout'] = attribute_string('startup_timeout')!
	row['expect'] = attribute(args, 'expect')!
	row['runtime_arch'] = attribute(args, 'runtime_arch')!
	flags['strace'] = ah.Value(truth(attribute(args, 'strace')!))
	row['flags'] = ah.Value(flags)
	row['focus_0'] = callback('str_attribute', {
		'name':  ah.Value('focus')
		'index': ah.Value(0)
	})!
	row['focus_1'] = callback('str_attribute', {
		'name':  ah.Value('focus')
		'index': ah.Value(1)
	})!
	return row
}

fn deployment(operation string, fields map[string]ah.Value) !ah.Value {
	encoded := ah.pack_string_value(ah.Value(fields))
	return ah.unpack_string_value(ah.deployment_query({
		'fields_encoded': encoded
	}, operation)!)!
}

struct ProbeFile {
	name   string
	target string
}

fn prepare(mut args map[string]ah.Value, root string) !ah.Value {
	overlay := join([attribute_text(args, 'state_dir')!, 'overlay'])!
	if test('exists', overlay)! { rmtree(overlay)! }
	mut base := []string{}
	if attribute(args, 'initramfs')! is json2.Null {
		miniroot := join([attribute_text(args, 'repo')!,
			'build-aarch64-userland/downloads/alpine-minirootfs-3.21.7-aarch64.tar.gz'])!
		mkdir(overlay, true, false)!
		tar_extract(miniroot, overlay)!
		copy_layer(join([attribute_text(args, 'repo')!, 'build-aarch64-x11/staging'])!, overlay, true)!
	} else {
		base = base_libraries(attribute_text(args, 'initramfs')!)!
	}
	copy_layer(attribute_text(args, 'runtime')!, overlay, true)!
	if attribute_text(args, 'launcher')! == 'roblox' {
		callback('roblox_validate', {
			'source':  ah.Value(join([root, 'build-support/roblox/build.py'])!)
			'staging': attribute(args, 'roblox_staging')!
			'runtime': attribute(args, 'runtime')!
		})!
		copy_layer(attribute_text(args, 'roblox_staging')!, overlay, true)!
	}
	test_directory := join([overlay, 'opt/android-test'])!
	mkdir(test_directory, true, true)!
	x11 := join([attribute_text(args, 'repo')!, 'build-aarch64-x11/sysroot'])!
	compiler := callback('which', {
		'name': ah.Value('aarch64-linux-musl-gcc')
	})!.text()
	if compiler == '' { return failure('aarch64-linux-musl-gcc is required for the test helpers') }
	command([compiler, '-O2', '-Wall', '-Wextra', '-Werror', '-isystem', join([x11, 'usr/include'])!,
		join([root, 'tests/android/x11-probe.c'])!, '-L' + x11 + '/usr/lib', '-L' + x11 + '/lib',
		'-Wl,--allow-shlib-undefined', '-lXtst', '-lX11', '-lxcb', '-o',
		join([test_directory, 'x11-probe'])!])!
	mut observer := compiler
	if attribute_text(args, 'runtime_arch')! == 'x86_64' {
		observer = callback('which', {
			'name': ah.Value('x86_64-linux-musl-gcc')
		})!.text()
		if observer == '' {
			return failure('x86_64-linux-musl-gcc is required for the translated runtime observer')
		}
	}
	if !truth(attribute(args, 'observe')!) {
		command([observer, '-O2', '-Wall', '-Wextra', '-Werror', '-shared', '-fPIC',
			join([root, 'tests/android/text-observer.c'])!, '-ldl', '-o',
			join([test_directory, 'text-observer.so'])!])!
	}
	command([observer, '-O2', '-Wall', '-Wextra', '-Werror',
		join([root, 'tests/android/runtime-stack-probe.c'])!, '-pthread', '-o',
		join([test_directory, 'runtime-stack-probe'])!])!
	command([observer, '-O2', '-Wall', '-Wextra', '-Werror',
		join([root, 'tests/android/memory-probe.c'])!, '-o',
		join([test_directory, 'runtime-memory-probe'])!])!
	if attribute_text(args, 'runtime_arch')! == 'aarch64' {
		command([compiler, '-O2', '-Wall', '-Wextra', '-Werror',
			join([root, 'tests/android/atfork-test.c'])!, '-ldl', '-pthread', '-o',
			join([test_directory, 'runtime-atfork-probe'])!])!
		command([compiler, '-O2', '-Wall', '-Wextra', '-Werror',
			join([root, 'tests/android/fortify-test.c'])!, '-ldl', '-o',
			join([test_directory, 'runtime-fortify-probe'])!])!
		command([compiler, '-O2', '-Wall', '-Wextra', '-Werror',
			'-I' + join([root, 'build-support/android'])!,
			join([root, 'tests/android/mallinfo-test.c'])!, '-ldl', '-pthread', '-o',
			join([test_directory, 'runtime-mallinfo-probe'])!])!
		command([compiler, '-O2', '-Wall', '-Wextra', '-Werror',
			'-I' + join([root, 'build-support/android'])!, join([root, 'tests/android/netdb-test.c'])!,
			'-ldl', '-o', join([test_directory, 'runtime-netdb-probe'])!])!
	}
	if truth(attribute(args, 'loader_probe')!) {
		loader := join([test_directory, 'loader'])!
		mkdir(loader, false, false)!
		mut sums := map[string]ah.Value{}
		args_set(mut args, 'loader_probe_sha256', ah.Value(sums), 'value')!
		for name in ['loader-test', 'packed-relocation-probe.so'] {
			target := join([loader, name])!
			copy(join([attribute_text(args, 'loader_probe')!, name])!, target)!
			sums[name] = ah.Value(digest(target)!)
			callback('args_item', {
				'name':  ah.Value('loader_probe_sha256')
				'key':   ah.Value(name)
				'value': sums[name] or { null() }
			})!
			args['loader_probe_sha256'] = ah.Value(sums)
		}
	}
	command([compiler, '-O2', '-Wall', '-Wextra', '-Werror', '-static',
		join([root, 'tests/android/memory-probe.c'])!, '-o', join([test_directory, 'memory-probe'])!])!
	host_core := join([test_directory, 'wine-host-core.c'])!
	command(['python3', join([root, 'build-support/xorg-server/compile-v-host.py'])!, 'winehost',
		host_core, '--arch', 'arm64'])!
	command([compiler, '-O2', '-w', '-D__vinix__', '-I' + x11 + '/usr/include', host_core,
		'-I' + root + '/build-support/xorg-server', '-L' + x11 + '/usr/lib', '-L' + x11 + '/lib',
		'-Wl,--allow-shlib-undefined', '-lXtst', '-lXdamage', '-lX11', '-lXext', '-lxcb', '-o',
		join([overlay, 'usr/bin/vinix-wine-host'])!])!
	copy(attribute_text(args, 'desktop')!, join([overlay, 'usr/bin/vinix-desktop'])!)!
	for app_name in [
		if attribute_text(args, 'launcher')! == 'roblox' {
			'vinix-roblox'
		} else {
			'vinix-android-calculator'
		},
		'vinix-terminal',
	] {
		app := join([overlay, 'usr/bin', app_name])!
		if test('exists', app)! || test('is_symlink', app)! { unlink(app)! }
		path('symlink_to', app, [ah.Value('vinix-desktop')], map[string]ah.Value{})!
	}
	if attribute(args, 'initramfs')! is json2.Null {
		copy(join([attribute_text(args, 'repo')!, 'build-aarch64-userland/staging/bin/zsh'])!, join([
			overlay,
			'usr/bin/zsh',
		])!)!
		copy_layer(join([attribute_text(args, 'repo')!, 'build-aarch64-userland/staging/usr/lib/zsh'])!, join([
			overlay,
			'usr/lib/zsh',
		])!, true)!
		shell := join([overlay, 'bin/zsh'])!
		if test('exists', shell)! || test('is_symlink', shell)! { unlink(shell)! }
		path('symlink_to', shell, [ah.Value('../usr/bin/zsh')], map[string]ah.Value{})!
	}
	icons := join([overlay, 'usr/share/vinix/icons'])!
	mkdir(icons, true, true)!
	for icon in list('glob', join([attribute_text(args, 'repo')!, 'desktop/assets'])!, [ah.Value('*.qoi')])! {
		copy(icon, join([icons, path('name', icon, []ah.Value{}, map[string]ah.Value{})!.text()])!)!
	}
	copy(attribute_text(args, 'apk')!, join([overlay, 'opt/android-test/application.apk'])!)!
	mut splits := []string{}
	mut split_sums := []ah.Value{}
	args_set(mut args, 'split_apk_sha256', ah.Value(split_sums), 'value')!
	for index, source in attribute(args, 'split_apk')!.items() {
		target := join([test_directory, 'split-' + index.str() + '.apk'])!
		copy(source.text(), target)!
		split_sums << ah.Value(digest(target)!)
		callback('args_append', {
			'name':  ah.Value('split_apk_sha256')
			'value': split_sums.last()
		})!
		args['split_apk_sha256'] = ah.Value(split_sums)
		splits << '/opt/android-test/' + path('name', target, []ah.Value{}, map[string]ah.Value{})!.text()
	}
	probes := [ProbeFile{'layout_probe', 'android-layout-focus-probe.jar'},
		ProbeFile{'pointer_probe', 'android-pointer-capture-probe.jar'},
		ProbeFile{'lifecycle_probe', 'android-activity-lifecycle-probe.apk'},
		ProbeFile{'cookie_probe', 'android-cookie-probe.apk'},
		ProbeFile{'autofill_probe', 'android-autofill-probe.apk'},
		ProbeFile{'location_probe', 'android-location-probe.apk'},
		ProbeFile{'egl_queue_probe', 'android-egl-queue-probe.apk'}]
	for probe in probes { prepare_probe(mut args, probe, test_directory, false)! }
	if truth(attribute(args, 'split_probe')!) {
		args_set(mut args, 'split_probe_sha256', split_prepare(attribute_text(args, 'split_probe')!, join([
			test_directory,
			'split-probe',
		])!)!, 'value')!
	}
	for probe in [ProbeFile{'egl_probe', 'egl-interop-test'},
		ProbeFile{'tls_probe', 'android-tls-probe.jar'}, ProbeFile{'boot_probe', 'art-boot-probe.jar'}] {
		prepare_probe(mut args, probe, test_directory, probe.name == 'egl_probe')!
	}
	mut fields := deployment_fields(args, splits)!
	fields['apk_checksum'] = ah.Value(runner_digest(attribute_text(args, 'apk')!)!)
	mut flags := ah.field(fields, 'flags').object()
	flags['observe'] = ah.Value(truth(attribute(args, 'observe')!))
	flags['interactive'] = ah.Value(truth(attribute(args, 'interactive')!))
	fields['flags'] = ah.Value(flags)
	fields['observation_seconds'] = attribute_string('observation_seconds')!
	write(join([test_directory, 'config.sh'])!, deployment('runner_configuration', fields)!.text())!
	for launch in deployment('runner_optional', fields)!.items() {
		row := launch.object()
		target := join([test_directory, text(row, 'name')])!
		write(target, text(row, 'script'))!
		chmod(target, 0o755)!
	}
	fields['activity'] = if attribute_text(args, 'launcher')! == 'android' {
		attribute(args, 'activity')!
	} else {
		ah.Value('')
	}
	fields['runtime_arg'] = attribute(args, 'runtime_arg')!
	launch := join([test_directory, 'launch'])!
	write(launch, deployment('runner_launch', fields)!.text())!
	chmod(launch, 0o755)!
	if attribute_text(args, 'launcher')! == 'android' {
		launcher := join([overlay, 'usr/bin/run-android-calculator'])!
		if test('exists', launcher)! || test('is_symlink', launcher)! { unlink(launcher)! }
		write(launcher, '#!/bin/sh\nexec /opt/android-test/launch "$@"\n')!
		chmod(launcher, 0o755)!
	}
	supply_host_libraries(attribute_text(args, 'repo')!, overlay, base)!
	if attribute(args, 'initramfs')! is json2.Null {
		for directory in ['sbin', 'proc', 'dev', 'sys', 'tmp', 'root', 'run'] {
			mkdir(join([overlay, directory])!, true, true)!
		}
		init := join([overlay, 'sbin/init'])!
		if test('exists', init)! || test('is_symlink', init)! { unlink(init)! }
		copy(join([root, 'tests/android/guest-init.sh'])!, init)!
		args_set(mut args, 'initramfs', ah.Value(join([
			attribute_text(args, 'state_dir')!,
			'initramfs.tar',
		])!), 'path')!
		archive_root(overlay, attribute_text(args, 'initramfs')!)!
		return null()
	}
	return ah.Value(overlay)
}

fn prepare_probe(mut args map[string]ah.Value, probe ProbeFile, directory string, executable bool) ! {
	if !truth(attribute(args, probe.name)!) { return }
	target := join([directory, probe.target])!
	copy(attribute_text(args, probe.name)!, target)!
	if executable { chmod(target, 0o755)! }
	args_set(mut args, probe.name + '_sha256', ah.Value(digest(target)!), 'value')!
}
