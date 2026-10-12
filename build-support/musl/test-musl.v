// SPDX-License-Identifier: GPL-2.0-or-later
module main

import cachecli
import crypto.sha256
import hosttest
import json2
import muslnative
import os
import tarcore

fn cached_fixture(work string) ! {
	os.mkdir(work)!
	os.mkdir(work + '/stage')!
	muslnative.parents(work + '/stage/lib')!
	mut loader := []u8{len: 32}
	for i, value in [u8(0x7f), `E`, `L`, `F`, 2, 1] { loader[i] = value }
	loader[18] = 62
	loader << '\x001.2.5\x00'.bytes()
	os.write_file_array(work + '/stage/lib/ld-musl-x86_64.so.1', loader)!
	// A copied executable preserves the selected compiler's basename after
	// realpath resolution; probe commands are admitted through actual children.
	os.cp(os.executable(), work + '/cc')!
	os.chmod(work + '/cc', 0o755)!
	muslnative.parents(work + '/support/alpine')!
	os.write_file(work + '/support/alpine/manifest.json', '[]')!
	os.write_file(work + '/support/malloc-retain.patch', 'immutable controlled patch')!
	options := muslnative.Options{ root: work + '/repository', support: work + '/support', arch: 'x86_64', stage: work + '/stage', cache: work + '/cache', cc: work + '/cc', required_exports: ['malloc_trim'] }
	plan := muslnative.plan(options, '1')!
	assert plan.version == '1.2.5'
	assert plan.cflags == '-fstack-protector-strong -DVINIX_MALLOC_RETAIN=1'
	assert plan.ldflags == '-Wl,-soname,libc.musl-x86_64.so.1'
	build := options.cache + '/x86_64/' + plan.key
	muslnative.parents(build + '/objects/lib')!
	muslnative.parents(build + '/musl-1.2.5/include')!
	muslnative.parents(options.stage + '/usr/include')!
	os.write_file(options.stage + '/usr/include/stdlib.h', 'headers present')!
	mut rebuilt := loader.clone()
	rebuilt << 'rebuilt controlled loader'.bytes()
	os.write_file_array(build + '/objects/lib/libc.so', rebuilt)!
	os.write_file(build + '/objects/lib/libc.a', 'rebuilt controlled archive')!
	os.write_file(build + '/musl-1.2.5/include/malloc.h', 'int malloc_trim(size_t);')!
	os.write_file(build + '/musl-1.2.5/COPYRIGHT', 'controlled license')!
	mut manifest := plan.manifest.clone()
	manifest['libc_so_sha256'] = muslnative.digest(build + '/objects/lib/libc.so')!
	manifest['libc_a_sha256'] = muslnative.digest(build + '/objects/lib/libc.a')!
	hosttest.write_json(build + '/build.json', manifest)!
	os.setenv('VINIX_MUSL_TEST_READELF', os.executable(), true)
	os.setenv('VINIX_MUSL_TEST_TARGET', work + '/stage', true)
	muslnative.publish(plan)!
	assert os.read_bytes(options.stage + '/lib/ld-musl-x86_64.so.1')! == rebuilt
	assert os.stat(options.stage + '/lib/ld-musl-x86_64.so.1')!.mode & 0o777 == 0o755
	assert os.readlink(options.stage + '/usr/lib/libc.so')! == '../../lib/ld-musl-x86_64.so.1'
	assert os.readlink(options.stage + '/lib/libc.musl-x86_64.so.1')! == 'ld-musl-x86_64.so.1'
	assert hosttest.decode_json(os.read_file(options.stage + '/usr/share/vinix/musl-build.json')!)!.as_map() == manifest
	muslnative.publish(plan)!
	assert os.ls(options.cache)! == ['build.lock', 'x86_64'] || os.ls(options.cache)! == [
		'x86_64',
		'build.lock',
	]
	println('NATIVE MUSL / actual compiler probes / cached identity / exported symbols / atomic staged files and links / repeated publication: PASS')
}

fn file_cases(work string) ! {
	os.mkdir(work)!
	os.write_file(work + '/source', 'new content')!
	os.write_file(work + '/outside', 'outside must stay unchanged')!
	os.symlink(work + '/outside', work + '/target')!
	muslnative.install(work + '/source', work + '/target', 0o644)!
	assert !os.is_link(work + '/target') && os.read_file(work + '/target')! == 'new content'
	assert os.read_file(work + '/outside')! == 'outside must stay unchanged'
	muslnative.replace_link(work + '/target', 'new-destination')!
	assert os.readlink(work + '/target')! == 'new-destination'
	os.mkdir(work + '/directory')!
	muslnative.install(work + '/source', work + '/directory', 0o644) or {
		assert os.ls(work + '/directory')!.len == 0
		assert os.ls(work)!.filter(it.starts_with('.')).len == 0
		return
	}
	return error('directory destination was accepted as a container')
}

fn archive_cases(work string) ! {
	os.mkdir(work)!
	for name in ['valid', 'absolute', 'parent', 'symlink', 'hardlink', 'wrong'] {
		path := work + '/' + name + '.tar'
		mut writer := tarcore.create(path)!
		member := tarcore.Member{
			name:     match name {
				'absolute' { '/musl-1.2.5/file' }
				'parent' { 'musl-1.2.5/../escape' }
				'wrong' { 'other/file' }
				else { 'musl-1.2.5/file' }
			}
			kind:     match name {
				'symlink' { u8(`2`) }
				'hardlink' { u8(`1`) }
				else { u8(`0`) }
			}
			linkname: if name in ['symlink', 'hardlink'] { 'outside' } else { '' }
			mode:     0o644
			size:     0
		}
		writer.add(member, []u8{})!
		writer.finish()!
		writer.close_checked()!
		muslnative.validate_archive(path, '1.2.5') or {
			assert name != 'valid'
			continue
		}
		assert name == 'valid'
	}
	println('NATIVE MUSL / validated tar names / link rejection / publication does not follow target links or directory containers: PASS')
}

fn retained_keys() ! {
	path := hosttest.root() + '/tests/alloc-bench/results/2026-10-03-userspace-v6/validation/independent-review/object-proof.json'
	stages := hosttest.decode_json(os.read_file(path)!)!.as_map()['stages']!.as_map()
	for name, value in stages {
		manifest := value.as_map()['manifest']!.as_map()
		mut inputs := map[string]json2.Any{}
		for key in ['version', 'alpine_package', 'arch', 'source_url', 'source_sha256', 'patches',
			'cc', 'compiler_version', 'compiler_target', 'cflags', 'ldflags', 'optimize', 'retention'] {
			inputs[key] = manifest[key]!
		}
		key := sha256.sum(muslnative.canonical(inputs)!.bytes()).hex()
		expected := os.base(os.dir(os.dir(manifest['configure_argv']!.as_array()[0].str())))
		assert key == expected, 'retained cache key differs: ' + name
	}
	println('NATIVE MUSL / all four immutable original cache identities / ASCII canonical manifest: PASS')
}

fn main() {
	if os.base(os.args[0]) == 'cc' {
		match os.args[1] {
			'-dumpmachine' { println('x86_64-linux-musl') }
			'--version' { println('gcc (controlled) 14.2.0') }
			'-print-prog-name=ar' { println('ar') }
			'-print-prog-name=ranlib' { println('ranlib') }
			'-print-prog-name=readelf' { println(os.getenv('VINIX_MUSL_TEST_READELF')) }
			else {
				eprintln('unexpected compiler probe')
				exit(1)
			}
		}
		return
	}
	if os.args.len == 4 && os.args[1..3] == ['--dyn-syms', '--wide'] {
		println(' 1: 0 0 FUNC GLOBAL DEFAULT 1 malloc')
		println(' 2: 0 0 FUNC WEAK DEFAULT 1 malloc_trim')
		println(' 3: 0 0 FUNC GLOBAL DEFAULT UND ignored')
		return
	}
	if os.args.len != 2 {
		eprintln('usage: test-musl NEW_STATE')
		exit(2)
	}
	assert muslnative.canonical(json2.Any({
		'β': json2.Any('é😀\x7f')
		'z': json2.Any([json2.Any(true), json2.Any(i64(1))])
	}))! == '{"z": [true, 1], "\\u03b2": "\\u00e9\\ud83d\\ude00\\u007f"}'
	assert muslnative.exports('1: 0 0 FUNC GLOBAL DEFAULT 1 x@V\n2: 0 0 FUNC WEAK DEFAULT 1 x\n3: 0 0 FUNC GLOBAL DEFAULT UND bad') == ['x']
	os.mkdir(os.args[1]) or {
		eprintln(err)
		exit(1)
	}
	guard := cachecli.own_commands()
	defer { guard.close() }
	retained_keys() or {
		eprintln(err)
		exit(1)
	}
	file_cases(os.args[1] + '/files') or {
		eprintln(err)
		exit(1)
	}
	archive_cases(os.args[1] + '/archives') or {
		eprintln(err)
		exit(1)
	}
	cached_fixture(os.args[1] + '/cached') or {
		eprintln(err)
		exit(1)
	}
}
