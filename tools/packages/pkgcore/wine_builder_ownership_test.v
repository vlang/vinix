// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time
import tests.packages.elffixture

#include <sys/resource.h>
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int
fn C.setenv(&char, &char, int) int
fn C.pwrite(int, voidptr, usize, i64) isize
struct WineBuilderLimit { current u64 maximum u64 }

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

fn owner_put(mut bytes []u8, offset int, value u64, width int) {
	for index in 0 .. width { bytes[offset + index] = u8(value >> (index * 8)) }
}

// Structural fixtures only: neither this PE nor the ELF launcher is executed.
fn owner_fixture_pe() []u8 {
	mut bytes := []u8{len: 1024}
	bytes[0] = `M`; bytes[1] = `Z`
	owner_put(mut bytes, 60, 128, 4)
	bytes[128] = `P`; bytes[129] = `E`
	owner_put(mut bytes, 132, 0x8664, 2)
	owner_put(mut bytes, 134, 1, 2)
	owner_put(mut bytes, 148, 240, 2)
	owner_put(mut bytes, 150, 2, 2)
	owner_put(mut bytes, 152, 0x20b, 2)
	owner_put(mut bytes, 168, 0x1000, 4)
	owner_put(mut bytes, 208, 0x2000, 4)
	owner_put(mut bytes, 212, 512, 4)
	owner_put(mut bytes, 220, 3, 2)
	owner_put(mut bytes, 400, 512, 4)
	owner_put(mut bytes, 404, 0x1000, 4)
	owner_put(mut bytes, 408, 512, 4)
	owner_put(mut bytes, 412, 512, 4)
	owner_put(mut bytes, 428, 0x60000020, 4)
	bytes[512] = 0xc3
	return bytes
}

fn owner_fixture_recipe(architecture string, application bool) RootRecipe {
	return if application {
		RootRecipe{ manifest: Package{ id: 'org.example.win64', version: '1.0.0', architecture: architecture,
			name: 'Reviewed Win64 application', description: 'Explicit publisher-supplied compatibility closure.',
			license: 'Example-EULA', proprietary: true, kind: 'windows', runtime: 'org.example.wine',
			entrypoint: 'bin/wine-runner', arguments: ['@APP@/bin/program.exe', 'literal ; $ argument'],
			permissions: ['files', 'process'], associations: ['text/plain'],
			dependencies: [Dependency{ id: 'org.example.wine', minimum: '1.0.0', before: '2.0.0' }] },
			entries: [RootEntry{ source: 'app/program.exe', path: 'bin/program.exe' },
				RootEntry{ source: 'licenses/application-LICENSE.txt', path: wine_application_notice }] }
	} else {
		RootRecipe{ manifest: Package{ id: 'org.example.wine', version: '1.0.0', architecture: architecture,
			name: 'Reviewed Wine closure', license: 'LGPL-2.1-or-later', kind: 'runtime' },
			entries: [RootEntry{ source: 'runtime/runner', path: 'bin/wine-runner' },
				RootEntry{ source: 'runtime/closure.txt', path: 'share/closure.txt' },
				RootEntry{ source: 'licenses/runtime-LICENSE.txt', path: wine_runtime_notice }] }
	}
}

fn owner_fixture() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-wine-profile-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	for architecture in ['aarch64', 'x86_64'] {
		root := work + '/roots/' + architecture
		for directory in ['app', 'runtime', 'licenses'] { os.mkdir_all(root + '/' + directory)! }
		os.write_file_array(root + '/app/program.exe', owner_fixture_pe())!
		os.write_file_array(root + '/runtime/runner', elffixture.image(architecture, 'static'))!
		os.chmod(root + '/runtime/runner', 0o755)!
		os.write_file(root + '/runtime/closure.txt', 'publisher enumerated runtime resources ' + architecture)!
		os.write_file(root + '/licenses/application-LICENSE.txt', 'Fixture license; not permission to distribute a commercial application.')!
		os.write_file(root + '/licenses/runtime-LICENSE.txt', 'Fixture runtime license.')!
		os.mkdir_all(work + '/recipes/' + architecture)!
		for role in ['application', 'runtime'] {
			os.write_file(work + '/recipes/' + architecture + '/' + role + '.json',
				json2.encode(owner_fixture_recipe(architecture, role == 'application')))!
		}
	}
	return work
}
// Native writes keep fixture file-helper storage out of production measurements.
fn builder_write(path string, text string) ! {
	fd := C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_TRUNC | C.O_CLOEXEC | C.O_NOFOLLOW, 0o644)
	if fd < 0 { return error('cannot create Wine builder fault fixture') }
	defer { C.close(fd) }
	assert C.write(fd, text.str, usize(text.len)) == text.len
}

fn builder_replace(path string, saved string) ! {
	assert C.rename(path.str, saved.str) == 0; assert C.mkdir(path.str, 0o700) == 0
	keep := path + '/keep'; defer { unsafe { keep.free() } }; builder_write(keep, 'preserved replacement')!
}

fn builder_checkpoint(phase string, stage string) ! {
	mode := os.getenv('VINIX_WINE_OWNER_MODE'); defer { unsafe { mode.free() } }
	if phase == 'created' { assert C.setenv(c'VINIX_WINE_OWNER_STAGE', stage.str, 1) == 0 }
	if mode == phase { return error('injected Wine builder checkpoint refusal') }
	if mode.starts_with('packed-') && phase == 'packed' {
		index := int(mode[7] - `1`)
		ids := ['org.example.win64-aarch64', 'org.example.wine-aarch64', 'org.example.win64-x86_64', 'org.example.wine-x86_64']!
		version := '1.0.0'
		path := stage + '/inventory/manifests/' + ids[index] + '-' + version + '.json'; defer { unsafe { path.free() } }
		if publisher_entry_exists(path) { return error('injected Wine builder checkpoint refusal') }
	}
	if phase == 'created' && mode in ['root-replaced', 'inventory-replaced', 'lock-replaced']! {
		saved := os.getenv('VINIX_WINE_OWNER_SAVED'); defer { unsafe { saved.free() } }
		child := if mode == 'inventory-replaced' { 'inventory' } else { 'lock' }
		path := if mode == 'root-replaced' { stage.clone() } else { stage + '/' + child }
		defer { unsafe { path.free() } }; builder_replace(path, saved)!
	}
	if phase == 'created' && mode.starts_with('import-') {
		roots := os.getenv('VINIX_WINE_OWNER_ROOTS'); defer { unsafe { roots.free() } }
		child := if mode == 'import-pe' { 'app/program.exe' } else if mode == 'import-elf' || mode == 'import-mode' { 'runtime/runner' } else { 'licenses/runtime-LICENSE.txt' }
		path := roots + '/x86_64/' + child; defer { unsafe { path.free() } }
		if mode in ['import-pe', 'import-elf']! {
			fd := C.open(path.str, C.O_WRONLY | C.O_CLOEXEC | C.O_NOFOLLOW); assert fd >= 0; defer { C.close(fd) }
			byte := [u8(0)]!; assert C.pwrite(fd, &byte[0], 1, 0) == 1
		} else if mode == 'import-mode' { assert C.chmod(path.str, 0o644) == 0 }
		else if mode == 'import-notice' { builder_write(path, '')! }
		else { assert C.unlinkat(C.AT_FDCWD, path.str, 0) == 0; assert C.mkdir(path.str, 0o700) == 0 }
	}
	if phase == 'created' && mode == 'changed-template' {
		root := os.getenv('VINIX_WINE_OWNER_RECIPES'); path := root + '/x86_64/application.json'
		defer { unsafe { root.free(); path.free() } }; builder_write(path, '{}')!
	}

	if phase == 'ready' && mode == 'changed-lock' {
		path := stage + '/lock/catalog.json'; defer { unsafe { path.free() } }; builder_write(path, '{}')!
	}
	if phase == 'ready' && mode == 'raced-target' {
		path := os.getenv('VINIX_WINE_OWNER_TARGET'); defer { unsafe { path.free() } }; assert C.mkdir(path.str, 0o700) == 0
		keep := path + '/keep'; defer { unsafe { keep.free() } }; builder_write(keep, 'preserved replacement')!
	}
}

fn builder_space(path string) !u64 {
	mode := os.getenv('VINIX_WINE_OWNER_MODE'); parent := os.getenv('VINIX_WINE_OWNER_PARENT')
	defer { unsafe { mode.free(); parent.free() } }
	if mode == 'space-error' { return error('injected Wine space query refusal') }
	if (mode == 'no-output-space' && path == parent) || (mode == 'no-temp-space' && path != parent) { return 0 }
	return ~u64(0)
}

fn builder_flush(fd int) int {
	mode := os.getenv('VINIX_WINE_OWNER_MODE'); defer { unsafe { mode.free() } }
	if mode == 'flush' { return -1 }
	if mode == 'cleanup' {
		stage := os.getenv('VINIX_WINE_OWNER_STAGE'); saved := os.getenv('VINIX_WINE_OWNER_SAVED')
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
	for name in os.ls(fixture)! { if name.starts_with('.vinix-wine-profile-') { os.rmdir_all(fixture + '/' + name)! } }
}

fn builder_prepare(mode string, fixture string) ! {
	roots := fixture + '/roots'; path := roots + '/x86_64/licenses/runtime-LICENSE.txt'
	app := owner_fixture_recipe('x86_64', true); runtime := owner_fixture_recipe('x86_64', false)
	mut changed := app
	match mode {
		'missing-recipe' { os.rm(fixture + '/recipes/x86_64/runtime.json')! }
		'invalid-json' { os.write_file(fixture + '/recipes/x86_64/application.json', '{')! }
		'invalid-schema' { os.write_file(fixture + '/recipes/x86_64/application.json', '{"unknown":0}')! }
		'wrong-architecture' { changed = RootRecipe{ ...app, manifest: Package{ ...app.manifest, architecture: 'all' } } }
		'pinned-template' { changed = RootRecipe{ ...app, manifest: Package{ ...app.manifest, files: [Payload{ path: 'bin/program.exe', bytes: 1, sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' }] } } }
		'firmware' { changed = RootRecipe{ ...app, manifest: Package{ ...app.manifest, firmware: true } } }
		'app-kind' { changed = RootRecipe{ ...app, manifest: Package{ ...app.manifest, kind: 'linux' } } }
		'unbounded-runtime' { changed = RootRecipe{ ...app, manifest: Package{ ...app.manifest, dependencies: [Dependency{ id: app.manifest.runtime, minimum: '1.0.0' }] } } }
		'missing-selector' { changed = RootRecipe{ ...app, entries: [app.entries[0]] } }
		'host-mismatch' { changed = RootRecipe{ ...app, manifest: Package{ ...app.manifest, proprietary: false } } }
		'runtime-grants' { os.write_file(fixture + '/recipes/x86_64/runtime.json', json2.encode(RootRecipe{ ...runtime, manifest: Package{ ...runtime.manifest, permissions: ['network'] } }))! }
		'runtime-mismatch' { for arch in ['aarch64', 'x86_64']! { r := owner_fixture_recipe(arch, false); os.write_file(fixture + '/recipes/' + arch + '/runtime.json', json2.encode(RootRecipe{ ...r, manifest: Package{ ...r.manifest, id: 'org.example.other' } }))! } }
		'missing-architecture' { os.rename(roots + '/x86_64', fixture + '/saved-root')! }
		'wrong-target' { os.write_file_array(roots + '/x86_64/runtime/runner', elffixture.image('aarch64', 'static'))! }
		'wrong-mode' { os.chmod(roots + '/x86_64/runtime/runner', 0o644)! }
		'wrong-pe' { os.write_file(roots + '/x86_64/app/program.exe', 'invalid PE')! }
		'missing-notice' { os.rm(path)! } 'empty-notice' { os.write_file(path, '')! }
		'notice-directory' { os.rm(path)!; os.mkdir(path)! } else {}
	}
	if mode in ['wrong-architecture', 'pinned-template', 'firmware', 'app-kind', 'unbounded-runtime', 'missing-selector', 'host-mismatch']! { os.write_file(fixture + '/recipes/x86_64/application.json', json2.encode(changed))! }
}

fn builder_restore(fixture string) ! {
	roots := fixture + '/roots'
	if os.is_dir(fixture + '/saved-root') { os.rename(fixture + '/saved-root', roots + '/x86_64')! }
	path := roots + '/x86_64/licenses/runtime-LICENSE.txt'
	if os.is_dir(path) { os.rmdir_all(path)! }
	os.write_file(path, 'Fixture runtime license.')!
	os.write_file_array(roots + '/x86_64/runtime/runner', elffixture.image('x86_64', 'static'))!; os.chmod(roots + '/x86_64/runtime/runner', 0o755)!
	os.write_file_array(roots + '/x86_64/app/program.exe', owner_fixture_pe())!
	for arch in ['aarch64', 'x86_64']! { for role in ['application', 'runtime']! { os.write_file(fixture + '/recipes/' + arch + '/' + role + '.json', json2.encode(owner_fixture_recipe(arch, role == 'application')))! } }
}

fn builder_attempt(mode string, recipes string, roots string, target string) {
	input := if mode == 'missing-root' { roots + '/missing' } else { roots.clone() }
	declarations := if mode == 'missing-recipes' { recipes + '/missing' } else { recipes.clone() }
	defer { unsafe { input.free(); declarations.free() } }
	if result := wine_catalog_with(declarations, input, target, CatalogOptions{ checkpoint: builder_checkpoint, available_space: builder_space, flush: builder_flush }) {
		mut info := result; $if !wine_owner_baseline ? { info.close(); info.close() }; assert mode in ['complete', 'nested', 'changed-template']!
	} else {
		message := err.msg(); defer { unsafe { message.free(); err.free() } }; assert mode !in ['complete', 'nested', 'changed-template']!
		expected := match mode {
			'missing-root' { 'prepared root' } 'missing-architecture' { 'ordinary directory' }
			'missing-recipes', 'missing-recipe' { 'metadata' } 'invalid-json' { 'incomplete administration document structure' } 'invalid-schema' { 'unknown' }
			'wrong-architecture', 'pinned-template', 'firmware' { 'target-specific unpinned' }
			'app-kind', 'unbounded-runtime' { 'bounded explicit runtime' } 'missing-selector' { 'explicit file selector' }
			'runtime-grants' { 'complete closure' } 'host-mismatch' { 'declarations must match' } 'runtime-mismatch' { 'does not match' }
			'wrong-target' { 'wrong ELF target/type' } 'wrong-mode' { 'ordinary executable' } 'wrong-pe' { 'ordinary Win64 executable' }
			'missing-notice' { 'cannot open prepared guest path' } 'empty-notice' { 'nonempty redistribution notices' } 'notice-directory' { 'individual ordinary files' }
			'no-output-space', 'no-temp-space' { 'insufficient disk space' } 'space-error' { 'injected Wine space query' }
			'created', 'ready', 'packed-1', 'packed-2', 'packed-3', 'packed-4' { 'injected Wine builder checkpoint' }
			'import-pe' { 'invalid DOS/PE headers' } 'import-elf' { 'wrong ELF target/type' } 'import-mode' { 'lost executable permission' }
			'import-notice' { 'invalid redistribution/build notice' } 'import-directory' { 'unexpected payload inventory' }
			'changed-lock' { 'catalog lock changed' } 'occupied' { 'destination must be new' } 'raced-target' { 'without replacing' } 'flush' { 'directory flush failed' }
			'cleanup', 'root-replaced', 'inventory-replaced', 'lock-replaced' { 'cleanup refused' } else { panic(mode) }
		}
		assert message.contains(expected), message
		if mode in ['flush', 'cleanup']! { assert message.contains('published at ') }
	}
}

fn test_complete_wine_builder_retires_success_partial_import_and_publication_refusal_storage() {
	defer { for key in ['MODE', 'ROOTS', 'TARGET', 'PARENT', 'STAGE', 'SAVED', 'RECIPES']! { os.unsetenv('VINIX_WINE_OWNER_' + key) } }
	for mode in ['complete', 'nested', 'missing-recipes', 'missing-recipe', 'invalid-json', 'invalid-schema', 'wrong-architecture', 'pinned-template', 'firmware', 'app-kind', 'unbounded-runtime', 'missing-selector', 'runtime-grants', 'host-mismatch', 'runtime-mismatch',
		'missing-root', 'missing-architecture', 'wrong-pe', 'wrong-target', 'wrong-mode', 'missing-notice', 'empty-notice', 'notice-directory', 'no-output-space', 'no-temp-space', 'space-error', 'created',
		'packed-1', 'packed-2', 'packed-3', 'packed-4', 'ready', 'import-pe', 'import-elf', 'import-mode', 'import-notice', 'import-directory', 'changed-template', 'changed-lock', 'occupied', 'raced-target', 'flush', 'cleanup', 'root-replaced', 'inventory-replaced', 'lock-replaced']! {
		if !builder_selected(mode) { continue }
		fixture := owner_fixture()!; defer { os.rmdir_all(fixture) or {} }
		recipes := fixture + '/recipes'; roots := fixture + '/roots'; target := fixture + if mode == 'nested' { '/new/parent/lock' } else { '/lock' }
		// Initialize JSON metadata outside the complete-call measurement.
		mut warm := wine_catalog(recipes, roots, target)!; $if !wine_owner_baseline ? { warm.close(); warm.close() }; builder_remove(target)!
		os.setenv('VINIX_WINE_OWNER_MODE', mode, true); os.setenv('VINIX_WINE_OWNER_ROOTS', roots, true)
		os.setenv('VINIX_WINE_OWNER_TARGET', target, true); os.setenv('VINIX_WINE_OWNER_PARENT', os.dir(target), true)
		os.setenv('VINIX_WINE_OWNER_RECIPES', recipes, true)
		os.setenv('VINIX_WINE_OWNER_SAVED', fixture + '/saved', true); builder_prepare(mode, fixture)!
		mut original := WineBuilderLimit{}; assert C.getrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0
		limit := WineBuilderLimit{ current: 32, maximum: original.maximum }; assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &limit }) == 0
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
			if published { assert index_digest(os.read_file(target + '/catalog.json')!) == '90db70b6721ee1375480ecdefb080c3d51d5cb3251b419ad942fc305065d3f35' }
			if mode == 'occupied' { assert os.read_file(target)! == 'preserved replacement' }
			if mode == 'raced-target' { assert os.read_file(target + '/keep')! == 'preserved replacement' }
			if mode in ['cleanup', 'root-replaced', 'inventory-replaced', 'lock-replaced']! {
				stage := os.getenv('VINIX_WINE_OWNER_STAGE'); saved := fixture + '/saved'; assert os.is_dir(saved)
				path := if mode == 'root-replaced' { stage.clone() } else { stage + '/' + if mode == 'lock-replaced' { 'lock' } else { 'inventory' } }
				assert os.read_file(path + '/keep')! == 'preserved replacement'
			} else { assert os.ls(fixture)!.all(!it.starts_with('.vinix-wine-profile-')) }
		}
		assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0
		$if track_heap ? {
			println('WINE OWNER case=' + mode + ' retained=' + maximum.str() + ' allocations=' + records.str())
			$if !wine_owner_baseline ? { assert maximum == 0 && records == 0 }
		}
		builder_reset(fixture, target)!; builder_restore(fixture)!; os.unsetenv('VINIX_WINE_OWNER_MODE')
		mut retried := wine_catalog(recipes, roots, target)!; $if !wine_owner_baseline ? { retried.close(); retried.close() }
		assert index_digest(os.read_file(target + '/catalog.json')!) == '90db70b6721ee1375480ecdefb080c3d51d5cb3251b419ad942fc305065d3f35'
		assert os.read_file(roots + '/aarch64/licenses/runtime-LICENSE.txt')! == 'Fixture runtime license.'
		assert os.read_bytes(roots + '/aarch64/runtime/runner')! == elffixture.image('aarch64', 'static')
		println('WINE OWNER ' + mode + ' canonical retry, saved output, source and descriptor preservation PASS')
	}
}
