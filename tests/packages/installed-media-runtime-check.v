// SPDX-License-Identifier: GPL-2.0-or-later
module main

import hwhost
import json2
import os
import plainiso
import tools.packages.pkgcore

const image_id = 'vinix-installed-offline-media-1'

struct ImportBinding {
	receipt_sha256 string
	deployment_sha256 string
	configuration_sha256 string
	sandbox_sha256 string
	update_publisher string
	update_index_sha256 string
}

fn capture_media(work string, source string) !string {
	root := work + '/media-root'
	os.mkdir(root)!
	hwhost.run_tool(['cp', '-Rp', source, root + '/release'], map[string]string{}, work + '/media-copy.log', 120)!
	return root
}

fn format_media(work string, root string, formatter string, debugfs string, directories []string) !string {
	image := work + '/release.ext2'
	hwhost.run_tool([formatter, '-q', '-F', '-t', 'ext2', '-b', '4096', '-d', root, image, '65536'],
		map[string]string{}, work + '/media-build.log', 120)!
	// These directories must belong to the guest administrator, even if the
	// host account owns the staged paths. Payload bytes are preserved.
	ownership := work + '/media-ownership.txt'
	mut commands := []string{}
	for directory in directories {
		commands << ['set_inode_field ${directory} uid 0', 'set_inode_field ${directory} gid 0']
	}
	os.write_file(ownership, commands.join('\n') + '\n')!
	hwhost.run_tool([debugfs, '-w', '-f', ownership, image], map[string]string{}, work + '/media-ownership.log', 120)!
	return image
}

fn attach_media(arch string, image string) []string {
	return if arch == 'aarch64' {
		['-drive', 'if=none,id=offline,format=raw,readonly=on,file=' + image,
			'-device', 'virtio-blk-device,drive=offline']
	} else {
		['-drive', 'if=ide,index=1,format=raw,snapshot=on,file=' + image]
	}
}

fn check_update(source string, sandbox string, publishers []pkgcore.IsoOfflinePublisher) !pkgcore.ReleaseInfo {
	if source == '' { return pkgcore.ReleaseInfo{} }
	if sandbox == '' || publishers.len != 1 {
		return error('offline maintenance requires a sandbox and one baseline publisher')
	}
	baseline := publishers[0]
	mut update := pkgcore.check_release_export(source, baseline.id, baseline.public_key)!
	if update.sequence <= baseline.sequence {
		update.close()
		return error('offline update must advance the signed publisher sequence')
	}
	return update
}

fn check() ! {
	if os.args.len != 7 || os.args[1] !in ['aarch64', 'x86_64'] || os.getenv('VINIX_HWTEST_TCG') != '1' {
		return error('usage: VINIX_HWTEST_TCG=1 installed-media-runtime-check ARCH KERNEL MEDIA RECEIPT CONFIG NEW_WORK')
	}
	arch := os.args[1]
	kernel := os.real_path(os.args[2])
	media := os.real_path(os.args[3])
	receipt_path := os.real_path(os.args[4])
	configuration := os.real_path(os.args[5])
	work := os.abs_path(os.args[6])
	receipt_text := os.read_file(receipt_path)!
	receipt := json2.decode[pkgcore.IsoPackageReceipt](receipt_text)!
	if receipt.format != 1 || receipt.architecture != arch || receipt.applications.len != 7 {
		return error('expected a format-1 receipt for the target mixed catalog')
	}
	if pkgcore.hash_file(configuration)! != receipt.configuration_sha256 {
		return error('consumer configuration differs from the ISO package receipt')
	}
	pkgcore.verify_iso_offline_media(media, arch, receipt.applications, receipt.deployment_sha256, receipt.publishers)!
	root := hwhost.find_root(@FILE)!
	host := hwhost.find_host(root, arch, '')!
	formatter := os.getenv_opt('VINIX_MKE2FS') or { os.find_abs_path_of_executable('mke2fs')! }
	debugfs := os.dir(os.real_path(formatter)) + '/debugfs'
	sandbox := os.getenv_opt('VINIX_INSTALLED_MEDIA_SANDBOX') or { '' }
	sandbox_path := if sandbox != '' { os.real_path(sandbox) } else { '' }
	sandbox_sha256 := if sandbox_path != '' { pkgcore.hash_file(sandbox_path)! } else { '' }
	update_source := os.getenv('VINIX_INSTALLED_MEDIA_UPDATE')
	mut update := check_update(update_source, sandbox_path, receipt.publishers)!
	defer { update.close() }
	os.mkdir(work)!
	boot := work + '/boot'
	extras := work + '/staging'
	fixture := extras + '/usr/share/installed-media'
	os.mkdir_all(fixture)!
	mut config := pkgcore.prepare_image_configuration(extras, arch, configuration)!
	defer { config.close() }
	config.publish()!
	config_path := extras + '/etc/vinix-packages/config.json'
	config_sha256 := pkgcore.hash_file(config_path)!
	os.write_file(fixture + '/receipt.json', receipt_text)!
	os.write_file(fixture + '/binding.json', json2.encode(ImportBinding{
		receipt_sha256: pkgcore.hash_file(fixture + '/receipt.json')!
		deployment_sha256: receipt.deployment_sha256
		configuration_sha256: config_sha256
		sandbox_sha256: sandbox_sha256
		update_publisher: update.repository
		update_index_sha256: update.index_sha256
	}) + '\n')!
	os.write_file(extras + '/.vinix-image-id', image_id + '\n')!
	media_root := capture_media(work, media)!
	pkgcore.verify_iso_offline_media(media_root + '/release', arch, receipt.applications, receipt.deployment_sha256,
		receipt.publishers)!
	mut directories := ['/release']
	for publisher in receipt.publishers {
		directories << ['/release/' + publisher.id, '/release/' + publisher.id + '/objects']
	}
	media_image := format_media(work, media_root, formatter, debugfs, directories)!
	mut inputs := map[string]string{}
	mut reboots := [hwhost.Reboot{ qemu: attach_media(arch, media_image) }, hwhost.Reboot{}, hwhost.Reboot{}]
	mut attachments := {1: media_image}
	if update_source != '' {
		update_work := work + '/update'
		os.mkdir(update_work)!
		update_root := capture_media(update_work, update.directory)!
		mut captured := pkgcore.check_release_export(update_root + '/release', update.repository, update.public_key)!
		defer { captured.close() }
		if captured.index_sha256 != update.index_sha256 { return error('offline update changed during capture') }
		update_image := format_media(update_work, update_root, formatter, debugfs, ['/release', '/release/objects'])!
		inputs[update_image] = pkgcore.hash_file(update_image)!
		attachments[4] = update_image
		reboots << [hwhost.Reboot{ qemu: attach_media(arch, update_image) }, hwhost.Reboot{}, hwhost.Reboot{}]
	}
	guest_source := root + '/tests/packages/installed-media-guest'
	guest := hwhost.build_program_with_flags(host, guest_source, work + '/guest-build', 'init', ['.'], ['-prod'])!
	cli := hwhost.build_program_with_flags(host, root + '/tools/packages/main.v', work + '/cli-build',
		'vinix-package', ['.', 'tools/accounts'], ['-prod', '-manualfree', '-enable-globals'])!
	os.mkdir_all(extras + '/usr/bin')!
	os.cp(cli, extras + '/usr/bin/vinix-package')!
	os.chmod(extras + '/usr/bin/vinix-package', 0o755)!
	if sandbox_path != '' {
		target := extras + '/usr/bin/vinix-sandbox'
		os.cp(sandbox_path, target)!
		os.chmod(target, 0o755)!
		if pkgcore.hash_file(target)! != sandbox_sha256 { return error('sandbox changed during staging') }
		inputs[sandbox_path] = sandbox_sha256
	}
	for path in [@FILE, guest_source + '/main.v', guest_source + '/launch.v', guest_source + '/maintenance.v', kernel,
		host.v, host.qemu, host.firmware, formatter, debugfs, configuration,
		receipt_path, media_image, guest, cli] {
		physical := os.real_path(path)
		inputs[physical] = pkgcore.hash_file(physical)!
	}
	os.write_file(work + '/inputs.json', json2.encode(inputs) + '\n')!
	runtime := if arch == 'x86_64' { hwhost.Host{ ...host, root: plainiso.prepare(root, work)! } } else { host }
	result := hwhost.run_scenario(runtime, hwhost.Scenario{
		name: 'installed-offline-media'
		arches: [arch]
		cmdline: 'vinix.disk=auto'
		disks: [hwhost.Disk{ name: 'system.vjfs', size_mib: 4096 }]
		qemu: ['-nic', 'none']
		qemu_aarch64: ['-drive', 'if=none,id=packages,format=raw,file={state}/system.vjfs',
			'-device', 'virtio-blk-device,drive=packages']
		qemu_x86_64: ['-drive', 'if=ide,index=0,format=raw,file={state}/system.vjfs']
		reboots: reboots
		ending: .poweroff
		required: [
			'HWTEST PASS clean disk root before offline media attachment',
			'HWTEST PASS receipt-bound media imported and UID 1000 saved its lock on the installed disk',
			'HWTEST PASS detached media and cold boot allowed exact reviewed cache-only installation',
			'HWTEST PASS seven release roots and their complete closure survived another cold boot',
			...if sandbox_path != '' {
				['HWTEST PASS five offline-installed applications ran as UID 1000',
					'HWTEST PASS offline-installed applications reopened unchanged private data after cold boot']
			} else { []string{} },
			...if update_source != '' {
				['HWTEST PASS signed update media populated cache without activating a generation',
					'HWTEST PASS detached update changed only SQLite runtime and rollback restored release',
					'HWTEST PASS rollback, update trust and private data survived offline cold boot']
			} else { []string{} },
		]
		forbidden: ['HWTEST FAIL', 'V panic:', 'Kernel panic', 'running from memory', 'sysdisk: updating the system on']
	}, hwhost.Run{ kernel: kernel, guest: guest, extras: extras, state: boot, timeout: 1500,
		memory_mib: 2048, keep: true })
	os.write_file(work + '/result.json', json2.encode(result) + '\n')!
	if !result.passed || result.interrupted { return error(result.reason) }
	boots := reboots.len + 1
	for boot_number in 0 .. boots {
		argv := json2.decode[[]string](os.read_file(boot + '/qemu-${boot_number}.argv.json')!)!
		for expected_boot, image in attachments {
			if argv.any(it.ends_with('file=' + image)) != (boot_number == expected_boot) {
				return error('unexpected removable media attachment on boot ${boot_number + 1}')
			}
		}
	}
	for path, expected in inputs {
		if pkgcore.hash_file(path)! != expected { return error('qualification input changed: ' + path) }
	}
	println('INSTALLED OFFLINE MEDIA ${arch} ${boots} cold boots PASS (${result.seconds}s)')
}

fn main() {
	if plainiso.requested() { plainiso.build() or { eprintln(err); exit(1) }; return }
	check() or { eprintln(err); exit(1) }
}
