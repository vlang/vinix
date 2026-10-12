// SPDX-License-Identifier: GPL-2.0-or-later
module main

import androidtools
import os
import sourcecommand
import tarcore

fn cancelled() bool { return false }

fn compressed(path string, members []tarcore.Member, contents [][]u8) ![]u8 {
	mut writer := tarcore.create(path)!
	defer { writer.close() }
	for index, item in members { writer.add(item, contents[index])! }
	writer.finish()!
	writer.close()
	output := sourcecommand.capture(['/usr/bin/gzip', '-c', path], os.environ(), 30, 8 * 1024 * 1024, cancelled)!
	assert output.status == 0 && output.stderr == ''
	return output.stdout.bytes()
}

fn qualify(work string) ! {
	os.mkdir(work)!
	archive := work + '/concatenated.apk'
	mut bytes := compressed(work + '/sign.tar', [tarcore.Member{name: '.SIGN.fixture', size: 4}], ['sign'.bytes()])!
	bytes << compressed(work + '/control.tar', [tarcore.Member{name: '.PKGINFO', size: 7}], ['control'.bytes()])!
	bytes << compressed(work + '/payload.tar', [tarcore.Member{name: 'usr/lib/payload.so', size: 7, mode: 0o751}, tarcore.Member{name: 'lib/absolute.so', kind: `2`, linkname: '/usr/lib/payload.so'}, tarcore.Member{name: 'usr/lib/hard.so', kind: `1`, linkname: 'usr/lib/payload.so'}, tarcore.Member{name: 'usr/share/name\\with\\slashes', size: 3}], ['payload'.bytes(), []u8{}, []u8{}, 'yes'.bytes()])!
	os.write_file_array(archive, bytes)!
	runtime := work + '/runtime'; os.mkdir(runtime)!
	androidtools.extract_apk(archive, runtime)!
	assert !os.exists(runtime + '/.SIGN.fixture') && !os.exists(runtime + '/.PKGINFO')
	assert os.read_file(runtime + '/usr/lib/payload.so')! == 'payload'
	assert os.stat(runtime + '/usr/lib/payload.so')!.mode & 0o777 == 0o751
	assert os.readlink(runtime + '/lib/absolute.so')! == '../usr/lib/payload.so'
	assert os.read_file(runtime + '/lib/absolute.so')! == 'payload'
	assert os.stat(runtime + '/usr/lib/hard.so')!.inode == os.stat(runtime + '/usr/lib/payload.so')!.inode
	assert os.read_file(runtime + '/usr/share/name\\with\\slashes')! == 'yes'
	androidtools.materialize_library_links(runtime)!
	assert !os.is_link(runtime + '/lib/absolute.so')
	assert os.stat(runtime + '/lib/absolute.so')!.inode == os.stat(runtime + '/usr/lib/payload.so')!.inode
	outside := work + '/outside'; os.mkdir(outside)!
	for index, member in [tarcore.Member{name: 'usr/../../outside/escape', size: 0}, tarcore.Member{name: '/outside/escape', size: 0}, tarcore.Member{name: 'usr/escape', kind: `2`, linkname: '../../../outside'}, tarcore.Member{name: 'usr/hard', kind: `1`, linkname: '../outside'}, tarcore.Member{name: 'usr/escape/file', size: 0}] {
		bad := work + '/bad-' + index.str() + '.apk'
		os.write_file_array(bad, compressed(work + '/bad-' + index.str() + '.tar', [member], [[]u8{}])!)!
		if index == 4 { os.symlink(outside, runtime + '/usr/escape')! }
		mut refused := false
		androidtools.extract_apk(bad, runtime) or { refused = true }
		assert refused, member.name
		assert os.ls(outside)!.len == 0
	}
	os.rm(runtime + '/usr/escape')!
	os.symlink(outside, runtime + '/usr/lib/escape.so')!
	mut refused := false
	androidtools.materialize_library_links(runtime) or { refused = true }
	assert refused && os.is_link(runtime + '/usr/lib/escape.so')
	fonts := runtime + '/etc/fonts'; os.mkdir_all(fonts)!
	os.write_file(fonts + '/fonts.conf', '/usr/share/fonts /usr/local/share/fonts /etc/fonts')!
	os.write_file(work + '/external.conf', '/usr/share/fonts')!
	os.symlink(work + '/external.conf', fonts + '/external.conf')!
	androidtools.relocate_configuration(runtime)!
	assert os.read_file(fonts + '/fonts.conf')! == '/opt/vinix-android-aarch64/usr/share/fonts /opt/vinix-android-aarch64/usr/local/share/fonts /opt/vinix-android-aarch64/etc/fonts'
	assert os.read_file(work + '/external.conf')! == '/usr/share/fonts'
	androidtools.extract_member(archive, 'usr/lib/payload.so', work + '/selected')!
	assert os.read_file(work + '/selected')! == 'payload'
	os.write_file(work + '/passed', 'PASS\n')!
	println('NATIVE APK FILES / three concatenated gzip and tar streams / modes, absolute symlinks, hardlink inode and literal backslashes / traversal, parent and library escapes / relocated config and untouched symlink / selected member beyond end markers: PASS')
}

fn main() {
	if os.args.len != 2 { eprintln('usage: test-runtime-files NEW_STATE'); exit(2) }
	qualify(os.args[1]) or { eprintln(err); exit(1) }
}
