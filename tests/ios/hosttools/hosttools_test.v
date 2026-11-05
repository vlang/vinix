// SPDX-License-Identifier: GPL-2.0-or-later
module hosttools

import os
import time

fn test_linux_uses_arm64_emulation_without_host_cpu_assumptions() {
	for arch in ['amd64', 'arm64'] {
		accel, cpu := acceleration('linux', arch, '') or { panic(err) }
		assert accel == 'tcg' && cpu == 'max'
	}
	accel, cpu := acceleration('macos', 'arm64', '') or { panic(err) }
	assert accel == 'hvf' && cpu == 'host'
	kvm, kvm_cpu := acceleration('linux', 'arm64', 'kvm') or { panic(err) }
	assert kvm == 'kvm' && kvm_cpu == 'host'
	for input in [['linux', 'amd64', 'kvm'], ['linux', 'arm64', 'hvf'], ['macos', 'arm64', 'kvm'],
		['linux', 'amd64', 'bad']] {
		if _, _ := acceleration(input[0], input[1], input[2]) {
			assert false
		}
	}
}

fn test_explicit_invalid_tool_does_not_fall_back() {
	variable := 'VINIX_IOS_HOSTTOOLS_TEST_EXECUTABLE'
	previous := os.getenv_opt(variable)
	defer {
		if value := previous { os.setenv(variable, value, true) } else { os.unsetenv(variable) }
	}
	os.setenv(variable, '/definitely-absent/ios-host-tool', true)
	if _ := executable(variable, ['/bin/sh']) {
		assert false
	}
	os.setenv(variable, '', true)
	if _ := executable(variable, ['/bin/sh']) {
		assert false
	}
	os.unsetenv(variable)
	assert executable(variable, ['/bin/sh']) or { panic(err) } == os.abs_path('/bin/sh')
}

fn test_sparse_file_size_zero_bytes_and_exclusive_creation() {
	work := os.join_path(os.temp_dir(), 'vinix-ios-hosttools-${os.getpid()}-${time.sys_mono_now()}')
	os.mkdir(work) or { panic(err) }
	defer { os.rmdir_all(work) or { panic(err) } }
	path := work + '/disk.img'
	bytes := u64(64 * 1024 * 1024)
	sparse_file(path, bytes) or { panic(err) }
	assert os.file_size(path) == bytes
	assert firmware_file(path) or { panic(err) } == os.real_path(path)
	mut input := os.open(path) or { panic(err) }
	mut data := []u8{len: 32}
	assert input.read(mut data) or { panic(err) } == data.len
	assert data.all(it == 0)
	input.seek(i64(bytes - u64(data.len)), .start) or { panic(err) }
	assert input.read(mut data) or { panic(err) } == data.len
	assert data.all(it == 0)
	input.close()
	if _ := sparse_file(path, 4096) {
		assert false
	}
	assert os.file_size(path) == bytes
	os.symlink(work + '/missing', work + '/link') or { panic(err) }
	if _ := sparse_file(work + '/link', 4096) {
		assert false
	}
	assert os.is_link(work + '/link') && !os.exists(work + '/missing')
	if _ := sparse_file(work + '/zero', 0) {
		assert false
	}
	if _ := sparse_file(work + '/overflow', u64(0x8000000000000000)) {
		assert false
	}
	assert !os.exists(work + '/zero') && !os.exists(work + '/overflow')
	os.write_file(work + '/short-firmware', 'short') or { panic(err) }
	if _ := firmware_file(work + '/short-firmware') {
		assert false
	}
}

fn test_archive_tool_requires_libarchive_overlay_support() {
	variable := 'VINIX_IOS_BSDTAR'
	previous := os.getenv_opt(variable)
	defer {
		if value := previous { os.setenv(variable, value, true) } else { os.unsetenv(variable) }
	}
	// A successful process exit alone must not qualify an unrelated executable.
	os.setenv(variable, '/usr/bin/true', true)
	if _ := bsdtar() {
		assert false
	}
}

fn test_ca_bundle_uses_host_default_and_validates_explicit_override() {
	assert default_ca_bundle('linux') or { panic(err) } == '/etc/ssl/certs/ca-certificates.crt'
	assert default_ca_bundle('macos') or { panic(err) } == '/etc/ssl/cert.pem'
	if _ := default_ca_bundle('unknown') {
		assert false
	}
	variable := 'VINIX_IOS_CA_BUNDLE'
	previous := os.getenv_opt(variable)
	defer {
		if value := previous { os.setenv(variable, value, true) } else { os.unsetenv(variable) }
	}
	os.unsetenv(variable)
	selected := ca_bundle() or { panic(err) }
	assert selected == os.real_path(default_ca_bundle(platform()) or { panic(err) })
	work := os.join_path(os.temp_dir(), 'vinix-ios-ca-${os.getpid()}-${time.sys_mono_now()}')
	os.mkdir(work) or { panic(err) }
	defer { os.rmdir_all(work) or { panic(err) } }
	copy := work + '/certificates.pem'
	os.cp(selected, copy) or { panic(err) }
	os.setenv(variable, copy, true)
	assert ca_bundle() or { panic(err) } == os.real_path(copy)
	for value in ['', work + '/absent', work] {
		os.setenv(variable, value, true)
		if _ := ca_bundle() {
			assert false
		}
	}
	os.setenv(variable, copy, true)
	for content in ['', 'not a certificate', '-----BEGIN CERTIFICATE-----\nunclosed'] {
		os.write_file(copy, content) or { panic(err) }
		if _ := ca_bundle() {
			assert false
		}
	}
}

fn test_qemu_drive_paths_escape_option_separators() {
	assert qemu_drive_file('/external/firmware.fd') or { panic(err) } == '/external/firmware.fd'
	assert qemu_drive_file('/external/a,b,readonly=off/firmware.fd') or { panic(err) } ==
		'/external/a,,b,,readonly=off/firmware.fd'
	assert qemu_drive_file('/external/space path=a,,b/boot.img') or { panic(err) } ==
		'/external/space path=a,,,,b/boot.img'
	for invalid in ['', '/external/a\n', '/external/a\r', '/external/a\x00b'] {
		if _ := qemu_drive_file(invalid) {
			assert false
		}
	}
}
