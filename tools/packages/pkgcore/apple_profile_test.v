// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time
import tests.packages.applefixture
import tests.packages.elffixture

fn apple_fixture_info(id string) string {
	return '<plist><dict><key>CFBundleIdentifier</key><string>' + id + '</string><key>CFBundleExecutable</key><string>Example</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>'
}

fn apple_fixture_recipe(application bool) RootRecipe {
	return if application {
		RootRecipe{ manifest: Package{ id: 'org.example.apple', version: '1.0.0', architecture: 'aarch64',
			name: 'Reviewed Apple application', description: 'Publisher-supplied iOS bundle and isolated runtime.',
			license: 'Example-EULA', proprietary: true, kind: 'apple', runtime: 'org.example.ios-runtime',
			entrypoint: 'bin/run-ios', arguments: ['@APP@/Example.app/Example', 'literal ; $ argument'],
			permissions: ['files', 'process'], associations: ['text/plain'],
			dependencies: [Dependency{ id: 'org.example.ios-runtime', minimum: '1.0.0', before: '2.0.0' }] },
			entries: [RootEntry{ source: 'app/Example', path: 'Example.app/Example' },
				RootEntry{ source: 'app/Info.plist', path: 'Example.app/Info.plist' },
				RootEntry{ source: 'licenses/application-LICENSE.txt', path: apple_application_notice }] }
	} else {
		RootRecipe{ manifest: Package{ id: 'org.example.ios-runtime', version: '1.0.0', architecture: 'aarch64',
			name: 'Reviewed iOS runtime closure', license: 'GPL-2.0-or-later AND MIT', kind: 'runtime' },
			entries: [RootEntry{ source: 'runtime/runner', path: 'bin/run-ios' },
				RootEntry{ source: 'runtime/closure.txt', path: 'share/closure.txt' },
				RootEntry{ source: 'licenses/runtime-LICENSE.txt', path: apple_runtime_notice }] }
	}
}

fn apple_fixture() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-apple-profile-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	root := work + '/roots/aarch64'
	for directory in ['app', 'runtime', 'licenses'] { os.mkdir_all(root + '/' + directory)! }
	os.write_file_array(root + '/app/Example', applefixture.image(23))!
	os.write_file(root + '/app/Info.plist', apple_fixture_info('org.example.apple'))!
	os.write_file_array(root + '/runtime/runner', elffixture.image('aarch64', 'static'))!
	os.chmod(root + '/runtime/runner', 0o755)!
	os.write_file(root + '/runtime/closure.txt', 'enumerated runtime resources')!
	os.write_file(root + '/licenses/application-LICENSE.txt', 'Fixture only; no commercial redistribution rights.')!
	os.write_file(root + '/licenses/runtime-LICENSE.txt', 'Fixture runtime license.')!
	os.mkdir_all(work + '/recipes/aarch64')!
	for role in ['application', 'runtime'] { os.write_file(work + '/recipes/aarch64/' + role + '.json', json2.encode(apple_fixture_recipe(role == 'application')))! }
	return work
}

fn test_apple_profile_reproducible_lock_signing_offline_policy_lifecycle_and_architecture() {
	work := apple_fixture()!
	defer { os.rmdir_all(work) or {} }
	one := apple_catalog(work + '/recipes', work + '/roots', work + '/one')!
	two := apple_catalog(work + '/recipes', work + '/roots', work + '/two')!
	assert one.profile == 'apple-ios-arm64' && one.architectures == ['aarch64'] && one.catalog_sha256 == two.catalog_sha256
	assert os.ls(one.directory)! == ['catalog.json'] && os.stat(one.directory)!.mode & 0o777 == 0o700
	recipe := catalog_recipe(read_metadata(one.catalog)!)!
	assert recipe.architectures == ['aarch64'] && recipe.packages.len == 2
	app := recipe.packages.filter(it.recipe.manifest.kind == 'apple')[0].recipe.manifest
	assert app.proprietary && app.license == 'Example-EULA' && !app.firmware
	assert app.permissions == ['files', 'process'] && app.associations == ['text/plain']
	assert app.arguments == ['@APP@/Example.app/Example', 'literal ; $ argument']
	assert app.files.len == 3 && app.files.any(it.path == 'Example.app/Example' && !it.executable)
	assert pack_catalog(one.catalog, work + '/roots', work + '/workspace')!.package_count == 2
	key := keygen(work + '/seed')!
	publish_release(work + '/workspace', 'apple', work + '/seed', 1, time.now().unix() + 3600, work + '/release')!
	config := Config{ architecture: 'aarch64', repositories: [Repository{ id: 'apple', url: 'file://' + work + '/release', public_key: key }], policy: Policy{ offline: true, reserve_bytes: 0 } }
	store := work + '/state'; refresh(config, store)!
	mut denied := false
	transact(config, store, 'install', [one.application], TransactionOptions{}) or { denied = err.msg().contains('license') }
	assert denied && read_state(store, 'aarch64')!.generation == 0
	accepted := Config{ ...config, policy: Policy{ offline: true, reserve_bytes: 0, licenses: ['Example-EULA'] } }
	assert transact(accepted, store, 'install', [one.application], TransactionOptions{})!.packages.len == 2
	launcher := store + '/current/share/applications/vinix-org.example.apple.desktop'
	assert os.read_file(launcher)!.contains('MimeType=text/plain;')
	assert transact(accepted, store, 'remove', [one.application], TransactionOptions{})!.packages.len == 0 && !os.exists(launcher)
	assert rollback(accepted, store)!.packages.len == 2
	x86 := Config{ ...accepted, architecture: 'x86_64' }; refresh(x86, work + '/x86')!
	mut unsupported := false
	transact(x86, work + '/x86', 'install', [one.application], TransactionOptions{}) or { unsupported = true }
	assert unsupported && read_state(work + '/x86', 'x86_64')!.generation == 0
	runtime := apple_fixture_recipe(false)
	os.write_file(work + '/recipes/aarch64/runtime.json', json2.encode(RootRecipe{ ...runtime, manifest: Package{ ...runtime.manifest, version: '1.1.0' } }))!
	updated := apple_catalog(work + '/recipes', work + '/roots', work + '/updated')!
	assert updated.runtime_version == '1.1.0' && catalog_recipe(read_metadata(updated.catalog)!)!.packages.filter(it.recipe.manifest.kind == 'apple')[0].recipe.manifest == app
	println('APPLE-PROFILE: reproducible single-target lock, explicit grants/licenses, signed offline install, association/removal/rollback and unsupported-host refusal PASS')
}

fn test_apple_and_dual_host_native_profiles_compose_into_an_explicit_arm_release() {
	work := apple_fixture()!
	defer { os.rmdir_all(work) or {} }
	os.mkdir(work + '/roots/apple')!
	os.rename(work + '/roots/aarch64', work + '/roots/apple/aarch64')!
	for architecture in ['aarch64', 'x86_64'] {
		root := work + '/roots/native/' + architecture
		os.mkdir_all(root + '/bin')!; os.mkdir_all(root + '/licenses')!
		for name in ['package-hello', 'counter', 'memo'] {
			os.write_file_array(root + '/bin/' + name, elffixture.image(architecture, 'static'))!
			os.chmod(root + '/bin/' + name, 0o755)!
		}
		for name in ['application-sdk-MIT.txt', 'v-MIT.txt', 'musl-MIT.txt'] { os.write_file(root + '/licenses/' + name, name)! }
	}
	apple := apple_catalog(work + '/recipes', work + '/roots/apple', work + '/apple-lock')!
	native := native_catalog('1.0.0', work + '/roots/native', work + '/native-lock')!
	sources := [CatalogSource{ id: 'apple', catalog: apple.catalog }, CatalogSource{ id: 'native', catalog: native.catalog }]
	selected := compose_catalog_for('aarch64', sources, work + '/selected')!
	assert selected.package_count == 5 && selected.architectures == ['aarch64']
	mut denied := false
	compose_catalog_for('x86_64', sources, work + '/unsupported') or { denied = err.msg().contains('apple does not support requested architecture x86_64') }
	assert denied && !os.exists(work + '/unsupported')
	// Selecting a host does not require absent payloads for the omitted host.
	os.rmdir_all(work + '/roots/native/x86_64')!
	assert pack_catalog(selected.catalog, work + '/roots', work + '/workspace')!.package_count == 5
	key := keygen(work + '/seed')!
	publish_release(work + '/workspace', 'mixed', work + '/seed', 1, time.now().unix() + 3600, work + '/release')!
	config := Config{ architecture: 'aarch64', repositories: [Repository{ id: 'mixed', url: 'file://' + work + '/release', public_key: key }],
		policy: Policy{ offline: true, reserve_bytes: 0, licenses: ['Example-EULA'] } }
	store := work + '/store'; refresh(config, store)!
	installed := transact(config, store, 'install', [apple.application, 'org.vinix.package-hello'], TransactionOptions{})!
	assert installed.packages.len == 3 && installed.packages.all(it.package.architecture == 'aarch64')
	assert installed.packages.any(it.package.kind == 'apple') && installed.packages.any(it.package.kind == 'native') && installed.packages.any(it.package.kind == 'runtime')
	assert transact(config, store, 'remove', [apple.application], TransactionOptions{})!.packages.len == 1
	assert !os.exists(store + '/current/share/applications/vinix-' + apple.application + '.desktop')
	assert os.is_file(store + '/current/share/applications/vinix-org.vinix.package-hello.desktop')
	assert rollback(config, store)!.packages.len == 3
	println('APPLE-PROFILE: real producer locks combine Apple/native runtime closures for an explicit ARM host; x86 refuses, signed offline removal/rollback preserve independent apps PASS')
}

fn apple_no_space(_ string) !u64 { return 0 }
fn apple_change_image(phase string, stage string) ! { if phase == 'created' { os.write_file(os.dir(stage) + '/roots/aarch64/app/Example', 'changed executable')! } }
fn apple_change_info(phase string, stage string) ! { if phase == 'created' { os.write_file(os.dir(stage) + '/roots/aarch64/app/Info.plist', apple_fixture_info('other.app'))! } }
fn apple_change_notice(phase string, stage string) ! { if phase == 'created' { os.write_file(os.dir(stage) + '/roots/aarch64/licenses/runtime-LICENSE.txt', '')! } }
fn apple_change_runner(phase string, stage string) ! { if phase == 'created' { os.write_file_array(os.dir(stage) + '/roots/aarch64/runtime/runner', elffixture.image('x86_64', 'static'))! } }
fn apple_change_inventory(phase string, stage string) ! {
	if phase == 'created' { path := os.dir(stage) + '/roots/aarch64/app/Info.plist'; os.rm(path)!; os.mkdir(path)!; os.write_file(path + '/child', 'directory substitution')! }
}
fn apple_change_lock(phase string, stage string) ! { if phase == 'ready' { os.write_file(stage + '/lock/catalog.json', '{}')! } }
fn apple_race_destination(phase string, stage string) ! { if phase == 'ready' { os.mkdir(os.dir(stage) + '/refused')!; os.write_file(os.dir(stage) + '/refused/keep', 'concurrent owner')! } }
fn apple_change_recipe(phase string, stage string) ! { if phase == 'created' { os.write_file(os.dir(stage) + '/recipes/aarch64/application.json', '{}')! } }

fn test_apple_profile_import_rechecks_space_races_inventory_cleanup_and_retry() {
	for options in [CatalogOptions{ available_space: apple_no_space }, CatalogOptions{ checkpoint: apple_change_image },
		CatalogOptions{ checkpoint: apple_change_info }, CatalogOptions{ checkpoint: apple_change_notice },
		CatalogOptions{ checkpoint: apple_change_runner }, CatalogOptions{ checkpoint: apple_change_inventory },
		CatalogOptions{ checkpoint: apple_change_lock }, CatalogOptions{ checkpoint: apple_race_destination }] {
		work := apple_fixture()!
		defer { os.rmdir_all(work) or {} }
		baseline := apple_catalog(work + '/recipes', work + '/roots', work + '/baseline')!
		mut denied := false
		apple_catalog_with(work + '/recipes', work + '/roots', work + '/refused', options) or { denied = true }
		assert denied && os.ls(work)!.all(!it.starts_with('.vinix-apple-profile-'))
		if os.exists(work + '/refused') { assert os.read_file(work + '/refused/keep')! == 'concurrent owner'; os.rmdir_all(work + '/refused')! }
		root := work + '/roots/aarch64'
		os.write_file_array(root + '/app/Example', applefixture.image(23))!
		if os.is_dir(root + '/app/Info.plist') { os.rmdir_all(root + '/app/Info.plist')! }
		os.write_file(root + '/app/Info.plist', apple_fixture_info('org.example.apple'))!
		os.write_file(root + '/licenses/runtime-LICENSE.txt', 'Fixture runtime license.')!
		os.write_file_array(root + '/runtime/runner', elffixture.image('aarch64', 'static'))!; os.chmod(root + '/runtime/runner', 0o755)!
		assert apple_catalog(work + '/recipes', work + '/roots', work + '/refused')!.catalog_sha256 == baseline.catalog_sha256
	}
	work := apple_fixture()!
	defer { os.rmdir_all(work) or {} }
	expected := apple_catalog(work + '/recipes', work + '/roots', work + '/baseline')!
	assert apple_catalog_with(work + '/recipes', work + '/roots', work + '/captured', CatalogOptions{ checkpoint: apple_change_recipe })!.catalog_sha256 == expected.catalog_sha256
	println('APPLE-PROFILE: copied image/plist/notices/runner rechecks, directory substitution, space/lock/destination refusal, cleanup/retry and captured declarations PASS')
}

fn test_apple_profile_refuses_unbounded_runtime_incorrect_hosts_bad_arguments_missing_notices_and_alias_root() {
	work := apple_fixture()!
	defer { os.rmdir_all(work) or {} }
	app := apple_fixture_recipe(true)
	for p in [Package{ ...app.manifest, architecture: 'x86_64' }, Package{ ...app.manifest, firmware: true },
		Package{ ...app.manifest, entrypoint: 'usr/bin/run-ios' }, Package{ ...app.manifest, arguments: []string{} },
		Package{ ...app.manifest, arguments: ['/usr/share/host.app/Example'] },
		Package{ ...app.manifest, arguments: ['@APP@/../Example.app/Example'] },
		Package{ ...app.manifest, arguments: ['@APP@/Example.app/nested/Example'] },
		Package{ ...app.manifest, dependencies: [Dependency{ id: app.manifest.runtime, minimum: '1.0.0' }] }] {
		os.write_file(work + '/recipes/aarch64/application.json', json2.encode(RootRecipe{ ...app, manifest: p }))!
		mut denied := false; apple_catalog(work + '/recipes', work + '/roots', work + '/refused') or { denied = true }
		assert denied && !os.exists(work + '/refused')
	}
	os.write_file(work + '/recipes/aarch64/application.json', json2.encode(app))!
	runtime := apple_fixture_recipe(false)
	for p in [Package{ ...runtime.manifest, permissions: ['network'] }, Package{ ...runtime.manifest, id: 'other.runtime' }, Package{ ...runtime.manifest, version: '2.0.0' }] {
		os.write_file(work + '/recipes/aarch64/runtime.json', json2.encode(RootRecipe{ ...runtime, manifest: p }))!
		mut denied := false; apple_catalog(work + '/recipes', work + '/roots', work + '/refused') or { denied = true }
		assert denied && !os.exists(work + '/refused')
	}
	os.write_file(work + '/recipes/aarch64/runtime.json', json2.encode(runtime))!
	os.rm(work + '/roots/aarch64/licenses/application-LICENSE.txt')!
	mut notice := false; apple_catalog(work + '/recipes', work + '/roots', work + '/refused') or { notice = true }
	assert notice && !os.exists(work + '/refused')
	os.write_file(work + '/roots/aarch64/licenses/application-LICENSE.txt', 'notice')!
	os.rename(work + '/roots/aarch64', work + '/saved')!; os.symlink(work + '/saved', work + '/roots/aarch64')!
	mut alias := false; apple_catalog(work + '/recipes', work + '/roots', work + '/refused') or { alias = err.msg().contains('ordinary directory') }
	assert alias && !os.exists(work + '/refused')
}

fn test_apple_profile_cli_matches_api_and_rejects_bad_arity_and_occupied_output() {
	cli := os.getenv('VINIX_PACKAGE_APPLE_CLI'); if cli == '' { return }
	work := apple_fixture()!
	defer { os.rmdir_all(work) or {} }
	expected := apple_catalog(work + '/recipes', work + '/roots', work + '/api')!
	result := os.exec([cli, 'apple-catalog', work + '/recipes', work + '/roots', work + '/cli'])
	assert result.exit_code == 0, result.output
	actual := json2.decode[AppleProfileInfo](result.output)!
	assert actual.catalog_sha256 == expected.catalog_sha256 && actual.architectures == ['aarch64']
	packed := os.exec([cli, 'pack-catalog', actual.catalog, work + '/roots', work + '/workspace'])
	assert packed.exit_code == 0 && json2.decode[CatalogInfo](packed.output)!.package_count == 2, packed.output
	for args in [ []string{}, [work + '/recipes'], [work + '/recipes', work + '/roots'], [work + '/recipes', work + '/roots', work + '/cli', 'extra'] ] {
		invalid := os.exec([cli, 'apple-catalog', ...args]); assert invalid.exit_code == 1 && invalid.output.contains('requires a recipe directory')
	}
	occupied := os.exec([cli, 'apple-catalog', work + '/recipes', work + '/roots', work + '/cli'])
	assert occupied.exit_code == 1 && occupied.output.contains('must be new')
	assert read_metadata(actual.catalog)! == read_metadata(expected.catalog)!
}
