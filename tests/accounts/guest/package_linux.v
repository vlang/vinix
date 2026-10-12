// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import tools.packages.pkgcore
import tools.packages.pkgprotocol

fn reviewed_package_operation(operation string, names []string) !string {
	mut review := pkgprotocol.decode_review(package_success(['review', operation, ...names])!)!
	defer { review.close() }
	return package_success(['apply', review.fingerprint, operation, ...names])
}

fn qualify_package_configuration_lock() ! {
	guard := pkgcore.acquire('/var/lib/vinix-packages')!
	defer { guard.release() }
	path := '/etc/vinix-packages/config.json'
	original := os.read_file(path)!
	defer { os.write_file(path, original) or { panic(err) } }
	os.write_file(path, '{broken configuration')!
	for args in [
		['update'], ['status'], ['--json', 'verify'], ['review', 'install', 'linux-probe'],
		['apply', '0'.repeat(64), 'install', 'linux-probe'], ['rollback'], ['gc'],
		['run', 'linux-probe'],
	] {
		busy := run(['/usr/bin/vinix-package', ...args], '', none, none)
		assert busy.status != 0 && busy.output.contains('another package transaction'), busy.output
	}
}

fn qualify_package_linux(mut t Test) ! {
	t.make_accounts()
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	prepared := '/tmp/linux-root'
	for directory in ['bin', 'lib', 'usr/lib', 'licenses'] {
		os.mkdir_all(prepared + '/' + directory)!
	}
	for source, destination in {
		'linux-probe':   'bin/probe'
		'linux-runner':  'bin/vinix-linux-runner'
		'musl':          'lib/libc.so'
		'linux-library': 'usr/lib/libfixture.so.1'
	} {
		os.cp('/usr/share/package-fixtures/' + source, prepared + '/' + destination)!
		os.chmod(prepared + '/' + destination, 0o755)!
	}
	os.symlink('/lib/libc.so', prepared + '/lib/ld-musl-' + architecture + '.so.1')!
	os.symlink('libfixture.so.1', prepared + '/usr/lib/libfixture.so')!
	os.write_file(prepared + '/licenses/COPYING', read_text('/usr/share/package-fixtures/COPYING'))!
	os.write_file(prepared + '/licenses/musl-COPYRIGHT', read_text('/usr/share/package-fixtures/musl-COPYRIGHT'))!
	repository := '/tmp/linux-repository'
	runtime := pkgcore.Package{
		id:           'musl-fixture'
		version:      '1.0.0'
		architecture: architecture
		name:         'Explicit musl Linux runtime fixture'
		license:      'GPL-2.0-or-later AND MIT'
		kind:         'runtime'
	}
	application := pkgcore.Package{
		id:           'linux-probe'
		version:      '1.0.0'
		architecture: architecture
		name:         'Dynamic Linux qualification'
		license:      'GPL-2.0-or-later'
		kind:         'linux'
		runtime:      runtime.id
		entrypoint:   'bin/vinix-linux-runner'
		arguments:    ['@RUNTIME@/lib/ld-musl-' + architecture + '.so.1', '@APP@/bin/probe',
			'a space; $literal', '@unchanged']
		dependencies: [pkgcore.Dependency{ id: runtime.id, minimum: '1.0.0', before: '2.0.0' }]
	}
	for recipe in [
		pkgcore.RootRecipe{
			manifest: runtime
			entries:  [
				pkgcore.RootEntry{ source: 'bin/vinix-linux-runner', path: 'bin/vinix-linux-runner' },
				pkgcore.RootEntry{ source: 'lib', path: 'lib' },
				pkgcore.RootEntry{ source: 'usr/lib', path: 'usr/lib' },
				pkgcore.RootEntry{ source: 'licenses', path: 'licenses' },
			]
		},
		pkgcore.RootRecipe{
			manifest: application
			entries:  [
				pkgcore.RootEntry{ source: 'bin/probe', path: 'bin/probe' },
				pkgcore.RootEntry{ source: 'licenses/COPYING', path: 'licenses/COPYING' },
			]
		},
	] {
		os.write_file('/tmp/linux-recipe.json', json2.encode(recipe))!
		packed := json2.decode[pkgcore.Package](package_success(['pack-root', '/tmp/linux-recipe.json',
			prepared, repository])!)!
		assert packed.id == recipe.manifest.id && packed.files.len > 0
	}
	key := pkgcore.keygen('/tmp/linux-signing-seed')!
	pkgcore.publish(repository, 'fixture', '/tmp/linux-signing-seed', 1, time.now().unix() + 3600)!
	first_index := os.read_file(repository + '/index.json')!
	first_signature := os.read_file(repository + '/index.sig')!
	config := pkgcore.Config{
		architecture: architecture
		launch_user:  'alex'
		policy:       pkgcore.Policy{ reserve_bytes: 0 }
	}
	os.mkdir_all('/etc/vinix-packages')!
	os.write_file('/etc/vinix-packages/config.json', json2.encode(config))!
	os.chmod('/etc/vinix-packages/config.json', 0o644)!
	mut trust := pkgprotocol.decode_repository_review(package_success(['repo-review', 'enroll', 'fixture', 'file://' + repository, key])!)!
	defer { trust.close() }
	assert trust.sequence == 1 && trust.package_count == 2 && trust.public_key == key && trust.previous_public_key == ''
	assert pkgcore.load_config('')!.repositories.len == 0
	package_success(['repo-apply', trust.fingerprint, 'enroll', 'fixture', 'file://' + repository, key])!
	stale_trust := run(['/usr/bin/vinix-package', 'repo-apply', trust.fingerprint, 'enroll', 'fixture', 'file://' + repository, key], '', none, none)
	assert stale_trust.status != 0 && stale_trust.output.contains('review is stale'), stale_trust.output
	enrolled := json2.decode[pkgcore.RepositoryStatus](package_success(['--json', 'repo-list'])!)!
	assert enrolled.repositories.len == 1 && enrolled.repositories[0].public_key == key
	assert enrolled.history.len == 1 && enrolled.history[0].sequence == 1
	assert pkgcore.load_config('')!.launch_user == 'alex'
	os.write_file('/home/alex/outside.txt', 'not granted\n')!
	os.chown('/home/alex/outside.txt', 1000, 1000)!
	package_success(['update'])!
	qualify_package_configuration_lock()!
	mut installation := pkgprotocol.decode_review(package_success(['review', 'install', application.id])!)!
	defer { installation.close() }
	assert installation.rows.len == 2
	assert installation.rows.any(it.id == runtime.id && it.kind == 'runtime' && it.license == runtime.license)
	assert installation.rows.all(it.action == 'install' && it.repository == 'fixture' && it.public_key == key)
	assert pkgcore.read_state('/var/lib/vinix-packages', architecture)!.generation == 0
	enrolled_config := pkgcore.load_config('')!
	os.write_file('/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{
		...enrolled_config, policy: pkgcore.Policy{ ...enrolled_config.policy, reserve_bytes: 1 }
	}))!
	stale_policy := run(['/usr/bin/vinix-package', 'apply', installation.fingerprint, 'install', application.id], '', none, none)
	assert stale_policy.status != 0 && stale_policy.output.contains('review is stale'), stale_policy.output
	assert os.ls('/var/lib/vinix-packages/objects')!.len == 0
	os.write_file('/etc/vinix-packages/config.json', json2.encode(enrolled_config))!
	package_success(['apply', installation.fingerprint, 'install', application.id])!
	stale := run(['/usr/bin/vinix-package', 'apply', installation.fingerprint, 'install', application.id], '', none, none)
	assert stale.status != 0 && stale.output.contains('review is stale'), stale.output
	t.say('PACKAGE REVIEW full-runtime-closure provenance stale-confirmation PASS')
	state := pkgcore.read_state('/var/lib/vinix-packages', architecture)!
	assert state.requested == [application.id]
	assert state.packages.len == 2 && state.packages.any(it.package.id == runtime.id)
	generation := '/var/lib/vinix-packages/generations/' + state.generation.str()
	loader := generation + '/apps/' + runtime.id + '/lib/ld-musl-' + architecture + '.so.1'
	assert os.is_file(loader) && !os.is_link(loader)
	assert package_success(['run', application.id])!.contains('PACKAGE LINUX')
	data := '/home/alex/.local/share/vinix-apps/linux-probe/result'
	assert owner_of(data) == 1000 && read_text(data) == 'packaged shared library: 23\n'
	// Verification covers the complete runtime, including usr/lib dependencies.
	library := generation + '/apps/' + runtime.id + '/usr/lib/libfixture.so'
	original := os.read_bytes(library)!
	os.write_file(library, 'tampered\n')!
	bad_verification := run(['/usr/bin/vinix-package', '--json', 'verify'], '', none, none)
	assert bad_verification.status != 0 && bad_verification.output.contains('installed payload verification failed'), bad_verification.output
	changed := run(['/usr/bin/vinix-package', 'run', application.id], '', none, none)
	assert changed.status != 0 && changed.output.contains('installed application payload changed'), changed.output
	os.write_file_array(library, original)!
	package_success(['run', application.id])!
	// A signed publisher mistake reaches the loader's useful failure diagnostic.
	// No host-global copy can satisfy a missing library outside the grants.
	broken_recipe := pkgcore.RootRecipe{
		manifest: pkgcore.Package{ ...runtime, version: '1.1.0' }
		entries:  [
			pkgcore.RootEntry{ source: 'bin/vinix-linux-runner', path: 'bin/vinix-linux-runner' },
			pkgcore.RootEntry{ source: 'lib', path: 'lib' },
			pkgcore.RootEntry{ source: 'licenses', path: 'licenses' },
		]
	}
	os.write_file('/tmp/linux-recipe.json', json2.encode(broken_recipe))!
	package_success(['pack-root', '/tmp/linux-recipe.json', prepared, repository])!
	pkgcore.publish(repository, 'fixture', '/tmp/linux-signing-seed', 2, time.now().unix() + 3600)!
	latest_index := os.read_file(repository + '/index.json')!
	latest_signature := os.read_file(repository + '/index.sig')!
	package_success(['update'])!
	updates := json2.decode[pkgcore.SoftwareView](package_success(['view'])!)!
	assert updates.update_error == '' && updates.rows.filter(it.updatable).map(it.id) == [runtime.id]
	assert updates.rows.any(it.id == runtime.id && it.kind == 'runtime' && it.version == '1.1.0'
		&& it.installed_version == '1.0.0' && it.update_action == 'update' && it.public_key == key)
	update_row := json2.decode[pkgcore.SoftwareRow](package_success(['--json', 'updates'])!)!
	assert update_row.id == runtime.id && update_row.updatable
	reviewed_package_operation('upgrade', [])!
	assert package_success(['--json', 'updates'])!.trim_space() == ''
	t.say('PACKAGE UPDATES runtime-only resolved-version complete-closure PASS')
	missing := run(['/usr/bin/vinix-package', 'run', application.id], '', none, none)
	assert missing.status == 127 && missing.output.contains('libfixture.so.1'), missing.output
	reviewed_package_operation('rollback', [])!
	assert package_success(['run', application.id])!.contains('PACKAGE LINUX')
	mut revocation := pkgprotocol.decode_repository_review(package_success(['repo-review', 'revoke', 'fixture'])!)!
	defer { revocation.close() }
	assert revocation.public_key == key && revocation.url == 'file://' + repository
	package_success(['repo-apply', revocation.fingerprint, 'revoke', 'fixture'])!
	revoked_launch := run(['/usr/bin/vinix-package', 'run', application.id], '', none, none)
	assert revoked_launch.status != 0, revoked_launch.output
	revoked_rollback := run(['/usr/bin/vinix-package', 'rollback'], '', none, none)
	assert revoked_rollback.status != 0, revoked_rollback.output
	reviewed_package_operation('remove', [application.id])!
	removed := pkgcore.read_state('/var/lib/vinix-packages', architecture)!
	assert removed.packages.len == 0
	assert os.is_file(data)
	package_success(['update'])!
	assert pkgcore.read_snapshots('/var/lib/vinix-packages')!.len == 0
	os.write_file(repository + '/index.json', first_index)!
	os.write_file(repository + '/index.sig', first_signature)!
	replay := run(['/usr/bin/vinix-package', 'repo-enroll', 'fixture', 'file://' + repository, key], '', none, none)
	assert replay.status != 0 && replay.output.contains('retained trust history'), replay.output
	assert pkgcore.load_config('')!.repositories.len == 0
	os.write_file(repository + '/index.json', latest_index)!
	os.write_file(repository + '/index.sig', latest_signature)!
	package_success(['repo-enroll', 'fixture', 'file://' + repository, key])!
	package_success(['update'])!
	assert pkgcore.read_state('/var/lib/vinix-packages', architecture)!.generation == removed.generation
	assert os.is_file(data)
	t.say('PACKAGE TRUST REVIEW read-only authenticated-metadata stale-confirmation reviewed-revocation PASS')
	t.say('PACKAGE CONFIGURATION lock-scoped-policy verified-json-status busy-launch PASS')
	t.say('PACKAGE REPOSITORY authenticated-enrollment revocation retained-replay-floor re-enrollment PASS')
	t.say('PACKAGE LINUX IMPORT signed-source-aliases explicit-runtime tamper-refusal missing-library rollback clean-uninstall PASS')
}

fn scenario_packages_linux(mut t Test) {
	qualify_package_linux(mut t) or { t.check(false, err.msg()) }
}
