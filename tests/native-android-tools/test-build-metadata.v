// SPDX-License-Identifier: GPL-2.0-or-later
module main

import androidhost as ah
import androidtools
import crypto.sha256
import crypto.sha512
import encoding.hex
import json2
import os

fn fixture_files(directory string, names []string, payload []u8) ! {
	for name in names { os.mkdir_all(os.dir(directory + '/' + name))!; os.write_file_array(directory + '/' + name, payload)! }
}

fn manifest(path string) !map[string]ah.Value { return json2.decode[ah.Value](os.read_file(path)!, strict: true)!.object() }

fn qualify(work string) ! {
	os.mkdir(work)!
	tools := work + '/tools'; os.mkdir(tools)!
	for name in ['gcc', 'apk', 'strip', 'java'] { os.cp(os.executable(), tools + '/' + name)!; os.chmod(tools + '/' + name, 0o700)! }
	os.setenv('PATH', tools + ':' + os.getenv('PATH'), true)
	os.setenv('VINIX_ATL_JAVA_D8', tools + '/java', true)
	root := androidtools.root()
	constants := ah.runtime_constants(root + '/build-support/android')
	gold := json2.decode[map[string]json2.Any](os.read_file(root + '/tests/android/runtimefixture/elf.json')!)!
	images := gold['elf']!.as_map()
	native := hex.decode(images['native']!.str())!
	archive := work + '/source.tar.gz'; os.write_file(archive, 'source archive identity')!
	cache := work + '/packages'; os.mkdir(cache)!; os.write_file(cache + '/z.apk', 'z')!; os.write_file(cache + '/a.apk', 'a')!
	art := work + '/art'; os.mkdir(art)!
	fixture_files(art, constants['ART_ELFS']!.items().map(it.text()), native)!
	fixture_files(art, constants['ART_HEADERS']!.items().map(it.text()), 'native provider header'.bytes())!
	art_arguments := [art, constants['SOURCE_COMMIT']!.text(), 'https://example.invalid/art', archive, constants['PATCH']!.text(), cache]
	androidtools.write_build_manifest('art', art_arguments)!
	art_receipt := manifest(art + '/art-runtime-manifest.json')!
	assert boothost_number(ah.field(art_receipt, 'source_date_epoch')) == 1759985629
	assert ah.field(art_receipt, 'source_sha512').text() == sha512.sum512('source archive identity'.bytes()).hex()
	assert ah.field(art_receipt, 'source_sha256').text() == sha256.sum('source archive identity'.bytes()).hex()
	assert ah.field(art_receipt, 'compiler_target').text() == 'aarch64-linux-musl'
	assert ah.field(art_receipt, 'files').items().len == constants['ART_ELFS']!.items().len + 1
	assert ah.field(art_receipt, 'dependency_archives').items().map(ah.field(it.object(), 'filename').text()) == ['a.apk', 'z.apk']
	for shape in ['foreign', 'incongruent'] {
		path := art + '/usr/lib/art/libart.so'
		os.write_file_array(path, hex.decode(images[shape]!.str())!)!
		mut refused := false; androidtools.write_build_manifest('art', art_arguments) or { refused = true }
		assert refused
		os.write_file_array(path, native)!
	}
	bionic := work + '/bionic'; os.mkdir(bionic)!
	fixture_files(bionic, constants['BIONIC_LIBRARIES']!.items().map(it.text()), native)!
	androidtools.write_build_manifest('bionic', [bionic, constants['BIONIC_SOURCE_COMMIT']!.text(), 'https://example.invalid/bionic', archive, constants['BIONIC_PATCH']!.text(), cache])!
	assert ah.field(manifest(bionic + '/bionic-runtime-manifest.json')!, 'files').items().len == 9
	boot := json2.decode[map[string]json2.Any](os.read_file(root + '/tests/android/runtimefixture/boot-builders.json')!)!
	dex := hex.decode(boot['dex']!.as_array()[0].as_map()['hex']!.str())!
	atl := work + '/atl'; os.mkdir(atl)!
	fixture_files(atl, constants['ATL_ELFS']!.items().map(it.text()), native)!
	for name in constants['ATL_JARS']!.items() { os.mkdir_all(os.dir(atl + '/' + name.text()))!; ah.write_archive(atl + '/' + name.text(), [ah.ArchiveItem{name: 'classes.dex', data: dex}])! }
	fixture_files(atl, [constants['ATL_RESOURCES']!.text(), constants['ATL_FONTS']!.text()], 'data'.bytes())!
	r8 := work + '/r8.jar'; os.write_file(r8, 'compiler jar')!
	core := work + '/core.jar'; os.write_file(core, 'core classfiles')!
	probe := ah.configuration_probe_digest(root + '/build-support/android')!
	androidtools.write_build_manifest('atl', [atl, constants['ATL_SOURCE_COMMIT']!.text(), 'https://example.invalid/atl', archive, r8, core, root + '/build-support/android/atl-dex', root + '/build-support/android/build-atl.sh', cache, constants['ATL_PATCH']!.text(), constants['PATCH']!.text(), art, probe])!
	result := manifest(atl + '/atl-runtime-manifest.json')!
	assert ah.field(result, 'dex_adapter_sha256').text() == ah.dex_adapter_digest(root + '/build-support/android')!
	assert ah.field(result, 'configuration_probe_sha256').text() == probe
	assert ah.field(result, 'dex_compiler').text() == 'D8 8.3.37 (build native fixture)'
	assert ah.field(result, 'files').items().len == constants['ATL_REQUIRED']!.items().len
	for record in ah.field(result, 'files').items() {
		row := record.object()
		if ah.field(row, 'path').text().ends_with('.jar') { assert boothost_number(ah.field(row, 'class_count')) == 1 && boothost_number(ah.field(row, 'bootstrap_callsites')) == 0 }
	}
	before := androidtools.build_source_key('source', art, [archive])!
	os.write_file(archive, 'changed source identity')!
	assert androidtools.build_source_key('source', art, [archive])! != before
	assert androidtools.build_source_key('source', bionic, [archive])! != androidtools.build_source_key('source', art, [archive])!
	os.write_file(work + '/passed', 'PASS\n')!
	println('NATIVE BUILD METADATA / actual compiler and package children / complete ART and nine Bionic files / foreign and 16 KiB ELF rejection / ATL DEX counts / source, compiler, provider and native closure hashes / sorted package receipts / source and absolute-path cache invalidation: PASS')
}

fn boothost_number(value ah.Value) u64 { return ah.integer(value) or { panic('not an integer') } }

fn main() {
	name := os.file_name(os.executable())
	if name == 'gcc' { println(if os.args.len > 1 && os.args[1] == '-dumpmachine' { 'aarch64-linux-musl' } else { 'native fixture gcc 13' }); return }
	if name == 'apk' { println('fixture-package-1-r0 installed'); return }
	if name == 'java' { println('D8 8.3.37 (build native fixture)'); return }
	if name == 'strip' { return }
	if os.args.len != 2 { eprintln('usage: test-build-metadata NEW_STATE'); exit(2) }
	qualify(os.args[1]) or { eprintln(err); exit(1) }
}
