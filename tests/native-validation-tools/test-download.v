// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import androidhost as ah
import cachecli
import crypto.sha256
import gamehost
import os
import sourcecommand
import validationhost

struct FetchFixture {
mut:
	data  string
	calls int
}

fn fetch_command(argv []string, _ bool, pointer voidptr) !sourcecommand.Output {
	mut f := unsafe { &FetchFixture(pointer) }
	f.calls++
	assert argv[0] == 'curl' && '--max-filesize' in argv && '--connect-timeout' in argv && '--speed-time' in argv && '--max-time' !in argv
	assert argv[argv.index('--max-filesize') + 1] == '7' && argv[argv.index('--user-agent') + 1] == 'fixture agent'
	os.write_file(argv[argv.index('--output') + 1], f.data)!
	return sourcecommand.Output{}
}

fn fetch_cases(work string) ! {
	mut f := FetchFixture{ data: 'payload' }
	tools := gamehost.Tools{ command_hook: fetch_command, context: &f }
	pin := validationhost.DownloadPin{ name: 'package.bin', url: 'https://fixture.invalid/pinned', hash: sha256.hexhash('payload'), size: 7, user_agent: 'fixture agent', timeout: 30 }
	target := validationhost.pinned_download(tools, work, pin, false)!
	assert os.read_file(target)! == 'payload' && f.calls == 1
	validationhost.pinned_download(tools, work, pin, false)!
	assert f.calls == 1
	os.write_file(target, 'old corrupted cache')!
	mut refused := false
	validationhost.pinned_download(tools, work, pin, false) or { refused = true }
	assert refused && f.calls == 1
	f.data = 'wrong bytes'
	refused = false
	validationhost.pinned_download(tools, work, pin, true) or { refused = true }
	assert refused && os.read_file(target)! == 'old corrupted cache'
	f.data = 'payload'
	validationhost.pinned_download(tools, work, pin, true)!
	assert os.read_file(target)! == 'payload'
	for name in os.ls(work)! {
		assert !name.starts_with('.vinix-download.')
	}
}

fn archive_cases(work string) ! {
	package := work + '/safe.zip'
	ah.write_archive(package, [ah.ArchiveItem{ name: 'a/', data: [], mode: 0o040755 },
		ah.ArchiveItem{ name: 'a/program', data: 'unchanged binary'.bytes(), mode: 0o100755 }])!
	archive := ah.open_archive(package)!
	entries := archive.entries()
	assert entries.map(it.name) == ['a/', 'a/program'] && entries[1].size == 16 && entries[1].mode == 0o100755
	root := work + '/unpacked'
	validationhost.extract_zip(archive, root, 16, 16, 2, 16, ['a/', 'a/program'])!
	assert os.read_file(root + '/a/program')! == 'unchanged binary'
	os.write_file(root + '/a/program', 'old destination')!
	for control in 0 .. 5 {
		mut refused := false
		validationhost.extract_zip(archive, root, if control == 0 { 15 } else { 16 }, if control == 1 {
			15
		} else {
			16
		}, if control == 2 { 3 } else { 2 }, if control == 3 { 15 } else { 16 }, if control == 4 {
			['a/', 'other']
		} else {
			['a/', 'a/program']
		}) or { refused = true }
		assert refused && os.read_file(root + '/a/program')! == 'old destination'
	}
	for name in ['../outside', '/absolute', 'a\\backslash'] {
		ah.write_archive(package, [ah.ArchiveItem{ name: name, data: 'bad'.bytes() }])!
		mut refused := false
		validationhost.extract_zip(ah.open_archive(package)!, root, 3, 3, 1, 3, []) or { refused = true }
		assert refused
	}
	ah.write_archive(package, [ah.ArchiveItem{ name: 'same', data: [] },
		ah.ArchiveItem{ name: 'same', data: [] }])!
	mut refused := false
	validationhost.extract_zip(ah.open_archive(package)!, root, 1, 1, 2, 0, []) or { refused = true }
	assert refused
	ah.write_archive(package, [ah.ArchiveItem{ name: 'link', data: 'target'.bytes(), mode: 0o120777 }])!
	refused = false
	validationhost.extract_zip(ah.open_archive(package)!, root, 6, 6, 1, 6, []) or { refused = true }
	assert refused
	ah.write_archive(package, [ah.ArchiveItem{ name: 'parent/file', data: 'safe'.bytes() }])!
	os.symlink(work, root + '/parent')!
	refused = false
	validationhost.extract_zip(ah.open_archive(package)!, root, 4, 4, 1, 4, []) or { refused = true }
	assert refused && !os.exists(work + '/file')
	header := work + '/demo.pbp'
	mut data := []u8{len: 48}
	for index, byte in [u8(0), `P`, `B`, `P`, 1, 0, 1, 0] { data[index] = byte }
	data[36] = 40
	for index, byte in 'NPUMDIMG'.bytes() { data[index + 40] = byte }
	os.write_file_array(header, data)!
	validationhost.verify_pbp(header, true)!
	data[36] = 41
	os.write_file_array(header, data)!
	refused = false
	validationhost.verify_pbp(header, true) or { refused = true }
	assert refused
	before := os.ls('/dev/fd')!.len
	os.write_file(work + '/broken.zip', 'broken')!
	for _ in 0 .. 100 {
		ah.open_archive(work + '/broken.zip') or { continue }
		return error('invalid ZIP accepted')
	}
	assert os.ls('/dev/fd')!.len == before
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.args.len != 2 { exit(2) }
	work := os.args[1]
	gamehost.mkdir(work) or { panic(err) }
	fetch_cases(work) or {
		eprintln(err)
		exit(1)
	}
	archive_cases(work) or {
		eprintln(err)
		exit(1)
	}
	os.write_file(work + '/passed', 'PASS\n') or { panic(err) }
	println('NATIVE PINNED DOWNLOADS / flags/cache/repair/failure preservation, ZIP metadata/preflight/path/mode/size/duplicate/link policy, PBP offsets and 100 failed constructors: PASS')
}
