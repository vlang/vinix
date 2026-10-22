// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import crypto.sha256
import json2
import os

// Supply the real Khronos loader for APKs which link Vulkan even when they
// select GLES at runtime. No ICD is installed: vkCreateInstance must report
// VK_ERROR_INCOMPATIBLE_DRIVER rather than advertise a working Vulkan device.
fn build_native_vulkan_loader(output string, compiler string, arch string) ! {
	if arch != 'arm64' { return error('native Vulkan loader requires arm64') }
	work := output + '/vulkan-build'
	provider := output + '/vulkan-ws'
	os.mkdir_all(work)!
	os.mkdir_all(provider + '/licenses')!
	name := 'vulkan-loader-1.3.261.1-r0.apk'
	url := 'https://dl-cdn.alpinelinux.org/alpine/v3.19/main/aarch64/' + name
	archive_hash := '7c3db97d4d351c8b3932fe59d86c78ab8a495cadc6027c0ba7a702d272ef9be3'
	archive := work + '/' + name
	ws_fetch(archive, url, archive_hash)!
	checked(['tar', '-xf', archive, '-C', work, 'usr/lib'])!
	binary := work + '/usr/lib/libvulkan.so.1.3.261'
	data := os.read_bytes(binary)!
	if data.len < 64 || data[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
		|| data[18] != 183 || data[19] != 0 {
		return error('unexpected Vulkan loader ELF architecture')
	}
	dynamic := checked([compiler.replace('gcc', 'readelf'), '-d', binary])!.stdout
	mut needed := []string{}
	for line in dynamic.split_into_lines() {
		if line.contains('(NEEDED)') { needed << line.all_after('[').all_before(']') }
	}
	if needed != ['libc.musl-aarch64.so.1'] || !dynamic.contains('[libvulkan.so.1]') {
		return error('unexpected Vulkan loader ELF dependency closure: ' + needed.join(', '))
	}
	os.cp(binary, provider + '/libvulkan.so.1')!
	// Retain the exact upstream source and all embedded permissive notices,
	// including third-party JSON and generated loader code copyright notices.
	source_hash := 'f85f0ea57b63750d4ddaf6c8649df781c4777006daa3cd772b01e7b5ed02f3f2'
	source_url := 'https://codeload.github.com/KhronosGroup/Vulkan-Loader/tar.gz/refs/tags/sdk-1.3.261.1'
	source := provider + '/licenses/vulkan-loader-sdk-1.3.261.1.tar.gz'
	ws_fetch(source, source_url, source_hash)!
	license := checked(['tar', '-xOf', source, 'Vulkan-Loader-sdk-1.3.261.1/LICENSE.txt'])!.stdout
	os.write_file(provider + '/licenses/vulkan-loader-LICENSE', license)!
	receipt := {
		'archive_url':            json2.Any(url)
		'archive_sha256':         json2.Any(archive_hash)
		'package_metadata':       json2.Any(checked(['tar', '-xOf', archive, '.PKGINFO'])!.stdout)
		'upstream_source_url':    json2.Any(source_url)
		'upstream_source_sha256': json2.Any(source_hash)
		'libvulkan.so.1_sha256':  json2.Any(sha256.sum(data).hex())
		'license_sha256':         json2.Any(sha256.sum(license.bytes()).hex())
		'needed':                 json2.Any(needed.map(json2.Any(it)))
		'scope':                  json2.Any('Khronos Vulkan 1.3.261 loader. No ICD or Vulkan rendering/presentation support. Only musl is needed; no X11, GTK or Wayland dependency.')
	}
	encoded := json2.encode(receipt, prettify: true) + '\n'
	os.write_file(output + '/vulkan-ws-manifest.json', encoded)!
	os.write_file(provider + '/licenses/vulkan-loader-build.json', encoded)!
}
