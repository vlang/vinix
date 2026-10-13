// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time

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
	return Installed{ package: p, repository: 'fixture', public_key: '01'.repeat(32), sequence: 1 }
}

fn view_configuration() Config {
	return Config{
		architecture: 'aarch64'
		repositories: [Repository{
			id:         'fixture'
			url:        'https://example.invalid'
			public_key: '01'.repeat(32)
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
	new_key := '02'.repeat(32)
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
	assert os.ls(directory + '/objects')! == objects && os.ls(directory + '/generations')! == generations
	assert read_state(directory, 'aarch64')! == state
	guard := acquire(directory)!
	if _ := software_view(root, false) {
		assert false, 'view ignored package writer lock'
	}
	guard.release()
}
