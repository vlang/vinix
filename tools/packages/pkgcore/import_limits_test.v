// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time

#include <sys/resource.h>
fn C.mkfifo(&char, u32) int
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int
struct ImportLimitDescriptors { current u64 maximum u64 }

fn import_limits_work() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-import-limits-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(work + '/root/tree')!
	os.mkdir(work + '/output')!
	return work
}

fn import_limits_recipe(entries []RootEntry) RootRecipe {
	return RootRecipe{ manifest: Package{ id: 'bounded', name: 'Bounded import', architecture: 'all',
		version: '1.0.0', kind: 'data', license: 'MIT' }, entries: entries }
}

fn import_limits_package(work string, root string, target string, repository string) !Package {
	recipe := publisher_json(import_limits_recipe([RootEntry{ source: 'tree', path: target }]))
	defer { unsafe { recipe.free() } }
	os.write_file(work + '/recipe.json', recipe)!
	return pack_root(work + '/recipe.json', root, repository)
}

fn import_limits_scratch() ![]string {
	prefix := 'vinix-pack-root-' + os.getpid().str() + '-'
	return os.ls(os.temp_dir())!.filter(it.starts_with(prefix))
}

fn import_limits_tree(root string, descendants int) !string {
	mut path := root + '/tree'
	for _ in 0 .. descendants { path += '/d'; os.mkdir(path)! }
	os.write_file(path + '/data', 'bounded payload')!
	return path
}

fn test_prepared_import_stops_before_materializing_excessive_directory_depth() {
	work := import_limits_work()!
	defer { os.rmdir_all(work) or {} }
	leaf := import_limits_tree(work + '/root', 128)!
	root := capture_prepared_root(work + '/root', 'test')!
	defer { C.close(root) }
	mut importer := RootImport{ root: root, output: work + '/output' }
	mut diagnostic := ''
	importer.copy('tree', 'payload') or { diagnostic = err.msg() }
	before := os.getenv('VINIX_IMPORT_LIMITS_BEFORE') == '1'
	if before {
		assert diagnostic == ''
		assert os.read_file(work + '/output/payload' + '/d'.repeat(128) + '/data')! == 'bounded payload'
		println('IMPORT LIMITS baseline: 129 directory levels and payload materialized before the later pack walk PASS')
	} else {
		assert diagnostic.contains('depth limit'), diagnostic
		assert !os.exists(work + '/output/payload' + '/d'.repeat(128))
		assert importer.ancestors.len == 0
		mut refused := false
		import_limits_package(work, work + '/root', 'payload', work + '/denied') or { refused = err.msg().contains('depth limit') }
		assert refused && !os.exists(work + '/denied') && import_limits_scratch()!.len == 0
		recipe := publisher_json(import_limits_recipe([RootEntry{ source: 'tree/d', path: 'payload' }]))
		os.write_file(work + '/retry.json', recipe)!
		p := pack_root(work + '/retry.json', work + '/root', work + '/retry-repository')!
		assert p.files.len == 1 && import_limits_scratch()!.len == 0
		close_decoded_package(p)
		println('IMPORT LIMITS 129th directory refuses before materialization; source and ancestor state preserved PASS')
	}
	assert os.read_file(leaf + '/data')! == 'bounded payload'
}

fn test_prepared_import_exact_depth_and_nested_selector_parents_match_final_packer() {
	assert max_pack_depth == 128 && max_pack_entries == 32768
	work := import_limits_work()!
	defer { os.rmdir_all(work) or {} }
	import_limits_tree(work + '/root', 127)!
	p := import_limits_package(work, work + '/root', 'payload', work + '/exact')!
	defer { close_decoded_package(p) }
	assert p.files.len == 1 && p.files[0].path == 'payload' + '/d'.repeat(127) + '/data'
	os.write_file(work + '/root/tree/data', 'shallow payload')!
	// An existing shallow directory selected beneath 128 parents is itself the
	// 129th directory and must refuse before its payload is copied.
	root := capture_prepared_root(work + '/root', 'test')!
	defer { C.close(root) }
	mut nested := RootImport{ root: root, output: work + '/output' }
	mut refused := false
	nested.copy('tree', 'p/'.repeat(128) + 'tree') or { refused = err.msg().contains('depth limit') }
	assert refused && os.ls(work + '/output')!.len == 0
	// A regular file may have exactly 128 parents, matching pack's depth rule.
	mut file := RootImport{ root: root, output: work + '/output' }
	target := 'p/'.repeat(128) + 'data'
	file.copy('tree/data', target)!
	assert os.read_file(work + '/output/' + target)! == 'shallow payload'
	mut excessive := RootImport{ root: root, output: work + '/not-created' }
	refused = false
	excessive.copy('tree/data', 'p/'.repeat(129) + 'data') or { refused = err.msg().contains('depth limit') }
	assert refused && !os.exists(work + '/not-created')
	println('IMPORT LIMITS exact 128-level directory/file boundary and nested selector parents match final pack rules PASS')
}

fn test_prepared_import_global_entry_budget_counts_aliases_and_all_selectors() {
	work := import_limits_work()!
	defer { os.rmdir_all(work) or {} }
	os.mkdir(work + '/root/tree/empty')!
	os.write_file(work + '/root/tree/data', 'bounded payload')!
	os.symlink('/tree', work + '/root/alias')!
	root := capture_prepared_root(work + '/root', 'test')!
	defer { C.close(root) }
	mut importer := RootImport{ root: root, output: work + '/output', entries: max_pack_entries - 3 }
	importer.copy('alias', 'first')!
	assert importer.entries == max_pack_entries && importer.files == 1 && importer.ancestors.len == 0
	assert os.read_file(work + '/output/first/data')! == 'bounded payload'
	mut refused := false
	importer.copy('tree', 'second') or { refused = err.msg().contains('entry limit') }
	assert refused && !os.exists(work + '/output/second')
	mut insufficient := RootImport{ root: root, output: work + '/too-wide', entries: max_pack_entries - 2 }
	refused = false
	insufficient.copy('alias', 'payload') or { refused = err.msg().contains('entry limit') }
	assert refused && !os.exists(work + '/too-wide') && insufficient.ancestors.len == 0
	// A new import has a fresh budget; separate selectors of the same namespace
	// consume work again, but are not mistaken for a directory cycle.
	mut retry := RootImport{ root: root, output: work + '/retry' }
	retry.copy('tree', 'one')!; retry.copy('alias', 'two')!
	assert retry.entries == 6 && retry.files == 2 && retry.ancestors.len == 0
	assert os.read_file(work + '/retry/one/data')! == os.read_file(work + '/retry/two/data')!
	println('IMPORT LIMITS shared 32768-entry budget counts selected roots, empty directories and repeated aliases; refusal precedes output and retry resets budget PASS')
}

fn test_prepared_import_bounded_enumeration_retires_descriptors_and_partial_names() {
	work := import_limits_work()!
	defer { os.rmdir_all(work) or {} }
	os.write_file(work + '/root/tree/a', 'a')!
	os.write_file(work + '/root/tree/b', 'b')!
	before := import_limits_descriptors()
	for _ in 0 .. 32 {
		for limit in [0, 1, 2]! {
			root := capture_prepared_root(work + '/root/tree', 'test')!
			defer { C.close(root) }
			if names := import_names_limit(root, limit) {
				assert limit == 2 && names == ['a', 'b']
				unsafe { names.free() }
			} else { assert limit < 2 && err.msg().contains('entry limit') }
		}
		assert import_limits_descriptors() == before
	}
	println('IMPORT LIMITS remaining-budget enumeration refuses partial lists and preserves sorted exact-boundary names PASS')
}

fn import_limits_descriptors() int {
	mut count := 0
	for fd in 0 .. 256 { if C.fcntl(fd, C.F_GETFD, 0) >= 0 { count++ } }
	return count
}

fn test_prepared_import_failure_cleanup_descriptor_retirement_and_public_retry() {
	work := import_limits_work()!
	defer { os.rmdir_all(work) or {} }
	os.write_file(work + '/root/tree/data', 'bounded payload')!
	mut original := ImportLimitDescriptors{}
	assert C.getrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0
	limit := ImportLimitDescriptors{ current: 32, maximum: original.maximum }
	assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&limit)) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0 }
	before := import_limits_descriptors()
	for _ in 0 .. 32 {
		assert C.mkfifo((work + '/root/tree/fifo').str, 0o600) == 0
		mut refused := false
		import_limits_package(work, work + '/root', 'payload', work + '/repository') or { refused = err.msg().contains('special file') }
		assert refused && !os.exists(work + '/repository') && import_limits_scratch()!.len == 0
		os.rm(work + '/root/tree/fifo')!
		p := import_limits_package(work, work + '/root', 'payload', work + '/repository')!
		assert p.files.len == 1
		close_decoded_package(p)
		assert import_limits_scratch()!.len == 0 && import_limits_descriptors() == before
		os.rmdir_all(work + '/repository')!
	}
	println('IMPORT LIMITS 32 failed/successful public imports retire descriptors and private scratch, preserve source bytes and permit exact retry PASS')
}
