// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time

#include <sys/resource.h>
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int
fn C.mkfifo(&char, u32) int
struct CatalogExportLimit { current u64 maximum u64 }

fn catalog_export_fixture() !(string, []CatalogSource) {
	work := os.real_path(os.temp_dir()) + '/vinix-catalog-export-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	mut sources := []CatalogSource{}
	for id in ['alpha', 'beta']! {
		root := work + '/roots/' + id + '/shared'
		os.mkdir_all(root)!
		os.write_file(root + '/data', id + ' authenticated catalog data')!
		p := Package{ id: id, version: '1.0.0', architecture: 'all', name: id, kind: 'data', license: 'MIT',
			files: [Payload{ path: 'share/data', bytes: os.file_size(root + '/data'), sha256: hash_file(root + '/data')! }] }
		recipe := CatalogRecipe{ format: 1, architectures: ['aarch64', 'x86_64'], packages: [CatalogImport{ source: 'shared',
			recipe: RootRecipe{ manifest: p, entries: [RootEntry{ source: 'data', path: 'share/data' }] } }] }
		path := work + '/' + id + '.json'
		os.write_file(path, publisher_json(recipe))!
		sources << CatalogSource{ id: id, catalog: path }
	}
	return work, sources
}

fn catalog_export_run(kind string, architecture string, work string, sources []CatalogSource, target string, options CatalogOptions) ! {
	if kind == 'catalog' {
		mut info := catalog_build(sources[0].catalog, work + '/roots/alpha', target, options)!
		defer { info.close() }
		assert info.architectures == ['aarch64', 'x86_64'] && info.package_count == 1
	} else {
		mut info := compose_catalog_selected(sources, target, architecture, options)!
		defer { info.close() }
		assert info.architectures == if architecture == '' { ['aarch64', 'x86_64'] } else { [architecture] }
		assert info.package_count == 2 && info.sources.map(it.id) == ['alpha', 'beta']
	}
}

fn catalog_export_replace_failed(phase string, stage string) ! {
	if phase != 'created' { return }
	parent := os.dir(stage)
	os.write_file(parent + '/stage-path', stage)!
	os.rename(stage, parent + '/saved-stage')!
	os.mkdir(stage)!
	os.write_file(stage + '/keep', 'replacement must survive')!
	return error('injected catalog export refusal')
}

fn catalog_export_baseline(kind string) ! {
	work, sources := catalog_export_fixture()!; defer { os.rmdir_all(work) or {} }
	mut refused := false
	catalog_export_run(kind, '', work, sources, work + '/output/export', CatalogOptions{ checkpoint: catalog_export_replace_failed }) or {
		refused = err.msg().contains('injected catalog export refusal')
	}
	stage := os.read_file(work + '/output/stage-path')!
	preserved := os.read_file(stage + '/keep') or { '' }
	println('CATALOG EXPORT baseline ' + kind + ' refused=' + refused.str() + ' replacement-preserved=' + (preserved == 'replacement must survive').str())
	assert refused && preserved == 'replacement must survive' && os.is_dir(work + '/output/saved-stage') && !os.exists(work + '/output/export')
}

fn test_catalog_export_failed_workspace_preserves_replaced_stage() { catalog_export_baseline('catalog')! }
fn test_catalog_export_failed_composition_preserves_replaced_stage() { catalog_export_baseline('composition')! }

fn catalog_export_snapshot(directory string) !string {
	mut paths := os.walk_ext(directory, '')
	paths.sort()
	mut text := ''
	for path in paths {
		if os.is_file(path) {
			text += path[directory.len..] + ':' + os.stat(path)!.mode.str() + ':' + hash_file(path)! + '\n'
		}
	}
	return text
}

fn catalog_export_substitute(phase string, stage string) ! {
	if phase != os.getenv('VINIX_CATALOG_EXPORT_PHASE') { return }
	work := os.getenv('VINIX_CATALOG_EXPORT_CASE')
	if os.exists(work + '/stage-path') { return }
	os.write_file(work + '/stage-path', stage)!
	os.write_file(work + '/stage-inode', os.stat(stage)!.inode.str())!
	os.write_file(work + '/stage-snapshot', catalog_export_snapshot(stage)!)!
	kind := os.getenv('VINIX_CATALOG_EXPORT_KIND')
	if kind == 'parent' { os.rename(os.dir(stage), work + '/saved-parent')!; os.mkdir(os.dir(stage))! }
	else { os.rename(stage, work + '/saved-stage')! }
	match kind {
		'directory', 'parent' { os.mkdir(stage)!; os.write_file(stage + '/keep', 'preserved')! }
		'alias' { os.symlink(work + '/outside', stage)! }
		'dangling' { os.symlink(work + '/absent', stage)! }
		'fifo' { assert C.mkfifo(stage.str, 0o600) == 0 }
		'file' { os.write_file(stage, 'preserved')! }
		'missing' {}
		'clone' { os.cp_all(work + '/saved-stage', stage, true)! }
		else { panic('unknown catalog export substitution') }
	}
	if os.getenv('VINIX_CATALOG_EXPORT_FAIL') == 'yes' { return error('injected catalog export refusal') }
}

fn catalog_export_assert_replacement(work string, kind string) ! {
	stage := os.read_file(work + '/stage-path')!
	snapshot := os.read_file(work + '/stage-snapshot')!
	if kind in ['directory', 'parent']! { assert os.read_file(stage + '/keep')! == 'preserved' }
	if kind == 'file' { assert os.read_file(stage)! == 'preserved' }
	if kind == 'alias' { assert os.readlink(stage)! == work + '/outside' }
	if kind == 'dangling' { assert os.readlink(stage)! == work + '/absent' }
	if kind == 'fifo' { assert os.lstat(stage)!.mode & 0o170000 == 0o010000 }
	if kind == 'missing' { assert !os.exists(stage) && !os.is_link(stage) }
	if kind == 'clone' { assert catalog_export_snapshot(stage)! == snapshot }
	if kind == 'parent' { assert os.ls(work + '/saved-parent')!.len == 0 }
	else {
		assert catalog_export_snapshot(work + '/saved-stage')! == snapshot
		assert os.stat(work + '/saved-stage')!.inode.str() == os.read_file(work + '/stage-inode')!
	}
	assert os.read_file(work + '/outside/keep')! == 'preserved' && os.stat(work + '/outside')!.mode & 0o777 == 0o700
}

fn test_catalog_export_root_and_parent_substitutions_preserve_recovery_and_retry() {
	work, sources := catalog_export_fixture()!; defer { os.rmdir_all(work) or {} }
	mut inputs := map[string]string{}
	for source in sources { inputs[source.catalog] = os.read_file(source.catalog)! }
	for id in ['alpha', 'beta']! { path := work + '/roots/' + id + '/shared/data'; inputs[path] = os.read_file(path)! }
	mut original := CatalogExportLimit{}
	assert C.getrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0
	limit := CatalogExportLimit{ current: 32, maximum: original.maximum }
	assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &limit }) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0 }
	defer { for name in ['VINIX_CATALOG_EXPORT_CASE', 'VINIX_CATALOG_EXPORT_PHASE', 'VINIX_CATALOG_EXPORT_KIND', 'VINIX_CATALOG_EXPORT_FAIL']! { os.unsetenv(name) } }
	mut cases := 0
	for operation in ['catalog', 'composition', 'aarch64', 'x86_64']! {
		kind := if operation == 'catalog' { 'catalog' } else { 'composition' }
		architecture := if operation in ['aarch64', 'x86_64']! { operation } else { '' }
		for phase in if kind == 'catalog' { ['created', 'packed', 'ready'] } else { ['created', 'ready'] } {
			for replacement in ['directory', 'alias', 'dangling', 'fifo', 'file', 'missing', 'clone', 'parent']! {
				for fail in ['yes', 'no']! {
					case := work + '/case-' + cases.str()
					os.mkdir_all(case + '/output')!; os.mkdir(case + '/outside')!; os.chmod(case + '/outside', 0o700)!
					os.write_file(case + '/outside/keep', 'preserved')!
					for name, value in {'VINIX_CATALOG_EXPORT_CASE': case, 'VINIX_CATALOG_EXPORT_PHASE': phase, 'VINIX_CATALOG_EXPORT_KIND': replacement, 'VINIX_CATALOG_EXPORT_FAIL': fail} { os.setenv(name, value, true) }
					mut message := ''
					catalog_export_run(kind, architecture, work, sources, case + '/output/export', CatalogOptions{ checkpoint: catalog_export_substitute }) or { message = err.msg() }
					assert message != '' && !os.exists(case + '/output/export'), operation + '/' + phase + '/' + replacement + '/' + fail
					if fail == 'yes' { assert message.contains('injected catalog export refusal') }
					if replacement != 'parent' { assert message.contains('cleanup refused') }
					catalog_export_assert_replacement(case, replacement)!
					catalog_export_run(kind, architecture, work, sources, case + '/output/export', CatalogOptions{})!
					catalog_export_assert_replacement(case, replacement)!
					assert os.is_file(case + '/output/export/catalog.json')
					for path, text in inputs { assert os.read_file(path)! == text }
					assert !os.exists(work + '/roots/alpha/.publisher') && !os.exists(work + '/roots/beta/.publisher')
					os.rmdir_all(case)!
					cases++
				}
			}
		}
	}
	assert cases == 144
	println('CATALOG EXPORT 144 workspace/composition/selected-host root and parent substitutions preserve replacements, complete recovery snapshots and source pins; fresh retry under 32 descriptors PASS')
}

fn catalog_export_no_flush(_ int) int { return -1 }

fn catalog_export_move_parent(fd int) int {
	work := os.getenv('VINIX_CATALOG_EXPORT_SAVED')
	os.rename(work + '/output', work + '/saved-parent') or { return -1 }
	os.mkdir(work + '/output') or { return -1 }
	os.write_file(work + '/output/keep', 'replacement parent') or { return -1 }
	return C.fsync(fd)
}

fn test_catalog_export_post_publication_failures_preserve_saved_artifacts() {
	work, sources := catalog_export_fixture()!; defer { os.rmdir_all(work) or {}; os.unsetenv('VINIX_CATALOG_EXPORT_SAVED') }
	for operation in ['catalog', 'composition', 'aarch64', 'x86_64']! {
		kind := if operation == 'catalog' { 'catalog' } else { 'composition' }
		architecture := if operation in ['aarch64', 'x86_64']! { operation } else { '' }
		for mode in ['flush', 'parent']! {
			case := work + '/' + operation + '-' + mode
			os.mkdir_all(case + '/output')!
			os.setenv('VINIX_CATALOG_EXPORT_SAVED', case, true)
			mut message := ''
			catalog_export_run(kind, architecture, work, sources, case + '/output/export', CatalogOptions{ flush: if mode == 'flush' { catalog_export_no_flush } else { catalog_export_move_parent } }) or { message = err.msg() }
			assert message.contains('published') && message.contains(if mode == 'flush' { 'directory flush failed' } else { 'parent path changed' })
			saved := case + if mode == 'flush' { '/output/export' } else { '/saved-parent/export' }
			assert os.is_file(saved + '/catalog.json')
			if mode == 'parent' { assert os.read_file(case + '/output/keep')! == 'replacement parent' && os.ls(case + '/saved-parent')! == ['export'] }
			else { assert os.ls(case + '/output')! == ['export'] }
			catalog_export_run(kind, architecture, work, sources, case + '/retry/export', CatalogOptions{})!
			assert catalog_export_snapshot(saved)! == catalog_export_snapshot(case + '/retry/export')!
		}
	}
	println('CATALOG EXPORT directory-flush and post-rename parent failures retain complete canonical artifacts and accurate saved diagnostics for workspace and all composition target modes PASS')
}

fn test_catalog_export_preserved_composition_and_workspace_feed_signed_offline_consumers() {
	work, sources := catalog_export_fixture()!; defer { os.rmdir_all(work) or {} }
	mut composition := compose_catalog(sources, work + '/composition')!; defer { composition.close() }
	mut workspace := pack_catalog(composition.catalog, work + '/roots', work + '/workspace')!; defer { workspace.close() }
	key := keygen(work + '/seed')!
	publish_release(work + '/workspace', 'fixture', work + '/seed', 1, time.now().unix() + 3600, work + '/release')!
	for architecture in ['aarch64', 'x86_64']! {
		config := Config{ architecture: architecture, policy: Policy{ offline: true, reserve_bytes: 0 },
			repositories: [Repository{ id: 'fixture', url: 'file://' + work + '/release', public_key: key }] }
		store := work + '/store-' + architecture
		refresh(config, store)!
		installed := transact(config, store, 'install', ['alpha', 'beta'], TransactionOptions{})!
		// Transaction results borrow caller/catalog fields; State.close() is
		// reserved for independently owned Service.state/verify observations.
		assert installed.packages.len == 2 && installed.requested == ['alpha', 'beta']
		assert os.read_file(store + '/generations/1/apps/alpha/share/data')! == 'alpha authenticated catalog data'
		removed := transact(config, store, 'remove', ['alpha', 'beta'], TransactionOptions{})!
		assert removed.packages.len == 0
	}
	println('CATALOG EXPORT canonical composition and workspace preserve signed release closure and offline install/remove for both consumer architectures PASS')
}
