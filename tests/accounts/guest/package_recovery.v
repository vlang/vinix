// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import tools.packages.pkgcore

const package_disk = $if arm64 { '/root' } $else { '/package-disk' }
const package_test_root = package_disk + '/root'
const package_state = package_test_root + '/var/lib/vinix-packages'

fn package_crash_checkpoint(phase string) {
	wanted := read_text('/etc/hwtest-scenario').trim_space().all_after_last('-')
	if phase != wanted { return }
	// No sync, return, defer or orderly shutdown follows this marker.
	fd := C.open(&char(console_path.str), C.O_WRONLY)
	text := 'PACKAGE CUT ${phase}\n'
	assert fd >= 0 && C.write(fd, text.str, usize(text.len)) == text.len
	idle()
}

fn package_disk_mount() ! {
	$if arm64 {
		// This kernel discovers/registers VirtIO ext2 volumes in its supported
		// persistent-home boot path, before userspace starts.
		if read_text('/proc/mounts').contains(' /root qemu-persist ') { return }
		return error('the kernel did not mount the prepared persistent-home ext2 disk')
	}
	os.mkdir_all(package_disk)!
	for device in ['/dev/vda', '/dev/vdb', '/dev/sd0', '/dev/sd1', '/dev/sd2', '/dev/sd3'] {
		if C.mount(&char(device.str), &char(package_disk.str), c'ext2', 0, unsafe { nil }) == 0 {
			return
		}
	}
	return error('cannot mount the prepared package ext2 disk')
}

fn package_root_cli(arguments []string) !string {
	return package_success(['--root', package_test_root, ...arguments])!
}

fn package_disk_version(version string, architecture string) ! {
	source := package_disk + '/source'
	os.write_file(source + '/version.txt', version + '\n')!
	manifest := pkgcore.Package{
		id:           'recovery-app'
		version:      version
		architecture: architecture
		name:         'Recovery fixture'
		license:      'GPL-2.0-or-later'
		kind:         'native'
		entrypoint:   'bin/app'
	}
	os.write_file(package_disk + '/manifest.json', json2.encode(manifest))!
	pkgcore.pack(package_disk + '/manifest.json', source, package_disk + '/repository')!
}

fn package_disk_setup() !pkgcore.Config {
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	os.mkdir_all(package_disk + '/source/bin')!
	os.cp('/sbin/init', package_disk + '/source/bin/app')!
	os.chmod(package_disk + '/source/bin/app', 0o755)!
	os.mkdir_all(package_test_root + '/etc/vinix-packages')!
	key := pkgcore.keygen(package_disk + '/signing-seed')!
	config := pkgcore.Config{
		architecture: architecture
		repositories: [pkgcore.Repository{ id: 'fixture', url: 'file://' + package_disk + '/repository', public_key: key }]
		policy:       pkgcore.Policy{ reserve_bytes: 0 }
	}
	pkgcore.atomic_write(package_test_root + '/etc/vinix-packages/config.json', json2.encode(config))!
	package_disk_version('1.0.0', architecture)!
	pkgcore.publish(package_disk + '/repository', 'fixture', package_disk + '/signing-seed', 1, time.now().unix() + 3600)!
	package_root_cli(['update'])!
	package_root_cli(['install', 'recovery-app'])!
	assert pkgcore.read_state(package_state, architecture)!.generation == 1
	package_disk_version('2.0.0', architecture)!
	pkgcore.publish(package_disk + '/repository', 'fixture', package_disk + '/signing-seed', 2, time.now().unix() + 3600)!
	package_root_cli(['update'])!
	// A durable partial download must resume and authenticate before publication.
	catalog := pkgcore.load_catalog(config, package_state)!
	v2 := catalog.packages.filter(it.package.version == '2.0.0')[0].package
	file := v2.files.filter(it.path == 'version.txt')[0]
	pkgcore.atomic_write(package_state + '/objects/' + file.sha256 + '.part', '2.')!
	data := package_test_root + '/home/alex/.local/share/vinix-apps/recovery-app'
	os.mkdir_all(data)!
	os.write_file(data + '/personal.txt', 'personal data survives\n')!
	os.chown(data + '/personal.txt', 1000, 1000)!
	os.chmod(data + '/personal.txt', 0o600)!
	// Only preparation uses a global sync. The transaction must supply its own.
	C.sync()
	pkgcore.atomic_write(package_disk + '/armed', 'prepared\n')!
	return config
}

fn qualify_package_recovery(mut t Test) ! {
	package_disk_mount()!
	phase := t.scenario.all_after_last('-')
	if !os.is_file(package_disk + '/armed') {
		config := package_disk_setup()!
		pkgcore.transact(config, package_state, 'upgrade', [], pkgcore.TransactionOptions{
			checkpoint: package_crash_checkpoint
		})!
		return error('transaction returned without reaching its crash checkpoint')
	}
	config := pkgcore.load_config(package_test_root)!
	state := pkgcore.read_state(package_state, config.architecture)!
	expected := if phase == 'activated' { '2.0.0' } else { '1.0.0' }
	assert state.packages.len == 1 && state.packages[0].package.version == expected
	assert state.generation == if phase == 'activated' { u64(2) } else { u64(1) }
	package_root_cli(['verify'])!
	assert os.is_file(package_state + '/current/share/applications/vinix-recovery-app.desktop')
	assert read_text(package_state + '/current/apps/recovery-app/version.txt') == expected + '\n'
	assert os.is_dir(package_state + '/generations/.stage-2') == (phase == 'staged')
	if phase == 'published' {
		assert os.is_dir(package_state + '/generations/2')
	}
	// No repository payload is available after reboot: use the verified cache.
	os.rmdir_all(package_disk + '/repository/objects')!
	package_root_cli(['--offline', 'upgrade'])!
	assert !os.exists(package_state + '/generations/.stage-2')
	assert read_text(package_state + '/current/apps/recovery-app/version.txt') == '2.0.0\n'
	package_root_cli(['verify'])!
	package_root_cli(['rollback'])!
	assert read_text(package_state + '/current/apps/recovery-app/version.txt') == '1.0.0\n'
	package_root_cli(['remove', 'recovery-app'])!
	assert pkgcore.read_state(package_state, config.architecture)!.packages.len == 0
	assert !os.exists(package_state + '/current/share/applications/vinix-recovery-app.desktop')
	package_root_cli(['rollback'])!
	package_root_cli(['verify'])!
	package_root_cli(['gc'])!
	assert os.ls(package_state + '/generations')!.sorted() == ['4', '5']
	assert pkgcore.read_state(package_state, config.architecture)!.previous == 4
	data := package_test_root + '/home/alex/.local/share/vinix-apps/recovery-app/personal.txt'
	assert read_text(data) == 'personal data survives\n' && owner_of(data) == 1000
	assert mode_of(data) == 0o600
	assert !os.ls(package_state + '/objects')!.any(it.ends_with('.part'))
	t.say('PACKAGE RECOVERY ${phase} coherent-state cached-upgrade rollback remove registration data gc PASS')
}

fn scenario_package_recovery(mut t Test) {
	qualify_package_recovery(mut t) or { t.check(false, err.msg()) }
}
