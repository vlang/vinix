// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time

#include <sys/resource.h>
fn C.mkfifo(&char, u32) int
fn C.link(&char, &char) int
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int
struct RetirementLimit { current u64 maximum u64 }
$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32

fn retirement_fixture() !string {
	work := os.temp_dir() + '/vinix-collection-retirement-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	for generation in [1, 2] {
		path := work + '/store/generations/' + generation.str()
		os.mkdir_all(path)!
		os.write_file(path + '/lease', '')!
		os.write_file(path + '/state.json', json2.encode(State{ generation: u64(generation),
			previous: if generation == 2 { u64(1) } else { u64(0) }, architecture: 'aarch64' }))!
	}
	os.symlink('generations/2', work + '/store/current')!
	os.mkdir(work + '/store/objects')!
	os.write_file(work + '/store/objects/' + 'a'.repeat(64), 'cached')!
	os.mkdir(work + '/outside')!; os.chmod(work + '/outside', 0o700)!
	os.write_file(work + '/outside/keep', 'preserved')!; os.chmod(work + '/outside/keep', 0o600)!
	return work
}

fn retirement_obsolete(work string, number int) !string {
	path := work + '/store/generations/' + number.str()
	os.mkdir(path)!; os.write_file(path + '/lease', '')!; os.chmod(path + '/lease', 0o444)!
	os.write_file(path + '/keep', 'obsolete')!
	return path
}

fn retirement_preserved(work string) ! {
	assert os.readlink(work + '/store/current')! == 'generations/2'
	assert read_state(work + '/store', 'aarch64')!.generation == 2
	assert os.exists(work + '/store/generations/1/state.json')
	assert os.read_file(work + '/outside/keep')! == 'preserved'
	assert os.lstat(work + '/outside/keep')!.mode & 0o777 == 0o600
	assert os.lstat(work + '/outside')!.mode & 0o777 == 0o700
}

fn test_collection_refuses_writable_obsolete_roots_before_any_retirement() {
	work := retirement_fixture()!; defer { os.rmdir_all(work) or {} }
	good := retirement_obsolete(work, 3)!
	bad := retirement_obsolete(work, 4)!
	os.chmod(bad, 0o777)!
	stage := work + '/store/generations/.stage-interrupted'
	os.mkdir(stage)!; os.write_file(stage + '/keep', 'interrupted')!
	mut refused := false
	collect(Config{ architecture: 'aarch64' }, work + '/store') or { refused = true }
	preserved := os.exists(good + '/keep') && os.exists(bad + '/keep') && os.exists(stage + '/keep')
		&& os.exists(work + '/store/objects/' + 'a'.repeat(64))
	println('COLLECTION RETIREMENT writable-root refused=${refused} preserved=${preserved}')
	assert refused && preserved
	retirement_preserved(work)!
	os.chmod(bad, 0o755)!
	collect(Config{ architecture: 'aarch64' }, work + '/store')!
	assert os.ls(work + '/store/generations')!.sorted() == ['1', '2']
	assert os.ls(work + '/store/objects')!.len == 0
	retirement_preserved(work)!
	println('COLLECTION RETIREMENT unsafe root preserves all generations, interrupted stages and cache; restored root retries PASS')
}

fn retirement_mixed(work string, number int, depth int) !string {
	path := retirement_obsolete(work, number)!
	deep := path + '/' + 'nested/'.repeat(depth)
	os.mkdir_all(deep)!; os.write_file(deep + 'payload', 'partial')!
	os.symlink(work + '/outside', deep + 'alias-dir')!
	os.symlink(work + '/outside/keep', deep + 'alias-file')!
	os.symlink(work + '/store/generations/2', deep + 'active-alias')!
	assert C.mkfifo((deep + 'fifo').str, 0o600) == 0
	assert C.link((work + '/outside/keep').str, (deep + 'hard-link').str) == 0
	return path
}

fn retirement_replace(work string, path string, kind string) ! {
	match kind {
		'directory' { os.mkdir(path)!; os.write_file(path + '/replacement', 'preserved')! }
		'alias' { os.symlink(work + '/outside', path)! }
		'fifo' { assert C.mkfifo(path.str, 0o600) == 0 }
		'file' { os.write_file(path, 'replacement')! }
		'missing' {}
		else { panic(kind) }
	}
}

fn retirement_remove_replacement(path string) ! {
	if os.is_link(path) { os.rm(path)! }
	else if os.is_dir(path) { os.rmdir_all(path)! }
	else if os.exists(path) { os.rm(path)! }
}

fn test_collection_binds_removal_to_the_captured_generation_parent() {
	work := retirement_fixture()!; defer { os.rmdir_all(work) or {} }
	path := retirement_obsolete(work, 3)!
	guard := acquire(work + '/store')!; defer { guard.release() }
	targets := collection_targets(work + '/store', State{ generation: 2, previous: 1 })!
	defer { close_collection_targets(targets) }
	parent := work + '/store/generations'
	os.rename(parent, work + '/saved')!; os.mkdir(parent)!
	// The generation and lease inodes are unchanged, but their parent is new.
	os.rename(work + '/saved/3', path)!
	mut refused := false
	remove_collection_target(targets[0]) or { refused = err.msg().contains('parent changed') }
	assert refused && os.read_file(path + '/keep')! == 'obsolete'
	assert os.exists(path + '/lease') && os.exists(work + '/saved/2/state.json')
	os.rename(path, work + '/saved/3')!; os.rmdir(parent)!; os.rename(work + '/saved', parent)!
	remove_collection_target(targets[0])!
	assert !os.exists(path)
	retirement_preserved(work)!
	println('COLLECTION RETIREMENT changed parent refuses even with unchanged generation and lease inodes; restored parent retries PASS')
}

fn test_collection_rechecks_inventory_directories_and_retains_lease_on_failure() {
	work := retirement_fixture()!; defer { os.rmdir_all(work) or {} }
	guard := acquire(work + '/store')!; defer { guard.release() }
	parent := recovery_parent(work + '/store')!; defer { C.close(parent) }
	for subject in ['nested', 'nested/nested'] {
		for kind in ['directory', 'alias', 'fifo', 'file', 'missing'] {
			path := retirement_mixed(work, 3, 2)!
			lease := open_collection_entry(parent, '3')!; defer { close_collection_lease(lease) }
			assert C.flock(lease.lease, C.LOCK_EX | C.LOCK_NB) == 0
			root := StageTarget{ name: '3', device: lease.directory_device, inode: lease.directory_inode }
			nodes := inventory_stage_tree(lease.directory, root)!; defer { close_stage_inventory(nodes) }
			assert nodes.len == 3
			changed := path + '/' + subject
			os.rename(changed, work + '/saved')!; retirement_replace(work, changed, kind)!
			mut refused := false
			remove_collection_tree(parent, root, lease, nodes) or { refused = true }
			assert refused && os.exists(path + '/lease') && os.read_file(path + '/keep')! == 'obsolete'
			assert os.read_file(work + '/saved/' + if subject == 'nested' { 'nested/payload' } else { 'payload' })! == 'partial'
			if kind == 'directory' { assert os.read_file(changed + '/replacement')! == 'preserved' }
			retirement_preserved(work)!
			retirement_remove_replacement(changed)!; os.rename(work + '/saved', changed)!
			remove_collection_tree(parent, root, lease, nodes)!
			assert !os.exists(path)
		}
	}
	println('COLLECTION RETIREMENT ten changed nested/ancestor directories preserve data and the named lease; restored inventories retry PASS')
}

fn test_collection_rechecks_root_and_lease_after_inventory_before_deletion() {
	work := retirement_fixture()!; defer { os.rmdir_all(work) or {} }
	guard := acquire(work + '/store')!; defer { guard.release() }
	parent := recovery_parent(work + '/store')!; defer { C.close(parent) }
	for subject in ['root', 'lease'] {
		for kind in ['directory', 'alias', 'fifo', 'file', 'missing'] {
			path := retirement_mixed(work, 3, 2)!
			lease := open_collection_entry(parent, '3')!; defer { close_collection_lease(lease) }
			assert C.flock(lease.lease, C.LOCK_EX | C.LOCK_NB) == 0
			root := StageTarget{ name: '3', device: lease.directory_device, inode: lease.directory_inode }
			nodes := inventory_stage_tree(lease.directory, root)!; defer { close_stage_inventory(nodes) }
			changed := if subject == 'root' { path } else { path + '/lease' }
			os.rename(changed, work + '/saved')!; retirement_replace(work, changed, kind)!
			mut refused := false
			remove_collection_tree(parent, root, lease, nodes) or { refused = true }
			assert refused
			data := if subject == 'root' { work + '/saved' } else { path }
			assert os.read_file(data + '/keep')! == 'obsolete' && os.read_file(data + '/nested/nested/payload')! == 'partial'
			if kind == 'directory' { assert os.read_file(changed + '/replacement')! == 'preserved' }
			retirement_preserved(work)!
			retirement_remove_replacement(changed)!; os.rename(work + '/saved', changed)!
			remove_collection_tree(parent, root, lease, nodes)!
			assert !os.exists(path)
		}
	}
	println('COLLECTION RETIREMENT ten post-inventory root/lease replacements refuse before deletion; restored identities retry PASS')
}

fn test_collection_retires_deep_wide_and_repeated_trees_with_bounded_descriptors() {
	work := retirement_fixture()!; defer { os.rmdir_all(work) or {} }
	path := retirement_mixed(work, 3, 1)!
	lease := C.open((path + '/lease').str, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW)
	assert lease >= 0 && C.flock(lease, C.LOCK_SH | C.LOCK_NB) == 0
	defer { C.close(lease) }
	for number in 4 .. 132 { retirement_mixed(work, number, 1)! }
	retirement_mixed(work, 132, 64)!
	wide := retirement_mixed(work, 133, 1)!
	for i in 0 .. 1024 { os.write_file(wide + '/nested/' + i.str() + '-' + 'x'.repeat(64), 'partial')! }
	mut original := RetirementLimit{}
	assert C.getrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0
	limited := RetirementLimit{ current: 32, maximum: original.maximum }
	assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &limited }) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0 }
	collect(Config{ architecture: 'aarch64' }, work + '/store')!
	assert os.ls(work + '/store/generations')!.sorted() == ['1', '2', '3']
	assert os.read_file(path + '/keep')! == 'obsolete'
	assert C.flock(lease, C.LOCK_UN) == 0
	collect(Config{ architecture: 'aarch64' }, work + '/store')!
	for _ in 0 .. 128 {
		retirement_mixed(work, 3, 3)!
		collect(Config{ architecture: 'aarch64' }, work + '/store')!
		bad := retirement_obsolete(work, 3)!; os.chmod(bad, 0o777)!
		mut refused := false
		collect(Config{ architecture: 'aarch64' }, work + '/store') or {
			refused = true; message := err.msg(); unsafe { message.free(); err.free() }
		}
		assert refused && os.exists(bad + '/lease') && os.exists(bad + '/keep')
		os.chmod(bad, 0o755)!; collect(Config{ architecture: 'aarch64' }, work + '/store')!
	}
	retirement_preserved(work)!
	println('COLLECTION RETIREMENT 128-generation batch, 64-level tree, 1024 long-name files and 128 success/refusal loops pass below 32 descriptors; live lease protected PASS')
}

fn test_collection_retirement_releases_owned_scratch() {
	$if track_heap ? {
		work := retirement_fixture()!; defer { os.rmdir_all(work) or {} }
		guard := acquire(work + '/store')!; defer { guard.release() }
		for damaged in [false, true] {
			for _ in 0 .. 128 {
				path := retirement_mixed(work, 3, 3)!
				targets := collection_targets(work + '/store', State{ generation: 2, previous: 1 })!
				if damaged { os.chmod(path, 0o777)! }
				C.vinix_heap_begin()
				mut refused := false
				remove_collection_target(targets[0]) or {
					refused = true; message := err.msg(); unsafe { message.free(); err.free() }
				}
				bytes := C.vinix_heap_end(); count := C.vinix_heap_count()
				assert refused == damaged && bytes == 0 && count == 0
				if damaged { os.chmod(path, 0o755)!; remove_collection_target(targets[0])! }
				close_collection_targets(targets)
			}
		}
		println('COLLECTION RETIREMENT 128 successful removals and 128 refusals retain zero removal-helper allocations PASS')
	}
}
