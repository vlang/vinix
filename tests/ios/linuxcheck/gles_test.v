// SPDX-License-Identifier: GPL-2.0-or-later
module linuxcheck

import os
import json2

fn gles_test_sdk(base string) !GlesProfile {
	for header in ['EGL/egl.h', 'EGL/eglext.h', 'GLES2/gl2.h', 'GLES3/gl3.h', 'KHR/khrplatform.h'] {
		path := base + '/usr/include/' + header
		os.mkdir_all(os.dir(path))!
		os.write_file(path, 'intentional header fixture\n')!
	}
	mut elf := []u8{len: 64}
	for i, byte in [u8(0x7f), `E`, `L`, `F`, 2, 1, 1] { elf[i] = byte }
	elf[16] = 3
	elf[18] = 183
	for library in ['libEGL.so', 'libEGL.so.1', 'libGLESv2.so', 'libGLESv2.so.2', 'libEGL_mesa.so.0',
		'libz.so.1', 'dri/swrast_dri.so'] {
		path := base + '/usr/lib/aarch64-linux-gnu/' + library
		os.mkdir_all(os.dir(path))!
		os.write_file_array(path, elf)!
	}
	return gles_profile_at(base)
}

fn test_gles_profile_rejects_wrong_architecture_and_search_path_delimiters() {
	base := os.join_path(os.temp_dir(), 'ios-gles-profile-${os.getpid()}')
	defer { os.rmdir_all(base) or {} }
	profile := gles_test_sdk(base) or { panic(err) }
	assert profile.enabled
	mut bytes := os.read_bytes(profile.driver) or { panic(err) }
	bytes[18] = 62
	os.write_file_array(profile.driver, bytes) or { panic(err) }
	mut refused := false
	gles_profile_at(base) or { refused = err.msg().contains('ARM64 ELF') }
	assert refused
	for delimiter in [':', ','] {
		mut rejected := false
		gles_profile_at(base + delimiter + 'injected') or { rejected = err.msg().contains('delimiters') }
		assert rejected
	}
}

fn test_gles_input_pins_detect_changed_headers_and_refuse_external_aliases() {
	base := os.join_path(os.temp_dir(), 'ios-gles-inputs-${os.getpid()}')
	outside := base + '-external'
	defer {
		os.rmdir_all(base) or {}
		os.rm(outside) or {}
	}
	profile := gles_test_sdk(base) or { panic(err) }
	before := gles_inputs(profile) or { panic(err) }
	assert before.len == 12
	assert before == gles_inputs(profile) or { panic(err) }
	os.write_file(profile.include + '/EGL/egl.h', 'changed\n') or { panic(err) }
	assert before != gles_inputs(profile) or { panic(err) }
	os.write_file(outside, 'not an SDK input') or { panic(err) }
	os.symlink(outside, profile.include + '/EGL/external.h') or { panic(err) }
	mut refused := false
	gles_inputs(profile) or { refused = err.msg().contains('escapes selected SDK') }
	assert refused
}

struct TestEglIcd {
	library_path string
}

struct TestEglVendor {
	file_format_version string
	icd                 TestEglIcd @[json: 'ICD']
}

fn test_gles_execution_environment_removes_capability_and_rasterization_overrides() {
	base := os.join_path(os.temp_dir(), 'ios-gles-env-${os.getpid()} with "quotes"')
	defer { os.rmdir_all(base) or {} }
	profile := gles_test_sdk(base) or { panic(err) }
	mut env := {
		'MESA_GLES_VERSION_OVERRIDE':     '99.0'
		'MESA_EXTENSION_OVERRIDE':        'GL_FAKE_capability'
		'MESA_NO_ERROR':                  '1'
		'MESA_SHADER_READ_PATH':          '/untrusted'
		'GALLIUM_DRIVER':                 'zink'
		'LIBGL_DRIVERS_PATH':             '/host/architecture'
		'__EGL_VENDOR_LIBRARY_FILENAMES': '/host/vendor.json'
		'SOFTPIPE_NO_RAST':               '1'
		'LD_LIBRARY_PATH':                '/host/compiler/libs'
		'UNCHANGED_CONTROL':              'present'
	}
	gles_environment(profile, base, '/cross', mut env) or { panic(err) }
	assert 'MESA_GLES_VERSION_OVERRIDE' !in env
	assert 'MESA_EXTENSION_OVERRIDE' !in env
	assert 'MESA_NO_ERROR' !in env
	assert 'MESA_SHADER_READ_PATH' !in env
	assert 'SOFTPIPE_NO_RAST' !in env
	assert env['GALLIUM_DRIVER'] == 'softpipe'
	assert env['LIBGL_ALWAYS_SOFTWARE'] == 'true'
	assert env['LD_LIBRARY_PATH'] == profile.libraries + ':/cross/lib'
	assert env['UNCHANGED_CONTROL'] == 'present'
	vendor := json2.decode[TestEglVendor](os.read_file(base + '/mesa-vendor.json') or { panic(err) }) or { panic(err) }
	assert vendor.file_format_version == '1.0.0'
	assert vendor.icd.library_path == profile.vendor
}

fn test_gles_coverage_needs_all_distinct_markers() {
	markers := ['IOS-LINUX-GLES-CONTEXTS:', 'IOS-LINUX-GLES-DRAW:', 'IOS-LINUX-GLES-SURFACE:',
		'IOS-LINUX-GLES-THREADS:', 'IOS-LINUX-GLES-CLEANUP:']
	complete := markers.map(it + ' PASS').join('\n')
	require_markers('gles_linux_test.v', complete) or { panic(err) }
	for broken in [markers[..4].join('\n'), complete + '\n' + markers[0], complete + '\nFAIL'] {
		mut refused := false
		require_markers('gles_linux_test.v', broken) or { refused = true }
		assert refused
	}
}

fn test_gles_link_flags_keep_unrelated_linker_scripts_as_inventory_inputs() {
	base := os.join_path(os.temp_dir(), 'ios-gles-link-scripts-${os.getpid()}')
	defer { os.rmdir_all(base) or {} }
	profile := gles_test_sdk(base) or { panic(err) }
	for name in ['libm.so', 'libc.so'] {
		os.write_file(profile.libraries + '/' + name,
			'/* intentional GNU development linker script fixture */ GROUP ( /lib/aarch64-linux-gnu/' + name + '.6 )\n') or { panic(err) }
	}
	inputs := gles_inputs(profile) or { panic(err) }
	assert inputs.len == 14
	flags := gles_link_flags(profile) or { panic(err) }
	assert flags == ['-Wl,-rpath-link,' + profile.libraries,
		profile.libraries + '/libEGL.so', profile.libraries + '/libGLESv2.so']
	for name in ['libm.so', 'libc.so'] {
		path := profile.libraries + '/' + name
		selected := inputs.filter(it.path == path)
		assert selected.len == 1
		assert selected[0].resolved == path
		expected := digest(path) or { panic(err) }
		assert selected[0].sha256 == expected.sha256
	}
	disabled := gles_link_flags(GlesProfile{}) or { panic(err) }
	assert disabled.len == 0
}

fn test_gles_link_flags_resolve_sdk_aliases_to_exact_elf_inputs() {
	base := os.join_path(os.temp_dir(), 'ios-gles-link-aliases-${os.getpid()}')
	defer { os.rmdir_all(base) or {} }
	initial := gles_test_sdk(base) or { panic(err) }
	for names in [['libEGL.so', 'libEGL.so.1', 'libEGL.so.1.1.0'],
		['libGLESv2.so', 'libGLESv2.so.2', 'libGLESv2.so.2.1.0']] {
		os.rm(initial.libraries + '/' + names[0]) or { panic(err) }
		os.mv(initial.libraries + '/' + names[1], initial.libraries + '/' + names[2]) or { panic(err) }
		os.symlink(names[1], initial.libraries + '/' + names[0]) or { panic(err) }
		os.symlink(names[2], initial.libraries + '/' + names[1]) or { panic(err) }
	}
	profile := gles_profile_at(base) or { panic(err) }
	flags := gles_link_flags(profile) or { panic(err) }
	assert flags == ['-Wl,-rpath-link,' + profile.libraries,
		profile.libraries + '/libEGL.so.1.1.0', profile.libraries + '/libGLESv2.so.2.1.0']
	inputs := gles_inputs(profile) or { panic(err) }
	for name in ['libEGL.so', 'libGLESv2.so'] {
		path := profile.libraries + '/' + name
		selected := inputs.filter(it.path == path)
		assert selected.len == 1
		assert selected[0].resolved == os.real_path(path)
		assert selected[0].resolved in flags
	}
}

fn test_gles_link_flags_revalidate_alias_containment_after_profile_selection() {
	base := os.join_path(os.temp_dir(), 'ios-gles-link-escape-${os.getpid()}')
	outside := base + '-external.so'
	defer {
		os.rmdir_all(base) or {}
		os.rm(outside) or {}
	}
	profile := gles_test_sdk(base) or { panic(err) }
	path := profile.libraries + '/libEGL.so'
	bytes := os.read_bytes(path) or { panic(err) }
	os.write_file_array(outside, bytes) or { panic(err) }
	os.rm(path) or { panic(err) }
	os.symlink(outside, path) or { panic(err) }
	mut refused := false
	gles_link_flags(profile) or { refused = err.msg().contains('escapes selected SDK') }
	assert refused
}

fn test_gles_link_flags_reject_required_linker_scripts_after_profile_selection() {
	base := os.join_path(os.temp_dir(), 'ios-gles-link-required-${os.getpid()}')
	defer { os.rmdir_all(base) or {} }
	profile := gles_test_sdk(base) or { panic(err) }
	for name in ['libEGL.so', 'libGLESv2.so'] {
		path := profile.libraries + '/' + name
		bytes := os.read_bytes(path) or { panic(err) }
		os.write_file(path,
			'/* required graphics input deliberately replaced by a linker script */ GROUP ( /lib/aarch64-linux-gnu/' + name + '.1 )\n') or { panic(err) }
		mut refused_link := false
		gles_link_flags(profile) or { refused_link = err.msg().contains('ARM64 ELF') }
		assert refused_link
		mut refused_profile := false
		gles_profile_at(base) or { refused_profile = err.msg().contains('ARM64 ELF') }
		assert refused_profile
		os.write_file_array(path, bytes) or { panic(err) }
	}
}
