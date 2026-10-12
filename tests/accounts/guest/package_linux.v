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
	config := pkgcore.Config{
		architecture: architecture
		launch_user:  'alex'
		repositories: [pkgcore.Repository{ id: 'fixture', url: 'file://' + repository, public_key: key }]
		policy:       pkgcore.Policy{ reserve_bytes: 0 }
	}
	os.mkdir_all('/etc/vinix-packages')!
	os.write_file('/etc/vinix-packages/config.json', json2.encode(config))!
	os.chmod('/etc/vinix-packages/config.json', 0o644)!
	os.write_file('/home/alex/outside.txt', 'not granted\n')!
	os.chown('/home/alex/outside.txt', 1000, 1000)!
	package_success(['update'])!
	mut installation := pkgprotocol.decode_review(package_success(['review', 'install', application.id])!)!
	defer { installation.close() }
	assert installation.rows.len == 2
	assert installation.rows.any(it.id == runtime.id && it.kind == 'runtime' && it.license == runtime.license)
	assert installation.rows.all(it.action == 'install' && it.repository == 'fixture' && it.public_key == key)
	assert pkgcore.read_state('/var/lib/vinix-packages', architecture)!.generation == 0
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
	package_success(['update'])!
	reviewed_package_operation('upgrade', [])!
	missing := run(['/usr/bin/vinix-package', 'run', application.id], '', none, none)
	assert missing.status == 127 && missing.output.contains('libfixture.so.1'), missing.output
	reviewed_package_operation('rollback', [])!
	assert package_success(['run', application.id])!.contains('PACKAGE LINUX')
	reviewed_package_operation('remove', [application.id])!
	removed := pkgcore.read_state('/var/lib/vinix-packages', architecture)!
	assert removed.packages.len == 0
	assert os.is_file(data)
	t.say('PACKAGE LINUX IMPORT signed-source-aliases explicit-runtime tamper-refusal missing-library rollback clean-uninstall PASS')
}

fn scenario_packages_linux(mut t Test) {
	qualify_package_linux(mut t) or { t.check(false, err.msg()) }
}
