// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import crypto.sha256
import gamehost
import os
import runtimehost
import tarcore
import sourcecommand

fn ar_entry(name string, data []u8) []u8 {
	header := name + '/'
	row := header + ' '.repeat(16 - header.len) + '0           0     0     100644  ' + data.len.str() + ' '.repeat(10 - data.len.str().len) + '`\n'
	assert row.len == 60
	mut bytes := row.bytes()
	bytes << data
	if data.len % 2 != 0 { bytes << `\n` }
	return bytes
}

fn parser_cases() ! {
	assert runtimehost.dependency_key('\u2003libc6:any (>= 2.34) [arm64]') == 'libc6'
	assert runtimehost.parse_relations('a:any (>= 1) | b, c [arm64], ,') == [
		['a', 'b'],
		['c'],
	]
	data := 'Package: root\r\nVersion: 1\r\nFilename: pool/root.deb\r\nSize: 17\r\nPre-Depends: virtual | direct\r\nDepends: missing | child, ignored\r\nArchitecture: arm64\r\n\r\nPackage: provider\nFilename: provider.deb\nProvides: virtual (= 1)\n\nPackage: direct\nFilename: direct.deb\nDepends: child\n\nPackage: child\nFilename: child.deb\nDepends: root\n\nPackage: child\nFilename: second-version.deb\n\nPackage: ignored\nFilename: ignored.deb\n\nmalformed\nDescription: skip me\n'
	packages := runtimehost.parse_packages(data)!
	assert packages.len == 6 && packages[0].size == 17
	selected := runtimehost.resolve(packages, ['root'], ['ignored'])!
	assert selected.map(it.name) == ['child', 'direct', 'root']
	assert selected[0].filename == 'child.deb'
	assert runtimehost.resolve(packages, ['virtual'], [])!.map(it.name) == ['provider']
	continued := runtimehost.parse_packages('Package: a\nFilename: a.deb\nDepends: b,\n c | d\nDescription: invalid \xff\n')!
	assert continued[0].dependencies == [['b'], ['c', 'd']]
	mut refused := false
	runtimehost.resolve(packages, ['absent'], []) or {
		refused = true
		assert err.msg() == 'unresolved Debian dependency: absent'
	}
	assert refused
}

fn archive_cases(work string) ! {
	compressed := work + '/data.tar.gz'
	mut writer := tarcore.create_gzip(compressed)!
	writer.add(tarcore.Member{ name: './usr/bin/tool', mode: 0o755, size: 7 }, 'payload'.bytes())!
	writer.add(tarcore.Member{ name: './usr/bin/alias', kind: `1`, linkname: './usr/bin/tool' }, []u8{})!
	writer.add(tarcore.Member{ name: './usr/bin/link', kind: `2`, linkname: 'tool' }, []u8{})!
	writer.finish()!
	writer.close_checked()!
	mut deb := '!<arch>\n'.bytes()
	deb << ar_entry('debian-binary', '2.0\n'.bytes())
	deb << ar_entry('control.tar.gz', [u8(1), 2, 3])
	deb << ar_entry('data.tar.gz', os.read_bytes(compressed)!)
	archive := work + '/package.deb'
	os.write_file_array(archive, deb)!
	members := runtimehost.ar_members(deb)!
	assert members.map(it.name) == ['debian-binary', 'control.tar.gz', 'data.tar.gz']
	root := work + '/root'
	gamehost.mkdir(root)!
	runtimehost.extract_deb(archive, root)!
	assert os.read_file(root + '/usr/bin/tool')! == 'payload'
	assert os.read_file(root + '/usr/bin/alias')! == 'payload'
	assert os.readlink(root + '/usr/bin/link')! == 'tool'
	assert os.stat(root + '/usr/bin/tool')!.mode & 0o7777 == 0o755
	assert os.stat(root + '/usr/bin/tool')!.inode != os.stat(root + '/usr/bin/alias')!.inode
	runtimehost.extract_deb(archive, root)!
	for name in os.ls(work)! {
		assert !name.starts_with('.vinix-deb.')
	}
	// Selecting the first data payload must not parse a broken later ar member.
	mut later := deb.clone()
	later << 'broken later ar header'.repeat(4).bytes()
	os.write_file_array(work + '/later.deb', later)!
	runtimehost.extract_deb(work + '/later.deb', root)!
	for malformed in [deb[..7], deb[..deb.len - 100]] {
		mut refused := false
		runtimehost.ar_members(malformed) or { refused = true }
		assert refused
	}
}

fn prepare_command(argv []string, _ bool, _ voidptr) !sourcecommand.Output {
	assert argv[0].ends_with('/build-support/debian-root')
	assert argv[argv.len - 2..] == ['base-files', 'busybox-static']
	root := argv[argv.index('--root') + 1]
	gamehost.mkdir(root + '/usr/bin')!
	os.write_file(root + '/usr/bin/busybox', 'native prepared userspace')!
	return sourcecommand.Output{}
}

fn prepare_cases(work string) ! {
	directory := work + '/prepare'
	gamehost.mkdir(directory + '/downloads')!
	source := work + '/data.tar.gz'
	mut writer := tarcore.create_gzip(source)!
	writer.add(tarcore.Member{ name: './boot/vmlinuz-fixture-cloud-arm64', mode: 0o755, size: 6 }, 'kernel'.bytes())!
	writer.finish()!
	writer.close_checked()!
	mut archive := '!<arch>\n'.bytes()
	archive << ar_entry('data.tar.gz', os.read_bytes(source)!)
	os.write_file_array(directory + '/downloads/kernel.deb', archive)!
	os.write_file(directory + '/downloads/Packages.xz', 'cached index compressed')!
	os.write_file(directory + '/downloads/Packages', 'Package: linux-image-cloud-arm64\nFilename: meta.deb\nDepends: linux-image-fixture-cloud-arm64\n\nPackage: linux-image-fixture-cloud-arm64\nVersion: pinned fixture\nArchitecture: arm64\nFilename: pool/kernel.deb\nSize: ${archive.len}\nSHA256: ${sha256.sum(archive).hex()}\n')!
	runtimehost.prepare_debian(gamehost.Tools{ root: 'fixture repo', command_hook: prepare_command }, directory)!
	assert os.read_file(directory + '/root/boot/vmlinuz-fixture-cloud-arm64')! == 'kernel'
	assert os.read_file(directory + '/kernel.json')!.contains('pinned fixture')
	runtimehost.prepare_debian(gamehost.Tools{ root: 'fixture repo', command_hook: prepare_command }, directory)!
	// The 373-line installer header is skipped as data, never executed.
	payload := work + '/demo.tar.gz'
	mut demo_writer := tarcore.create_gzip(payload)!
	demo_writer.add(tarcore.Member{ name: 'ignored', size: 7 }, 'ignored'.bytes())!
	demo_writer.add(tarcore.Member{ name: 'demo/demo00.pk4', size: 12 }, 'demo payload'.bytes())!
	demo_writer.finish()!
	demo_writer.close_checked()!
	mut installer := 'do not execute\n'.repeat(373).bytes()
	installer << os.read_bytes(payload)!
	os.write_file_array(work + '/installer.run', installer)!
	runtimehost.install_doom_demo(work + '/installer.run', work + '/demo00.pk4')!
	assert os.read_file(work + '/demo00.pk4')! == 'demo payload'
	for name in os.ls(work)! {
		assert !name.starts_with('.vinix-runtime.')
	}
}

fn download_cases(work string) ! {
	gamehost.mkdir(work + '/mirror/pool')!
	gamehost.mkdir(work + '/cache')!
	data := 'verified package'
	os.write_file(work + '/mirror/pool/file.deb', data)!
	package := runtimehost.Package{ name: 'test', filename: 'pool/file.deb', architecture: 'arm64', sha256: sha256.hexhash(data), size: data.len }
	destination := runtimehost.download_package(gamehost.Tools{}, 'file://' + work + '/mirror', package, work + '/cache')!
	assert os.read_file(destination)! == data
	os.write_file(work + '/mirror/pool/file.deb', 'bad replacement')!
	assert runtimehost.download_package(gamehost.Tools{}, 'file://' + work + '/mirror', package, work + '/cache')! == destination
	os.write_file(destination, 'bad cache')!
	mut refused := false
	runtimehost.download_package(gamehost.Tools{}, 'file://' + work + '/mirror', package, work + '/cache') or {
		refused = true
		assert err.msg().contains('checksum mismatch')
	}
	assert refused && os.read_file(destination)! == 'bad cache'
	assert !os.exists(destination + '.partial')
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.args.len != 2 { exit(2) }
	work := os.args[1]
	gamehost.mkdir(work) or { panic(err) }
	parser_cases() or {
		eprintln(err)
		exit(1)
	}
	archive_cases(work) or {
		eprintln(err)
		exit(1)
	}
	download_cases(work) or {
		eprintln(err)
		exit(1)
	}
	prepare_cases(work) or {
		eprintln(err)
		exit(1)
	}
	os.write_file(work + '/passed', 'PASS\n') or { panic(err) }
	eprintln('NATIVE DEBIAN / Unicode/continued indexes, dependency alternatives, providers/ignored/cycles, ar and compressed payloads, modes and links, real curl cache/checksum preservation: PASS')
}
