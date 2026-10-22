// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time

fn catalog_fixture() !(string, CatalogRecipe) {
	work := os.real_path(os.temp_dir()) + '/vinix-catalog-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(work + '/roots/shared')!
	os.write_file(work + '/roots/shared/COPYING', 'shared license document')!
	mut items := []CatalogImport{}
	for arch in ['aarch64', 'x86_64'] {
		root := work + '/roots/' + arch
		os.mkdir_all(root + '/bin')!
		os.mkdir_all(root + '/lib')!
		os.write_file(root + '/bin/application', 'application ' + arch)!
		os.chmod(root + '/bin/application', 0o755)!
		os.write_file(root + '/bin/runner', 'isolated runner ' + arch)!
		os.chmod(root + '/bin/runner', 0o755)!
		os.symlink('/bin/runner', root + '/lib/runner-alias')!
		for id in ['app', 'runtime'] {
			source := if id == 'app' { 'bin/application' } else { 'bin/runner' }
			path := if id == 'app' { 'bin/application' } else { 'bin/runner' }
			p := Package{ id: id, version: '1.0.0', architecture: arch, name: id,
				license: 'MIT', kind: if id == 'app' { 'linux' } else { 'runtime' },
				runtime: if id == 'app' { 'runtime' } else { '' },
				entrypoint: if id == 'app' { 'bin/runner' } else { '' },
				arguments: if id == 'app' { ['@APP@/bin/application'] } else { []string{} },
				dependencies: if id == 'app' { [Dependency{ id: 'runtime', before: '2.0.0' }, Dependency{ id: 'license' }] } else { []Dependency{} },
				files: [Payload{ path: path, bytes: os.file_size(root + '/' + source),
					sha256: hash_file(root + '/' + source)!, executable: true }] }
			items << CatalogImport{ source: arch, recipe: RootRecipe{ manifest: p,
				entries: [RootEntry{ source: if id == 'app' { source } else { 'lib/runner-alias' }, path: path }] } }
		}
	}
	items << CatalogImport{ source: 'shared', recipe: RootRecipe{
		manifest: Package{ id: 'license', version: '1.0.0', architecture: 'all', name: 'License',
			kind: 'data', license: 'Vendor-EULA', proprietary: true, firmware: true,
			files: [Payload{ path: 'COPYING', bytes: os.file_size(work + '/roots/shared/COPYING'),
				sha256: hash_file(work + '/roots/shared/COPYING')! }] },
		entries: [RootEntry{ source: 'COPYING', path: 'COPYING' }] } }
	recipe := CatalogRecipe{ format: 1, architectures: ['x86_64', 'aarch64'], packages: items }
	os.write_file(work + '/catalog.json', json2.encode(recipe))!
	return work, recipe
}

fn catalog_refusal(work string, destination string, diagnostic string) {
	mut refused := false
	pack_catalog(work + '/catalog.json', work + '/roots', work + '/' + destination) or {
		refused = err.msg().contains(diagnostic)
	}
	assert refused && !os.exists(work + '/' + destination), diagnostic
	names := os.ls(work) or { panic(err) }
	defer { unsafe { names.free() } }
	assert names.all(!it.starts_with('.vinix-catalog-'))
}

fn test_catalog_pinned_import_reproducible_release_and_offline_install_on_both_targets() {
	work, recipe := catalog_fixture()!
	defer { os.rmdir_all(work) or {} }
	first := pack_catalog(work + '/catalog.json', work + '/roots', work + '/first')!
	assert first.format == 1 && first.package_count == 5 && first.object_count == 5
	assert first.architectures == ['aarch64', 'x86_64']
	assert os.stat(work + '/first')!.mode & 0o777 == 0o700
	mut reversed := recipe.packages.clone()
	reversed.reverse_in_place()
	os.write_file(work + '/catalog.json', json2.encode(CatalogRecipe{ ...recipe, architectures: ['aarch64', 'x86_64'], packages: reversed }))!
	second := pack_catalog(work + '/catalog.json', work + '/roots', work + '/second')!
	assert first.catalog_sha256 == second.catalog_sha256
	assert read_metadata(work + '/first/catalog.json')! == read_metadata(work + '/second/catalog.json')!
	for name in os.ls(work + '/first/manifests')! {
		assert read_metadata(work + '/first/manifests/' + name)! == read_metadata(work + '/second/manifests/' + name)!
	}
	key := keygen(work + '/seed')!
	expires := time.now().unix() + 3600
	one := publish_release(work + '/first', 'fixture', work + '/seed', 1, expires, work + '/release-one')!
	two := publish_release(work + '/second', 'fixture', work + '/seed', 1, expires, work + '/release-two')!
	assert one.index_sha256 == two.index_sha256
	assert read_metadata(work + '/release-one/index.sig')! == read_metadata(work + '/release-two/index.sig')!
	assert os.ls(work + '/release-one')!.len == 3
	for arch in ['aarch64', 'x86_64'] {
		store := work + '/store-' + arch
		base := Config{ architecture: arch, repositories: [Repository{ id: 'fixture', url: 'file://' + work + '/release-one', public_key: key }],
			policy: Policy{ offline: true, reserve_bytes: 0 } }
		refresh(base, store)!
		mut denied := false
		transact(base, store, 'install', ['app'], TransactionOptions{}) or { denied = err.msg().contains('license') || err.msg().contains('firmware') }
		assert denied, 'catalog construction must not accept licenses for consumers'
		accepted := Config{ ...base, policy: Policy{ offline: true, reserve_bytes: 0, licenses: ['Vendor-EULA'], allow_firmware: true } }
		state := transact(accepted, store, 'install', ['app'], TransactionOptions{})!
		assert state.packages.len == 3 && state.packages.any(it.package.id == 'runtime')
		assert read_metadata(store + '/generations/1/apps/app/bin/application')! == 'application ' + arch
		assert state.packages.filter(it.package.id == 'license')[0].package.proprietary
		removed := transact(accepted, store, 'remove', ['app'], TransactionOptions{})!
		assert removed.packages.len == 0
	}
}

fn test_catalog_refuses_incomplete_targets_duplicate_identities_and_missing_runtime_closures() {
	work, recipe := catalog_fixture()!
	defer { os.rmdir_all(work) or {} }
	for architectures in [[]string{}, ['aarch64', 'aarch64'], ['arm64']] {
		os.write_file(work + '/catalog.json', json2.encode(CatalogRecipe{ ...recipe, architectures: architectures }))!
		catalog_refusal(work, 'invalid-targets', '')
	}
	for items in [recipe.packages.filter(it.recipe.manifest.id != 'app' || it.source != 'x86_64'),
		[...recipe.packages, recipe.packages[0]],
		recipe.packages.filter(it.recipe.manifest.id != 'runtime')] {
		os.write_file(work + '/catalog.json', json2.encode(CatalogRecipe{ ...recipe, packages: items }))!
		catalog_refusal(work, 'invalid', if items.len == 6 { 'duplicate catalog' } else if items.len == 3 { 'dependency closure' } else { 'coverage' })
	}
	mut wrong := recipe.packages.clone()
	wrong[0] = CatalogImport{ ...wrong[0], source: 'x86_64' }
	os.write_file(work + '/catalog.json', json2.encode(CatalogRecipe{ ...recipe, packages: wrong }))!
	catalog_refusal(work, 'mixed-root', 'source must match')
}

fn test_catalog_refuses_changed_bytes_modes_added_files_and_unsafe_source_roots_atomically() {
	work, recipe := catalog_fixture()!
	defer { os.rmdir_all(work) or {} }
	file := work + '/roots/aarch64/bin/application'
	original := read_metadata(file)!
	os.write_file(file, original.replace('application', 'Application'))!
	catalog_refusal(work, 'changed', 'payload inventory differs')
	os.write_file(file, original)!
	os.chmod(file, 0o644)!
	catalog_refusal(work, 'mode', 'payload inventory differs')
	os.chmod(file, 0o755)!
	os.mkdir(work + '/roots/aarch64/selected')!
	os.cp(file, work + '/roots/aarch64/selected/application')!
	os.chmod(work + '/roots/aarch64/selected/application', 0o755)!
	os.write_file(work + '/roots/aarch64/selected/unexpected', 'unexpected payload')!
	mut expanded := recipe.packages.clone()
	expanded[0] = CatalogImport{ ...expanded[0], recipe: RootRecipe{ ...expanded[0].recipe,
		entries: [RootEntry{ source: 'selected', path: 'bin' }] } }
	os.write_file(work + '/catalog.json', json2.encode(CatalogRecipe{ ...recipe, packages: expanded }))!
	catalog_refusal(work, 'extra-file', 'payload inventory differs')
	os.write_file(work + '/catalog.json', json2.encode(recipe))!
	os.rename(work + '/roots/aarch64', work + '/saved-root')!
	os.symlink(work + '/saved-root', work + '/roots/aarch64')!
	catalog_refusal(work, 'source-link', 'ordinary directory')
	os.rm(work + '/roots/aarch64')!
	os.rename(work + '/saved-root', work + '/roots/aarch64')!
	os.symlink(work + '/roots', work + '/root-alias')!
	mut refused := false
	pack_catalog(work + '/catalog.json', work + '/root-alias', work + '/top-link') or { refused = err.msg().contains('ordinary directory') }
	assert refused && !os.exists(work + '/top-link')
	os.mkdir(work + '/occupied')!
	os.write_file(work + '/occupied/keep', 'retained')!
	mut occupied_refused := false
	pack_catalog(work + '/catalog.json', work + '/roots', work + '/occupied') or { occupied_refused = err.msg().contains('must be new') }
	assert occupied_refused && read_metadata(work + '/occupied/keep')! == 'retained'
}

fn catalog_no_space(_ string) !u64 { return 0 }

fn catalog_corrupt_ready(phase string, directory string) ! {
	if phase != 'ready' { return }
	name := os.ls(directory + '/objects')![0]
	os.write_file(directory + '/objects/' + name, 'corrupted')!
}

fn catalog_race_ready(phase string, directory string) ! {
	if phase == 'ready' { os.mkdir(os.dir(directory) + '/raced')! }
}

fn catalog_replace_source_path(phase string, directory string) ! {
	if phase != 'created' { return }
	work := os.dir(directory)
	os.rename(work + '/roots/aarch64', work + '/captured-root')!
	os.mkdir_all(work + '/roots/aarch64/bin')!
	os.write_file(work + '/roots/aarch64/bin/application', 'replacement namespace')!
}

fn test_catalog_captures_source_roots_before_importing_any_packages() {
	work, _ := catalog_fixture()!
	defer { os.rmdir_all(work) or {} }
	info := catalog_build(work + '/catalog.json', work + '/roots', work + '/captured',
		CatalogOptions{ checkpoint: catalog_replace_source_path })!
	assert info.package_count == 5
	assert read_metadata(work + '/roots/aarch64/bin/application')! == 'replacement namespace'
	manifest := json2.decode[Package](read_metadata(work + '/captured/manifests/app-aarch64-1.0.0.json')!)!
	assert read_metadata(work + '/captured/objects/' + manifest.files[0].sha256)! == 'application aarch64'
}

fn test_catalog_space_integrity_and_destination_races_leave_no_visible_partial_workspace() {
	work, _ := catalog_fixture()!
	defer { os.rmdir_all(work) or {} }
	for options in [CatalogOptions{ available_space: catalog_no_space }, CatalogOptions{ checkpoint: catalog_corrupt_ready }] {
		mut refused := false
		catalog_build(work + '/catalog.json', work + '/roots', work + '/failed', options) or {
			refused = err.msg().contains('insufficient disk space') || err.msg().contains('object changed')
		}
		assert refused && !os.exists(work + '/failed')
		assert os.ls(work)!.all(!it.starts_with('.vinix-catalog-'))
	}
	mut refused := false
	catalog_build(work + '/catalog.json', work + '/roots', work + '/raced', CatalogOptions{ checkpoint: catalog_race_ready }) or { refused = true }
	assert refused && os.is_dir(work + '/raced') && os.ls(work + '/raced')!.len == 0
	assert os.ls(work)!.all(!it.starts_with('.vinix-catalog-'))
}

fn test_catalog_requires_explicit_pins_and_license_flags_and_refuses_unknown_duplicate_escaped_keys() {
	work, recipe := catalog_fixture()!
	defer { os.rmdir_all(work) or {} }
	valid := json2.encode(recipe)
	for text in [valid.replace_once('"format":1', '"format":1,"formatt":1'),
		valid.replace_once('"source":"aarch64"', '"source":"aarch64","sour\\u0063e":"aarch64"'),
		valid.replace_once('"proprietary":false,', ''), valid.replace_once('"firmware":false,', ''),
		valid.replace_once(',"executable":true', ''),
		valid.replace_once('"sha256":', '"sha25":')] {
		assert text != valid
		os.write_file(work + '/catalog.json', text)!
		catalog_refusal(work, 'schema', '')
	}
}

fn test_catalog_reply_close_leaves_published_workspace_and_other_results_usable() {
	work, _ := catalog_fixture()!
	defer { os.rmdir_all(work) or {} }
	mut first := pack_catalog(work + '/catalog.json', work + '/roots', work + '/owned-first')!
	mut second := pack_catalog(work + '/catalog.json', work + '/roots', work + '/owned-second')!
	digest := first.catalog_sha256.clone()
	defer { unsafe { digest.free() } }
	first.close(); first.close()
	assert first.directory == '' && first.architectures.len == 0
	assert second.directory == work + '/owned-second' && second.architectures == ['aarch64', 'x86_64']
	assert second.package_count == 5 && second.object_count == 5 && second.catalog_sha256 == digest
	second.close(); second.close()
	assert index_digest(read_metadata(work + '/owned-first/catalog.json')!) == digest
	assert index_digest(read_metadata(work + '/owned-second/catalog.json')!) == digest
	assert os.ls(work + '/owned-first/manifests')!.len == 5 && os.ls(work + '/owned-second/objects')!.len == 5
	println('CATALOG WORKSPACE owned replies close independently without removing published manifests, objects or catalog PASS')
}
