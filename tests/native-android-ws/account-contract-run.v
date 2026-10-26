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
const installed_apks = 'tmp/maps256-data/_installed_apks_/'
const activity_packages = ['org.vinix.activity.client', 'org.vinix.activity.companion', 'org.vinix.activity.disabled']
const service_packages = ['org.vinix.serviceaccess.client', 'org.vinix.serviceaccess.companion', 'org.vinix.serviceaccess.blocked', 'org.vinix.serviceaccess.disabled']
const modules = ['initramfs.tar', 'qemu-runtime.tar', 'maps335-diagnostics.tar', 'maps350-diagnostics.tar', 'maps372-diagnostics.tar']
const fixture_pass = 'ACCOUNT-ASYNC-PASS credential-insertion-rejected null-type no-callback no-accounts main-queued worker-to-main explicit-handler callback-once same-future done cancel-false result-authenticator-exception repeat timed null-unit'
const response_pass = 'AUTHENTICATOR-RESPONSE-PASS local proxy oneway descriptor null-bundle intent error parcelable remote-exception runtime-exception parcel-cleanup'
const activity_pass = 'COMPANION-ACTIVITY-PASS package classloader resources theme application-once caller intent-copy cached-result result-overwrite finish-once default-canceled recreate-pending primary-recreate missing disabled unexported permission cached-invisible'
const intent_pass = 'INTENT-PARCEL-PASS values categories selector component source-bounds response-binder bundle cursor typed-array null-clear atomic-read unsupported malformed clip-rejected'
const request_pass = 'AUTHENTICATOR-REQUEST-PASS account-parcel fourteen-local fourteen-proxy typed-values typed-nulls response-binder oneway descriptor unknown trailing-data remote-exception runtime-exception parcel-cleanup'
const authenticator_base_pass = 'AUTHENTICATOR-BASE-PASS fourteen-dispatch permission-denied-before-dispatch result error-mapping async-null label default-removal default-cloning default-sessions suggested-false no-account-registration'
const service_pass = 'SERVICE-ACCESS-PASS declared enabled application-enabled exported permission requested-permission same-package application-once classloader resources intent-copy bind start cached-invisible no-denied-callback'
const fixture_kinds = ['fixture', 'response-fixture', 'companion-activity-fixture', 'intent-parcel-fixture', 'authenticator-request-fixture', 'authenticator-base-fixture', 'service-access-fixture']
const compiled_runner_source = $embed_file(@FILE).to_string()
const compiled_stream_source = $embed_file('../../build-support/android/modulestream/stream.v').to_string()
const compiled_stream_header = $embed_file('../../build-support/android/modulestream/spawn_abi.h').to_string()

fn fixture_source(kind string) !string {
	return match kind {
		'fixture' { repo + '/tests/native-android-ws/account-addition-fixture.v' }
		'response-fixture' { repo + '/tests/native-android-ws/authenticator-response-fixture.v' }
		'companion-activity-fixture' { repo + '/tests/native-android-ws/companion-activity-fixture.v' }
		'intent-parcel-fixture' { repo + '/tests/native-android-ws/intent-parcel-fixture.v' }
		'authenticator-request-fixture' { repo + '/tests/native-android-ws/authenticator-request-fixture.v' }
		'authenticator-base-fixture' { repo + '/tests/native-android-ws/authenticator-base-fixture.v' }
		'service-access-fixture' { repo + '/tests/native-android-ws/service-access-fixture.v' }
		else { return error('unknown account fixture kind') }
	}
}

fn fixture_marker(kind string) !string {
	return match kind {
		'fixture' { fixture_pass }
		'response-fixture' { response_pass }
		'companion-activity-fixture' { activity_pass }
		'intent-parcel-fixture' { intent_pass }
		'authenticator-request-fixture' { request_pass }
		'authenticator-base-fixture' { authenticator_base_pass }
		'service-access-fixture' { service_pass }
		else { return error('unknown account fixture kind') }
	}
}

fn fixture_scope(kind string) !string {
	return match kind {
		'fixture' { 'unsupported account future/callback contract in guest ART' }
		'response-fixture' { 'authenticator response Binder/Parcelable contract in guest ART; no Google authentication' }
		'companion-activity-fixture' { 'explicit companion Activity ownership, recreation and result lifetime in guest ART; no Google authentication' }
		'intent-parcel-fixture' { 'modeled Intent Parcelable codec in guest ART; no native Android byte interoperability or Google authentication' }
		'authenticator-request-fixture' { 'Account Parcelable and authenticator request Binder ABI in guest ART; no account broker, account storage or Google authentication' }
		'authenticator-base-fixture' { 'AbstractAccountAuthenticator base API and transport dispatch in guest ART; no broker, account storage, tokens or Google authentication' }
		'service-access-fixture' { 'ordinary explicit Service access, companion ownership and denied dispatch in guest ART; no privileged account broker or Google authentication' }
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

fn qmp_path_check(root string) ! {
	// QEMU runs on macOS, whose sockaddr_un.sun_path holds 104 bytes,
	// including the terminating NUL. V string lengths count UTF-8 bytes.
	path := root + '/qmp.sock'
	if path.len >= 104 || path.contains('\x00') {
		return error('QMP Unix socket path must be at most 103 bytes: ' + path)
	}
}

fn paths_overlap(first string, second string) bool {
	return first == second || first.starts_with(second + '/') || second.starts_with(first + '/')
}

fn scratch_path(root string, requested string, protected []string) !string {
	if requested == '' { return root + '/scratch' }
	parent := os.dir(requested)
	if !os.is_abs_path(requested) || os.abs_path(requested) != requested
		|| requested.contains_any(' \n\t\x00') || os.exists(requested) || os.is_link(requested)
		|| !os.is_dir(parent) || os.real_path(parent) != parent || os.is_link(parent) {
		return error('scratch requires a fresh absolute canonical path with an existing directory parent')
	}
	for path in [root, repo, baseline] { if paths_overlap(requested, path) { return error('scratch overlaps audit root or runtime source: ' + path) } }
	for path in protected {
		if path != '' && paths_overlap(requested, os.real_path(path)) {
			return error('scratch overlaps a preparation input: ' + path)
		}
	}
	return requested
}

struct ScratchOwnership {
	path string
	dev u64
	inode u64
}

fn create_scratch(path string) !ScratchOwnership {
	// mkdir, unlike mkdir_all, refuses an existing entry. Never adopt a caller's
	// directory, even when it is empty, and retain failures for inspection.
	os.mkdir(path, mode: 0o700)!
	info := os.lstat(path)!
	if info.get_filetype() != .directory || os.real_path(path) != path { return error('created scratch path changed') }
	return ScratchOwnership{path: path, dev: info.dev, inode: info.inode}
}

fn remove_scratch(owned_scratch ScratchOwnership) ! {
	info := os.lstat(owned_scratch.path)!
	if info.get_filetype() != .directory || info.dev != owned_scratch.dev || info.inode != owned_scratch.inode
		|| os.real_path(owned_scratch.path) != owned_scratch.path { return error('scratch ownership changed; refusing cleanup') }
	os.rmdir_all(owned_scratch.path)!
}

fn scratch_completed(root string, prepared map[string]json2.Any) ! {
	// Historical preparations have no external scratch receipt.
	if 'scratch_path' !in prepared { return }
	path := prepared['scratch_path']!.str()
	completion := json2.decode[map[string]string](os.read_file(root + '/scratch.json')!)!
	if completion['path'] != path || completion['state'] != 'complete'
		|| os.exists(path) || os.is_link(path) { return error('scratch preparation did not complete') }
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

fn companion_packages(kind string) ![]string {
	return match kind {
		'companion-activity-fixture' { activity_packages }
		'service-access-fixture' { service_packages }
		else { return error('fixture does not have companion APKs') }
	}
}

// Accept exactly the APKs built by the maintained companion fixture. Verify
// their receipt, signatures and package names again before staging them.
fn companion_apks(root string, apks []string, kind string, mut inputs map[string]string) !string {
	packages := companion_packages(kind)!
	if apks.len != packages.len { return error('companion fixture APK set differs') }
	names := if kind == 'companion-activity-fixture' { ['client', 'companion', 'disabled'] } else { ['client', 'companion', 'blocked', 'disabled'] }
	launcher := if kind == 'companion-activity-fixture' { 'org.vinix.activity.Main' } else { 'org.vinix.serviceaccess.Main' }
	label := if kind == 'companion-activity-fixture' { 'activity' } else { 'service-access' }
	fixture_root := os.dir(os.dir(apks[0]))
	receipt_path := fixture_root + '/build.json'
	receipt := json2.decode[map[string]json2.Any](os.read_file(receipt_path)!)!
	if receipt['client_package']!.str() != packages[0]
		|| receipt['companion_packages']!.as_array().map(it.str()) != packages[1..]
		|| receipt['pass_marker']!.str() != fixture_marker(kind)! { return error('companion fixture receipt identity differs') }
	mut args := receipt['argv']!.as_array().map(it.str())
	if args.len != 7 || args[1] != fixture_root { return error('companion fixture build arguments differ') }
	pins := receipt['inputs_sha256']!.as_map()
	source := fixture_source(kind)!
	if pins[source]!.str() != digest(source)! { return error('companion fixture generator differs from receipt') }
	// The maintained generator records invocation arguments as supplied, but
	// identifies its pinned tools by absolute repository paths.
	for i in [2, 5, 6] {
		args[i] = os.abs_path(if args[i].starts_with('/') { args[i] } else { repo + '/' + args[i] })
	}
	for path in [args[2], args[5], args[6]] {
		if path !in pins { return error('companion fixture tool is not pinned: ' + path) }
	}
	for path, expected in pins {
		if digest(path)! != expected.str() { return error('companion fixture input changed: ' + path) }
		inputs[path] = expected.str()
	}
	inputs[receipt_path] = digest(receipt_path)!
	declared := receipt['apks_sha256']!.as_map()
	if declared.len != packages.len { return error('companion fixture APK receipt set differs') }
	for i, apk in apks {
		name := names[i]
		if apk != fixture_root + '/' + name + '/probe.apk' || os.is_link(apk)
			|| declared[apk]!.str() != digest(apk)! { return error('companion fixture APK differs: ' + name) }
		command(root, label + '-' + name + '-signature', [args[5], '-jar', args[6], 'verify', '--verbose', apk])!
		badging := command(root, label + '-' + name + '-badging', [args[2], 'dump', 'badging', apk])!
		package_lines := badging.split_into_lines().filter(it.starts_with('package:'))
		if package_lines.len != 1 || !package_lines[0].starts_with("package: name='" + packages[i] + "' ")
			|| package_lines[0].contains(' split=') || badging.contains('uses-split:') {
			return error('companion APK package or split identity differs: ' + name)
		}
		if i == 0 && !badging.split_into_lines().any(it.starts_with("launchable-activity: name='" + launcher + "' ")) {
			return error('companion fixture launcher differs')
		}
		inputs[apk] = digest(apk)!
	}
	return receipt_path
}

fn single_fixture_apk(root string, apk string, kind string, mut inputs map[string]string) !string {
	fixture_root := os.dir(apk)
	receipt_path := fixture_root + '/build.json'
	receipt := json2.decode[map[string]json2.Any](os.read_file(receipt_path)!)!
	if os.is_link(apk) || apk != fixture_root + '/probe.apk'
		|| receipt['apk_sha256']!.str() != digest(apk)!
		|| receipt['pass_marker']!.str() != fixture_marker(kind)! { return error('fixture APK or contract differs from receipt') }
	args := receipt['argv']!.as_array().map(it.str())
	if args.len != 6 || args[1] != fixture_root { return error('fixture build arguments differ') }
	pins := receipt['inputs_sha256']!.as_map()
	source := fixture_source(kind)!
	if pins[source]!.str() != digest(source)! { return error('fixture source differs from receipt') }
	java := os.real_path(if args[4].starts_with('/') { args[4] } else { repo + '/' + args[4] })
	signer := os.real_path(if args[5].starts_with('/') { args[5] } else { repo + '/' + args[5] })
	if java !in pins || signer !in pins { return error('fixture signing tools are not pinned') }
	for path, expected in pins {
		if digest(path)! != expected.str() { return error('fixture input changed: ' + path) }
		inputs[path] = expected.str()
	}
	command(root, kind + '-signature', [java, '-jar', signer, 'verify', '--verbose', apk])!
	inputs[receipt_path] = digest(receipt_path)!
	return receipt_path
}

fn native_artifact(build string, receipt map[string]json2.Any, mut inputs map[string]string) !string {
	native := build + '/native/libvinix-android-native.so'
	if digest(native)! != receipt['native_sha256']!.str()
		|| receipt['native_base_sha256']!.str() != baseline_native { return error('native library differs from build receipt or frozen351 base') }
	inputs[native] = digest(native)!
	return native
}

fn request_native(receipt map[string]json2.Any, mut inputs map[string]string) !string {
	base := receipt['baseline_path']!.str()
	pins := receipt['input_sha256']!.as_map()
	for name in ['api-impl.jar', 'build.json', 'sha256.json'] {
		path := base + '/' + name
		if digest(path)! != pins[path]!.str() { return error('request native baseline input changed: ' + path) }
		inputs[path] = pins[path]!.str()
	}
	base_receipt := json2.decode[map[string]json2.Any](os.read_file(base + '/build.json')!)!
	if inputs[base + '/api-impl.jar']! != receipt['baseline_api_impl_sha256']!.str()
		|| inputs[base + '/api-impl.jar']! != base_receipt['api_impl_sha256']!.str()
		|| inputs[base + '/sha256.json']! != receipt['baseline_manifest_sha256']!.str() {
		return error('request native baseline receipt differs')
	}
	return native_artifact(base, base_receipt, mut inputs)
}

fn authenticator_base_native(receipt map[string]json2.Any, mut inputs map[string]string) !string {
	base := receipt['baseline_path']!.str()
	pins := receipt['input_sha256']!.as_map()
	for name in ['api-impl.jar', 'build.json', 'sha256.json'] {
		path := base + '/' + name
		if digest(path)! != pins[path]!.str() { return error('authenticator base framework input changed: ' + path) }
		inputs[path] = pins[path]!.str()
	}
	base_receipt := json2.decode[map[string]json2.Any](os.read_file(base + '/build.json')!)!
	if inputs[base + '/api-impl.jar']! != receipt['baseline_api_impl_sha256']!.str()
		|| inputs[base + '/api-impl.jar']! != base_receipt['api_impl_sha256']!.str()
		|| inputs[base + '/sha256.json']! != receipt['baseline_manifest_sha256']!.str() {
		return error('authenticator base framework receipt differs')
	}
	native := request_native(base_receipt, mut inputs)!
	native_base := receipt['native_reference_path']!.str()
	if native != native_base + '/native/libvinix-android-native.so'
		|| inputs[native]! != receipt['native_sha256']!.str() {
		return error('authenticator base native reference differs from request baseline')
	}
	for name in ['build.json', 'sha256.json', 'native/libvinix-android-native.so'] {
		path := native_base + '/' + name
		if digest(path)! != pins[path]!.str() { return error('authenticator base native reference changed: ' + path) }
		inputs[path] = pins[path]!.str()
	}
	if inputs[native_base + '/sha256.json']! != receipt['native_reference_manifest_sha256']!.str() {
		return error('authenticator base native reference manifest differs')
	}
	return native
}

fn service_native(receipt map[string]json2.Any, mut inputs map[string]string) !string {
	base := receipt['baseline_path']!.str()
	pins := receipt['input_sha256']!.as_map()
	for name in ['api-impl.jar', 'build.json', 'sha256.json'] {
		path := base + '/' + name
		if digest(path)! != pins[path]!.str() { return error('service framework input changed: ' + path) }
		inputs[path] = pins[path]!.str()
	}
	base_receipt := json2.decode[map[string]json2.Any](os.read_file(base + '/build.json')!)!
	if inputs[base + '/api-impl.jar']! != receipt['baseline_api_impl_sha256']!.str()
		|| inputs[base + '/api-impl.jar']! != base_receipt['api_impl_sha256']!.str()
		|| inputs[base + '/sha256.json']! != receipt['baseline_manifest_sha256']!.str() {
		return error('service framework receipt differs')
	}
	native := authenticator_base_native(base_receipt, mut inputs)!
	native_base := receipt['native_reference_path']!.str()
	if native != native_base + '/native/libvinix-android-native.so'
		|| inputs[native]! != receipt['native_sha256']!.str() {
		return error('service native reference differs from authenticator base')
	}
	for name in ['build.json', 'sha256.json', 'native/libvinix-android-native.so'] {
		path := native_base + '/' + name
		if digest(path)! != pins[path]!.str() { return error('service native reference changed: ' + path) }
		inputs[path] = pins[path]!.str()
	}
	if inputs[native_base + '/sha256.json']! != receipt['native_reference_manifest_sha256']!.str() {
		return error('service native reference manifest differs')
	}
	return native
}

fn retain_compiled_sources(root string, mut inputs map[string]string) ! {
	$if !prod { return error('compile this source-capturing runner with -prod; development embeds reload checkout files') }
	for name, source in {
		'runner-source.v': compiled_runner_source,
		'stream-source/stream.v': compiled_stream_source,
		'stream-source/spawn_abi.h': compiled_stream_header
	} {
		path := root + '/' + name
		os.mkdir_all(os.dir(path))!
		os.write_file(path, source)!
		inputs[path] = sha256.sum(source.bytes()).hex()
		if digest(path)! != inputs[path]! { return error('retained compiled source differs: ' + name) }
	}
}

fn prepare(root string, build string, apk string, kind string, companions []string) ! {
	qmp_path_check(root)!
	if (apk == '') != (kind == 'maps') { return error('fixture APK and kind differ') }
	companion_kind := kind in ['companion-activity-fixture', 'service-access-fixture']
	packages := if companion_kind { companion_packages(kind)! } else { []string{} }
	expected_companions := if companion_kind { packages.len - 1 } else { 0 }
	if companions.len != expected_companions { return error('fixture companion set differs') }
	if apk != '' { fixture_source(kind)! }
	if os.exists(root) || os.is_link(root) { return error('fresh external state required') }
	requested_scratch := os.getenv('VINIX_ACCOUNT_CONTRACT_SCRATCH')
	mut protected := [build]
	if apk != '' { protected << os.dir(apk) }
	protected << companions.map(os.dir(it))
	scratch := scratch_path(root, requested_scratch, protected)!
	os.mkdir_all(root + '/commands')!
	root_check(root)!
	write_json(root + '/scratch.json', {'path': scratch, 'selection': if requested_scratch == '' { 'default' } else { 'VINIX_ACCOUNT_CONTRACT_SCRATCH' }, 'state': 'planned; failed composition is retained'})!
	receipt := json2.decode[map[string]json2.Any](os.read_file(build + '/build.json')!)!
	jar := build + '/api-impl.jar'
	jar_hash := digest(jar)!
	if jar_hash != receipt['api_impl_sha256']!.str() { return error('new framework JAR differs from build receipt') }
	if digest(baseline + '/boot.img')! != baseline_boot { return error('qualified Maps372 boot differs') }
	mut inputs := map[string]string{}
	for path in [baseline + '/boot.img', baseline + '/efivars.fd', jar, build + '/build.json',
		os.executable(), qemu, firmware] { inputs[path] = digest(path)! }
	retain_compiled_sources(root, mut inputs)!
	if apk != '' {
		inputs[apk] = digest(apk)!
		inputs[fixture_source(kind)!] = digest(fixture_source(kind)!)!
	}
	mut fixture_receipt := ''
	mut native := ''
	if companion_kind {
		mut apks := [apk]
		apks << companions
		fixture_receipt = companion_apks(root, apks, kind, mut inputs)!
		native = if kind == 'companion-activity-fixture' { native_artifact(build, receipt, mut inputs)! } else { service_native(receipt, mut inputs)! }
	} else if kind in ['intent-parcel-fixture', 'authenticator-request-fixture', 'authenticator-base-fixture'] {
		fixture_receipt = single_fixture_apk(root, apk, kind, mut inputs)!
		if kind == 'authenticator-request-fixture' { native = request_native(receipt, mut inputs)! }
		if kind == 'authenticator-base-fixture' { native = authenticator_base_native(receipt, mut inputs)! }
	}
	// The native reference may live outside BUILD; protect every resolved input
	// directory as well before creating scratch or cloning audit media.
	scratch_path(root, requested_scratch, inputs.keys().map(os.dir(it)))!
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
	owned_scratch := create_scratch(scratch)!
	write_json(root + '/scratch-ownership.json', owned_scratch)!
	for name in modules {
		module_pins[name] = stream_module(root, 'hash-' + name, baseline + '/boot.img', name, '')!
		// initramfs supplies the OS; the Android runtime and ordered overlays
		// form the application tree whose exact file delta is checked below.
		if name != 'initramfs.tar' {
			stream_module(root, 'compose-' + name, baseline + '/boot.img', name, scratch)!
		}
		if name !in ['initramfs.tar', 'qemu-runtime.tar'] {
			command(root, 'extract-' + name, ['mcopy', '-i', baseline + '/boot.img', '::/boot/' + name, root + '/' + name])!
			if digest(root + '/' + name)! != module_pins[name]! { return error('retained original module differs: ' + name) }
		}
	}
	if digest(scratch + '/' + jar_member)! != baseline_jar { return error('composed runtime framework is not Framework371') }
	mut before := map[string]string{}
	inventory(scratch, '', mut before)!
	os.cp(jar, scratch + '/' + jar_member)!
	mut changed := [jar_member]
	mut replacements := {jar_member: jar_hash}
	mut additions := map[string]string{}
	if apk != '' {
		os.cp(apk, scratch + '/opt/android-test/application.apk')!
		os.write_file(scratch + '/opt/android-test/popular-id', 'account-contract')!
		os.write_file(scratch + '/usr/share/vinix/android-app-label', 'Account contract')!
		changed << ['opt/android-test/application.apk', 'opt/android-test/popular-id', 'usr/share/vinix/android-app-label']
		replacements['opt/android-test/application.apk'] = inputs[apk]!
		replacements['opt/android-test/popular-id'] = sha256.sum('account-contract'.bytes()).hex()
		replacements['usr/share/vinix/android-app-label'] = sha256.sum('Account contract'.bytes()).hex()
	}
	if native != '' {
		if before[native_member] != baseline_native { return error('composed runtime native library is not frozen351') }
		os.cp(native, scratch + '/' + native_member)!
		replacements[native_member] = inputs[native]!
		changed << native_member
	}
	if companion_kind {
		for i, companion in companions {
			member := installed_apks + packages[i + 1] + '.apk'
			if member in before { return error('fixture companion already exists in baseline: ' + member) }
			os.mkdir_all(os.dir(scratch + '/' + member))!
			os.cp(companion, scratch + '/' + member)!
			additions[member] = inputs[companion]!
			changed << member
		}
	}
	mut after := map[string]string{}
	inventory(scratch, '', mut after)!
	runtime_delta(before, after, replacements, additions)!
	write_json(root + '/module-before.json', before)!
	write_json(root + '/module-after.json', after)!
	for name in changed {
		os.mkdir_all(os.dir(root + '/overlay/' + name))!
		os.cp(scratch + '/' + name, root + '/overlay/' + name)!
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
	for path, pin in inputs { if digest(path)! != pin { return error('input changed while preparing: ' + path) } }
	if apk != '' {
		os.cp(apk, root + '/fixture.apk')!
		os.cp(fixture_source(kind)!, root + '/fixture-source.v')!
	}
	if fixture_receipt != '' { os.cp(fixture_receipt, root + '/fixture-build.json')! }
	if companion_kind {
		for i, companion in companions { os.cp(companion, root + '/fixture-' + packages[i + 1] + '.apk')! }
	}
	os.cp(os.executable(), root + '/runner')!
	write_json(root + '/prepare.json', {
		'scope': json2.Any(if apk == '' { 'Maps precredential Add account retest; no authenticator or account store' } else { fixture_scope(kind)! }),
		'kind': json2.Any(kind),
		'scratch_path': json2.Any(scratch),
		'scratch_selection': json2.Any(if requested_scratch == '' { 'default' } else { 'VINIX_ACCOUNT_CONTRACT_SCRATCH' }),
		'source_revision': json2.Any(checked(['/usr/bin/git', '-C', repo, 'rev-parse', 'HEAD'])!),
		'source_revision_scope': json2.Any('checkout revision at preparation; embedded runner source is identified separately'),
		'runner_source_sha256': json2.Any(inputs[root + '/runner-source.v']!),
		'runner_source_origin': json2.Any('embedded at runner compilation with $embed_file(@FILE)'),
		'input_sha256': json2.decode[json2.Any](json2.encode(inputs))!,
		'preserved_original_module_sha256': json2.decode[json2.Any](json2.encode(module_pins))!,
		'account_overlay_sha256': json2.Any(overlay_pin),
		'prepared_boot_sha256': json2.Any(digest(root + '/boot.img')!),
		'changed_runtime_files': json2.Any(changed),
		'added_runtime_files': json2.decode[json2.Any](json2.encode(additions))!
	})!
	// Complete all checks and the preparation receipt before discarding scratch.
	// A separate final marker prevents start after cleanup/finalization failure.
	remove_scratch(owned_scratch)!
	write_json(root + '/scratch.json', {'path': scratch, 'selection': if requested_scratch == '' { 'default' } else { 'VINIX_ACCOUNT_CONTRACT_SCRATCH' }, 'state': 'complete'})!
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
	qmp_path_check(root)!
	root_check(root)!
	if os.exists(root + '/launch.json') || os.is_link(root + '/launch.json') { return error('guest can be launched once only') }
	for line in checked(['/bin/ps', '-axo', 'pid=,command='])!.split_into_lines() {
		if line.contains(qemu + ' ') && (line.contains('/maps372/') || line.contains('/maps-signin-') || line.contains('/account-contract-')) { return error('another Maps/account guest is live') }
	}
	prepared := json2.decode[map[string]json2.Any](os.read_file(root + '/prepare.json')!)!
	scratch_completed(root, prepared)!
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
	for marker in ['APK-SUITE-EXIT id=', 'ANDROID-WS-FAIL', 'java.lang.AssertionError', 'java.lang.VerifyError', 'NoClassDefFoundError', 'UnsatisfiedLinkError', 'Exception in thread', 'ACCOUNT-ASYNC-FAIL', 'AUTHENTICATOR-RESPONSE-FAIL', 'COMPANION-ACTIVITY-FAIL', 'INTENT-PARCEL-FAIL', 'AUTHENTICATOR-REQUEST-FAIL', 'AUTHENTICATOR-BASE-FAIL', 'SERVICE-ACCESS-FAIL', 'VINIX-ACCOUNT-PASSWORD-SENTINEL-2026', 'VINIX-ACCOUNT-USERDATA-SENTINEL-2026'] {
		if log.contains(marker) { return error('ART fixture failure marker: ' + marker) }
	}
	mut passes := 0
	for line in log.split_into_lines() {
		if line.contains('ACCOUNT-ASYNC-PASS') || line.contains('AUTHENTICATOR-RESPONSE-PASS') || line.contains('COMPANION-ACTIVITY-PASS') || line.contains('INTENT-PARCEL-PASS') || line.contains('AUTHENTICATOR-REQUEST-PASS') || line.contains('AUTHENTICATOR-BASE-PASS') || line.contains('SERVICE-ACCESS-PASS') {
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

fn compiled_sources_test() ! {
	root := '/Users/alex/.local/state/vinix/android/account-contract-source-test-' + os.getpid().str()
	if os.exists(root) { return error('fresh source test directory required') }
	defer { os.rmdir_all(root) or {} }
	mut inputs := map[string]string{}
	retain_compiled_sources(root, mut inputs)!
	if inputs.len != 3 || os.read_file(root + '/runner-source.v')! != compiled_runner_source
		|| os.read_file(root + '/stream-source/stream.v')! != compiled_stream_source
		|| os.read_file(root + '/stream-source/spawn_abi.h')! != compiled_stream_header {
		return error('compiled source snapshot differs')
	}
	println('ACCOUNT-CONTRACT-COMPILED-SOURCE-PASS sha256=' + inputs[root + '/runner-source.v']!)
}

fn service_additions_test() ! {
	before := {'framework': 'old', 'native': 'old-native', 'unchanged': 'fixed'}
	replacements := {'framework': 'new', 'native': 'new-native'}
	mut additions := map[string]string{}
	for i, package_name in companion_packages('service-access-fixture')![1..] {
		additions[installed_apks + package_name + '.apk'] = 'apk-' + i.str()
	}
	if additions.len != 3 { return error('service fixture companion set differs') }
	mut after := before.clone()
	for name, pin in replacements { after[name] = pin }
	for name, pin in additions { after[name] = pin }
	runtime_delta(before, after, replacements, additions)!
	for name in additions.keys() {
		for case in 0 .. 3 {
			mut bad := after.clone()
			match case {
				0 { bad.delete(name) }
				1 { bad[name] = 'wrong-apk' }
				else { bad.delete(name); bad[installed_apks + 'unlisted.apk'] = 'unlisted' }
			}
			runtime_delta(before, bad, replacements, additions) or { continue }
			return error('invalid service companion addition accepted')
		}
	}
}

fn qmp_path_test() ! {
	suffix := '/qmp.sock'
	qmp_path_check('/' + 'x'.repeat(103 - suffix.len - 1))!
	for root in ['/' + 'x'.repeat(104 - suffix.len - 1), '/' + 'é'.repeat(48), '/bad\x00path'] {
		qmp_path_check(root) or { continue }
		return error('invalid QMP Unix socket path accepted')
	}
	root := '/Users/alex/.local/state/vinix/android/account-contract-qmp-path-test-' + os.getpid().str() + '-' + 'x'.repeat(104)
	if os.exists(root) || os.is_link(root) { return error('fresh QMP path test required') }
	mut prepare_rejected := false
	prepare(root, '/does-not-exist', '', 'maps', []string{}) or {
		prepare_rejected = err.msg().starts_with('QMP Unix socket path ')
	}
	mut start_rejected := false
	start(root) or { start_rejected = err.msg().starts_with('QMP Unix socket path ') }
	if !prepare_rejected || !start_rejected || os.exists(root) || os.is_link(root) {
		return error('long QMP path was not rejected before prepare/start mutation')
	}
}

fn scratch_test() ! {
	parent := '/Users/alex/.local/state/vinix/android/account-contract-scratch-test-' + os.getpid().str()
	if os.exists(parent) || os.is_link(parent) { return error('fresh scratch test directory required') }
	os.mkdir(parent)!
	defer { os.rmdir_all(parent) or {} }
	root := parent + '/audit'
	path := parent + '/composition'
	input := parent + '/inputs'
	os.mkdir(input)!
	os.write_file(parent + '/existing-file', 'untouched')!
	os.symlink(parent, parent + '/alias')!
	os.symlink(parent + '/missing', parent + '/broken')!
	if scratch_path(root, '', [input])! != root + '/scratch'
		|| scratch_path(root, path, [input])! != path
		|| scratch_path(root, root + '-sibling', [input])! != root + '-sibling' {
		return error('valid scratch path rejected')
	}
	for bad in ['relative', parent + '/composition/', parent + '/./composition', parent + '/missing/child',
		parent + '/alias/child', parent + '/broken', parent + '/existing-file', input,
		input + '/child', root, root + '/child', parent, repo + '/untracked-scratch', path + '\x00bad'] {
		scratch_path(root, bad, [input]) or { continue }
		return error('unsafe scratch path accepted: ' + bad)
	}
	if !paths_overlap(root, root + '/child') || !paths_overlap(root + '/child', root)
		|| paths_overlap(root, root + '-sibling') { return error('scratch ancestry check differs') }
	owned_scratch := create_scratch(path)!
	os.write_file(path + '/partial', 'retained')!
	create_scratch(path) or {
		if os.read_file(path + '/partial')! != 'retained' { return error('existing scratch was modified') }
		// A replacement directory must survive cleanup attempted with old ownership.
		os.mv(path, path + '-original')!
		os.mkdir(path)!
		os.write_file(path + '/unrelated', 'untouched')!
		mut rejected := false
		remove_scratch(owned_scratch) or { rejected = true }
		if !rejected || os.read_file(path + '/unrelated')! != 'untouched'
			|| os.read_file(path + '-original/partial')! != 'retained' { return error('scratch cleanup accepted a replacement directory') }
		os.rmdir_all(path)!
		os.mv(path + '-original', path)!
		remove_scratch(owned_scratch)!
		if os.exists(path) { return error('owned scratch cleanup failed') }
		scratch_completed(parent, map[string]json2.Any{})!
		prepared := {'scratch_path': json2.Any(path)}
		for completion in [
			{'path': path, 'state': 'planned'},
			{'path': path + '-different', 'state': 'complete'}
		] {
			write_json(parent + '/scratch.json', completion)!
			scratch_completed(parent, prepared) or { continue }
			return error('incomplete scratch preparation accepted')
		}
		write_json(parent + '/scratch.json', {'path': path, 'state': 'complete'})!
		scratch_completed(parent, prepared)!
		os.symlink(input, path)!
		mut linked_rejected := false
		scratch_completed(parent, prepared) or { linked_rejected = true }
		os.rm(path)!
		if !linked_rejected { return error('scratch completion accepted a remaining symlink') }
		previous := os.getenv('VINIX_ACCOUNT_CONTRACT_SCRATCH')
		os.setenv('VINIX_ACCOUNT_CONTRACT_SCRATCH', input, true)
		defer { os.setenv('VINIX_ACCOUNT_CONTRACT_SCRATCH', previous, true) }
		mut prepare_rejected := false
		prepare(root, input, '', 'maps', []string{}) or { prepare_rejected = err.msg().starts_with('scratch ') }
		if !prepare_rejected || os.exists(root) || os.is_link(root) { return error('unsafe scratch was not rejected before prepare mutation') }
		println('ACCOUNT-CONTRACT-SCRATCH-PASS freshness aliases overlap ownership cleanup and pre-mutation rejection')
		return
	}
	return error('scratch creation adopted an existing directory')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' {
		for kind in fixture_kinds {
			marker := fixture_marker(kind)!
			if fixture_log('no begin', kind)! || fixture_log(marker, kind)!
				|| !fixture_log('APK-SUITE-BEGIN id=account-contract backend=vinix-ws\n' + marker + '\r\n', kind)! {
				panic('fixture begin or exact marker classification differs')
			}
			for suffix in [' extra', '\njava.lang.AssertionError late', '\n' + marker, '\nAPK-SUITE-EXIT id=account-contract code=1', '\nVINIX-ACCOUNT-PASSWORD-SENTINEL-2026', '\nVINIX-ACCOUNT-USERDATA-SENTINEL-2026', '\nAUTHENTICATOR-RESPONSE-FAIL', '\nACCOUNT-ASYNC-FAIL', '\nCOMPANION-ACTIVITY-FAIL', '\nINTENT-PARCEL-FAIL', '\nAUTHENTICATOR-REQUEST-FAIL', '\nAUTHENTICATOR-BASE-FAIL', '\nSERVICE-ACCESS-FAIL'] {
				fixture_log('APK-SUITE-BEGIN id=account-contract backend=vinix-ws\n' + marker + suffix, kind) or { continue }
				panic('late or malformed fixture failure accepted')
			}
			for other_kind in fixture_kinds.filter(it != kind) {
				other := fixture_marker(other_kind)!
				fixture_log('APK-SUITE-BEGIN id=account-contract backend=vinix-ws\n' + other, kind) or { continue }
				panic('wrong fixture contract accepted')
			}
		}
		runtime_delta_test()!
		service_additions_test()!
		qmp_path_test()!
		scratch_test()!
		compiled_sources_test()!
		ownership_test()!
		println('ACCOUNT-CONTRACT-RUN-SELF-TEST-PASS exact replacements/additions checked; late errors, sentinels and duplicate markers rejected; unrelated process protected')
		return
	}
	if os.args.len < 3 { eprintln('usage: account-contract-run prepare ROOT BUILD [FIXTURE_APK] | prepare-response|prepare-intent|prepare-request|prepare-base ROOT BUILD FIXTURE_APK | prepare-activity ROOT BUILD CLIENT_APK COMPANION_APK DISABLED_APK | prepare-service ROOT BUILD CLIENT_APK COMPANION_APK BLOCKED_APK DISABLED_APK | start|stop|status|observe ROOT\nOptional preparation scratch: VINIX_ACCOUNT_CONTRACT_SCRATCH=/fresh/absolute/path (default ROOT/scratch; failed composition retained)'); exit(2) }
	root := os.abs_path(os.args[2])
	match os.args[1] {
		'prepare' { if os.args.len !in [4, 5] { exit(2) }; prepare(root, os.abs_path(os.args[3]), if os.args.len == 5 { os.abs_path(os.args[4]) } else { '' }, if os.args.len == 5 { 'fixture' } else { 'maps' }, []string{}) or { eprintln(err); exit(1) } }
		'prepare-response' { if os.args.len != 5 { exit(2) }; prepare(root, os.abs_path(os.args[3]), os.abs_path(os.args[4]), 'response-fixture', []string{}) or { eprintln(err); exit(1) } }
		'prepare-intent' { if os.args.len != 5 { exit(2) }; prepare(root, os.abs_path(os.args[3]), os.abs_path(os.args[4]), 'intent-parcel-fixture', []string{}) or { eprintln(err); exit(1) } }
		'prepare-request' { if os.args.len != 5 { exit(2) }; prepare(root, os.abs_path(os.args[3]), os.abs_path(os.args[4]), 'authenticator-request-fixture', []string{}) or { eprintln(err); exit(1) } }
		'prepare-base' { if os.args.len != 5 { exit(2) }; prepare(root, os.abs_path(os.args[3]), os.abs_path(os.args[4]), 'authenticator-base-fixture', []string{}) or { eprintln(err); exit(1) } }
		'prepare-activity' { if os.args.len != 7 { exit(2) }; prepare(root, os.abs_path(os.args[3]), os.abs_path(os.args[4]), 'companion-activity-fixture', [os.abs_path(os.args[5]), os.abs_path(os.args[6])]) or { eprintln(err); exit(1) } }
		'prepare-service' { if os.args.len != 8 { exit(2) }; prepare(root, os.abs_path(os.args[3]), os.abs_path(os.args[4]), 'service-access-fixture', [os.abs_path(os.args[5]), os.abs_path(os.args[6]), os.abs_path(os.args[7])]) or { eprintln(err); exit(1) } }
		'start' { start(root) or { eprintln(err); exit(1) } }
		'stop' { stop(root) or { eprintln(err); exit(1) } }
		'status' { println(json2.encode(owned(root) or { eprintln(err); exit(1) })) }
		'observe' { observe(root) or { eprintln(err); exit(1) } }
		else { exit(2) }
	}
}
