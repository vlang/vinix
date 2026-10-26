// SPDX-License-Identifier: GPL-2.0-or-later
// Isolated ART regression and Maps retest using the qualified Maps372 runtime.
module main

import crypto.sha256
import json2
import modulestream
import os
import strconv
import time

#include <sys/clonefile.h>
#include <signal.h>
fn C.clonefile(&char, &char, int) int
fn C.kill(int, int) int

const repo = '/Users/alex/code/vinix'
const baseline = repo + '/build/android-maps/maps372/vm'
const baseline_boot = '176094564fba09181b1a2f334f240dc49f0e5f25032696a84db12c2316d0445c'
const baseline_jar = '3b345e1661ca9f5b616f5abe25c9f4abc1df383204d25333477dae69221a8d21'
const qemu = repo + '/build/qemu-horizontal/bin/qemu-system-aarch64'
const firmware = '/opt/homebrew/share/qemu/edk2-aarch64-code.fd'
const jar_member = 'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'
const native_member = 'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'
const baseline_native = 'd3da7eefd58c8f1faf7a88dd0b6fa0839cebdba145d236bd5fe1ecc185e257a1'
const installed_apks = 'root/.local/share/vinix/android/application.apk_/_installed_apks_/'
const activity_packages = ['org.vinix.activity.client', 'org.vinix.activity.companion', 'org.vinix.activity.disabled']
const modules = ['initramfs.tar', 'qemu-runtime.tar', 'maps335-diagnostics.tar', 'maps350-diagnostics.tar', 'maps372-diagnostics.tar']
const fixture_pass = 'ACCOUNT-ASYNC-PASS credential-insertion-rejected null-type no-callback no-accounts main-queued worker-to-main explicit-handler callback-once same-future done cancel-false result-authenticator-exception repeat timed null-unit'
const response_pass = 'AUTHENTICATOR-RESPONSE-PASS local proxy oneway descriptor null-bundle intent error parcelable remote-exception runtime-exception parcel-cleanup'
const activity_pass = 'COMPANION-ACTIVITY-PASS package classloader resources theme application-once caller intent-copy cached-result result-overwrite finish-once default-canceled recreate-pending primary-recreate missing disabled unexported permission cached-invisible'

fn fixture_source(kind string) !string {
	return match kind {
		'fixture' { repo + '/tests/native-android-ws/account-addition-fixture.v' }
		'response-fixture' { repo + '/tests/native-android-ws/authenticator-response-fixture.v' }
		'companion-activity-fixture' { repo + '/tests/native-android-ws/companion-activity-fixture.v' }
		else { return error('unknown account fixture kind') }
	}
}

fn fixture_marker(kind string) !string {
	return match kind {
		'fixture' { fixture_pass }
		'response-fixture' { response_pass }
		'companion-activity-fixture' { activity_pass }
		else { return error('unknown account fixture kind') }
	}
}

fn fixture_scope(kind string) !string {
	return match kind {
		'fixture' { 'unsupported account future/callback contract in guest ART' }
		'response-fixture' { 'authenticator response Binder/Parcelable contract in guest ART; no Google authentication' }
		'companion-activity-fixture' { 'explicit companion Activity ownership, recreation and result lifetime in guest ART; no Google authentication' }
		else { return error('unknown account fixture kind') }
	}
}

struct Ownership {
	pid     int
	command string
	started string
}

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut sum := sha256.new()
	mut bytes := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut bytes) or { if err.code() == 0 { break }; return err }
		if n == 0 { break }
		sum.write(bytes[..n])!
	}
	return sum.sum([]u8{}).hex()
}

fn write_json[T](path string, value T) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn checked(argv []string) !string {
	r := os.exec(argv)
	if r.exit_code != 0 { return error(argv[0] + ': ' + r.output) }
	return r.output.trim_space()
}

fn command(root string, label string, argv []string) !string {
	exe := if argv[0].contains('/') { os.real_path(argv[0]) } else { os.find_abs_path_of_executable(argv[0])! }
	exe_hash := digest(exe)!
	started := time.utc().str()
	r := os.exec(argv)
	os.write_file(root + '/commands/' + label + '.log', r.output)!
	write_json(root + '/commands/' + label + '.json', {
		'argv': json2.Any(argv), 'started_utc': json2.Any(started),
		'completed_utc': json2.Any(time.utc().str()), 'exit_code': json2.Any(r.exit_code),
		'executable_sha256': json2.Any(exe_hash)
	})!
	if r.exit_code != 0 { return error(label + ': ' + r.output) }
	if digest(exe)! != exe_hash { return error('command executable changed: ' + exe) }
	return r.output
}

fn stream_module(root string, label string, image string, member string, destination string) !string {
	mut executables := map[string]string{}
	for name in ['mcopy', '/usr/bin/tar', '/usr/bin/shasum'] {
		path := if name.contains('/') { name } else { os.find_abs_path_of_executable(name)! }
		executables[path] = digest(path)!
	}
	started := time.utc().str()
	mut pin := ''
	mut producer := 0
	mut consumer := 0
	if destination == '' {
		result := modulestream.hash_member(image, member, root + '/commands/' + label + '.log')!
		pin = result.sha256
		producer = result.statuses.producer
		consumer = result.statuses.consumer
	} else {
		result := modulestream.extract_member(image, member, destination)!
		producer = result.producer
		consumer = result.consumer
	}
	write_json(root + '/commands/' + label + '.json', {
		'image': json2.Any(image), 'member': json2.Any(member), 'destination': json2.Any(destination),
		'started_utc': json2.Any(started), 'completed_utc': json2.Any(time.utc().str()),
		'producer_exit_code': json2.Any(producer), 'consumer_exit_code': json2.Any(consumer),
		'sha256': json2.Any(pin), 'executable_sha256': json2.decode[json2.Any](json2.encode(executables))!
	})!
	for path, expected in executables { if digest(path)! != expected { return error('stream executable changed: ' + path) } }
	if producer != 0 || consumer != 0 || (destination == '' && pin.len != 64) {
		return error('module stream failed: ' + label)
	}
	return pin
}

fn inventory(root string, prefix string, mut pins map[string]string) ! {
	for name in os.ls(root + '/' + prefix)! {
		key := if prefix == '' { name } else { prefix + '/' + name }
		path := root + '/' + key
		match os.lstat(path)!.get_filetype() {
			.directory { inventory(root, key, mut pins)! }
			.regular {
				if key.ends_with('.oat') || key.ends_with('.odex') || key.ends_with('.vdex') || key.contains('/dalvik-cache/') {
					return error('compiled cache could shadow framework DEX: ' + key)
				}
				pins[key] = digest(path)!
			}
			.symbolic_link { pins[key] = 'symlink:' + os.readlink(path)! }
			else { return error('unexpected runtime file kind: ' + key) }
		}
	}
}

fn root_check(root string) ! {
	if !root.starts_with('/Users/alex/.local/state/vinix/android/') || root.contains_any(' \n\t')
		|| os.real_path(root) != root || os.is_link(root) { return error('canonical external state path required') }
}

// New files are allowed only when this preparation names their exact paths and
// expected contents. Every original file remains present, with only the named
// replacements changing; a replacement already present is also rejected.
fn runtime_delta(before map[string]string, after map[string]string, replacements map[string]string, additions map[string]string) ! {
	if after.len != before.len + additions.len { return error('runtime file count differs') }
	for name, expected in replacements {
		if name !in before || name in additions || before[name] == expected {
			return error('invalid runtime replacement: ' + name)
		}
	}
	for name, expected in additions {
		if name in before || name !in after || after[name] != expected {
			return error('unexpected added runtime file: ' + name)
		}
	}
	for name, pin in before {
		expected := replacements[name] or { pin }
		if name !in after || after[name] != expected { return error('unexpected runtime delta: ' + name) }
	}
}

// Accept only the three APKs built by the maintained Activity fixture. Verify
// their receipt, signatures and package names again before staging them.
fn activity_apks(root string, apks []string, mut inputs map[string]string) !string {
	if apks.len != activity_packages.len { return error('three Activity fixture APKs required') }
	fixture_root := os.dir(os.dir(apks[0]))
	receipt_path := fixture_root + '/build.json'
	receipt := json2.decode[map[string]json2.Any](os.read_file(receipt_path)!)!
	if receipt['client_package']!.str() != activity_packages[0]
		|| receipt['companion_packages']!.as_array().map(it.str()) != activity_packages[1..]
		|| receipt['pass_marker']!.str() != activity_pass { return error('Activity fixture receipt identity differs') }
	mut args := receipt['argv']!.as_array().map(it.str())
	if args.len != 7 || args[1] != fixture_root { return error('Activity fixture build arguments differ') }
	pins := receipt['inputs_sha256']!.as_map()
	source := fixture_source('companion-activity-fixture')!
	if pins[source]!.str() != digest(source)! { return error('Activity fixture generator differs from receipt') }
	// The maintained generator records invocation arguments as supplied, but
	// identifies its pinned tools by absolute repository paths.
	for i in [2, 5, 6] {
		args[i] = os.abs_path(if args[i].starts_with('/') { args[i] } else { repo + '/' + args[i] })
	}
	for path in [args[2], args[5], args[6]] {
		if path !in pins { return error('Activity fixture tool is not pinned: ' + path) }
	}
	for path, expected in pins {
		if digest(path)! != expected.str() { return error('Activity fixture input changed: ' + path) }
		inputs[path] = expected.str()
	}
	inputs[receipt_path] = digest(receipt_path)!
	declared := receipt['apks_sha256']!.as_map()
	if declared.len != activity_packages.len { return error('Activity fixture APK receipt set differs') }
	for i, apk in apks {
		name := ['client', 'companion', 'disabled'][i]
		if apk != fixture_root + '/' + name + '/probe.apk' || os.is_link(apk)
			|| declared[apk]!.str() != digest(apk)! { return error('Activity fixture APK differs: ' + name) }
		command(root, 'activity-' + name + '-signature', [args[5], '-jar', args[6], 'verify', '--verbose', apk])!
		badging := command(root, 'activity-' + name + '-badging', [args[2], 'dump', 'badging', apk])!
		packages := badging.split_into_lines().filter(it.starts_with('package:'))
		if packages.len != 1 || !packages[0].starts_with("package: name='" + activity_packages[i] + "' ")
			|| packages[0].contains(' split=') || badging.contains('uses-split:') {
			return error('Activity APK package or split identity differs: ' + name)
		}
		if i == 0 && !badging.split_into_lines().any(it.starts_with("launchable-activity: name='org.vinix.activity.Main' ")) {
			return error('Activity fixture launcher differs')
		}
		inputs[apk] = digest(apk)!
	}
	return receipt_path
}

fn prepare(root string, build string, apk string, kind string, companions []string) ! {
	if (apk == '') != (kind == 'maps') { return error('fixture APK and kind differ') }
	if (kind == 'companion-activity-fixture' && companions.len != 2)
		|| (kind != 'companion-activity-fixture' && companions.len != 0) { return error('Activity fixture companion set differs') }
	if apk != '' { fixture_source(kind)! }
	if os.exists(root) || os.is_link(root) { return error('fresh external state required') }
	os.mkdir_all(root + '/commands')!
	root_check(root)!
	receipt := json2.decode[map[string]json2.Any](os.read_file(build + '/build.json')!)!
	jar := build + '/api-impl.jar'
	jar_hash := digest(jar)!
	if jar_hash != receipt['api_impl_sha256']!.str() { return error('new framework JAR differs from build receipt') }
	if digest(baseline + '/boot.img')! != baseline_boot { return error('qualified Maps372 boot differs') }
	mut inputs := map[string]string{}
	for path in [baseline + '/boot.img', baseline + '/efivars.fd', jar, build + '/build.json',
		repo + '/tests/native-android-ws/account-contract-run.v',
		repo + '/build-support/android/modulestream/stream.v',
		repo + '/build-support/android/modulestream/spawn_abi.h',
		os.executable(), qemu, firmware] { inputs[path] = digest(path)! }
	if apk != '' {
		inputs[apk] = digest(apk)!
		inputs[fixture_source(kind)!] = digest(fixture_source(kind)!)!
	}
	mut activity_receipt := ''
	mut native := ''
	if kind == 'companion-activity-fixture' {
		activity_receipt = activity_apks(root, [apk, companions[0], companions[1]], mut inputs)!
		native = build + '/native/libvinix-android-native.so'
		if digest(native)! != receipt['native_sha256']!.str()
			|| receipt['native_base_sha256']!.str() != baseline_native { return error('native library differs from build receipt or frozen351 base') }
		inputs[native] = digest(native)!
	}
	for name in ['boot.img', 'efivars.fd'] {
		from := baseline + '/' + name
		to := root + '/' + name
		if C.clonefile(from.str, to.str, 0) != 0 { return error('APFS clone failed: ' + name) }
		if digest(to)! != inputs[from]! { return error('cloned media differs: ' + name) }
	}
	config := command(root, 'read-limine', ['mtype', '-i', baseline + '/boot.img', '::/boot/limine.conf'])!
	module_lines := config.split_into_lines().map(it.trim_space()).filter(it.starts_with('module_path:'))
	if module_lines != modules.map('module_path: boot():/boot/' + it) { return error('unexpected baseline module load order') }
	os.write_file(root + '/limine-before.conf', config)!
	mut module_pins := map[string]string{}
	os.mkdir_all(root + '/scratch')!
	for name in modules {
		module_pins[name] = stream_module(root, 'hash-' + name, baseline + '/boot.img', name, '')!
		// initramfs supplies the OS; the Android runtime and ordered overlays
		// form the application tree whose exact file delta is checked below.
		if name != 'initramfs.tar' {
			stream_module(root, 'compose-' + name, baseline + '/boot.img', name, root + '/scratch')!
		}
		if name !in ['initramfs.tar', 'qemu-runtime.tar'] {
			command(root, 'extract-' + name, ['mcopy', '-i', baseline + '/boot.img', '::/boot/' + name, root + '/' + name])!
			if digest(root + '/' + name)! != module_pins[name]! { return error('retained original module differs: ' + name) }
		}
	}
	if digest(root + '/scratch/' + jar_member)! != baseline_jar { return error('composed runtime framework is not Framework371') }
	mut before := map[string]string{}
	inventory(root + '/scratch', '', mut before)!
	os.cp(jar, root + '/scratch/' + jar_member)!
	mut changed := [jar_member]
	mut replacements := {jar_member: jar_hash}
	mut additions := map[string]string{}
	if apk != '' {
		os.cp(apk, root + '/scratch/opt/android-test/application.apk')!
		os.write_file(root + '/scratch/opt/android-test/popular-id', 'account-contract')!
		os.write_file(root + '/scratch/usr/share/vinix/android-app-label', 'Account contract')!
		changed << ['opt/android-test/application.apk', 'opt/android-test/popular-id', 'usr/share/vinix/android-app-label']
		replacements['opt/android-test/application.apk'] = inputs[apk]!
		replacements['opt/android-test/popular-id'] = sha256.sum('account-contract'.bytes()).hex()
		replacements['usr/share/vinix/android-app-label'] = sha256.sum('Account contract'.bytes()).hex()
	}
	if kind == 'companion-activity-fixture' {
		if before[native_member] != baseline_native { return error('composed runtime native library is not frozen351') }
		os.cp(native, root + '/scratch/' + native_member)!
		replacements[native_member] = inputs[native]!
		changed << native_member
		for i, companion in companions {
			member := installed_apks + activity_packages[i + 1] + '.apk'
			if member in before { return error('Activity companion already exists in baseline: ' + member) }
			os.mkdir_all(os.dir(root + '/scratch/' + member))!
			os.cp(companion, root + '/scratch/' + member)!
			additions[member] = inputs[companion]!
			changed << member
		}
	}
	mut after := map[string]string{}
	inventory(root + '/scratch', '', mut after)!
	runtime_delta(before, after, replacements, additions)!
	write_json(root + '/module-before.json', before)!
	write_json(root + '/module-after.json', after)!
	for name in changed {
		os.mkdir_all(os.dir(root + '/overlay/' + name))!
		os.cp(root + '/scratch/' + name, root + '/overlay/' + name)!
	}
	command(root, 'create-account-overlay', ['/usr/bin/tar', '--format=ustar', '-b', '1', '-cf', root + '/account-contract.tar', '-C', root + '/overlay', '.'])!
	overlay_pin := digest(root + '/account-contract.tar')!
	command(root, 'install-account-overlay', ['mcopy', '-o', '-i', root + '/boot.img', root + '/account-contract.tar', '::/boot/account-contract.tar'])!
	os.write_file(root + '/limine-after.conf', config.trim_right('\n') + '\n    module_path: boot():/boot/account-contract.tar\n')!
	command(root, 'install-limine', ['mcopy', '-o', '-i', root + '/boot.img', root + '/limine-after.conf', '::/boot/limine.conf'])!
	if command(root, 'read-back-limine', ['mtype', '-i', root + '/boot.img', '::/boot/limine.conf'])! != os.read_file(root + '/limine-after.conf')! { return error('written module load order differs') }
	command(root, 'read-back-overlay', ['mcopy', '-i', root + '/boot.img', '::/boot/account-contract.tar', root + '/read-back-overlay.tar'])!
	if digest(root + '/read-back-overlay.tar')! != overlay_pin { return error('written account overlay differs') }
	os.mkdir_all(root + '/read-back-overlay')!
	command(root, 'unpack-read-back-overlay', ['/usr/bin/tar', '-xf', root + '/read-back-overlay.tar', '-C', root + '/read-back-overlay'])!
	mut overlay_files := map[string]string{}
	inventory(root + '/read-back-overlay', '', mut overlay_files)!
	if overlay_files.len != changed.len { return error('account overlay file set differs') }
	for name in changed { if overlay_files[name] != after[name] { return error('account overlay file differs: ' + name) } }
	for name, pin in module_pins {
		if stream_module(root, 'preserved-' + name, root + '/boot.img', name, '')! != pin { return error('original module changed: ' + name) }
	}
	os.rmdir_all(root + '/overlay')!
	os.rmdir_all(root + '/read-back-overlay')!
	os.rmdir_all(root + '/scratch')!
	for path, pin in inputs { if digest(path)! != pin { return error('input changed while preparing: ' + path) } }
	os.cp(repo + '/tests/native-android-ws/account-contract-run.v', root + '/runner-source.v')!
	os.mkdir_all(root + '/stream-source')!
	for name in ['stream.v', 'spawn_abi.h'] {
		os.cp(repo + '/build-support/android/modulestream/' + name, root + '/stream-source/' + name)!
	}
	if apk != '' {
		os.cp(apk, root + '/fixture.apk')!
		os.cp(fixture_source(kind)!, root + '/fixture-source.v')!
	}
	if kind == 'companion-activity-fixture' {
		os.cp(activity_receipt, root + '/fixture-build.json')!
		for i, companion in companions { os.cp(companion, root + '/fixture-' + activity_packages[i + 1] + '.apk')! }
	}
	os.cp(os.executable(), root + '/runner')!
	write_json(root + '/prepare.json', {
		'scope': json2.Any(if apk == '' { 'Maps precredential Add account retest; no authenticator or account store' } else { fixture_scope(kind)! }),
		'kind': json2.Any(kind),
		'source_revision': json2.Any(checked(['/usr/bin/git', '-C', repo, 'rev-parse', 'HEAD'])!),
		'input_sha256': json2.decode[json2.Any](json2.encode(inputs))!,
		'preserved_original_module_sha256': json2.decode[json2.Any](json2.encode(module_pins))!,
		'account_overlay_sha256': json2.Any(overlay_pin),
		'prepared_boot_sha256': json2.Any(digest(root + '/boot.img')!),
		'changed_runtime_files': json2.Any(changed),
		'added_runtime_files': json2.decode[json2.Any](json2.encode(additions))!
	})!
	println('ACCOUNT-CONTRACT-PREPARED ' + root)
}

fn identity(pid int) !Ownership {
	if pid <= 1 { return error('invalid process ID') }
	return Ownership{pid: pid, command: checked(['/bin/ps', '-ww', '-p', pid.str(), '-o', 'command='])!, started: checked(['/bin/ps', '-p', pid.str(), '-o', 'lstart='])!}
}

fn owned(root string) !Ownership {
	root_check(root)!
	recorded := json2.decode[Ownership](os.read_file(root + '/ownership.json')!)!
	if strconv.atoi(os.read_file(root + '/qemu.pid')!.trim_space())! != recorded.pid { return error('ownership PID differs') }
	current := identity(recorded.pid)!
	if current != recorded || !current.command.starts_with(qemu + ' ')
		|| !current.command.contains('unix:' + root + '/qmp.sock,server=on,wait=off')
		|| !current.command.ends_with('-pidfile ' + root + '/qemu.pid') { return error('process ownership differs; refusing signal') }
	return current
}

fn start(root string) ! {
	root_check(root)!
	if os.exists(root + '/launch.json') || os.is_link(root + '/launch.json') { return error('guest can be launched once only') }
	for line in checked(['/bin/ps', '-axo', 'pid=,command='])!.split_into_lines() {
		if line.contains(qemu + ' ') && (line.contains('/maps372/') || line.contains('/maps-signin-') || line.contains('/account-contract-')) { return error('another Maps/account guest is live') }
	}
	prepared := json2.decode[map[string]json2.Any](os.read_file(root + '/prepare.json')!)!
	if digest(root + '/boot.img')! != prepared['prepared_boot_sha256']!.str() { return error('prepared image changed') }
	args := ['-qmp', 'unix:' + root + '/qmp.sock,server=on,wait=off', '-machine', 'virt,gic-version=3', '-accel', 'hvf', '-cpu', 'host', '-m', '12288', '-smp', '4', '-object', 'rng-random,filename=/dev/urandom,id=vinix-rng', '-device', 'virtio-rng-device', '-drive', 'if=pflash,format=raw,readonly=on,file=' + firmware, '-drive', 'if=pflash,format=raw,file=' + root + '/efivars.fd', '-drive', 'format=raw,file=' + root + '/boot.img', '-device', 'virtio-keyboard-device', '-device', 'virtio-tablet-device', '-device', 'ramfb', '-netdev', 'user,id=net0', '-device', 'virtio-net-device,netdev=net0', '-object', 'filter-dump,id=capture,netdev=net0,file=' + root + '/network.pcap', '-display', 'none', '-monitor', 'none', '-serial', 'file:' + root + '/serial.log', '-daemonize', '-pidfile', root + '/qemu.pid']
	mut argv := [qemu]
	argv << args
	write_json(root + '/launch.json', {'argv': json2.Any(argv), 'started_utc': json2.Any(time.utc().str())})!
	command(root, 'launch', argv)!
	write_json(root + '/ownership.json', identity(strconv.atoi(os.read_file(root + '/qemu.pid')!.trim_space())!)!)!
	println('ACCOUNT-CONTRACT-STARTED pid=' + owned(root)!.pid.str() + ' state=' + root)
}

fn stop(root string) ! {
	owner := owned(root)!
	if C.kill(owner.pid, C.SIGTERM) != 0 { return error('could not signal owned process') }
	write_json(root + '/stop.json', {'pid': json2.Any(owner.pid), 'signal': json2.Any('SIGTERM'), 'requested_utc': json2.Any(time.utc().str())})!
	println('ACCOUNT-CONTRACT-STOP-SENT pid=' + owner.pid.str())
}

fn fixture_log(log string, kind string) !bool {
	expected := fixture_marker(kind)!
	for marker in ['APK-SUITE-EXIT id=', 'ANDROID-WS-FAIL', 'java.lang.AssertionError', 'java.lang.VerifyError', 'NoClassDefFoundError', 'UnsatisfiedLinkError', 'Exception in thread', 'ACCOUNT-ASYNC-FAIL', 'AUTHENTICATOR-RESPONSE-FAIL', 'COMPANION-ACTIVITY-FAIL', 'VINIX-ACCOUNT-PASSWORD-SENTINEL-2026', 'VINIX-ACCOUNT-USERDATA-SENTINEL-2026'] {
		if log.contains(marker) { return error('ART fixture failure marker: ' + marker) }
	}
	mut passes := 0
	for line in log.split_into_lines() {
		if line.contains('ACCOUNT-ASYNC-PASS') || line.contains('AUTHENTICATOR-RESPONSE-PASS') || line.contains('COMPANION-ACTIVITY-PASS') {
			if line.trim_space() != expected { return error('unexpected fixture pass marker') }
			passes++
		}
	}
	if passes > 1 { return error('duplicate fixture pass marker') }
	return log.contains('APK-SUITE-BEGIN id=account-contract ') && passes == 1
}

fn observe(root string) ! {
	config := json2.decode[map[string]json2.Any](os.read_file(root + '/prepare.json')!)!
	kind := config['kind']!.str()
	fixture_marker(kind)!
	mut passed_at := i64(0)
	begin := time.now().unix()
	for time.now().unix() - begin < 180 {
		owned(root)!
		log := os.read_file(root + '/serial.log') or { '' }
		if fixture_log(log, kind)! {
			if passed_at == 0 { passed_at = time.now().unix() }
			if time.now().unix() - passed_at >= 10 {
				write_json(root + '/fixture-result.json', {'passed': json2.Any(true), 'scope': json2.Any(fixture_scope(kind)!), 'quiet_seconds_after_pass': json2.Any(10), 'serial_sha256': json2.Any(digest(root + '/serial.log')!)})!
				println('ACCOUNT-CONTRACT-ART-PASS ten seconds after exact semantic marker')
				return
			}
		}
		time.sleep(250 * time.millisecond)
	}
	return error('ART fixture timed out')
}

fn ownership_test() ! {
	root := '/Users/alex/.local/state/vinix/android/account-contract-ownership-test-' + os.getpid().str()
	if os.exists(root) { return error('fresh ownership test directory required') }
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	mut sleeper := os.new_process('/bin/sleep')
	sleeper.set_args(['30'])
	sleeper.run()
	defer {
		if sleeper.is_alive() { sleeper.signal_term() }
		sleeper.wait()
		sleeper.close()
	}
	write_json(root + '/ownership.json', identity(sleeper.pid)!)!
	os.write_file(root + '/qemu.pid', sleeper.pid.str() + '\n')!
	mut rejected := false
	stop(root) or { rejected = true }
	if !rejected || !sleeper.is_alive() || os.exists(root + '/stop.json') { return error('unrelated process was not protected') }
}

fn runtime_delta_test() ! {
	before := {'framework': 'old', 'native': 'native-old', 'unchanged': 'fixed'}
	after := {'framework': 'new', 'native': 'native-new', 'unchanged': 'fixed', 'companion': 'apk'}
	replacements := {'framework': 'new', 'native': 'native-new'}
	additions := {'companion': 'apk'}
	runtime_delta(before, after, replacements, additions)!
	runtime_delta(before, before, map[string]string{}, map[string]string{})!
	mut candidates := []map[string]string{}
	mut missing := after.clone()
	missing.delete('companion')
	candidates << missing
	mut extra := after.clone()
	extra['unlisted'] = 'extra'
	candidates << extra
	mut removed := after.clone()
	removed.delete('unchanged')
	candidates << removed
	mut altered := after.clone()
	altered['unchanged'] = 'changed'
	candidates << altered
	mut wrong := after.clone()
	wrong['companion'] = 'different'
	candidates << wrong
	mut stale := after.clone()
	stale['native'] = 'native-old'
	candidates << stale
	// Equal file counts must not hide one missing file and an unlisted addition.
	mut substituted := after.clone()
	substituted.delete('companion')
	substituted['unlisted'] = 'apk'
	candidates << substituted
	for candidate in candidates {
		runtime_delta(before, candidate, replacements, additions) or { continue }
		return error('invalid runtime delta accepted')
	}
	for bad_replacements in [
		{'framework': 'new', 'native': 'native-old'},
		{'framework': 'new', 'native': 'native-new', 'absent': 'invalid'},
		{'framework': 'new'}
	] {
		runtime_delta(before, after, bad_replacements, additions) or { continue }
		return error('invalid replacement allowlist accepted')
	}
	runtime_delta(before, after, replacements, {'unchanged': 'fixed'}) or { return }
	return error('preexisting addition accepted')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' {
		for kind in ['fixture', 'response-fixture', 'companion-activity-fixture'] {
			marker := fixture_marker(kind)!
			assert !fixture_log('no begin', kind)!
			assert !fixture_log(marker, kind)!
			assert fixture_log('APK-SUITE-BEGIN id=account-contract backend=vinix-ws\n' + marker + '\r\n', kind)!
			for suffix in [' extra', '\njava.lang.AssertionError late', '\n' + marker, '\nAPK-SUITE-EXIT id=account-contract code=1', '\nVINIX-ACCOUNT-PASSWORD-SENTINEL-2026', '\nVINIX-ACCOUNT-USERDATA-SENTINEL-2026', '\nAUTHENTICATOR-RESPONSE-FAIL', '\nACCOUNT-ASYNC-FAIL', '\nCOMPANION-ACTIVITY-FAIL'] {
				fixture_log('APK-SUITE-BEGIN id=account-contract backend=vinix-ws\n' + marker + suffix, kind) or { continue }
				panic('late or malformed fixture failure accepted')
			}
			for other_kind in ['fixture', 'response-fixture', 'companion-activity-fixture'].filter(it != kind) {
				other := fixture_marker(other_kind)!
				fixture_log('APK-SUITE-BEGIN id=account-contract backend=vinix-ws\n' + other, kind) or { continue }
				panic('wrong fixture contract accepted')
			}
		}
		runtime_delta_test()!
		ownership_test()!
		println('ACCOUNT-CONTRACT-RUN-SELF-TEST-PASS exact replacements/additions checked; late errors, sentinels and duplicate markers rejected; unrelated process protected')
		return
	}
	if os.args.len < 3 { eprintln('usage: account-contract-run prepare ROOT BUILD [FIXTURE_APK] | prepare-response ROOT BUILD FIXTURE_APK | prepare-activity ROOT BUILD CLIENT_APK COMPANION_APK DISABLED_APK | start|stop|status|observe ROOT'); exit(2) }
	root := os.abs_path(os.args[2])
	match os.args[1] {
		'prepare' { if os.args.len !in [4, 5] { exit(2) }; prepare(root, os.abs_path(os.args[3]), if os.args.len == 5 { os.abs_path(os.args[4]) } else { '' }, if os.args.len == 5 { 'fixture' } else { 'maps' }, []string{}) or { eprintln(err); exit(1) } }
		'prepare-response' { if os.args.len != 5 { exit(2) }; prepare(root, os.abs_path(os.args[3]), os.abs_path(os.args[4]), 'response-fixture', []string{}) or { eprintln(err); exit(1) } }
		'prepare-activity' { if os.args.len != 7 { exit(2) }; prepare(root, os.abs_path(os.args[3]), os.abs_path(os.args[4]), 'companion-activity-fixture', [os.abs_path(os.args[5]), os.abs_path(os.args[6])]) or { eprintln(err); exit(1) } }
		'start' { start(root) or { eprintln(err); exit(1) } }
		'stop' { stop(root) or { eprintln(err); exit(1) } }
		'status' { println(json2.encode(owned(root) or { eprintln(err); exit(1) })) }
		'observe' { observe(root) or { eprintln(err); exit(1) } }
		else { exit(2) }
	}
}
