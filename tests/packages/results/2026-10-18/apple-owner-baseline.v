// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time
import tests.packages.elffixture
import tests.packages.applefixture

#include <sys/resource.h>
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int
fn C.setenv(&char, &char, int) int
fn C.pwrite(int, voidptr, usize, i64) isize
struct AppleBuilderLimit { current u64 maximum u64 }

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
	fn C.vinix_heap_count() u32
}

fn builder_selected(name string) bool {
	if os.args.len == 1 { return true }
	assert os.args.len == 3 && os.args[1] == 'case'
	return os.args[2] == name
}

fn builder_descriptors() int {
	mut count := 0
	for fd in 0 .. 256 { if C.fcntl(fd, C.F_GETFD, 0) >= 0 { count++ } }
	return count
}

fn owner_fixture_info(id string) string {
	return '<plist><dict><key>CFBundleIdentifier</key><string>' + id + '</string><key>CFBundleExecutable</key><string>Example</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>'
}

fn owner_fixture_recipe(application bool) RootRecipe {
	return if application {
		RootRecipe{ manifest: Package{ id: 'org.example.apple', version: '1.0.0', architecture: 'aarch64',
			name: 'Reviewed Apple application', description: 'Publisher-supplied iOS bundle and isolated runtime.',
			license: 'Example-EULA', proprietary: true, kind: 'apple', runtime: 'org.example.ios-runtime',
			entrypoint: 'bin/run-ios', arguments: ['@APP@/Example.app/Example', 'literal ; $ argument'],
			permissions: ['files', 'process'], associations: ['text/plain'],
			dependencies: [Dependency{ id: 'org.example.ios-runtime', minimum: '1.0.0', before: '2.0.0' }] },
			entries: [RootEntry{ source: 'app/Example', path: 'Example.app/Example' },
				RootEntry{ source: 'app/Info.plist', path: 'Example.app/Info.plist' },
				RootEntry{ source: 'licenses/application-LICENSE.txt', path: apple_application_notice }] }
	} else {
		RootRecipe{ manifest: Package{ id: 'org.example.ios-runtime', version: '1.0.0', architecture: 'aarch64',
			name: 'Reviewed iOS runtime closure', license: 'GPL-2.0-or-later AND MIT', kind: 'runtime' },
			entries: [RootEntry{ source: 'runtime/runner', path: 'bin/run-ios' },
				RootEntry{ source: 'runtime/closure.txt', path: 'share/closure.txt' },
				RootEntry{ source: 'licenses/runtime-LICENSE.txt', path: apple_runtime_notice }] }
	}
}

fn owner_fixture() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-apple-profile-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	root := work + '/roots/aarch64'
	for directory in ['app', 'runtime', 'licenses'] { os.mkdir_all(root + '/' + directory)! }
	os.write_file_array(root + '/app/Example', applefixture.image(23))!
	os.write_file(root + '/app/Info.plist', owner_fixture_info('org.example.apple'))!
	os.write_file_array(root + '/runtime/runner', elffixture.image('aarch64', 'static'))!
	os.chmod(root + '/runtime/runner', 0o755)!
	os.write_file(root + '/runtime/closure.txt', 'enumerated runtime resources')!
	os.write_file(root + '/licenses/application-LICENSE.txt', 'Fixture only; no commercial redistribution rights.')!
	os.write_file(root + '/licenses/runtime-LICENSE.txt', 'Fixture runtime license.')!
	os.mkdir_all(work + '/recipes/aarch64')!
	for role in ['application', 'runtime'] { os.write_file(work + '/recipes/aarch64/' + role + '.json', json2.encode(owner_fixture_recipe(role == 'application')))! }
	return work
}

// Native writes keep fixture file-helper storage out of production measurements.
fn builder_write(path string, text string) ! {
	fd := C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_TRUNC | C.O_CLOEXEC | C.O_NOFOLLOW, 0o644)
	if fd < 0 { return error('cannot create Apple builder fault fixture') }
	defer { C.close(fd) }
	assert C.write(fd, text.str, usize(text.len)) == text.len
}

fn builder_replace(path string, saved string) ! {
	assert C.rename(path.str, saved.str) == 0; assert C.mkdir(path.str, 0o700) == 0
	keep := path + '/keep'; defer { unsafe { keep.free() } }; builder_write(keep, 'preserved replacement')!
}

fn builder_checkpoint(phase string, stage string) ! {
	mode := os.getenv('VINIX_APPLE_OWNER_MODE'); defer { unsafe { mode.free() } }
	if phase == 'created' { assert C.setenv(c'VINIX_APPLE_OWNER_STAGE', stage.str, 1) == 0 }
	if mode == phase { return error('injected Apple builder checkpoint refusal') }
	if mode.starts_with('packed-') && phase == 'packed' {
		index := int(mode[7] - `1`)
		ids := ['org.example.apple-aarch64', 'org.example.ios-runtime-aarch64']!
		version := '1.0.0'
		path := stage + '/inventory/manifests/' + ids[index] + '-' + version + '.json'; defer { unsafe { path.free() } }
		if publisher_entry_exists(path) { return error('injected Apple builder checkpoint refusal') }
	}
	if phase == 'created' && mode in ['root-replaced', 'inventory-replaced', 'lock-replaced']! {
		saved := os.getenv('VINIX_APPLE_OWNER_SAVED'); defer { unsafe { saved.free() } }
		child := if mode == 'inventory-replaced' { 'inventory' } else { 'lock' }
		path := if mode == 'root-replaced' { stage.clone() } else { stage + '/' + child }
		defer { unsafe { path.free() } }; builder_replace(path, saved)!
	}
	if phase == 'created' && mode.starts_with('import-') {
		roots := os.getenv('VINIX_APPLE_OWNER_ROOTS'); defer { unsafe { roots.free() } }
		child := if mode == 'import-macho' { 'app/Example' } else if mode == 'import-elf' || mode == 'import-mode' { 'runtime/runner' } else if mode == 'import-plist' { 'app/Info.plist' } else { 'licenses/runtime-LICENSE.txt' }
		path := roots + '/aarch64/' + child; defer { unsafe { path.free() } }
		if mode in ['import-macho', 'import-elf', 'import-plist']! {
			fd := C.open(path.str, C.O_WRONLY | C.O_CLOEXEC | C.O_NOFOLLOW); assert fd >= 0; defer { C.close(fd) }
			byte := [u8(0)]!; assert C.pwrite(fd, &byte[0], 1, 0) == 1
		} else if mode == 'import-mode' { assert C.chmod(path.str, 0o644) == 0 }
		else if mode == 'import-notice' { builder_write(path, '')! }
		else { assert C.unlinkat(C.AT_FDCWD, path.str, 0) == 0; assert C.mkdir(path.str, 0o700) == 0 }
	}
	if phase == 'created' && mode == 'changed-template' {
		root := os.getenv('VINIX_APPLE_OWNER_RECIPES'); path := root + '/aarch64/application.json'
		defer { unsafe { root.free(); path.free() } }; builder_write(path, '{}')!
	}

	if phase == 'ready' && mode == 'changed-lock' {
		path := stage + '/lock/catalog.json'; defer { unsafe { path.free() } }; builder_write(path, '{}')!
	}
	if phase == 'ready' && mode == 'raced-target' {
		path := os.getenv('VINIX_APPLE_OWNER_TARGET'); defer { unsafe { path.free() } }; assert C.mkdir(path.str, 0o700) == 0
		keep := path + '/keep'; defer { unsafe { keep.free() } }; builder_write(keep, 'preserved replacement')!
	}
}

fn builder_space(path string) !u64 {
	mode := os.getenv('VINIX_APPLE_OWNER_MODE'); parent := os.getenv('VINIX_APPLE_OWNER_PARENT')
	defer { unsafe { mode.free(); parent.free() } }
	if mode == 'space-error' { return error('injected Apple space query refusal') }
	if (mode == 'no-output-space' && path == parent) || (mode == 'no-temp-space' && path != parent) { return 0 }
	return ~u64(0)
}

fn builder_flush(fd int) int {
	mode := os.getenv('VINIX_APPLE_OWNER_MODE'); defer { unsafe { mode.free() } }
	if mode == 'flush' { return -1 }
	if mode == 'cleanup' {
		stage := os.getenv('VINIX_APPLE_OWNER_STAGE'); saved := os.getenv('VINIX_APPLE_OWNER_SAVED')
		path := stage + '/inventory'; defer { unsafe { stage.free(); saved.free(); path.free() } }
		builder_replace(path, saved) or { panic(err) }
	}
	return atomic_flush(fd)
}

fn builder_remove(path string) ! {
	if os.is_dir(path) { os.rmdir_all(path)! } else if os.exists(path) || os.is_link(path) { os.rm(path)! }
}

fn builder_reset(fixture string, target string) ! {
	builder_remove(target)!; builder_remove(fixture + '/saved')!
	for name in os.ls(fixture)! { if name.starts_with('.vinix-apple-profile-') { os.rmdir_all(fixture + '/' + name)! } }
}

fn builder_prepare(mode string, fixture string) ! {
	roots := fixture + '/roots'; path := roots + '/aarch64/licenses/runtime-LICENSE.txt'
	app := owner_fixture_recipe(true); runtime := owner_fixture_recipe(false)
	mut changed := app
	match mode {
		'missing-recipe' { os.rm(fixture + '/recipes/aarch64/runtime.json')! }
		'invalid-json' { os.write_file(fixture + '/recipes/aarch64/application.json', '{')! }
		'invalid-schema' { os.write_file(fixture + '/recipes/aarch64/application.json', '{"unknown":0}')! }
		'wrong-architecture' { changed = RootRecipe{ ...app, manifest: Package{ ...app.manifest, architecture: 'all' } } }
		'pinned-template' { changed = RootRecipe{ ...app, manifest: Package{ ...app.manifest, files: [Payload{ path: 'Example.app/Example', bytes: 1, sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' }] } } }
		'firmware' { changed = RootRecipe{ ...app, manifest: Package{ ...app.manifest, firmware: true } } }
		'app-kind' { changed = RootRecipe{ ...app, manifest: Package{ ...app.manifest, kind: 'linux' } } }
		'unbounded-runtime' { changed = RootRecipe{ ...app, manifest: Package{ ...app.manifest, dependencies: [Dependency{ id: app.manifest.runtime, minimum: '1.0.0' }] } } }
		'missing-selector' { changed = RootRecipe{ ...app, entries: [app.entries[0]] } }
		'runtime-grants' { os.write_file(fixture + '/recipes/aarch64/runtime.json', json2.encode(RootRecipe{ ...runtime, manifest: Package{ ...runtime.manifest, permissions: ['network'] } }))! }
		'runtime-mismatch' { os.write_file(fixture + '/recipes/aarch64/runtime.json', json2.encode(RootRecipe{ ...runtime, manifest: Package{ ...runtime.manifest, id: 'org.example.other' } }))! }
		'missing-architecture' { os.rename(roots + '/aarch64', fixture + '/saved-root')! }
		'wrong-target' { os.write_file_array(roots + '/aarch64/runtime/runner', elffixture.image('x86_64', 'static'))! }
		'wrong-mode' { os.chmod(roots + '/aarch64/runtime/runner', 0o644)! }
		'wrong-macho' { os.write_file(roots + '/aarch64/app/Example', 'invalid Mach-O')! }
		'wrong-plist' { os.write_file(roots + '/aarch64/app/Info.plist', owner_fixture_info('other.app'))! }
		'invalid-plist' { os.write_file(roots + '/aarch64/app/Info.plist', '<plist><dict>')! }
		'empty-arguments' { changed = RootRecipe{ ...app, manifest: Package{ ...app.manifest, arguments: []string{} } } }
		'nested-program' { changed = RootRecipe{ ...app, manifest: Package{ ...app.manifest, arguments: ['@APP@/Example.app/nested/Example'] } } }
		'missing-notice' { os.rm(path)! } 'empty-notice' { os.write_file(path, '')! }
		'notice-directory' { os.rm(path)!; os.mkdir(path)! } else {}
	}
	if mode in ['wrong-architecture', 'pinned-template', 'firmware', 'app-kind', 'unbounded-runtime', 'missing-selector', 'empty-arguments', 'nested-program']! { os.write_file(fixture + '/recipes/aarch64/application.json', json2.encode(changed))! }
}

fn builder_restore(fixture string) ! {
	roots := fixture + '/roots'
	if os.is_dir(fixture + '/saved-root') { os.rename(fixture + '/saved-root', roots + '/aarch64')! }
	path := roots + '/aarch64/licenses/runtime-LICENSE.txt'
	if os.is_dir(path) { os.rmdir_all(path)! }
	os.write_file(path, 'Fixture runtime license.')!
	os.write_file_array(roots + '/aarch64/runtime/runner', elffixture.image('aarch64', 'static'))!; os.chmod(roots + '/aarch64/runtime/runner', 0o755)!
	os.write_file_array(roots + '/aarch64/app/Example', applefixture.image(23))!
	info := roots + '/aarch64/app/Info.plist'
	if os.is_dir(info) { os.rmdir_all(info)! }
	os.write_file(info, owner_fixture_info('org.example.apple'))!
	for role in ['application', 'runtime']! { os.write_file(fixture + '/recipes/aarch64/' + role + '.json', json2.encode(owner_fixture_recipe(role == 'application')))! }
}

fn builder_attempt(mode string, recipes string, roots string, target string) {
	input := if mode == 'missing-root' { roots + '/missing' } else { roots.clone() }
	declarations := if mode == 'missing-recipes' { recipes + '/missing' } else { recipes.clone() }
	defer { unsafe { input.free(); declarations.free() } }
	if result := apple_catalog_with(declarations, input, target, CatalogOptions{ checkpoint: builder_checkpoint, available_space: builder_space, flush: builder_flush }) {
		mut info := result; $if !apple_owner_baseline ? { info.close(); info.close() }; assert mode in ['complete', 'nested', 'changed-template']!
	} else {
		message := err.msg(); defer { unsafe { message.free(); err.free() } }; assert mode !in ['complete', 'nested', 'changed-template']!
		expected := match mode {
			'missing-root' { 'prepared root' } 'missing-architecture' { 'ordinary directory' }
			'missing-recipes', 'missing-recipe' { 'metadata' } 'invalid-json' { 'incomplete administration document structure' } 'invalid-schema' { 'unknown' }
			'wrong-architecture', 'pinned-template', 'firmware' { 'unpinned AArch64' }
			'app-kind', 'unbounded-runtime' { 'bounded explicit runtime' } 'missing-selector' { 'explicit file selector' }
			'runtime-grants' { 'complete closure' } 'empty-arguments' { 'explicit @APP@' } 'nested-program' { 'invalid bundle executable path' } 'runtime-mismatch' { 'does not match' }
			'wrong-target' { 'wrong ELF target/type' } 'wrong-mode' { 'ordinary executable' } 'wrong-macho' { 'ordinary Mach-O executable' } 'wrong-plist' { 'disagrees with its declared' } 'invalid-plist' { 'plist:' }
			'missing-notice' { 'cannot open prepared guest path' } 'empty-notice' { 'nonempty redistribution notices' } 'notice-directory' { 'individual ordinary files' }
			'no-output-space', 'no-temp-space' { 'insufficient disk space' } 'space-error' { 'injected Apple space query' }
			'created', 'ready', 'packed-1', 'packed-2' { 'injected Apple builder checkpoint' }
			'import-macho' { 'thin plain ARM64' } 'import-plist' { 'plist:' } 'import-elf' { 'wrong ELF target/type' } 'import-mode' { 'lost executable permission' }
			'import-notice' { 'invalid redistribution/build notice' } 'import-directory' { 'unexpected payload inventory' }
			'changed-lock' { 'catalog lock changed' } 'occupied' { 'destination must be new' } 'raced-target' { 'without replacing' } 'flush' { 'directory flush failed' }
			'cleanup', 'root-replaced', 'inventory-replaced', 'lock-replaced' { 'cleanup refused' } else { panic(mode) }
		}
		assert message.contains(expected), message
		if mode in ['flush', 'cleanup']! { assert message.contains('published at ') }
	}
}

fn test_complete_apple_builder_retires_success_partial_import_and_publication_refusal_storage() {
	defer { for key in ['MODE', 'ROOTS', 'TARGET', 'PARENT', 'STAGE', 'SAVED', 'RECIPES']! { os.unsetenv('VINIX_APPLE_OWNER_' + key) } }
	for mode in ['complete', 'nested', 'missing-recipes', 'missing-recipe', 'invalid-json', 'invalid-schema', 'wrong-architecture', 'pinned-template', 'firmware', 'app-kind', 'unbounded-runtime', 'missing-selector', 'runtime-grants', 'empty-arguments', 'nested-program', 'runtime-mismatch',
		'missing-root', 'missing-architecture', 'wrong-macho', 'wrong-plist', 'invalid-plist', 'wrong-target', 'wrong-mode', 'missing-notice', 'empty-notice', 'notice-directory', 'no-output-space', 'no-temp-space', 'space-error', 'created',
		'packed-1', 'packed-2', 'ready', 'import-macho', 'import-plist', 'import-elf', 'import-mode', 'import-notice', 'import-directory', 'changed-template', 'changed-lock', 'occupied', 'raced-target', 'flush', 'cleanup', 'root-replaced', 'inventory-replaced', 'lock-replaced']! {
		if !builder_selected(mode) { continue }
		fixture := owner_fixture()!; defer { os.rmdir_all(fixture) or {} }
		recipes := fixture + '/recipes'; roots := fixture + '/roots'; target := fixture + if mode == 'nested' { '/new/parent/lock' } else { '/lock' }
		// Initialize JSON metadata outside the complete-call measurement.
		mut warm := apple_catalog(recipes, roots, target)!; $if !apple_owner_baseline ? { warm.close(); warm.close() }; builder_remove(target)!
		os.setenv('VINIX_APPLE_OWNER_MODE', mode, true); os.setenv('VINIX_APPLE_OWNER_ROOTS', roots, true)
		os.setenv('VINIX_APPLE_OWNER_TARGET', target, true); os.setenv('VINIX_APPLE_OWNER_PARENT', os.dir(target), true)
		os.setenv('VINIX_APPLE_OWNER_RECIPES', recipes, true)
		os.setenv('VINIX_APPLE_OWNER_SAVED', fixture + '/saved', true); builder_prepare(mode, fixture)!
		mut original := AppleBuilderLimit{}; assert C.getrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0
		limit := AppleBuilderLimit{ current: 32, maximum: original.maximum }; assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &limit }) == 0
		before := builder_descriptors(); mut maximum := u64(0); mut records := u32(0)
		for _ in 0 .. 8 {
			builder_reset(fixture, target)!
			if mode == 'nested' { builder_remove(fixture + '/new')! }
			if mode == 'occupied' { os.write_file(target, 'preserved replacement')! }
			if mode.starts_with('import-') || mode == 'changed-template' { builder_restore(fixture)! }
			$if track_heap ? { C.vinix_heap_begin() }
			builder_attempt(mode, recipes, roots, target)
			$if track_heap ? {
				kept := C.vinix_heap_end(); count := C.vinix_heap_count()
				if kept > maximum { maximum = kept }; if count > records { records = count }
			}
			assert builder_descriptors() == before
			published := mode in ['complete', 'nested', 'changed-template', 'flush', 'cleanup']!
			assert os.is_file(target + '/catalog.json') == published
			if published { assert index_digest(os.read_file(target + '/catalog.json')!) == '86bec8ad8127402ffbd4fe94c1b845902e4b3c2785a2bcdc36237aa2c9ac435d' }
			if mode == 'occupied' { assert os.read_file(target)! == 'preserved replacement' }
			if mode == 'raced-target' { assert os.read_file(target + '/keep')! == 'preserved replacement' }
			if mode in ['cleanup', 'root-replaced', 'inventory-replaced', 'lock-replaced']! {
				stage := os.getenv('VINIX_APPLE_OWNER_STAGE'); saved := fixture + '/saved'; assert os.is_dir(saved)
				path := if mode == 'root-replaced' { stage.clone() } else { stage + '/' + if mode == 'lock-replaced' { 'lock' } else { 'inventory' } }
				assert os.read_file(path + '/keep')! == 'preserved replacement'
			} else { assert os.ls(fixture)!.all(!it.starts_with('.vinix-apple-profile-')) }
		}
		assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0
		$if track_heap ? {
			println('APPLE OWNER case=' + mode + ' retained=' + maximum.str() + ' allocations=' + records.str())
			$if !apple_owner_baseline ? { assert maximum == 0 && records == 0 }
		}
		builder_reset(fixture, target)!; builder_restore(fixture)!; os.unsetenv('VINIX_APPLE_OWNER_MODE')
		mut retried := apple_catalog(recipes, roots, target)!; $if !apple_owner_baseline ? { retried.close(); retried.close() }
		assert index_digest(os.read_file(target + '/catalog.json')!) == '86bec8ad8127402ffbd4fe94c1b845902e4b3c2785a2bcdc36237aa2c9ac435d'
		assert os.read_file(roots + '/aarch64/licenses/runtime-LICENSE.txt')! == 'Fixture runtime license.'
		assert os.read_bytes(roots + '/aarch64/runtime/runner')! == elffixture.image('aarch64', 'static')
		println('APPLE OWNER ' + mode + ' canonical retry, saved output, source and descriptor preservation PASS')
	}
}
