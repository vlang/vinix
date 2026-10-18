// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time
import tests.packages.elffixture

fn wine_put(mut bytes []u8, offset int, value u64, width int) {
	for index in 0 .. width { bytes[offset + index] = u8(value >> (index * 8)) }
}

// Structural fixtures only: neither this PE nor the ELF launcher is executed.
fn wine_fixture_pe() []u8 {
	mut bytes := []u8{len: 1024}
	bytes[0] = `M`; bytes[1] = `Z`
	wine_put(mut bytes, 60, 128, 4)
	bytes[128] = `P`; bytes[129] = `E`
	wine_put(mut bytes, 132, 0x8664, 2)
	wine_put(mut bytes, 134, 1, 2)
	wine_put(mut bytes, 148, 240, 2)
	wine_put(mut bytes, 150, 2, 2)
	wine_put(mut bytes, 152, 0x20b, 2)
	wine_put(mut bytes, 168, 0x1000, 4)
	wine_put(mut bytes, 208, 0x2000, 4)
	wine_put(mut bytes, 212, 512, 4)
	wine_put(mut bytes, 220, 3, 2)
	wine_put(mut bytes, 400, 512, 4)
	wine_put(mut bytes, 404, 0x1000, 4)
	wine_put(mut bytes, 408, 512, 4)
	wine_put(mut bytes, 412, 512, 4)
	wine_put(mut bytes, 428, 0x60000020, 4)
	bytes[512] = 0xc3
	return bytes
}

fn wine_fixture_recipe(architecture string, application bool) RootRecipe {
	return if application {
		RootRecipe{ manifest: Package{ id: 'org.example.win64', version: '1.0.0', architecture: architecture,
			name: 'Reviewed Win64 application', description: 'Explicit publisher-supplied compatibility closure.',
			license: 'Example-EULA', proprietary: true, kind: 'windows', runtime: 'org.example.wine',
			entrypoint: 'bin/wine-runner', arguments: ['@APP@/bin/program.exe', 'literal ; $ argument'],
			permissions: ['files', 'process'], associations: ['text/plain'],
			dependencies: [Dependency{ id: 'org.example.wine', minimum: '1.0.0', before: '2.0.0' }] },
			entries: [RootEntry{ source: 'app/program.exe', path: 'bin/program.exe' },
				RootEntry{ source: 'licenses/application-LICENSE.txt', path: wine_application_notice }] }
	} else {
		RootRecipe{ manifest: Package{ id: 'org.example.wine', version: '1.0.0', architecture: architecture,
			name: 'Reviewed Wine closure', license: 'LGPL-2.1-or-later', kind: 'runtime' },
			entries: [RootEntry{ source: 'runtime/runner', path: 'bin/wine-runner' },
				RootEntry{ source: 'runtime/closure.txt', path: 'share/closure.txt' },
				RootEntry{ source: 'licenses/runtime-LICENSE.txt', path: wine_runtime_notice }] }
	}
}

fn wine_fixture() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-wine-profile-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	for architecture in ['aarch64', 'x86_64'] {
		root := work + '/roots/' + architecture
		for directory in ['app', 'runtime', 'licenses'] { os.mkdir_all(root + '/' + directory)! }
		os.write_file_array(root + '/app/program.exe', wine_fixture_pe())!
		os.write_file_array(root + '/runtime/runner', elffixture.image(architecture, 'static'))!
		os.chmod(root + '/runtime/runner', 0o755)!
		os.write_file(root + '/runtime/closure.txt', 'publisher enumerated runtime resources ' + architecture)!
		os.write_file(root + '/licenses/application-LICENSE.txt', 'Fixture license; not permission to distribute a commercial application.')!
		os.write_file(root + '/licenses/runtime-LICENSE.txt', 'Fixture runtime license.')!
		os.mkdir_all(work + '/recipes/' + architecture)!
		for role in ['application', 'runtime'] {
			os.write_file(work + '/recipes/' + architecture + '/' + role + '.json',
				json2.encode(wine_fixture_recipe(architecture, role == 'application')))!
		}
	}
	return work
}

fn test_wine_profile_reproducible_pins_signed_offline_install_license_policy_and_clean_removal() {
	work := wine_fixture()!
	defer { os.rmdir_all(work) or {} }
	one := wine_catalog(work + '/recipes', work + '/roots', work + '/one')!
	two := wine_catalog(work + '/recipes', work + '/roots', work + '/two')!
	assert one.profile == 'wine-win64' && one.application == 'org.example.win64' && one.runtime == 'org.example.wine'
	assert one.catalog_sha256 == two.catalog_sha256
	assert os.ls(one.directory)! == ['catalog.json'] && os.stat(one.directory)!.mode & 0o777 == 0o700
	recipe := catalog_recipe(read_metadata(one.catalog)!)!
	assert recipe.architectures == ['aarch64', 'x86_64'] && recipe.packages.len == 4
	for item in recipe.packages {
		p := item.recipe.manifest
		if p.kind == 'windows' {
			assert p.proprietary && p.license == 'Example-EULA' && !p.firmware
			assert p.permissions == ['files', 'process'] && p.associations == ['text/plain']
			assert p.runtime == one.runtime && p.arguments == ['@APP@/bin/program.exe', 'literal ; $ argument']
			assert p.files.len == 2 && p.files.any(it.path == 'bin/program.exe' && !it.executable)
		} else {
			assert p.kind == 'runtime' && p.permissions.len == 0 && p.files.len == 3
			assert p.files.any(it.path == 'bin/wine-runner' && it.executable)
		}
	}
	assert pack_catalog(one.catalog, work + '/roots', work + '/workspace')!.package_count == 4
	key := keygen(work + '/seed')!
	publish_release(work + '/workspace', 'wine', work + '/seed', 1, time.now().unix() + 3600, work + '/release')!
	for architecture in one.architectures {
		config := Config{ architecture: architecture, repositories: [Repository{ id: 'wine', url: 'file://' + work + '/release', public_key: key }],
			policy: Policy{ offline: true, reserve_bytes: 0 } }
		store := work + '/store-' + architecture
		refresh(config, store)!
		mut denied := false
		transact(config, store, 'install', [one.application], TransactionOptions{}) or { denied = err.msg().contains('license') }
		assert denied && read_state(store, architecture)!.generation == 0
		accepted := Config{ ...config, policy: Policy{ offline: true, reserve_bytes: 0, licenses: ['Example-EULA'] } }
		installed := transact(accepted, store, 'install', [one.application], TransactionOptions{})!
		assert installed.packages.len == 2 && installed.requested == [one.application]
		assert installed.packages.all(it.package.architecture == architecture)
		launcher := store + '/current/share/applications/vinix-org.example.win64.desktop'
		assert os.read_file(launcher)!.contains('MimeType=text/plain;')
		assert transact(accepted, store, 'remove', [one.application], TransactionOptions{})!.packages.len == 0
		assert !os.exists(launcher)
		assert rollback(accepted, store)!.packages.len == 2
	}
	// A new runtime version is explicit and does not rewrite application metadata.
	for architecture in ['aarch64', 'x86_64'] {
		runtime := wine_fixture_recipe(architecture, false)
		os.write_file(work + '/recipes/' + architecture + '/runtime.json', json2.encode(RootRecipe{
			...runtime, manifest: Package{ ...runtime.manifest, version: '1.1.0' } }))!
	}
	updated := wine_catalog(work + '/recipes', work + '/roots', work + '/updated')!
	updated_recipe := catalog_recipe(read_metadata(updated.catalog)!)!
	assert updated.runtime_version == '1.1.0'
	assert recipe.packages.filter(it.recipe.manifest.kind == 'windows') == updated_recipe.packages.filter(it.recipe.manifest.kind == 'windows')
}

fn test_wine_pe_admission_bounds_target_kind_sections_and_file_backed_entrypoint() {
	work := wine_fixture()!
	defer { os.rmdir_all(work) or {} }
	root := capture_prepared_root(work + '/roots/aarch64', 'PE test')!
	defer { C.close(root) }
	profile_win64(root, 'app/program.exe')!
	// DOS/PE offsets, host-inappropriate machine, PE32, DLL, EFI subsystem,
	// header truncation, section range and nonexecutable/unbacked entrypoints.
	for row in [[0, 0, 1], [60, 63, 4], [60, 0xffffffff, 4], [128, 0, 4],
		[132, 0xaa64, 2], [132, 0x14c, 2], [134, 97, 2], [148, 111, 2], [148, 4097, 2],
		[150, 0x2002, 2], [150, 0, 2], [152, 0x10b, 2], [168, 0, 4], [168, 0x2000, 4],
		[212, 431, 4], [220, 10, 2], [400, 0xffffffff, 4], [408, 513, 4],
		[412, 511, 4], [412, 1024, 4], [428, 0x40000040, 4], [168, 0x1200, 4]] {
		mut bytes := wine_fixture_pe()
		wine_put(mut bytes, row[0], u64(row[1]), row[2])
		os.write_file_array(work + '/roots/aarch64/app/program.exe', bytes)!
		mut denied := false
		profile_win64(root, 'app/program.exe') or { denied = true }
		assert denied, 'accepted invalid field at ' + row[0].str()
	}
	for size in [0, 63, 151, 263, 431, 1023] {
		bytes := wine_fixture_pe()
		os.write_file_array(work + '/roots/aarch64/app/program.exe', bytes[..size])!
		mut denied := false
		profile_win64(root, 'app/program.exe') or { denied = true }
		assert denied
	}
}

fn wine_no_space(_ string) !u64 { return 0 }
fn wine_change_pe(phase string, stage string) ! {
	if phase == 'created' { os.write_file(os.dir(stage) + '/roots/aarch64/app/program.exe', 'changed after preflight')! }
}
fn wine_change_notice(phase string, stage string) ! {
	if phase == 'created' { os.write_file(os.dir(stage) + '/roots/x86_64/licenses/runtime-LICENSE.txt', '')! }
}
fn wine_change_runner(phase string, stage string) ! {
	if phase == 'created' { os.write_file_array(os.dir(stage) + '/roots/aarch64/runtime/runner', elffixture.image('x86_64', 'static'))! }
}
fn wine_change_lock(phase string, stage string) ! {
	if phase == 'ready' { os.write_file(stage + '/lock/catalog.json', '{}')! }
}
fn wine_race_destination(phase string, stage string) ! {
	if phase == 'ready' { os.mkdir(os.dir(stage) + '/refused')!; os.write_file(os.dir(stage) + '/refused/keep', 'concurrent owner')! }
}

fn test_wine_profile_preflight_races_space_cleanup_and_retry() {
	for options in [CatalogOptions{ available_space: wine_no_space }, CatalogOptions{ checkpoint: wine_change_pe },
		CatalogOptions{ checkpoint: wine_change_notice }, CatalogOptions{ checkpoint: wine_change_runner },
		CatalogOptions{ checkpoint: wine_change_lock }, CatalogOptions{ checkpoint: wine_race_destination }] {
		work := wine_fixture()!
		defer { os.rmdir_all(work) or {} }
		baseline := wine_catalog(work + '/recipes', work + '/roots', work + '/baseline')!
		mut denied := false
		wine_catalog_with(work + '/recipes', work + '/roots', work + '/refused', options) or { denied = true }
		assert denied && os.ls(work)!.all(!it.starts_with('.vinix-wine-profile-'))
		if os.exists(work + '/refused') {
			assert os.ls(work + '/refused')! == ['keep']
			assert os.read_file(work + '/refused/keep')! == 'concurrent owner'
			os.rmdir_all(work + '/refused')!
		}
		os.write_file_array(work + '/roots/aarch64/app/program.exe', wine_fixture_pe())!
		os.write_file_array(work + '/roots/aarch64/runtime/runner', elffixture.image('aarch64', 'static'))!
		os.write_file(work + '/roots/x86_64/licenses/runtime-LICENSE.txt', 'Fixture runtime license.')!
		assert wine_catalog(work + '/recipes', work + '/roots', work + '/refused')!.catalog_sha256 == baseline.catalog_sha256
	}
}

fn test_wine_profile_refuses_inconsistent_hosts_unbounded_runtime_missing_notice_and_alias_root() {
	work := wine_fixture()!
	defer { os.rmdir_all(work) or {} }
	app := wine_fixture_recipe('x86_64', true)
	for p in [Package{ ...app.manifest, permissions: ['network'] }, Package{ ...app.manifest, proprietary: false },
		Package{ ...app.manifest, architecture: 'all' }, Package{ ...app.manifest, arguments: ['/usr/bin/wine'] },
		Package{ ...app.manifest, dependencies: [Dependency{ id: app.manifest.runtime, minimum: '1.0.0' }] }] {
		os.write_file(work + '/recipes/x86_64/application.json', json2.encode(RootRecipe{ ...app, manifest: p }))!
		mut denied := false
		wine_catalog(work + '/recipes', work + '/roots', work + '/refused') or { denied = true }
		assert denied && !os.exists(work + '/refused')
	}
	os.write_file(work + '/recipes/x86_64/application.json', json2.encode(app))!
	os.rm(work + '/roots/aarch64/licenses/application-LICENSE.txt')!
	mut notice := false
	wine_catalog(work + '/recipes', work + '/roots', work + '/refused') or { notice = true }
	assert notice && !os.exists(work + '/refused')
	os.write_file(work + '/roots/aarch64/licenses/application-LICENSE.txt', 'notice')!
	os.rename(work + '/roots/x86_64', work + '/saved')!
	os.symlink(work + '/saved', work + '/roots/x86_64')!
	mut alias := false
	wine_catalog(work + '/recipes', work + '/roots', work + '/refused') or { alias = err.msg().contains('ordinary directory') }
	assert alias && !os.exists(work + '/refused')
}

fn test_wine_profile_cli_matches_public_api_and_refuses_bad_arity_and_reused_output() {
	cli := os.getenv('VINIX_PACKAGE_WINE_CLI')
	if cli == '' { return } // The maintained qualification driver supplies it.
	work := wine_fixture()!
	defer { os.rmdir_all(work) or {} }
	mut expected := wine_catalog(work + '/recipes', work + '/roots', work + '/api')!
	defer { expected.close() }
	result := os.exec([cli, 'wine-catalog', work + '/recipes', work + '/roots', work + '/cli'])
	assert result.exit_code == 0, result.output
	actual := json2.decode[WineProfileInfo](result.output)!
	assert actual.catalog_sha256 == expected.catalog_sha256 && actual.architectures == ['aarch64', 'x86_64']
	assert actual.application == expected.application && actual.runtime_version == expected.runtime_version
	packed := os.exec([cli, 'pack-catalog', actual.catalog, work + '/roots', work + '/workspace'])
	assert packed.exit_code == 0, packed.output
	assert json2.decode[CatalogInfo](packed.output)!.package_count == 4
	for arguments in [ []string{}, [work + '/recipes'], [work + '/recipes', work + '/roots'],
		[work + '/recipes', work + '/roots', work + '/cli', 'extra'] ] {
		invalid := os.exec([cli, 'wine-catalog', ...arguments])
		assert invalid.exit_code == 1 && invalid.output.contains('requires a recipe directory')
	}
	occupied := os.exec([cli, 'wine-catalog', work + '/recipes', work + '/roots', work + '/cli'])
	assert occupied.exit_code == 1 && occupied.output.contains('must be new')
	assert read_metadata(actual.catalog)! == read_metadata(expected.catalog)!
	for architecture in ['aarch64', 'x86_64']! {
		runtime := wine_fixture_recipe(architecture, false)
		os.write_file(work + '/recipes/' + architecture + '/runtime.json', json2.encode(RootRecipe{
			...runtime, manifest: Package{ ...runtime.manifest, version: '1.1.0' } }))!
	}
	target := work + '/CLI runtime update'
	updated := os.exec([cli, 'wine-catalog', work + '/recipes', work + '/roots', target])
	assert updated.exit_code == 0, updated.output
	mut reply := json2.decode[WineProfileInfo](updated.output)!
	assert reply.format == 1 && reply.profile == 'wine-win64' && reply.directory == target && reply.catalog == target + '/catalog.json'
	assert reply.application == actual.application && reply.version == actual.version && reply.runtime == actual.runtime && reply.runtime_version == '1.1.0'
	assert reply.architectures == actual.architectures && reply.catalog_sha256 == index_digest(read_metadata(reply.catalog)!)
	before := catalog_recipe(read_metadata(actual.catalog)!)!; after := catalog_recipe(read_metadata(reply.catalog)!)!
	assert before.packages.filter(it.recipe.manifest.kind == 'windows') == after.packages.filter(it.recipe.manifest.kind == 'windows')
	reply.close(); reply.close(); assert os.is_file(target + '/catalog.json')
	println('WINE OWNER production CLI format-1 replies, paths with spaces, compatible runtime update and exact refusal preservation PASS')
}
