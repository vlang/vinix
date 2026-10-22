// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time

fn C.link(&char, &char) int
fn C.mkfifo(&char, u32) int
fn C.fork() int
fn C.waitpid(int, &int, int) int
fn C._exit(int)
fn C.alarm(u32) u32

#include <sys/wait.h>

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
	fn C.vinix_heap_count() u32
}

// Deliberately executable checks: the pinned compiler removes assert in -prod.
fn catalog_publication_check(ok bool, message string) {
	if !ok { panic(message) }
}

fn catalog_publication_fixture() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-catalog-publication-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(work + '/roots/shared')!
	os.write_file(work + '/roots/shared/COPYING', 'explicitly licensed fixture data')!
	mut imports := []CatalogImport{}
	for arch in ['aarch64', 'x86_64']! {
		root := work + '/roots/' + arch
		defer { unsafe { root.free() } }
		os.mkdir_all(root + '/bin')!
		os.write_file(root + '/bin/application', 'application ' + arch)!
		os.write_file(root + '/bin/runner', 'runtime ' + arch)!
		os.chmod(root + '/bin/application', 0o755)!
		os.chmod(root + '/bin/runner', 0o755)!
		for id in ['app', 'runtime']! {
			path := if id == 'app' { 'bin/application' } else { 'bin/runner' }
			imports << CatalogImport{
				source: arch
				recipe: RootRecipe{
					manifest: Package{
						id:           id
						version:      '1.0.0'
						architecture: arch
						name:         id
						description:  'reviewed declaration'
						homepage:     'https://example.invalid/app'
						license:      'MIT'
						kind:         if id == 'app' { 'linux' } else { 'runtime' }
						runtime:      if id == 'app' { 'runtime' } else { '' }
						entrypoint:   if id == 'app' { 'bin/runner' } else { '' }
						arguments:    if id == 'app' {
							['@APP@/bin/application', '--one', '--two']
						} else {
							[]string{}
						}
						permissions:  ['network', 'files']
						associations: ['text/plain', 'image/png']
						dependencies: if id == 'app' {
							[Dependency{ id: 'runtime', before: '2.0.0' }, Dependency{ id: 'assets' }]
						} else {
							[]Dependency{}
						}
						files:        [Payload{ path: path, bytes: os.file_size(root + '/' + path), sha256: hash_file(root + '/' + path)!, executable: true }]
					}
					entries:  [RootEntry{ source: path, path: path }]
				}
			}
		}
	}
	imports << CatalogImport{
		source: 'shared'
		recipe: RootRecipe{
			manifest: Package{
				id:           'assets'
				name:         'Licensed assets'
				version:      '1.0.0'
				architecture: 'all'
				kind:         'data'
				license:      'Fixture-EULA'
				proprietary:  true
				firmware:     true
				files:        [Payload{
					path:   'COPYING'
					bytes:  os.file_size(work + '/roots/shared/COPYING')
					sha256: hash_file(work + '/roots/shared/COPYING')!
				}]
			}
			entries:  [RootEntry{ source: 'COPYING', path: 'COPYING' }]
		}
	}
	recipe := CatalogRecipe{ format: 1, architectures: ['x86_64', 'aarch64'], packages: imports }
	text := json2.encode(recipe)
	defer {
		close_decoded_catalog(recipe)
		unsafe { text.free() }
	}
	os.write_file(work + '/recipe.json', text)!
	mut info := pack_catalog(work + '/recipe.json', work + '/roots', work + '/repository')!
	info.close()
	os.write_file(work + '/seed', '00'.repeat(32) + '\n')!
	os.chmod(work + '/seed', 0o600)!
	return work
}

fn catalog_publication_packages(repository string) ![]Package {
	names := os.ls(repository + '/manifests')!
	defer { unsafe { names.free() } }
	mut packages := []Package{}
	unsafe { packages.flags |= .noslices }
	mut complete := false
	defer { if !complete { catalog_publication_close(packages) } }
	for name in names {
		text := read_metadata(repository + '/manifests/' + name)!
		defer { unsafe { text.free() } }
		p := decode_manifest(text, true)!
		unsafe { packages.push_many(&p, 1) }
	}
	complete = true
	return packages
}

fn catalog_publication_close(packages []Package) {
	for p in packages { close_decoded_package(p) }
	unsafe { (&array(&packages)).free() }
}

fn catalog_publication_attempt(repository string, packages []Package, refused bool) {
	if _ := publication_catalog_matches(repository, packages) {
		catalog_publication_check(!refused, 'catalog mismatch accepted')
	} else {
		message := err.msg()
		defer {
			unsafe {
				message.free()
				err.free()
			}
		}
		catalog_publication_check(refused, message)
	}
}

fn catalog_publication_denied(work string) {
	repository := work + '/repository'
	defer { unsafe { repository.free() } }
	mut denied := false
	publish(repository, 'fixture', work + '/seed', 2, 2100000000) or {
		message := err.msg()
		defer {
			unsafe {
				message.free()
				err.free()
			}
		}
		denied = message.contains('catalog')
	}
	catalog_publication_check(denied, 'publish signed a mismatched catalog')
	denied = false
	if result := publish_release(repository, 'fixture', work + '/seed', 2, 2100000000, work + '/refused') {
		mut info := result
		info.close()
	} else {
		message := err.msg()
		defer {
			unsafe {
				message.free()
				err.free()
			}
		}
		denied = message.contains('catalog')
	}
	catalog_publication_check(denied && !os.exists(work + '/refused'), 'publish-release exposed a mismatched catalog')
}

fn test_catalog_publication_signs_semantically_equal_locks_and_preserves_plain_workspace_bytes() {
	work := catalog_publication_fixture()!
	defer { os.rmdir_all(work) or {} }
	repository := work + '/repository'
	mut first := publish_release(repository, 'fixture', work + '/seed', 1, 2100000000, work + '/locked')!
	defer { first.close() }
	text := read_metadata(repository + '/catalog.json')!
	catalog := catalog_recipe(text)!
	defer {
		unsafe { text.free() }
		close_decoded_catalog(catalog)
	}
	mut imports := catalog.packages.clone()
	defer { unsafe { (&array(&imports)).free() } }
	imports.reverse_in_place()
	// Package order, formatting, architecture order and set-like arrays have no
	// signing meaning. The declarations and launch argument order still do.
	mut reordered := json2.encode(CatalogRecipe{ ...catalog, architectures: ['x86_64', 'aarch64'], packages: imports })
	reordered = reordered.replace('["files","network"]', '["network","files"]').replace('["image/png","text/plain"]', '["text/plain","image/png"]')
	os.write_file(repository + '/catalog.json', '\n  ' + reordered + '\n')!
	unsafe { reordered.free() }
	publish(repository, 'fixture', work + '/seed', 1, 2100000000)!
	catalog_publication_check(read_metadata(repository + '/index.json')! == read_metadata(work + '/locked/index.json')!, 'equivalent catalog changed signed index')
	catalog_publication_check(read_metadata(repository + '/index.sig')! == read_metadata(work + '/locked/index.sig')!, 'equivalent catalog changed signature')
	os.rm(repository + '/catalog.json')!
	mut plain := publish_release(repository, 'fixture', work + '/seed', 1, 2100000000, work + '/plain')!
	defer { plain.close() }
	catalog_publication_check(first.index_sha256 == plain.index_sha256 && first.public_key == plain.public_key, 'plain workspace compatibility changed')
	catalog_publication_check(read_metadata(work + '/plain/index.sig')! == read_metadata(work + '/locked/index.sig')!, 'plain signature changed')
	catalog_publication_check(os.ls(work + '/locked')!.len == 3 && !os.exists(work + '/locked/catalog.json'), 'lock leaked into consumer release')
	println('CATALOG PUBLICATION signed lock/plain bytes and semantic reordering PASS')
}

fn test_catalog_publication_rejects_changed_added_and_missing_rows_before_any_publication() {
	work := catalog_publication_fixture()!
	defer { os.rmdir_all(work) or {} }
	repository := work + '/repository'
	publish(repository, 'fixture', work + '/seed', 1, 2100000000)!
	mut warm := publish_release(repository, 'fixture', work + '/seed', 1, 2100000000, work + '/initial')!
	warm.close()
	history := read_metadata(repository + '/.publisher/history.json')!
	index := read_metadata(repository + '/index.json')!
	signature := read_metadata(repository + '/index.sig')!
	manifest := repository + '/manifests/app-aarch64-1.0.0.json'
	before := read_metadata(manifest)!
	for mode in ['changed', 'extra', 'missing']! {
		match mode {
			'changed' {
				os.write_file(manifest, before.replace('reviewed declaration', 'unreviewed declaration'))!
			}
			'extra' { os.cp(manifest, repository + '/manifests/extra.json')! }
			else { os.rm(manifest)! }
		}
		catalog_publication_denied(work)
		catalog_publication_check(read_metadata(repository + '/index.json')! == index && read_metadata(repository + '/index.sig')! == signature, 'refusal replaced published bytes')
		catalog_publication_check(read_metadata(repository + '/.publisher/history.json')! == history, 'refusal reserved sequence')
		if mode == 'extra' { os.rm(repository + '/manifests/extra.json')! }
		os.write_file(manifest, before)!
	}
	mut retry := publish_release(repository, 'fixture', work + '/seed', 2, 2100000000, work + '/retry')!
	retry.close()
	println('CATALOG PUBLICATION publish/release changed/extra/missing row refusal, unchanged bytes/history and retry PASS')
}

struct CatalogPublicationChange {
	from string
	to   string
}

fn test_catalog_publication_compares_all_manifest_declarations_and_argument_order() {
	work := catalog_publication_fixture()!
	defer { os.rmdir_all(work) or {} }
	repository := work + '/repository'
	manifest := repository + '/manifests/app-aarch64-1.0.0.json'
	before := read_metadata(manifest)!
	base := decode_manifest(before, true)!
	defer { close_decoded_package(base) }
	for change in [
		CatalogPublicationChange{'"id":"app"', '"id":"other"'},
		CatalogPublicationChange{'"version":"1.0.0"', '"version":"1.0.1"'},
		CatalogPublicationChange{'"architecture":"aarch64"', '"architecture":"x86_64"'},
		CatalogPublicationChange{'"name":"app"', '"name":"different"'},
		CatalogPublicationChange{'reviewed declaration', 'different description'},
		CatalogPublicationChange{'https://example.invalid/app', 'https://example.invalid/other'},
		CatalogPublicationChange{'"license":"MIT"', '"license":"Other-EULA"'},
		CatalogPublicationChange{'"proprietary":false', '"proprietary":true'},
		CatalogPublicationChange{'"firmware":false', '"firmware":true'},
		CatalogPublicationChange{'"kind":"linux"', '"kind":"native"'},
		CatalogPublicationChange{'"runtime":"runtime"', '"runtime":"other"'},
		CatalogPublicationChange{'"entrypoint":"bin/runner"', '"entrypoint":"bin/application"'},
		CatalogPublicationChange{'"--one","--two"', '"--two","--one"'},
		CatalogPublicationChange{'"files","network"', '"files","process"'},
		CatalogPublicationChange{'"image/png","text/plain"', '"image/png","text/html"'},
		CatalogPublicationChange{'"before":"2.0.0"', '"before":"3.0.0"'},
		CatalogPublicationChange{'"minimum":""', '"minimum":"0.1.0"'},
		CatalogPublicationChange{base.files[0].sha256, '0'.repeat(64)},
		CatalogPublicationChange{'"bytes":' + base.files[0].bytes.str(), '"bytes":123'},
		CatalogPublicationChange{'"executable":true', '"executable":false'},
	] {
		after := before.replace_once(change.from, change.to)
		catalog_publication_check(after != before, 'mutation did not change manifest: ' + change.from)
		os.write_file(manifest, after)!
		packages := catalog_publication_packages(repository)!
		catalog_publication_attempt(repository, packages, true)
		catalog_publication_close(packages)
		unsafe { after.free() }
	}
	os.write_file(manifest, before)!
	println('CATALOG PUBLICATION 20 complete-declaration/argument-order refusals PASS')
}

fn test_catalog_publication_refuses_invalid_lock_schema_and_incomplete_catalogs() {
	work := catalog_publication_fixture()!
	defer { os.rmdir_all(work) or {} }
	repository := work + '/repository'
	path := repository + '/catalog.json'
	text := read_metadata(path)!
	packages := catalog_publication_packages(repository)!
	defer {
		catalog_publication_close(packages)
		unsafe { text.free() }
	}
	for invalid in ['', '{', '{}', text.replace_once('"format":1', '"format":1,"unknown":true'),
		text.replace_once('"format":1', '"format":1,"format":1'),
		text.replace_once('"format":1', '"format":2'),
		text.replace_once('"architectures":["aarch64","x86_64"]', '"architectures":[]'),
		text.replace_once('"source":"aarch64"', '"source":"x86_64"')] {
		catalog_publication_check(invalid != text, 'invalid-lock mutation did not change fixture')
		os.write_file(path, invalid)!
		catalog_publication_attempt(repository, packages, true)
		catalog_publication_denied(work)
	}
	os.write_file(path, text)!
	catalog_publication_attempt(repository, packages, false)
	println('CATALOG PUBLICATION 8 malformed/schema/architecture/source lock refusals PASS')
}

fn catalog_publication_reader(path string, options MetadataReadOptions, refused bool) {
	if present, text := publication_catalog_text(path, options) {
		defer { unsafe { text.free() } }
		catalog_publication_check(!refused && present, 'unsafe catalog file admitted')
	} else {
		message := err.msg()
		defer {
			unsafe {
				message.free()
				err.free()
			}
		}
		catalog_publication_check(refused, message)
	}
}

fn catalog_publication_checkpoint(phase string, path string) ! {
	if phase != os.file_name(os.dir(path)) { return }
	match os.file_name(path) {
		'replace' {
			os.rename(path, path + '.saved')!
			os.write_file(path, 'replacement')!
		}
		'remove' { os.rm(path)! }
		'grow' {
			mut f := os.open_append(path)!
			defer { f.close() }
			f.write_string('appended')!
		}
		'shrink' { os.write_file(path, '')! }
		'mode' { os.chmod(path, 0o666)! }
		'error' { return error('injected catalog reader failure') }
		else { return error('unknown reader mutation') }
	}
}

fn test_catalog_publication_captures_bounded_controlled_lock_and_refuses_replacements() {
	work := catalog_publication_fixture()!
	defer { os.rmdir_all(work) or {} }
	path := work + '/lock'
	present, absent := publication_catalog_text(path, MetadataReadOptions{})!
	catalog_publication_check(!present && absent == '', 'missing lock must preserve plain workspaces')
	os.write_file(path, 'captured')!
	catalog_publication_reader(path, MetadataReadOptions{}, false)
	limit := 'x'.repeat(max_metadata)
	os.write_file(path, limit)!
	bounded, captured := publication_catalog_text(path, MetadataReadOptions{})!
	os.write_file(path, 'replacement')!
	catalog_publication_check(bounded && captured == limit, 'inclusive metadata limit or owned captured bytes changed')
	unsafe {
		limit.free()
		captured.free()
	}
	for mode in ['alias', 'dangling', 'directory', 'hardlink', 'writable', 'oversized', 'fifo']! {
		os.rm(path)!
		match mode {
			'alias' { os.symlink(work + '/seed', path)! }
			'dangling' { os.symlink(work + '/missing', path)! }
			'directory' { os.mkdir(path)! }
			'hardlink' {
				catalog_publication_check(C.link((work + '/seed').str, path.str) == 0, 'hardlink fixture failed')
			}
			'writable' {
				os.write_file(path, 'unsafe')!
				os.chmod(path, 0o666)!
			}
			'oversized' {
				mut f := os.open_file(path, 'w', 0o600)!
				f.seek(max_metadata, .start)!
				f.write_string('x')!
				f.close()
			}
			'fifo' {
				catalog_publication_check(C.mkfifo(path.str, 0o600) == 0, 'FIFO fixture failed')
			}
			else {}
		}
		// An accidental blocking FIFO open fails in two seconds, not a hung run.
		child := C.fork()
		catalog_publication_check(child >= 0, 'fork failed')
		if child == 0 {
			C.alarm(2)
			catalog_publication_reader(path, MetadataReadOptions{}, true)
			C._exit(0)
		}
		mut status := 0
		catalog_publication_check(C.waitpid(child, &status, 0) == child && status == 0, 'unsafe file refused promptly: ' + mode)
		if mode == 'directory' { os.rmdir(path)! } else { os.rm(path)! }
		os.write_file(path, 'captured')!
	}
	for phase in ['opened', 'sized', 'read']! {
		os.mkdir(work + '/' + phase)!
		for mode in ['replace', 'remove', 'mode', 'error', 'grow', 'shrink']! {
			if phase == 'opened' && mode in ['grow', 'shrink']! { continue }
			input := work + '/' + phase + '/' + mode
			os.write_file(input, 'captured')!
			catalog_publication_reader(input, MetadataReadOptions{ checkpoint: catalog_publication_checkpoint }, true)
			if mode == 'remove' { os.write_file(input, 'captured')! }
			os.chmod(input, 0o600)!
			os.write_file(input, 'restored')!
			catalog_publication_reader(input, MetadataReadOptions{}, false)
		}
	}
	println('CATALOG PUBLICATION controlled bounded descriptor/alias/FIFO/race refusal and restored retry PASS')
}

fn catalog_publication_reader_error(phase string, path string) ! {
	if path.ends_with(phase) { return error('injected catalog reader error') }
}

fn catalog_publication_descriptors() int {
	mut count := 0
	for fd in 0 .. 256 { if C.fcntl(fd, C.F_GETFD, 0) >= 0 { count++ } }
	return count
}

fn test_catalog_publication_closes_reader_and_decoded_comparison_owners_repeatedly() {
	work := catalog_publication_fixture()!
	defer { os.rmdir_all(work) or {} }
	repository := work + '/repository'
	path := repository + '/catalog.json'
	text := read_metadata(path)!
	packages := catalog_publication_packages(repository)!
	defer {
		catalog_publication_close(packages)
		unsafe { text.free() }
	}
	for mode in ['match', 'mismatch', 'schema', 'absent', 'reader', 'reader-refusal', 'error-opened',
		'error-sized', 'error-read']! {
		if mode == 'absent' {
			os.rm(path)!
		} else {
			os.write_file(path, if mode == 'schema' {
				'{'
			} else if mode == 'mismatch' {
				text.replace('reviewed declaration', 'unreviewed declaration')
			} else {
				text
			})!
		}
		if mode == 'reader-refusal' { os.chmod(path, 0o666)! }
		cycles := $if track_heap ? { 128 } $else { 4 }
		mut maximum := u64(0)
		mut records := u32(0)
		error_path := repository + '/' + mode
		defer { unsafe { error_path.free() } }
		if mode.starts_with('error-') { os.write_file(error_path, text)! }
		descriptors := catalog_publication_descriptors()
		for i in 0 .. cycles + 1 {
			$if track_heap ? {
				if i > 0 { C.vinix_heap_begin() }
			}
			if mode.starts_with('error-') {
				catalog_publication_reader(error_path, MetadataReadOptions{ checkpoint: catalog_publication_reader_error }, true)
			} else if mode.starts_with('reader') {
				catalog_publication_reader(path, MetadataReadOptions{}, mode == 'reader-refusal')
			} else {
				catalog_publication_attempt(repository, packages, mode in ['mismatch', 'schema']!)
			}
			$if track_heap ? {
				if i > 0 {
					kept := C.vinix_heap_end()
					allocations := C.vinix_heap_count()
					if kept > maximum { maximum = kept }
					if allocations > records { records = allocations }
				}
			}
			catalog_publication_check(catalog_publication_descriptors() == descriptors, 'catalog descriptor leak')
		}
		$if track_heap ? {
			catalog_publication_check(maximum == 0 && records == 0, 'retained catalog allocations: ' + mode)
		}
		println('CATALOG PUBLICATION ownership ' + mode + ' cycles=' + cycles.str() + ' retained=' + maximum.str() + ' allocations=' + records.str() + ' PASS')
		if mode == 'reader-refusal' { os.chmod(path, 0o600)! }
	}
}
