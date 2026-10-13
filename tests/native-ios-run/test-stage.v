// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import gamehost
import ioshost
import os
import sourcecommand

struct Recording {
mut:
	commands     [][]string
	environments []map[string]string
}

fn capture(argv []string, environment map[string]string, context voidptr) !sourcecommand.Output {
	mut recording := unsafe { &Recording(context) }
	recording.commands << argv.clone()
	recording.environments << environment.clone()
	return sourcecommand.Output{}
}

fn plans() ! {
	flags := ['--no-build', '--with-2048', '--with-cxx', '--with-gles', '--with-ppsspp',
		'--ppsspp-muted', '--ppsspp-cube', '--ppsspp-nzp', '--ppsspp-gow']
	for mask in 0 .. 512 {
		mut argv := []string{}
		for index, flag in flags { if mask & (1 << index) != 0 { argv << flag } }
		value := ioshost.parse(argv) or { continue }
		mut recording := Recording{}
		tools := ioshost.Tools{
			root:        '/repo'
			environment: {
				'TEST': 'retained'
			}
			hook:        capture
			context:     unsafe { &recording }
		}
		tools.build('/build', value)!
		mut golden := [][]string{}
		if mask & 1 == 0 {
			mut command := ['bash', '/repo/scripts/build-ios-aarch64.sh']
			if mask & 4 != 0 { command << '--with-cxx' }
			if mask & 8 != 0 { command << '--with-gles' }
			golden << command
		}
		golden << ['sh', '/repo/tests/ios/build-fixture.sh', '/build/fixtures']
		if mask & 4 != 0 {
			for name in ['build-cxx-fixture.sh', 'build-cxx-native.sh'] {
				golden << ['bash', '/repo/tests/ios/' + name, '/build/fixtures']
			}
		}
		if mask & 8 != 0 {
			golden << ['bash', '/repo/tests/ios/build-gles-fixture.sh', '/build/fixtures']
		}
		golden << ['bash', '/repo/examples/ios-calculator/build.sh']
		if mask & 2 != 0 {
			golden << [['bash', '/repo/examples/ios-2048/build.sh'],
				['bash', '/repo/tests/ios/build-2048-model.sh']]
		}
		if mask & (8 | 16) != 0 {
			golden << ['/repo/examples/ios-ppsspp/download', '--output', '/build/ppsspp']
		}
		for bit, name in {
			64:  'cube'
			128: 'nzp'
			256: 'gow'
		} {
			if mask & bit != 0 {
				golden << ['/repo/examples/ios-ppsspp/download-' + name, '--output', '/build/' + if name == 'cube' {
					'ppsspp/cube.pbp'
				} else if name == 'nzp' {
					'nzportable'
				} else {
					'god-of-war'
				}]
			}
		}
		assert recording.commands == golden
		for index, command in recording.commands {
			assert recording.environments[index]['TEST'] == 'retained'
			if command[1].ends_with('/examples/ios-calculator/build.sh') {
				assert recording.environments[index]['VINIX_IOS_CALCULATOR_BUILD_DIR'] == '/build/objc'
			}
			if command[1].ends_with('/examples/ios-2048/build.sh') || command[1].ends_with('/tests/ios/build-2048-model.sh') {
				assert recording.environments[index]['VINIX_IOS_2048_BUILD_DIR'] == '/build/2048'
			}
		}
	}
}

fn files(work string) ! {
	gamehost.mkdir(work)!
	os.write_file(work + '/source', 'literal é\\ file')!
	os.chmod(work + '/source', 0o751)!
	os.symlink('source', work + '/link')!
	ioshost.copy_file(work + '/link', work + '/copied')!
	assert !os.is_link(work + '/copied') && os.read_file(work + '/copied')! == 'literal é\\ file' && os.stat(work + '/copied')!.mode & 0o7777 == 0o751
	ioshost.asset_file(work + '/source', work + '/hardlinked')!
	assert os.stat(work + '/source')!.inode == os.stat(work + '/hardlinked')!.inode
	os.write_file(work + '/fallback', 'previous')!
	ioshost.asset_file(work + '/link', work + '/fallback')!
	assert !os.is_link(work + '/fallback') && os.read_file(work + '/fallback')! == 'literal é\\ file'
	gamehost.mkdir(work + '/tree/nested')!
	os.write_file(work + '/tree/nested/file', 'tree asset')!
	os.chmod(work + '/tree', 0o751)!
	ioshost.asset_tree(work + '/tree', work + '/tree-copy')!
	assert os.stat(work + '/tree/nested/file')!.inode == os.stat(work + '/tree-copy/nested/file')!.inode
	assert os.stat(work + '/tree')!.mode == os.stat(work + '/tree-copy')!.mode && os.stat(work + '/tree')!.mtime == os.stat(work + '/tree-copy')!.mtime
	os.symlink('nested/file', work + '/tree/linked')!
	os.symlink('/nonexistent/vinix-library', work + '/tree/absolute')!
	ioshost.dependency_tree(work + '/tree', work + '/dependency-copy')!
	assert os.readlink(work + '/dependency-copy/linked')! == 'nested/file'
	assert os.readlink(work + '/dependency-copy/absolute')! == '/nonexistent/vinix-library'
	assert os.lstat(work + '/tree/linked')!.mtime == os.lstat(work + '/dependency-copy/linked')!.mtime
	assert os.stat(work + '/tree')!.mode == os.stat(work + '/dependency-copy')!.mode && os.stat(work + '/tree')!.mtime == os.stat(work + '/dependency-copy')!.mtime
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.args.len != 2 { exit(2) }
	plans() or { panic(err) }
	files(os.args[1]) or { panic(err) }
	os.write_file(os.args[1] + '/passed', 'PASS\n') or { panic(err) }
	println('PASS all valid original build plans, native downloaders, copied metadata, hard links and fallback link following')
}
