// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time

#include <sys/resource.h>
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int
fn C.setenv(&char, &char, int) int
struct CatalogBuilderLimit { current u64 maximum u64 }

$if track_heap ? {
#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32
}

// Synthetic payloads are inventoried, never executed. Two shared paths have
// one digest; runtime selectors resolve guest-absolute aliases on both hosts.
fn builder_fixture() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-catalog-owner-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(work + '/roots/shared')!
	os.write_file(work + '/roots/shared/COPYING', 'shared license document')!
	mut imports := []CatalogImport{}
	for architecture in ['aarch64', 'x86_64']! {
		root := work + '/roots/' + architecture
		os.mkdir_all(root + '/bin')!; os.mkdir(root + '/lib')!
		os.write_file(root + '/bin/application', 'application ' + architecture)!; os.chmod(root + '/bin/application', 0o755)!
		os.write_file(root + '/bin/runner', 'isolated runner ' + architecture)!; os.chmod(root + '/bin/runner', 0o755)!
		os.symlink('/bin/runner', root + '/lib/runner-alias')!
		for application in [true, false]! {
			path := if application { 'bin/application' } else { 'bin/runner' }
			p := Package{ id: if application { 'app' } else { 'runtime' }, name: if application { 'Application' } else { 'Runtime' },
				version: '1.0.0', architecture: architecture, license: 'MIT', kind: if application { 'linux' } else { 'runtime' },
				runtime: if application { 'runtime' } else { '' }, entrypoint: if application { 'bin/runner' } else { '' },
				arguments: if application { ['@APP@/bin/application', 'literal ; $ argument'] } else { []string{} },
				permissions: if application { ['files'] } else { []string{} }, associations: if application { ['text/plain'] } else { []string{} },
				dependencies: if application { [Dependency{ id: 'runtime', minimum: '1.0.0', before: '2.0.0' }, Dependency{ id: 'license' }] } else { []Dependency{} },
				files: [Payload{ path: path, bytes: os.file_size(root + '/' + path), sha256: hash_file(root + '/' + path)!, executable: true }] }
			imports << CatalogImport{ source: architecture, recipe: RootRecipe{ manifest: p,
				entries: [RootEntry{ source: if application { path } else { 'lib/runner-alias' }, path: path }] } }
		}
	}
	notice := Payload{ path: 'COPYING', bytes: 23, sha256: hash_file(work + '/roots/shared/COPYING')! }
	imports << CatalogImport{ source: 'shared', recipe: RootRecipe{
		manifest: Package{ id: 'license', name: 'Explicit license and firmware', version: '1.0.0', architecture: 'all', kind: 'data',
			license: 'Vendor-EULA', proprietary: true, firmware: true, files: [notice, Payload{ ...notice, path: 'notices/COPYING' }] },
		entries: [RootEntry{ source: 'COPYING', path: 'COPYING' }, RootEntry{ source: 'COPYING', path: 'notices/COPYING' }] } }
	text := publisher_json(CatalogRecipe{ format: 1, architectures: ['x86_64', 'aarch64'], packages: imports })
	os.write_file(work + '/recipe.json', text)!; os.write_file(work + '/original.json', text)!
	os.mkdir(work + '/output')!
	return work
}

fn builder_selected(mode string) bool {
	if os.args.len == 1 { return true }
	assert os.args.len == 3 && os.args[1] == 'case'
	return os.args[2] == mode
}

fn builder_descriptors() int {
	mut count := 0
	for fd in 0 .. 256 { if C.fcntl(fd, C.F_GETFD, 0) >= 0 { count++ } }
	return count
}

fn builder_write(path string, text string) ! {
	fd := C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_TRUNC | C.O_CLOEXEC | C.O_NOFOLLOW, 0o644)
	if fd < 0 { return error('cannot write catalog owner fixture') }
	defer { C.close(fd) }; assert C.write(fd, text.str, usize(text.len)) == text.len
}

fn builder_checkpoint(phase string, stage string) ! {
	mode := os.getenv('VINIX_CATALOG_OWNER_MODE'); defer { unsafe { mode.free() } }
	if phase == 'created' { assert C.setenv(c'VINIX_CATALOG_OWNER_STAGE', stage.str, 1) == 0 }
	if mode == phase { return error('injected catalog owner checkpoint refusal') }
	if phase == 'packed' && mode.starts_with('packed-') {
		names := ['app-aarch64', 'app-x86_64', 'license-all', 'runtime-aarch64', 'runtime-x86_64']!
		name := names[int(mode[7] - `1`)]
		path := stage + '/manifests/' + name + '-1.0.0.json'; defer { unsafe { path.free() } }
		if publisher_entry_exists(path) { return error('injected catalog owner checkpoint refusal') }
	}
	if phase == 'created' && mode.starts_with('import-') {
		work := os.getenv('VINIX_CATALOG_OWNER_WORK'); path := work + '/roots/aarch64/bin/application'
		defer { unsafe { work.free(); path.free() } }
		if mode == 'import-mode' { assert C.chmod(path.str, 0o644) == 0 }
		else if mode == 'import-bytes' { builder_write(path, 'Application aarch64')! }
		else {
			assert C.unlinkat(C.AT_FDCWD, path.str, 0) == 0
			if mode == 'import-directory' { assert C.mkdir(path.str, 0o700) == 0 }
		}
	}
	if phase == 'created' && mode == 'changed-recipe' {
		work := os.getenv('VINIX_CATALOG_OWNER_WORK'); path := work + '/recipe.json'
		defer { unsafe { work.free(); path.free() } }; builder_write(path, '{}')!
	}
	if phase == 'created' && mode.starts_with('root-replaced') {
		work := os.getenv('VINIX_CATALOG_OWNER_WORK'); saved := work + '/saved-stage'; keep := stage + '/keep'
		defer { unsafe { work.free(); saved.free(); keep.free() } }
		assert C.rename(stage.str, saved.str) == 0; assert C.mkdir(stage.str, 0o700) == 0
		builder_write(keep, 'preserved replacement')!
		if mode == 'root-replaced-refused' { return error('injected catalog owner checkpoint refusal') }
	}
	if phase == 'ready' && mode in ['manifest-mutated', 'manifest-extra', 'catalog-mutated']! {
		path := stage + match mode { 'catalog-mutated' { '/catalog.json' } 'manifest-extra' { '/manifests/extra.json' } else { '/manifests/runtime-x86_64-1.0.0.json' } }
		defer { unsafe { path.free() } }; builder_write(path, '{}')!
	}
	if phase == 'ready' && mode.starts_with('object-') {
		hash := os.getenv('VINIX_CATALOG_OWNER_OBJECT'); path := stage + '/objects/' + hash
		defer { unsafe { hash.free(); path.free() } }
		if mode == 'object-mutated' { builder_write(path, 'changed')! }
		else { assert C.unlinkat(C.AT_FDCWD, path.str, 0) == 0 }
	}
	if phase == 'ready' && mode == 'raced-target' {
		path := os.getenv('VINIX_CATALOG_OWNER_TARGET'); keep := path + '/keep'
		defer { unsafe { path.free(); keep.free() } }; assert C.mkdir(path.str, 0o700) == 0; builder_write(keep, 'preserved replacement')!
	}
}

fn builder_space(path string) !u64 {
	mode := os.getenv('VINIX_CATALOG_OWNER_MODE'); parent := os.getenv('VINIX_CATALOG_OWNER_PARENT')
	defer { unsafe { mode.free(); parent.free() } }
	if mode == 'space-error' { return error('injected catalog space refusal') }
	if (mode == 'no-output-space' && path == parent) || (mode == 'no-temp-space' && path != parent) { return 0 }
	return ~u64(0)
}

fn builder_flush(fd int) int {
	mode := os.getenv('VINIX_CATALOG_OWNER_MODE'); defer { unsafe { mode.free() } }
	if mode == 'flush' { return -1 }
	return atomic_flush(fd)
}

fn builder_remove(path string) ! {
	if os.is_dir(path) && !os.is_link(path) { os.rmdir_all(path)! }
	else if os.exists(path) || os.is_link(path) { os.rm(path)! }
}

fn builder_reset(work string) ! {
	for name in ['output', 'saved-stage']! { builder_remove(work + '/' + name)! }
	os.mkdir(work + '/output')!
	if os.is_link(work + '/roots/aarch64') { os.rm(work + '/roots/aarch64')!; os.rename(work + '/saved-root', work + '/roots/aarch64')! }
	if !os.exists(work + '/roots/aarch64') && os.is_dir(work + '/saved-root') { os.rename(work + '/saved-root', work + '/roots/aarch64')! }
	if os.is_dir(work + '/roots/aarch64/bin/application') { os.rmdir(work + '/roots/aarch64/bin/application')! }
	os.write_file(work + '/roots/aarch64/bin/application', 'application aarch64')!; os.chmod(work + '/roots/aarch64/bin/application', 0o755)!
	os.write_file(work + '/recipe.json', os.read_file(work + '/original.json')!)!
}

fn builder_prepare(mode string, work string, target string) ! {
	text := os.read_file(work + '/recipe.json')!
	match mode {
		'missing-recipe' { os.rm(work + '/recipe.json')! }
		'invalid-json' { os.write_file(work + '/recipe.json', '{')! }
		'unknown-schema' { os.write_file(work + '/recipe.json', text.replace_once('"format":1', '"format":1,"unknown":1'))! }
		'wrong-host' { os.write_file(work + '/recipe.json', text.replace('aarch64', 'arm64'))! }
		'unresolved' { os.write_file(work + '/recipe.json', text.replace('"id":"runtime","minimum"', '"id":"absent","minimum"').replace('"runtime":"runtime"', '"runtime":"absent"'))! }
		'missing-architecture' { os.rename(work + '/roots/aarch64', work + '/saved-root')! }
		'alias-source' { os.rename(work + '/roots/aarch64', work + '/saved-root')!; os.symlink(work + '/saved-root', work + '/roots/aarch64')! }
		'occupied' { os.write_file(target, 'preserved replacement')! }
		else {}
	}
}

fn builder_attempt(mode string, recipe string, roots string, target string) {
	input := if mode == 'missing-root' { roots + '/missing' } else { roots.clone() }
	defer { unsafe { input.free() } }
	if result := catalog_build(recipe, input, target, CatalogOptions{ checkpoint: builder_checkpoint, available_space: builder_space, flush: builder_flush }) {
		mut info := result
		assert info.package_count == 5 && info.object_count == 5 && info.architectures.len == 2 && info.architectures[0] == 'aarch64' && info.architectures[1] == 'x86_64'
		info.close(); info.close(); assert mode in ['complete', 'nested', 'changed-recipe']!
	} else {
		message := err.msg(); defer { unsafe { message.free(); err.free() } }
		assert mode !in ['complete', 'nested', 'changed-recipe']!
		expected := match mode {
			'missing-recipe' { 'metadata' } 'invalid-json' { 'incomplete administration' } 'unknown-schema' { 'unknown' }
			'wrong-host' { 'supported architectures' } 'unresolved' { 'dependency closure' }
			'missing-root' { 'prepared root' } 'missing-architecture', 'alias-source' { 'ordinary directory' }
			'no-output-space', 'no-temp-space' { 'insufficient disk space' } 'space-error' { 'injected catalog space' }
			'created', 'packed-1', 'packed-2', 'packed-3', 'packed-4', 'packed-5', 'ready' { 'injected catalog owner checkpoint' }
			'import-missing' { 'catalog import app/aarch64/1.0.0' }
			'import-bytes', 'import-mode' { 'catalog payload inventory differs' }
			'import-directory' { 'catalog import app/aarch64/1.0.0: app: invalid file count' }
			'manifest-mutated' { 'catalog manifest changed' } 'manifest-extra' { 'catalog manifest set changed' }
			'object-mutated', 'object-missing' { 'catalog object changed' } 'catalog-mutated' { 'catalog recipe changed' }
			'occupied' { 'destination must be new' } 'raced-target' { 'without replacing' } 'flush' { 'published at ' }
			'root-replaced', 'root-replaced-refused' { 'cleanup refused' } else { panic(mode) }
		}
		assert message.contains(expected), message
		if mode == 'import-missing' { assert message.contains('cannot open prepared guest path') }
		if mode == 'flush' { assert message.contains('directory flush failed') }
	}
}

fn test_complete_catalog_builder_retires_import_verification_and_publication_storage() {
	defer { for name in ['MODE', 'WORK', 'PARENT', 'TARGET', 'STAGE', 'OBJECT']! { os.unsetenv('VINIX_CATALOG_OWNER_' + name) } }
	for mode in ['complete', 'nested', 'missing-recipe', 'invalid-json', 'unknown-schema', 'wrong-host', 'unresolved', 'missing-root', 'missing-architecture', 'alias-source',
		'no-output-space', 'no-temp-space', 'space-error', 'created', 'packed-1', 'packed-2', 'packed-3', 'packed-4', 'packed-5', 'ready',
		'import-missing', 'import-bytes', 'import-mode', 'import-directory', 'manifest-mutated', 'manifest-extra', 'object-mutated', 'object-missing', 'catalog-mutated',
		'changed-recipe', 'occupied', 'raced-target', 'flush', 'root-replaced', 'root-replaced-refused']! {
		if !builder_selected(mode) { continue }
		work := builder_fixture()!; defer { os.rmdir_all(work) or {} }
		recipe := work + '/recipe.json'; roots := work + '/roots'; target := work + if mode == 'nested' { '/output/new/parent/lock' } else { '/output/lock' }
		mut warm := pack_catalog(recipe, roots, target)!; golden := warm.catalog_sha256.clone(); warm.close(); warm.close()
		defer { unsafe { golden.free() } }
		assert golden == 'a5fac25e7915d6a796c04f427d79e0a7eab7ebbcff09a5ea79bb1ddcd4ea9158'
		println('CATALOG BUILDER golden=' + golden)
		os.setenv('VINIX_CATALOG_OWNER_MODE', mode, true); os.setenv('VINIX_CATALOG_OWNER_WORK', work, true)
		os.setenv('VINIX_CATALOG_OWNER_TARGET', target, true); os.setenv('VINIX_CATALOG_OWNER_PARENT', os.dir(target), true)
		os.setenv('VINIX_CATALOG_OWNER_OBJECT', hash_file(roots + '/shared/COPYING')!, true)
		mut original := CatalogBuilderLimit{}; assert C.getrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0
		limit := CatalogBuilderLimit{ current: 32, maximum: original.maximum }; assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &limit }) == 0
		before := builder_descriptors(); mut maximum := u64(0); mut records := u32(0)
		for _ in 0 .. 8 {
			builder_reset(work)!
			if os.is_dir(work + '/saved-root') { os.rename(work + '/saved-root', roots + '/aarch64')! }
			builder_prepare(mode, work, target)!
			$if track_heap ? { C.vinix_heap_begin() }
			builder_attempt(mode, recipe, roots, target)
			$if track_heap ? {
				kept := C.vinix_heap_end(); count := C.vinix_heap_count()
				if kept > maximum { maximum = kept }; if count > records { records = count }
			}
			assert builder_descriptors() == before
			if mode in ['complete', 'nested', 'changed-recipe', 'flush']! { assert index_digest(os.read_file(target + '/catalog.json')!) == golden }
			else if mode == 'occupied' { assert os.read_file(target)! == 'preserved replacement' }
			else if mode == 'raced-target' { assert os.read_file(target + '/keep')! == 'preserved replacement' }
			else { assert !os.exists(target) }
			if mode.starts_with('root-replaced') {
				stage := os.getenv('VINIX_CATALOG_OWNER_STAGE'); assert os.read_file(stage + '/keep')! == 'preserved replacement' && os.is_dir(work + '/saved-stage')
			} else { assert os.ls(work + '/output')!.all(!it.starts_with('.vinix-catalog-')) }
		}
		assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0
		$if track_heap ? {
			println('CATALOG BUILDER case=' + mode + ' retained=' + maximum.str() + ' allocations=' + records.str())
			$if !catalog_builder_baseline ? { assert maximum == 0 && records == 0 }
		}
		builder_reset(work)!
		if os.is_dir(work + '/saved-root') { os.rename(work + '/saved-root', roots + '/aarch64')! }
		os.unsetenv('VINIX_CATALOG_OWNER_MODE')
		mut retried := pack_catalog(recipe, roots, target)!; assert retried.catalog_sha256 == golden; retried.close(); retried.close()
		assert os.read_file(roots + '/aarch64/bin/application')! == 'application aarch64' && os.read_file(roots + '/shared/COPYING')! == 'shared license document'
		println('CATALOG BUILDER ' + mode + ' canonical retry, deduplication, saved output, sources and descriptors PASS')
	}
}
