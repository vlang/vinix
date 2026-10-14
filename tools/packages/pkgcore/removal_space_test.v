// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import os
import time

fn test_removal_space_follows_verified_active_sources_and_deduplicates_fallback_objects() {
	directory := os.temp_dir() + '/vinix-removal-estimate-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(directory + '/generations/7/apps/retained/bin')!
	os.mkdir_all(directory + '/objects')!
	defer { os.rmdir_all(directory) or {} }
	data := 'retained signed bytes'
	file := Payload{ path: 'bin/one', sha256: sha256.sum(data.bytes()).hex(), bytes: u64(data.len), executable: true }
	package := Package{ id: 'retained', files: [file, Payload{ ...file, path: 'bin/two' }] }
	plan := Plan{ packages: [Installed{ package: package }] }
	current := State{ generation: 7 }
	cost := file.bytes + 8192
	staged := u64(4 * 1024 * 1024) + cost * 2
	first := directory + '/generations/7/apps/retained/bin/one'
	second := directory + '/generations/7/apps/retained/bin/two'
	object := directory + '/objects/' + file.sha256
	// Both paths need one shared missing object until each retained source verifies.
	assert estimate_transaction_space(plan, directory, current, 'remove')! == staged + cost
	os.write_file(first, data)!
	assert estimate_transaction_space(plan, directory, current, 'remove')! == staged + cost
	os.write_file(second, data)!
	assert estimate_transaction_space(plan, directory, current, 'remove')! == staged
	for operation in ['install', 'upgrade', 'deploy'] {
		assert estimate_transaction_space(plan, directory, current, operation)! == staged + cost
	}
	assert estimate_space(plan, directory)! == staged + cost
	assert estimate_transaction_space(plan, directory, State{}, 'remove')! == staged + cost
	// Same-size corruption and aliases do not qualify as retained sources.
	os.write_file(second, 'x'.repeat(data.len))!
	assert estimate_transaction_space(plan, directory, current, 'remove')! == staged + cost
	os.write_file(object, data)!
	assert estimate_transaction_space(plan, directory, current, 'remove')! == staged
	os.rm(second)!; os.symlink(first, second)!
	os.write_file(object, 'x'.repeat(data.len))!
	assert estimate_transaction_space(plan, directory, current, 'remove')! == staged + cost
	os.rm(second)!; os.mkdir(second)!
	assert estimate_transaction_space(plan, directory, current, 'remove')! == staged + cost
	// A different generation's file cannot reduce the current plan's estimate.
	assert estimate_transaction_space(plan, directory, State{ generation: 8 }, 'remove')! == staged + cost
	for bytes in [~u64(0), ~u64(0) - 8192] {
		if _ := estimate_space(Plan{ packages: [Installed{ package: Package{ files: [Payload{ bytes: bytes }] } }] }, directory) {
			assert false
		}
	}
	println('REMOVAL SPACE active-generation verification, shared fallback objects, missing/corrupt/linked sources, acquisition isolation and overflow PASS')
}
