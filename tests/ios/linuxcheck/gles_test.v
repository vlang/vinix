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
