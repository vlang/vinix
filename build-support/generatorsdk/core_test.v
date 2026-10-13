// SPDX-License-Identifier: GPL-2.0-or-later
module generatorsdk

import os

#include <stdlib.h>
fn C.mkdtemp(&u8) &char

fn fixture() string {
	mut pattern := '/private/tmp/vinix-generator-sdk.XXXXXX\x00'.bytes()
	assert C.mkdtemp(pattern.data) != unsafe { nil }
	return pattern.bytestr().all_before('\x00')
}

fn installed(site string, name string, version string, module_path string) {
	directory := site + '/' + name + '-' + version + '.dist-info'
	os.mkdir_all(directory) or { panic(err) }
	os.write_file(directory + '/METADATA', 'Metadata-Version: 2.1\r\nName: ' + name + '\r\nVersion: ' + version + '\r\n\r\n') or { panic(err) }
	os.mkdir_all(os.dir(site + '/' + module_path)) or { panic(err) }
	// Inert SDK module data; never create or execute Python source in a fixture.
	os.write_file(directory + '/module-data', '') or { panic(err) }
	os.symlink(directory + '/module-data', site + '/' + module_path) or { panic(err) }
}

fn remove_fixture(path string) {
	if os.is_link(path) || os.is_file(path) { os.rm(path) or { panic(err) }; return }
	for name in os.ls(path) or { panic(err) } { remove_fixture(path + '/' + name) }
	os.rmdir(path) or { panic(err) }
}

fn test_qemu_sdk_keeps_selected_prefix_pin_and_never_executes_interpreter() {
	work := fixture()
	defer { remove_fixture(work) }
	prefix := work + '/SDK with spaces 漢字'
	os.mkdir_all(prefix + '/bin') or { panic(err) }
	// If the verifier launches this selected executable it fails the test.
	os.symlink('/usr/bin/false', prefix + '/bin/python3') or { panic(err) }
	executable := prefix + '/bin/python3'
	site := prefix + '/lib/python3.12/site-packages'
	installed(site, 'tomli', '2.2.1', 'tomli/__init__.py')
	assert verify('qemu', executable) or { panic(err) } == executable
	metadata_path := site + '/tomli-2.2.1.dist-info/METADATA'
	for text in ['Name: tomli\nVersion: 2.2.0\n', 'Name: tomli\nVersion: 2.2.1\nVersion: 2.2.1\n', 'Name: other\nVersion: 2.2.1\n', '\xff'] {
		os.write_file(metadata_path, text) or { panic(err) }
		mut rejected := false
		verify('qemu', executable) or { rejected = true }
		assert rejected
	}
	os.write_file(metadata_path, 'Name: tomli\nVersion: 2.2.1\n') or { panic(err) }
	os.mkdir_all(site + '/tomli-9.dist-info') or { panic(err) }
	mut rejected := false
	verify('qemu', executable) or { rejected = true }
	assert rejected
	os.rmdir(site + '/tomli-9.dist-info') or { panic(err) }
	os.rm(site + '/tomli/__init__.py') or { panic(err) }
	rejected = false
	verify('qemu', executable) or { rejected = true }
	assert rejected
}

fn test_virgl_distributions_aliases_ambiguity_and_missing_executables() {
	work := fixture()
	defer { remove_fixture(work) }
	os.mkdir_all(work + '/bin') or { panic(err) }
	os.symlink('/usr/bin/false', work + '/bin/meson') or { panic(err) }
	site := work + '/lib/python3.12/site-packages'
	installed(site, 'meson', '1.11.2', 'mesonbuild/__init__.py')
	installed(site, 'PyYAML', '6.0.3', 'yaml/__init__.py')
	assert verify('virgl', work + '/bin/meson') or { panic(err) } == work + '/bin/meson'
	os.symlink(work + '/lib', work + '/lib64') or { panic(err) }
	assert verify('virgl', work + '/bin/meson') or { panic(err) } == work + '/bin/meson'
	os.mkdir_all(work + '/lib/python3.13/site-packages') or { panic(err) }
	for pair in [['virgl', work + '/bin/meson'], ['qemu', work + '/missing'], ['bad', work + '/bin/meson']] {
		mut rejected := false
		verify(pair[0], pair[1]) or { rejected = true }
		assert rejected
	}
}
