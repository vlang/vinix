// SPDX-License-Identifier: GPL-2.0-or-later
// Real Vinix boots, real ART, unchanged APKs. A live window is observation,
// never an automatic functional pass. Requires an already prepared private VM.
module main

import compress.gzip
import crypto.sha256
import json2
import nativeapk
import os
import time

#include <sys/file.h>

fn C.flock(int, int) int

fn checked(args []string) !string {
	result := os.exec(args)
	if result.exit_code != 0 { return error(args[0] + ': ' + result.output) }
	return result.output
}

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn quote_field(line string, name string) string {
	prefix := name + "='"
	if !line.contains(prefix) { return '' }
	return line.all_after(prefix).all_before("'")
}

fn package_files(source string, package_name string, directory string) !(string, []string) {
	names := checked(['unzip', '-Z1', source])!.split_into_lines()
	if 'AndroidManifest.xml' in names { return source, []string{} }
	if 'manifest.json' !in names { return error('not an APK or supported XAPK container') }
	os.mkdir_all(directory)!
	mut files := []string{}
	for name in names {
		if !name.ends_with('.apk') { continue }
		if name != os.base(name) || name.starts_with('-') || name.contains('..') {
			return error('unsafe container member')
		}
		checked(['unzip', '-o', source, name, '-d', directory])!
		files << directory + '/' + name
	}
	base := directory + '/' + package_name + '.apk'
	if base !in files { return error('missing package base APK') }
	return base, files.filter(it != base)
}

fn inspect_apk(apk string, aapt string, signer string, java string) !map[string]json2.Any {
	badging := checked([aapt, 'dump', 'badging', apk])!
	signature := checked([java, '-jar', signer, 'verify', '--verbose', '--print-certs', apk])!
	mut result := map[string]json2.Any{}
	result['badging'] = badging
	manifest := checked([aapt, 'dump', 'xmltree', apk, '--file', 'AndroidManifest.xml'])!
	result['split_required'] = manifest.contains('requiredSplitTypes')
		|| (manifest.contains('isSplitRequired') && manifest.contains('isSplitRequired(0x01010591)=true'))
		|| manifest.contains('com.android.vending.splits.required')
	mut split_lines := []string{}
	for line in manifest.split_into_lines() {
		if line.contains('requiredSplitTypes') || line.contains('isSplitRequired') || line.contains('com.android.vending.splits') {
			split_lines << line.trim_space()
		}
	}
	result['split_manifest'] = json2.Any(split_lines)
	result['signature_verification'] = signature
	result['apk_sha256'] = digest(apk)!
	for line in badging.split_into_lines() {
		if line.starts_with('package: ') {
			for key in ['name', 'versionCode', 'versionName', 'split'] {
				result[key] = quote_field(line, key)
			}
		} else if line.starts_with('native-code:') {
			result['native_code'] = line.all_after(':').trim_space()
		} else if line.starts_with('sdkVersion:') || line.starts_with('minSdkVersion:') {
			result['min_sdk'] = line.all_after(':').trim("'")
		} else if line.starts_with('targetSdkVersion:') {
			result['target_sdk'] = line.all_after(':').trim("'")
		} else if line.starts_with('launchable-activity:') {
			result['launchable_activity'] = quote_field(line, 'name')
		}
	}
	if (result['name'] or { json2.Any('') }).str() == '' {
		return error('missing APK package identity')
	}
	return result
}

fn observation(log string, id string) map[string]json2.Any {
	begin := log.contains('APK-SUITE-BEGIN id=' + id + ' ')
	ready := log.contains('ANDROID-WS-READY backend=vinix-native')
	exited := log.contains('APK-SUITE-EXIT id=' + id + ' ')
	mut failures := []string{}
	for line in log.split_into_lines() {
		if line.contains('ANDROID-WS-FAIL') || line.contains('APK-SUITE-DEPENDENCY-FAIL')
			|| line.contains('ANDROID-WS-DEPENDENCY-FAIL') || line.contains('ANDROID-WS-PROCESS-FAIL')
			|| line.contains('JNI DETECTED ERROR') || line.contains('NoClassDefFoundError')
			|| line.contains('NoSuchMethodError') || line.contains('UnsatisfiedLinkError')
			|| line.contains('ClassNotFoundException') || line.contains('NoSuchFieldError')
			|| line.contains('APK-SUITE-EXIT id=') {
			failures << line.trim_space()
		}
	}
	return {
		'launcher_entered':     json2.Any(begin)
		'backend_ready':        json2.Any(ready)
		'process_exited':       json2.Any(exited)
		'native_maps_observed': json2.Any(log.contains('APK-SUITE-MAPS id=' + id + ' '))
		'functional_passed':    json2.Any(json2.Null{})
		'outcome':              json2.Any(if !begin {
			'harness_failure'
		} else if exited || failures.len > 0 {
			'startup_failed'
		} else if ready {
			'window_observed'
		} else {
			'startup_timeout'
		})
		'failure_markers':      json2.Any(failures)
	}
}

// Real companion packages, installed at the paths consumed by ATL's package
// loader. PackageManager still authenticates them in guest ART before use.
fn stage_companions(settings map[string]json2.Any, app map[string]json2.Any, output string) ![]json2.Any {
	mut records := []json2.Any{}
	companions := (app['companion_apks'] or { json2.Any([]json2.Any{}) }).as_array()
	data := output + '/module/root/.local/share/vinix/android/application.apk_'
	mut packages := map[string]bool{}
	for item in companions {
		mut record := item.as_map().clone()
		apk := os.abs_path(record['apk']!.str())
		name := record['package']!.str()
		if name.len == 0 || name.split('.').any(it.len == 0 || !it.bytes().all(it.is_alnum() || it == `_`))
			|| name in packages || name == app['package']!.str() {
			return error('invalid or duplicate companion package identity')
		}
		packages[name] = true
		metadata := inspect_apk(apk, settings['aapt2']!.str(), settings['apksigner']!.str(), settings['java']!.str())!
		if metadata['name']!.str() != name || metadata['split_required']!.bool() {
			return error('companion identity mismatch or missing required splits: ' + name)
		}
		libraries := nativeapk.install(apk, output + '/companion-native/' + name, 'arm64-v8a')!
		os.mkdir_all(data + '/_installed_apks_')!
		os.mkdir_all(data + '/' + name + '_/lib')!
		os.link(apk, data + '/_installed_apks_/' + name + '.apk')!
		mut hashes := map[string]json2.Any{}
		for library in os.ls(libraries)! {
			os.cp(libraries + '/' + library, data + '/' + name + '_/lib/' + library)!
			hashes[library] = digest(libraries + '/' + library)!
		}
		record['metadata'] = metadata
		record['native_libraries'] = hashes
		records << json2.Any(record)
	}
	return records
}

fn prepare_module(settings map[string]json2.Any, app map[string]json2.Any, output string) ! {
	native := os.abs_path(settings['native_dir']!.str())
	module_root := output + '/module'
	// Reuse one module directory, replacing the single APK for every fresh boot.
	os.mkdir_all(module_root)!
	data := module_root + '/root/.local/share/vinix/android/application.apk_'
	if os.exists(data) { os.rmdir_all(data)! }
	checked(['tar', '-xf', settings['base_module']!.str(), '-C', module_root])!
	runtime := module_root + '/opt/vinix-android-aarch64'
	for path in ['/opt/android-test', '/usr/bin', '/sbin', '/opt/vinix-android-aarch64/usr/bin',
		'/opt/vinix-android-aarch64/usr/lib/art/native-ws',
		'/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer'] {
		os.mkdir_all(module_root + path)!
	}
	for source, target in {
		'libvinix-android-native.so': runtime + '/usr/lib/art/libvinix-android-native.so'
		'libdl_bio.so.0':             runtime + '/usr/lib/art/native-ws/libdl_bio.so.0'
		'vinix-android-native':       runtime + '/usr/bin/vinix-android-native'
		'run-android':                module_root + '/usr/bin/run-android'
		'api-impl.jar':               runtime + '/usr/lib/java/dex/android_translation_layer/api-impl.jar'
		'vinix-desktop':              module_root + '/usr/bin/vinix-desktop'
		'guest':                      module_root + '/opt/android-test/native-guest'
		'popular-launcher':           module_root + '/usr/bin/run-android-calculator'
	} {
		os.cp(native + '/' + source, target)!
	}
	if os.is_file(native + '/libvinix-android-compat.so') {
		os.cp(native + '/libvinix-android-compat.so', runtime + '/usr/lib/libvinix-android-compat.so')!
	}
	if os.is_file(native + '/tzdata') {
		os.mkdir_all(runtime + '/usr/share/zoneinfo')!
		os.cp(native + '/tzdata', runtime + '/usr/share/zoneinfo/tzdata')!
	}
	if os.is_file(native + '/cacerts') {
		os.mkdir_all(runtime + '/etc/ssl/certs/java')!
		os.cp(native + '/cacerts', runtime + '/etc/ssl/certs/java/cacerts')!
	}
	if os.is_file(native + '/bionic-ws.cfg') {
		config := runtime + '/usr/share/vinix-android-ws/bionic_translation/cfg.d'
		os.mkdir_all(config)!
		os.cp(native + '/bionic-ws.cfg', config + '/native.cfg')!
	}
	for name in ['libglapi.so.0', 'libvinix-ws-GLESv1_CM.so', 'libvinix-ws-GLESv2.so'] {
		if os.is_file(native + '/' + name) { os.cp(native + '/' + name, runtime + '/usr/lib/art/native-ws/' + name)! }
	}
	for provider in ['egl-ws', 'vulkan-ws'] {
		if os.is_dir(native + '/' + provider) {
			os.cp_all(native + '/' + provider, runtime + '/usr/lib/art/native-ws', false)!
		}
	}
	if os.is_file(native + '/vinix-session') { os.cp(native + '/vinix-session', module_root + '/usr/bin/vinix-session')! }
	os.cp(native + '/vinix-desktop', module_root + '/usr/bin/vinix-android-calculator')!
	os.link(os.abs_path(app['staged_apk']!.str()), module_root + '/opt/android-test/application.apk')!
	os.write_file(module_root + '/opt/android-test/popular-id', app['id']!.str())!
	os.mkdir_all(module_root + '/usr/share/vinix')!
	label := (app['name'] or { app['package']! }).str()
	if label.len == 0 || label.len > 128 || label.bytes().any(it < 32 || it == 127) { return error('invalid APK display label') }
	os.write_file(module_root + '/usr/share/vinix/android-app-label', label)!
	os.write_file(module_root + '/opt/android-test/native-mode', 'desktop')!
	// This harness always boots QEMU user networking, whose DNS proxy is
	// 10.0.2.3. Seed it before kernel resolver publication, including for
	// older baseline kernels that do not publish their DHCP DNS settings.
	os.write_file(module_root + '/etc/resolv.conf', 'nameserver 10.0.2.3\n')!
	os.write_file(module_root + '/sbin/init', '#!/bin/sh\nexec /opt/android-test/native-guest\n')!
	os.chmod(module_root + '/sbin/init', 0o755)!
	companions := stage_companions(settings, app, output)!
	os.write_file(output + '/companion-packages.json', json2.encode(companions, prettify: true))!
	stream_module(module_root, settings['boot_image']!.str())!
	os.rm(module_root + '/opt/android-test/application.apk')!
	// Retain hashes and source metadata, rather than another private APK copy.
	if os.exists(data) { os.rmdir_all(data)! }
}

fn run_app(settings map[string]json2.Any, app map[string]json2.Any, output string) !map[string]json2.Any {
	id := app['id']!.str()
	startup_seconds := (app['startup_seconds'] or { json2.Any(60) }).int()
	if startup_seconds < 1 || startup_seconds > 900 { return error('startup_seconds must be between 1 and 900') }
	state := output + '/' + id
	os.mkdir_all(state)!
	prepare_module(settings, app, output)!
	socket := state + '/qmp.sock'
	serial_path := state + '/serial.log'
	if os.exists(socket) { os.rm(socket)! }
	mut qemu := os.new_process(settings['qemu']!.str())
	qemu.set_args(['-qmp', 'unix:' + socket + ',server=on,wait=off', '-machine', 'virt,gic-version=3',
		'-accel', 'hvf', '-cpu', 'host', '-m', '12288', '-smp', '4', '-object',
		'rng-random,filename=/dev/urandom,id=vinix-rng', '-device', 'virtio-rng-device', '-drive',
		'if=pflash,format=raw,readonly=on,file=' + settings['firmware']!.str(), '-drive',
		'if=pflash,format=raw,file=' + settings['efivars']!.str(), '-drive',
		'format=raw,file=' + settings['boot_image']!.str(), '-device', 'virtio-keyboard-device',
		'-device', 'virtio-tablet-device', '-device', 'ramfb', '-netdev', 'user,id=net0', '-device',
		'virtio-net-device,netdev=net0', '-object', 'filter-dump,id=capture,netdev=net0,file=' + state + '/network.pcap', '-display', 'none', '-monitor', 'none', '-serial',
		'file:' + serial_path])
	qemu.run()
	os.write_file(state + '/qemu.pid', qemu.pid.str())!
	defer {
		if qemu.is_alive() { qemu.signal_term() }
		qemu.wait()
	}
	mut begin_at := time.now().unix()
	mut entered := false
	for time.now().unix() - begin_at < if entered { i64(startup_seconds) } else { i64(120) } {
		log := os.read_file(serial_path) or { '' }
		if !entered && log.contains('APK-SUITE-BEGIN id=' + id + ' ') {
			entered = true
			begin_at = time.now().unix()
		}
		if log.contains('APK-SUITE-EXIT id=' + id + ' ') {
			time.sleep(time.second)
			break
		}
		if !qemu.is_alive() { break }
		time.sleep(200 * time.millisecond)
	}
	frame := state + '/application.png'
	mut result := observation(os.read_file(serial_path) or { '' }, id)
	result['companion_packages'] = json2.decode[json2.Any](os.read_file(output + '/companion-packages.json')!)!
	result['startup_timeout_seconds'] = json2.Any(startup_seconds)
	capture := os.exec([settings['input_tool']!.str(), 'screenshot', '--socket', socket, '--destination',
		frame])
	if capture.exit_code == 0 {
		result['screenshot_sha256'] = digest(frame)!
		result['screenshot'] = frame
	} else {
		result['screenshot_error'] = capture.output
	}
	serial := os.read_bytes(serial_path)!
	os.write_file_array(state + '/serial.log.gz', gzip.compress(serial)!)!
	result['serial_sha256'] = sha256.sum(serial).hex()
	result['serial_log'] = state + '/serial.log.gz'
	return result
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' {
		assert observation('no application launch', 'a')['outcome']!.str() == 'harness_failure'
		assert observation('APK-SUITE-BEGIN id=a backend=vinix-ws\nANDROID-WS-READY backend=vinix-native', 'a')['outcome']!.str() == 'window_observed'
		assert observation('APK-SUITE-BEGIN id=a backend=vinix-ws\nANDROID-WS-READY backend=vinix-native\nANDROID-WS-FAIL input or render', 'a')['outcome']!.str() == 'startup_failed'
		assert observation('APK-SUITE-BEGIN id=a backend=vinix-ws\nAPK-SUITE-EXIT id=a code=0', 'a')['outcome']!.str() == 'startup_failed'
		assert observation('APK-SUITE-BEGIN id=a backend=vinix-ws', 'a')['outcome']!.str() == 'startup_timeout'
		println('APK-SUITE-CLASSIFICATION-PASS no-window-pass-after-failure')
		return
	}
	if os.args.len != 2 { panic('usage: suite MANIFEST.json') }
	settings := json2.decode[map[string]json2.Any](os.read_file(os.args[1])!)!
	mut image_guard := os.open_file(settings['boot_image']!.str() + '.suite.lock', 'a', 0o600)!
	if C.flock(image_guard.fd, 6) != 0 {
		panic('this boot image is already in use by another suite')
	}
	defer {
		C.flock(image_guard.fd, 8)
		image_guard.close()
	}
	output := os.abs_path(settings['output']!.str())
	os.mkdir_all(output)!
	mut applications := []json2.Any{}
	for entry in settings['applications']!.as_array() {
		mut app := entry.as_map().clone()
		id := app['id']!.str()
		println('APK-SUITE inspect ' + id)
		base, splits := package_files(app['apk']!.str(), app['package']!.str(), output + '/' + id + '/package') or {
			app['outcome'] = 'package_inspection_failed'
			app['inspection_error'] = err.msg()
			applications << json2.Any(app)
			os.write_file(output + '/results.json', json2.encode(applications, prettify: true))!
			continue
		}
		app['staged_apk'] = base
		app['container_sha256'] = digest(app['apk']!.str())!
		app['split_apks'] = json2.Any(splits)
		mut split_checks := []json2.Any{}
		for split in splits {
			split_checks << json2.Any(inspect_apk(split, settings['aapt2']!.str(), settings['apksigner']!.str(), settings['java']!.str())!)
		}
		app['split_metadata'] = json2.Any(split_checks)
		metadata := inspect_apk(base, settings['aapt2']!.str(), settings['apksigner']!.str(), settings['java']!.str()) or {
			app['outcome'] = 'package_inspection_failed'
			app['inspection_error'] = err.msg()
			applications << json2.Any(app)
			os.write_file(output + '/results.json', json2.encode(applications, prettify: true))!
			continue
		}
		if metadata['name']!.str() != app['package']!.str() {
			panic(id + ': unexpected package identity')
		}
		app['metadata'] = metadata
		app['probe_scope'] = if splits.len > 0 || metadata['split_required']!.bool() {
			'base_apk_startup; required splits not supplied'
		} else {
			'standalone_apk_startup'
		}
		println('APK-SUITE boot ' + id + ' version=' + metadata['versionName']!.str())
		observed := run_app(settings, app, output) or {
			app['outcome'] = 'harness_failure'
			app['harness_error'] = err.msg()
			applications << json2.Any(app)
			os.write_file(output + '/results.json', json2.encode(applications, prettify: true))!
			continue
		}
		for key, value in observed { app[key] = value }
		applications << json2.Any(app)
		os.write_file(output + '/results.json', json2.encode(applications, prettify: true) + '\n')!
		println('APK-SUITE result ' + id + ' ' + app['outcome']!.str())
	}
}

#include <spawn.h>
#include <sys/wait.h>
#include <errno.h>
#include <signal.h>

@[typedef]
struct C.posix_spawn_file_actions_t {}

fn C.posix_spawn_file_actions_init(voidptr) i32
fn C.posix_spawn_file_actions_destroy(voidptr) i32
fn C.posix_spawn_file_actions_adddup2(voidptr, i32, i32) i32
fn C.posix_spawn_file_actions_addclose(voidptr, i32) i32
fn C.posix_spawnp(&i32, &char, voidptr, voidptr, &&char, &&char) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) i32
fn C.WEXITSTATUS(i32) i32
fn C.WTERMSIG(i32) i32
fn C.kill(i32, i32) i32

struct StreamStatuses {
 producer int
 consumer int
}

fn stream_spawn(arguments []string, read_fd int, write_fd int, pipe_fds []int) !i32 {
 if arguments.len == 0 || arguments.any(it.contains('\x00')) { return error('invalid stream command') }
 mut actions := C.posix_spawn_file_actions_t{}
 initialized := C.posix_spawn_file_actions_init(&actions)
 if initialized != 0 { return error('stream spawn actions: ' + os.get_error_msg(initialized)) }
 defer { C.posix_spawn_file_actions_destroy(&actions) }
 for pair in [[read_fd, 0], [write_fd, 1]] {
  if pair[0] < 0 { continue }
  status := C.posix_spawn_file_actions_adddup2(&actions, i32(pair[0]), i32(pair[1]))
  if status != 0 { return error('stream redirect: ' + os.get_error_msg(status)) }
 }
 for descriptor in pipe_fds {
  status := C.posix_spawn_file_actions_addclose(&actions, i32(descriptor))
  if status != 0 { return error('stream close action: ' + os.get_error_msg(status)) }
 }
 mut argv := []&char{cap: arguments.len + 1}
 for argument in arguments { argv << &char(argument.str) }
 argv << &char(unsafe { nil })
 mut environment := []string{}
 for key, value in os.environ() { environment << key + '=' + value }
 mut envp := []&char{cap: environment.len + 1}
 for item in environment { envp << &char(item.str) }
 envp << &char(unsafe { nil })
 mut pid := i32(0)
 status := C.posix_spawnp(&pid, &char(arguments[0].str), &actions, unsafe { nil }, argv.data, envp.data)
 if status != 0 { return error('stream spawn ' + arguments[0] + ': ' + os.get_error_msg(status)) }
 return pid
}

fn stream_wait(pid i32) !int {
 mut status := i32(0)
 for C.waitpid(pid, &status, 0) < 0 {
  if C.errno != C.EINTR { return error('stream wait: ' + os.get_error_msg(C.errno)) }
 }
 return if C.WIFEXITED(status) != 0 { int(C.WEXITSTATUS(status)) } else { 128 + int(C.WTERMSIG(status)) }
}

// Connect the two programs directly. Both statuses are checked: an archive
// producer failure must not be hidden by mcopy successfully copying a prefix.
fn stream_commands(producer []string, consumer []string) !StreamStatuses {
 mut pipe := os.pipe()!
 defer { pipe.close() }
 if pipe.read_fd < 3 || pipe.write_fd < 3 { return error('stream requires open standard descriptors') }
 descriptors := [pipe.read_fd, pipe.write_fd]
 producer_pid := stream_spawn(producer, -1, pipe.write_fd, descriptors)!
 mut producer_reaped := false
 defer {
  if !producer_reaped {
   C.kill(producer_pid, C.SIGKILL)
   stream_wait(producer_pid) or {}
  }
 }
 consumer_pid := stream_spawn(consumer, pipe.read_fd, -1, descriptors)!
 mut consumer_reaped := false
 defer {
  if !consumer_reaped {
   C.kill(consumer_pid, C.SIGKILL)
   stream_wait(consumer_pid) or {}
  }
 }
 pipe.close()
 producer_status := stream_wait(producer_pid)!
 producer_reaped = true
 consumer_status := stream_wait(consumer_pid)!
 consumer_reaped = true
 return StreamStatuses{producer: producer_status, consumer: consumer_status}
}

fn stream_module(module_root string, boot_image string) ! {
 result := stream_commands(['tar', '--format=ustar', '-b', '1', '-cf', '-', '-C', module_root, '.'],
  ['mcopy', '-o', '-i', boot_image, '-', '::/boot/qemu-runtime.tar'])!
 println('MODULE-STREAM producer=' + result.producer.str() + ' consumer=' + result.consumer.str())
 if result.producer != 0 || result.consumer != 0 {
  return error('module stream failed: tar=' + result.producer.str() + ' mcopy=' + result.consumer.str())
 }
}
