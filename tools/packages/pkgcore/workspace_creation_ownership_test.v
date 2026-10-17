// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time

fn C.umask(u32) u32

fn creation_selected(name string) bool {
	if os.args.len == 1 { return true }
	assert os.args.len == 3 && os.args[1] == 'case'
	return os.args[2] == name
}

fn creation_group(prefix string) bool {
	if os.args.len == 1 { return true }
	assert os.args.len == 3 && os.args[1] == 'case'
	return os.args[2].starts_with(prefix)
}

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
	fn C.vinix_heap_count() u32
}

fn creation_error(cause IError, expected string) {
	message := cause.msg(); assert message.contains(expected), message
	unsafe { message.free(); cause.free() }
}

fn creation_locked(phase string, _ string) ! { if phase == 'locked' { return error('injected creation refusal') } }
fn creation_hashed(phase string, path string) ! { if phase == 'hashed' && path == 'd/data-9' { return error('injected creation refusal') } }
fn creation_copied(phase string, path string) ! { if phase == 'copied' && path == 'd/data-9' { return error('injected creation refusal') } }

fn creation_fixture(count int) !(string, string, string) {
	work := os.real_path(os.temp_dir()) + '/vinix-create-owned-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	root := work + '/source'; manifest := work + '/manifest.json'; os.mkdir_all(root + '/d')!
	for index in 0 .. count {
		digits := index.str(); path := root + '/d/data-' + digits; data := 'payload-' + digits
		defer { unsafe { digits.free(); path.free(); data.free() } }
		os.write_file(path, data)!
	}
	p := Package{ id: 'fixture', name: 'Fixture', version: '1.0.0', architecture: 'all', kind: 'data', license: 'MIT' }
	text := publisher_json(p); defer { close_decoded_package(p); unsafe { text.free() } }
	// Initialize immutable process-wide JSON field metadata before measuring
	// filesystem construction. No destination or cached payload exists yet.
	warm := publisher_json(Payload{}); unsafe { warm.free() }
	os.write_file(manifest, text)!
	return work, root, manifest
}

fn creation_once(mode string, path string) ! {
	match mode {
		'export' { target := export_target(path, 'creation fixture')!; unsafe { target.free() } }
		'workspace' { target := publisher_workspace(path, true)!; unsafe { target.free() } }
		'owned' { owned_directory(path, 0o700)! }
		'existing', 'alias' { export_target(path, 'creation fixture') or { creation_error(err, 'destination must be new'); return }; assert false }
		'unsafe' { export_target(path, 'creation fixture') or { creation_error(err, 'parent must be controlled'); return }; assert false }
		'file-parent' { export_target(path, 'creation fixture') or { creation_error(err, 'parent must be a directory'); return }; assert false }
		'create-failure' { make_package_directories(path, 0o755) or { creation_error(err, 'cannot create package directory'); return }; assert false }
		else { panic(mode) }
	}
}

fn test_creation_component_paths_retire_new_parents_and_refusal_scratch() {
	if !creation_group('component-') && !creation_group('refusal-') { return }
	work, _, _ := creation_fixture(1)!
	defer { os.rmdir_all(work) or {} }
	base := work + '/new'
	for deep in [false, true]! {
		path := if deep { base + '/a/b/c/d/e/f/g/h/target' } else { base + '/target' }
		for mode in ['export', 'workspace', 'owned']! {
			if !creation_selected('component-' + mode + '-' + deep.str()) { continue }
			mut maximum := u64(0); mut records := u32(0)
			for _ in 0 .. 128 {
				if os.exists(base) { os.rmdir_all(base)! }; os.mkdir(base)!
				$if track_heap ? { C.vinix_heap_begin() }
				creation_once(mode, path)!
				$if track_heap ? {
					kept := C.vinix_heap_end(); allocations := C.vinix_heap_count()
					if kept > maximum { maximum = kept }; if allocations > records { records = allocations }
				}
				assert os.exists(path) == (mode != 'export')
				if mode == 'owned' { assert os.lstat(path)!.mode & 0o777 == 0o700 }
			}
			$if track_heap ? {
				println('WORKSPACE CREATION mode=' + mode + ' deep=' + deep.str() + ' retained=' + maximum.str() + ' allocations=' + records.str())
				$if !workspace_creation_baseline ? { assert maximum == 0 && records == 0 }
			}
		}
	}
	os.mkdir(work + '/existing')!; os.symlink(work + '/absent', work + '/alias')!
	os.mkdir(work + '/unsafe')!; os.chmod(work + '/unsafe', 0o777)!; os.write_file(work + '/file', 'preserved')!
	for mode in ['existing', 'alias', 'unsafe', 'file-parent', 'create-failure']! {
		if !creation_selected('refusal-' + mode) { continue }
		path := work + '/' + match mode { 'unsafe' { 'unsafe/new' } 'file-parent' { 'file/new' }
			'create-failure' { 'failed/' + 'x'.repeat($if macos { 300 } $else { 8192 }) + '/child' } else { mode } }
		mut maximum := u64(0); mut records := u32(0)
		for _ in 0 .. 128 {
			$if track_heap ? { C.vinix_heap_begin() }
			creation_once(mode, path)!
			$if track_heap ? {
				kept := C.vinix_heap_end(); allocations := C.vinix_heap_count()
				if kept > maximum { maximum = kept }; if allocations > records { records = allocations }
			}
		}
		$if track_heap ? {
			println('WORKSPACE CREATION refusal=' + mode + ' retained=' + maximum.str() + ' allocations=' + records.str())
			$if !workspace_creation_baseline ? { assert maximum == 0 && records == 0 }
		}
	}
	assert os.read_file(work + '/file')! == 'preserved' && os.ls(work + '/unsafe')!.len == 0
	println('WORKSPACE CREATION fresh parent/workspace/private directories and existing/alias/unsafe/file-parent/creation refusals retire owned scratch PASS')
}

fn test_creation_preserves_parent_alias_dotdot_umask_existing_modes_and_partial_parents() {
	if !creation_selected('paths') { return }
	work, _, _ := creation_fixture(1)!
	defer { os.rmdir_all(work) or {} }
	os.mkdir_all(work + '/real/child')!; os.chmod(work + '/real/child', 0o755)!
	os.symlink(work + '/real/child', work + '/alias')!
	cwd := os.getwd(); os.chdir(work)!; defer { os.chdir(cwd) or { panic(err) } }
	previous := C.umask(0o077); defer { C.umask(previous) }
	target := export_target('alias/../nested/a/out///', 'fixture')!
	defer { unsafe { target.free() } }
	assert target == work + '/real/nested/a/out' && !os.exists(work + '/nested')
	assert os.lstat(work + '/real/nested')!.mode & 0o777 == 0o700
	workspace := publisher_workspace('alias/../nested/a/repository', true)!
	defer { unsafe { workspace.free() } }
	assert workspace == work + '/real/nested/a/repository' && os.lstat(workspace)!.mode & 0o777 == 0o700
	owned_directory('direct/a///', 0o755)!
	assert os.lstat('direct/a')!.mode & 0o777 == 0o755 && os.lstat('direct')!.mode & 0o777 == 0o700
	mut refused := false
	owned_directory('alias', 0o700) or { refused = true; creation_error(err, 'ordinary directories') }
	assert refused && os.lstat(work + '/real/child')!.mode & 0o777 == 0o755
	for path in ['', 'nul/child\x00ignored']! {
		make_package_directories(path, 0o755) or { creation_error(err, 'nonempty path without NUL'); continue }; assert false
	}
	assert !os.exists('nul')
	os.write_file('file', 'preserved')!
	refused = false
	make_package_directories('file/child', 0o755) or { refused = true; creation_error(err, 'parent must be a directory') }
	assert refused && os.read_file('file')! == 'preserved'
	// Vinix bounds copied syscall paths at PATH_MAX; its tmpfs does not
	// enforce the host's short component limit. Exceed a native bound on each.
	failed := 'partial/' + 'x'.repeat($if macos { 300 } $else { 8192 }) + '/child'
	refused = false
	make_package_directories(failed, 0o755) or { refused = true; creation_error(err, 'cannot create package directory') }
	assert refused && os.is_dir('partial') && os.ls('partial')!.len == 0
	make_package_directories('partial/corrected/child', 0o755)!
	assert os.is_dir('partial/corrected/child')
	println('WORKSPACE CREATION parent aliases and dotdot, trailing separators, umask, existing modes, invalid paths and retained partial-parent retry PASS')
}

fn test_creation_first_packing_calls_and_late_refusals_retire_all_call_storage() {
	if !creation_group('pack-') { return }
	for count in [1, 32]! {
		if !creation_group('pack-' + count.str() + '-') { continue }
		work, source, manifest := creation_fixture(count)!
		defer { os.rmdir_all(work) or {} }
		base := work + '/new'
		for deep in [false, true]! {
			repository := if deep { base + '/a/b/c/d/e/f/g/h/repository' } else { base + '/repository' }
			for mode in ['complete', 'locked', 'hashed', 'copied']! {
				if count == 1 && mode in ['hashed', 'copied']! { continue }
				if !creation_selected('pack-' + count.str() + '-' + deep.str() + '-' + mode) { continue }
				options := PackSourceOptions{ checkpoint: if mode == 'locked' { creation_locked } else if mode == 'hashed' { creation_hashed }
					else if mode == 'copied' { creation_copied } else { mirror_no_checkpoint } }
				mut maximum := u64(0); mut records := u32(0)
				for _ in 0 .. 16 {
					if os.exists(base) { os.rmdir_all(base)! }; os.mkdir(base)!
					$if track_heap ? { C.vinix_heap_begin() }
					if result := pack_with(manifest, source, repository, options) { mut p := result; p.close(); p.close(); assert mode == 'complete' }
					else { assert mode != 'complete'; creation_error(err, 'injected creation refusal') }
					$if track_heap ? {
						kept := C.vinix_heap_end(); allocations := C.vinix_heap_count()
						if kept > maximum { maximum = kept }; if allocations > records { records = allocations }
					}
					// A refused cold copy leaves verified objects/partials available.
					// Retry outside the measurement must recover the exact inventory.
					mut retry := pack(manifest, source, repository)!
					assert retry.files.len == count
					saved := repository + '/manifests/fixture-all-1.0.0.json'; text := publisher_json(retry)
					assert read_metadata(saved)! == text
					unsafe { saved.free(); text.free() }; retry.close()
				}
				$if track_heap ? {
					println('WORKSPACE CREATION pack files=' + count.str() + ' deep=' + deep.str() + ' mode=' + mode + ' retained=' + maximum.str() + ' allocations=' + records.str())
					$if !workspace_creation_baseline ? { assert maximum == 0 && records == 0 }
				}
			}
		}
	}
	println('WORKSPACE CREATION first packing, cold copies and locked/hash/copy refusals retire owned scratch; exact retry PASS')
}
