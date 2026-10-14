// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time

#include <sys/resource.h>
fn C.link(&char, &char) int
fn C.mkfifo(&char, u32) int
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int
fn C.fork() int
fn C.waitpid(int, &int, int) int
fn C._exit(int)
fn C.alarm(u32) u32
struct PublisherWorkspaceLimit { current u64 maximum u64 }

fn workspace_case(name string) bool {
	if os.args.len == 1 { return true }
	assert os.args.len == 3 && os.args[1] == 'case'
	assert os.args[2] in ['writers', 'admission', 'containment', 'entries', 'retirement']
	return os.args[2] == name
}

fn publisher_workspace_fixture() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-publisher-workspace-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir(work, mode: 0o700)!; os.mkdir(work + '/source')!
	println('PUBLISHER FIXTURE created')
	os.write_file(work + '/source/data', 'payload')!
	os.write_file(work + '/seed', '01'.repeat(32) + '\n')!; os.chmod(work + '/seed', 0o600)!
	os.write_file(work + '/manifest.json', json2.encode(Package{ id: 'data', name: 'Data',
		version: '1.0.0', architecture: 'all', kind: 'data', license: 'MIT' }))!
	pack(work + '/manifest.json', work + '/source', work + '/repository')!
	println('PUBLISHER FIXTURE packed')
	publish(work + '/repository', 'fixture', work + '/seed', 1, 2000000000)!
	println('PUBLISHER FIXTURE signed')
	publish_release(work + '/repository', 'fixture', work + '/seed', 1, 2000000000, work + '/first')!
	println('PUBLISHER FIXTURE released')
	return work
}

fn workspace_call(operation string, work string, repository string, destination string) ! {
	match operation {
		'pack' { pack(work + '/manifest.json', work + '/source', repository)! }
		'publish' { publish(repository, 'fixture', work + '/seed', 2, 2000000000)! }
		'release' { publish_release(repository, 'fixture', work + '/seed', 2, 2000000000, destination)! }
		else { return error('unknown publisher operation') }
	}
}

fn workspace_documents(work string) ![]string {
	mut documents := []string{}
	for name in ['manifests/data-all-1.0.0.json', 'index.json', 'index.sig', '.publisher/history.json'] {
		documents << read_metadata(work + '/repository/' + name)!
	}
	documents << os.ls(work + '/repository/objects')!.sorted().join('\n')
	return documents
}

fn workspace_nested_attempt(phase string, workspace string) ! {
	if phase != 'locked' { return }
	work := os.dir(workspace)
	for operation in ['pack', 'publish', 'release'] {
		mut refused := false
		workspace_call(operation, work, workspace, work + '/nested-release') or { refused = err.msg().contains('another publisher') }
		assert refused && !os.exists(work + '/nested-release')
	}
}

fn workspace_stop_locked(phase string, _ string) ! { if phase == 'locked' { C._exit(77) } }

fn test_publisher_workspace_all_mutators_share_exclusion_preserve_documents_and_retry() {
	if !workspace_case('writers') { return }
	work := publisher_workspace_fixture()!
	defer { os.rmdir_all(work) or {} }
	before := workspace_documents(work)!
	os.write_file(work + '/source/data', 'updated payload')!
	guard := publisher_lock(work + '/repository')!
	for operation in ['pack', 'publish', 'release'] {
		mut refused := false
		workspace_call(operation, work, work + '/repository', work + '/blocked-release') or { refused = err.msg().contains('another publisher') }
		assert refused && workspace_documents(work)! == before && !os.exists(work + '/blocked-release')
	}
	guard.release()
	// The pack checkpoint proves that its lock stays held throughout copying and
	// manifest publication, and that every other entry point observes it.
	pack_with(work + '/manifest.json', work + '/source', work + '/repository',
		PackSourceOptions{ checkpoint: workspace_nested_attempt })!
	for operation in ['publish', 'release'] { workspace_call(operation, work, work + '/repository', work + '/retry-release')! }
	assert release_history(work + '/repository')!.repositories[0].sequence == 2
	assert read_metadata(work + '/repository/index.json')! == read_metadata(work + '/retry-release/index.json')!
	assert read_metadata(work + '/repository/index.sig')! == read_metadata(work + '/retry-release/index.sig')!
	assert os.ls(work + '/retry-release')!.sorted() == ['index.json', 'index.sig', 'objects']
	stable := workspace_documents(work)!
	os.write_file(work + '/source/data', 'interrupted payload')!
	child := C.fork(); assert child >= 0
	if child == 0 {
		C.alarm(3)
		pack_with(work + '/manifest.json', work + '/source', work + '/repository',
			PackSourceOptions{ checkpoint: workspace_stop_locked }) or { C._exit(78) }
		C._exit(79)
	}
	mut status := 0
	assert C.waitpid(child, &status, 0) == child && status == 77 << 8
	assert workspace_documents(work)! == stable
	pack(work + '/manifest.json', work + '/source', work + '/repository')!
}

fn test_publisher_workspace_admission_refuses_nul_aliases_and_shared_roots_without_mutation() {
	if !workspace_case('admission') { return }
	work := publisher_workspace_fixture()!
	defer { os.rmdir_all(work) or {} }
	os.symlink(work + '/repository', work + '/alias')!
	os.symlink(work, work + '/parent-alias')!
	before := workspace_documents(work)!
	for operation in ['pack', 'publish', 'release'] {
		for path in ['', '/'.repeat(4097), work + '/repository\x00ignored', work + '/alias', work + '/alias///'] {
			mut refused := false
			workspace_call(operation, work, path, work + '/refused') or { refused = true }
			assert refused && workspace_documents(work)! == before && !os.exists(work + '/refused')
		}
		os.chmod(work + '/repository', 0o777)!
		mut refused := false
		workspace_call(operation, work, work + '/repository', work + '/refused') or { refused = err.msg().contains('not writable') }
		assert refused && os.lstat(work + '/repository')!.mode & 0o777 == 0o777 && workspace_documents(work)! == before
		os.chmod(work + '/repository', 0o755)!
	}
	for path in [work + '/repository///', work + '/parent-alias/repository'] {
		p := publisher_workspace(path, false)!
		assert p == work + '/repository'
		unsafe { p.free() }
	}
}

fn test_publisher_workspace_output_cannot_contaminate_captured_sources_including_alias_dotdot() {
	if !workspace_case('containment') { return }
	work := publisher_workspace_fixture()!
	defer { os.rmdir_all(work) or {} }
	os.mkdir(work + '/source/sub')!
	os.symlink(work + '/source/sub', work + '/alias')!
	before := os.ls(work + '/source')!.sorted()
	for path in [work + '/source', work + '/source/sub/deep/repository', work + '/alias/../deep/repository'] {
		mut refused := false
		pack(work + '/manifest.json', work + '/source', path) or { refused = err.msg().contains('outside the package source') }
		assert refused && os.ls(work + '/source')!.sorted() == before
		assert os.ls(work + '/source/sub')!.len == 0 && !os.exists(work + '/source/deep')
	}
	// Similar lexical prefixes are unrelated directories and remain supported.
	pack(work + '/manifest.json', work + '/source', work + '/source-other/new/repository')!
	assert os.is_file(work + '/source-other/new/repository/manifests/data-all-1.0.0.json')
}

fn test_publisher_workspace_refuses_unsafe_child_directories_and_shared_or_replaced_lock_files() {
	if !workspace_case('entries') { return }
	work := publisher_workspace_fixture()!
	defer { os.rmdir_all(work) or {} }
	os.mkdir(work + '/outside')!; os.write_file(work + '/outside/preserved', 'untouched')!
	for name in ['objects', 'manifests', '.publisher'] {
		path := work + '/repository/' + name
		os.rename(path, path + '.saved')!; os.symlink(work + '/outside', path)!
		for operation in ['pack', 'publish', 'release'] {
			mut refused := false
			workspace_call(operation, work, work + '/repository', work + '/refused') or { refused = true }
			assert refused && !os.exists(work + '/refused') && os.ls(work + '/outside')! == ['preserved']
		}
		os.rm(path)!; os.rename(path + '.saved', path)!
	}
	lock_path := work + '/repository/.publisher/lock'
	assert C.link(lock_path.str, (work + '/shared-lock').str) == 0
	for operation in ['pack', 'publish', 'release'] {
		mut refused := false
		workspace_call(operation, work, work + '/repository', work + '/refused') or { refused = err.msg().contains('without hard links') }
		assert refused && !os.exists(work + '/refused') && os.read_file(lock_path)! == ''
	}
	os.rm(work + '/shared-lock')!
	guard := publisher_lock(work + '/repository')!
	os.rename(lock_path, lock_path + '.saved')!; os.write_file(lock_path, '')!; os.chmod(lock_path, 0o600)!
	mut refused := false
	check_publisher_lock(guard.fd, lock_path) or { refused = true }
	assert refused
	os.rm(lock_path)!; os.rename(lock_path + '.saved', lock_path)!; guard.release()
	guard2 := publisher_lock(work + '/repository')!; guard2.release()
}

fn test_publisher_workspace_ancestor_and_lock_checks_retire_descriptors_under_repeated_refusal() {
	if !workspace_case('retirement') { return }
	work := publisher_workspace_fixture()!
	defer { os.rmdir_all(work) or {} }
	root := capture_prepared_root(work + '/source', 'test')!
	defer { C.close(root) }
	mut original := PublisherWorkspaceLimit{}
	assert C.getrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0
	limit := PublisherWorkspaceLimit{ current: 32, maximum: original.maximum }
	assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&limit)) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0 }
	for _ in 0 .. 64 {
		publisher_outside_source(root, work + '/new/deep/repository')!
		mut refused := false
		publisher_outside_source(root, work + '/source/deep/repository') or { refused = true }; assert refused
		path := publisher_workspace(work + '/repository///', false)!; unsafe { path.free() }
		guard := publisher_lock(work + '/repository')!
		refused = false; publisher_lock(work + '/repository') or { refused = true }; assert refused
		guard.release()
	}
}
