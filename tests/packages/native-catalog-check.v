// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import hwhost
import json2
import os
import time
import tools.packages.pkgcore

struct NativeArtifact { role string bytes u64 sha256 string }
struct NativeReceipt { format int = 1 architecture string completed_at i64 seconds f64 platform string = 'qemu-initramfs' boots int = 1 artifacts []NativeArtifact }
struct NativeInputArtifact { path string bytes u64 sha256 string }
struct NativeInputs { format int profile string version string catalog_sha256 string artifacts []NativeInputArtifact }

fn native_artifact(role string, path string) !NativeArtifact {
	bytes := os.read_bytes(path)!
	defer { unsafe { bytes.free() } }
	return NativeArtifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn native_suite(sandbox string, image bool, software bool) hwhost.Suite {
	files := [
		hwhost.RootFile{ path: 'etc/passwd', text: 'root:x:0:0:root:/root:/bin/sh\n' },
		hwhost.RootFile{ path: 'etc/group', text: 'root:x:0:\ntty:x:5:\n' },
		hwhost.RootFile{ path: 'etc/vinix/auth.conf', text: 'scrypt_ln = 10\n' },
	]
	binaries := [hwhost.RootBinary{ source: sandbox, path: 'usr/bin/vinix-sandbox' }]
	mut programs := if software {
		[hwhost.Program{ source: 'tools/accounts/account.v', path: 'usr/sbin/vinix-account' },
			hwhost.Program{ source: 'tools/accounts/authd.v', path: 'usr/sbin/vinix-authd' }]
	} else if image {
		[hwhost.Program{ source: 'tools/accounts/account.v', path: 'usr/sbin/vinix-account' },
			hwhost.Program{ source: 'tools/packages/pkgcore/image_configuration_test.v', path: 'usr/share/package-fixtures/image-configuration' }]
	} else {
		[hwhost.Program{ source: 'tools/packages/main.v', path: 'usr/bin/vinix-package' },
			hwhost.Program{ source: 'tools/accounts/account.v', path: 'usr/sbin/vinix-account' },
			hwhost.Program{ source: 'tools/accounts/session.v', path: 'usr/sbin/vinix-session' }]
	}
	if image { programs << hwhost.Program{ source: 'tools/packages/pkgcore/image_repositories_test.v', path: 'usr/share/package-fixtures/image-repositories' } }
	name := if software { 'packages-software-image' } else if image { 'packages-native-image' } else { 'packages-native-catalog' }
	mut required := ['HWTEST START ' + name,
		'PACKAGE NATIVE CATALOG six-pinned-packages signed-review architecture notices document-grant protocols-1-2 ordinary-data PASS',
		'PACKAGE NATIVE CATALOG upgrade rollback uninstall-registration offline-cache-reinstall retained-private-data PASS', 'HWTEST PASS ' + name]
	if image { required << ['PACKAGE IMAGE CONFIG booted with staged trust policy and launch account before first refresh PASS',
		'PACKAGE IMAGE CONFIG unchanged staged configuration real native apps upgrade rollback offline reinstall PASS'] }
	if software {
		required = ['HWTEST START ' + name, 'HWTEST PASS ' + name,
			'SOFTWARE IMAGE ordinary-admin real-refresh cancel bad-password review install progress native-window-1-2 document-grant PASS',
			'SOFTWARE IMAGE standard-account denied-administration own-isolated-launch private-data PASS',
			'SOFTWARE IMAGE reviewed-update rollback retained-memo PASS',
			'SOFTWARE IMAGE updates rollback uninstall registration cached-reinstall retained-memo PASS',
			'SOFTWARE IMAGE unchanged-staged-trust root-owned-state separate-user-data clean-runtime PASS']
	}
	if image { required << 'PACKAGE IMAGE BUNDLE production-staged signed repository before first refresh PASS' }
	return hwhost.Suite{ name: 'package-native-catalog', guest: 'tests/accounts/guest',
		module_paths: ['.', 'tools/accounts', 'tools/security-events', 'tools/keyring'],
		programs: programs,
		files: files, binaries: binaries, directories: ['run', 'home', 'var/log', 'tmp:1777'],
		scenarios: [hwhost.Scenario{ name: name, arches: ['aarch64', 'x86_64'],
			about: if software { 'ordinary Software controller with real administration, native-window launch and maintenance services' }
				else { 'signed six-variant native catalog with real SDK apps, update/rollback and cached reinstall' }, timeout: 300, ending: .poweroff,
			required: required, forbidden: ['V panic:'] }] }
}

fn persistent_software_suite(sandbox string, disk string) hwhost.Suite {
	base := native_suite(sandbox, true, true)
	return hwhost.Suite{ ...base, name: 'package-software-persistence', scenarios: [hwhost.Scenario{
		name: 'packages-software-persistence', arches: ['aarch64', 'x86_64'],
		about: 'four cold boots with ordinary Software, ext2 package/account state and native app data',
		cmdline: 'vinix.qemu_persist=1', timeout: 600, ending: .poweroff,
		disks: [hwhost.Disk{ name: 'packages.ext2', size_mib: 128, image: disk }],
		qemu_aarch64: ['-drive', 'if=none,id=packages,format=raw,cache=writeback,file={state}/packages.ext2', '-device', 'virtio-blk-device,drive=packages'],
		qemu_x86_64: ['-drive', 'if=ide,format=raw,cache=writeback,file={state}/packages.ext2'],
		reboots: [hwhost.Reboot{}, hwhost.Reboot{}, hwhost.Reboot{}],
		required: ['HWTEST START packages-software-persistence', 'HWTEST PASS packages-software-persistence',
			'PACKAGE COLD BOOT 1 fresh staged trust ordinary Software install separate user data PASS',
			'PACKAGE COLD BOOT 2 exact retained state accounts trust native reopen reviewed upgrade PASS',
			'PACKAGE COLD BOOT 3 exact retained upgrade rollback uninstall cached reinstall PASS',
			'PACKAGE COLD BOOT 4 exact retained reinstall provenance registration private data PASS'],
		forbidden: ['V panic:', 'HWTEST FAIL'],
	}] }
}

fn stage_software_image(host hwhost.Host, root string, work string) !NativeArtifact {
	modules := os.getenv_opt('VINIX_PACKAGE_TEST_UI2') or { host.root + '/build/vmodules' }
	if !os.is_file(modules + '/ui2/v.mod') { return error('provide VINIX_PACKAGE_TEST_UI2 with a headless ui2 module') }
	source := work + '/software-source'; os.mkdir(source)!
	for name in os.ls(host.root + '/desktop')! {
		if name.starts_with('software_') && name.ends_with('.v') { os.cp(host.root + '/desktop/' + name, source + '/' + name)! }
	}
	os.cp(host.root + '/tests/packages/software_image_fixture.v', source + '/main.v')!
	os.cp(host.root + '/tests/packages/software_terminal_fixture.v', source + '/terminal_fixture.v')!
	lookup := '@vlib|' + modules + '|@vmodules|' + host.root + '|' + host.root + '/tools/accounts'
	binary := hwhost.build_program_with_flags(host, source, work + '/software-build', 'software-image', [],
		['-manualfree', '-enable-globals', '-d', 'ui2_headless', '-path', lookup, '-cflags', '-I' + host.root + '/desktop'])!
	target := root + '/usr/share/package-fixtures/software-image'
	os.mkdir_all(os.dir(target))!
	os.cp(binary, target)!; os.chmod(target, 0o755)!
	return native_artifact('image/usr/share/package-fixtures/software-image', target)!
}

// Foreign-target executables are publisher data, not suite programs. Admit all
// twelve input pins from the builder's record before copying either closure.
fn stage_native_inputs(inputs string, root string) ![]NativeArtifact {
	record := json2.decode[NativeInputs](os.read_file(inputs + '/build.json')!)!
	if record.format != 1 || record.profile != 'native-sdk' || record.version != '1.0.0' {
		return error('expected the complete native SDK 1.0.0 build record')
	}
	mut expected := []string{}
	for architecture in ['aarch64', 'x86_64'] {
		for path in ['bin/package-hello', 'bin/counter', 'bin/memo', 'licenses/application-sdk-MIT.txt', 'licenses/v-MIT.txt', 'licenses/musl-MIT.txt'] {
			expected << 'roots/' + architecture + '/' + path
		}
	}
	mut artifacts := [native_artifact('input-build-record', inputs + '/build.json')!]
	for item in record.artifacts {
		if !item.path.starts_with('roots/') { continue } // compiler executables are recorded host tools
		if item.path !in expected || os.is_link(inputs + '/' + item.path) { return error('unexpected or duplicate native input: ${item.path}') }
		expected.delete(expected.index(item.path))
		bytes := os.read_bytes(inputs + '/' + item.path)!
		defer { unsafe { bytes.free() } }
		if u64(bytes.len) != item.bytes || sha256.sum(bytes).hex() != item.sha256 { return error('changed native input: ${item.path}') }
		destination := root + '/usr/share/native-catalog/' + item.path
		os.mkdir_all(os.dir(destination))!
		os.write_file_array(destination, bytes)!
		os.chmod(destination, if item.path.contains('/bin/') { 0o755 } else { 0o644 })!
		artifacts << native_artifact('input/' + item.path, destination)!
	}
	if expected.len != 0 { return error('native input record lacks required payloads') }
	catalog_text := os.read_file(inputs + '/lock/catalog.json')!
	if sha256.sum(catalog_text.bytes()).hex() != record.catalog_sha256 { return error('changed native catalog lock') }
	os.write_file(root + '/usr/share/native-catalog/catalog.json', catalog_text)!
	artifacts << native_artifact('input/catalog.json', root + '/usr/share/native-catalog/catalog.json')!
	return artifacts
}

fn stage_native_image(host hwhost.Host, inputs string, root string, work string) ![]NativeArtifact {
	// Verify and capture the builder's exact inputs before using them to create
	// complete signed release exports. The signing seed stays outside the image.
	verified := work + '/verified-inputs'
	os.mkdir(verified)!
	mut artifacts := stage_native_inputs(inputs, verified)!
	prepared := verified + '/usr/share/native-catalog/roots'
	publisher := work + '/publisher'; os.mkdir(publisher, mode: 0o700)!
	key := pkgcore.keygen(publisher + '/seed')!
	for i, version in ['1.0.0', '1.1.0'] {
		profile := pkgcore.native_catalog(version, prepared, publisher + '/lock-' + version)!
		workspace := publisher + '/workspace-' + version
		pkgcore.pack_catalog(profile.catalog, prepared, workspace)!
		destination := if i == 0 { publisher + '/bundle/native' } else { root + '/usr/share/native-catalog/releases/' + version }
		pkgcore.publish_release(workspace, 'native', publisher + '/seed', u64(i + 1), time.now().unix() + 3600, destination)!
	}
	configuration := publisher + '/image-config.json'
	os.write_file(configuration, json2.encode(pkgcore.Config{ architecture: host.arch, launch_user: 'alex',
		policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 },
		repositories: [pkgcore.Repository{ id: 'native', url: 'file://' + pkgcore.image_repositories_path + '/native', public_key: key }] }) + '\n')!
	stage := work + '/package-stage'
	hwhost.run_tool([host.v, '-nocache', '-no-skip-unused', '-path', '@vlib|@vmodules|' + host.root + '|' + host.root + '/tools/accounts',
		'-o', stage, host.root + '/tools/packages/stage.v'], {}, work + '/stage-build.log', 300)!
	mut arguments := [stage, '--arch', host.arch, '--staging', root, '--config', configuration, '--repositories', publisher + '/bundle']
	compiler := os.getenv('CC_' + host.arch.to_upper())
	if compiler != '' { arguments << ['--cc', compiler] }
	hwhost.run_tool(arguments, { 'V': host.v, 'VFLAGS': '-nocache' }, work + '/stage.log', 300)!
	for path in ['etc/vinix-packages/config.json', 'usr/bin/vinix-package', 'usr/sbin/vinix-session',
		'usr/libexec/vinix/vinix-linux-runner', 'usr/share/vinix/actions/packages-change', 'usr/share/vinix/actions/packages-launch',
		'usr/share/licenses/vinix-packages/ed25519-MIT.txt', 'usr/share/licenses/vinix-packages/application-sdk-MIT.txt']! {
		artifacts << native_artifact('image/' + path, root + '/' + path)!
	}
	for path in os.walk_ext(root + '/usr/share/native-catalog/releases', '') {
		if os.is_file(path) { artifacts << native_artifact('image/' + path[root.len + 1..], path)! }
	}
	for path in os.walk_ext(root + pkgcore.image_repositories_path, '') {
		if os.is_file(path) { artifacts << native_artifact('image/' + path[root.len + 1..], path)! }
	}
	artifacts << native_artifact('image/usr/share/package-fixtures/image-repositories', root + '/usr/share/package-fixtures/image-repositories')!
	return artifacts
}

fn check() !int {
	persistent := '--persistent' in os.args
	software := '--software' in os.args || persistent
	image := '--image' in os.args || software
	arguments := os.args[1..].filter(it !in ['--image', '--software', '--persistent'])
	options := hwhost.parse_options(arguments)!
	if options.help || options.list { return hwhost.run_suite(if persistent { persistent_software_suite('', '') } else { native_suite('', image, software) }, arguments, @FILE) }
	inputs := os.getenv('VINIX_NATIVE_CATALOG_INPUTS')
	sandbox := os.getenv('VINIX_NATIVE_CATALOG_SANDBOX')
	if os.getenv('VINIX_HWTEST_TCG') != '1' || !os.is_file(options.kernel) || !os.is_dir(inputs)
		|| !os.is_file(sandbox) || options.state_dir == '' || os.exists(options.state_dir) || os.is_link(options.state_dir) {
		return error('provide VINIX_HWTEST_TCG=1, VINIX_NATIVE_CATALOG_INPUTS, target VINIX_NATIVE_CATALOG_SANDBOX, --kernel and a new --state-dir')
	}
	repository := hwhost.find_root(@FILE)!
	definition := if persistent { persistent_software_suite(sandbox, '') } else { native_suite(sandbox, image, software) }
	hwhost.validate_scenarios(definition.scenarios)!
	selection := hwhost.select_scenarios(definition.scenarios, options.arch, options.scenarios)!
	if selection.run.len != 1 { return error('select packages-native-catalog, --image packages-native-image, --software packages-software-image or --persistent packages-software-persistence') }
	host := hwhost.find_host(repository, options.arch, options.qemu)!
	os.mkdir_all(options.state_dir)!
	work := os.real_path(options.state_dir)
	os.cp(options.kernel, work + '/kernel')!
	if persistent {
		disk := work + '/initial.ext2'
		os.write_file(disk, '')!; os.truncate(disk, u64(128) << 20)!
		formatter := os.getenv_opt('VINIX_MKE2FS') or { os.find_abs_path_of_executable('mke2fs') or { '/opt/homebrew/opt/e2fsprogs/sbin/mke2fs' } }
		hwhost.run_tool([formatter, '-q', '-F', '-t', 'ext2', '-b', '4096', '-I', '128', '-m', '0', '-O',
			'none,filetype,sparse_super,large_file', disk], {}, work + '/format.log', 60)!
	}
	hwhost.watch_interrupts()
	guest := hwhost.build_program(host, repository + '/' + definition.guest, work + '/guest', 'init', definition.module_paths)!
	root := hwhost.build_extras(host, definition, work + '/guest')!
	mut artifacts := [native_artifact('kernel', work + '/kernel')!, native_artifact('guest-init', guest)!]
	if persistent { artifacts << native_artifact('initial-ext2', work + '/initial.ext2')! }
	for file in definition.files { artifacts << native_artifact(file.path, root + '/' + file.path)! }
	artifacts << if image { stage_native_image(host, inputs, root, work)! } else { stage_native_inputs(inputs, root)! }
	if software {
		artifacts << stage_software_image(host, root, work)!
		artifacts << native_artifact('image/usr/sbin/vinix-authd', root + '/usr/sbin/vinix-authd')!
	}
	for path in ['usr/bin/vinix-package', 'usr/bin/vinix-sandbox', 'usr/sbin/vinix-account', 'usr/sbin/vinix-session'] {
		artifacts << native_artifact(path, root + '/' + path)!
	}
	scenario := if persistent { persistent_software_suite(sandbox, work + '/initial.ext2').scenarios[0] } else { selection.run[0] }
	outcome := hwhost.run_scenario(host, scenario, hwhost.Run{ kernel: work + '/kernel', guest: guest, extras: root,
		state: work + '/native', timeout: if options.timeout > scenario.timeout { options.timeout } else { scenario.timeout }, keep: true })
	println(hwhost.report(options.arch, outcome))
	if outcome.interrupted { return 130 }
	if !outcome.passed { return 1 }
	for role, path in {'serial-log': 'serial.log', 'qmp-log': 'qmp.log'} { artifacts << native_artifact(role, work + '/native/' + path)! }
	if persistent {
		for boot in 2 .. 5 { artifacts << native_artifact('serial-log-' + boot.str(), work + '/native/serial-' + boot.str() + '.log')! }
		artifacts << native_artifact('final-ext2', work + '/native/packages.ext2')!
	}
	os.write_file(work + '/qualification.json', json2.encode(NativeReceipt{ architecture: options.arch, completed_at: time.now().unix(),
		seconds: outcome.seconds, platform: if persistent { 'qemu-ext2-retained-subtrees' } else { 'qemu-initramfs' },
		boots: scenario.boots(), artifacts: artifacts }) + '\n')!
	return 0
}

fn main() { exit(check() or { eprintln(err); 2 }) }
