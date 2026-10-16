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

fn composition_single_target(source CatalogSource, architecture string) ! {
	recipe := catalog_recipe(read_metadata(source.catalog)!)!
	os.write_file(source.catalog, json2.encode(CatalogRecipe{ ...recipe, architectures: [architecture],
		packages: recipe.packages.filter(it.recipe.manifest.architecture in [architecture, 'all']) }))!
}

fn test_selected_composition_preserves_shared_packages_pins_disclosures_and_full_input_provenance() {
	work, sources := composition_fixture()!
	defer { os.rmdir_all(work) or {} }
	for architecture in ['aarch64', 'x86_64'] {
		one := compose_catalog_for(architecture, sources, work + '/' + architecture)!
		assert one.architectures == [architecture] && one.package_count == 4
		assert one.sources.map(it.id) == ['alpha', 'beta']
		mut reversed := sources.clone(); reversed.reverse_in_place()
		two := compose_catalog_for(architecture, reversed, work + '/' + architecture + '-reversed')!
		assert read_metadata(one.catalog)! == read_metadata(two.catalog)!
		assert read_metadata(one.directory + '/composition.json')! == read_metadata(two.directory + '/composition.json')!
		assert os.stat(one.directory)!.mode & 0o777 == 0o700
		selected := catalog_recipe(read_metadata(one.catalog)!)!
		assert selected.packages.all(it.recipe.manifest.architecture in [architecture, 'all'])
		for source in sources {
			input := catalog_recipe(read_metadata(source.catalog)!)!
			assert one.sources.filter(it.id == source.id)[0].catalog_sha256 == index_digest(json2.encode(input) + '\n')
			for item in input.packages.filter(it.recipe.manifest.architecture in [architecture, 'all']) {
				actual := selected.packages.filter(it.source == source.id + '/' + item.source && it.recipe.manifest.id == item.recipe.manifest.id)
				assert actual.len == 1 && actual[0].recipe == item.recipe
			}
		}
		workspace := work + '/workspace-' + architecture
		assert pack_catalog(one.catalog, work + '/roots', workspace)!.package_count == 4
		key := keygen(work + '/seed-' + architecture)!
		release := work + '/release-' + architecture
		publish_release(workspace, 'selected', work + '/seed-' + architecture, 1, time.now().unix() + 3600, release)!
		config := Config{ architecture: architecture, repositories: [Repository{ id: 'selected', url: 'file://' + release, public_key: key }],
			policy: Policy{ offline: true, reserve_bytes: 0 } }
		store := work + '/store-' + architecture
		refresh(config, store)!
		mut denied := false
		transact(config, store, 'install', ['alpha', 'beta'], TransactionOptions{}) or { denied = true }
		assert denied && read_state(store, architecture)!.generation == 0
		accepted := Config{ ...config, policy: Policy{ offline: true, reserve_bytes: 0, licenses: ['Vendor-EULA'], allow_firmware: true } }
		assert transact(accepted, store, 'install', ['alpha', 'beta'], TransactionOptions{})!.packages.len == 4
		assert read_metadata(store + '/current/apps/alpha/bin/app')! == 'alpha ' + architecture
		assert transact(accepted, store, 'remove', ['alpha', 'beta'], TransactionOptions{})!.packages.len == 0
		assert rollback(accepted, store)!.packages.len == 4
		// Input pins are still complete, but packing reads only selected roots.
		other := if architecture == 'aarch64' { 'x86_64' } else { 'aarch64' }
		for profile in ['alpha', 'beta'] { os.rename(work + '/roots/' + profile + '/' + other, work + '/' + profile + '-saved')! }
		assert pack_catalog(one.catalog, work + '/roots', work + '/only-' + architecture)!.package_count == 4
		for profile in ['alpha', 'beta'] { os.rename(work + '/' + profile + '-saved', work + '/roots/' + profile + '/' + other)! }
	}
	baseline := compose_catalog_for('aarch64', sources, work + '/baseline')!
	input := catalog_recipe(read_metadata(sources[0].catalog)!)!
	mut changed := []CatalogImport{}
	for item in input.packages { changed << if item.recipe.manifest.architecture == 'x86_64' {
		CatalogImport{ ...item, recipe: RootRecipe{ ...item.recipe, manifest: Package{ ...item.recipe.manifest, description: 'Reviewed omitted variant changed' } } }
	} else { item } }
	os.write_file(sources[0].catalog, json2.encode(CatalogRecipe{ ...input, packages: changed }))!
	updated := compose_catalog_for('aarch64', sources, work + '/updated')!
	assert baseline.catalog_sha256 == updated.catalog_sha256
	assert baseline.sources[0].catalog_sha256 != updated.sources[0].catalog_sha256
	assert read_metadata(baseline.directory + '/composition.json')! != read_metadata(updated.directory + '/composition.json')!
	for source in sources { os.write_file(source.catalog, ' \n' + read_metadata(source.catalog)! + '\n')! }
	formatted := compose_catalog_for('aarch64', sources, work + '/formatted')!
	assert read_metadata(updated.directory + '/composition.json')! == read_metadata(formatted.directory + '/composition.json')!
	println('COMPOSITION TARGET: both host selections preserve shared dependencies, manifests/pins/policy, signed offline maintenance and full-input provenance PASS')
}

fn test_selected_composition_combines_mixed_targets_without_changing_strict_composition() {
	work, sources := composition_fixture()!
	defer { os.rmdir_all(work) or {} }
	composition_single_target(sources[1], 'aarch64')!
	composition_refused(sources, work, CatalogOptions{}, 'same architectures')
	selected := compose_catalog_for('aarch64', sources, work + '/selected')!
	assert selected.package_count == 4 && selected.architectures == ['aarch64']
	mut unsupported := false
	compose_catalog_for('x86_64', sources, work + '/unsupported') or {
		unsupported = err.msg().contains('beta does not support requested architecture x86_64')
	}
	assert unsupported && !os.exists(work + '/unsupported')
	composition_single_target(sources[0], 'aarch64')!
	strict := compose_catalog(sources, work + '/strict')!
	projected := compose_catalog_for('aarch64', sources, work + '/projected')!
	assert read_metadata(strict.catalog)! == read_metadata(projected.catalog)!
	assert read_metadata(strict.directory + '/composition.json')! == read_metadata(projected.directory + '/composition.json')!
}

fn composition_target_refused(architecture string, sources []CatalogSource, work string, options CatalogOptions, diagnostic string) {
	mut denied := false
	compose_catalog_for_with(architecture, sources, work + '/refused', options) or { denied = err.msg().contains(diagnostic) }
	assert denied && !os.exists(work + '/refused'), diagnostic
	assert os.ls(work)!.all(!it.starts_with('.vinix-composition-'))
}

fn test_selected_composition_validates_full_inputs_before_omitting_other_variants() {
	work, sources := composition_fixture()!
	defer { os.rmdir_all(work) or {} }
	original := read_metadata(sources[0].catalog)!
	input := catalog_recipe(original)!
	for fault in ['missing-variant', 'source', 'dependency', 'unknown-field'] {
		mut imports := []CatalogImport{}
		for item in input.packages {
			if item.recipe.manifest.architecture != 'x86_64' { imports << item; continue }
			if fault == 'missing-variant' { continue }
			imports << if fault == 'source' { CatalogImport{ ...item, source: '../x86_64' } }
			else if fault == 'dependency' { CatalogImport{ ...item, recipe: RootRecipe{ ...item.recipe,
				manifest: Package{ ...item.recipe.manifest, dependencies: [Dependency{ id: 'absent-runtime' }] } } } }
			else { item }
		}
		text := json2.encode(CatalogRecipe{ ...input, packages: imports })
		os.write_file(sources[0].catalog, if fault == 'unknown-field' { text.replace_once('"architecture":"x86_64"', '"architecture":"x86_64","unknown":true') } else { text })!
		composition_target_refused('aarch64', sources, work, CatalogOptions{}, '')
	}
	os.write_file(sources[0].catalog, original)!
	// Shared identities must not be duplicated across selected profiles either.
	os.write_file(sources[1].catalog, read_metadata(sources[1].catalog)!.replace('beta-notice', 'alpha-notice'))!
	composition_target_refused('aarch64', sources, work, CatalogOptions{}, 'duplicate catalog package')
	println('COMPOSITION TARGET: incomplete, malformed, unsafe and unresolved omitted variants plus shared identity collisions refuse before publication PASS')
}

fn test_selected_composition_refuses_invalid_targets_space_staging_corruption_and_output_races() {
	work, sources := composition_fixture()!
	defer { os.rmdir_all(work) or {} }
	for architecture in ['', 'all', 'arm64', 'AARCH64', '../aarch64'] {
		composition_target_refused(architecture, sources, work, CatalogOptions{}, 'target must be aarch64 or x86_64')
	}
	composition_target_refused('aarch64', []CatalogSource{}, work, CatalogOptions{}, 'between 1 and 64')
	composition_target_refused('aarch64', []CatalogSource{len: 65, init: sources[0]}, work, CatalogOptions{}, 'between 1 and 64')
	composition_target_refused('aarch64', [sources[0], sources[0]], work, CatalogOptions{}, 'distinct valid profile IDs')
	composition_target_refused('aarch64', [CatalogSource{ id: '../escape', catalog: sources[0].catalog }], work, CatalogOptions{}, 'distinct valid profile IDs')
	composition_target_refused('aarch64', sources, work, CatalogOptions{ available_space: composition_no_space }, 'insufficient disk space')
	composition_target_refused('aarch64', sources, work, CatalogOptions{ checkpoint: composition_corrupt }, 'changed before publication')
	mut raced := false
	compose_catalog_for_with('aarch64', sources, work + '/refused', CatalogOptions{ checkpoint: composition_race }) or { raced = true }
	assert raced && os.is_dir(work + '/refused') && os.ls(work + '/refused')!.len == 0
	assert os.ls(work)!.all(!it.starts_with('.vinix-composition-'))
	os.rmdir(work + '/refused')!
	assert compose_catalog_for('aarch64', sources, work + '/refused')!.package_count == 4
}

fn test_selected_composition_cli_matches_api_with_literal_paths_and_refuses_invalid_requests() {
	cli := os.getenv('VINIX_PACKAGE_COMPOSITION_CLI'); if cli == '' { return }
	work, sources := composition_fixture()!
	defer { os.rmdir_all(work) or {} }
	composition_single_target(sources[1], 'aarch64')!
	literal := work + '/catalog ; $literal.json'
	os.rename(sources[1].catalog, literal)!
	pairs := ['alpha', sources[0].catalog, 'beta', literal]
	api := compose_catalog_for('aarch64', [sources[0], CatalogSource{ id: 'beta', catalog: literal }], work + '/api')!
	destination := work + '/lock ; $literal'
	result := os.exec([cli, 'compose-catalog-for', 'aarch64', destination, ...pairs])
	assert result.exit_code == 0, result.output
	actual := json2.decode[CompositionInfo](result.output)!
	assert actual.catalog_sha256 == api.catalog_sha256 && actual.architectures == ['aarch64'] && actual.sources == api.sources
	assert read_metadata(destination + '/composition.json')! == read_metadata(api.directory + '/composition.json')!
	for arguments in [ []string{}, ['aarch64'], ['aarch64', work + '/bad'], ['aarch64', work + '/bad', 'alpha'],
		['all', work + '/bad', ...pairs], ['x86_64', work + '/bad', ...pairs],
		['aarch64', destination, ...pairs], ['aarch64', work + '/bad', ...pairs, 'extra'] ] {
		refused := os.exec([cli, 'compose-catalog-for', ...arguments])
		assert refused.exit_code != 0 && refused.output.trim_space() != '' && !refused.output.contains('V panic:'), refused.output
		assert !os.exists(work + '/bad')
	}
	assert os.exec([cli, 'compose-catalog', work + '/bad', ...pairs]).exit_code != 0 && !os.exists(work + '/bad')
	println('COMPOSITION TARGET: explicit CLI/API equivalence, literal paths, unsupported host, argument counts and existing-output refusals PASS')
}
