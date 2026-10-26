// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time
import desktop.packagecore

fn registration_require(condition bool, reason string) {
	if !condition { panic(reason) }
}

fn registration_name(version string) string { return '  Editor\\name ' + version + '  ' }

fn test_real_package_generations_update_uninstall_and_rollback_have_coherent_desktop_registration() {
	work := os.real_path(os.temp_dir()) + '/vinix-registration-lifecycle-' + os.getpid().str()
	os.mkdir_all(work + '/source/bin')!
	defer { os.rmdir_all(work) or {} }
	os.write_file(work + '/source/bin/runner', 'fixture payload, never executed\n')!
	os.chmod(work + '/source/bin/runner', 0o755)!
	key := keygen(work + '/seed')!
	for architecture in ['aarch64', 'x86_64'] {
		repository := work + '/repository-' + architecture
		root := work + '/root-' + architecture
		os.mkdir_all(root + '/etc/vinix-packages')!
		os.write_file(root + '/etc/vinix-packages/config.json', json2.encode(Config{architecture: architecture,
			repositories: [Repository{id: 'fixture', url: 'file://' + repository, public_key: key}],
			policy: Policy{reserve_bytes: 0}}))!
		service := Service{root: root}
		directory := state_directory(root)
		mut registry := packagecore.Registry{}
		for index, version in ['1.0.0', '2.0.0'] {
			name := registration_name(version)
			description := ' Literal \\n \\t \\r \\s \\\\ é🚀 '
			for p in [Package{id: 'editor', version: version, architecture: architecture, name: name,
				description: description, license: 'MIT', kind: 'native', runtime: 'runtime', entrypoint: 'bin/runner',
				permissions: ['files'], associations: ['text/plain'], dependencies: [Dependency{id: 'runtime', minimum: version}]},
				Package{id: 'runtime', version: version, architecture: architecture, name: 'Runtime', license: 'MIT', kind: 'runtime'}] {
				os.write_file(work + '/manifest.json', json2.encode(p))!
				pack(work + '/manifest.json', work + '/source', repository)!
			}
			publish(repository, 'fixture', work + '/seed', u64(index + 1), time.now().unix() + 3600)!
			service.refresh()!
			mut state := service.transact(if index == 0 { 'install' } else { 'upgrade' }, if index == 0 { ['editor'] } else { []string{} }, TransactionOptions{})!
			registration_require(registry.refresh(directory, u32(os.geteuid()), architecture)!, 'installed registry did not refresh')
			registration_require(registry.generation == state.generation && registry.apps.len == 1, 'installed registry generation mismatch')
			registration_require(registry.apps[0].name == name && registry.apps[0].description == description
				&& registry.apps[0].accepts('text/plain'), 'registry changed signed strings or MIME association')
			registration_require(!registry.refresh(directory, u32(os.geteuid()), architecture)!, 'unchanged registry refreshed')
			if index == 0 {
				// A launcher written by the old raw serializer must be repaired from
				// signed state rather than interpreting its escapes as new metadata.
				base := directory + '/generations/' + state.generation.str()
				entry := base + '/share/applications/vinix-editor.desktop'
				legacy := '[Desktop Entry]\nType=Application\nName=' + name + '\nComment=' + description
					+ '\nExec=/usr/bin/vinix-package run editor %F\nTerminal=false\nMimeType=text/plain;\nX-Vinix-Package=editor\nX-Vinix-Runtime=runtime\n'
				canonical := os.read_file(entry)!
				registration_require(canonical != legacy, 'XDG escaped metadata was written as raw launcher strings')
				os.write_file(entry, legacy)!
				mut refused := false
				service.verify() or { refused = true }
				registration_require(refused, 'Verify accepted a legacy raw launcher')
				mut review := service.review('install', ['editor'])!
				defer { review.close() }
				registration_require(review.rows.filter(it.action == 'update').map(it.id) == ['editor'], 'legacy launcher was not scheduled for repair')
				state = service.transact('install', ['editor'], TransactionOptions{ expected_review: review.fingerprint })!
				new_base := directory + '/generations/' + state.generation.str()
				registration_require(os.read_file(new_base + '/share/applications/vinix-editor.desktop')! == canonical, 'repair changed canonical launcher bytes')
				registration_require(service.verify()!.generation == state.generation, 'repaired registration did not verify')
				registration_require(registry.refresh(directory, u32(os.geteuid()), architecture)!
					&& registry.apps[0].name == name && registry.apps[0].description == description, 'repair changed signed registry strings')
			}
		}
		removed := service.transact('remove', ['editor'], TransactionOptions{})!
		registration_require(registry.refresh(directory, u32(os.geteuid()), architecture)!, 'removed registry did not refresh')
		registration_require(registry.generation == removed.generation && registry.apps.len == 0, 'uninstall retained registration')
		restored := service.rollback('')!
		registration_require(registry.refresh(directory, u32(os.geteuid()), architecture)!, 'rollback registry did not refresh')
		registration_require(registry.generation == restored.generation && registry.apps.len == 1
			&& registry.apps[0].name == registration_name('2.0.0'), 'rollback changed signed registry strings')
		registration_require(service.verify()!.generation == restored.generation, 'rollback launcher did not verify')
		registry.close()
		println('Real generation registration: ' + architecture + ' escaped signed metadata, install/repair/update/remove/rollback and MIME cache PASS')
	}
}
