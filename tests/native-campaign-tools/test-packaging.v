// SPDX-License-Identifier: GPL-2.0-or-later
module main

import campaignhost
import hosttest
import json2
import os

fn admission(work string) ! {
	os.mkdir(work)!
	for arch in ['amd64', 'aarch64'] {
		prior := work + '/prior'
		downloads := prior + '/' + arch + '/downloads'
		campaignhost.mkdirs(downloads)!
		mut index := ''
		for package in ['build-base', 'vim', 'zsh', 'libuuid'] {
			index += 'P:' + package + '\nV:1-r0\nA:' + if arch == 'amd64' { 'x86_64\n\n' } else { 'aarch64\n\n' }
			os.write_file(downloads + '/' + package + '-1-r0.apk', package)!
		}
		os.write_file(downloads + '/main_APKINDEX', index)!
		os.write_file(downloads + '/community_APKINDEX', '')!
		os.write_file(downloads + '/oh-my-zsh-frozen.tar.gz', 'cached')!
		if arch == 'amd64' { os.write_file(prior + '/' + arch + '/alpine-minirootfs-3.21.7-x86_64.tar.gz', 'cached')! }
		else { os.write_file(downloads + '/alpine-minirootfs-3.21.7-aarch64.tar.gz', 'cached')! }
		target := work + '/' + arch
		campaignhost.packaging_admission(prior, arch, target)!
		assert os.readlink(target + '/downloads')! == downloads
		mut reused := false
		campaignhost.packaging_admission(prior, arch, target) or { reused = true }
		assert reused
		os.rm(downloads + '/vim-1-r0.apk')!
		mut missing := false
		campaignhost.packaging_admission(prior, arch, target + '-missing') or { missing = true }
		assert missing
	}
}

fn payload(work string) ! {
	os.mkdir(work)!
	for arch in ['amd64', 'aarch64'] {
		machine := if arch == 'amd64' { 'x86_64' } else { 'aarch64' }
		stage := work + '/' + arch
		for dir in ['lib', 'usr/lib', 'usr/include', 'usr/share/vinix'] { campaignhost.mkdirs(stage + '/' + dir)! }
		loader := 'lib/ld-musl-' + machine + '.so.1'
		os.write_file(stage + '/' + loader, 'independent shared payload')!
		os.write_file(stage + '/usr/lib/libc.a', 'independent archive payload')!
		os.write_file(stage + '/usr/include/malloc.h', 'int malloc_trim(size_t);\n')!
		os.symlink('../../' + loader, stage + '/usr/lib/libc.so')!
		manifest := map[string]json2.Any{
			'arch': json2.Any(machine)
			'retention': json2.Any(u64(1))
			'optimize': json2.Any('internal,malloc,malloc/mallocng/*.c,string')
			'patches': json2.Any([json2.Any({'name': json2.Any('malloc-retain.patch'), 'sha256': json2.Any('independent patch identity')})])
			'compiler_version': json2.Any('target GCC (GCC) 14.2.0')
			'libc_so_sha256': json2.Any(campaignhost.digest(stage + '/' + loader)!)
			'libc_a_sha256': json2.Any(campaignhost.digest(stage + '/usr/lib/libc.a')!)
		}
		path := stage + '/usr/share/vinix/musl-build.json'
		hosttest.write_json(path, manifest)!
		archive := work + '/' + arch + '.tar'
		campaignhost.deterministic_archive(stage, archive)!
		assert campaignhost.verify_packaging(stage, archive, arch, 'independent patch identity')! == manifest
		for key, value in {'arch': json2.Any('wrong'), 'retention': json2.Any(u64(0)), 'optimize': json2.Any('wrong'), 'compiler_version': json2.Any('GCC 14.3.0'), 'libc_so_sha256': json2.Any('wrong'), 'libc_a_sha256': json2.Any('wrong')} {
			mut altered := campaignhost.copy_record(manifest)!
			altered[key] = value
			hosttest.write_json(path, altered)!
			mut refused := false
			campaignhost.verify_packaging(stage, archive, arch, 'independent patch identity') or { refused = true }
			assert refused, key
		}
		hosttest.write_json(path, manifest)!
		original := os.read_bytes(stage + '/' + loader)!
		os.write_file(stage + '/' + loader, 'changed library')!
		mut refused := false
		campaignhost.verify_packaging(stage, archive, arch, 'independent patch identity') or { refused = true }
		assert refused
		os.write_file_array(stage + '/' + loader, original)!
		assert campaignhost.verify_packaging(stage, archive, arch, 'independent patch identity')! == manifest
	}
}

fn missing_desktop(work string) ! {
	os.mkdir(work)!
	root := work + '/root'
	state := work + '/state'
	campaignhost.mkdirs(root + '/third_party/useralloc-pipe')!
	os.mkdir(state)!
	hosttest.write_json(state + '/preparation.json', {'untouched': json2.Any('preserved')})!
	assert campaignhost.static_desktop(campaignhost.Context{root: root, state: state, origin: root + '/origin'})! == 127
	result := campaignhost.read_json(state + '/build.json')!
	assert result['build_exit_code']!.int() == 127 && result['untouched']!.str() == 'preserved'
	assert os.is_file(state + '/build.pid') && os.read_file(state + '/build.log')!.contains('No such file')
}

fn qualify(work string) ! {
	os.mkdir(work)!
	admission(work + '/admission')!
	payload(work + '/payload')!
	missing_desktop(work + '/desktop')!
	os.write_file(work + '/passed', 'PASS\n')!
	println('CACHED PACKAGING / both architectures / selected APK closure / protected roots and missing archives / staged and embedded payloads / independent provenance failures / actual missing desktop builder exit and receipt: PASS')
	flush_stdout()
}

fn main() {
	if os.args.len != 2 { eprintln('usage: test-packaging NEW_STATE'); exit(2) }
	qualify(os.args[1]) or { eprintln(err); exit(1) }
}
