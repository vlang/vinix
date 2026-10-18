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
struct NativeBuilderLimit { current u64 maximum u64 }

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
	path := os.real_path(os.temp_dir()) + '/vinix-native-builder-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	for architecture in ['aarch64', 'x86_64']! {
		root := path + '/roots/' + architecture
		os.mkdir_all(root + '/bin')!; os.mkdir(root + '/licenses')!
		bytes := elffixture.image(architecture, 'static')
		for name in ['package-hello', 'counter', 'memo']! { os.write_file_array(root + '/bin/' + name, bytes)!; os.chmod(root + '/bin/' + name, 0o755)! }
		for name in ['application-sdk-MIT.txt', 'v-MIT.txt', 'musl-MIT.txt']! { os.write_file(root + '/licenses/' + name, name)! }
	}
	return path
}

// Native writes keep fixture file-helper storage out of production measurements.
fn builder_write(path string, text string) ! {
	fd := C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_TRUNC | C.O_CLOEXEC | C.O_NOFOLLOW, 0o644)
	if fd < 0 { return error('cannot create native builder fault fixture') }
	defer { C.close(fd) }
	assert C.write(fd, text.str, usize(text.len)) == text.len
}

fn builder_replace(path string, saved string) ! {
	assert C.rename(path.str, saved.str) == 0; assert C.mkdir(path.str, 0o700) == 0
	keep := path + '/keep'; defer { unsafe { keep.free() } }; builder_write(keep, 'preserved replacement')!
}

fn builder_checkpoint(phase string, stage string) ! {
	mode := os.getenv('VINIX_NATIVE_BUILDER_MODE'); defer { unsafe { mode.free() } }
	if phase == 'created' { assert C.setenv(c'VINIX_NATIVE_BUILDER_STAGE', stage.str, 1) == 0 }
	if mode == phase { return error('injected native builder checkpoint refusal') }
	if mode.starts_with('packed-') && phase == 'packed' {
		index := int(mode[7] - `1`)
		ids := ['org.vinix.package-hello-aarch64', 'org.vinix.counter-aarch64', 'org.vinix.memo-aarch64',
			'org.vinix.package-hello-x86_64', 'org.vinix.counter-x86_64', 'org.vinix.memo-x86_64']!
		path := stage + '/inventory/manifests/' + ids[index] + '-1.0.0.json'; defer { unsafe { path.free() } }
		if publisher_entry_exists(path) { return error('injected native builder checkpoint refusal') }
	}
	if phase == 'created' && mode in ['root-replaced', 'inventory-replaced', 'lock-replaced']! {
		saved := os.getenv('VINIX_NATIVE_BUILDER_SAVED'); defer { unsafe { saved.free() } }
		child := if mode == 'inventory-replaced' { 'inventory' } else { 'lock' }
		path := if mode == 'root-replaced' { stage.clone() } else { stage + '/' + child }
		defer { unsafe { path.free() } }; builder_replace(path, saved)!
	}
	if phase == 'created' && mode.starts_with('import-') {
		roots := os.getenv('VINIX_NATIVE_BUILDER_ROOTS'); defer { unsafe { roots.free() } }
		child := if mode == 'import-elf' { 'bin/memo' } else { 'licenses/musl-MIT.txt' }
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
		path := os.getenv('VINIX_NATIVE_BUILDER_TARGET'); defer { unsafe { path.free() } }; assert C.mkdir(path.str, 0o700) == 0
		keep := path + '/keep'; defer { unsafe { keep.free() } }; builder_write(keep, 'preserved replacement')!
	}
}

fn builder_space(path string) !u64 {
	mode := os.getenv('VINIX_NATIVE_BUILDER_MODE'); parent := os.getenv('VINIX_NATIVE_BUILDER_PARENT')
	defer { unsafe { mode.free(); parent.free() } }
	if mode == 'space-error' { return error('injected native space query refusal') }
	if (mode == 'no-output-space' && path == parent) || (mode == 'no-temp-space' && path != parent) { return 0 }
	return ~u64(0)
}

fn builder_flush(fd int) int {
	mode := os.getenv('VINIX_NATIVE_BUILDER_MODE'); defer { unsafe { mode.free() } }
	if mode == 'flush' { return -1 }
	if mode == 'cleanup' {
		stage := os.getenv('VINIX_NATIVE_BUILDER_STAGE'); saved := os.getenv('VINIX_NATIVE_BUILDER_SAVED')
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
	for name in os.ls(fixture)! { if name.starts_with('.vinix-native-profile-') { os.rmdir_all(fixture + '/' + name)! } }
}

fn builder_prepare(mode string, fixture string) ! {
	roots := fixture + '/roots'; path := roots + '/x86_64/licenses/musl-MIT.txt'
	match mode {
		'missing-architecture' { os.rename(roots + '/x86_64', fixture + '/saved-root')! }
		'wrong-target' { os.write_file_array(roots + '/x86_64/bin/memo', elffixture.image('aarch64', 'static'))! }
		'wrong-mode' { os.chmod(roots + '/x86_64/bin/memo', 0o644)! }
		'missing-notice' { os.rm(path)! } 'empty-notice' { os.write_file(path, '')! }
		'notice-directory' { os.rm(path)!; os.mkdir(path)! } else {}
	}
}

fn builder_restore(fixture string) ! {
	roots := fixture + '/roots'
	if os.is_dir(fixture + '/saved-root') { os.rename(fixture + '/saved-root', roots + '/x86_64')! }
	path := roots + '/x86_64/licenses/musl-MIT.txt'
	if os.is_dir(path) { os.rmdir_all(path)! }
	os.write_file(path, 'musl-MIT.txt')!
	os.write_file_array(roots + '/x86_64/bin/memo', elffixture.image('x86_64', 'static'))!; os.chmod(roots + '/x86_64/bin/memo', 0o755)!
}

fn builder_attempt(mode string, roots string, target string) {
	input := if mode == 'missing-root' { roots + '/missing' } else { roots.clone() }; defer { unsafe { input.free() } }
	if result := native_catalog_with(if mode == 'version' { '1.01.0' } else { '1.0.0' }, input, target,
		CatalogOptions{ checkpoint: builder_checkpoint, available_space: builder_space, flush: builder_flush }) {
		mut info := result; info.close(); info.close(); assert mode in ['complete', 'nested']!
	} else {
		message := err.msg(); defer { unsafe { message.free(); err.free() } }; assert mode !in ['complete', 'nested']!
		expected := match mode {
			'version' { 'invalid version' } 'missing-root' { 'prepared root' } 'missing-architecture' { 'ordinary architecture roots' }
			'wrong-target' { 'wrong ELF target/type' } 'wrong-mode' { 'ordinary executable' }
			'missing-notice' { 'cannot open prepared guest path' } 'empty-notice', 'notice-directory' { 'nonempty redistribution notice' }
			'no-output-space', 'no-temp-space' { 'insufficient disk space' } 'space-error' { 'injected native space query' }
			'created', 'ready', 'packed-1', 'packed-2', 'packed-3', 'packed-4', 'packed-5', 'packed-6' { 'injected native builder checkpoint' }
			'import-elf' { 'segment outside the file' } 'import-notice' { 'invalid redistribution/build notice' }
			'import-directory' { 'unexpected payload inventory' } 'changed-lock' { 'catalog lock changed' }
			'occupied' { 'destination must be new' } 'raced-target' { 'without replacing' } 'flush' { 'directory flush failed' }
			'cleanup', 'root-replaced', 'inventory-replaced', 'lock-replaced' { 'cleanup refused' } else { panic(mode) }
		}
		assert message.contains(expected), message
		if mode in ['flush', 'cleanup']! { assert message.contains('published at ') }
	}
}

fn test_complete_native_builder_retires_success_partial_import_and_publication_refusal_storage() {
	defer { for key in ['MODE', 'ROOTS', 'TARGET', 'PARENT', 'STAGE', 'SAVED']! { os.unsetenv('VINIX_NATIVE_BUILDER_' + key) } }
	for mode in ['complete', 'nested', 'version', 'missing-root', 'missing-architecture', 'wrong-target', 'wrong-mode',
		'missing-notice', 'empty-notice', 'notice-directory', 'no-output-space', 'no-temp-space', 'space-error', 'created',
		'packed-1', 'packed-2', 'packed-3', 'packed-4', 'packed-5', 'packed-6', 'ready', 'import-elf', 'import-notice',
		'import-directory', 'changed-lock', 'occupied', 'raced-target', 'flush', 'cleanup', 'root-replaced', 'inventory-replaced', 'lock-replaced']! {
		if !builder_selected(mode) { continue }
		fixture := builder_fixture()!; defer { os.rmdir_all(fixture) or {} }
		roots := fixture + '/roots'; target := fixture + if mode == 'nested' { '/new/parent/lock' } else { '/lock' }
		// Initialize JSON metadata outside the complete-call measurement.
		mut warm := native_catalog('1.0.0', roots, target)!; warm.close(); warm.close(); builder_remove(target)!
		os.setenv('VINIX_NATIVE_BUILDER_MODE', mode, true); os.setenv('VINIX_NATIVE_BUILDER_ROOTS', roots, true)
		os.setenv('VINIX_NATIVE_BUILDER_TARGET', target, true); os.setenv('VINIX_NATIVE_BUILDER_PARENT', os.dir(target), true)
		os.setenv('VINIX_NATIVE_BUILDER_SAVED', fixture + '/saved', true); builder_prepare(mode, fixture)!
		mut original := NativeBuilderLimit{}; assert C.getrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0
		limit := NativeBuilderLimit{ current: 32, maximum: original.maximum }; assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &limit }) == 0
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
			if published { assert index_digest(os.read_file(target + '/catalog.json')!) == '249d6bfb150918c4586f86d68da6b6394800d150f7385c3654fadb7ab19a3fce' }
			if mode == 'occupied' { assert os.read_file(target)! == 'preserved replacement' }
			if mode == 'raced-target' { assert os.read_file(target + '/keep')! == 'preserved replacement' }
			if mode in ['cleanup', 'root-replaced', 'inventory-replaced', 'lock-replaced']! {
				stage := os.getenv('VINIX_NATIVE_BUILDER_STAGE'); saved := fixture + '/saved'; assert os.is_dir(saved)
				path := if mode == 'root-replaced' { stage.clone() } else { stage + '/' + if mode == 'lock-replaced' { 'lock' } else { 'inventory' } }
				assert os.read_file(path + '/keep')! == 'preserved replacement'
			} else { assert os.ls(fixture)!.all(!it.starts_with('.vinix-native-profile-')) }
		}
		assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0
		$if track_heap ? {
			println('NATIVE BUILDER case=' + mode + ' retained=' + maximum.str() + ' allocations=' + records.str())
			$if !native_builder_baseline ? { assert maximum == 0 && records == 0 }
		}
		builder_reset(fixture, target)!; builder_restore(fixture)!; os.unsetenv('VINIX_NATIVE_BUILDER_MODE')
		mut retried := native_catalog('1.0.0', roots, target)!; retried.close(); retried.close()
		assert index_digest(os.read_file(target + '/catalog.json')!) == '249d6bfb150918c4586f86d68da6b6394800d150f7385c3654fadb7ab19a3fce'
		assert os.read_file(roots + '/aarch64/licenses/musl-MIT.txt')! == 'musl-MIT.txt'
		assert os.read_bytes(roots + '/aarch64/bin/counter')! == elffixture.image('aarch64', 'static')
		println('NATIVE BUILDER ' + mode + ' canonical retry, saved output, source and descriptor preservation PASS')
	}
}
