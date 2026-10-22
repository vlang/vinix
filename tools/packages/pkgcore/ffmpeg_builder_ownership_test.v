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
struct FfmpegBuilderLimit { current u64 maximum u64 }

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

fn builder_archive() !string {
	path := os.getenv('VINIX_PROFILE_EXPORT_SOURCE')
	if !os.is_file(path) || os.file_size(path) != ffmpeg_source_bytes || hash_file(path)! != ffmpeg_source_digest {
		return error('provide VINIX_PROFILE_EXPORT_SOURCE with the reviewed FFmpeg 8.0.1 source archive')
	}
	return path
}

fn builder_fixture() !string {
	archive := builder_archive()!
	path := os.real_path(os.temp_dir()) + '/vinix-ffmpeg-owner-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	for architecture in ['aarch64', 'x86_64']! {
		root := path + '/roots/' + architecture
		for name in ['bin', 'lib', 'licenses', 'sources']! { os.mkdir_all(root + '/' + name)! }
		for name in ['bin/ffmpeg', 'bin/ffprobe', 'bin/vinix-linux-runner', 'lib/libc.so', ...ffmpeg_libraries] {
			os.write_file_array(root + '/' + name, elffixture.image(architecture, ffmpeg_elf_kind(name)))!; os.chmod(root + '/' + name, 0o755)!
		}
		for name in ffmpeg_notices { os.write_file(root + '/' + name, name)! }
		os.cp(archive, root + '/sources/ffmpeg.tar.xz')!
	}
	return path
}

// Native writes keep fixture file-helper storage out of production measurements.
fn builder_write(path string, text string) ! {
	fd := C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_TRUNC | C.O_CLOEXEC | C.O_NOFOLLOW, 0o644)
	if fd < 0 { return error('cannot create FFmpeg builder fault fixture') }
	defer { C.close(fd) }
	assert C.write(fd, text.str, usize(text.len)) == text.len
}

fn builder_replace(path string, saved string) ! {
	assert C.rename(path.str, saved.str) == 0; assert C.mkdir(path.str, 0o700) == 0
	keep := path + '/keep'; defer { unsafe { keep.free() } }; builder_write(keep, 'preserved replacement')!
}

fn builder_corrupt_source(path string) ! {
	fd := C.open(path.str, C.O_WRONLY | C.O_CLOEXEC | C.O_NOFOLLOW); assert fd >= 0; defer { C.close(fd) }
	byte := [u8(0)]!
	assert C.pwrite(fd, &byte[0], 1, 0) == 1
}

fn builder_checkpoint(phase string, stage string) ! {
	mode := os.getenv('VINIX_FFMPEG_OWNER_MODE'); defer { unsafe { mode.free() } }
	if phase == 'created' { assert C.setenv(c'VINIX_FFMPEG_OWNER_STAGE', stage.str, 1) == 0 }
	if mode == phase { return error('injected FFmpeg builder checkpoint refusal') }
	if mode.starts_with('packed-') && phase == 'packed' {
		index := int(mode[7] - `1`)
		ids := ['org.ffmpeg.cli-aarch64', 'org.ffmpeg.probe-aarch64', 'org.vinix.ffmpeg-runtime-aarch64', 'org.ffmpeg.cli-x86_64', 'org.ffmpeg.probe-x86_64', 'org.vinix.ffmpeg-runtime-x86_64']!
		version := if index % 3 == 2 { '1.0.0' } else { '8.0.1' }
		path := stage + '/inventory/manifests/' + ids[index] + '-' + version + '.json'; defer { unsafe { path.free() } }
		if publisher_entry_exists(path) { return error('injected FFmpeg builder checkpoint refusal') }
	}
	if phase == 'created' && mode in ['root-replaced', 'inventory-replaced', 'lock-replaced']! {
		saved := os.getenv('VINIX_FFMPEG_OWNER_SAVED'); defer { unsafe { saved.free() } }
		child := if mode == 'inventory-replaced' { 'inventory' } else { 'lock' }
		path := if mode == 'root-replaced' { stage.clone() } else { stage + '/' + child }
		defer { unsafe { path.free() } }; builder_replace(path, saved)!
	}
	if phase == 'created' && mode.starts_with('import-') {
		roots := os.getenv('VINIX_FFMPEG_OWNER_ROOTS'); defer { unsafe { roots.free() } }
		child := if mode == 'import-elf' { 'bin/ffmpeg' } else if mode == 'import-source' { 'sources/ffmpeg.tar.xz' } else { 'licenses/ffmpeg-COPYING.LGPLv2.1' }
		path := roots + '/x86_64/' + child
		defer { unsafe { path.free() } }
		if mode == 'import-elf' {
			fd := C.open(path.str, C.O_WRONLY | C.O_CLOEXEC | C.O_NOFOLLOW); assert fd >= 0; defer { C.close(fd) }
			bytes := [u8(1), 2, 0, 0, 0, 0, 0, 0]!
			assert C.pwrite(fd, &bytes[0], 8, 96) == 8
		} else if mode == 'import-source' { builder_corrupt_source(path)! }
		else if mode == 'import-notice' { builder_write(path, '')! }
		else { assert C.unlinkat(C.AT_FDCWD, path.str, 0) == 0; assert C.mkdir(path.str, 0o700) == 0 }
	}
	if phase == 'ready' && mode == 'changed-lock' {
		path := stage + '/lock/catalog.json'; defer { unsafe { path.free() } }; builder_write(path, '{}')!
	}
	if phase == 'ready' && mode == 'raced-target' {
		path := os.getenv('VINIX_FFMPEG_OWNER_TARGET'); defer { unsafe { path.free() } }; assert C.mkdir(path.str, 0o700) == 0
		keep := path + '/keep'; defer { unsafe { keep.free() } }; builder_write(keep, 'preserved replacement')!
	}
}

fn builder_space(path string) !u64 {
	mode := os.getenv('VINIX_FFMPEG_OWNER_MODE'); parent := os.getenv('VINIX_FFMPEG_OWNER_PARENT')
	defer { unsafe { mode.free(); parent.free() } }
	if mode == 'space-error' { return error('injected FFmpeg space query refusal') }
	if (mode == 'no-output-space' && path == parent) || (mode == 'no-temp-space' && path != parent) { return 0 }
	return ~u64(0)
}

fn builder_flush(fd int) int {
	mode := os.getenv('VINIX_FFMPEG_OWNER_MODE'); defer { unsafe { mode.free() } }
	if mode == 'flush' { return -1 }
	if mode == 'cleanup' {
		stage := os.getenv('VINIX_FFMPEG_OWNER_STAGE'); saved := os.getenv('VINIX_FFMPEG_OWNER_SAVED')
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
	for name in os.ls(fixture)! { if name.starts_with('.vinix-ffmpeg-profile-') { os.rmdir_all(fixture + '/' + name)! } }
}

fn builder_prepare(mode string, fixture string) ! {
	roots := fixture + '/roots'; path := roots + '/x86_64/licenses/ffmpeg-COPYING.LGPLv2.1'
	source := roots + '/x86_64/sources/ffmpeg.tar.xz'
	match mode {
		'closure-needed' { os.write_file_array(roots + '/x86_64/bin/ffmpeg', elffixture.missing_library('x86_64'))! }
		'missing-source' { os.rm(source)! } 'source-size' { os.write_file(source, 'wrong size')! }
		'source-executable' { os.chmod(source, 0o755)! } 'source-pin' { builder_corrupt_source(source)! }
		'missing-architecture' { os.rename(roots + '/x86_64', fixture + '/saved-root')! }
		'wrong-target' { os.write_file_array(roots + '/x86_64/bin/ffmpeg', elffixture.image('aarch64', 'pie'))! }
		'wrong-mode' { os.chmod(roots + '/x86_64/bin/ffmpeg', 0o644)! }
		'missing-notice' { os.rm(path)! } 'empty-notice' { os.write_file(path, '')! }
		'notice-directory' { os.rm(path)!; os.mkdir(path)! } else {}
	}
}

fn builder_restore(fixture string) ! {
	roots := fixture + '/roots'
	if os.is_dir(fixture + '/saved-root') { os.rename(fixture + '/saved-root', roots + '/x86_64')! }
	path := roots + '/x86_64/licenses/ffmpeg-COPYING.LGPLv2.1'
	if os.is_dir(path) { os.rmdir_all(path)! }
	os.write_file(path, 'licenses/ffmpeg-COPYING.LGPLv2.1')!
	os.write_file_array(roots + '/x86_64/bin/ffmpeg', elffixture.image('x86_64', 'pie'))!; os.chmod(roots + '/x86_64/bin/ffmpeg', 0o755)!
	source := roots + '/x86_64/sources/ffmpeg.tar.xz'
	if os.exists(source) { os.rm(source)! }
	os.cp(builder_archive()!, source)!
}

fn builder_attempt(mode string, roots string, target string) {
	input := if mode == 'missing-root' { roots + '/missing' } else { roots.clone() }; defer { unsafe { input.free() } }
	if result := ffmpeg_catalog_with(if mode == 'version' { '1.01.0' } else if mode == 'runtime-range' { '2.0.0' } else { '1.0.0' }, input, target,
		CatalogOptions{ checkpoint: builder_checkpoint, available_space: builder_space, flush: builder_flush }) {
		mut info := result; $if !ffmpeg_owner_baseline ? { info.close(); info.close() }; assert mode in ['complete', 'nested']!
	} else {
		message := err.msg(); defer { unsafe { message.free(); err.free() } }; assert mode !in ['complete', 'nested']!
		expected := match mode {
			'closure-needed' { 'ELF closure missing library missing.so' }
			'version' { 'invalid version' } 'runtime-range' { 'supported 1.x' } 'missing-root' { 'prepared root' } 'missing-architecture' { 'ordinary architecture roots' }
			'wrong-target' { 'wrong ELF target/type' } 'wrong-mode' { 'ordinary executable' }
			'missing-notice' { 'cannot open prepared guest path' } 'empty-notice', 'notice-directory' { 'nonempty redistribution/build notice' }
			'no-output-space', 'no-temp-space' { 'insufficient disk space' } 'space-error' { 'injected FFmpeg space query' }
			'created', 'ready', 'packed-1', 'packed-2', 'packed-3', 'packed-4', 'packed-5', 'packed-6' { 'injected FFmpeg builder checkpoint' }
			'import-elf' { 'segment outside the file' } 'import-notice' { 'invalid redistribution/build notice' }
			'import-directory' { 'unexpected payload inventory' } 'changed-lock' { 'catalog lock changed' }
			'missing-source' { 'cannot open prepared guest path' }
			'source-size', 'source-executable' { 'ordinary, nonexecutable pinned' }
			'source-pin', 'import-source' { 'source archive differs from the reviewed' }
			'occupied' { 'destination must be new' } 'raced-target' { 'without replacing' } 'flush' { 'directory flush failed' }
			'cleanup', 'root-replaced', 'inventory-replaced', 'lock-replaced' { 'cleanup refused' } else { panic(mode) }
		}
		assert message.contains(expected), message
		if mode in ['flush', 'cleanup']! { assert message.contains('published at ') }
	}
}

fn test_complete_ffmpeg_builder_retires_success_partial_import_and_publication_refusal_storage() {
	defer { for key in ['MODE', 'ROOTS', 'TARGET', 'PARENT', 'STAGE', 'SAVED']! { os.unsetenv('VINIX_FFMPEG_OWNER_' + key) } }
	for mode in ['complete', 'nested', 'closure-needed', 'version', 'runtime-range', 'missing-root', 'missing-architecture', 'wrong-target', 'wrong-mode',
		'missing-notice', 'empty-notice', 'notice-directory', 'missing-source', 'source-size', 'source-executable', 'source-pin', 'import-source',
		'no-output-space', 'no-temp-space', 'space-error', 'created',
		'packed-1', 'packed-2', 'packed-3', 'packed-4', 'packed-5', 'packed-6', 'ready', 'import-elf', 'import-notice',
		'import-directory', 'changed-lock', 'occupied', 'raced-target', 'flush', 'cleanup', 'root-replaced', 'inventory-replaced', 'lock-replaced']! {
		if !builder_selected(mode) { continue }
		fixture := builder_fixture()!; defer { os.rmdir_all(fixture) or {} }
		roots := fixture + '/roots'; target := fixture + if mode == 'nested' { '/new/parent/lock' } else { '/lock' }
		// Initialize JSON metadata outside the complete-call measurement.
		mut warm := ffmpeg_catalog('1.0.0', roots, target)!; $if !ffmpeg_owner_baseline ? { warm.close(); warm.close() }; builder_remove(target)!
		os.setenv('VINIX_FFMPEG_OWNER_MODE', mode, true); os.setenv('VINIX_FFMPEG_OWNER_ROOTS', roots, true)
		os.setenv('VINIX_FFMPEG_OWNER_TARGET', target, true); os.setenv('VINIX_FFMPEG_OWNER_PARENT', os.dir(target), true)
		os.setenv('VINIX_FFMPEG_OWNER_SAVED', fixture + '/saved', true); builder_prepare(mode, fixture)!
		mut original := FfmpegBuilderLimit{}; assert C.getrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0
		limit := FfmpegBuilderLimit{ current: 32, maximum: original.maximum }; assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &limit }) == 0
		before := builder_descriptors(); mut maximum := u64(0); mut records := u32(0)
		for _ in 0 .. 2 {
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
			if published { assert index_digest(os.read_file(target + '/catalog.json')!) == '52e1ce43f7e52205655ea33fde374a623df23063dcd1a6275a785be61416b2f8' }
			if mode == 'occupied' { assert os.read_file(target)! == 'preserved replacement' }
			if mode == 'raced-target' { assert os.read_file(target + '/keep')! == 'preserved replacement' }
			if mode in ['cleanup', 'root-replaced', 'inventory-replaced', 'lock-replaced']! {
				stage := os.getenv('VINIX_FFMPEG_OWNER_STAGE'); saved := fixture + '/saved'; assert os.is_dir(saved)
				path := if mode == 'root-replaced' { stage.clone() } else { stage + '/' + if mode == 'lock-replaced' { 'lock' } else { 'inventory' } }
				assert os.read_file(path + '/keep')! == 'preserved replacement'
			} else { assert os.ls(fixture)!.all(!it.starts_with('.vinix-ffmpeg-profile-')) }
		}
		assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0
		$if track_heap ? {
			println('FFMPEG OWNER case=' + mode + ' retained=' + maximum.str() + ' allocations=' + records.str())
			$if !ffmpeg_owner_baseline ? { assert maximum == 0 && records == 0 }
		}
		builder_reset(fixture, target)!; builder_restore(fixture)!; os.unsetenv('VINIX_FFMPEG_OWNER_MODE')
		mut retried := ffmpeg_catalog('1.0.0', roots, target)!; $if !ffmpeg_owner_baseline ? { retried.close(); retried.close() }
		assert index_digest(os.read_file(target + '/catalog.json')!) == '52e1ce43f7e52205655ea33fde374a623df23063dcd1a6275a785be61416b2f8'
		assert os.read_file(roots + '/aarch64/licenses/ffmpeg-COPYING.LGPLv2.1')! == 'licenses/ffmpeg-COPYING.LGPLv2.1'
		assert os.read_bytes(roots + '/aarch64/bin/vinix-linux-runner')! == elffixture.image('aarch64', 'static')
		println('FFMPEG OWNER ' + mode + ' canonical retry, saved output, source and descriptor preservation PASS')
	}
}
