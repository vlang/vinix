// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import gamehost
import launcherfixtures
import os
import sourcecommand
import steamshim
import tarcore
import tarstream

fn archive(path string, members []tarcore.Member, payloads [][]u8) ! {
	mut writer := tarcore.create(path)!
	defer { writer.close() }
	for i, member in members { writer.add(member, payloads[i])! }
	writer.finish()!
}

fn proc_cases(work string) ! {
	gamehost.mkdir(work + '/net')!
	line := '0: 0100007F:1F90 0200007F:0035 01 0 0 0 0 0 123\n'
	os.write_file(work + '/net/tcp', 'header\n' + line + '1: 0100007F:1F90 00000000:0000 0a 0 0 0 0 0 456\n')!
	assert steamshim.ipv4('0100007F')! == '127.0.0.1'
	assert steamshim.tcp_sockets(work + '/net/tcp', '127.0.0.2', '53')! == {
		'123': '127.0.0.1:8080->127.0.0.2:53'
	}
	for pid in ['123', '٤٥٦'] {
		gamehost.mkdir(work + '/' + pid + '/fd')!
		os.symlink('socket:[123]', work + '/' + pid + '/fd/9')!
		os.symlink('socket:[456]', work + '/' + pid + '/fd/4')!
		os.symlink('pipe:[123]', work + '/' + pid + '/fd/5')!
		os.write_file(work + '/' + pid + '/stat', '456 (complex (name)) S 42 0 0\n')!
	}
	args := ['-P', '-F', 'upnR', '-i', 'TCP@127.0.0.1:８０８０']
	report := steamshim.lsof_report(work, args)!
	assert report.status == 0 && report.error_text == ''
	assert report.output.contains('p123\nR42\nu' + os.getuid().str() + '\n')
	assert report.output.contains('p٤٥٦\nR42\nu' + os.getuid().str() + '\n')
	assert report.output.count('n127.0.0.1:8080->127.0.0.2:53\n') == 2
	assert report.output.count('n127.0.0.1:8080\n') == 2
	assert !report.output.contains('f5\n')
	assert steamshim.lsof_report(work, ['-P', '-F', 'upnR', '-i', 'TCP@127.0.0.1:9'.repeat(100)])!.status == 1
	assert steamshim.lsof_report(work, [])!.error_text == 'lsof: unsupported arguments\n'
	assert steamshim.lsof_report(work, ['-P', '-F', 'upnR', '-i', 'TCP@bad'])!.error_text == 'lsof: expected TCP@host:port\n'
	os.rm(work + '/123/stat')!
	missing := steamshim.lsof_report(work, args)!
	assert missing.status == 0 && !missing.output.contains('p123\n')
	println('PASS actual procfs fixtures, Unicode decimal filters, inode matching, parent/UID records and disappearing processes')
}

fn tar_cases(work string) ! {
	gamehost.mkdir(work)!
	before := os.ls('/dev/fd')!.len
	plain := work + '/plain.tar'
	data := 'native Steam payload\x00'.bytes()
	archive(plain, [tarcore.Member{ name: 'dir', kind: `5`, mode: 0o777 },
		tarcore.Member{ name: 'dir/file', size: data.len, mode: 0o751 },
		tarcore.Member{ name: 'dir/symbolic', kind: `2`, linkname: 'file' },
		tarcore.Member{ name: 'dir/hard', kind: `1`, linkname: 'dir/file' }], [[]u8{}, data, []u8{},
		[]u8{}])!
	gzip := os.find_abs_path_of_executable('gzip')!
	xz := os.find_abs_path_of_executable('xz')!
	bzip2 := os.find_abs_path_of_executable('bzip2')!
	options := steamshim.TarOptions{ decompressors: {
		'gzip':  gzip
		'xz':    xz
		'bzip2': bzip2
	} }
	guard := cachecli.own_commands()
	defer { guard.close() }
	for name in ['plain', 'gzip', 'xz', 'bzip2'] {
		path := if name == 'plain' { plain } else { work + '/' + name + '.tar' }
		if name != 'plain' {
			result := sourcecommand.capture_full([options.decompressors[name], '-c', plain], os.environ(), -1, 1024 * 1024, cachecli.cancelled)!
			assert result.status == 0
			os.write_file(path, result.stdout)!
		}
		destination := work + '/' + name + '-root'
		steamshim.extract(path, destination, options)!
		assert os.read_bytes(destination + '/dir/file')! == data
		assert os.read_file(destination + '/dir/symbolic')! == data.bytestr()
		assert os.readlink(destination + '/dir/symbolic')! == 'file'
		assert os.read_bytes(destination + '/dir/hard')! == data
		assert os.stat(destination + '/dir/file')!.mode & 0o777 == 0o751
		assert os.stat(destination + '/dir')!.mode & 0o777 == 0o700
		steamshim.extract(path, destination, options)!
		assert os.read_bytes(destination + '/dir/file')! == data
		assert os.read_bytes(destination + '/dir/hard')! == data
		assert os.stat(destination + '/dir/hard')!.mtime == 0
		assert os.ls('/dev/fd')!.len == before
	}
	for i, member in [tarcore.Member{ name: '../escape', size: 1 },
		tarcore.Member{ name: 'link', kind: `2`, linkname: '../outside' },
		tarcore.Member{ name: 'link', kind: `1`, linkname: '../outside' },
		tarcore.Member{ name: 'pipe', kind: `6` }] {
		path := work + '/invalid-' + i.str() + '.tar'
		archive(path, [member], [if member.regular() { 'x'.bytes() } else { []u8{} }])!
		mut failed := false
		steamshim.extract(path, work + '/invalid-' + i.str(), options) or { failed = true }
		assert failed
		assert os.ls('/dev/fd')!.len == before
	}
	assert !os.exists(work + '/escape')
	for selected_args in [['-xf', plain], ['xJvf', plain, '-C', work],
		['-xzf' + plain, '--directory=' + work, '--checkpoint', '99', '--no-same-owner']] {
		selected := steamshim.extraction_args(selected_args, work) or { return error('original extraction flags rejected') }
		assert selected.archive == plain && selected.directory == work
	}
	for invalid_args in [[]string{}, ['-tf', plain], ['-xf', '-'], ['-x', '-f'],
		['--extract', '--file', plain]] {
		assert steamshim.extraction_args(invalid_args, work) == none
	}
	println('PASS actual plain/gzip/xz/bzip2 extraction, link ownership, exact modes, path guards, original flags and descriptor retirement')
	launcherfixtures.sparse_cases(work + '/sparse', options)!
}

fn main() {
	if launcherfixtures.reader_mock() or {panic(err)}{return}
	if os.args.len != 2 { exit(2) }
	gamehost.mkdir(os.args[1]) or { panic(err) }
	proc_cases(os.args[1] + '/proc') or { panic(err) }
	tar_cases(os.args[1] + '/tar') or { panic(err) }
	launcherfixtures.reader_cases(os.args[1]+'/reader') or {panic(err)}
}
