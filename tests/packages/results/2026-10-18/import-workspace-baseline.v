// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time

#include <sys/resource.h>
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int
struct WorkspaceLimit { current u64 maximum u64 }

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
	fn C.vinix_heap_count() u32
}

fn workspace_selected(name string) bool {
	if os.args.len == 1 { return true }
	assert os.args.len == 3 && os.args[1] == 'case'
	return os.args[2] == name
}

fn workspace_descriptors() int {
	mut count := 0
	for fd in 0 .. 256 { if C.fcntl(fd, C.F_GETFD, 0) >= 0 { count++ } }
	return count
}

fn workspace_refuse_opened(phase string, _ string) ! { if phase == 'opened' { return error('injected import workspace refusal') } }
fn workspace_refuse_directory(phase string, _ string) ! { if phase == 'directory' { return error('injected import workspace refusal') } }
fn workspace_refuse_copied(phase string, path string) ! { if phase == 'copied' && path.ends_with('data-9') { return error('injected import workspace refusal') } }

fn workspace_import(recipe string, root string, repository string, captured int, pinned RootRecipe, mode string, options PackSourceOptions) !Package {
	if mode == 'pinned' { return pack_root_descriptor_with(pinned, captured, repository, true, options) }
	return pack_root_with(recipe, root, repository, options)
}

fn workspace_attempt(recipe string, root string, repository string, captured int, pinned RootRecipe, mode string) {
	options := PackSourceOptions{ checkpoint: match mode {
		'opened' { workspace_refuse_opened } 'directory' { workspace_refuse_directory }
		'copied' { workspace_refuse_copied } else { mirror_no_checkpoint }
	} }
	result := workspace_import(recipe, root, repository, captured, pinned, mode, options) or {
		message := err.msg()
		expected := match mode { 'publisher-file' { 'publisher output ancestor' } 'object-directory', 'manifest-directory' { 'cannot atomically replace' }
			else { 'injected import workspace refusal' } }
		assert mode !in ['complete', 'pinned']! && message.contains(expected), message
		unsafe { message.free(); err.free() }
		return
	}
	mut p := result
	p.close(); p.close()
	assert mode in ['complete', 'pinned']!
}

fn test_complete_prepared_import_workspace_retires_storage_on_success_and_refusal() {
	work := os.real_path(os.temp_dir()) + '/vinix-import-workspace-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	defer { os.rmdir_all(work) or {} }
	root := work + '/root'; recipe_path := work + '/recipe.json'; repository := work + '/repository'
	os.mkdir_all(root + '/tree/a/empty')!
	for index in 0 .. 16 { os.write_file(root + '/tree/a/data-' + index.str(), 'payload-' + index.str())! }
	declaration := Package{ id: 'fixture', name: 'Fixture', version: '1.0.0', architecture: 'all', kind: 'data', license: 'MIT', permissions: ['files'] }
	entries := [RootEntry{ source: 'tree', path: 'data' }]
	recipe := RootRecipe{ manifest: declaration, entries: entries }
	text := publisher_json(recipe)
	os.write_file(recipe_path, text)!
	// Initialize JSON field metadata before measuring per-call ownership.
	mut expected := pack_root(recipe_path, root, repository)!
	defer { expected.close() }
	pinned := RootRecipe{ manifest: expected, entries: entries }
	canonical := publisher_json(expected)
	captured := capture_prepared_root(root, 'test')!; defer { C.close(captured) }
	before := workspace_descriptors()
	mut original := WorkspaceLimit{}
	assert C.getrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0
	limit := WorkspaceLimit{ current: 32, maximum: original.maximum }
	assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &limit }) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0 }
	for mode in ['complete', 'pinned', 'opened', 'directory', 'copied', 'publisher-file', 'object-directory', 'manifest-directory']! {
		if !workspace_selected(mode) { continue }
		mut maximum := u64(0); mut records := u32(0)
		cycles := $if track_heap ? { 16 } $else { 2 }
		for _ in 0 .. cycles {
			if os.is_dir(repository) { os.rmdir_all(repository)! }
			else if os.exists(repository) { os.rm(repository)! }
			if mode == 'publisher-file' { os.write_file(repository, 'preserved')! }
			if mode == 'object-directory' { os.mkdir_all(repository + '/objects/' + expected.files[0].sha256)! }
			if mode == 'manifest-directory' { os.mkdir_all(repository + '/manifests/fixture-all-1.0.0.json')! }
			$if track_heap ? { C.vinix_heap_begin() }
			workspace_attempt(recipe_path, root, repository, captured, pinned, mode)
			$if track_heap ? {
				kept := C.vinix_heap_end(); allocations := C.vinix_heap_count()
				if kept > maximum { maximum = kept }; if allocations > records { records = allocations }
			}
			assert workspace_descriptors() == before
		}
		$if track_heap ? {
			println('IMPORT WORKSPACE case=' + mode + ' retained=' + maximum.str() + ' allocations=' + records.str())
			$if !import_workspace_baseline ? { assert maximum == 0 && records == 0 }
		}
		if mode == 'publisher-file' { assert os.read_file(repository)! == 'preserved'; os.rm(repository)! }
		else if os.exists(repository) { os.rmdir_all(repository)! }
		mut retried := pack_root(recipe_path, root, repository)!
		assert publisher_json(retried) == canonical
		retried.close(); retried.close()
		assert os.read_file(root + '/tree/a/data-9')! == 'payload-9'
	}
	println('IMPORT WORKSPACE complete cold/pinned imports and early/late/publisher refusals retire storage and descriptors; exact canonical retry PASS')
}
