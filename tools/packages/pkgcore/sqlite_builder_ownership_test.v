// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time
import tests.packages.elffixture

#include <sys/resource.h>
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int
fn C.setenv(&char, &char, int) int
fn C.pwrite(int, voidptr, usize, i64) isize
struct SqliteBuilderLimit { current u64 maximum u64 }

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

fn builder_fixture() !string {
	path := os.real_path(os.temp_dir()) + '/vinix-sqlite-builder-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	for architecture in ['aarch64', 'x86_64']! {
		root := path + '/roots/' + architecture
		for name in ['bin', 'lib', 'licenses']! { os.mkdir_all(root + '/' + name)! }
		for index, name in ['bin/sqlite3', 'bin/vinix-linux-runner', 'lib/libc.so', 'lib/libsqlite3.so.0']! {
			kind := if index == 0 { 'pie' } else if index == 1 { 'static' } else { 'shared' }
			os.write_file_array(root + '/' + name, elffixture.image(architecture, kind))!; os.chmod(root + '/' + name, 0o755)!
		}
		for name in ['sqlite-COPYRIGHT', 'musl-COPYRIGHT', 'vinix-COPYING']! { os.write_file(root + '/licenses/' + name, name)! }
	}
	return path
}

// Native writes keep fixture file-helper storage out of production measurements.
fn builder_write(path string, text string) ! {
	fd := C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_TRUNC | C.O_CLOEXEC | C.O_NOFOLLOW, 0o644)
	if fd < 0 { return error('cannot create SQLite builder fault fixture') }
	defer { C.close(fd) }
	assert C.write(fd, text.str, usize(text.len)) == text.len
}

fn builder_replace(path string, saved string) ! {
	assert C.rename(path.str, saved.str) == 0; assert C.mkdir(path.str, 0o700) == 0
	keep := path + '/keep'; defer { unsafe { keep.free() } }; builder_write(keep, 'preserved replacement')!
}

fn builder_checkpoint(phase string, stage string) ! {
	mode := os.getenv('VINIX_SQLITE_BUILDER_MODE'); defer { unsafe { mode.free() } }
	if phase == 'created' { assert C.setenv(c'VINIX_SQLITE_BUILDER_STAGE', stage.str, 1) == 0 }
	if mode == phase { return error('injected SQLite builder checkpoint refusal') }
	if mode.starts_with('packed-') && phase == 'packed' {
		index := int(mode[7] - `1`)
		ids := ['org.sqlite.cli-aarch64', 'org.vinix.sqlite-runtime-aarch64', 'org.sqlite.cli-x86_64', 'org.vinix.sqlite-runtime-x86_64']!
		version := if index % 2 == 0 { '3.53.4' } else { '1.0.0' }
		path := stage + '/inventory/manifests/' + ids[index] + '-' + version + '.json'; defer { unsafe { path.free() } }
		if publisher_entry_exists(path) { return error('injected SQLite builder checkpoint refusal') }
	}
	if phase == 'created' && mode in ['root-replaced', 'inventory-replaced', 'lock-replaced']! {
		saved := os.getenv('VINIX_SQLITE_BUILDER_SAVED'); defer { unsafe { saved.free() } }
		child := if mode == 'inventory-replaced' { 'inventory' } else { 'lock' }
		path := if mode == 'root-replaced' { stage.clone() } else { stage + '/' + child }
		defer { unsafe { path.free() } }; builder_replace(path, saved)!
	}
	if phase == 'created' && mode.starts_with('import-') {
		roots := os.getenv('VINIX_SQLITE_BUILDER_ROOTS'); defer { unsafe { roots.free() } }
		child := if mode == 'import-elf' { 'bin/sqlite3' } else { 'licenses/musl-COPYRIGHT' }
		path := roots + '/x86_64/' + child
		defer { unsafe { path.free() } }
		if mode == 'import-elf' {
			fd := C.open(path.str, C.O_WRONLY | C.O_CLOEXEC | C.O_NOFOLLOW); assert fd >= 0; defer { C.close(fd) }
			bytes := [u8(1), 2, 0, 0, 0, 0, 0, 0]!
			assert C.pwrite(fd, &bytes[0], 8, 96) == 8
		} else if mode == 'import-notice' { builder_write(path, '')! }
		else { assert C.unlinkat(C.AT_FDCWD, path.str, 0) == 0; assert C.mkdir(path.str, 0o700) == 0 }
	}
	if phase == 'ready' && mode == 'changed-lock' {
		path := stage + '/lock/catalog.json'; defer { unsafe { path.free() } }; builder_write(path, '{}')!
	}
	if phase == 'ready' && mode == 'raced-target' {
		path := os.getenv('VINIX_SQLITE_BUILDER_TARGET'); defer { unsafe { path.free() } }; assert C.mkdir(path.str, 0o700) == 0
		keep := path + '/keep'; defer { unsafe { keep.free() } }; builder_write(keep, 'preserved replacement')!
	}
}

fn builder_space(path string) !u64 {
	mode := os.getenv('VINIX_SQLITE_BUILDER_MODE'); parent := os.getenv('VINIX_SQLITE_BUILDER_PARENT')
	defer { unsafe { mode.free(); parent.free() } }
	if mode == 'space-error' { return error('injected SQLite space query refusal') }
	if (mode == 'no-output-space' && path == parent) || (mode == 'no-temp-space' && path != parent) { return 0 }
	return ~u64(0)
}

fn builder_flush(fd int) int {
	mode := os.getenv('VINIX_SQLITE_BUILDER_MODE'); defer { unsafe { mode.free() } }
	if mode == 'flush' { return -1 }
	if mode == 'cleanup' {
		stage := os.getenv('VINIX_SQLITE_BUILDER_STAGE'); saved := os.getenv('VINIX_SQLITE_BUILDER_SAVED')
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
	for name in os.ls(fixture)! { if name.starts_with('.vinix-sqlite-profile-') { os.rmdir_all(fixture + '/' + name)! } }
}

fn builder_prepare(mode string, fixture string) ! {
	roots := fixture + '/roots'; path := roots + '/x86_64/licenses/musl-COPYRIGHT'
	match mode {
		'closure-needed' { os.write_file_array(roots + '/x86_64/bin/sqlite3', elffixture.missing_library('x86_64'))! }
		'missing-architecture' { os.rename(roots + '/x86_64', fixture + '/saved-root')! }
		'wrong-target' { os.write_file_array(roots + '/x86_64/bin/sqlite3', elffixture.image('aarch64', 'pie'))! }
		'wrong-mode' { os.chmod(roots + '/x86_64/bin/sqlite3', 0o644)! }
		'missing-notice' { os.rm(path)! } 'empty-notice' { os.write_file(path, '')! }
		'notice-directory' { os.rm(path)!; os.mkdir(path)! } else {}
	}
}

fn builder_restore(fixture string) ! {
	roots := fixture + '/roots'
	if os.is_dir(fixture + '/saved-root') { os.rename(fixture + '/saved-root', roots + '/x86_64')! }
	path := roots + '/x86_64/licenses/musl-COPYRIGHT'
	if os.is_dir(path) { os.rmdir_all(path)! }
	os.write_file(path, 'musl-COPYRIGHT')!
	os.write_file_array(roots + '/x86_64/bin/sqlite3', elffixture.image('x86_64', 'pie'))!; os.chmod(roots + '/x86_64/bin/sqlite3', 0o755)!
}

fn builder_attempt(mode string, roots string, target string) {
	input := if mode == 'missing-root' { roots + '/missing' } else { roots.clone() }; defer { unsafe { input.free() } }
	if result := sqlite_catalog_with(if mode == 'version' { '3.053.4' } else { '3.53.4' }, if mode == 'runtime-version' { '1.01.0' } else if mode == 'runtime-range' { '2.0.0' } else { '1.0.0' }, input, target,
		CatalogOptions{ checkpoint: builder_checkpoint, available_space: builder_space, flush: builder_flush }) {
		mut info := result; $if !sqlite_builder_baseline ? { info.close(); info.close() }; assert mode in ['complete', 'nested']!
	} else {
		message := err.msg(); defer { unsafe { message.free(); err.free() } }; assert mode !in ['complete', 'nested']!
		expected := match mode {
			'closure-needed' { 'ELF closure missing library missing.so' }
			'version', 'runtime-version' { 'invalid version' } 'runtime-range' { 'supported 1.x' } 'missing-root' { 'prepared root' } 'missing-architecture' { 'ordinary architecture roots' }
			'wrong-target' { 'wrong ELF target/type' } 'wrong-mode' { 'ordinary executable' }
			'missing-notice' { 'cannot open prepared guest path' } 'empty-notice', 'notice-directory' { 'nonempty redistribution notice' }
			'no-output-space', 'no-temp-space' { 'insufficient disk space' } 'space-error' { 'injected SQLite space query' }
			'created', 'ready', 'packed-1', 'packed-2', 'packed-3', 'packed-4' { 'injected SQLite builder checkpoint' }
			'import-elf' { 'segment outside the file' } 'import-notice' { 'invalid redistribution/build notice' }
			'import-directory' { 'unexpected payload inventory' } 'changed-lock' { 'catalog lock changed' }
			'occupied' { 'destination must be new' } 'raced-target' { 'without replacing' } 'flush' { 'directory flush failed' }
			'cleanup', 'root-replaced', 'inventory-replaced', 'lock-replaced' { 'cleanup refused' } else { panic(mode) }
		}
		assert message.contains(expected), message
		if mode in ['flush', 'cleanup']! { assert message.contains('published at ') }
	}
}

fn test_complete_sqlite_builder_retires_success_partial_import_and_publication_refusal_storage() {
	defer { for key in ['MODE', 'ROOTS', 'TARGET', 'PARENT', 'STAGE', 'SAVED']! { os.unsetenv('VINIX_SQLITE_BUILDER_' + key) } }
	for mode in ['complete', 'nested', 'closure-needed', 'version', 'runtime-version', 'runtime-range', 'missing-root', 'missing-architecture', 'wrong-target', 'wrong-mode',
		'missing-notice', 'empty-notice', 'notice-directory', 'no-output-space', 'no-temp-space', 'space-error', 'created',
		'packed-1', 'packed-2', 'packed-3', 'packed-4', 'ready', 'import-elf', 'import-notice',
		'import-directory', 'changed-lock', 'occupied', 'raced-target', 'flush', 'cleanup', 'root-replaced', 'inventory-replaced', 'lock-replaced']! {
		if !builder_selected(mode) { continue }
		fixture := builder_fixture()!; defer { os.rmdir_all(fixture) or {} }
		roots := fixture + '/roots'; target := fixture + if mode == 'nested' { '/new/parent/lock' } else { '/lock' }
		// Initialize JSON metadata outside the complete-call measurement.
		mut warm := sqlite_catalog('3.53.4', '1.0.0', roots, target)!; $if !sqlite_builder_baseline ? { warm.close(); warm.close() }; builder_remove(target)!
		os.setenv('VINIX_SQLITE_BUILDER_MODE', mode, true); os.setenv('VINIX_SQLITE_BUILDER_ROOTS', roots, true)
		os.setenv('VINIX_SQLITE_BUILDER_TARGET', target, true); os.setenv('VINIX_SQLITE_BUILDER_PARENT', os.dir(target), true)
		os.setenv('VINIX_SQLITE_BUILDER_SAVED', fixture + '/saved', true); builder_prepare(mode, fixture)!
		mut original := SqliteBuilderLimit{}; assert C.getrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0
		limit := SqliteBuilderLimit{ current: 32, maximum: original.maximum }; assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &limit }) == 0
		before := builder_descriptors(); mut maximum := u64(0); mut records := u32(0)
		for _ in 0 .. 8 {
			builder_reset(fixture, target)!
			if mode == 'nested' { builder_remove(fixture + '/new')! }
			if mode == 'occupied' { os.write_file(target, 'preserved replacement')! }
			if mode.starts_with('import-') { builder_restore(fixture)! }
			$if track_heap ? { C.vinix_heap_begin() }
			builder_attempt(mode, roots, target)
			$if track_heap ? {
				kept := C.vinix_heap_end(); count := C.vinix_heap_count()
				if kept > maximum { maximum = kept }; if count > records { records = count }
			}
			assert builder_descriptors() == before
			published := mode in ['complete', 'nested', 'flush', 'cleanup']!
			assert os.is_file(target + '/catalog.json') == published
			if published { assert index_digest(os.read_file(target + '/catalog.json')!) == '262cec39b9eec78382a43173df580c83accfd807d4710ca67fcef4601ffafc3a' }
			if mode == 'occupied' { assert os.read_file(target)! == 'preserved replacement' }
			if mode == 'raced-target' { assert os.read_file(target + '/keep')! == 'preserved replacement' }
			if mode in ['cleanup', 'root-replaced', 'inventory-replaced', 'lock-replaced']! {
				stage := os.getenv('VINIX_SQLITE_BUILDER_STAGE'); saved := fixture + '/saved'; assert os.is_dir(saved)
				path := if mode == 'root-replaced' { stage.clone() } else { stage + '/' + if mode == 'lock-replaced' { 'lock' } else { 'inventory' } }
				assert os.read_file(path + '/keep')! == 'preserved replacement'
			} else { assert os.ls(fixture)!.all(!it.starts_with('.vinix-sqlite-profile-')) }
		}
		assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0
		$if track_heap ? {
			println('SQLITE BUILDER case=' + mode + ' retained=' + maximum.str() + ' allocations=' + records.str())
			$if !sqlite_builder_baseline ? { assert maximum == 0 && records == 0 }
		}
		builder_reset(fixture, target)!; builder_restore(fixture)!; os.unsetenv('VINIX_SQLITE_BUILDER_MODE')
		mut retried := sqlite_catalog('3.53.4', '1.0.0', roots, target)!; $if !sqlite_builder_baseline ? { retried.close(); retried.close() }
		assert index_digest(os.read_file(target + '/catalog.json')!) == '262cec39b9eec78382a43173df580c83accfd807d4710ca67fcef4601ffafc3a'
		assert os.read_file(roots + '/aarch64/licenses/musl-COPYRIGHT')! == 'musl-COPYRIGHT'
		assert os.read_bytes(roots + '/aarch64/bin/vinix-linux-runner')! == elffixture.image('aarch64', 'static')
		println('SQLITE BUILDER ' + mode + ' canonical retry, saved output, source and descriptor preservation PASS')
	}
}
