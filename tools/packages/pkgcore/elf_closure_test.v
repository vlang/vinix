// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time
import tests.packages.elffixture

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
	fn C.vinix_heap_count() u32
}

fn closure_fixture(architecture string, kind string, needed []string, soname string, runpath string) []u8 {
	mut bytes := elffixture.image(architecture, kind)
	if kind == 'static' { return bytes }
	bytes << []u8{len: 8192 - bytes.len}
	elffixture.put(mut bytes, 96, u64(bytes.len)); elffixture.put(mut bytes, 104, u64(bytes.len))
	ph := if kind == 'pie' { 176 } else { 120 }
	elffixture.put(mut bytes, ph + 8, 512); elffixture.put(mut bytes, ph + 16, 0x100200)
	mut count := 2; mut cursor := 6145
	elffixture.put(mut bytes, 512, 5); elffixture.put(mut bytes, 520, 0x101800)
	for name in needed {
		elffixture.put(mut bytes, 512 + count * 16, 1); elffixture.put(mut bytes, 520 + count * 16, u64(cursor - 6144))
		for c in name { bytes[cursor] = c; cursor++ }; cursor++; count++
	}
	for tag, name in {u64(14): soname, u64(29): runpath} {
		if name == '' { continue }
		elffixture.put(mut bytes, 512 + count * 16, tag); elffixture.put(mut bytes, 520 + count * 16, u64(cursor - 6144))
		for c in name { bytes[cursor] = c; cursor++ }; cursor++; count++
	}
	elffixture.put(mut bytes, 528, 10); elffixture.put(mut bytes, 536, u64(cursor - 6144))
	elffixture.put(mut bytes, ph + 32, u64((count + 1) * 16)); elffixture.put(mut bytes, ph + 40, u64((count + 1) * 16))
	return bytes
}

fn closure_attempt(root int, images []ProfileElfImage, architecture string, expected string) {
	if _ := profile_elf_closure(root, images, architecture) { assert expected == '' }
	else {
		message := err.msg()
		assert expected != '' && message.contains(expected), message
		unsafe { message.free(); err.free() }
	}
}

fn closure_descriptors() int {
	mut count := 0
	for fd in 0 .. 256 { if C.fcntl(fd, C.F_GETFD, 0) >= 0 { count++ } }
	return count
}

fn closure_inventory_attempt(root int, images []ProfileElfImage, architecture string) {
	mut application := []Payload{cap: images.len}; mut runtime := []Payload{cap: images.len}
	defer { unsafe { (&array(&application)).free(); (&array(&runtime)).free() } }
	for image in images {
		file := Payload{path: image.path, sha256: image.object, executable: true}
		if image.space == 'app' { unsafe { application.push_many(&file, 1) } }
		else { unsafe { runtime.push_many(&file, 1) } }
	}
	mut packages := []CatalogImport{cap: 2}
	defer { unsafe { (&array(&packages)).free() } }
	packages << CatalogImport{source: '', recipe: RootRecipe{manifest: Package{id: 'test-app', kind: 'linux',
		architecture: architecture, runtime: 'test-runtime', files: application}}}
	packages << CatalogImport{source: '', recipe: RootRecipe{manifest: Package{id: 'test-runtime', kind: 'runtime',
		architecture: architecture, files: runtime}}}
	profile_linux_closures(root, packages, 'test-runtime') or { panic(err) }
}

fn test_elf_closure_bounds_dependencies_search_paths_aliases_and_ownership() {
	work := os.real_path(os.temp_dir()) + '/vinix-elf-closure-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	root := capture_prepared_root(work, 'closure fixture')!; defer { C.close(root) }
	mut cases := 0
	for architecture in ['aarch64', 'x86_64']! {
		loader := 'lib/ld-musl-' + architecture + '.so.1'
		defer { unsafe { loader.free() } }
		for fault in ['valid', 'missing-direct', 'missing-transitive', 'ambiguous', 'same-alias', 'soname-conflict', 'loader-mismatch',
			'no-dynamic', 'duplicate-dynamic', 'unterminated-dynamic', 'duplicate-strtab', 'no-strsz', 'huge-strsz',
			'unmapped-strtab', 'bad-needed', 'needed-offset', 'needed-nul', 'many-needed', 'static-dynamic',
			'origin', 'origin-braces', 'origin-usr-lib', 'ambient-rpath', 'relative-rpath', 'empty-rpath', 'origin-escape', 'filter',
			'unmapped-dynamic', 'mismapped-dynamic', 'ambiguous-dynamic', 'ambiguous-strtab', 'same-load-map']! {
			mut app := closure_fixture(architecture, 'pie', if fault == 'missing-direct' { ['missing.so'] } else { ['libone.so'] }, '',
				match fault { 'origin' { '$ORIGIN/../lib' } 'origin-braces' { '\${ORIGIN}/../lib' } 'origin-usr-lib' { '$ORIGIN/../usr/lib' }
					'ambient-rpath' { '/usr/lib' } 'relative-rpath' { 'lib' } 'empty-rpath' { '$ORIGIN/../lib:' }
					'origin-escape' { '$ORIGIN/../../lib' } else { '' } })
			mut library := closure_fixture(architecture, 'shared', if fault == 'missing-transitive' { ['libleaf.so'] } else { ['libc.so'] }, 'libone.so', '')
			libc := closure_fixture(architecture, 'shared', []string{}, if fault == 'soname-conflict' { 'libone.so' } else { '' }, '')
			defer { unsafe { app.free(); library.free(); libc.free() } }
			mut images := [ProfileElfImage{'app', 'bin/app', 'app', 'pie'}, ProfileElfImage{'runtime', 'lib/libone.so', 'library', 'shared'},
				ProfileElfImage{'runtime', 'lib/libc.so', 'libc', 'shared'}, ProfileElfImage{'runtime', loader, 'libc', 'shared'}]
			defer { unsafe { (&array(&images)).free() } }
			mut expected := ''
			match fault {
				'missing-direct', 'missing-transitive' { expected = 'missing library' }
				'ambiguous', 'same-alias' {
					images << ProfileElfImage{'app', 'usr/lib/libone.so', if fault == 'same-alias' { 'library' } else { 'libc' }, 'shared'}
					if fault == 'ambiguous' { expected = 'ambiguous library' }
				}
				'soname-conflict' { expected = 'ambiguous SONAME' }
				'loader-mismatch' { images[3] = ProfileElfImage{'runtime', loader, 'library', 'shared'}; expected = 'loader/libc' }
				'no-dynamic' { app[176] = 0; expected = 'no PT_DYNAMIC' }
				'duplicate-dynamic' { app[56]++; for i in 0 .. 56 { app[232 + i] = app[176 + i] }; expected = 'one bounded PT_DYNAMIC' }
				'unterminated-dynamic' { elffixture.put(mut app, 208, 48); expected = 'terminated dynamic' }
				'duplicate-strtab' { elffixture.put(mut app, 544, 5); expected = 'duplicate DT_STRTAB' }
				'no-strsz' { elffixture.put(mut app, 528, 21); expected = 'terminated dynamic' }
				'huge-strsz' { elffixture.put(mut app, 536, 4 * 1024 * 1024 + 1); expected = 'bounded string table' }
				'unmapped-strtab' { elffixture.put(mut app, 520, 0x10000000); expected = 'not file-backed' }
				'bad-needed' { app[6145] = `/`; expected = 'library basename' }
				'needed-offset' { elffixture.put(mut app, 552, 99999); expected = 'string offset' }
				'needed-nul' { for i in 6145 .. 6155 { app[i] = `a` }; expected = 'NUL-terminated' }
				'many-needed' { unsafe { app.free() }; app = closure_fixture(architecture, 'pie', []string{len: 257, init: 'a'}, '', ''); expected = 'too many DT_NEEDED' }
				'static-dynamic' { library[16] = 2; elffixture.put(mut library, 24, 0x100100); images[1] = ProfileElfImage{'runtime', 'lib/libone.so', 'library', 'static'}; expected = 'static runner contains' }
				'ambient-rpath', 'relative-rpath', 'empty-rpath', 'origin-escape' { expected = 'outside the packaged' }
				'filter' { elffixture.put(mut app, 544, 0x7fffffff); expected = 'auxiliary/filter' }
				'unmapped-dynamic' { elffixture.put(mut app, 192, 0x10000000); expected = 'PT_DYNAMIC is not file-backed' }
				'mismapped-dynamic' { elffixture.put(mut app, 192, 0x100201); expected = 'PT_DYNAMIC has ambiguous' }
				'ambiguous-dynamic', 'ambiguous-strtab', 'same-load-map' {
					app[56]++
					app[232] = 1; app[236] = 4
					elffixture.put(mut app, 240, if fault == 'ambiguous-strtab' { 4096 } else if fault == 'same-load-map' { 512 } else { 1024 })
					elffixture.put(mut app, 248, if fault == 'ambiguous-strtab' { 0x101800 } else { 0x100200 })
					elffixture.put(mut app, 264, 256); elffixture.put(mut app, 272, 256); elffixture.put(mut app, 280, 1)
					if fault != 'same-load-map' { expected = if fault == 'ambiguous-strtab' { 'string table has ambiguous' } else { 'PT_DYNAMIC has ambiguous' } }
				}
				else {}
			}
			os.write_file_array(work + '/app', app)!; os.write_file_array(work + '/library', library)!; os.write_file_array(work + '/libc', libc)!
			closure_attempt(root, images, architecture, expected)
			descriptors := closure_descriptors()
			for _ in 0 .. 32 {
				$if track_heap ? { C.vinix_heap_begin() }
				closure_attempt(root, images, architecture, expected)
				$if track_heap ? { assert C.vinix_heap_end() == 0 && C.vinix_heap_count() == 0, architecture + '/' + fault }
			}
			assert closure_descriptors() == descriptors
			if fault == 'valid' {
				closure_inventory_attempt(root, images, architecture)
				for _ in 0 .. 128 {
					$if track_heap ? { C.vinix_heap_begin() }
					closure_inventory_attempt(root, images, architecture)
					$if track_heap ? { assert C.vinix_heap_end() == 0 && C.vinix_heap_count() == 0 }
				}
				assert closure_descriptors() == descriptors
			}
			cases++
		}
	}
	assert cases == 64
	println('ELF CLOSURE 64 dependency, metadata, search-path and alias cases; 2048 repeated checks plus 256 inventory checks retain zero tracked bytes/descriptors PASS')
}
