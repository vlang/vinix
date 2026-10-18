// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time
import tools.packages.pkgprotocol

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32

fn view_package(id string, version string, kind string) Package {
	p := Package{
		id:           id
		name:         id
		description:  'View fixture'
		version:      version
		architecture: if kind == 'data' { 'all' } else { 'aarch64' }
		license:      'MIT'
		kind:         kind
		entrypoint:   if kind == 'data' { '' } else { 'bin/runner' }
		files:        [Payload{ path: 'bin/runner', sha256: '01'.repeat(32), bytes: 1, executable: kind != 'data' }]
	}
	p.validate() or { panic(err) }
	return p
}

fn view_installed(p Package) Installed {
	return Installed{ package: p, repository: 'fixture', public_key: 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a', sequence: 1 }
}

fn view_configuration() Config {
	return Config{
		architecture: 'aarch64'
		repositories: [Repository{
			id:         'fixture'
			url:        'https://example.invalid'
			public_key: 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a'
		}]
	}
}

fn view_row(view SoftwareView, id string) SoftwareRow {
	return view.rows.filter(it.id == id)[0]
}

fn test_updates_expose_resolved_runtime_data_and_new_dependencies() {
	config := view_configuration()
	runtime := view_package('runtime', '1.0.0', 'runtime')
	assets := view_package('assets', '1.0.0', 'data')
	app := Package{
		...view_package('app', '1.0.0', 'native')
		kind:         'linux'
		runtime:      'runtime'
		dependencies: [Dependency{ id: 'runtime', before: '2.0.0' }, Dependency{ id: 'assets' }]
	}
	app.validate()!
	current := State{
		architecture: 'aarch64'
		generation:   1
		requested:    ['app']
		packages:     [view_installed(app), view_installed(runtime), view_installed(assets)]
	}
	new_runtime := Package{ ...runtime, version: '1.1.0', dependencies: [Dependency{ id: 'extras' }], permissions: ['process'] }
	catalog := Catalog{
		packages: [
			view_installed(Package{ ...app, version: '2.0.0', dependencies: [
				Dependency{ id: 'missing' },
				Dependency{ id: 'runtime' },
			] }),
			view_installed(app),
			view_installed(runtime),
			view_installed(new_runtime),
			view_installed(Package{ ...runtime, version: '2.0.0' }),
			view_installed(Package{ ...runtime, version: '9.0.0', architecture: 'x86_64' }),
			view_installed(Package{ ...assets, version: '2.0.0' }),
			view_installed(view_package('extras', '1.0.0', 'data')),
			view_installed(view_package('unrelated-runtime', '1.0.0', 'runtime')),
			view_installed(view_package('unrelated-data', '1.0.0', 'data')),
		]
	}
	view := catalog_view(config, catalog, current, '')!
	assert view.catalog_error == '' && view.update_error == '' && view.generation == 1
	assert view.rows.map(it.id) == ['app', 'assets', 'extras', 'runtime']
	assert view_row(view, 'app').version == '1.0.0' && !view_row(view, 'app').updatable
	row := view_row(view, 'runtime')
	assert row.updatable && row.update_action == 'update' && row.version == '1.1.0'
	assert row.installed_version == '1.0.0' && row.kind == 'runtime' && row.permissions == ['process']
	assert row.installed_kind == 'runtime' && row.installed_permissions.len == 0
	assert view_row(view, 'assets').updatable && view_row(view, 'assets').architecture == 'all'
	extra := view_row(view, 'extras')
	assert extra.updatable && extra.update_action == 'install' && extra.installed_version == '' && !extra.requested
}

fn test_launch_presentation_retains_installed_metadata_when_an_update_changes_kind_name_and_permissions() {
	old := Package{ ...view_package('app', '1.0.0', 'native'), name: 'Installed app', permissions: [] }
	new := Package{ ...view_package('app', '2.0.0', 'data'), name: 'Planned assets', permissions: ['files'] }
	current := State{ architecture: 'aarch64', generation: 1, requested: ['app'], packages: [view_installed(old)] }
	view := catalog_view(view_configuration(), Catalog{ packages: [view_installed(old), view_installed(new)] }, current, '')!
	row := view_row(view, 'app')
	assert row.updatable && row.name == 'Planned assets' && row.kind == 'data' && row.permissions == ['files']
	assert row.installed_name == 'Installed app' && row.installed_kind == 'native' && row.installed_permissions.len == 0
}

fn test_software_provenance_retains_installation_identity_through_preview_revocation_activation_and_rollback() {
	for architecture in ['aarch64', 'x86_64']! {
		base := view_configuration()
		replacement := Repository{ ...base.repositories[0], public_key: '3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c' }
		config := Config{ ...base, architecture: architecture, repositories: [replacement] }
		assets := view_installed(view_package('assets', '1.0.0', 'data'))
		old := view_installed(Package{ ...view_package('app', '1.0.0', 'native'), architecture: architecture, dependencies: [Dependency{ id: 'assets', minimum: '1.0.0', before: '2.0.0' }] })
		incoming := Installed{ ...old, package: Package{ ...old.package, version: '2.0.0', dependencies: [] }, repository: replacement.id, public_key: replacement.public_key }
		fresh := Installed{ ...incoming, package: Package{ ...incoming.package, id: 'fresh' } }
		current := State{ architecture: architecture, generation: 1, requested: ['app'], packages: [old, assets] }
		catalog := Catalog{ packages: [incoming, fresh] }
		view := catalog_view(config, catalog, current, '')!
		row := view_row(view, 'app')
		assert row.version == '2.0.0' && row.installed_version == '1.0.0' && row.update_action == 'update'
		assert row.installed_dependencies_known && row.installed_dependencies == old.package.dependencies
		assert row.repository == replacement.id && row.public_key == replacement.public_key
		assert row.installed_repository == old.repository && row.installed_public_key == old.public_key
		mut wire := pkgprotocol.decode_software_view(json2.encode(view))!
		assert wire.rows.filter(it.id == 'app')[0].installed_public_key == old.public_key
		assert wire.rows.filter(it.id == 'app')[0].public_key == replacement.public_key
		assert wire.rows.filter(it.id == 'app')[0].installed_dependencies[0].minimum == '1.0.0'
		assert wire.rows.filter(it.id == 'app')[0].installed_dependencies[0].before == '2.0.0'
		wire.close()
		assert row.diagnostic.contains('revoked')
		removed := view_row(view, 'assets')
		assert removed.update_action == 'remove' && removed.installed_repository == assets.repository && removed.installed_public_key == assets.public_key
		assert view_row(view, 'fresh').installed_repository == '' && view_row(view, 'fresh').installed_public_key == ''
		assert !view_row(view, 'fresh').installed_dependencies_known && view_row(view, 'fresh').installed_dependencies.len == 0
		revoked := catalog_view(Config{ ...config, repositories: [] }, Catalog{}, current, 'publisher revoked')!
		assert view_row(revoked, 'app').installed_repository == old.repository && view_row(revoked, 'app').installed_public_key == old.public_key
		assert view_row(revoked, 'app').diagnostic.contains('revoked') && !view_row(revoked, 'app').updatable
		assert view_row(revoked, 'app').installed_dependencies == old.package.dependencies
		activated := catalog_view(config, catalog, State{ ...current, generation: 2, packages: [incoming] }, '')!
		assert view_row(activated, 'app').installed_repository == incoming.repository && view_row(activated, 'app').installed_public_key == incoming.public_key
		assert view_row(activated, 'app').installed_dependencies_known && view_row(activated, 'app').installed_dependencies.len == 0
		restored := catalog_view(config, catalog, State{ ...current, generation: 3 }, '')!
		assert view_row(restored, 'app').installed_repository == old.repository && view_row(restored, 'app').installed_public_key == old.public_key
		assert view_row(restored, 'app').installed_dependencies == old.package.dependencies
		unavailable := catalog_view(config, Catalog{}, current, 'catalog unavailable')!
		assert view_row(unavailable, 'app').installed_repository == old.repository && view_row(unavailable, 'app').installed_public_key == old.public_key
	}
	println('SOFTWARE PROVENANCE both hosts retain installed publisher across previews, removal, revocation, activation, restored generations and unavailable catalogs PASS')
	println('SOFTWARE DEPENDENCIES both hosts retain installed requirements across update previews, removals, revocation, activation and rollback PASS')
}

fn test_updates_disclose_dependency_removals_and_retain_explicit_roots() {
	config := view_configuration()
	assets := view_installed(view_package('assets', '1.0.0', 'data'))
	app := view_installed(Package{ ...view_package('app', '1.0.0', 'native'), dependencies: [Dependency{ id: 'assets' }] })
	new_app := view_installed(view_package('app', '2.0.0', 'native'))
	current := State{ architecture: 'aarch64', generation: 1, requested: ['app'], packages: [
		app,
		assets,
	] }
	catalog := Catalog{ packages: [app, assets, new_app] }
	view := catalog_view(config, catalog, current, '')!
	removed := view_row(view, 'assets')
	assert removed.updatable && removed.update_action == 'remove'
	assert removed.installed_version == '1.0.0' && removed.version == '1.0.0'
	retained := catalog_view(config, catalog, State{ ...current, requested: ['app', 'assets'] }, '')!
	assert !view_row(retained, 'assets').updatable && view_row(retained, 'assets').requested
}

fn test_update_flags_cover_manifest_key_changes_and_policy_downgrades() {
	config := view_configuration()
	app := view_installed(view_package('app', '2.0.0', 'native'))
	current := State{ architecture: 'aarch64', generation: 1, requested: ['app'], packages: [app] }
	// Signed expiry/sequence renewal alone does not advertise an application update.
	renewed := Installed{ ...app, sequence: 2 }
	assert !catalog_view(config, Catalog{ packages: [renewed] }, current, '')!.rows[0].updatable
	changed := Installed{ ...app, package: Package{ ...app.package, permissions: ['network'] } }
	assert catalog_view(config, Catalog{ packages: [changed] }, current, '')!.rows[0].update_action == 'update'
	new_key := '3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c'
	rotated := Config{ ...config, repositories: [Repository{ ...config.repositories[0], public_key: new_key }] }
	key_change := Installed{ ...app, public_key: new_key }
	assert catalog_view(rotated, Catalog{ packages: [key_change] }, current, '')!.rows[0].updatable
	pinned := Config{ ...config, policy: Policy{ pins: [Dependency{ id: 'app', before: '2.0.0' }] } }
	older := view_installed(view_package('app', '1.0.0', 'native'))
	view := catalog_view(pinned, Catalog{ packages: [app, older] }, current, '')!
	assert view.rows[0].version == '1.0.0' && view.rows[0].installed_version == '2.0.0'
	assert view.rows[0].updatable && view.rows[0].update_action == 'update'
}

fn test_failed_resolution_reports_reason_without_advertising_other_publishers() {
	config := view_configuration()
	runtime := view_installed(Package{ ...view_package('runtime', '1.0.0', 'runtime'), permissions: ['process'] })
	app := view_installed(Package{ ...view_package('app', '1.0.0', 'native'), dependencies: [Dependency{ id: 'runtime' }] })
	current := State{ architecture: 'aarch64', generation: 1, requested: ['app'], packages: [
		app,
		runtime,
	] }
	blocked := Config{ ...config, policy: Policy{ permissions: ['files'] } }
	view := catalog_view(blocked, Catalog{ packages: [app, runtime] }, current, '')!
	assert view.update_error.contains('permissions blocked')
	assert view.rows.all(!it.updatable && it.version == '1.0.0')
	assert view_row(view, 'runtime').diagnostic.contains('permissions blocked')
	assert view_row(view, 'app').diagnostic == view_row(view, 'runtime').diagnostic
	replacement := Installed{
		...app
		repository: 'replacement'
		public_key: '02'.repeat(32)
		package:    Package{ ...app.package, version: '3.0.0' }
	}
	revoked := Config{
		...config
		repositories: [Repository{
			id:         'replacement'
			url:        'https://example.invalid'
			public_key: replacement.public_key
		}]
	}
	adoption := catalog_view(revoked, Catalog{ packages: [replacement] }, current, '')!
	assert adoption.update_error != '' && adoption.rows.all(!it.updatable)
	assert view_row(adoption, 'app').repository == 'fixture' && view_row(adoption, 'app').version == '1.0.0'
	assert view_row(adoption, 'app').diagnostic.contains('revoked')
	expired := catalog_view(config, Catalog{}, current, 'expired index')!
	assert expired.catalog_error == 'expired index' && expired.rows.len == 2 && expired.rows.all(!it.updatable)
}

fn test_new_catalog_applications_prefer_allowed_versions_and_host_architecture() {
	config := view_configuration()
	app := view_installed(view_package('app', '1.0.0', 'native'))
	proprietary := Installed{ ...app, package: Package{ ...app.package, version: '2.0.0', proprietary: true, license: 'Vendor-EULA' } }
	wrong_arch := Installed{ ...app, package: Package{ ...app.package, version: '9.0.0', architecture: 'x86_64' } }
	for candidates in [[app, proprietary, wrong_arch], [wrong_arch, proprietary, app]] {
		view := catalog_view(config, Catalog{ packages: candidates }, State{ architecture: 'aarch64' }, '')!
		assert view.rows.len == 1 && view.rows[0].version == '1.0.0' && view.rows[0].diagnostic == ''
	}
	blocked := catalog_view(config, Catalog{ packages: [proprietary] }, State{ architecture: 'aarch64' }, '')!
	assert blocked.rows[0].diagnostic.contains('accept license')
}

fn test_disk_view_is_read_only_and_uses_package_reader_lock() {
	root := os.real_path(os.temp_dir()) + '/vinix-software-view-' + os.getpid().str()
	os.mkdir_all(root + '/etc/vinix-packages')!
	defer { os.rmdir_all(root) or {} }
	os.write_file(root + '/etc/vinix-packages/config.json', json2.encode(Config{ architecture: 'aarch64', policy: Policy{ reserve_bytes: 0 } }))!
	assert software_view(root, false)!.catalog_error.contains('repo-enroll')
	assert !os.exists(state_directory(root))
	os.mkdir_all(root + '/source/bin')!
	os.write_file(root + '/source/bin/runner', 'signed view fixture\n')!
	os.chmod(root + '/source/bin/runner', 0o755)!
	key := keygen(root + '/seed')!
	app := Package{ ...view_package('app', '1.0.0', 'native'), dependencies: [Dependency{ id: 'runtime' }] }
	runtime := view_package('runtime', '1.0.0', 'runtime')
	for p in [app, runtime] {
		os.write_file(root + '/manifest.json', json2.encode(p))!
		pack(root + '/manifest.json', root + '/source', root + '/repository')!
	}
	publish(root + '/repository', 'fixture', root + '/seed', 1, time.now().unix() + 3600)!
	config := enroll_repository(root, Repository{ id: 'fixture', url: 'file://' + root + '/repository', public_key: key }, false)!
	directory := state_directory(root)
	refresh(config, directory)!
	transact(config, directory, 'install', ['app'], TransactionOptions{})!
	os.write_file(root + '/source/bin/runner', 'new signed view fixture\n')!
	os.write_file(root + '/manifest.json', json2.encode(Package{ ...runtime, version: '2.0.0' }))!
	pack(root + '/manifest.json', root + '/source', root + '/repository')!
	publish(root + '/repository', 'fixture', root + '/seed', 2, time.now().unix() + 3600)!
	refresh(config, directory)!
	objects := os.ls(directory + '/objects')!
	generations := os.ls(directory + '/generations')!
	state := read_state(directory, 'aarch64')!
	view := software_view(root, true)!
	assert view.generation == state.generation && view.offline && !load_config(root)!.policy.offline
	assert view.rows.filter(it.updatable).map(it.id) == ['runtime']
	assert view_row(view, 'runtime').version == '2.0.0'
	assert view_row(view, 'runtime').installed_repository == 'fixture' && view_row(view, 'runtime').installed_public_key == key
	assert view_row(view, 'app').installed_repository == 'fixture' && view_row(view, 'app').installed_public_key == key
	assert view_row(view, 'app').installed_dependencies_known && view_row(view, 'app').installed_dependencies == app.dependencies
	mut wire := pkgprotocol.decode_software_view(json2.encode(view))!
	assert wire.rows.filter(it.id == 'app')[0].installed_dependencies[0].id == 'runtime'
	wire.close()
	assert os.ls(directory + '/objects')! == objects && os.ls(directory + '/generations')! == generations
	assert read_state(directory, 'aarch64')! == state
	guard := acquire(directory)!
	if _ := software_view(root, false) {
		assert false, 'view ignored package writer lock'
	}
	guard.release()
}


fn diagnostic_fixture() (Config, State) {
	config := view_configuration()
	app := view_installed(Package{ ...view_package('app', '1.0.0', 'native'), dependencies: [Dependency{ id: 'bridge' }] })
	bridge := view_installed(Package{ ...view_package('bridge', '1.0.0', 'data'), dependencies: [Dependency{ id: 'runtime' }] })
	runtime := Installed{ ...view_installed(Package{ ...view_package('runtime', '1.0.0', 'runtime'), dependencies: [Dependency{ id: 'bridge' }] }), repository: 'legacy' }
	return Config{ ...config, repositories: [config.repositories[0], Repository{ ...config.repositories[0], id: 'legacy' }] },
		State{ architecture: 'aarch64', generation: 1, requested: ['app', 'independent'], packages: [app, bridge, runtime,
			view_installed(view_package('independent', '1.0.0', 'native'))] }
}

fn test_diagnostics_propagate_trust_failures_through_cycles_without_blocking_other_apps() {
	config, state := diagnostic_fixture()
	for key in ['01' + '00'.repeat(31), '95' + '99'.repeat(31), '02' + '00'.repeat(31)] {
		packages := state.packages.map(if it.repository == 'legacy' { Installed{ ...it, public_key: key } } else { it })
		invalid := Config{ ...config, repositories: [config.repositories[0], Repository{ ...config.repositories[1], public_key: key }] }
		messages := package_diagnostics(invalid, packages)
		assert messages['runtime'].contains('runtime: repository legacy has an invalid publisher key')
		assert messages['runtime'].contains('administrator') && messages['runtime'].contains('uninstall remains available')
		assert messages['app'] == messages['runtime'] && messages['bridge'] == messages['runtime']
		assert messages['independent'] == ''
		close_package_diagnostics(messages)
		// No global key cache: a subsequent trust/configuration read must differ.
		revoked := package_diagnostics(Config{ ...invalid, repositories: [config.repositories[0]] }, packages)
		assert revoked['app'].contains('runtime: publisher key has been revoked')
		close_package_diagnostics(revoked)
	}
	valid := package_diagnostics(config, state.packages)
	assert valid.values().all(it == '')
	close_package_diagnostics(valid)
}

fn test_software_keeps_installed_dependency_blocker_until_an_update_activates() {
	config, state := diagnostic_fixture()
	revoked := Config{ ...config, repositories: [config.repositories[0]] }
	// This update removes the old runtime/bridge. It does not repair the launch
	// snapshot currently used by Run, even when its preview resolves successfully.
	updated := view_installed(view_package('app', '2.0.0', 'native'))
	catalog := Catalog{ packages: [updated, state.packages[3]] }
	view := catalog_view(revoked, catalog, state, '')!
	assert view.update_error == '' && view_row(view, 'app').updatable
	assert view_row(view, 'app').version == '2.0.0' && view_row(view, 'app').installed_version == '1.0.0'
	assert view_row(view, 'app').diagnostic.contains('runtime: publisher key has been revoked')
	assert view_row(view, 'runtime').update_action == 'remove'
	assert view_row(view, 'independent').diagnostic == ''
	activated := catalog_view(revoked, catalog, State{ ...state, generation: 2, packages: catalog.packages }, '')!
	assert view_row(activated, 'app').diagnostic == ''
}

fn test_software_reports_invalid_keys_without_a_usable_catalog_and_after_policy_changes() {
	config, state := diagnostic_fixture()
	weak := '01' + '00'.repeat(31)
	packages := state.packages.map(if it.repository == 'legacy' { Installed{ ...it, public_key: weak } } else { it })
	invalid := Config{ ...config, repositories: [config.repositories[0], Repository{ ...config.repositories[1], public_key: weak }] }
	view := catalog_view(invalid, Catalog{}, State{ ...state, packages: packages }, 'publisher key admission failed')!
	assert view.catalog_error != '' && view.rows.all(!it.updatable)
	assert view_row(view, 'app').diagnostic.contains('runtime: repository legacy has an invalid publisher key')
	assert view_row(view, 'independent').diagnostic == ''
	// A newly advertised application also reports direct trust denial.
	fresh := view_installed(view_package('fresh', '1.0.0', 'native'))
	bad_app := Installed{ ...fresh, public_key: weak, repository: 'legacy' }
	assert catalog_view(invalid, Catalog{ packages: [bad_app] }, State{ architecture: 'aarch64' }, '')!.rows[0].diagnostic.contains('invalid publisher key')
	policy := Config{ ...config, policy: Policy{ permissions: [] } }
	restricted := state.packages.map(if it.package.id == 'runtime' { Installed{ ...it, package: Package{ ...it.package, permissions: ['process'] } } } else { it })
	blocked := catalog_view(policy, Catalog{}, State{ ...state, packages: restricted }, 'expired index')!
	assert view_row(blocked, 'app').diagnostic.contains('runtime: permissions blocked')
}

fn test_diagnostic_graphs_retire_owned_messages_edges_and_key_checks() {
	$if track_heap ? {
		config, state := diagnostic_fixture()
		weak := '01' + '00'.repeat(31)
		packages := state.packages.map(if it.repository == 'legacy' { Installed{ ...it, public_key: weak } } else { it })
		invalid := Config{ ...config, repositories: [config.repositories[0], Repository{ ...config.repositories[1], public_key: weak }] }
		for installed in packages {
			C.vinix_heap_begin()
			mut keys := map[string]bool{}
			message := package_diagnostic(invalid, installed, mut keys)
			unsafe { message.free(); keys.free() }
			kept := C.vinix_heap_end()
			assert kept == 0 && C.vinix_heap_count() == 0, '${installed.package.id}: direct diagnostic retained ${kept}'
		}
		for _ in 0 .. 32 {
			for index, checked in [config, invalid, Config{ ...config, repositories: [] }, Config{ ...invalid, policy: Policy{ allowed: ['runtime'] } }] {
				C.vinix_heap_begin()
				messages := package_diagnostics(checked, packages)
				assert messages['app'] != '' && messages['runtime'] != ''
				close_package_diagnostics(messages)
				kept := C.vinix_heap_end()
				assert kept == 0 && C.vinix_heap_count() == 0, 'case ${index}: package diagnostics retained ${kept} bytes'
			}
		}
		println('Package diagnostics: 128 valid/invalid/revoked/policy graph reads and retirement cycles retain zero tracked bytes PASS')
	}
}

fn test_publisher_key_decoding_preserves_canonical_lowercase_admission() {
	for encoded in ['d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a',
		'3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c',
		'fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025'] {
		key := admitted_publisher_key(encoded)!
		assert key.len == 32 && key.hex() == encoded
		unsafe { key.free() }
	}
	for encoded in ['', 'f'.repeat(63), 'f'.repeat(65), 'A'.repeat(64), 'g'.repeat(64),
		'0x' + '01'.repeat(31), '01' + '00'.repeat(31)] {
		if _ := admitted_publisher_key(encoded) { assert false, encoded } else {
			assert err.msg().contains('publisher key')
			unsafe { err.free() }
		}
	}
}
