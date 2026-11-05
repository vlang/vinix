// SPDX-License-Identifier: GPL-2.0-or-later
module linuxcheck

import os
import json2

fn cxx_test_backend(root string) ! {
	os.mkdir_all(root + '/include/c++/v1/__thread/support')!
	sysroot := root + '/gnu-sysroot'
	resource := root + '/clang-resource'
	os.mkdir_all(sysroot + '/include/bits')!
	os.mkdir_all(resource + '/include')!
	mut sysroot_headers := map[string]string{}
	mut resource_headers := map[string]string{}
	for name in ['stdio.h', 'bits/native-state.h', '.hidden-platform.h'] {
		os.write_file(sysroot + '/include/' + name, 'synthetic GNU declaration: ${name}\n')!
		sysroot_headers[name] = digest(sysroot + '/include/' + name)!.sha256
	}
	for name in ['stddef.h', '__stddef_size_t.h'] {
		os.write_file(resource + '/include/' + name, 'synthetic Clang declaration: ${name}\n')!
		resource_headers[name] = digest(resource + '/include/' + name)!.sha256
	}
	for name in ['__config', '__config_site', '__locale', '__thread/support/pthread.h', 'string',
		'sstream'] {
		os.write_file(root + '/include/c++/v1/' + name, 'synthetic header: profile validation only\n')!
	}
	mut artifacts := map[string]string{}
	mut headers := []FileDigest{}
	inventory_files(root + '/include/c++/v1', '', mut headers)!
	for header in headers { artifacts['include/c++/v1/' + header.path] = header.sha256 }
	for name in ['libcxx-ios.a', 'libc++abi.a', 'libunwind.a', 'apple-gnu-abi.h',
		'gnu-cxx-abi-probe.cpp', 'gnu-cxx-sanitizer-control.cpp'] {
		os.write_file(root + '/' + name, if name.ends_with('.a') {
			'!<arch>\n'
		} else {
			'synthetic preamble\n'
		})!
		artifacts[name] = digest(root + '/' + name)!.sha256
	}
	os.write_file(root + '/gnu-cxx.json', json2.encode(CxxBuildManifest{
		target:                'aarch64-linux-gnu'
		llvm_version:          '19.1.7'
		sanitizers:            true
		compiler_resource_dir: resource
		sysroot:               sysroot
		sysroot_headers:       sysroot_headers
		resource_headers:      resource_headers
		artifacts:             artifacts
	}))!
}

fn test_cxx_profile_requires_matching_target_sanitizers_and_archive_bytes() {
	root := os.join_path(os.temp_dir(), 'vinix-cxx-profile-${os.getpid()}')
	defer { os.rmdir_all(root) or {} }
	cxx_test_backend(root) or { panic(err) }
	profile := cxx_profile_at(root, true) or { panic(err) }
	assert profile.enabled && profile.libraries.len == 3
	mut refused := false
	cxx_profile_at(root, false) or { refused = err.msg().contains('sanitizer profile') }
	assert refused
	manifest := os.read_file(root + '/gnu-cxx.json') or { panic(err) }
	os.write_file(root + '/gnu-cxx.json', manifest.replace('aarch64-linux-gnu', 'aarch64-linux-musl')) or { panic(err) }
	refused = false
	cxx_profile_at(root, true) or { refused = err.msg().contains('ARM64/glibc') }
	assert refused
	os.write_file(root + '/gnu-cxx.json', manifest) or { panic(err) }
	os.write_file(root + '/libcxx-ios.a', '!<arch>\nchanged payload') or { panic(err) }
	refused = false
	cxx_profile_at(root, true) or { refused = err.msg().contains('differs from its build manifest') }
	assert refused
}

fn test_cxx_inputs_cover_headers_and_reject_external_aliases() {
	root := os.join_path(os.temp_dir(), 'vinix-cxx-inputs-${os.getpid()}')
	defer { os.rmdir_all(root) or {} }
	cxx_test_backend(root) or { panic(err) }
	profile := cxx_profile_at(root, true) or { panic(err) }
	before := cxx_inputs(profile) or { panic(err) }
	assert before.len == 18
	assert before.any(it.path == profile.manifest.sysroot + '/include/.hidden-platform.h')
	assert before.any(it.path == profile.manifest.compiler_resource_dir + '/include/stddef.h')
	os.write_file(profile.include + '/__locale', 'changed mask layout') or { panic(err) }
	assert cxx_inputs(profile) or { panic(err) } != before
	os.rm(profile.include + '/string') or { panic(err) }
	os.symlink(root + '/apple-gnu-abi.h', profile.include + '/string') or { panic(err) }
	mut refused := false
	cxx_profile_at(root, true) or { refused = err.msg().contains('regular files') }
	assert refused
	for path in ['../outside', '/absolute', 'include//string', 'include/./string'] {
		refused = false
		cxx_regular(root, path) or { refused = true }
		assert refused
	}
}

fn test_cxx_external_header_maps_are_required_and_cannot_escape_their_roots() {
	root := os.join_path(os.temp_dir(), 'vinix-cxx-header-maps-${os.getpid()}')
	defer { os.rmdir_all(root) or {} }
	cxx_test_backend(root) or { panic(err) }
	manifest_path := root + '/gnu-cxx.json'
	manifest := json2.decode[CxxBuildManifest](os.read_file(manifest_path) or { panic(err) }) or { panic(err) }
	for changed in [
		CxxBuildManifest{ ...manifest, sysroot_headers: map[string]string{} },
		CxxBuildManifest{ ...manifest, resource_headers: map[string]string{} },
		CxxBuildManifest{ ...manifest, compiler_resource_dir: '' },
		CxxBuildManifest{
			...manifest
			sysroot_headers: {
				'../outside.h': manifest.sysroot_headers['stdio.h']
			}
		},
	] {
		os.write_file(manifest_path, json2.encode(changed)) or { panic(err) }
		mut refused := false
		cxx_profile_at(root, true) or { refused = true }
		assert refused
	}
}

fn test_cxx_external_header_mutations_fail_initial_and_final_qualification() {
	root := os.join_path(os.temp_dir(), 'vinix-cxx-header-mutation-${os.getpid()}')
	defer { os.rmdir_all(root) or {} }
	cxx_test_backend(root) or { panic(err) }
	profile := cxx_profile_at(root, true) or { panic(err) }
	before := cxx_inputs(profile) or { panic(err) }
	for path in [profile.manifest.sysroot + '/include/stdio.h',
		profile.manifest.compiler_resource_dir + '/include/stddef.h'] {
		original := os.read_file(path) or { panic(err) }
		os.write_file(path, original + 'changed native declaration\n') or { panic(err) }
		mut refused := false
		cxx_profile_at(root, true) or { refused = err.msg().contains('header differs from its build manifest') }
		assert refused
		refused = false
		cxx_inputs(profile) or { refused = err.msg().contains('header differs from its build manifest') }
		assert refused
		os.write_file(path, original) or { panic(err) }
		assert cxx_inputs(profile) or { panic(err) } == before
	}
}

fn test_cxx_external_header_completeness_and_aliases_are_checked() {
	root := os.join_path(os.temp_dir(), 'vinix-cxx-header-completeness-${os.getpid()}')
	defer { os.rmdir_all(root) or {} }
	cxx_test_backend(root) or { panic(err) }
	profile := cxx_profile_at(root, true) or { panic(err) }
	before := cxx_inputs(profile) or { panic(err) }
	for prefix in [profile.manifest.sysroot, profile.manifest.compiler_resource_dir] {
		extra := prefix + '/include/.unrecorded.h'
		os.write_file(extra, 'unexpected hidden declaration\n') or { panic(err) }
		mut refused := false
		cxx_inputs(profile) or { refused = err.msg().contains('header set differs') }
		assert refused
		os.rm(extra) or { panic(err) }
		name := if prefix == profile.manifest.sysroot { 'stdio.h' } else { 'stddef.h' }
		path := prefix + '/include/' + name
		original := os.read_file(path) or { panic(err) }
		os.rm(path) or { panic(err) }
		refused = false
		cxx_inputs(profile) or { refused = true }
		assert refused
		os.write_file(root + '/outside.h', original) or { panic(err) }
		os.symlink(root + '/outside.h', path) or { panic(err) }
		refused = false
		cxx_inputs(profile) or { refused = err.msg().contains('regular files') }
		assert refused
		os.rm(path) or { panic(err) }
		os.write_file(path, original) or { panic(err) }
		assert cxx_inputs(profile) or { panic(err) } == before
	}
}

fn test_cxx_manifest_cannot_substitute_an_unrelated_file_for_the_conversion_probe() {
	root := os.join_path(os.temp_dir(), 'vinix-cxx-probe-manifest-${os.getpid()}')
	defer { os.rmdir_all(root) or {} }
	cxx_test_backend(root) or { panic(err) }
	os.cp(root + '/gnu-cxx-abi-probe.cpp', root + '/unrelated.txt') or { panic(err) }
	manifest := os.read_file(root + '/gnu-cxx.json') or { panic(err) }
	os.write_file(root + '/gnu-cxx.json', manifest.replace('gnu-cxx-abi-probe.cpp', 'unrelated.txt')) or { panic(err) }
	mut refused := false
	cxx_profile_at(root, true) or { refused = err.msg().contains('conversion probe differs') }
	assert refused
}

fn test_cxx_coverage_cannot_pass_with_backend_disabled_or_missing_join_case() {
	markers := ['IOS-LINUX-CXX-SYMBOLS:', 'IOS-LINUX-CXX-STRINGS:', 'IOS-LINUX-CXX-LOCALE:',
		'IOS-LINUX-CXX-CONVERSIONS:', 'IOS-LINUX-CXX-THREADS:', 'IOS-LINUX-CXX-CLEANUP:']
	complete := markers.map(it + ' PASS').join('\n')
	require_markers('cxx_linux_test.v', complete) or { panic(err) }
	for output in ['', markers[..3].join('\n'), complete + '\n' + markers[3], complete + '\nFAIL'] {
		mut refused := false
		require_markers('cxx_linux_test.v', output) or { refused = true }
		assert refused
	}
}

fn test_native_constructor_lifetime_adapter_preserves_reference_comparisons() {
	original := os.read_file(os.join_path(os.dir(@FILE), '..', 'cxx-extended.cpp')) or { panic(err) }
	adapted := cxx_native_fixture_source(original) or { panic(err) }
	assert adapted.split_into_lines().filter(it.trim_space().starts_with('CHECK(')) ==
		original.split_into_lines().filter(it.trim_space().starts_with('CHECK('))
	assert adapted.all_after('static int integer_sorts()') == original.all_after('static int integer_sorts()')
	assert !adapted.contains('std::string short_string;') && !adapted.contains('std::string filled;')
	assert adapted.count('~VinixLegacyStringStorage() { if (initialized) string_destroy_base(bytes); }') == 1
	assert adapted.count('short_storage.initialized = true;') == 1
	assert adapted.count('filled_storage.initialized = true;') == 1
	for changed in [
		original.replace('std::string short_string;', 'std::string other_name;'),
		original + '\nstatic int strings() {',
	] {
		mut refused := false
		cxx_native_fixture_source(changed) or { refused = err.msg().contains('lifetime anchor') }
		assert refused
	}
}
