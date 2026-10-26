// SPDX-License-Identifier: GPL-2.0-or-later
module dylibclosure

import os
import time

fn fixture(path string, dependencies []string, rpaths []string, id string) ! {
	os.mkdir_all(os.dir(path))!
	os.write_file(path, 'Mach-O fixture; never executed\n')!
	canonical := os.real_path(path)
	mut listed := canonical + ':\n'
	mut commands := canonical + ':\n'
	mut names := []string{}
	if id != '' { names << id }
	names << dependencies
	for name in names {
		listed += '\t' + name + ' (compatibility version 1.0.0, current version 1.0.0)\n'
	}
	if id != '' {
		commands += 'Load command 0\n cmd LC_ID_DYLIB\n name ' + id + ' (offset 24)\n'
	}
	for index, name in dependencies {
		commands += 'Load command ' + (index + 1).str() + '\n cmd LC_LOAD_DYLIB\n name '
			+ name + ' (offset 24)\n'
	}
	for index, path_value in rpaths {
		commands += 'Load command ' + (dependencies.len + index + 1).str()
			+ '\n cmd LC_RPATH\n path ' + path_value + ' (offset 12)\n'
	}
	os.write_file(canonical + '.listed', listed)!
	os.write_file(canonical + '.commands', commands)!
}

fn fixture_checked(argv []string) !string {
	if argv.len != 5 || argv[0] != otool || argv[1] != '-arch'
		|| argv[2] !in ['arm64', 'x86_64'] || argv[3] !in ['-L', '-l'] {
		return error('unexpected fixture command: ' + argv.str())
	}
	return os.read_file(argv[4] + if argv[3] == '-L' { '.listed' } else { '.commands' })
}

fn fixture_root(label string) !string {
	path := os.temp_dir() + '/vinix-dylib-' + label + '-' + time.sys_mono_now().str()
	os.mkdir(path)!
	return os.real_path(path)
}

fn test_loader_rpath_recursive_closure_and_intermediate_opt_symlink() ! {
	root := fixture_root('recursive')!
	defer { os.rmdir_all(root) or {} }
	main_image := root + '/Cellar/tool/1/bin/tool'
	library := root + '/Cellar/tool/1/lib/libfirst.dylib'
	second := root + '/Cellar/second/1/lib/libsecond.dylib'
	opt := root + '/opt/second'
	os.mkdir_all(os.dir(opt))!
	os.symlink('../Cellar/second/1', opt)!
	fixture(main_image, ['@rpath/libfirst.dylib', '/usr/lib/libSystem.B.dylib'],
		['@loader_path/../lib'], '')!
	fixture(library, [opt + '/lib/libsecond.dylib'], [], '@rpath/libfirst.dylib')!
	fixture(second, ['/usr/lib/libc++.1.dylib'], [], opt + '/lib/libsecond.dylib')!
	result := closure([main_image], fixture_checked)!
	assert main_image in result.paths
	assert library in result.paths
	assert second in result.paths
	assert result.metadata['link:' + opt] == '../Cellar/second/1'
	assert result.metadata['resolved:' + opt] == root + '/Cellar/second/1'
	assert result.metadata.values().any(it == '/usr/lib/libSystem.B.dylib')
	assert '/usr/lib/libSystem.B.dylib' !in result.paths
}

fn test_inherited_rpaths_and_loader_specific_rpaths() ! {
	root := fixture_root('inherited')!
	defer { os.rmdir_all(root) or {} }
	main_image := root + '/bin/tool'
	first := root + '/parent/libfirst.dylib'
	local := root + '/parent/child/libsecond.dylib'
	shadowed := root + '/parent/libsecond.dylib'
	fixture(main_image, ['@rpath/libfirst.dylib'], ['@executable_path/../parent'], '')!
	fixture(first, ['@rpath/libsecond.dylib'], ['@loader_path/child'], '@rpath/libfirst.dylib')!
	fixture(local, [], [], '@rpath/libsecond.dylib')!
	fixture(shadowed, [], [], '@rpath/libsecond.dylib')!
	result := closure([main_image], fixture_checked)!
	assert local in result.paths
	assert shadowed !in result.paths
}

fn test_missing_first_candidate_is_bound_and_later_candidate_used() ! {
	root := fixture_root('search')!
	defer { os.rmdir_all(root) or {} }
	main_image := root + '/bin/tool'
	library := root + '/later/libfirst.dylib'
	fixture(main_image, ['@rpath/libfirst.dylib'],
		['@loader_path/../missing', '@loader_path/../later'], '')!
	fixture(library, [], [], '@rpath/libfirst.dylib')!
	result := closure([main_image], fixture_checked)!
	assert library in result.paths
	assert result.metadata['absent:' + root + '/missing'] == 'absent'
}

fn test_dotdot_follows_symlink_before_parent() ! {
	root := fixture_root('dotdot')!
	defer { os.rmdir_all(root) or {} }
	os.mkdir_all(root + '/real/nested')!
	os.symlink('real/nested', root + '/link')!
	mut state := State{}
	located := state.locate(root + '/link/..', [])!
	assert located.present
	assert located.path == root + '/real'
	assert state.metadata['link:' + root + '/link'] == 'real/nested'
}

fn test_dependency_cycle_terminates() ! {
	root := fixture_root('cycle')!
	defer { os.rmdir_all(root) or {} }
	first := root + '/first.dylib'
	second := root + '/second.dylib'
	fixture(first, ['@loader_path/second.dylib'], [], '@loader_path/first.dylib')!
	fixture(second, ['@loader_path/first.dylib'], [], '@loader_path/second.dylib')!
	result := closure([first], fixture_checked)!
	assert result.paths.filter(it == first).len == 1
	assert result.paths.filter(it == second).len == 1
}

fn test_unresolved_dependency_refuses() ! {
	root := fixture_root('missing')!
	defer { os.rmdir_all(root) or {} }
	main_image := root + '/tool'
	fixture(main_image, ['@rpath/missing.dylib'], ['@loader_path'], '')!
	mut refused := false
	closure([main_image], fixture_checked) or { refused = true }
	assert refused
}

fn test_mismatched_load_commands_refuse() ! {
	listed := '/fixture:\n\t/one.dylib (compatibility version 1.0.0, current version 1.0.0)\n'
	commands := '/fixture:\nLoad command 0\n cmd LC_LOAD_DYLIB\n name /two.dylib (offset 24)\n'
	mut refused := false
	parse_image('/fixture', listed, commands) or { refused = true }
	assert refused
}

fn test_dangling_and_cyclic_intermediate_links_refuse() ! {
	root := fixture_root('badlink')!
	defer { os.rmdir_all(root) or {} }
	os.symlink('missing', root + '/dangling')!
	os.symlink('b', root + '/a')!
	os.symlink('a', root + '/b')!
	for name in ['dangling', 'a'] {
		mut state := State{}
		mut refused := false
		state.locate(root + '/' + name + '/file.dylib', []) or { refused = true }
		assert refused
	}
}

fn test_system_path_does_not_accept_traversal() {
	assert system_path('/usr/lib/libSystem.B.dylib')
	assert system_path('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation')
	assert !system_path('/usr/lib/../../opt/changed.dylib')
	assert !system_path('/System/Library/../changed.dylib')
	assert !system_path('/usr/libexec/changed.dylib')
}
