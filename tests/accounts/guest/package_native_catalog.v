// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import tools.packages.appsdk
import tools.packages.pkgcore

fn native_catalog_reopen(memo string) ! {
	for id in ['org.vinix.counter', 'org.vinix.memo'] {
		result := run(['/usr/bin/vinix-package', 'run-window', id], '', none, none)
		assert result.status == 0, result.output
		mut frames := window_guest_frames(result.output)!
		defer { for mut frame in frames { frame.close() } }
		assert frames.len == 1
		if id == 'org.vinix.counter' { assert frames[0].format == 1 && frames[0].elements[0].text == 'Count: 1' }
		else { assert frames[0].format == 2 && frames[0].elements[1].text == memo }
	}
}

fn qualify_package_native_catalog(mut t Test) ! {
	t.make_accounts()
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	roots := '/usr/share/native-catalog/roots'
	os.mkdir_all('/tmp/package-publisher', mode: 0o700)!
	key := pkgcore.keygen('/tmp/package-publisher/native-seed')!
	for i, version in ['1.0.0', '1.1.0'] {
		profile := pkgcore.native_catalog(version, roots, '/tmp/native-lock-' + version)!
		if i == 0 { assert os.read_file(profile.catalog)! == os.read_file('/usr/share/native-catalog/catalog.json')! }
		workspace := '/tmp/native-workspace-' + version
		assert pkgcore.pack_catalog(profile.catalog, roots, workspace)!.package_count == 6
		pkgcore.publish_release(workspace, 'native', '/tmp/package-publisher/native-seed', u64(i + 1), time.now().unix() + 3600, '/tmp/native-release-' + version)!
	}
	os.mkdir_all('/etc/vinix-packages')!
	os.write_file('/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{ architecture: architecture, launch_user: 'alex',
		policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 } }))!
	os.chmod('/etc/vinix-packages/config.json', 0o644)!
	// Stable repository identity, with successive complete signed snapshots.
	os.symlink('/tmp/native-release-1.0.0', '/tmp/native-repository')!
	package_success(['repo-enroll', 'native', 'file:///tmp/native-repository', key])!
	native_catalog_consume(mut t, key, architecture, '/tmp/native-release-', '/tmp/native-repository')!
}

fn native_catalog_consume(mut t Test, key string, architecture string, release_prefix string, repository string) ! {
	package_success(['update'])!
	ids := ['org.vinix.counter', 'org.vinix.memo', 'org.vinix.package-hello']
	reviewed_package_operation('install', ids)!
	state := pkgcore.Service{}.verify()!
	assert state.packages.len == 3 && state.packages.all(it.package.architecture == architecture)
	view := pkgcore.software_view('', false)!
	assert view.rows.len == 3
	for row in view.rows {
		if row.id == 'org.vinix.counter' { assert row.installed_window_protocol == 1 }
		if row.id == 'org.vinix.memo' { assert row.installed_window_protocol == 2 }
	}
	for installed in state.packages {
		p := installed.package
		assert p.files.len == 4 && installed.public_key == key && installed.repository == 'native'
		assert os.is_file('/var/lib/vinix-packages/current/share/applications/vinix-' + p.id + '.desktop')
	}
	document := '/home/alex/native document.txt'
	os.write_file(document, 'native catalog document')!; os.chown(document, 1000, 1000)!; os.chmod(document, 0o600)!
	hello := package_success(['run', ids[2], document])!
	assert hello.contains('Application: ' + ids[2] + ' 1.0.0') && hello.contains('native catalog document')
	input := appsdk.WindowEvent{ kind: 'click', sequence: 1, id: 'increase' }.encode()! + '\n'
		+ appsdk.WindowEvent{ kind: 'close', sequence: 2 }.encode()! + '\n'
	counter := run(['/usr/bin/vinix-package', 'run-window', ids[0]], input, none, none)
	assert counter.status == 0, counter.output
	memo := 'Catalog é🚀 $literal'
	text := appsdk.WindowEvent{ format: 2, kind: 'text', sequence: 1, id: 'memo', text: memo }.encode()! + '\n'
		+ appsdk.WindowEvent{ format: 2, kind: 'click', sequence: 2, id: 'save' }.encode()! + '\n'
		+ appsdk.WindowEvent{ format: 2, kind: 'close', sequence: 3 }.encode()! + '\n'
	saved := run(['/usr/bin/vinix-package', 'run-window', ids[1]], text, none, none)
	assert saved.status == 0, saved.output
	data := '/home/alex/.local/share/vinix-apps/'
	assert owner_of(data + ids[0] + '/counter.txt') == 1000 && os.read_file(data + ids[0] + '/counter.txt')! == '1'
	assert owner_of(data + ids[1] + '/memo.txt') == 1000 && os.read_file(data + ids[1] + '/memo.txt')! == memo
	native_catalog_reopen(memo)!
	t.say('PACKAGE NATIVE CATALOG six-pinned-packages signed-review architecture notices document-grant protocols-1-2 ordinary-data PASS')
	if os.is_link(repository) { os.rm(repository)! } else { os.rename(repository, repository + '-initial')! }
	os.symlink(release_prefix + '1.1.0', repository)!
	package_success(['update'])!
	reviewed_package_operation('upgrade', [])!
	assert pkgcore.Service{}.verify()!.packages.all(it.package.version == '1.1.0')
	assert package_success(['run', ids[2]])!.contains(ids[2] + ' 1.1.0')
	native_catalog_reopen(memo)!
	reviewed_package_operation('rollback', [])!
	assert pkgcore.Service{}.verify()!.packages.all(it.package.version == '1.0.0')
	native_catalog_reopen(memo)!
	reviewed_package_operation('upgrade', [])!
	reviewed_package_operation('remove', ids)!
	for id in ids { assert !os.exists('/var/lib/vinix-packages/current/share/applications/vinix-' + id + '.desktop') }
	package_success(['gc'])!
	os.rename(release_prefix + '1.1.0/objects', '/tmp/native-hidden-objects')!
	reviewed_package_operation('install', ids)!
	assert pkgcore.Service{}.verify()!.packages.all(it.package.version == '1.1.0')
	native_catalog_reopen(memo)!
	assert package_success(['run', ids[2]])!.contains(ids[2] + ' 1.1.0')
	t.say('PACKAGE NATIVE CATALOG upgrade rollback uninstall-registration offline-cache-reinstall retained-private-data PASS')
}

fn scenario_packages_native_catalog(mut t Test) { qualify_package_native_catalog(mut t) or { t.check(false, err.msg()) } }

fn qualify_package_native_image(mut t Test) ! {
	t.make_accounts()
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	path := '/etc/vinix-packages/config.json'
	initial := os.read_file(path)!
	config := pkgcore.load_config('')!
	assert config.architecture == architecture && config.launch_user == 'alex' && config.policy.offline
	assert config.repositories.len == 1 && config.repositories[0].id == 'native'
	assert config.repositories[0].url == 'file://' + pkgcore.image_repositories_path + '/native'
	assert os.ls('/var/lib/vinix-packages')!.len == 0
	assert os.is_file(pkgcore.image_repositories_path + '/native/index.json') && !os.is_link(pkgcore.image_repositories_path)
	t.say('PACKAGE IMAGE CONFIG booted with staged trust policy and launch account before first refresh PASS')
	fixture := run(['/usr/share/package-fixtures/image-configuration'], '', none, none)
	assert fixture.status == 0, fixture.output
	assert fixture.output.contains('PACKAGE IMAGE CONFIG signed catalog install remove rollback both architectures PASS')
	image_repository_assertions(mut t)!
	native_catalog_consume(mut t, config.repositories[0].public_key, architecture, '/usr/share/native-catalog/releases/', pkgcore.image_repositories_path + '/native')!
	assert os.read_file(path)! == initial
	t.say('PACKAGE IMAGE CONFIG unchanged staged configuration real native apps upgrade rollback offline reinstall PASS')
}

fn image_repository_assertions(mut t Test) ! {
	fixture := run(['/usr/share/package-fixtures/image-repositories'], '', none, none)
	assert fixture.status == 0, fixture.output
	assert fixture.output.contains('PACKAGE IMAGE BUNDLE captured signed closure atomic publication offline dependency install both architectures PASS')
	t.say('PACKAGE IMAGE BUNDLE production-staged signed repository before first refresh PASS')
}

fn scenario_packages_native_image(mut t Test) { qualify_package_native_image(mut t) or { t.check(false, err.msg()) } }
