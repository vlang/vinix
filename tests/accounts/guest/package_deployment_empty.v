// SPDX-License-Identifier: GPL-2.0-or-later
module main

import accountcore
import json2
import os
import tools.packages.pkgcore
import tools.packages.pkgprotocol

fn qualify_empty_package_deployment(mut t Test, db accountcore.Database, alex accountcore.User, sam accountcore.User) ! {
	service := pkgcore.Service{}
	store := pkgcore.state_directory('')
	before := service.state()!
	state_text := os.read_file(store + '/current/state.json')!
	config_path := '/etc/vinix-packages/config.json'
	config_text := os.read_file(config_path)!
	config := pkgcore.load_config('')!
	catalog := os.read_file(store + '/catalog.json')!
	history := os.read_file(store + '/trust-history.json')!
	blocked := json2.encode(pkgcore.Config{ ...config, repositories: [],
		policy: pkgcore.Policy{ offline: true, allowed: ['other'], permissions: [], reserve_bytes: 1234 } })
	os.write_file(config_path, blocked)!
	os.write_file(store + '/catalog.json', '{unavailable catalog')!
	os.write_file(store + '/trust-history.json', '{unavailable history')!
	os.rename(store + '/objects', store + '/objects-empty-saved')!
	os.mkdir(store + '/objects', mode: 0o700)!
	data := '/home/alex/.local/share/vinix-apps/admin-fixture'
	for directory in ['/home/alex/.local', '/home/alex/.local/share', '/home/alex/.local/share/vinix-apps', data] {
		os.mkdir(directory, mode: 0o700)!
		os.chown(directory, int(alex.uid), int(alex.gid))!
	}
	os.write_file(data + '/empty-retained', 'retain private application data')!
	os.chown(data + '/empty-retained', int(alex.uid), int(alex.gid))!
	path := '/tmp/empty deployment ; literal.json'
	mut fingerprint := ''
	for format in [1, 2]! {
		os.write_file(path, '{"format":${format},"architecture":"${config.architecture}","packages":[]' + if format == 2 { ',"locked":[]}' } else { '}' })!
		os.chmod(path, 0o644)!
		for user in [alex, sam] {
			response := run(['/usr/bin/vinix-package', 'deployment-review', path], '', db, user)
			assert response.status == 0, response.output
			mut view := pkgprotocol.decode_review(response.output)!
			assert view.generation == before.generation && view.requested.len == 0 && view.rows.len == 1
			assert view.rows[0].id == 'admin-fixture' && view.rows[0].action == 'remove' && view.rows[0].repository == 'admin-publisher'
			assert view.disk_needed == 4 * 1024 * 1024 && view.disk_reserve == 1234
			if format == 2 { fingerprint = view.fingerprint.clone() }
			view.close()
		}
		assert service.state()! == before && os.read_file(store + '/current/state.json')! == state_text
	}
	command := ['/usr/bin/vinix-package', 'admin', '--progress', 'deployment-apply', fingerprint, path]
	standard := run(command, sam_password + '\n', db, sam)
	assert standard.status != 0 && standard.output.contains('cannot approve'), standard.output
	wrong := run(command, 'wrong password\n', db, alex)
	assert wrong.status != 0 && service.state()! == before, wrong.output
	removed := run(command, alex_password + '\n', db, alex)
	assert removed.status == 0 && removed.output.contains(pkgprotocol.progress_prefix), removed.output
	current := service.verify()!
	assert current.generation == before.generation + 1 && current.previous == before.generation && current.requested.len == 0 && current.packages.len == 0
	assert os.ls(store + '/current/apps')!.len == 0 && os.ls(store + '/current/share/applications')!.len == 0
	assert os.read_file(config_path)! == blocked && os.read_file(store + '/catalog.json')! == '{unavailable catalog'
	assert os.read_file(store + '/trust-history.json')! == '{unavailable history' && os.ls(store + '/objects')!.len == 0
	assert os.read_file(data + '/empty-retained')! == 'retain private application data'
	assert owner_of(data) == alex.uid && mode_of(data) == 0o700 && owner_of(data + '/empty-retained') == alex.uid
	stale := run(command, alex_password + '\n', db, alex)
	assert stale.status != 0 && stale.output.contains('stale') && service.state()! == current, stale.output
	mut refused := false
	service.review('rollback', []) or { refused = true }
	assert refused
	os.write_file(config_path, config_text)!
	os.write_file(store + '/catalog.json', catalog)!; os.write_file(store + '/trust-history.json', history)!
	mut rollback := service.review('rollback', [])!
	defer { rollback.close() }
	restored := run(['/usr/bin/vinix-package', 'admin', 'apply', rollback.fingerprint, 'rollback'], alex_password + '\n', db, alex)
	assert restored.status == 0 && service.verify()!.packages == before.packages, restored.output
	assert os.ls(store + '/objects')!.len == 0 && os.read_file(data + '/empty-retained')! == 'retain private application data'
	os.rmdir(store + '/objects')!
	os.rename(store + '/objects-empty-saved', store + '/objects')!
	assert os.ls('/run/user/1000')!.all(!it.starts_with('pkg-'))
	t.say('PACKAGE DEPLOYMENT empty-offline formats-1-2 revoked-catalog authenticated-remove stale-refusal retained-data authorized-rollback PASS')
}
