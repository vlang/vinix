// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import os
import time

#include <sys/resource.h>
fn C.mkfifo(&char, u32) int
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int
struct ImportCaptureLimit { current u64 maximum u64 }

fn import_capture_work() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-import-capture-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(work + '/root/tree')!
	os.mkdir(work + '/root/other')!
	os.write_file(work + '/root/tree/data', 'original')!
	os.write_file(work + '/root/other/data', 'external')!
	os.chmod(work + '/root/tree/data', 0o644)!
	os.chmod(work + '/root/other/data', 0o640)!
	return work
}

fn import_capture_recipe(work string, source string) !string {
	path := work + '/recipe.json'
	text := publisher_json(RootRecipe{ manifest: Package{ id: 'captured', name: 'Captured import', version: '1.0.0',
		architecture: 'all', kind: 'data', license: 'MIT' }, entries: [RootEntry{ source: source, path: 'payload' }] })
	defer { unsafe { text.free() } }
	os.write_file(path, text)!
	return path
}

fn import_capture_change(phase string, relative string) ! {
	if phase != os.getenv('VINIX_IMPORT_CAPTURE_PHASE') || relative != os.getenv('VINIX_IMPORT_CAPTURE_ENTRY') { return }
	// One mutation per attempt, including multi-block hash/copy loops.
	os.unsetenv('VINIX_IMPORT_CAPTURE_PHASE')
	path := os.getenv('VINIX_IMPORT_CAPTURE_PATH')
	match os.getenv('VINIX_IMPORT_CAPTURE_CHANGE') {
		'error' { return error('injected prepared import failure') }
		'grow' { mut file := os.open_append(path)!; file.write_string('extra')!; file.close() }
		'shrink' { os.truncate(path, 0)! }
		'exec' { os.chmod(path, 0o755)! }
		'content' { os.write_file(path, os.getenv('VINIX_IMPORT_CAPTURE_CONTENT'))! }
		'add' { os.write_file(path + '/added', 'extra entry')! }
		'remove' { os.rm(path + '/data')! }
		'rename' { os.rename(path + '/data', path + '/renamed')! }
		else {
			os.rename(path, path + '.saved')!
			match os.getenv('VINIX_IMPORT_CAPTURE_CHANGE') {
				'alias' { os.symlink(os.getenv('VINIX_IMPORT_CAPTURE_TARGET'), path)! }
				'fifo' { assert C.mkfifo(path.str, 0o600) == 0 }
				'ordinary' { os.write_file(path, 'external')! }
				'directory' { os.mkdir(path)!; os.write_file(path + '/data', 'external')! }
				'missing' {}
				else { panic('unknown import capture mutation') }
			}
		}
	}
}

fn import_capture_hook(phase string, entry string, path string, target string, change string) PackSourceOptions {
	for key, value in { 'PHASE': phase, 'ENTRY': entry, 'PATH': path, 'TARGET': target, 'CHANGE': change } {
		os.setenv('VINIX_IMPORT_CAPTURE_' + key, value, true)
	}
	return PackSourceOptions{ checkpoint: import_capture_change }
}

fn import_capture_descriptors() int {
	mut count := 0
	for fd in 0 .. 256 { if C.fcntl(fd, C.F_GETFD, 0) >= 0 { count++ } }
	return count
}

fn import_capture_scratch() ![]string {
	prefix := 'vinix-pack-root-' + os.getpid().str() + '-'
	return os.ls(os.temp_dir())!.filter(it.starts_with(prefix))
}

fn import_capture_restore(path string, directory bool) ! {
	if os.is_dir(path) && !os.is_link(path) { os.rmdir_all(path)! } else { os.rm(path) or {} }
	if os.exists(path + '.saved') { os.rename(path + '.saved', path)! } else if directory {
		os.mkdir(path)!; os.write_file(path + '/data', 'original')!
	} else { os.write_file(path, 'original')! }
	os.chmod(if directory { path + '/data' } else { path }, 0o644)!
}

fn test_prepared_import_captured_root_survives_host_replacement_and_resolves_guest_links() {
	work := import_capture_work()!
	defer { os.rmdir_all(work) or {} }
	os.symlink('/tree', work + '/root/alias')!
	os.mkdir(work + '/outside')!; os.write_file(work + '/outside/data', 'external')!
	recipe := import_capture_recipe(work, 'alias')!
	options := import_capture_hook('root', work + '/root///', work + '/root', work + '/outside', 'alias')
	p := pack_root_with(recipe, work + '/root///', work + '/repository', options)!
	defer { close_decoded_package(p) }
	assert p.files.len == 1 && p.files[0].sha256 == sha256.hexhash('original')
	assert os.read_file(work + '/repository/objects/' + p.files[0].sha256)! == 'original'
	assert !os.exists(work + '/repository/objects/' + sha256.hexhash('external'))
	assert os.read_file(work + '/outside/data')! == 'external'
	retried := pack_root(recipe, work + '/root.saved', work + '/retry')!
	defer { close_decoded_package(retried) }
	assert p == retried && import_capture_scratch()!.len == 0
	println('IMPORT CAPTURE retained root and guest-absolute aliases survive host namespace replacement with identical retry metadata PASS')
}

fn test_prepared_import_rechecks_file_identity_size_and_executable_mode() {
	mut original := ImportCaptureLimit{}
	assert C.getrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0
	limit := ImportCaptureLimit{ current: 32, maximum: original.maximum }
	assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&limit)) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0 }
	before := import_capture_descriptors()
	for phase in ['opened', 'sized', 'block', 'read', 'hashed', 'copy-block', 'copied'] {
		for change in ['alias', 'ordinary', 'fifo', 'missing', 'grow', 'shrink', 'exec'] {
			work := import_capture_work()!
			defer { os.rmdir_all(work) or {} }
			recipe := import_capture_recipe(work, 'tree/data')!
			path := work + '/root/tree/data'
			options := import_capture_hook(phase, 'tree/data', path, '/other/data', change)
			mut diagnostic := ''
			pack_root_with(recipe, work + '/root', work + '/repository', options) or { diagnostic = err.msg() }
			assert diagnostic != '', phase + '/' + change
			assert !os.exists(work + '/repository') && import_capture_scratch()!.len == 0
			assert import_capture_descriptors() == before
			assert os.read_file(work + '/root/other/data')! == 'external'
			assert os.lstat(work + '/root/other/data')!.mode & 0o777 == 0o640
			import_capture_restore(path, false)!
			p := pack_root(recipe, work + '/root', work + '/repository')!
			assert p.files.len == 1 && p.files[0].sha256 == sha256.hexhash('original') && !p.files[0].executable
			close_decoded_package(p)
			assert import_capture_descriptors() == before && import_capture_scratch()!.len == 0
		}
	}
	println('IMPORT CAPTURE 49 file identity/size/execute mutations refuse before publication; 32-descriptor cleanup and exact retry PASS')
}

fn test_prepared_import_rejects_same_size_rewrites_between_hash_and_copy() {
	for phase in ['block', 'read', 'hashed', 'copy-block'] {
		work := import_capture_work()!
		defer { os.rmdir_all(work) or {} }
		text := 'o'.repeat(131073)
		os.write_file(work + '/root/tree/data', text)!
		os.setenv('VINIX_IMPORT_CAPTURE_CONTENT', 'x'.repeat(text.len), true)
		options := import_capture_hook(phase, 'tree/data', work + '/root/tree/data', '', 'content')
		recipe := import_capture_recipe(work, 'tree/data')!
		mut diagnostic := ''
		pack_root_with(recipe, work + '/root', work + '/repository', options) or { diagnostic = err.msg() }
		assert diagnostic.contains('changed contents'), phase + ': ' + diagnostic
		assert !os.exists(work + '/repository') && import_capture_scratch()!.len == 0
		os.write_file(work + '/root/tree/data', text)!
		p := pack_root(recipe, work + '/root', work + '/retry')!
		assert p.files[0].sha256 == sha256.hexhash(text) && p.files[0].bytes == u64(text.len)
		close_decoded_package(p)
	}
	println('IMPORT CAPTURE multi-block same-size rewrites during hashing and copying fail content comparison before publication PASS')
}

fn test_prepared_import_rechecks_directory_identity_and_complete_names() {
	for phase in ['opened', 'directory', 'copied'] {
		for change in ['alias', 'directory', 'fifo', 'missing'] {
			work := import_capture_work()!
			defer { os.rmdir_all(work) or {} }
			recipe := import_capture_recipe(work, 'tree')!
			options := import_capture_hook(phase, if phase == 'copied' { 'tree/data' } else { 'tree' },
				work + '/root/tree', '/other', change)
			mut refused := false
			pack_root_with(recipe, work + '/root', work + '/repository', options) or { refused = true }
			assert refused, phase + '/' + change
			assert !os.exists(work + '/repository') && import_capture_scratch()!.len == 0
			assert os.read_file(work + '/root/other/data')! == 'external'
			import_capture_restore(work + '/root/tree', true)!
			p := pack_root(recipe, work + '/root', work + '/repository')!
			assert p.files.len == 1 && p.files[0].sha256 == sha256.hexhash('original')
			close_decoded_package(p)
		}
	}
	for change in ['add', 'remove', 'rename'] {
		work := import_capture_work()!
		defer { os.rmdir_all(work) or {} }
		recipe := import_capture_recipe(work, 'tree')!
		options := import_capture_hook('copied', 'tree/data', work + '/root/tree', '', change)
		mut refused := false
		pack_root_with(recipe, work + '/root', work + '/repository', options) or { refused = true }
		assert refused && !os.exists(work + '/repository') && import_capture_scratch()!.len == 0
		import_capture_restore(work + '/root/tree', true)!
		p := pack_root(recipe, work + '/root', work + '/repository')!
		assert p.files.len == 1 && p.files[0].sha256 == sha256.hexhash('original')
		close_decoded_package(p)
	}
	println('IMPORT CAPTURE directory replacement and added/removed/renamed entries refuse; guest targets survive and retries succeed PASS')
}

fn test_prepared_import_pinned_inventory_and_empty_payloads_keep_canonical_bytes() {
	work := import_capture_work()!
	defer { os.rmdir_all(work) or {} }
	os.write_file(work + '/root/tree/empty', '')!
	os.chmod(work + '/root/tree/data', 0o4755)!
	recipe_path := import_capture_recipe(work, 'tree')!
	p := pack_root(recipe_path, work + '/root', work + '/ordinary')!
	defer { close_decoded_package(p) }
	root := capture_prepared_root(work + '/root', 'test')!
	defer { C.close(root) }
	recipe := RootRecipe{ manifest: p, entries: [RootEntry{ source: 'tree', path: 'payload' }] }
	pinned := pack_root_descriptor(recipe, root, work + '/pinned', true)!
	defer { close_decoded_package(pinned) }
	assert p == pinned && p.files.len == 2 && p.files[0].executable && p.files[1].bytes == 0
	options := import_capture_hook('hashed', 'tree/data', work + '/root/tree/data', '', 'content')
	os.setenv('VINIX_IMPORT_CAPTURE_CONTENT', 'external', true)
	mut refused := false
	pack_root_descriptor_with(recipe, root, work + '/denied', true, options) or { refused = err.msg().contains('inventory differs') }
	assert refused && !os.exists(work + '/denied') && import_capture_scratch()!.len == 0
	os.write_file(work + '/root/tree/data', 'original')!
	retried := pack_root_descriptor(recipe, root, work + '/retry', true)!
	defer { close_decoded_package(retried) }
	assert p == retried
	println('IMPORT CAPTURE pinned digest/execute admission, empty files, stripped special modes and canonical declarations survive exact retry PASS')
}

fn test_prepared_import_checkpoint_failures_retire_private_work_and_descriptors() {
	work := import_capture_work()!
	defer { os.rmdir_all(work) or {} }
	recipe := import_capture_recipe(work, 'tree')!
	before := import_capture_descriptors()
	for phase in ['root', 'opened', 'directory', 'sized', 'block', 'read', 'hashed', 'copy-block', 'copied'] {
		entry := if phase == 'root' { work + '/root' } else if phase in ['opened', 'directory'] { 'tree' } else { 'tree/data' }
		options := import_capture_hook(phase, entry, '', '', 'error')
		mut refused := false
		pack_root_with(recipe, work + '/root', work + '/repository', options) or {
			refused = err.msg() == 'injected prepared import failure'
		}
		assert refused && !os.exists(work + '/repository') && import_capture_scratch()!.len == 0, phase
		assert import_capture_descriptors() == before
		assert os.read_file(work + '/root/tree/data')! == 'original'
	}
	p := pack_root(recipe, work + '/root', work + '/repository')!
	close_decoded_package(p)
	assert import_capture_descriptors() == before && import_capture_scratch()!.len == 0
	println('IMPORT CAPTURE nine injected checkpoint failures retire descriptors and private scratch before successful public retry PASS')
}
