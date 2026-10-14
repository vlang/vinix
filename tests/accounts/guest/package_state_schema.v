// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import tools.packages.pkgcore

fn stored_guest_inventory(path string) ![]string {
	mut result := []string{}
	mut names := os.ls(path)!; names.sort()
	for name in names {
		child := path + '/' + name
		if os.is_link(child) { result << child + ' -> ' + os.readlink(child)!
		} else if os.is_dir(child) { result << child + '/'; result << stored_guest_inventory(child)!
		} else { result << child + ' ' + pkgcore.hash_file(child)! }
	}
	return result
}

fn qualify_package_state_schema(mut t Test) ! {
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	t.say('PACKAGE STORED STATE preparing signed fixture')
	source := '/tmp/stored-source'
	repository := '/tmp/stored-repository'
	os.mkdir_all(source)!
	os.write_file(source + '/COPYING', 'MIT redistribution fixture')!
	os.mkdir_all('/tmp/package-publisher', mode: 0o700)!
	key := pkgcore.keygen('/tmp/package-publisher/stored-seed')!
	os.mkdir_all('/etc/vinix-packages')!
	os.write_file('/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{ architecture: architecture,
		policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 } }))!
	os.chmod('/etc/vinix-packages/config.json', 0o644)!
	for i, version in ['1.0.0', '2.0.0'] {
		os.write_file('/tmp/stored-manifest.json', json2.encode(pkgcore.Package{ id: 'stored-data', version: version,
			architecture: 'all', name: 'Stored-state fixture', license: 'MIT', kind: 'data' }))!
		pkgcore.pack('/tmp/stored-manifest.json', source, repository)!
		pkgcore.publish(repository, 'stored', '/tmp/package-publisher/stored-seed', u64(i + 1), time.now().unix() + 3600)!
		if i == 0 { package_success(['repo-enroll', 'stored', 'file://' + repository, key])! }
		package_success(['update'])!
		package_success(if i == 0 { ['install', 'stored-data'] } else { ['upgrade'] })!
		t.say('PACKAGE STORED STATE installed ' + version)
	}
	directory := '/var/lib/vinix-packages'
	os.mkdir(directory + '/generations/3')!
	os.write_file(directory + '/generations/3/lease', '')!
	os.mkdir(directory + '/generations/.stage-sentinel')!
	os.write_file(directory + '/objects/' + 'd'.repeat(64) + '.part', 'interrupted download')!
	service := pkgcore.Service{}
	mut review := service.review('remove', ['stored-data'])!
	defer { review.close() }
	configuration := os.read_file('/etc/vinix-packages/config.json')!
	for generation in ['2', '1'] {
		t.say('PACKAGE STORED STATE checking generation ' + generation)
		path := directory + '/generations/' + generation + '/state.json'
		original := os.read_file(path)!
		for invalid in [original.replace('"firmware":false,', ''), original.replace('"proprietary":false,', ''),
			original.replace('"permissions":[]', '"permissions":null'), original.replace('"sdk":1', '"sdk":"1"')] {
			assert invalid != original
			os.write_file(path, invalid)!
			before := stored_guest_inventory(directory)!
			mut operations := [['rollback'], ['gc'], ['review', 'rollback']]
			if generation == '2' {
				operations << [['status'], ['--json', 'status'], ['verify'], ['--json', 'verify'],
					['plan', 'remove', 'stored-data'], ['review', 'remove', 'stored-data'], ['upgrade'],
					['remove', 'stored-data'], ['apply', review.fingerprint, 'remove', 'stored-data']]
			}
			for arguments in operations {
				failed := run(['/usr/bin/vinix-package', ...arguments], '', none, none)
				assert failed.status == 1 && !failed.output.contains('V panic:'), failed.output
				assert failed.output.contains('missing required signed package field') || failed.output.contains('invalid metadata document field type')
					|| failed.output.contains('Expected number, but got string'), failed.output
				assert stored_guest_inventory(directory)! == before
				assert os.read_file('/etc/vinix-packages/config.json')! == configuration
			}
		}
		os.write_file(path, original)!
	}
	t.say('PACKAGE STORED STATE active-previous missing-disclosures null-permissions coerced-sdk CLI-refusal no-mutation PASS')
	package_success(['verify'])!
	package_success(['apply', review.fingerprint, 'remove', 'stored-data'])!
	assert service.state()!.packages.len == 0
	package_success(['rollback'])!
	assert service.verify()!.packages[0].package.version == '2.0.0'
	package_success(['gc'])!
	assert !os.exists(directory + '/generations/3') && !os.exists(directory + '/generations/.stage-sentinel')
	package_success(['remove', 'stored-data'])!
	package_success(['--offline', 'install', 'stored-data'])!
	assert service.verify()!.packages[0].package.version == '2.0.0'
	t.say('PACKAGE STORED STATE restored reviewed-removal rollback collection offline-reinstall PASS')
}

fn scenario_packages_state_schema(mut t Test) { qualify_package_state_schema(mut t) or { t.check(false, err.msg()) } }
