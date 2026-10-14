// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import os
import time

#include <sys/resource.h>
fn C.mkfifo(&char, u32) int
fn C.link(&char, &char) int
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int
struct RecoveryLimit { current u64 maximum u64 }
$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32

struct RecoveryFixture { root string directory string config Config }

fn recovery_fixture() !RecoveryFixture {
	root := os.temp_dir() + '/vinix-stage-recovery-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	directory := root + '/store'
	generation := directory + '/generations/1'
	os.mkdir_all(generation + '/apps/app')!; os.mkdir_all(generation + '/share/applications')!
	os.mkdir(directory + '/objects')!
	payload := 'retained application'
	p := Package{ id: 'app', name: 'Application', description: 'Recovery fixture', version: '1.0.0',
		architecture: 'all', kind: 'data', license: 'MIT', files: [Payload{ path: 'asset',
		bytes: u64(payload.len), sha256: sha256.hexhash(payload) }] }
	state := State{ architecture: 'aarch64', generation: 1, requested: ['app'], packages: [Installed{
		package: p, repository: 'fixture', sequence: 1,
		public_key: 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a' }] }
	os.write_file(generation + '/apps/app/asset', payload)!; os.chmod(generation + '/apps/app/asset', 0o644)!
	os.write_file(generation + '/state.json', encode_generation_state(state)!)!; os.chmod(generation + '/state.json', 0o644)!
	os.write_file(generation + '/lease', '')!; os.chmod(generation + '/lease', 0o444)!
	os.symlink('generations/1', directory + '/current')!
	os.mkdir(root + '/outside')!; os.chmod(root + '/outside', 0o700)!
	os.write_file(root + '/outside/keep', 'preserved')!; os.chmod(root + '/outside/keep', 0o600)!
	return RecoveryFixture{ root: root, directory: directory,
		config: Config{ architecture: 'aarch64', policy: Policy{ reserve_bytes: 0, offline: true } } }
}

fn test_stage_recovery_refuses_root_alias_without_deleting_outside_data() {
	f := recovery_fixture()!; defer { os.rmdir_all(f.root) or {} }
	stage := f.directory + '/generations/.stage-alias'
	os.symlink(f.root + '/outside', stage)!
	mut message := ''
	transact(f.config, f.directory, 'remove', ['app'], TransactionOptions{}) or { message = err.msg() }
	preserved := os.exists(f.root + '/outside/keep')
	println('STAGE RECOVERY root-alias refused=${message != ""} preserved=${preserved}')
	assert message != '' && preserved
	assert os.is_link(stage) && os.readlink(f.directory + '/current')! == 'generations/1'
}

fn recovery_preserved(f RecoveryFixture) ! {
	assert os.readlink(f.directory + '/current')! == 'generations/1'
	assert read_state(f.directory, 'aarch64')!.generation == 1
	assert os.read_file(f.directory + '/generations/1/apps/app/asset')! == 'retained application'
	assert os.read_file(f.root + '/outside/keep')! == 'preserved'
	assert os.lstat(f.root + '/outside/keep')!.mode & 0o777 == 0o600
	assert os.lstat(f.root + '/outside')!.mode & 0o777 == 0o700
}

fn recovery_replacement(f RecoveryFixture, path string, kind string) ! {
	match kind {
		'alias' { os.symlink(f.root + '/outside', path)! }
		'active-alias' { os.symlink(f.directory + '/generations/1', path)! }
		'dangling' { os.symlink(f.root + '/absent', path)! }
		'fifo' { assert C.mkfifo(path.str, 0o600) == 0 }
		'file' { os.write_file(path, 'replacement')! }
		'directory', 'writable' {
			os.mkdir(path)!; os.write_file(path + '/keep', 'replacement')!
			os.chmod(path, if kind == 'writable' { 0o777 } else { 0o700 })!
		}
		'missing' {}
		else { panic(kind) }
	}
}

fn recovery_remove_replacement(path string) ! {
	if os.is_link(path) { os.rm(path)! }
	else if os.is_dir(path) { os.rmdir_all(path)! }
	else if os.exists(path) { os.rm(path)! }
}

fn test_stage_recovery_preflights_all_roots_before_transaction_or_collection_removal() {
	mut cases := 0
	for operation in ['remove', 'gc'] {
		for kind in ['alias', 'active-alias', 'dangling', 'fifo', 'file', 'writable'] {
			f := recovery_fixture()!; defer { os.rmdir_all(f.root) or {} }
			good := f.directory + '/generations/.stage-a-good'
			bad := f.directory + '/generations/.stage-z-bad'
			os.mkdir(good)!; os.write_file(good + '/keep', 'interrupted work')!
			recovery_replacement(f, bad, kind)!
			obsolete := f.directory + '/generations/2'
			os.mkdir(obsolete)!; os.write_file(obsolete + '/lease', '')!; os.write_file(obsolete + '/keep', 'obsolete')!
			object := f.directory + '/objects/' + 'a'.repeat(64)
			os.write_file(object, 'cached object')!; os.write_file(object + '.part', 'download')!
			metadata := os.read_file(f.directory + '/generations/1/state.json')!
			mut message := ''
			if operation == 'gc' { collect(f.config, f.directory) or { message = err.msg() } }
			else { transact(f.config, f.directory, 'remove', ['app'], TransactionOptions{}) or { message = err.msg() } }
			assert message.contains('unsafe unpublished package stage'), operation + '/' + kind + ': ' + message
			recovery_preserved(f)!
			assert os.read_file(good + '/keep')! == 'interrupted work'
			assert os.read_file(obsolete + '/keep')! == 'obsolete'
			assert os.read_file(object)! == 'cached object' && os.read_file(object + '.part')! == 'download'
			assert os.read_file(f.directory + '/generations/1/state.json')! == metadata
			recovery_remove_replacement(bad)!
			if operation == 'gc' { collect(f.config, f.directory)!; assert !os.exists(obsolete) && !os.exists(object) }
			else { assert transact(f.config, f.directory, 'remove', ['app'], TransactionOptions{})!.packages.len == 0 }
			assert !os.exists(good) && os.read_file(f.root + '/outside/keep')! == 'preserved'
			cases++
		}
	}
	assert cases == 12
	println('STAGE RECOVERY 12 malformed-root transaction/collection refusals preserve all stages, generations, cache and outside data; restored roots retry PASS')
}

fn test_stage_recovery_rechecks_captured_identity_before_removing_a_replacement() {
	f := recovery_fixture()!; defer { os.rmdir_all(f.root) or {} }
	parent := recovery_parent(f.directory)!; defer { C.close(parent) }
	stage := f.directory + '/generations/.stage-captured'
	for kind in ['directory', 'alias', 'fifo', 'file', 'missing'] {
		os.mkdir(stage)!; os.write_file(stage + '/keep', 'captured')!
		target := capture_stage(parent, '.stage-captured')!
		defer { unsafe { target.name.free() } }
		os.rename(stage, f.root + '/saved')!
		recovery_replacement(f, stage, kind)!
		mut refused := false
		retire_stage(parent, target) or { refused = err.msg().contains('identity changed') }
		assert refused && os.read_file(f.root + '/saved/keep')! == 'captured'
		if kind == 'directory' { assert os.read_file(stage + '/keep')! == 'replacement' }
		recovery_preserved(f)!
		recovery_remove_replacement(stage)!
		os.rename(f.root + '/saved', stage)!
		retire_stage(parent, target)!
		assert !os.exists(stage)
	}
	println('STAGE RECOVERY five changed captured roots preserve original and replacement identities; restored inode retires PASS')
}

fn test_stage_recovery_rechecks_nested_directories_and_never_follows_replaced_ancestors() {
	f := recovery_fixture()!; defer { os.rmdir_all(f.root) or {} }
	parent := recovery_parent(f.directory)!; defer { C.close(parent) }
	stage := f.directory + '/generations/.stage-nested'
	for subject in ['nested', 'nested/deeper'] {
		for kind in ['directory', 'alias', 'fifo', 'file', 'missing'] {
			os.mkdir_all(stage + '/nested/deeper')!; os.write_file(stage + '/nested/deeper/keep', 'captured')!
			target := capture_stage(parent, '.stage-nested')!
			defer { unsafe { target.name.free() } }
			root := C.open(stage.str, C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
			assert root >= 0
			defer { C.close(root) }
			mut nodes := []StageDirectory{cap: 4}
			unsafe { nodes.flags |= .noslices }
			defer { unsafe { for node in nodes { node.path.free() }; (&array(&nodes)).free() } }
			nodes << StageDirectory{ path: '', parent: -1, device: target.device, inode: target.inode }
			mut next := 0
			for next < nodes.len { scan_stage_tree(root, next, mut nodes)!; next++ }
			assert nodes.len == 3
			path := stage + '/' + subject
			os.rename(path, f.root + '/saved')!
			recovery_replacement(f, path, kind)!
			mut refused := false
			remove_stage_directory(root, parent, target, nodes, 2) or { refused = true }
			assert refused
			assert os.read_file(f.root + '/saved/' + if subject == 'nested' { 'deeper/keep' } else { 'keep' })! == 'captured'
			if kind == 'directory' { assert os.read_file(path + '/keep')! == 'replacement' }
			recovery_preserved(f)!
			recovery_remove_replacement(path)!
			os.rename(f.root + '/saved', path)!
			retire_stage(parent, target)!
		}
	}
	println('STAGE RECOVERY ten replaced nested/ancestor directories refuse without traversing aliases or deleting saved/replacement data; restored trees retire PASS')
}

fn recovery_change_inflight(phase string) {
	if phase != os.getenv('VINIX_RECOVERY_PHASE') { return }
	root := os.getenv('VINIX_RECOVERY_ROOT')
	stage := root + '/store/generations/.stage-2'
	os.rename(stage, root + '/saved') or { panic(err) }
	recovery_replacement(RecoveryFixture{ root: root }, stage, os.getenv('VINIX_RECOVERY_KIND')) or { panic(err) }
}

fn test_stage_recovery_failure_cleanup_preserves_changed_roots_and_outside_data() {
	defer { for key in ['VINIX_RECOVERY_ROOT', 'VINIX_RECOVERY_PHASE', 'VINIX_RECOVERY_KIND'] { os.unsetenv(key) } }
	mut cases := 0
	for phase in ['prepared', 'staged'] {
		for kind in ['directory', 'alias', 'fifo', 'file', 'missing'] {
			f := recovery_fixture()!; defer { os.rmdir_all(f.root) or {} }
			for key, value in {'VINIX_RECOVERY_ROOT': f.root, 'VINIX_RECOVERY_PHASE': phase, 'VINIX_RECOVERY_KIND': kind} { os.setenv(key, value, true) }
			mut refused := false
			transact(f.config, f.directory, 'remove', ['app'], TransactionOptions{ checkpoint: recovery_change_inflight }) or { refused = true }
			assert refused
			recovery_preserved(f)!
			assert os.exists(f.root + '/saved/state.json') && !os.exists(f.directory + '/generations/2')
			stage := f.directory + '/generations/.stage-2'
			if kind == 'directory' { assert os.read_file(stage + '/keep')! == 'replacement' }
			if kind == 'alias' { assert os.is_link(stage) }
			recovery_remove_replacement(stage)!
			os.rename(f.root + '/saved', stage)!
			assert transact(f.config, f.directory, 'remove', ['app'], TransactionOptions{})!.generation == 2
			assert !os.exists(stage) && os.read_file(f.root + '/outside/keep')! == 'preserved'
			cases++
		}
	}
	assert cases == 10
	println('STAGE RECOVERY ten in-flight prepared/staged replacements preserve saved stages and outside data; restored originals retry PASS')
}

fn recovery_mixed_stage(f RecoveryFixture, depth int) !string {
	stage := f.directory + '/generations/.stage-incomplete'
	deep := stage + '/' + 'nested/'.repeat(depth)
	os.mkdir_all(deep)!
	os.write_file(deep + 'partial', 'incomplete payload')!
	os.write_file(stage + '/state.json', '{incomplete')!
	os.symlink(f.root + '/outside', deep + 'alias-dir')!
	os.symlink(f.root + '/outside/keep', deep + 'alias-file')!
	assert C.mkfifo((deep + 'fifo').str, 0o600) == 0
	assert C.link((f.root + '/outside/keep').str, (deep + 'hard-link').str) == 0
	return stage
}

fn test_stage_recovery_handles_incomplete_deep_trees_and_retires_descriptors() {
	f := recovery_fixture()!; defer { os.rmdir_all(f.root) or {} }
	mut original := RecoveryLimit{}
	assert C.getrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0
	limit := RecoveryLimit{ current: 32, maximum: original.maximum }
	assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&limit)) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0 }
	for i in 0 .. 128 {
		path := f.directory + '/generations/.stage-batch-' + i.str()
		os.mkdir(path)!; os.write_file(path + '/partial', 'unfinished')!
	}
	recover_generation_stages(f.directory)!
	assert os.ls(f.directory + '/generations')! == ['1']
	deep := recovery_mixed_stage(f, 64)!
	recover_generation_stages(f.directory)!
	assert !os.exists(deep)
	for _ in 0 .. 128 {
		stage := recovery_mixed_stage(f, 4)!
		recover_generation_stages(f.directory)!
		assert !os.exists(stage)
		os.symlink(f.root + '/outside', stage)!
		mut refused := false
		recover_generation_stages(f.directory) or {
			message := err.msg(); refused = message.contains('unsafe unpublished package stage')
			unsafe { message.free(); err.free() }
		}
		assert refused
		os.rm(stage)!
	}
	recovery_preserved(f)!
	println('STAGE RECOVERY incomplete 64-level tree and 128 mixed-tree retirements/refusals keep descriptors below 32 without traversing aliases or opening FIFOs PASS')
}

fn test_stage_recovery_finishes_wide_directory_enumeration_before_deletion() {
	f := recovery_fixture()!; defer { os.rmdir_all(f.root) or {} }
	stage := recovery_mixed_stage(f, 1)!
	for i in 0 .. 1024 { os.write_file(stage + '/nested/' + i.str() + '-' + 'x'.repeat(64), 'partial')! }
	recover_generation_stages(f.directory)!
	assert !os.exists(stage)
	recovery_preserved(f)!
	println('STAGE RECOVERY 1024 long-name files spanning directory buffers retire completely in one recovery pass PASS')
}

fn test_stage_recovery_checker_releases_owned_scratch() {
	$if track_heap ? {
		f := recovery_fixture()!; defer { os.rmdir_all(f.root) or {} }
		for damaged in [false, true] {
			for _ in 0 .. 128 {
				stage := if damaged { f.directory + '/generations/.stage-refuse' } else { recovery_mixed_stage(f, 4)! }
				if damaged { os.symlink(f.root + '/outside', stage)! }
				C.vinix_heap_begin()
				mut refused := false
				recover_generation_stages(f.directory) or {
					message := err.msg(); refused = true
					unsafe { message.free(); err.free() }
				}
				bytes := C.vinix_heap_end(); count := C.vinix_heap_count()
				assert refused == damaged && bytes == 0 && count == 0
				if damaged { os.rm(stage)! }
			}
		}
		println('STAGE RECOVERY 128 successful tree retirements and 128 refusals retain zero checker allocations PASS')
	}
}
