// SPDX-License-Identifier: GPL-2.0-or-later
module winehostimages

import os
import json2

fn line(pid string, path string) string {
	return 'dyld[' + pid + ']: <12345678-1234-1234-1234-123456789ABC> ' + path + '\n'
}

fn test_observed_identities_and_explicit_os_boundary() {
	text := line('12', '/opt/tool') + line('13', '/opt/tool') + line('12', '/usr/lib/libSystem.B.dylib') + 'dyld[12]: move loaded to delayed: tool\n'
	images := trace(text)!
	assert images.len == 2 && images[0].path == '/opt/tool'
	for bad in ['', text + 'unparsed\n', line('x', '/opt/tool'), line('1', '/opt/../tool'),
		text.replace('12345678-', 'g2345678-'), text.replace('\n', '\r\n'), text + '\x00',
		text + 'dyld[12]: move loaded to delayed: unknown\n'] {
		mut refused := false
		trace(bad) or { refused = true }
		assert refused
	}
	mut refused := false
	compatible([Image{path: '/opt/other', uuid: images[0].uuid, sha256: 'hash'}], images) or { refused = true }
	assert refused
	refused = false
	compatible([Image{path: '/usr/lib/libSystem.B.dylib', uuid: images[1].uuid, sha256: 'invented'}], images) or { refused = true }
	assert refused
}

fn test_real_managed_child_ignores_parent_loader_injection() {
	$if !macos { return }
	if !os.exists(clang) || !os.exists(linker) { return }
	external := os.getenv('VINIX_HOST_IMAGE_TEST_STATE')
	root := if external != '' { os.abs_path(external) } else { os.real_path(os.temp_dir()) + '/vinix-host-images-' + os.getpid().str() }
	if os.exists(root) { panic('fresh host image test state required') }
	os.mkdir_all(root)!
	defer { if external == '' { os.rmdir_all(root) or {} } }
	previous := os.getenv_opt('DYLD_INSERT_LIBRARIES')
	os.setenv('DYLD_INSERT_LIBRARIES', '/definitely-absent-parent-injection.dylib', true)
	defer {
		if value := previous { os.setenv('DYLD_INSERT_LIBRARIES', value, true) }
		else { os.unsetenv('DYLD_INSERT_LIBRARIES') }
	}
	invoke([clang, '--version'], root, root + '/cc.log')!
	baseline := json2.decode[Baseline](os.read_file(root + '/host-images-before.json')!)!
	assert baseline.images.any(!system(it.path) && it.sha256.len == 64)
	assert json2.decode[map[string]string](os.read_file(root + '/cc.log.environment.json')!)! == environment(root)
	assert 'DYLD_INSERT_LIBRARIES' !in environment(root)
	admit_names(root, root, ['cc.log'])!
	mut poisoned := environment(root)
	poisoned['CPATH'] = '/unrecorded'
	os.write_file(root + '/cc.log.environment.json', json2.encode(poisoned))!
	mut refused := false
	admit_names(root, root, ['cc.log']) or { refused = true }
	assert refused
}
