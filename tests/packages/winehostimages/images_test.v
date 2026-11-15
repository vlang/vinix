// SPDX-License-Identifier: GPL-2.0-or-later
module winehostimages

import os
import json2
import tests.packages.winesource

// The pinned compiler omits assert statements in -prod builds.
fn require_check(ok bool) { if !ok { panic('WINE helper control failed') } }
fn require_refusal(ok bool) { if !ok { panic('WINE helper expected refusal') } }

fn line(pid string, path string) string {
	return 'dyld[' + pid + ']: <12345678-1234-1234-1234-123456789ABC> ' + path + '\n'
}

fn test_observed_identities_and_explicit_os_boundary() {
	text := line('12', '/opt/tool') + line('13', '/opt/tool') + line('12', '/usr/lib/libSystem.B.dylib') + 'dyld[12]: move loaded to delayed: tool\n'
	images := trace(text)!
	require_check(images.len == 2 && images[0].path == '/opt/tool')
	for bad in ['', text + 'unparsed\n', line('x', '/opt/tool'), line('1', '/opt/../tool'),
		text.replace('12345678-', 'g2345678-'), text.replace('\n', '\r\n'), text + '\x00',
		text + 'dyld[12]: move loaded to delayed: unknown\n'] {
		mut refused := false
		trace(bad) or { refused = true }
		require_refusal(refused)
	}
	mut refused := false
	compatible([Image{path: '/opt/other', uuid: images[0].uuid, sha256: 'hash'}], images) or { refused = true }
	require_refusal(refused)
	refused = false
	compatible([Image{path: '/usr/lib/libSystem.B.dylib', uuid: images[1].uuid, sha256: 'invented'}], images) or { refused = true }
	require_refusal(refused)
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
	require_check(baseline.images.any(!system(it.path) && it.sha256.len == 64))
	require_check(json2.decode[map[string]string](os.read_file(root + '/cc.log.environment.json')!)! == environment(root))
	require_check('DYLD_INSERT_LIBRARIES' !in environment(root))
	admit_names(root, root, ['cc.log'])!
	mut poisoned := environment(root)
	poisoned['CPATH'] = '/unrecorded'
	os.write_file(root + '/cc.log.environment.json', json2.encode(poisoned))!
	mut refused := false
	admit_names(root, root, ['cc.log']) or { refused = true }
	require_refusal(refused)
}

fn test_optional_real_v_source_generation_ignores_parent_settings() {
	tool := os.getenv('VINIX_V_HOST_TEST_COMPILER')
	if tool == '' { return }
	root := os.abs_path(os.getenv('VINIX_V_HOST_TEST_STATE'))
	if os.getenv('VINIX_V_HOST_TEST_STATE') == '' || os.exists(root) { panic('fresh external V host state required') }
	os.mkdir_all(root)!
	mut previous := map[string]string{}
	mut present := map[string]bool{}
	for key in ['VFLAGS', 'VMODULES', 'VEXE', 'DYLD_INSERT_LIBRARIES'] {
		if value := os.getenv_opt(key) { previous[key] = value; present[key] = true }
		os.setenv(key, if key == 'VFLAGS' { '-definitely-invalid-parent-flag' } else { '/definitely-absent-parent-setting' }, true)
	}
	defer {
		for key in ['VFLAGS', 'VMODULES', 'VEXE', 'DYLD_INSERT_LIBRARIES'] {
			if present[key] { os.setenv(key, previous[key], true) } else { os.unsetenv(key) }
		}
	}
	os.write_file(root + '/program.v', 'module main\nfn main() { println("closed V environment") }\n')!
	base := [tool, '-backend', 'c', '-prod', '-os', 'linux', '-arch', 'amd64', '-gc', 'none', '-manualfree', '-o', root + '/program.c', root + '/program.v']
	mut discover := base.clone(); discover.insert(1, ['-print-watched-files', '-dump-files', root + '/sources-before.txt'])
	invoke_v(discover, root, root + '/discover.log')!
	mut compile := base.clone(); compile.insert(1, ['-dump-files', root + '/sources-built.txt'])
	invoke_v(compile, root, root + '/v.log')!
	inputs := {tool: winesource.file_digest(tool)!}
	admit_v(root, root, tool, inputs)!
	require_check(os.is_file(root + '/program.c'))
	require_check(os.read_file(root + '/sources-before.txt')! == os.read_file(root + '/sources-built.txt')!)
	mut poisoned := v_environment(root, tool)
	poisoned['VFLAGS'] = '-unrecorded'
	os.write_file(root + '/v.log.environment.json', json2.encode(poisoned))!
	mut refused := false
	admit_v(root, root, tool, inputs) or { refused = true }
	require_refusal(refused)
}
