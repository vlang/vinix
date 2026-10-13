// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time

fn composition_fixture() !(string, []CatalogSource) {
	work := os.real_path(os.temp_dir()) + '/vinix-composition-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	mut sources := []CatalogSource{}
	for profile in ['alpha', 'beta'] {
		mut imports := []CatalogImport{}
		for architecture in ['aarch64', 'x86_64'] {
			root := work + '/roots/' + profile + '/' + architecture
			os.mkdir_all(root + '/bin')!
			os.write_file(root + '/bin/app', profile + ' ' + architecture)!
			os.chmod(root + '/bin/app', 0o755)!
			imports << CatalogImport{ source: architecture, recipe: RootRecipe{
				manifest: Package{ id: profile, version: '1.0.0', architecture: architecture, kind: 'native', name: profile,
					license: 'MIT', entrypoint: 'bin/app', permissions: ['files'], associations: ['text/plain'],
					dependencies: [Dependency{ id: profile + '-notice' }],
					files: [Payload{ path: 'bin/app', bytes: os.file_size(root + '/bin/app'), sha256: hash_file(root + '/bin/app')!, executable: true }] }
				entries: [RootEntry{ source: 'bin/app', path: 'bin/app' }] } }
		}
		shared_root := work + '/roots/' + profile + '/shared'
		os.mkdir_all(shared_root)!
		os.write_file(shared_root + '/NOTICE', profile + ' notice')!
		imports << CatalogImport{ source: 'shared', recipe: RootRecipe{
			manifest: Package{ id: profile + '-notice', version: '1.0.0', architecture: 'all', kind: 'data', name: 'Notice',
				license: if profile == 'beta' { 'Vendor-EULA' } else { 'MIT' }, proprietary: profile == 'beta', firmware: profile == 'beta',
				files: [Payload{ path: 'NOTICE', bytes: os.file_size(shared_root + '/NOTICE'), sha256: hash_file(shared_root + '/NOTICE')! }] }
			entries: [RootEntry{ source: 'NOTICE', path: 'NOTICE' }] } }
		catalog_path := work + '/' + profile + '.json'
		os.write_file(catalog_path, json2.encode(CatalogRecipe{ format: 1, architectures: ['x86_64', 'aarch64'], packages: imports }))!
		sources << CatalogSource{ id: profile, catalog: catalog_path }
	}
	return work, sources
}

fn test_composition_is_canonical_preserves_pins_disclosures_and_installs_both_targets() {
	work, sources := composition_fixture()!
	defer { os.rmdir_all(work) or {} }
	one := compose_catalog(sources, work + '/one')!
	mut reversed := sources.clone(); reversed.reverse_in_place()
	two := compose_catalog(reversed, work + '/two')!
	assert one.catalog_sha256 == two.catalog_sha256 && one.package_count == 6
	assert one.architectures == ['aarch64', 'x86_64'] && one.sources.map(it.id) == ['alpha', 'beta']
	assert os.stat(work + '/one')!.mode & 0o777 == 0o700
	assert read_metadata(one.catalog)! == read_metadata(two.catalog)!
	assert read_metadata(work + '/one/composition.json')! == read_metadata(work + '/two/composition.json')!
	for source in sources { os.write_file(source.catalog, ' \n' + read_metadata(source.catalog)! + '\n')! }
	three := compose_catalog(sources, work + '/three')!
	assert one.catalog_sha256 == three.catalog_sha256
	assert read_metadata(work + '/one/composition.json')! == read_metadata(work + '/three/composition.json')!
	merged := catalog_recipe(read_metadata(one.catalog)!)!
	for source in sources {
		original := catalog_recipe(read_metadata(source.catalog)!)!
		assert one.sources.filter(it.id == source.id)[0].catalog_sha256 == index_digest(json2.encode(original) + '\n')
		for item in original.packages {
			selected := merged.packages.filter(it.source == source.id + '/' + item.source && it.recipe.manifest.id == item.recipe.manifest.id)
			assert selected.len == 1 && selected[0].recipe == item.recipe
		}
	}
	workspace := work + '/workspace'
	assert pack_catalog(one.catalog, work + '/roots', workspace)!.package_count == 6
	key := keygen(work + '/seed')!
	publish_release(workspace, 'composed', work + '/seed', 1, time.now().unix() + 3600, work + '/release')!
	for architecture in one.architectures {
		config := Config{ architecture: architecture,
			repositories: [Repository{ id: 'composed', url: 'file://' + work + '/release', public_key: key }],
			policy: Policy{ offline: true, reserve_bytes: 0 } }
		store := work + '/store-' + architecture
		refresh(config, store)!
		mut denied := false
		transact(config, store, 'install', ['alpha', 'beta'], TransactionOptions{}) or { denied = true }
		assert denied && read_state(store, architecture)!.generation == 0
		accepted := Config{ ...config, policy: Policy{ offline: true, reserve_bytes: 0, licenses: ['Vendor-EULA'], allow_firmware: true } }
		state := transact(accepted, store, 'install', ['alpha', 'beta'], TransactionOptions{})!
		assert state.packages.len == 4 && state.requested == ['alpha', 'beta']
		assert read_metadata(store + '/generations/1/apps/beta/bin/app')! == 'beta ' + architecture
		assert transact(accepted, store, 'remove', ['alpha', 'beta'], TransactionOptions{})!.packages.len == 0
	}
}

fn composition_refused(sources []CatalogSource, work string, options CatalogOptions, diagnostic string) {
	mut denied := false
	compose_catalog_with(sources, work + '/refused', options) or { denied = err.msg().contains(diagnostic) }
	assert denied && !os.exists(work + '/refused'), diagnostic
	assert os.ls(work)!.all(!it.starts_with('.vinix-composition-'))
}

fn composition_no_space(_ string) !u64 { return 0 }
fn composition_corrupt(phase string, stage string) ! {
	if phase == 'ready' { os.write_file(stage + '/composition.json', 'changed')! }
}
fn composition_race(phase string, stage string) ! {
	if phase == 'ready' { os.mkdir(os.dir(stage) + '/refused')! }
}

fn test_composition_refuses_duplicate_packages_profile_ids_targets_space_and_changed_metadata() {
	work, sources := composition_fixture()!
	defer { os.rmdir_all(work) or {} }
	for invalid in [ []CatalogSource{}, [sources[0], sources[0]], [CatalogSource{ id: '../escape', catalog: sources[0].catalog }],
		[CatalogSource{ id: 'same', catalog: sources[0].catalog }, CatalogSource{ id: 'other', catalog: sources[0].catalog }] ] {
		composition_refused(invalid, work, CatalogOptions{}, '')
	}
	composition_refused(sources, work, CatalogOptions{ available_space: composition_no_space }, 'insufficient disk space')
	composition_refused(sources, work, CatalogOptions{ checkpoint: composition_corrupt }, 'changed before publication')
	valid := read_metadata(sources[1].catalog)!
	recipe := catalog_recipe(valid)!
	partial := CatalogRecipe{ format: 1, architectures: ['aarch64'], packages: recipe.packages.filter(it.recipe.manifest.architecture != 'x86_64') }
	os.write_file(sources[1].catalog, json2.encode(partial))!
	composition_refused(sources, work, CatalogOptions{}, 'same architectures')
	os.write_file(sources[1].catalog, valid.replace_once('"format":1', '"format":1,"unknown":1'))!
	composition_refused(sources, work, CatalogOptions{}, '')
	os.write_file(sources[1].catalog, valid)!
	mut raced := false
	compose_catalog_with(sources, work + '/refused', CatalogOptions{ checkpoint: composition_race }) or { raced = true }
	assert raced && os.ls(work)!.all(!it.starts_with('.vinix-composition-'))
	assert os.is_dir(work + '/refused') && os.ls(work + '/refused')!.len == 0
}

fn test_scoped_sources_refuse_traversal_wrong_targets_excessive_depth_and_ancestor_links() {
	assert catalog_source('profile/aarch64', 'aarch64') && catalog_source('parent/profile/shared', 'all')
	for source in ['/profile/aarch64', '../aarch64', 'profile//aarch64', 'profile/../aarch64', 'profile/x86_64', 'Profile/aarch64', 'a/b/c/d/e/f/g/h/aarch64'] {
		assert !catalog_source(source, 'aarch64'), source
	}
	work, sources := composition_fixture()!
	defer { os.rmdir_all(work) or {} }
	composed := compose_catalog(sources, work + '/lock')!
	for suffix in ['', '/aarch64'] {
		path := work + '/roots/alpha' + suffix
		os.rename(path, work + '/saved')!
		os.symlink(work + '/saved', path)!
		mut denied := false
		pack_catalog(composed.catalog, work + '/roots', work + '/linked') or { denied = err.msg().contains('ordinary directory') }
		assert denied && !os.exists(work + '/linked')
		os.rm(path)!; os.rename(work + '/saved', path)!
	}
	os.write_file(work + '/roots/alpha/aarch64/bin/app', 'changed pinned source')!
	mut changed := false
	pack_catalog(composed.catalog, work + '/roots', work + '/changed') or { changed = err.msg().contains('inventory differs') }
	assert changed && !os.exists(work + '/changed')
	assert os.ls(work)!.all(!it.starts_with('.vinix-catalog-'))
}

fn composition_replace_namespace(phase string, stage string) ! {
	if phase != 'created' { return }
	work := os.dir(stage)
	os.rename(work + '/roots/alpha', work + '/captured-alpha')!
	os.mkdir_all(work + '/roots/alpha/aarch64/bin')!
	os.write_file(work + '/roots/alpha/aarch64/bin/app', 'replacement namespace')!
}

fn test_scoped_roots_are_captured_before_import_even_when_the_profile_namespace_is_replaced() {
	work, sources := composition_fixture()!
	defer { os.rmdir_all(work) or {} }
	composed := compose_catalog(sources, work + '/lock')!
	assert catalog_build(composed.catalog, work + '/roots', work + '/captured', CatalogOptions{ checkpoint: composition_replace_namespace })!.package_count == 6
	manifest := json2.decode[Package](read_metadata(work + '/captured/manifests/alpha-aarch64-1.0.0.json')!)!
	assert read_metadata(work + '/captured/objects/' + manifest.files[0].sha256)! == 'alpha aarch64'
}

fn test_composition_bounds_profile_count_and_nested_source_depth() {
	work, sources := composition_fixture()!
	defer { os.rmdir_all(work) or {} }
	composition_refused([]CatalogSource{len: 65, init: sources[0]}, work, CatalogOptions{}, 'between 1 and 64')
	mut current := compose_catalog(sources, work + '/depth-2')!
	for depth in 3 .. 9 {
		current = compose_catalog([CatalogSource{ id: 'parent', catalog: current.catalog }], work + '/depth-' + depth.str())!
		assert catalog_recipe(read_metadata(current.catalog)!)!.packages.all(it.source.split('/').len == depth)
	}
	composition_refused([CatalogSource{ id: 'parent', catalog: current.catalog }], work, CatalogOptions{}, 'source must match')
}
