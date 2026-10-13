// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import tools.packages.pkgcore

fn composed_probe(path string, grant bool) Ran {
	return media_command(pkgcore.ffprobe_application_id, ['-v', 'error', '-select_streams', 'a:0',
		'-show_entries', 'stream=codec_name,sample_rate,channels', '-of', 'csv=p=0', path], if grant { [path] } else { []string{} })
}

fn composed_media() !string {
	encoded := run(['/usr/bin/vinix-package', 'run-args', pkgcore.ffmpeg_application_id, '--data-cwd', '--',
		'-v', 'error', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=0.1', '-c:a', 'pcm_s16le', '-y', 'combined catalog; $literal.wav'], '', none, none)
	assert encoded.status == 0, encoded.output
	path := '/home/alex/.local/share/vinix-apps/' + pkgcore.ffmpeg_application_id + '/combined catalog; $literal.wav'
	assert os.file_size(path) > 0 && os.stat(path)!.uid == 1000
	probe := composed_probe(path, true)
	assert probe.status == 0 && probe.output.contains('pcm_s16le'), probe.output
	assert composed_probe(path, false).status != 0
	return path
}

fn qualify_package_composition(mut t Test) ! {
	t.make_accounts()
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	key := package_success(['keygen', '/tmp/composed-seed'])!.trim_space()
	expires := time.now().unix() + 3600
	for i, variant in ['base', 'math'] {
		root := '/tmp/composed-roots-' + variant
		os.mkdir(root)!
		os.cp_all('/usr/share/composition-fixtures/sqlite/' + variant, root + '/sqlite', false)!
		os.cp_all('/usr/share/composition-fixtures/media', root + '/media', false)!
		// cp does not preserve executable mode on every guest filesystem.
		for arch in ['aarch64', 'x86_64'] {
			for profile in ['sqlite', 'media'] {
				for directory in ['bin', 'lib'] {
					for path in os.walk_ext(root + '/' + profile + '/' + arch + '/' + directory, '') { os.chmod(path, 0o755)! }
				}
			}
		}
		sqlite := json2.decode[pkgcore.SqliteProfileInfo](package_success(['sqlite-catalog', '3.53.4',
			if variant == 'base' { '1.0.0' } else { '1.1.0' }, root + '/sqlite', '/tmp/composed-sqlite-' + variant])!)!
		media := json2.decode[pkgcore.FfmpegProfileInfo](package_success(['ffmpeg-catalog', '1.0.0', root + '/media', '/tmp/composed-media-' + variant])!)!
		composed := json2.decode[pkgcore.CompositionInfo](package_success(['compose-catalog', '/tmp/composed-lock-' + variant,
			'sqlite', sqlite.catalog, 'media', media.catalog])!)!
		assert composed.architectures == ['aarch64', 'x86_64'] && composed.package_count == 10
		assert composed.sources.map(it.id) == ['media', 'sqlite']
		reversed := json2.decode[pkgcore.CompositionInfo](package_success(['compose-catalog', '/tmp/composed-reversed-' + variant,
			'media', media.catalog, 'sqlite', sqlite.catalog])!)!
		assert composed.catalog_sha256 == reversed.catalog_sha256
		assert os.read_file(composed.directory + '/composition.json')! == os.read_file(reversed.directory + '/composition.json')!
		workspace := '/tmp/composed-workspace-' + variant
		assert json2.decode[pkgcore.CatalogInfo](package_success(['pack-catalog', composed.catalog, root, workspace])!)!.package_count == 10
		released := json2.decode[pkgcore.ReleaseInfo](package_success(['publish-release', workspace, 'composed-fixture',
			'/tmp/composed-seed', (i + 1).str(), expires.str(), '/tmp/composed-release-' + variant])!)!
		assert released.public_key == key && released.package_count == 10
	}
	t.say('PACKAGE COMPOSITION canonical-order scoped-roots pinned-two-target-catalog single-signed-publisher PASS')
	os.mkdir_all('/etc/vinix-packages')!
	os.write_file('/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{ architecture: architecture,
		launch_user: 'alex', policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 } }))!
	os.chmod('/etc/vinix-packages/config.json', 0o644)!
	package_success(['--offline', 'repo-enroll', 'composed-fixture', 'file:///tmp/composed-release-base', key])!
	package_success(['--offline', 'update'])!
	apps := [pkgcore.sqlite_application_id, pkgcore.ffmpeg_application_id, pkgcore.ffprobe_application_id]
	reviewed_package_operation('install', apps)!
	initial := pkgcore.read_state('/var/lib/vinix-packages', architecture)!
	assert initial.packages.len == 5 && initial.requested.len == 3
	assert initial.packages.all(it.repository == 'composed-fixture' && it.public_key == key && it.package.architecture == architecture)
	sql := sqlite_run_sql('PRAGMA journal_mode=WAL; CREATE TABLE saved(v INTEGER); INSERT INTO saved VALUES(42); SELECT sum(v) FROM saved; PRAGMA integrity_check;')
	assert sql.status == 0 && sql.output.contains('wal\n42\nok'), sql.output
	database := '/home/alex/.local/share/vinix-apps/' + pkgcore.sqlite_application_id + '/database.sqlite3'
	assert os.stat(database)!.uid == 1000
	media := composed_media()!
	assert sqlite_run_sql('SELECT ceil(1.25);').status != 0
	t.say('PACKAGE COMPOSITION real-sqlite-wal ffmpeg-audio ffprobe explicit-grants ordinary-owner distinct-runtimes PASS')
	package_success(['--offline', 'repo-enroll', 'composed-fixture', 'file:///tmp/composed-release-math', key])!
	package_success(['--offline', 'update'])!
	view := json2.decode[pkgcore.SoftwareView](package_success(['view'])!)!
	assert view.rows.filter(it.updatable).map(it.id) == [pkgcore.sqlite_runtime_id]
	reviewed_package_operation('upgrade', [])!
	updated := pkgcore.read_state('/var/lib/vinix-packages', architecture)!
	assert updated.packages.len == 5
	for item in initial.packages {
		if item.package.id == pkgcore.sqlite_runtime_id { continue }
		assert updated.packages.filter(it.package.id == item.package.id)[0].package == item.package
	}
	math := sqlite_run_sql('SELECT ceil(1.25); SELECT sum(v) FROM saved; PRAGMA integrity_check;')
	assert math.status == 0 && math.output.contains('2.0\n42\nok'), math.output
	assert composed_probe(media, true).status == 0
	reviewed_package_operation('rollback', [])!
	assert sqlite_run_sql('SELECT ceil(1.25);').status != 0
	assert sqlite_run_sql('SELECT sum(v) FROM saved;').output.contains('42')
	assert composed_probe(media, true).status == 0
	reviewed_package_operation('upgrade', [])!
	reviewed_package_operation('remove', apps)!
	assert pkgcore.read_state('/var/lib/vinix-packages', architecture)!.packages.len == 0
	assert os.is_file(database) && os.is_file(media)
	os.rename('/tmp/composed-release-math', '/tmp/composed-release-hidden')!
	reviewed_package_operation('install', apps)!
	assert pkgcore.read_state('/var/lib/vinix-packages', architecture)!.packages.len == 5
	reinstalled := sqlite_run_sql('SELECT ceil(1.25); SELECT sum(v) FROM saved;')
	assert reinstalled.status == 0 && reinstalled.output.contains('2.0\n42'), reinstalled.output
	assert composed_probe(media, true).status == 0
	reviewed_package_operation('remove', apps)!
	assert pkgcore.read_state('/var/lib/vinix-packages', architecture)!.packages.len == 0
	assert os.stat(database)!.uid == 1000 && os.stat(media)!.uid == 1000
	t.say('PACKAGE COMPOSITION reviewed-runtime-only-upgrade unchanged-media rollback offline-cache-reinstall clean-uninstall retained-data PASS')
}

fn scenario_packages_composition(mut t Test) {
	qualify_package_composition(mut t) or { t.check(false, err.msg()) }
}
