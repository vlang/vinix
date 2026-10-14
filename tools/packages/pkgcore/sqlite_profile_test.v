// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time

fn sqlite_fixture_elf(architecture string, pie bool, shared bool) []u8 {
	mut bytes := []u8{len: 128}
	for i, byte in [u8(127), `E`, `L`, `F`, 2, 1, 1] { bytes[i] = byte }
	bytes[16] = if pie || shared { u8(3) } else { u8(2) }
	bytes[18] = if architecture == 'aarch64' { u8(183) } else { u8(62) }
	bytes[20] = 1
	bytes[32] = 64
	bytes[54] = 56
	bytes[56] = 1
	bytes[64] = if pie { u8(3) } else { u8(1) }
	return bytes
}

fn sqlite_profile_fixture() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-sqlite-profile-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	for architecture in ['aarch64', 'x86_64'] {
		root := work + '/roots/' + architecture
		for directory in ['bin', 'lib', 'licenses'] { os.mkdir_all(root + '/' + directory)! }
		for path, kind in {'bin/sqlite3': 'pie', 'bin/vinix-linux-runner': 'static',
			'lib/libc.so': 'shared', 'lib/libsqlite3.so.0': 'shared'} {
			os.write_file_array(root + '/' + path, sqlite_fixture_elf(architecture, kind == 'pie', kind == 'shared'))!
			os.chmod(root + '/' + path, 0o755)!
		}
		for name in ['sqlite-COPYRIGHT', 'musl-COPYRIGHT', 'vinix-COPYING'] { os.write_file(root + '/licenses/' + name, 'notice ' + name)! }
	}
	return work
}

fn test_sqlite_profile_emits_complete_canonical_pins_and_separate_runtime_with_no_implicit_permissions() {
	work := sqlite_profile_fixture()!
	defer { os.rmdir_all(work) or {} }
	first := sqlite_catalog('3.53.4', '1.0.0', work + '/roots', work + '/first')!
	second := sqlite_catalog('3.53.4', '1.0.0', work + '/roots', work + '/second')!
	assert first.catalog_sha256 == second.catalog_sha256 && first.profile == 'sqlite-cli'
	assert os.ls(work + '/first')! == ['catalog.json']
	assert os.stat(work + '/first')!.mode & 0o777 == 0o700
	recipe := catalog_recipe(read_metadata(first.catalog)!)!
	assert recipe.architectures == ['aarch64', 'x86_64'] && recipe.packages.len == 4
	for item in recipe.packages {
		p := item.recipe.manifest
		assert !p.proprietary && !p.firmware && p.permissions.len == 0 && p.associations.len == 0
		assert p.files.any(it.path.starts_with('licenses/'))
		if p.id == sqlite_application_id {
			assert p.kind == 'linux' && p.runtime == sqlite_runtime_id && p.files.len == 2
			assert p.dependencies == [Dependency{ id: sqlite_runtime_id, minimum: '1.0.0', before: '2.0.0' }]
			assert p.arguments.last() == '@DATA@/database.sqlite3'
		} else {
			assert p.id == sqlite_runtime_id && p.kind == 'runtime' && p.version == '1.0.0' && p.files.len == 7
		}
	}
	workspace := pack_catalog(first.catalog, work + '/roots', work + '/workspace')!
	assert workspace.package_count == 4
	updated := sqlite_catalog('3.53.4', '1.1.0', work + '/roots', work + '/updated')!
	new_recipe := catalog_recipe(read_metadata(updated.catalog)!)!
	assert recipe.packages.filter(it.recipe.manifest.id == sqlite_application_id)
		== new_recipe.packages.filter(it.recipe.manifest.id == sqlite_application_id)
	assert os.ls(work)!.all(!it.starts_with('.vinix-sqlite-profile-'))
}

fn test_sqlite_profile_rejects_wrong_targets_interpreters_and_missing_notices_without_publication() {
	work := sqlite_profile_fixture()!
	defer { os.rmdir_all(work) or {} }
	path := work + '/roots/aarch64/bin/sqlite3'
	original := os.read_bytes(path)!
	mut wrong := original.clone()
	wrong[18] = 62
	mut bad_headers := original.clone()
	bad_headers[56] = 255
	for bytes in [wrong, sqlite_fixture_elf('aarch64', false, false), bad_headers] {
		os.write_file_array(path, bytes)!
		mut refused := false
		sqlite_catalog('3.53.4', '1.0.0', work + '/roots', work + '/failed') or { refused = true }
		assert refused && !os.exists(work + '/failed')
	}
	os.write_file_array(path, original)!
	os.write_file(work + '/roots/x86_64/licenses/musl-COPYRIGHT', '')!
	mut refused := false
	sqlite_catalog('3.53.4', '1.0.0', work + '/roots', work + '/notice') or { refused = err.msg().contains('redistribution notice') }
	assert refused && !os.exists(work + '/notice')
	assert os.ls(work)!.all(!it.starts_with('.vinix-sqlite-profile-'))
}

fn test_sqlite_profile_requires_both_targets_compatible_versions_and_new_destination() {
	work := sqlite_profile_fixture()!
	defer { os.rmdir_all(work) or {} }
	for version in ['0.9.0', '2.0.0', '1.01.0'] {
		mut refused := false
		sqlite_catalog('3.53.4', version, work + '/roots', work + '/version') or { refused = true }
		assert refused && !os.exists(work + '/version')
	}
	sqlite_catalog('3.53.4', '1.0.0', work + '/roots', work + '/occupied')!
	mut refused := false
	sqlite_catalog('3.53.4', '1.0.0', work + '/roots', work + '/occupied') or { refused = err.msg().contains('must be new') }
	assert refused && os.ls(work + '/occupied')! == ['catalog.json']
	os.rename(work + '/roots/x86_64', work + '/saved')!
	os.symlink(work + '/saved', work + '/roots/x86_64')!
	mut linked := false
	sqlite_catalog('3.53.4', '1.0.0', work + '/roots', work + '/link') or { linked = err.msg().contains('ordinary architecture roots') }
	assert linked && !os.exists(work + '/link')
}

fn sqlite_empty_imported_notice(phase string, stage string) ! {
	if phase == 'created' { os.write_file(os.dir(stage) + '/roots/x86_64/licenses/sqlite-COPYRIGHT', '')! }
}

fn sqlite_directory_imported_notice(phase string, stage string) ! {
	if phase != 'created' { return }
	path := os.dir(stage) + '/roots/x86_64/licenses/sqlite-COPYRIGHT'
	os.rm(path)!; os.mkdir(path)!; os.write_file(path + '/nested', 'unexpected notice directory')!
}

fn sqlite_oversized_imported_notice(phase string, stage string) ! {
	if phase != 'created' { return }
	mut file := os.open_file(os.dir(stage) + '/roots/x86_64/licenses/sqlite-COPYRIGHT', 'w', 0o644)!
	defer { file.close() }
	file.seek(1024 * 1024, .start)!; file.write_string('\x00')!
}

fn sqlite_profile_zero_space(_ string) !u64 { return 0 }

fn test_sqlite_profile_rechecks_imported_notices_cleans_failure_and_allows_exact_retry() {
	for checkpoint in [sqlite_empty_imported_notice, sqlite_directory_imported_notice, sqlite_oversized_imported_notice] {
		work := sqlite_profile_fixture()!
		defer { os.rmdir_all(work) or {} }
		path := work + '/roots/x86_64/licenses/sqlite-COPYRIGHT'
		original := os.read_file(path)!
		baseline := sqlite_catalog('3.53.4', '1.0.0', work + '/roots', work + '/baseline')!
		mut denied := false
		sqlite_catalog_with('3.53.4', '1.0.0', work + '/roots', work + '/refused', CatalogOptions{ checkpoint: checkpoint }) or {
			denied = err.msg().contains('unexpected payload path') || err.msg().contains('invalid redistribution/build notice')
		}
		assert denied && !os.exists(work + '/refused')
		assert os.ls(work)!.all(!it.starts_with('.vinix-sqlite-profile-'))
		if os.is_dir(path) { os.rmdir_all(path)! } else { os.rm(path)! }
		os.write_file(path, original)!
		assert sqlite_catalog('3.53.4', '1.0.0', work + '/roots', work + '/refused')!.catalog_sha256 == baseline.catalog_sha256
	}
	work := sqlite_profile_fixture()!
	defer { os.rmdir_all(work) or {} }
	mut full := false
	sqlite_catalog_with('3.53.4', '1.0.0', work + '/roots', work + '/refused', CatalogOptions{ available_space: sqlite_profile_zero_space }) or {
		full = err.msg().contains('insufficient disk space')
	}
	assert full && !os.exists(work + '/refused') && os.ls(work)!.all(!it.starts_with('.vinix-sqlite-profile-'))
}
