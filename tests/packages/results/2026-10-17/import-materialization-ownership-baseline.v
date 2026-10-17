// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time

fn C.mkfifo(&char, u32) int

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
	fn C.vinix_heap_count() u32
}

fn materialization_selected(name string) bool {
	if os.args.len == 1 { return true }
	assert os.args.len == 3 && os.args[1] == 'case'
	return os.args[2] == name
}

fn materialization_fixture() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-materialize-owned-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(work + '/root/tree/a/b/empty')!
	os.mkdir(work + '/root/other')!
	for index in 0 .. 16 { os.write_file(work + '/root/tree/a/b/data-' + index.str(), 'payload-' + index.str())! }
	os.write_file(work + '/root/file', 'o'.repeat(131073))!
	os.chmod(work + '/root/file', 0o4755)!
	os.write_file(work + '/root/empty', '')!
	os.symlink('/tree', work + '/root/alias')!
	os.symlink('/tree/a/../a', work + '/root/other/alias')!
	os.mkdir(work + '/root/cycle')!; os.symlink('/cycle', work + '/root/cycle/loop')!
	assert C.mkfifo((work + '/root/pipe').str, 0o600) == 0
	return work
}

fn materialization_refuse_opened(phase string, _ string) ! { if phase == 'opened' { return error('injected materialization failure') } }
fn materialization_refuse_directory(phase string, _ string) ! { if phase == 'directory' { return error('injected materialization failure') } }
fn materialization_refuse_sized(phase string, _ string) ! { if phase == 'sized' { return error('injected materialization failure') } }
fn materialization_refuse_block(phase string, _ string) ! { if phase == 'block' { return error('injected materialization failure') } }
fn materialization_refuse_read(phase string, _ string) ! { if phase == 'read' { return error('injected materialization failure') } }
fn materialization_refuse_hashed(phase string, _ string) ! { if phase == 'hashed' { return error('injected materialization failure') } }
fn materialization_refuse_copy(phase string, _ string) ! { if phase == 'copy-block' { return error('injected materialization failure') } }
fn materialization_refuse_copied(phase string, path string) ! { if phase == 'copied' && path.ends_with('data-9') { return error('injected materialization failure') } }

fn materialization_checkpoint(mode string) fn (string, string) ! {
	return match mode {
		'opened' { materialization_refuse_opened } 'directory' { materialization_refuse_directory }
		'sized' { materialization_refuse_sized } 'block' { materialization_refuse_block }
		'read' { materialization_refuse_read } 'hashed' { materialization_refuse_hashed }
		'copy-block' { materialization_refuse_copy } 'copied' { materialization_refuse_copied }
		else { mirror_no_checkpoint }
	}
}

fn materialization_attempt(root int, output string, mode string, pins map[string]Payload) ! {
	mut importer := RootImport{ root: root, output: output, pins: pins, options: PackSourceOptions{ checkpoint: materialization_checkpoint(mode) } }
	defer { unsafe { (&array(&importer.ancestors)).free() } }
	source := match mode { 'empty' { 'empty' } 'tree', 'copied', 'directory' { 'tree' } 'alias' { 'alias' }
		'parent-alias' { 'other/alias' } 'cycle' { 'cycle' } 'special' { 'pipe' } else { 'file' } }
	target := if mode == 'nested' { 'one/two/three/data' } else { 'payload' }
	if _ := importer.copy(source, target) {
		assert mode in ['file', 'empty', 'nested', 'tree', 'alias', 'parent-alias', 'pinned']!
	} else {
		message := err.msg()
		expected := match mode { 'cycle' { 'directory symlink cycle' } 'special' { 'special file' }
			'pin-size', 'pin-mode', 'pin-digest' { 'inventory differs' } else { 'injected materialization failure' } }
		assert message.contains(expected), message
		unsafe { message.free(); err.free() }
	}
	assert importer.ancestors.len == 0
}

fn test_prepared_materialization_retires_scratch_on_complete_recursive_and_late_refusal_paths() {
	work := materialization_fixture()!
	defer { os.rmdir_all(work) or {} }
	root_path := work + '/root'; output := work + '/output'
	root := capture_prepared_root(root_path, 'test')!; defer { C.close(root) }
	digest := hash_file(root_path + '/file')!
	defer { unsafe { digest.free() } }
	for mode in ['file', 'empty', 'nested', 'tree', 'alias', 'parent-alias', 'pinned', 'pin-size', 'pin-mode', 'pin-digest', 'cycle', 'special', 'opened', 'directory', 'sized', 'block', 'read', 'hashed', 'copy-block', 'copied']! {
		if !materialization_selected(mode) { continue }
		mut pins := map[string]Payload{}
		defer { unsafe { pins.free() } }
		if mode.starts_with('pin') {
			pins['payload'] = Payload{ path: 'payload', bytes: if mode == 'pin-size' { 1 } else { 131073 },
				sha256: if mode == 'pin-digest' { 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' } else { digest }, executable: mode != 'pin-mode' }
		}
		mut maximum := u64(0); mut records := u32(0)
		cycles := $if track_heap ? { 16 } $else { 2 }
		for _ in 0 .. cycles {
			if os.exists(output) { os.rmdir_all(output)! }; os.mkdir(output)!
			$if track_heap ? { C.vinix_heap_begin() }
			materialization_attempt(root, output, mode, pins)!
			$if track_heap ? {
				kept := C.vinix_heap_end(); allocations := C.vinix_heap_count()
				if kept > maximum { maximum = kept }; if allocations > records { records = allocations }
			}
		}
		$if track_heap ? {
			println('IMPORT MATERIALIZATION case=' + mode + ' retained=' + maximum.str() + ' allocations=' + records.str())
			$if !materialization_baseline ? { assert maximum == 0 && records == 0 }
		}
	}
	assert os.read_file(root_path + '/tree/a/b/data-9')! == 'payload-9'
	assert os.lstat(root_path + '/file')!.mode & 0o7777 == 0o4755
	println('IMPORT MATERIALIZATION files, recursive guest aliases, pinned inventories and late refusals retire owned scratch PASS')
}
