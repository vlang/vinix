// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import hwhost
import json2
import os
import time
import tools.packages.pkgcore
import tools.packages.pkgprotocol

struct NativeArtifact { role string bytes u64 sha256 string }
struct NativeReceipt { format int = 1 architecture string completed_at i64 seconds f64 platform string = 'qemu-initramfs' boots int = 1 artifacts []NativeArtifact }
struct NativeInputArtifact { path string bytes u64 sha256 string }
struct NativeInputs { format int profile string version string catalog_sha256 string artifacts []NativeInputArtifact }
struct NativeImageApplications { format int = 1 architecture string packages []string }

fn native_artifact(role string, path string) !NativeArtifact {
	mut source := os.open(path)!
	defer { source.close() }
	mut hash := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	mut digest := []u8{len: sha256.size}
	defer { unsafe { hash.free(); free(hash); buffer.free(); digest.free() } }
	mut bytes := u64(0)
	for {
		count := source.read(mut buffer) or { if err is os.Eof { break }; return err }
		if count == 0 { break }
		hash.write(unsafe { buffer[..count] })!
		bytes += u64(count)
	}
	hash.checksum_into(mut digest)
	return NativeArtifact{ role: role, bytes: bytes, sha256: digest.hex() }
}

const installed_image_id = 'vinix-packages-installed-sdk-1'
fn release_audit_markers() []string {
	return [
	'SOFTWARE RELEASE audit initial-empty installed=absent exact-baseline unchanged-state ordinary-read PASS',
	'SOFTWARE RELEASE audit initial-installed installed=1.0.0 exact-baseline unchanged-state ordinary-read PASS',
	'SOFTWARE RELEASE audit standard-account installed=1.0.0 exact-baseline unchanged-state ordinary-read PASS',
	'SOFTWARE RELEASE audit cold-upgrade installed=1.0.0 exact-baseline unchanged-state ordinary-read PASS',
	'SOFTWARE RELEASE audit cold-upgraded installed=1.1.0 exact-baseline unchanged-state ordinary-read PASS',
	'SOFTWARE RELEASE audit cold-maintain installed=1.1.0 exact-baseline unchanged-state ordinary-read PASS',
	'SOFTWARE RELEASE audit cold-rollback installed=1.0.0 exact-baseline unchanged-state ordinary-read PASS',
	'SOFTWARE RELEASE audit cold-removed installed=absent exact-baseline unchanged-state ordinary-read PASS',
	'SOFTWARE RELEASE audit cold-reinstalled installed=1.1.0 exact-baseline unchanged-state ordinary-read PASS',
	'SOFTWARE RELEASE audit cold-reopen installed=1.1.0 exact-baseline unchanged-state ordinary-read PASS',
	]
}
struct NativeInstalledImage { format int = 1 image string files []NativeArtifact }

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
	if image { programs << [hwhost.Program{ source: 'tools/packages/pkgcore/image_repositories_test.v', path: 'usr/share/package-fixtures/image-repositories' },
		hwhost.Program{ source: 'tools/packages/pkgcore/catalog_export_test.v', path: 'usr/share/package-fixtures/catalog-exports' }] }
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
		required << 'SOFTWARE IMAGE staged-release-catalog discovered full-set review separate administrator approval exact offline install PASS'
		required << release_audit_markers()[..3]
		required << 'SOFTWARE IMAGE compact-deployment 320x240 keyboard paging visible release review and audit separate approval PASS'
	}
	if image { required << ['PACKAGE IMAGE BUNDLE production-staged signed repository before first refresh PASS',
		'PACKAGE IMAGE CAPTURE guarded preparation publication checked retirement replacement preservation retry and saved output PASS',
		'PACKAGE CATALOG EXPORT guarded workspace composition host selection recovery retry saved output and signed offline consumption PASS'] }
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
			'PACKAGE COLD BOOT 4 exact retained reinstall provenance registration private data PASS',
			'SOFTWARE IMAGE staged-release-catalog discovered full-set review separate administrator approval exact offline install PASS',
			...release_audit_markers()],
		forbidden: ['V panic:', 'HWTEST FAIL'],
	}] }
}

fn installed_software_suite(sandbox string, disk string) hwhost.Suite {
	base := persistent_software_suite(sandbox, disk)
	scenario := base.scenarios[0]
	mut files := base.files.clone()
	files << hwhost.RootFile{ path: '.vinix-image-id', text: installed_image_id + '\n' }
	mut forbidden := scenario.forbidden.clone()
	forbidden << ['sysdisk: updating the system on', 'sysdisk: running from memory']
	selected := hwhost.Scenario{ name: 'packages-software-installed', arches: scenario.arches,
			about: 'install a complete system on a blank disk, then maintain native applications across four installed-root boots',
			cmdline: 'vinix.disk=auto', timeout: 900,
			ending: scenario.ending, reboots: scenario.reboots,
			qemu_aarch64: scenario.qemu_aarch64.map(it.replace('packages.ext2', 'system.vjfs')),
			qemu_x86_64: scenario.qemu_x86_64.map(it.replace('packages.ext2', 'system.vjfs')),
			disks: [hwhost.Disk{ name: 'system.vjfs', size_mib: 4096, image: disk }],
			required: ['HWTEST START packages-software-installed', 'HWTEST PASS packages-software-installed',
				'PACKAGE INSTALLED BOOT 1 disk root staged tools trust ordinary Software install PASS',
				'PACKAGE INSTALLED BOOT 2 retained tools accounts state native reopen reviewed upgrade PASS',
				'PACKAGE INSTALLED BOOT 3 retained upgrade rollback uninstall cached reinstall PASS',
				'PACKAGE INSTALLED BOOT 4 retained reinstall tools provenance registration private data PASS',
				'PACKAGE INSTALLED RELEASE exact declaration disk identity mode digest PASS',
				'SOFTWARE IMAGE staged-release-catalog discovered full-set review separate administrator approval exact offline install PASS',
				...release_audit_markers()],
			forbidden: forbidden,
	}
	return hwhost.Suite{ ...base, name: 'package-software-installed', files: files, scenarios: [selected] }
}

fn stage_installed_proof(root string, guest string) !NativeArtifact {
	mut files := [native_artifact('/sbin/init', guest)!]
	for path in ['/usr/bin/vinix-package', '/usr/bin/vinix-sandbox', '/usr/sbin/vinix-account', '/usr/sbin/vinix-authd',
		'/usr/sbin/vinix-session', '/usr/share/package-fixtures/software-image',
		'/usr/share/vinix/actions/packages-change', '/usr/share/vinix/actions/packages-launch', pkgprotocol.image_applications_path]! {
		files << native_artifact(path, root + path)!
	}
	path := '/usr/share/package-fixtures/installed-image.json'
	os.write_file(root + path, json2.encode(NativeInstalledImage{ image: installed_image_id, files: files }) + '\n')!
	os.chmod(root + path, 0o644)!
	return native_artifact('image' + path, root + path)!
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
	lookup := '@vlib|' + host.root + '|' + host.root + '/tools/accounts|' + modules + '|@vmodules'
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
	applications := publisher + '/image-applications.json'
	os.write_file(applications, json2.encode(NativeImageApplications{ architecture: host.arch,
		packages: ['org.vinix.counter', 'org.vinix.memo', 'org.vinix.package-hello'] }) + '\n')!
	hwhost.run_tool([host.v, '-nocache', '-no-skip-unused', '-path', '@vlib|@vmodules|' + host.root + '|' + host.root + '/tools/accounts',
		'-o', stage, host.root + '/tools/packages/stage.v'], {}, work + '/stage-build.log', 300)!
	mut arguments := [stage, '--arch', host.arch, '--staging', root, '--config', configuration, '--repositories', publisher + '/bundle', '--applications', applications]
	compiler := os.getenv('CC_' + host.arch.to_upper())
	if compiler != '' { arguments << ['--cc', compiler] }
	hwhost.run_tool(arguments, { 'V': host.v, 'VFLAGS': '-nocache' }, work + '/stage.log', 300)!
	artifacts << native_artifact('image' + pkgprotocol.image_applications_path, root + pkgprotocol.image_applications_path)!
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
	artifacts << native_artifact('image/usr/share/package-fixtures/catalog-exports', root + '/usr/share/package-fixtures/catalog-exports')!
	return artifacts
}

fn check() !int {
	profiles := '--profiles' in os.args
	installed := '--installed' in os.args
	persistent := '--persistent' in os.args || installed
	software := '--software' in os.args || persistent
	image := '--image' in os.args || software || profiles
	arguments := os.args[1..].filter(it !in ['--image', '--software', '--persistent', '--installed', '--profiles'])
	if profiles && software { return error('--profiles selects the native image scenario; run Software scenarios separately') }
	options := hwhost.parse_options(arguments)!
	if options.help || options.list { return hwhost.run_suite(if installed { installed_software_suite('', '') }
		else if persistent { persistent_software_suite('', '') } else { native_suite('', image, software) }, arguments, @FILE) }
	inputs := os.getenv('VINIX_NATIVE_CATALOG_INPUTS')
	sandbox := os.getenv('VINIX_NATIVE_CATALOG_SANDBOX')
	if os.getenv('VINIX_HWTEST_TCG') != '1' || !os.is_file(options.kernel) || !os.is_dir(inputs)
		|| !os.is_file(sandbox) || options.state_dir == '' || os.exists(options.state_dir) || os.is_link(options.state_dir) {
		return error('provide VINIX_HWTEST_TCG=1, VINIX_NATIVE_CATALOG_INPUTS, target VINIX_NATIVE_CATALOG_SANDBOX, --kernel and a new --state-dir')
	}
	repository := hwhost.find_root(@FILE)!
	base := if installed { installed_software_suite(sandbox, '') }
		else if persistent { persistent_software_suite(sandbox, '') } else { native_suite(sandbox, image, software) }
	definition := if profiles { hwhost.Suite{ ...base,
		programs: [...base.programs, hwhost.Program{ source: 'tools/packages/pkgcore/profile_export_test.v', path: 'usr/share/package-fixtures/profile-exports' }],
		scenarios: [hwhost.Scenario{ ...base.scenarios[0], timeout: 900, required: [...base.scenarios[0].required,
			'PACKAGE PROFILE EXPORT five captured publisher profiles recovery exact retry and saved output PASS'] }] }
	} else { base }
	hwhost.validate_scenarios(definition.scenarios)!
	selection := hwhost.select_scenarios(definition.scenarios, options.arch, options.scenarios)!
	if selection.run.len != 1 { return error('select packages-native-catalog, --image packages-native-image, --software packages-software-image, --persistent packages-software-persistence or --installed packages-software-installed') }
	host := hwhost.find_host(repository, options.arch, options.qemu)!
	os.mkdir_all(options.state_dir)!
	work := os.real_path(options.state_dir)
	os.cp(options.kernel, work + '/kernel')!
	disk := work + if installed { '/initial.raw' } else { '/initial.ext2' }
	if persistent {
		os.write_file(disk, '')!; os.truncate(disk, u64(if installed { 4096 } else { 128 }) << 20)!
		if !installed {
			formatter := os.getenv_opt('VINIX_MKE2FS') or { os.find_abs_path_of_executable('mke2fs') or { '/opt/homebrew/opt/e2fsprogs/sbin/mke2fs' } }
			hwhost.run_tool([formatter, '-q', '-F', '-t', 'ext2', '-b', '4096', '-I', '128', '-m', '0', '-O',
				'none,filetype,sparse_super,large_file', disk], {}, work + '/format.log', 60)!
		}
	}
	hwhost.watch_interrupts()
	guest := hwhost.build_program(host, repository + '/' + definition.guest, work + '/guest', 'init', definition.module_paths)!
	root := hwhost.build_extras(host, definition, work + '/guest')!
	mut artifacts := [native_artifact('kernel', work + '/kernel')!, native_artifact('guest-init', guest)!]
	if persistent { artifacts << native_artifact(if installed { 'initial-blank-system-disk' } else { 'initial-ext2' }, disk)! }
	for file in definition.files { artifacts << native_artifact(file.path, root + '/' + file.path)! }
	if profiles {
		archive := os.getenv('VINIX_PROFILE_EXPORT_SOURCE')
		if !os.is_file(archive) || os.file_size(archive) != pkgcore.ffmpeg_source_bytes
			|| native_artifact('source', archive)!.sha256 != pkgcore.ffmpeg_source_digest {
			return error('provide VINIX_PROFILE_EXPORT_SOURCE with the reviewed FFmpeg 8.0.1 source archive')
		}
		path := root + '/usr/share/package-fixtures/ffmpeg.tar.xz'
		os.cp(archive, path)!; os.chmod(path, 0o644)!
		artifacts << native_artifact('image/usr/share/package-fixtures/ffmpeg.tar.xz', path)!
		artifacts << native_artifact('image/usr/share/package-fixtures/profile-exports', root + '/usr/share/package-fixtures/profile-exports')!
	}
	artifacts << if image { stage_native_image(host, inputs, root, work)! } else { stage_native_inputs(inputs, root)! }
	if software {
		artifacts << stage_software_image(host, root, work)!
		artifacts << native_artifact('image/usr/sbin/vinix-authd', root + '/usr/sbin/vinix-authd')!
	}
	if installed { artifacts << stage_installed_proof(root, guest)! }
	for path in ['usr/bin/vinix-package', 'usr/bin/vinix-sandbox', 'usr/sbin/vinix-account', 'usr/sbin/vinix-session'] {
		artifacts << native_artifact(path, root + '/' + path)!
	}
	scenario := if installed { installed_software_suite(sandbox, disk).scenarios[0] }
		else if persistent { persistent_software_suite(sandbox, disk).scenarios[0] } else { selection.run[0] }
	outcome := hwhost.run_scenario(host, scenario, hwhost.Run{ kernel: work + '/kernel', guest: guest, extras: root,
		state: work + '/native', timeout: if options.timeout > scenario.timeout { options.timeout } else { scenario.timeout }, keep: true })
	println(hwhost.report(options.arch, outcome))
	if outcome.interrupted { return 130 }
	if !outcome.passed { return 1 }
	for role, path in {'serial-log': 'serial.log', 'qmp-log': 'qmp.log'} { artifacts << native_artifact(role, work + '/native/' + path)! }
	if persistent {
		for boot in 2 .. 5 { artifacts << native_artifact('serial-log-' + boot.str(), work + '/native/serial-' + boot.str() + '.log')! }
		artifacts << native_artifact(if installed { 'final-installed-system-disk' } else { 'final-ext2' },
			work + '/native/' + if installed { 'system.vjfs' } else { 'packages.ext2' })!
	}
	os.write_file(work + '/qualification.json', json2.encode(NativeReceipt{ architecture: options.arch, completed_at: time.now().unix(),
		seconds: outcome.seconds, platform: if installed { 'qemu-vjfs-installed-root' }
			else if persistent { 'qemu-ext2-retained-subtrees' } else { 'qemu-initramfs' },
		boots: scenario.boots(), artifacts: artifacts }) + '\n')!
	return 0
}

fn main() { exit(check() or { eprintln(err); 2 }) }
