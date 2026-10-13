// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import crypto.sha256
import graphicsbuild
import hosttest
import os
import sourcecommand
import tarcore

fn checked(argv []string) !sourcecommand.Output {
	r := sourcecommand.capture_full(argv, os.environ(), -1, 4 * 1024 * 1024, cachecli.cancelled)!
	if r.status != 0 { return error(argv.str() + '\n' + r.stdout + r.stderr) }
	return r
}

fn expect_failure(operation string, work string, options graphicsbuild.Options) ! {
	mut failed := false
	graphicsbuild.prepare(work + '/mesa.tar', work + '/build', work + '/manifest', options) or {
		failed = true
	}
	assert failed, operation
	assert !os.ls(work + '/build/downloads')!.any(it.starts_with('.venus-fetch.')), operation + '/temporary retirement'
}

fn hashes(work string) ! {
	path := work + '/hash-input'
	for count in [0, 1, 127, 128, 129, 65535, 65536, 65537, 1048577] {
		os.write_file_array(path, []u8{len: count, init: u8(index % 251)})!
		for algorithm, external in {'blake2b': '-blake2b512', 'sha512': '-sha512', 'sha256': '-sha256'} {
			reference := checked(['openssl', 'dgst', external, path])!.stdout.trim_space().all_after('= ')
			assert graphicsbuild.digest(algorithm, path)! == reference, algorithm + '/' + count.str()
		}
	}
	mut failed := false
	graphicsbuild.digest('invalid', path) or { failed = true }
	assert failed
	failed = false
	graphicsbuild.verify('sha512', path, 'invalid', 'test archive') or {
		assert err.msg().starts_with('test archive checksum mismatch: ')
		failed = true
	}
	assert failed
	println('PASS 27 streamed digests against OpenSSL and checksum failures')
}

fn libraries(work string) ! {
	source, destination := work + '/libs', work + '/private'
	os.mkdir(source)!
	os.mkdir(destination)!
	os.write_file(source + '/libreal.so.1', 'payload')!
	os.chmod(source + '/libreal.so.1', 0o751)!
	checked(['touch', '-t', '202001020304.05', source + '/libreal.so.1'])!
	os.write_file(source + '/.hidden.so', 'hidden')!
	os.write_file(source + '/library.txt', 'excluded')!
	os.symlink('libreal.so.1', source + '/libalias.so')!
	os.symlink('/missing/external', source + '/libabsolute.so')!
	os.symlink('missing', destination + '/libreal.so.1')!
	os.symlink('missing', destination + '/libalias.so')!
	for _ in 0 .. 2 {
		graphicsbuild.libraries(source, destination)!
		assert os.read_file(destination + '/libreal.so.1')! == 'payload'
		assert os.stat(destination + '/libreal.so.1')!.mode & 0o7777 == 0o751
		assert os.stat(destination + '/libreal.so.1')!.mtime == os.stat(source + '/libreal.so.1')!.mtime
		assert os.readlink(destination + '/libalias.so')! == 'libreal.so.1'
		assert os.readlink(destination + '/libabsolute.so')! == '/missing/external'
		assert os.read_file(destination + '/.hidden.so')! == 'hidden'
		assert !os.exists(destination + '/library.txt')
	}
	graphicsbuild.libraries(work + '/absent', destination)!
	assert os.ls(destination)!.len == 4
	println('PASS private library bytes, modes, times, hidden names and dangling/absolute link replacements')
}

fn fixture(work string) ! {
	os.mkdir(work + '/mirror')!
	os.mkdir_all(work + '/build/downloads')!
	os.mkdir(work + '/build/sysroot')!
	mut source := tarcore.create(work + '/mesa.tar')!
	source.add(tarcore.Member{name: 'mesa-25.0.5/', kind: `5`, mode: 0o755}, []u8{})!
	source.add(tarcore.Member{name: 'mesa-25.0.5/marker', size: 6, mode: 0o644}, 'source'.bytes())!
	source.finish()!
	source.close()
	mut manifest := '# fixture\n'
	for number in 0 .. 17 {
		name := 'package-' + number.str() + '.apk'
		data := 'payload-' + number.str()
		mut archive := tarcore.create_gzip(work + '/mirror/' + name)!
		archive.add(tarcore.Member{name: 'usr/', kind: `5`, mode: 0o755}, []u8{})!
		archive.add(tarcore.Member{name: 'usr/item-' + number.str(), size: data.len, mode: 0o640, mtime: 123}, data.bytes())!
		archive.finish()!
		archive.close()
		manifest += name + ' ' + sha256.sum(os.read_bytes(work + '/mirror/' + name)!).hex() + '\n'
	}
	os.write_file(work + '/manifest', manifest)!
	options := graphicsbuild.Options{mirror: 'file://' + work + '/mirror',
		source_digest: graphicsbuild.digest('blake2b', work + '/mesa.tar')!}
	graphicsbuild.prepare(work + '/mesa.tar', work + '/build', work + '/manifest', options)!
	for number in 0 .. 17 {
		path := work + '/build/sysroot/usr/item-' + number.str()
		assert os.read_file(path)! == 'payload-' + number.str()
		assert os.stat(path)!.mode & 0o7777 == 0o640 && os.stat(path)!.mtime == 123
	}
	os.write_file(work + '/build/mesa-25.0.5/marker', 'keep existing source')!
	graphicsbuild.prepare(work + '/mesa.tar', work + '/build', work + '/manifest', graphicsbuild.Options{
		...options
		curl: '/usr/bin/false'
	})!
	assert os.read_file(work + '/build/mesa-25.0.5/marker')! == 'keep existing source'
	os.write_file(work + '/build/downloads/package-0.apk', 'corrupt cache')!
	expect_failure('corrupt cached APK', work, options)!
	assert os.read_file(work + '/build/downloads/package-0.apk')! == 'corrupt cache'
	os.rm(work + '/build/downloads/package-0.apk')!
	os.write_file(work + '/mirror/package-0.apk', 'corrupt download')!
	expect_failure('corrupt downloaded APK', work, options)!
	assert !os.exists(work + '/build/downloads/package-0.apk')
	for number in 0 .. 8 { os.rm(work + '/build/downloads/package-' + number.str() + '.apk') or {} }
	expect_failure('eight failed curl owners', work, graphicsbuild.Options{...options, curl: '/usr/bin/false'})!
	os.write_file(work + '/manifest', '')!
	os.rm(work + '/build/mesa-25.0.5/marker')!
	os.rmdir(work + '/build/mesa-25.0.5')!
	expect_failure('failed tar owner', work, graphicsbuild.Options{...options, tar: '/usr/bin/false'})!
	expect_failure('wrong Mesa checksum', work, graphicsbuild.Options{...options, source_digest: 'wrong'})!
	for row in ['missing-hash.apk', '../escape.apk ' + '0'.repeat(64), 'a.apk zz',
		'a.apk ' + '0'.repeat(64) + '\na.apk ' + '0'.repeat(64)] {
		mut failed := false
		graphicsbuild.manifest(row) or { failed = true }
		assert failed, row
	}
	assert graphicsbuild.manifest('# comment\n\n')!.len == 0
	println('PASS 17 actual parallel downloads, cached reuse, staged metadata, six failure paths and manifest guards')
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.args.len != 2 { exit(2) }
	work := hosttest.work_dir(os.args[1], 'vinix-graphics-check-') or { panic(err) }
	hashes(work) or { panic(err) }
	libraries(work) or { panic(err) }
	os.mkdir(work + '/fixture') or { panic(err) }
	fixture(work + '/fixture') or { panic(err) }
	println('PASS native graphics builder checks')
}
