// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn test_setup_vendor_metadata_selects_the_full_app_for_the_right_architecture() {
	metadata := '{"assets":[{"name":"VSCodium-linux-x64-1.tar.gz","browser_download_url":"https://github.com/VSCodium/vscodium/releases/download/1/x64.tar.gz"},{"name":"VSCodium-linux-arm64-1.tar.gz","browser_download_url":"https://github.com/VSCodium/vscodium/releases/download/1/arm64.tar.gz","digest":"sha256:abc"}]}'
	asset := first_run_release_download(metadata, 'VSCodium-linux-arm64-', '.tar.gz')!
	assert asset.url.ends_with('/arm64.tar.gz')
	assert asset.sha256 == 'abc'
	if _ := first_run_release_download(metadata, 'vscodium-reh-', '.tar.gz') {
		assert false
	}
	assert first_run_slack_download('<iframe src="https://downloads.slack-edge.com/desktop-releases/linux/x64/1/slack-desktop-1-amd64.deb">')!.ends_with('-amd64.deb')
	if _ := first_run_slack_download('<a href="https://other.example/slack-amd64.deb">') {
		assert false
	}
}

fn test_setup_runtime_resolution_handles_alternatives_providers_and_cycles() {
	index := 'Package: application\nFilename: pool/application.deb\nDepends: unavailable | library:any (>= 2), virtual-api\n\nPackage: library\nFilename: pool/library.deb\nPre-Depends: application\n\nPackage: provider\nFilename: pool/provider.deb\nProvides: virtual-api (= 1)\n\nPackage: ignored\nFilename: ../../escape.deb\n'
	packages := first_run_debian_packages(index)
	assert packages.len == 3
	selected := first_run_debian_resolve(packages, ['application'])!
	assert selected.map(it.name) == ['application', 'library', 'provider']
	if _ := first_run_debian_resolve(packages, ['missing']) {
		assert false
	}
}

fn test_setup_vendor_archive_verification_and_atomic_publication() {
	root := os.join_path(os.temp_dir(), 'vinix-vendor-install-${os.getpid()}')
	os.mkdir_all(root + '/source')!
	defer { os.rmdir_all(root) or {} }
	mut elf := []u8{len: 64}
	elf[0] = 127
	elf[1] = `E`
	elf[2] = `L`
	elf[3] = `F`
	elf[4] = 2
	elf[5] = 1
	elf[6] = 1
	elf[16] = 2
	elf[18] = 183
	os.write_file_array(root + '/source/codium', elf)!
	os.chmod(root + '/source/codium', 0o755)!
	archive := root + '/codium.tar.gz'
	first_run_tool(['/usr/bin/tar', '-czf', archive, '-C', root + '/source', '.'])!
	bad := FirstRunDownload{ binary: 'codium', arch: 'aarch64', command: 'codium', sha256: '0'.repeat(64) }
	if _ := first_run_stage_vendor(bad, archive, root + '/rejected', false) {
		assert false
	}
	assert !os.exists(root + '/rejected')
	wrong_arch := FirstRunDownload{ ...bad, sha256: first_run_file_hash(archive)!, arch: 'x86_64' }
	if _ := first_run_stage_vendor(wrong_arch, archive, root + '/wrong-arch', false) {
		assert false
	}
	assert !os.exists(root + '/usr/bin/codium')
	valid := FirstRunDownload{ ...wrong_arch, arch: 'aarch64' }
	first_run_stage_vendor(valid, archive, root + '/payload', false)!
	first_run_publish_vendor('vscodium', valid, root + '/payload', root)!
	assert os.read_bytes(root + '/opt/vinix-apps/vscodium/codium')! == elf
	assert os.readlink(root + '/usr/bin/codium')! == '/usr/bin/vinix-desktop'
	assert os.read_file(root + '/usr/share/applications/vinix-vscodium.desktop')!.contains('--run-setup-app vscodium')
	assert os.read_file(root + '/var/lib/vinix-pkg/vscodium.files')!.contains('opt/vinix-apps/vscodium')
	// A failed replacement cannot discard the already installed client.
	if _ := first_run_publish_vendor('vscodium', valid, root + '/missing', root) {
		assert false
	}
	assert os.read_bytes(root + '/opt/vinix-apps/vscodium/codium')! == elf
	assert !os.exists(root + '/opt/vinix-apps/.vscodium-previous')
	// Debian payloads use the same validation and never execute control hooks.
	data_archive := root + '/data.tar.gz'
	first_run_tool(['/usr/bin/tar', '-czf', data_archive, '-C', root + '/source', '.'])!
	deb := root + '/codium.deb'
	data := os.read_bytes(data_archive)!
	size := data.len.str()
	header := 'data.tar.gz/' + ' '.repeat(4) + '0' + ' '.repeat(11) +
		'0' + ' '.repeat(5) + '0' + ' '.repeat(5) + '100644  ' +
		size + ' '.repeat(10 - size.len) + '`\n'
	assert header.len == 60
	mut container := '!<arch>\n'.bytes()
	container << header.bytes()
	container << data
	if data.len % 2 != 0 { container << u8(`\n`) }
	os.write_file_array(deb, container)!
	deb_download := FirstRunDownload{ ...valid, deb: true, sha256: first_run_file_hash(deb)! }
	first_run_stage_vendor(deb_download, deb, root + '/deb-payload', false)!
	assert os.read_bytes(root + '/deb-payload/codium')! == elf
	assert !os.exists(root + '/deb-payload/.deb-data')
}
