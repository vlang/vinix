// SPDX-License-Identifier: GPL-2.0-or-later
// Append protected real Google APKs and account runtime without booting media.
module main

import crypto.sha256
import json2
import mapsaccountstage as stage
import os
import v.embed_file

#include <sys/clonefile.h>
fn C.clonefile(&char, &char, int) int

const overlay = 'maps-account.tar'
const prefix = 'opt/vinix-maps-account'
const runtime = 'opt/vinix-android-aarch64'
const base_boot = '08b0a9c6d0eaf109a5027eac802cb5add897e7612aac85528a08fdba794b3f5e'
const base_receipt = '7448a177792eaba0a5555dd35ada0efefd790afd4b863def3647362c23c65559'
const maps_apk = '6218d72f48b184eb71f68879bce48cb9ebb2b510be7f7cff88217ea3fd592bb2'
const gms_apk = 'a34d6a3ccea3ceba491369517e8f12e11df3791e86fec38b1cdf693785e35707'
const ui_receipt = 'a7c8a08157f32595491863bf6bb2a86c370a79bb644d6bc681194547f60b0ecb'
const ui_seal = 'f5def88d6933a888f81b8a816788dbd28c38ca89523cc8417d074bfd1d1a624b'
const ui_guest = '253c6daefdd308c9dc8c7f597c5615b659e5323aeccd2e15f51aa98e9e6f0056'
const ui_controller = '3dcfb85051079e8205d4a71334e432241a72e9950b25551ea8e69ece70c909d4'
const ui_helper = 'eff0ee8da211772f2549a5b39fdb2739cbb746db44e859bc25bd56b854fbd989'
const signer_pin = '00ef9948f843fe395d2440ae3ef41405b8040a6d5d46493bd1902ac0ee6deae7'
const retained = {
	'tests/native-android-ws/maps-account-stage.v': carry($embed_file(@FILE))
	'tests/native-android-ws/mapsaccountstage/bundle.v': carry($embed_file("mapsaccountstage/bundle.v"))
	'tests/native-android-ws/mapsaccountstage/elf.v': carry($embed_file("mapsaccountstage/elf.v"))
	'tests/native-android-ws/mapsaccountstage/media.v': carry($embed_file("mapsaccountstage/media.v"))
	'tests/native-android-ws/mapsaccountstage/headless.v': carry($embed_file("mapsaccountstage/headless.v"))
	'build-support/android/modulestream/stream.v': carry($embed_file("../../build-support/android/modulestream/stream.v"))
	'build-support/android/modulestream/spawn_abi.h': carry($embed_file("../../build-support/android/modulestream/spawn_abi.h"))
	'build-support/tarcore/writer.v': carry($embed_file("../../build-support/tarcore/writer.v"))
	'build-support/tarcore/gzip.v': carry($embed_file("../../build-support/tarcore/gzip.v"))
	'build-support/tarstream/reader.v': carry($embed_file("../../build-support/tarstream/reader.v"))
	'build-support/tarstream/filter_abi.h': carry($embed_file("../../build-support/tarstream/filter_abi.h"))
	'build-support/tarstream/sparse.v': carry($embed_file("../../build-support/tarstream/sparse.v"))
}

struct Ref {
	root string
	seal string
}
struct ReplayMetadata {
	mode u32
	size u64
}
struct Request {
	kind string
	base string
	framework Ref
	framework_jar string
	framework_dex string
	native Ref
	account Ref
	launch Ref
	guest Ref
	browser Ref
	ui string
	token Ref
	token_apk string
	token_controller Ref
	java string
	signer string
}

fn carry(data embed_file.EmbedFileData) string {
	if data.str().all_after('uncompressed: ').trim_right(' }') == '0' {
		panic('maps-account-stage requires -prod embedded sources')
	}
	return data.to_string()
}
fn write_json(path string, value json2.Any) ! { os.write_file(path, json2.encode(value, prettify: true) + '\n')! }
fn as_json[T](value T) !json2.Any { return json2.decode[json2.Any](json2.encode(value)) }
fn copy_file(source string, destination string, mode u32) ! {
	if os.lstat(source)!.get_filetype() != .regular { return error('regular source required: ' + source) }
	os.mkdir_all(os.dir(destination), mode: 0o755)!
	if os.exists(destination) || os.is_link(destination) { return error('duplicate payload: ' + destination) }
	os.cp(source, destination)!
	os.chmod(destination, int(mode))!
}
fn payload_inventory(root string) ![]stage.Entry {
	mut entries := []stage.Entry{}
	mut names := os.ls(root)!
	names.sort()
	for name in names { stage.inventory(root + '/' + name, '', name, mut entries)! }
	return entries
}
// Homebrew dispatches the same mtools binary through symlinks. Retain regular
// named copies so argv[0] selects the tool while every executed inode is pinned.
fn prepare_mtools(root string) !map[string]string {
	os.mkdir(root + '/tools', mode: 0o755)!
	mut pins := map[string]string{}
	for name in ['mcopy', 'mtype', 'mdir'] {
		source := os.real_path(os.find_abs_path_of_executable(name)!)
		pin := stage.hash(source)!
		destination := root + '/tools/' + name
		copy_file(source, destination, 0o755)!
		if stage.hash(destination)! != pin || stage.hash(source)! != pin { return error('mtools copy differs') }
		pins[source] = pin
		pins[destination] = pin
	}
	write_json(root + '/mtools-inputs.json', as_json(pins)!)!
	os.setenv('PATH', root + '/tools:' + os.getenv('PATH'), true)
	return pins
}
fn safe_identity(passwd string, group string) ! {
	for text in [passwd, group] {
		if text == '' || !text.ends_with('\n') || text.contains_any('\x00\r') { return error('invalid account database') }
		for line in text.split_into_lines() {
			fields := line.split(':')
			if fields.len < 3 { return error('invalid account database row') }
			if fields[0] in ['vinixmaps', 'vinixgms', 'vinix-maps-account', 'vinix-gms-account', 'vinix-token-cache'] || fields[2] in ['10012', '10013', '10014']
				|| (fields.len == 7 && fields[3] in ['10012', '10013', '10014']) { return error('Maps/GMS/token fixture identity already allocated') }
		}
	}
}
// Tar overwrites retain inode modes. Check every occurrence and each ancestor.
fn safe_destinations(original []stage.Entry, planned []stage.Entry) ! {
	mut destinations := map[string]stage.Entry{}
	for entry in planned {
		if entry.name in destinations || !stage.relative(entry.name) || entry.kind !in ['regular', 'directory']
			|| entry.mode & 0o7022 != 0 { return error('unsafe or duplicate overlay destination') }
		destinations[entry.name] = entry
	}
	for old in original {
		for name, target in destinations {
			if old.name == name {
				if old.kind != target.kind || old.mode != target.mode { return error('existing destination kind/mode differs: ' + name) }
			} else if name.starts_with(old.name + '/') && (old.kind != 'directory' || old.mode & 0o7022 != 0) {
				return error('unprotected or aliased overlay ancestor: ' + old.name)
			}
		}
	}
}
// The kernel replaces existing regular contents without changing inode modes.
// Match those audited modes in the tar; the guest removes write bits only after
// validating every protected input and records the resulting inode identities.
fn inherited_modes(original []stage.Entry, planned []stage.Entry) !map[string]u32 {
	mut result := map[string]u32{}
	for target in planned {
		for old in original.filter(it.name == target.name) {
			if old.kind != target.kind || old.kind !in ['regular', 'directory']
				|| old.mode & 0o7022 != 0 || target.mode & 0o7022 != 0
				|| (old.mode & ~u32(0o222)) != (target.mode & ~u32(0o222))
				|| (old.kind == 'directory' && old.mode != target.mode) {
				return error('unsafe inherited overlay mode: ' + target.name)
			}
			if previous := result[target.name] {
				if previous != old.mode { return error('inconsistent original overlay modes: ' + target.name) }
			}
			result[target.name] = old.mode
		}
	}
	return result
}
fn signature(root string, java string, signer string, label string, apk string) !string {
	text := stage.command(root, 'verify-' + label + '-sdk29', [java, '-jar', signer, 'verify',
		'--min-sdk-version', '29', '--max-sdk-version', '29', '--verbose', '--print-certs', apk])!
	pins := text.split_into_lines().filter(it.starts_with('Signer #1 certificate SHA-256 digest: '))
	if pins.len != 1 || text.contains('Signer #2 ') { return error('exactly one SDK29 APK signer required') }
	pin := pins[0].all_after(': ').trim_space()
	if !stage.valid_pin(pin) { return error('APK signer pin absent') }
	return pin
}
fn complete_files(root string, relative string, mut files map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		path := if relative == '' { name } else { relative + '/' + name }
		if os.is_dir(root + '/' + path) && !os.is_link(root + '/' + path) { complete_files(root, path, mut files)! }
		else if path != 'sha256.json' { files[path] = stage.hash(root + '/' + path)! }
	}
}
fn seal(root string) ! {
	mut files := map[string]string{}
	complete_files(root, '', mut files)!
	write_json(root + '/sha256.json', as_json(files)!)!
}

// A prior guest run changes firmware and adds run evidence to a stage directory.
// Replay only the original complete sealed UI bundle, replacing firmware from
// its exact unbooted source. Preserve the old directory and its failed check.
fn replay_ui(source string, base string, output string) ! {
	root := stage.external(output)!
	stage.disjoint(root, [source, base])!
	if stage.hash(source + '/stage.json')! != ui_receipt || stage.hash(source + '/sha256.json')! != ui_seal
		|| stage.hash(base + '/stage.json')! != base_receipt || stage.hash(base + '/boot.img')! != base_boot {
		return error('UI replay requires exact original UI and unbooted baseline pins')
	}
	pins := json2.decode[map[string]string](os.read_file(source + '/sha256.json')!)!
	if pins['stage.json']! != ui_receipt || pins['efivars.fd']! != stage.hash(base + '/efivars.fd')! {
		return error('UI original firmware does not match unbooted source')
	}
	mut metadata := map[string]ReplayMetadata{}
	// Complete preflight precedes creation of the fresh output.
	for name, pin in pins {
		if !stage.relative_file(name) || !stage.valid_pin(pin) { return error('unsafe original UI manifest entry') }
		selected := if name == 'efivars.fd' { base + '/' + name } else { source + '/' + name }
		st := os.lstat(selected)!
		if st.get_filetype() != .regular || st.mode & 0o7022 != 0 || stage.hash(selected)! != pin {
			return error('original UI source differs: ' + name)
		}
		metadata[name] = ReplayMetadata{mode: st.mode & 0o777, size: st.size}
		mut ancestor := os.dir(selected)
		for ancestor != source && ancestor != base {
			if os.lstat(ancestor)!.get_filetype() != .directory { return error('aliased UI source ancestor') }
			ancestor = os.dir(ancestor)
		}
	}
	os.mkdir(root, mode: 0o700)!
	for name, pin in pins {
		selected := if name == 'efivars.fd' { base + '/' + name } else { source + '/' + name }
		before := os.lstat(selected)!
		if before.get_filetype() != .regular || before.mode & 0o777 != metadata[name]!.mode || before.size != metadata[name]!.size {
			return error('UI replay source metadata changed')
		}
		if name in ['boot.img', 'efivars.fd'] {
			if C.clonefile(selected.str, (root + '/' + name).str, 0) != 0 { return error('UI media replay clone failed') }
		} else { copy_file(selected, root + '/' + name, os.lstat(selected)!.mode & 0o777)! }
		after := os.lstat(root + '/' + name)!
		if after.get_filetype() != .regular || after.mode & 0o777 != metadata[name]!.mode || after.size != metadata[name]!.size
			|| stage.hash(root + '/' + name)! != pin || stage.hash(selected)! != pin { return error('UI replay differs') }
	}
	copy_file(source + '/sha256.json', root + '/sha256.json', 0o644)!
	if stage.load_inventory(root, ui_seal)! != pins { return error('complete UI replay differs') }
	write_json(root + '-replay.json', {
		'kind': json2.Any('vinix-account-ui-exact-replay-v1'), 'original_source': json2.Any(source),
		'unbooted_base': json2.Any(base), 'output': json2.Any(root), 'manifest_sha256': json2.Any(ui_seal),
		'firmware_source_sha256': json2.Any(pins['efivars.fd']!), 'scope': json2.Any('all original manifest files verified; prior run evidence preserved at source; no guest execution claim'),
		'stage_tool_sha256': json2.Any(stage.hash(os.executable())!),
		'verified_file_metadata': as_json(metadata)!,
	})!
	println('MAPS-UI-REPLAY PASS ' + root)
}

fn audit_base(base string, java string, signer string, output string) ! {
	root := stage.external(output)!
	stage.disjoint(root, [base, java, signer])!
	if stage.hash(base + '/stage.json')! != base_receipt || stage.hash(base + '/boot.img')! != base_boot
		|| stage.hash(signer)! != signer_pin { return error('baseline or signer differs') }
	receipt := json2.decode[map[string]json2.Any](os.read_file(base + '/stage.json')!)!
	mut expected := json2.decode[map[string]string](json2.encode(receipt['preserved_modules_sha256']!))!
	expected['headless-service.tar'] = stage.text_field(receipt, 'overlay_sha256')!
	os.mkdir(root, mode: 0o700)!
	os.mkdir(root + '/commands', mode: 0o755)!
	copy_file(os.executable(), root + '/stage', 0o755)!
	copy_file(base + '/stage.json', root + '/base-stage.json', 0o644)!
	tools := prepare_mtools(root)!
	mcopy, mtype := root + '/tools/mcopy', root + '/tools/mtype'
	config := stage.configure(stage.command(root, 'read-limine', [mtype, '-i', base + '/boot.img', '::/boot/limine.conf'])!, overlay)!
	mut entries := []stage.Entry{}
	for name in config.modules {
		if stage.module_hash(root, name, base + '/boot.img', name)! != expected[name]! { return error('base module differs') }
		paths := match name {
			'initramfs.tar' { ['etc/passwd', 'etc/group'] }
			'qemu-runtime.tar' { ['opt/android-test/application.apk', 'tmp/maps256-data/_installed_apks_/com.google.android.gms.apk'] }
			else { []string{} }
		}
		entries << stage.scan_module(mcopy, base + '/boot.img', name, if paths.len == 0 { '' } else { root + '/extract-' + name }, paths)!
	}
	safe_identity(os.read_file(root + '/extract-initramfs.tar/etc/passwd')!, os.read_file(root + '/extract-initramfs.tar/etc/group')!)!
	mut signers := map[string]string{}
	for pair in [['maps', 'opt/android-test/application.apk', maps_apk], ['gms', 'tmp/maps256-data/_installed_apks_/com.google.android.gms.apk', gms_apk]] {
		path := root + '/extract-qemu-runtime.tar/' + pair[1]
		if stage.hash(path)! != pair[2] { return error('real APK differs') }
		signers[pair[0]] = signature(root, java, signer, pair[0], path)!
	}
	if stage.hash(base + '/boot.img')! != base_boot { return error('baseline changed during audit') }
	for path, pin in tools { if stage.hash(path)! != pin { return error('audit tool changed') } }
	write_json(root + '/inventory.json', as_json(entries)!)!
	write_json(root + '/build.json', {
		'kind': json2.Any('vinix-maps-account-base-audit-v1'), 'base': json2.Any(base), 'boot_sha256': json2.Any(base_boot),
		'stage_tool_sha256': json2.Any(stage.hash(os.executable())!), 'java_sha256': json2.Any(stage.hash(java)!),
		'signer_sha256': json2.Any(signer_pin), 'sdk29_apk_signers': as_json(signers)!,
		'uid_gid_10012_10013_10014_unused': json2.Any(true), 'scope': json2.Any('unchanged original media and real APK signature preflight; no guest execution claim'),
	})!
	seal(root)!
	println('MAPS-BASE-AUDIT PASS ' + root)
}

fn run(request_path string, pin string, output string) ! {
	$if !macos { return error('staging requires macOS clonefile') }
	if request_path != os.real_path(request_path) || !stage.valid_pin(pin)
		|| stage.hash(request_path)! != pin { return error('canonical pinned request required') }
	request := json2.decode[Request](os.read_file(request_path)!)!
	if request.kind != 'vinix-maps-account-stage-request-v1' { return error('unsupported stage request') }
	root := stage.external(output)!
	refs := [request.framework, request.native, request.account, request.launch, request.guest, request.browser, request.token, request.token_controller]
	mut roots := [request_path, request.base, request.ui, request.java, request.signer]
	for ref in refs { roots << ref.root }
	stage.disjoint(root, roots)!
	if stage.hash(request.base + '/stage.json')! != base_receipt || stage.hash(request.base + '/boot.img')! != base_boot
		|| stage.hash(request.ui + '/stage.json')! != ui_receipt || stage.hash(request.signer)! != signer_pin {
		return error('audited baseline/UI/signer pin differs')
	}
	base := json2.decode[map[string]json2.Any](os.read_file(request.base + '/stage.json')!)!
	if stage.hash(request.base + '/efivars.fd')! != stage.text_field(base, 'staged_efivars_sha256')! { return error('baseline firmware differs') }
	framework := stage.load_bundle(request.framework.root, request.framework.seal)!
	stage.verify_framework(framework, request.framework.seal, request.framework_jar, request.framework_dex)!
	native := stage.load_bundle(request.native.root, request.native.seal)!
	stage.verify_native(native, framework)!
	account := stage.load_bundle(request.account.root, request.account.seal)!
	stage.verify_account(account)!
	launch := stage.load_bundle(request.launch.root, request.launch.seal)!
	stage.verify_launch(launch, framework, native)!
	guest := stage.load_bundle(request.guest.root, request.guest.seal)!
	stage.verify_static_controller(guest, 'vinix-maps-account-guest-build-v1', 'maps-account-guest')!
	browser := stage.load_bundle(request.browser.root, request.browser.seal)!
	token := stage.load_bundle(request.token.root, request.token.seal)!
	token_controller := stage.load_bundle(request.token_controller.root, request.token_controller.seal)!
	if !stage.valid_pin(request.token_apk) || token.files['probe.apk'] or { '' } != request.token_apk { return error('audited token fixture differs') }
	ui_files := stage.load_inventory(request.ui, ui_seal)!
	for name, expected in {'account-ui-guest': ui_guest, 'account-ui-controller': ui_controller, 'vinix-android-account-ui': ui_helper} {
		if ui_files['payload/bin/' + name] or { '' } != expected { return error('pinned UI fixture differs') }
	}
	stage.verify_static_controller(token_controller, 'vinix-account-token-cache-controller-v1', 'account-token-cache-controller')!
	os.mkdir(root, mode: 0o700)!
	for dir in ['commands', 'sources', 'payload', 'inputs'] { os.mkdir(root + '/' + dir, mode: 0o755)! }
	tools := prepare_mtools(root)!
	mcopy, mtype, mdir := root + '/tools/mcopy', root + '/tools/mtype', root + '/tools/mdir'
	for name, text in retained {
		os.mkdir_all(os.dir(root + '/sources/' + name))!
		os.write_file(root + '/sources/' + name, text)!
	}
	copy_file(os.executable(), root + '/stage', 0o755)!
	copy_file(request_path, root + '/request.json', 0o644)!
	copy_file(request.base + '/stage.json', root + '/base-stage.json', 0o644)!
	mut inputs := map[string]string{}
	for path, tool_pin in tools { inputs[path] = tool_pin }
	for path in [request_path, request.base + '/stage.json', request.base + '/boot.img', request.base + '/efivars.fd',
		request.ui + '/stage.json', request.ui + '/sha256.json', request.java, request.signer, mcopy, mtype, mdir, os.executable()] {
		inputs[path] = stage.hash(path)!
	}
	for index, bundle in [framework, native, account, launch, guest, browser, token, token_controller] {
		copy_file(bundle.root + '/sha256.json', root + '/inputs/' + index.str() + '-sha256.json', 0o644)!
		copy_file(bundle.root + '/build.json', root + '/inputs/' + index.str() + '-build.json', 0o644)!
		inputs[bundle.root + '/sha256.json'] = bundle.seal
	}
	boot := request.base + '/boot.img'
	original := stage.command(root, 'read-limine', [mtype, '-i', boot, '::/boot/limine.conf'])!
	if sha256.sum(original.bytes()).hex() != stage.text_field(base, 'limine_after_sha256')! { return error('base configuration differs') }
	config := stage.configure(original, overlay)!
	if config.modules != ['initramfs.tar', 'qemu-runtime.tar', 'maps335-diagnostics.tar', 'maps350-diagnostics.tar', 'maps372-diagnostics.tar', 'headless-service.tar'] {
		return error('baseline module order differs')
	}
	mut expected := json2.decode[map[string]string](json2.encode(base['preserved_modules_sha256']!))!
	expected['headless-service.tar'] = stage.text_field(base, 'overlay_sha256')!
	base_inventory := json2.decode[[]stage.Entry](json2.encode(base['overlay_inventory']!))!
	mut all := []stage.Entry{}
	mut before := map[string]string{}
	for name in config.modules {
		before[name] = stage.module_hash(root, 'original-' + name, boot, name)!
		if before[name] != expected[name] or { '' } { return error('original module differs: ' + name) }
		paths := match name {
			'initramfs.tar' { ['etc/passwd', 'etc/group'] }
			'qemu-runtime.tar' { ['opt/android-test/application.apk', 'tmp/maps256-data/_installed_apks_/com.google.android.gms.apk'] }
			'headless-service.tar' { base_inventory.filter(it.kind == 'regular' && it.name.starts_with('opt/vinix-headless-service/')).map(it.name) }
			else { []string{} }
		}
		entries := stage.scan_module(mcopy, boot, name, if paths.len == 0 { '' } else { root + '/extract-' + name }, paths)!
		if name == 'headless-service.tar' && entries != base_inventory { return error('original headless inventory differs') }
		all << entries
	}
	write_json(root + '/original-module-inventory.json', as_json(all)!)!
	init := root + '/extract-initramfs.tar/'
	safe_identity(os.read_file(init + 'etc/passwd')!, os.read_file(init + 'etc/group')!)!
	copy_file(init + 'etc/passwd', root + '/original-passwd', 0o644)!
	copy_file(init + 'etc/group', root + '/original-group', 0o644)!
	for entry in all.filter(it.name in ['etc/passwd', 'etc/group']) {
		if entry.kind != 'regular' || entry.sha256 != stage.hash(init + entry.name)! { return error('account database overridden by another module') }
	}
	os.mkdir(root + '/payload/etc', mode: 0o755)!
	os.write_file(root + '/payload/etc/passwd', os.read_file(init + 'etc/passwd')! + 'vinix-token-cache:x:10014:10014:Token cache fixture:/var/lib/vinix/apps/10014/home:/bin/sh\n')!
	os.write_file(root + '/payload/etc/group', os.read_file(init + 'etc/group')! + 'vinix-token-cache:x:10014:\n')!
	for pair in [['opt/android-test/application.apk', 'maps.apk', maps_apk], ['tmp/maps256-data/_installed_apks_/com.google.android.gms.apk', 'gms.apk', gms_apk]] {
		path := root + '/extract-qemu-runtime.tar/' + pair[0]
		if stage.hash(path)! != pair[2] { return error('real Google APK pin differs') }
		copy_file(path, root + '/payload/' + prefix + '/apks/' + pair[1], 0o644)!
	}
	maps_signer := signature(root, request.java, request.signer, 'maps', root + '/payload/' + prefix + '/apks/maps.apk')!
	gms_signer := signature(root, request.java, request.signer, 'gms', root + '/payload/' + prefix + '/apks/gms.apk')!
	registry := 'vinix-android-account-authority-v1\ncom.google.android.apps.maps\t10012\t10012\t/' + prefix + '/apks/maps.apk\t' + maps_apk + '\t' + maps_signer + '\t-\n' +
		'com.google.android.gms\t10013\t10013\t/' + prefix + '/apks/gms.apk\t' + gms_apk + '\t' + gms_signer + '\tcom.google.android.gms.auth.account.authenticator.GoogleAccountAuthenticatorService@android.accounts.AccountAuthenticator@com.google\n'
	os.write_file(root + '/payload/' + prefix + '/identity.registry', registry)!
	mut copies := map[string]string{}
	copies[runtime + '/usr/lib/java/dex/android_translation_layer/api-impl.jar'] = framework.root + '/api-impl.jar'
	copies[runtime + '/usr/lib/java/dex/android_translation_layer/classes.dex'] = framework.root + '/classes.dex'
	copies[runtime + '/usr/lib/art/libvinix-android-native.so'] = native.root + '/native/libvinix-android-native.so'
	for name in ['libvinix-android-account.so', 'libsqlite3.so.0'] { copies[runtime + '/usr/lib/' + name] = account.root + '/lib/' + name }
	for name in ['run-android', 'vinix-android-native', 'native-account-broker'] { copies[runtime + '/usr/bin/' + name] = launch.root + '/bin/' + name }
	copies['usr/bin/run-android'] = launch.root + '/bin/run-android'
	copies['usr/bin/run-android-calculator'] = guest.root + '/bin/maps-account-guest'
	copies[prefix + '/bin/maps-account-guest'] = guest.root + '/bin/maps-account-guest'
	copies[prefix + '/bin/account-token-cache-controller'] = token_controller.root + '/bin/account-token-cache-controller'
	copies[runtime + '/usr/bin/vinix-android-account-ui'] = request.ui + '/payload/bin/vinix-android-account-ui'
	for name, source in copies { copy_file(source, root + '/payload/' + name, if name.contains('/bin/') { u32(0o755) } else { u32(0o644) })! }
	for name in ['account-ui-guest', 'account-ui-controller', 'vinix-android-account-ui'] {
		copy_file(request.ui + '/payload/bin/' + name, root + '/payload/opt/vinix-account-ui/bin/' + name, 0o755)!
	}
	copy_file(request.ui + '/payload/guest-inputs.json', root + '/payload/opt/vinix-account-ui/guest-inputs.json', 0o644)!
	copy_file(token.root + '/probe.apk', root + '/payload/' + prefix + '/account-token-fixture.apk', 0o644)!
	finish(root, request, [framework, native, account, launch, guest, browser, token, token_controller], all, before, inputs, config.updated, original, ui_files, maps_signer, gms_signer, pin)!
}

fn finish(root string, request Request, bundles []stage.Bundle, original_entries []stage.Entry,
	before map[string]string, inputs map[string]string, updated string, original string,
	ui_files map[string]string, maps_signer string, gms_signer string, request_pin string) ! {
	framework, native, launch, browser := bundles[0], bundles[1], bundles[3], bundles[5]
	browser_entries := payload_inventory(browser.root + '/payload')!
	for entry in browser_entries {
		if entry.name == '' { continue }
		if !entry.name.starts_with('opt/vinix-google-browser/') && entry.name !in ['opt/vinix-google-browser', 'opt', 'lib', 'usr', 'usr/bin', 'usr/libexec', 'usr/libexec/webkitgtk-6.0',
			'etc', 'etc/ssl', 'etc/ssl/certs', 'etc/ssl/certs/ca-certificates.crt',
			'lib/ld-musl-aarch64.so.1', 'usr/bin/xkbcomp', 'usr/bin/bwrap',
			'usr/libexec/webkitgtk-6.0/WebKitWebProcess', 'usr/libexec/webkitgtk-6.0/WebKitNetworkProcess', 'usr/libexec/webkitgtk-6.0/WebKitGPUProcess'] {
			return error('browser payload escapes allowlist: ' + entry.name)
		}
		if entry.kind == 'directory' { os.mkdir_all(root + '/payload/' + entry.name, mode: 0o755)! }
		else if entry.kind == 'regular' { copy_file(browser.root + '/payload/' + entry.name, root + '/payload/' + entry.name, entry.mode)! }
		else { return error('browser payload must use regular files/directories') }
	}
	mut browser_manifests := map[string]json2.Any{}
	for pair in [['10012', 'maps'], ['10013', 'gms']] {
		destination := prefix + '/browser/' + pair[1] + '.manifest'
		copy_file(browser.root + '/manifests/' + pair[1] + '.manifest', root + '/payload/' + destination, 0o644)!
		browser_manifests[pair[0]] = as_json({'path': '/' + destination, 'sha256': stage.hash(root + '/payload/' + destination)!})!
	}
	headless := root + '/extract-headless-service.tar/opt/vinix-headless-service'
	copy_file(headless + '/guest-inputs.json', root + '/original-headless-inputs.json', 0o644)!
	mut replacement := map[string]string{}
	for name in [runtime + '/usr/bin/run-android', runtime + '/usr/bin/vinix-android-native',
		runtime + '/usr/lib/art/libvinix-android-native.so', runtime + '/usr/lib/java/dex/android_translation_layer/api-impl.jar'] {
		replacement['/' + name] = stage.hash(root + '/payload/' + name)!
	}
	replacement['/opt/vinix-headless-service/bin/headless-service-controller'] = launch.files['bin/headless-service-controller']!
	copy_file(launch.root + '/bin/headless-service-controller', root + '/payload/opt/vinix-headless-service/bin/headless-service-controller', 0o755)!
	os.write_file(root + '/payload/opt/vinix-headless-service/guest-inputs.json',
		stage.repin_headless_inputs(os.read_file(headless + '/guest-inputs.json')!, replacement)!)!
	for pair in [[native.root + '/build.json', 'native-build.json'], [native.root + '/sha256.json', 'native-sha256.json'],
		[framework.root + '/build.json', 'framework-build.json'], [framework.root + '/sha256.json', 'framework-sha256.json']] {
		copy_file(pair[0], root + '/payload/opt/vinix-headless-service/' + pair[1], 0o644)!
	}
	mut deployment_pins := map[string]string{}
	mut entries := payload_inventory(root + '/payload')!
	for entry in entries.filter(it.kind == 'regular') { deployment_pins['/' + entry.name] = entry.sha256 }
	deployment_pins['/opt/vinix-headless-service/bin/headless-service-guest'] = stage.headless_guest_sha256
	deployment_pins['/opt/vinix-headless-service/fixture.apk'] = stage.headless_fixture_sha256
	write_json(root + '/payload/' + prefix + '/build.json', {
		'kind': json2.Any('vinix-maps-account-deployment-v1'), 'format': json2.Any(1),
		'runtime_root': json2.Any('/' + runtime), 'maps_uid': json2.Any(10012), 'gms_uid': json2.Any(10013),
		'inputs_sha256': as_json(deployment_pins)!, 'browser_manifests': json2.Any(browser_manifests),
		'framework_manifest_sha256': json2.Any(framework.seal), 'native_manifest_sha256': json2.Any(native.seal),
		'account_manifest_sha256': json2.Any(bundles[2].seal), 'launch_manifest_sha256': json2.Any(launch.seal),
		'browser_manifest_sha256': json2.Any(browser.seal), 'maps_signer_sdk29_sha256': json2.Any(maps_signer),
		'token_controller_manifest_sha256': json2.Any(bundles[7].seal),
		'gms_signer_sdk29_sha256': json2.Any(gms_signer),
	})!
	entries = payload_inventory(root + '/payload')!
	modes := inherited_modes(original_entries, entries)!
	mut mode_changes := map[string]json2.Any{}
	for entry in entries {
		if inherited := modes[entry.name] {
			if inherited != entry.mode {
				mode_changes[entry.name] = as_json({'original_inode_mode': inherited, 'requested_readonly_mode': entry.mode})!
				os.chmod(root + '/payload/' + entry.name, int(inherited))!
			}
		}
	}
	write_json(root + '/inherited-overlay-modes.json', json2.Any(mode_changes))!
	entries = payload_inventory(root + '/payload')!
	safe_destinations(original_entries, entries)!
	mut sources := map[string]string{}
	for entry in entries.filter(it.kind == 'regular') { sources[entry.name] = root + '/payload/' + entry.name }
	write_json(root + '/overlay-plan.json', as_json(entries)!)!
	mcopy, mtype, mdir := root + '/tools/mcopy', root + '/tools/mtype', root + '/tools/mdir'
	boot := request.base + '/boot.img'
	stage.command_expected(root, 'overlay-absent', [mdir, '-i', boot, '::/boot/' + overlay], 1)!
	os.write_file(root + '/limine-before.conf', original)!
	os.write_file(root + '/limine-after.conf', updated)!
	for pair in [[boot, root + '/boot.img'], [request.base + '/efivars.fd', root + '/efivars.fd']] {
		if C.clonefile(pair[0].str, pair[1].str, 0) != 0 || stage.hash(pair[0])! != stage.hash(pair[1])! { return error('media clone failed or differs') }
	}
	stage.write_overlay(root + '/' + overlay, sources, entries)!
	stage.verify_overlay(root + '/' + overlay, entries)!
	stage.command(root, 'install-overlay', [mcopy, '-i', root + '/boot.img', root + '/' + overlay, '::/boot/' + overlay])!
	stage.command(root, 'install-limine', [mcopy, '-o', '-i', root + '/boot.img', root + '/limine-after.conf', '::/boot/limine.conf'])!
	if stage.command(root, 'readback-limine', [mtype, '-i', root + '/boot.img', '::/boot/limine.conf'])! != updated { return error('configuration readback differs') }
	if stage.module_hash(root, 'readback-overlay', root + '/boot.img', overlay)! != stage.hash(root + '/' + overlay)! { return error('overlay readback differs') }
	mut after := map[string]string{}
	for name, pin in before {
		after[name] = stage.module_hash(root, 'preserved-' + name, root + '/boot.img', name)!
		if after[name] != pin { return error('original module changed') }
	}
	for bundle in bundles { stage.recheck(bundle)! }
	if stage.load_inventory(request.ui, ui_seal)! != ui_files { return error('UI source changed') }
	for path, pin in inputs { if stage.hash(path)! != pin { return error('input changed: ' + path) } }
	final_entries := payload_inventory(root + '/payload')!
	if final_entries != entries { return error('payload changed during staging') }
	write_json(root + '/stage.json', {
		'format': json2.Any(1), 'scope': json2.Any('protected real Maps/GMS account and browser deployment; staging supplies no login or ART execution claim'),
		'base_stage_receipt_sha256': json2.Any(base_receipt), 'request_sha256': json2.Any(request_pin),
		'inputs_sha256': as_json(inputs)!, 'original_modules_sha256': as_json(before)!, 'preserved_modules_sha256': as_json(after)!,
		'overlay_inventory': as_json(entries)!, 'overlay_sha256': json2.Any(stage.hash(root + '/' + overlay)!),
		'limine_before_sha256': json2.Any(sha256.sum(original.bytes()).hex()), 'limine_after_sha256': json2.Any(sha256.sum(updated.bytes()).hex()),
		'staged_boot_sha256': json2.Any(stage.hash(root + '/boot.img')!), 'staged_efivars_sha256': json2.Any(stage.hash(root + '/efivars.fd')!),
		'guest_terminal_command': json2.Any('/' + prefix + '/bin/maps-account-guest --broker'),
		'guest_results': json2.Any('/' + prefix + '/results'), 'maps_launcher': json2.Any('/usr/bin/run-android-calculator'),
		'additional_fixtures': json2.Any(['/opt/vinix-headless-service/bin/headless-service-guest', '/opt/vinix-account-ui/bin/account-ui-guest'].map(json2.Any(it))),
	})!
	seal(root)!
	println('MAPS-ACCOUNT-STAGE PASS ' + root + '/stage.json')
}

fn self_test() ! {
	stage.self_test()!
	for p in ['root:x:0:0:root:/root:/bin/sh\nvinixmaps:x:4:4:x:/x:/bin/sh\n', 'root:x:0:0:root:/root:/bin/sh\nu:x:10012:7:x:/x:/bin/sh\n',
		'vinix-gms-account:x:7:7:x:/x:/bin/sh\n', 'u:x:10014:10014:x:/x:/bin/sh\n'] {
		if _ := safe_identity(p, 'root:x:0:\n') { return error('allocated account accepted') }
	}
	safe_identity('root:x:0:0:root:/root:/bin/sh\n', 'root:x:0:\n')!
	plan := [stage.Entry{name: 'opt/a/b', kind: 'regular', mode: 0o644}]
	for bad in [stage.Entry{name: 'opt', kind: 'symlink', mode: 0o755}, stage.Entry{name: 'opt/a', kind: 'directory', mode: 0o777}, stage.Entry{name: 'opt/a/b', kind: 'regular', mode: 0o755}] {
		if _ := safe_destinations([bad], plan) { return error('unsafe tar overwrite accepted') }
	}
	safe_destinations([stage.Entry{name: 'opt', kind: 'directory', mode: 0o755}], plan)!
	readonly := [stage.Entry{name: 'lib/loader', kind: 'regular', mode: 0o555}]
	inherited := inherited_modes([stage.Entry{name: 'lib/loader', kind: 'regular', mode: 0o755}], readonly)!
	if inherited['lib/loader']! != 0o755 { return error('existing inode mode not retained') }
	for bad in [stage.Entry{name: 'lib/loader', kind: 'symlink', mode: 0o777},
		stage.Entry{name: 'lib/loader', kind: 'regular', mode: 0o777},
		stage.Entry{name: 'lib/loader', kind: 'regular', mode: 0o4755},
		stage.Entry{name: 'lib/loader', kind: 'regular', mode: 0o644}] {
		if _ := inherited_modes([bad], readonly) { return error('unsafe inherited mode accepted') }
	}
	if _ := inherited_modes([stage.Entry{name: 'lib/loader', kind: 'regular', mode: 0o755},
		stage.Entry{name: 'lib/loader', kind: 'regular', mode: 0o555}], readonly) {
		return error('inconsistent inherited modes accepted')
	}
	println('MAPS-ACCOUNT-STAGE SELFTEST PASS identity collisions protected ancestors inode modes streaming media')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' { self_test() or { eprintln(err); exit(1) }; return }
	if os.args.len == 4 && os.args[1] == '--verify-inventory' {
		files := stage.load_inventory(os.args[2], os.args[3]) or { eprintln(err); exit(1) }
		println('MAPS-INVENTORY PASS files=' + files.len.str())
		return
	}
	if os.args.len == 5 && os.args[1] == '--replay-ui' {
		replay_ui(os.args[2], os.args[3], os.args[4]) or { eprintln(err); exit(1) }
		return
	}
	if os.args.len == 6 && os.args[1] == '--audit-base' {
		audit_base(os.args[2], os.args[3], os.args[4], os.args[5]) or { eprintln(err); exit(1) }
		return
	}
	if os.args.len != 4 { eprintln('usage: maps-account-stage REQUEST_JSON REQUEST_SHA256 FRESH_OUTPUT'); exit(2) }
	run(os.args[1], os.args[2], os.args[3]) or { eprintln(err); exit(1) }
}
