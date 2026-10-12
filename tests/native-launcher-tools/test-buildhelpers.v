// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import crypto.sha256
import gamehost
import launcherhost
import os
import sourcecommand
import tarcore

fn checked(argv []string) !sourcecommand.Output {
	r := sourcecommand.capture_full(argv, os.environ(), -1, 32 * 1024 * 1024, cachecli.cancelled)!
	if r.status != 0 || r.stderr.contains('retrying with') || r.stdout.contains('retrying with') {
		return error(argv.str() + '\n' + r.stdout + r.stderr)
	}
	return r
}

fn ar_field(text string, length int) string { return text + ' '.repeat(length - text.len) }

fn ar_member(name string, bytes []u8) []u8 {
	mut result := (ar_field(name + '/', 16) + ar_field('0', 12) + ar_field('0', 6) + ar_field('0', 6) + ar_field('100644', 8) + ar_field(bytes.len.str(), 10) + '`\n').bytes()
	result << bytes
	if bytes.len % 2 != 0 { result << u8(10) }
	return result
}

fn deb_cases(controller string, work string) ! {
	gamehost.mkdir(work)!
	mut control := tarcore.create(work + '/control.tar')!
	control.add(tarcore.Member{ name: 'control', size: 19, mode: 0o640, mtime: 123 }, 'Version: 1:2.3.4-5\n'.bytes())!
	control.finish()!
	control.close()
	mut data := tarcore.create(work + '/data.tar')!
	for directory in ['usr', 'usr/lib', 'usr/lib/steam'] {
		data.add(tarcore.Member{ name: directory, kind: `5`, mode: 0o751, mtime: 321 }, []u8{})!
	}
	data.add(tarcore.Member{ name: 'usr/lib/steam/bootstrap', size: 5, mode: 0o4751, mtime: 456 }, 'bytes'.bytes())!
	data.add(tarcore.Member{ name: 'usr/lib/steam/symbolic', kind: `2`, linkname: 'bootstrap' }, []u8{})!
	data.add(tarcore.Member{ name: 'usr/lib/steam/hard', kind: `1`, linkname: './usr/lib/steam/bootstrap', mode: 0o4751, mtime: 456 }, []u8{})!
	data.finish()!
	data.close()
	gzip := os.find_abs_path_of_executable('gzip')!
	xz := os.find_abs_path_of_executable('xz')!
	compressed_control := checked([gzip, '-c', work + '/control.tar'])!.stdout.bytes()
	compressed_data := checked([xz, '-c', work + '/data.tar'])!.stdout.bytes()
	mut deb := '!<arch>\n'.bytes()
	for pair in [ar_member('debian-binary', '2.0\n'.bytes()),
		ar_member('control.tar.gz', compressed_control), ar_member('ignored', 'x'.bytes()),
		ar_member('data.tar.xz', compressed_data)] {
		deb << pair
	}
	os.write_file_array(work + '/installer.deb', deb)!
	for _ in 0 .. 2 {
		assert launcherhost.unpack_steam_deb([work + '/installer.deb', work + '/out'])! == 0
		assert os.read_file(work + '/out/control/control')! == 'Version: 1:2.3.4-5\n'
		assert os.stat(work + '/out/control/control')!.mode & 0o7777 == 0o640
		assert os.stat(work + '/out/control/control')!.mtime == 123
		for name in ['bootstrap', 'symbolic', 'hard'] {
			assert os.read_file(work + '/out/data/usr/lib/steam/' + name)! == 'bytes'
		}
		assert os.stat(work + '/out/data/usr/lib/steam/bootstrap')!.mode & 0o7777 == 0o4751
		assert os.stat(work + '/out/data/usr/lib/steam/bootstrap')!.mtime == 456
		assert os.stat(work + '/out/data/usr/lib/steam/hard')!.inode == os.stat(work + '/out/data/usr/lib/steam/bootstrap')!.inode
		assert os.readlink(work + '/out/data/usr/lib/steam/symbolic')! == 'bootstrap'
		for directory in ['usr', 'usr/lib', 'usr/lib/steam'] {
			assert os.stat(work + '/out/data/' + directory)!.mode & 0o7777 == 0o751
			assert os.stat(work + '/out/data/' + directory)!.mtime == 321
		}
		assert os.ls(work + '/out')!.sorted() == ['control', 'data']
	}
	gamehost.mkdir(work + '/actual')!
	os.symlink(work + '/actual', work + '/alias')!
	for test in [[work + '/alias/a/../target', work + '/alias/links/item', '../target'],
		['relative/../target', 'relative/link', '../target'], ['/same', '/same/link', '.'],
		['//same/path', '//same/link', 'path']] {
		assert checked([controller, 'relative-link', test[0], test[1]])!.stdout == test[2] + '\n'
	}
	println('PASS real compressed DEB sections, bytes, links, setuid/directory modes, deferred directory times, repeated extraction and lexical relative links')
}

fn custom_builder(builder string, compiler string, root string, work string) ! {
	gamehost.mkdir(work + '/include')!
	source := work + '/guest.v'
	os.write_file(source, 'module main\n#flag -I ' + work + '/include\n#include <selected.h>\nfn main(){println(C.SELECTED_VALUE);$if extra ? {println(23)}}\n')!
	header := work + '/include/selected.h'
	os.write_file(header, '#define SELECTED_VALUE 17\n')!
	output := work + '/guest'
	base := [builder, '--arch', 'aarch64', '--sysroot', root + '/build-aarch64-userland/staging',
		'--static', '--source', source, '--source-input', work + '/include', '--include-dir',
		work + '/include', '--output', output, '--cache', work + '/cache', '--v', compiler]
	checked(base)!
	old := sha256.sum(os.read_bytes(output)!).hex()
	count := os.ls(work + '/cache')!.len
	checked(base)!
	assert sha256.sum(os.read_bytes(output)!).hex() == old && os.ls(work + '/cache')!.len == count
	checked([...base, '--define', 'extra'])!
	assert sha256.sum(os.read_bytes(output)!).hex() != old
	assert os.ls(work + '/cache')!.len == count + 2
	os.write_file(header, '#define SELECTED_VALUE 18\n')!
	checked(base)!
	assert sha256.sum(os.read_bytes(output)!).hex() != old
	assert os.ls(work + '/cache')!.len == count + 4
	os.write_file(source, os.read_file(source)! + '\nfn unused(){println(99)}\n')!
	checked(base)!
	assert os.ls(work + '/cache')!.len == count + 6
	os.write_file(source, 'not valid V source\n')!
	os.write_file(output, 'keep existing output')!
	failed := sourcecommand.capture_full(base, os.environ(), -1, 32 * 1024 * 1024, cachecli.cancelled)!
	assert failed.status != 0 && os.read_file(output)! == 'keep existing output'
	println('PASS custom guest cache: warm reuse, define/header/source invalidation and failed-build publication preservation')
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.args.len != 5 { exit(2) }
	root := os.real_path(os.dir(@FILE) + '/../..')
	deb_cases(os.args[1], os.args[4] + '/deb') or { panic(err) }
	custom_builder(os.args[2], os.args[3], root, os.args[4] + '/builder') or { panic(err) }
}
