// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time
import tools.packages.pkgprotocol

fn test_configuration_listing_survives_damaged_metadata_without_hiding_maintenance_failures() {
	root := os.real_path(os.temp_dir()) + '/vinix-repository-config-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(root + '/etc/vinix-packages')!
	defer { os.rmdir_all(root) or {} }
	repository := Repository{ id: 'legacy', url: 'file:///missing/offline-repository', public_key: '01' + '00'.repeat(31) }
	config := Config{ architecture: 'aarch64', policy: Policy{ offline: true }, repositories: [repository] }
	path := root + '/etc/vinix-packages/config.json'
	os.write_file(path, json2.encode(config))!
	os.chmod(path, 0o644)!
	configuration := repository_configuration(root)!
	assert configuration.scope == 'configuration' && configuration.repositories == [repository]
	assert !os.exists(state_directory(root))
	mut client := pkgprotocol.decode_repository_configuration(json2.encode(configuration))!
	assert client.architecture == 'aarch64' && client.repositories[0].public_key == repository.public_key
	client.close()
	directory := state_directory(root)
	guard := acquire(directory)!; guard.release()
	for damaged in [['not JSON', '{"format":1}'], ['[]', '{"format":1,"repositories":null}'],
		['null', '{"format":1,"repositories":[]}']] {
		os.write_file(directory + '/catalog.json', damaged[0])!
		os.write_file(directory + '/trust-history.json', damaged[1])!
		assert repository_configuration(root)! == configuration
		if _ := repository_status(root) { assert false }
		if _ := refresh(config, directory) { assert false }
		assert os.read_file(directory + '/catalog.json')! == damaged[0]
		assert os.read_file(directory + '/trust-history.json')! == damaged[1]
		assert os.read_file(path)! == json2.encode(config)
	}
	// A busy writer is reported before configuration is decoded, just as in
	// other read-only package APIs. The new endpoint never bypasses the lock.
	locked := acquire(directory)!
	os.write_file(path, 'broken configuration')!
	if _ := repository_configuration(root) { assert false } else { assert err.msg().contains('another package transaction') }
	locked.release()
	if _ := repository_configuration(root) { assert false }
	os.write_file(path, json2.encode(config))!
	cache := os.read_file(directory + '/catalog.json')!
	history := os.read_file(directory + '/trust-history.json')!
	mut review := review_repository(root, 'revoke', repository, true)!
	defer { review.close() }
	assert review.public_key == repository.public_key && review.operation == 'revoke'
	revoke_repository_reviewed(root, repository.id, review.fingerprint)!
	assert repository_configuration(root)!.repositories.len == 0
	assert os.read_file(directory + '/catalog.json')! == cache
	assert os.read_file(directory + '/trust-history.json')! == history
	if _ := repository_status(root) { assert false }
	if _ := refresh(load_config(root)!, directory) { assert false }
	println('REPOSITORY CONFIG fresh/locked/corrupt configuration checks; damaged cache/history listing and reviewed revocation preserve maintenance failures PASS')
}
