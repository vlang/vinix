// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time

fn C.mkfifo(&char, u32) int
fn C.link(&char, &char) int
#include <sys/resource.h>
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int
struct CapturedWorkspaceLimit { current u64 maximum u64 }

fn captured_workspace_descriptors() int {
	mut count := 0
	for fd in 0 .. 256 { if C.fcntl(fd, C.F_GETFD, 0) >= 0 { count++ } }
	return count
}

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
	fn C.vinix_heap_count() u32
}

fn captured_workspace_selected(name string) bool {
	if os.args.len == 1 { return true }
	assert os.args.len == 3 && os.args[1] == 'case'
	return os.args[2] == name
}

fn captured_workspace_fixture() !string {
	return os.real_path(os.temp_dir()) + '/vinix-workspace-capture-' + os.getpid().str() + '-' + time.now().unix_micro().str()
}

fn test_import_workspace_retirement_preserves_replaced_entries_and_retires_all_check_storage() {
	mut original_limit := CapturedWorkspaceLimit{}
	assert C.getrlimit(C.RLIMIT_NOFILE, unsafe { &original_limit }) == 0
	limit := CapturedWorkspaceLimit{ current: 32, maximum: original_limit.maximum }
	assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &limit }) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &original_limit }) == 0 }
	for mode in ['ordinary', 'root-directory', 'root-alias', 'root-mode', 'payload-directory', 'payload-alias', 'manifest-directory', 'manifest-file', 'manifest-alias', 'manifest-fifo', 'manifest-content', 'unexpected-directory', 'renamed-parent']! {
		if !captured_workspace_selected(mode) { continue }
		fixture := captured_workspace_fixture()!; defer { os.rmdir_all(fixture) or {} }
		parent := fixture + '/parent'; outside := fixture + '/outside'
		os.mkdir_all(parent)!; os.mkdir(outside)!; os.write_file(outside + '/keep', 'outside')!
		before := captured_workspace_descriptors()
		mut work := create_import_workspace_at(parent)!
		path := work.stage.path.clone(); saved := fixture + '/saved'; payload := path + '/payload'; manifest := path + '/manifest.json'
		original := '{"a":"1"}\n'; changed := '{"a":"2"}\n'
		work.write_manifest(original)!
		// Grow both retirement collections, and never follow leaf aliases,
		// open FIFOs or chmod external hard-link targets during cleanup.
		for index in 0 .. 32 {
			child := payload + '/d-' + index.str(); os.mkdir(child)!; os.write_file(child + '/data', 'owned')!
		}
		mut deep := payload.clone()
		for _ in 0 .. 40 { deep += '/n'; os.mkdir(deep)! }
		os.write_file(deep + '/keep', 'deep')!
		os.symlink(outside, payload + '/alias')!
		assert C.link((outside + '/keep').str, (payload + '/hardlink').str) == 0
		assert C.mkfifo((payload + '/fifo').str, 0o600) == 0
		match mode {
			'root-directory', 'root-alias' {
				assert C.rename(path.str, saved.str) == 0
				if mode == 'root-directory' { os.mkdir(path)!; os.write_file(path + '/keep', 'replacement')! }
				else { os.symlink(outside, path)! }
			}
			'root-mode' { os.chmod(path, 0o777)! }
			'payload-directory', 'payload-alias' {
				assert C.rename(payload.str, saved.str) == 0
				if mode == 'payload-directory' { os.mkdir(payload)!; os.write_file(payload + '/keep', 'replacement')! }
				else { os.symlink(outside, payload)! }
			}
			'manifest-directory', 'manifest-file', 'manifest-alias', 'manifest-fifo' {
				assert C.rename(manifest.str, saved.str) == 0
				match mode {
					'manifest-directory' { os.mkdir(manifest)!; os.write_file(manifest + '/keep', 'replacement')! }
					'manifest-file' { os.write_file(manifest, original)! }
					'manifest-alias' { os.symlink(outside + '/keep', manifest)! }
					else { assert C.mkfifo(manifest.str, 0o600) == 0 }
				}
			}
			'manifest-content' { os.write_file(manifest, changed)! }
			'unexpected-directory' { os.mkdir(path + '/unexpected')!; os.write_file(path + '/unexpected/keep', 'replacement')! }
			'renamed-parent' { assert C.rename(parent.str, saved.str) == 0; os.mkdir(parent)!; os.write_file(parent + '/keep', 'replacement')! }
			else {}
		}
		$if track_heap ? { C.vinix_heap_begin() }
		if mode == 'ordinary' {
			work.check()!; work.retire()!
		} else {
			mut refused := false
			work.check() or { refused = true; message := err.msg(); assert message != ''; unsafe { message.free(); err.free() } }
			assert refused
			failure := work.failure(error('injected import refusal'))
			message := failure.msg()
			assert message.contains('injected import refusal')
			if mode != 'renamed-parent' { assert message.contains('cleanup refused') && message.contains(path) }
			unsafe { message.free(); failure.free() }
		}
		work.close(); work.close()
		$if track_heap ? {
			kept := C.vinix_heap_end(); count := C.vinix_heap_count()
			println('IMPORT WORKSPACE CAPTURE case=' + mode + ' retained=' + kept.str() + ' allocations=' + count.str())
			assert kept == 0 && count == 0
		}
		assert captured_workspace_descriptors() == before
		assert os.read_file(outside + '/keep')! == 'outside'
		if mode == 'ordinary' { assert !os.exists(path) && os.ls(parent)!.len == 0 }
		else if mode == 'renamed-parent' { assert os.ls(saved)!.len == 0 && os.read_file(parent + '/keep')! == 'replacement' }
		else {
			assert os.exists(path) || os.is_link(path)
			if mode.starts_with('root-') && mode != 'root-mode' { assert os.read_file(saved + '/payload/d-9/data')! == 'owned' }
			else if mode.starts_with('payload-') { assert os.read_file(saved + '/d-9/data')! == 'owned' }
			else { assert os.read_file(payload + '/d-9/data')! == 'owned' }
			if mode == 'manifest-content' { assert os.read_file(manifest)! == changed }
		}
		println('IMPORT WORKSPACE CAPTURE ' + mode + ' preservation and captured-parent retirement PASS')
	}
}

fn captured_workspace_change(phase string, path string) ! {
	wanted := os.getenv('VINIX_WORKSPACE_PHASE'); defer { unsafe { wanted.free() } }
	if phase != wanted { return }
	os.setenv('VINIX_WORKSPACE_ACTUAL', path, true)
	site := os.getenv('VINIX_WORKSPACE_SITE'); saved := os.getenv('VINIX_WORKSPACE_SAVED')
	defer { unsafe { site.free(); saved.free() } }
	if site == 'extra' { os.mkdir(path + '/extra')!; os.write_file(path + '/extra/keep', 'replacement')!; return }
	if site == 'content' {
		manifest := path + '/manifest.json'; text := os.read_file(manifest)!
		assert text.contains('Fixture'); os.write_file(manifest, text.replace('Fixture', 'Changed'))!
		return
	}
	target := if site == 'root' { path.clone() } else { path + '/' + if site == 'payload' { 'payload' } else { 'manifest.json' } }
	assert C.rename(target.str, saved.str) == 0
	os.mkdir(target)!; os.write_file(target + '/keep', 'replacement')!
}

fn test_public_import_workspace_refuses_namespace_and_manifest_changes_before_and_after_packing() {
	if !captured_workspace_selected('public') { return }
	defer { for name in ['PHASE', 'SITE', 'SAVED', 'ACTUAL']! { os.unsetenv('VINIX_WORKSPACE_' + name) } }
	mut cases := 0
	for phase in ['workspace-created', 'workspace-copied', 'workspace-manifest', 'workspace-packed']! {
		for site in ['root', 'payload', 'manifest', 'content', 'extra']! {
			if site in ['manifest', 'content']! && phase in ['workspace-created', 'workspace-copied']! { continue }
			fixture := captured_workspace_fixture()!; defer { os.rmdir_all(fixture) or {} }
			root := fixture + '/root'; repository := fixture + '/repository'; saved := fixture + '/saved'
			os.mkdir_all(root)!; os.write_file(root + '/data', 'source')!
			recipe := RootRecipe{ manifest: Package{ id: 'fixture', name: 'Fixture', version: '1.0.0', architecture: 'all', kind: 'data', license: 'MIT' },
				entries: [RootEntry{ source: 'data', path: 'data' }] }
			fd := capture_prepared_root(root, 'test')!; defer { C.close(fd) }
			os.setenv('VINIX_WORKSPACE_PHASE', phase, true); os.setenv('VINIX_WORKSPACE_SITE', site, true); os.setenv('VINIX_WORKSPACE_SAVED', saved, true)
			mut refused := false
			pack_root_descriptor_with(recipe, fd, repository, false, PackSourceOptions{ checkpoint: captured_workspace_change }) or {
				message := err.msg(); assert message.contains('private import cleanup refused'), message
				if phase == 'workspace-packed' { assert message.contains('package packed at ') }
				refused = true; unsafe { message.free(); err.free() }
			}
			assert refused && os.read_file(root + '/data')! == 'source'
			manifest := repository + '/manifests/fixture-all-1.0.0.json'
			assert os.exists(manifest) == (phase == 'workspace-packed')
			actual := os.getenv('VINIX_WORKSPACE_ACTUAL')
			assert actual.starts_with(os.real_path(os.temp_dir()) + '/vinix-pack-root-' + os.getpid().str() + '-')
			if site == 'root' { assert os.read_file(actual + '/keep')! == 'replacement' && os.is_dir(saved + '/payload') }
			if site == 'payload' { assert os.read_file(actual + '/payload/keep')! == 'replacement' && os.is_dir(saved) }
			if site == 'manifest' { assert os.read_file(actual + '/manifest.json/keep')! == 'replacement' && os.read_file(saved)!.contains('Fixture') }
			if site == 'content' { assert os.read_file(actual + '/manifest.json')!.contains('Changed') }
			if site == 'extra' { assert os.read_file(actual + '/extra/keep')! == 'replacement' }
			// Only remove this fixture's explicitly retained random workspace.
			os.rmdir_all(actual)!
			os.unsetenv('VINIX_WORKSPACE_PHASE')
			mut retried := pack_root_descriptor(recipe, fd, repository, false)!
			assert retried.name == 'Fixture' && retried.files.len == 1 && retried.files[0].sha256 == index_digest('source')
			retried.close(); retried.close(); cases++
		}
	}
	assert cases == 16
	println('IMPORT WORKSPACE CAPTURE 16 public root/payload/manifest/content/unexpected-entry refusals preserve source, publication timing and canonical retry PASS')
}

fn test_import_workspace_creation_refusal_closes_captures_and_names_retained_recovery_data() {
	if !captured_workspace_selected('creation-refusal') { return }
	fixture := captured_workspace_fixture()!; defer { os.rmdir_all(fixture) or {} }
	parent := fixture + '/parent'; os.mkdir_all(parent)!
	mut warm := create_import_workspace_at(parent)!; warm.retire()!; warm.close()
	mut original := CapturedWorkspaceLimit{}
	assert C.getrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0
	limit := CapturedWorkspaceLimit{ current: 32, maximum: original.maximum }
	assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &limit }) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0 }
	mut descriptors := [32]int{}
	mut held := 0
	for held < descriptors.len {
		fd := C.dup(1)
		if fd < 0 { assert C.errno == C.EMFILE; break }
		descriptors[held] = fd; held++
	}
	assert held >= 2
	C.close(descriptors[held - 1]); C.close(descriptors[held - 2]); held -= 2
	defer { for index in 0 .. held { C.close(descriptors[index]) } }
	before := captured_workspace_descriptors()
	expected := 'cannot initialize private import workspace at ' + parent + '/vinix-pack-root-'
	$if track_heap ? { C.vinix_heap_begin() }
	mut refused := false
	if created := create_import_workspace_at(parent) {
		mut unexpected := created; unexpected.close()
	} else {
		message := err.msg()
		assert message.contains(expected) && message.contains('retain recovery data')
		refused = true; unsafe { message.free(); err.free() }
	}
	assert refused
	$if track_heap ? {
		kept := C.vinix_heap_end(); count := C.vinix_heap_count()
		println('IMPORT WORKSPACE CAPTURE case=creation-refusal retained=' + kept.str() + ' allocations=' + count.str())
		assert kept == 0 && count == 0
	}
	assert captured_workspace_descriptors() == before
	for index in 0 .. held { C.close(descriptors[index]) }; held = 0
	entries := os.ls(parent)!
	assert entries.len == 1 && os.is_dir(parent + '/' + entries[0] + '/payload')
	println('IMPORT WORKSPACE CAPTURE creation refusal closes both captured descriptors, retires scratch and identifies retained unadmitted data PASS')
}
