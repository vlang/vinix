// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time
import desktop.packagecore

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
			for p in [Package{id: 'editor', version: version, architecture: architecture, name: 'Editor ' + version,
				description: 'Write é🚀 text', license: 'MIT', kind: 'native', runtime: 'runtime', entrypoint: 'bin/runner',
				permissions: ['files'], associations: ['text/plain'], dependencies: [Dependency{id: 'runtime', minimum: version}]},
				Package{id: 'runtime', version: version, architecture: architecture, name: 'Runtime', license: 'MIT', kind: 'runtime'}] {
				os.write_file(work + '/manifest.json', json2.encode(p))!
				pack(work + '/manifest.json', work + '/source', repository)!
			}
			publish(repository, 'fixture', work + '/seed', u64(index + 1), time.now().unix() + 3600)!
			service.refresh()!
			state := service.transact(if index == 0 { 'install' } else { 'upgrade' }, if index == 0 { ['editor'] } else { []string{} }, TransactionOptions{})!
			assert registry.refresh(directory, u32(os.geteuid()), architecture)!
			assert registry.generation == state.generation && registry.apps.len == 1
			assert registry.apps[0].name == 'Editor ' + version && registry.apps[0].accepts('text/plain')
			assert !registry.refresh(directory, u32(os.geteuid()), architecture)!
		}
		removed := service.transact('remove', ['editor'], TransactionOptions{})!
		assert registry.refresh(directory, u32(os.geteuid()), architecture)!
		assert registry.generation == removed.generation && registry.apps.len == 0
		restored := service.rollback('')!
		assert registry.refresh(directory, u32(os.geteuid()), architecture)!
		assert registry.generation == restored.generation && registry.apps.len == 1 && registry.apps[0].name == 'Editor 2.0.0'
		registry.close()
		println('Real generation registration: ' + architecture + ' install/update/remove/rollback and MIME cache passed')
	}
}
