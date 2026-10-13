// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import tools.packages.pkgcore

fn sqlite_run_sql(statement string) Ran {
	return run(['/usr/bin/vinix-package', 'run', pkgcore.sqlite_application_id], '.bail on\n' + statement + '\n', none, none)
}

fn qualify_package_sqlite(mut t Test) ! {
	t.make_accounts()
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	key := package_success(['keygen', '/tmp/sqlite-seed'])!.trim_space()
	expires := time.now().unix() + 3600
	for i, variant in ['base', 'math'] {
		roots := '/usr/share/sqlite-fixtures/' + variant
		profile := json2.decode[pkgcore.SqliteProfileInfo](package_success(['sqlite-catalog', '3.53.4',
			if variant == 'base' { '1.0.0' } else { '1.1.0' }, roots, '/tmp/sqlite-lock-' + variant])!)!
		assert profile.architectures == ['aarch64', 'x86_64'] && profile.profile == 'sqlite-cli'
		workspace := '/tmp/sqlite-workspace-' + variant
		catalog := json2.decode[pkgcore.CatalogInfo](package_success(['pack-catalog', profile.catalog, roots, workspace])!)!
		assert catalog.package_count == 4
		pub_result := json2.decode[pkgcore.ReleaseInfo](package_success(['publish-release', workspace,
			'sqlite-fixture', '/tmp/sqlite-seed', (i + 1).str(), expires.str(), '/tmp/sqlite-release-' + variant])!)!
		assert pub_result.public_key == key && pub_result.package_count == 4
	}
	os.mkdir_all('/etc/vinix-packages')!
	os.write_file('/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{
		architecture: architecture, launch_user: 'alex', policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 }
	}))!
	os.chmod('/etc/vinix-packages/config.json', 0o644)!
	package_success(['--offline', 'repo-enroll', 'sqlite-fixture', 'file:///tmp/sqlite-release-base', key])!
	package_success(['--offline', 'update'])!
	package_success(['--offline', 'install', pkgcore.sqlite_application_id])!
	initial := pkgcore.read_state('/var/lib/vinix-packages', architecture)!
	assert initial.packages.len == 2 && initial.packages.all(it.package.permissions.len == 0)
	application := initial.packages.filter(it.package.id == pkgcore.sqlite_application_id)[0].package
	created := sqlite_run_sql("SELECT sqlite_version(); PRAGMA journal_mode=WAL; CREATE TABLE saved(v INTEGER); INSERT INTO saved VALUES(42); SELECT sum(v) FROM saved; PRAGMA integrity_check;")
	assert created.status == 0 && created.output.contains('3.53.4\nwal\n42\nok'), created.output
	data := '/home/alex/.local/share/vinix-apps/' + pkgcore.sqlite_application_id + '/database.sqlite3'
	assert os.is_file(data) && os.stat(data)!.uid == 1000
	reopened := sqlite_run_sql('SELECT sum(v) FROM saved; PRAGMA integrity_check;')
	assert reopened.status == 0 && reopened.output.contains('42\nok'), reopened.output
	outside := sqlite_run_sql('.open /home/alex/denied-sqlite.db')
	// The upstream shell falls back to an in-memory database and may return 0
	// after a denied .open. Check the diagnostic and actual filesystem effect.
	assert outside.output.contains('unable to open database file')
		&& outside.output.contains('substitute in-memory database')
		&& !os.exists('/home/alex/denied-sqlite.db'), outside.output
	old_math := sqlite_run_sql('SELECT ceil(1.25);')
	assert old_math.status != 0 && old_math.output.contains('no such function: ceil'), old_math.output
	t.say('PACKAGE SQLITE database-wal reopen-integrity ordinary-owner outside-path-refusal PASS')
	package_success(['--offline', 'repo-enroll', 'sqlite-fixture', 'file:///tmp/sqlite-release-math', key])!
	package_success(['--offline', 'update'])!
	view := json2.decode[pkgcore.SoftwareView](package_success(['view'])!)!
	assert view.rows.filter(it.updatable).map(it.id) == [pkgcore.sqlite_runtime_id]
	package_success(['--offline', 'upgrade'])!
	upgraded := pkgcore.read_state('/var/lib/vinix-packages', architecture)!
	assert upgraded.packages.filter(it.package.id == pkgcore.sqlite_application_id)[0].package == application
	assert upgraded.packages.any(it.package.id == pkgcore.sqlite_runtime_id && it.package.version == '1.1.0')
	math := sqlite_run_sql('SELECT ceil(1.25); SELECT sum(v) FROM saved; PRAGMA integrity_check;')
	assert math.status == 0 && math.output.contains('2.0\n42\nok'), math.output
	package_success(['rollback'])!
	assert sqlite_run_sql('SELECT ceil(1.25);').status != 0
	assert sqlite_run_sql('SELECT sum(v) FROM saved;').output.contains('42')
	package_success(['--offline', 'upgrade'])!
	package_success(['--offline', 'remove', pkgcore.sqlite_application_id])!
	assert pkgcore.read_state('/var/lib/vinix-packages', architecture)!.packages.len == 0
	assert os.is_file(data) && os.stat(data)!.uid == 1000
	os.rename('/tmp/sqlite-release-math', '/tmp/sqlite-release-hidden')!
	package_success(['--offline', 'install', pkgcore.sqlite_application_id])!
	reinstalled := sqlite_run_sql('SELECT ceil(1.25); SELECT sum(v) FROM saved; PRAGMA integrity_check;')
	assert reinstalled.status == 0 && reinstalled.output.contains('2.0\n42\nok'), reinstalled.output
	package_success(['--offline', 'remove', pkgcore.sqlite_application_id])!
	assert pkgcore.read_state('/var/lib/vinix-packages', architecture)!.packages.len == 0
	assert os.is_file(data)
	t.say('PACKAGE SQLITE runtime-only-real-library-upgrade unchanged-cli rollback offline-cache-reinstall data-preserving-uninstall PASS')
}

fn scenario_packages_sqlite(mut t Test) {
	qualify_package_sqlite(mut t) or { t.check(false, err.msg()) }
}
