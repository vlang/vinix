// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time
import tests.packages.elffixture

fn ffmpeg_test_elf(architecture string, kind string) []u8 {
	return elffixture.image(architecture, kind)
}

fn ffmpeg_test_roots() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-ffmpeg-profile-' + time.now().unix_micro().str()
	for architecture in ['aarch64', 'x86_64'] {
		root := work + '/roots/' + architecture
		for directory in ['bin', 'lib', 'licenses', 'sources'] { os.mkdir_all(root + '/' + directory)! }
		for path in ['bin/ffmpeg', 'bin/ffprobe', 'bin/vinix-linux-runner', 'lib/libc.so', ...ffmpeg_libraries] {
			os.write_file_array(root + '/' + path, ffmpeg_test_elf(architecture, ffmpeg_elf_kind(path)))!
			os.chmod(root + '/' + path, 0o755)!
		}
		for path in ffmpeg_notices { os.write_file(root + '/' + path, 'notice ' + path)! }
		mut file := os.open_file(root + '/sources/ffmpeg.tar.xz', 'w', 0o644)!
		file.seek(i64(ffmpeg_source_bytes) - 1, .start)!
		file.write_string('\x00')!
		file.close()
	}
	return work
}

fn test_ffmpeg_templates_disclose_permissions_source_and_complete_runtime_closure() {
	mut imports := []CatalogImport{}
	for architecture in ['aarch64', 'x86_64'] {
		for recipe in ffmpeg_templates(architecture, '1.0.0') {
			p := recipe.manifest
			assert !p.firmware && !p.proprietary && p.associations.len == 0
			assert recipe.entries.any(it.path == 'licenses/ffmpeg-COPYING.LGPLv2.1')
			if p.kind == 'runtime' {
				assert p.id == ffmpeg_runtime_id && p.permissions.len == 0
				assert recipe.entries.len == 20 && recipe.entries.any(it.path == 'sources/ffmpeg.tar.xz')
			} else {
				assert p.kind == 'linux' && p.version == '8.0.1' && p.permissions == ['files']
				assert p.runtime == ffmpeg_runtime_id && p.entrypoint == 'bin/vinix-linux-runner'
				assert p.dependencies == [Dependency{ id: ffmpeg_runtime_id, minimum: '1.0.0', before: '2.0.0' }]
			}
			files := recipe.entries.map(Payload{ path: it.path, bytes: 1, sha256: '01'.repeat(32), executable: ffmpeg_elf_kind(it.path) != '' })
			imports << CatalogImport{ source: architecture, recipe: RootRecipe{ ...recipe, manifest: Package{ ...p, files: files } } }
		}
	}
	release_closures(Index{ repository: 'fixture', sequence: 1, packages: imports.map(it.recipe.manifest) }, '01'.repeat(32))!
}

fn test_ffmpeg_profile_refuses_wrong_targets_links_notices_versions_and_unpinned_sources_atomically() {
	work := ffmpeg_test_roots()!
	defer { os.rmdir_all(work) or {} }
	for version in ['0.9.0', '2.0.0', '1.01.0'] {
		mut denied := false
		ffmpeg_catalog(version, work + '/roots', work + '/version') or { denied = true }
		assert denied && !os.exists(work + '/version')
	}
	path := work + '/roots/aarch64/bin/ffprobe'
	for kind in ['static', 'shared'] {
		os.write_file_array(path, ffmpeg_test_elf('aarch64', kind))!
		mut denied := false
		ffmpeg_catalog('1.0.0', work + '/roots', work + '/wrong') or { denied = true }
		assert denied && !os.exists(work + '/wrong')
	}
	os.write_file_array(path, ffmpeg_test_elf('x86_64', 'pie'))!
	mut target_denied := false
	ffmpeg_catalog('1.0.0', work + '/roots', work + '/target') or { target_denied = err.msg().contains('wrong ELF target/type') }
	assert target_denied && !os.exists(work + '/target')
	os.write_file_array(path, ffmpeg_test_elf('aarch64', 'pie'))!
	os.write_file(work + '/roots/x86_64/licenses/ffmpeg-COPYING.LGPLv2.1', '')!
	mut notice_denied := false
	ffmpeg_catalog('1.0.0', work + '/roots', work + '/notice') or { notice_denied = err.msg().contains('redistribution/build notice') }
	assert notice_denied && !os.exists(work + '/notice')
	os.write_file(work + '/roots/x86_64/licenses/ffmpeg-COPYING.LGPLv2.1', 'notice')!
	mut pin_denied := false
	ffmpeg_catalog('1.0.0', work + '/roots', work + '/pin') or { pin_denied = err.msg().contains('source archive differs') }
	assert pin_denied && !os.exists(work + '/pin')
	assert os.ls(work)!.all(!it.starts_with('.vinix-ffmpeg-profile-'))
	os.rename(work + '/roots/x86_64', work + '/saved')!
	os.symlink(work + '/saved', work + '/roots/x86_64')!
	mut link_denied := false
	ffmpeg_catalog('1.0.0', work + '/roots', work + '/link') or { link_denied = err.msg().contains('ordinary architecture roots') }
	assert link_denied && !os.exists(work + '/link')
	os.mkdir(work + '/occupied')!
	mut occupied := false
	ffmpeg_catalog('1.0.0', work + '/roots', work + '/occupied') or { occupied = err.msg().contains('must be new') }
	assert occupied && os.ls(work + '/occupied')!.len == 0
}

fn ffmpeg_directory_imported_source(phase string, stage string) ! {
	if phase != 'created' { return }
	path := os.dir(stage) + '/roots/aarch64/sources/ffmpeg.tar.xz'
	os.rm(path)!; os.mkdir(path)!; os.write_file(path + '/nested', 'unexpected source directory')!
}

fn ffmpeg_empty_imported_notice(phase string, stage string) ! {
	if phase == 'created' { os.write_file(os.dir(stage) + '/roots/aarch64/licenses/ffmpeg-COPYING.LGPLv2.1', '')! }
}

fn ffmpeg_empty_imported_build_record(phase string, stage string) ! {
	if phase == 'created' { os.write_file(os.dir(stage) + '/roots/aarch64/sources/build.json', '')! }
}

fn ffmpeg_oversized_imported_notice(phase string, stage string) ! {
	if phase != 'created' { return }
	mut file := os.open_file(os.dir(stage) + '/roots/aarch64/licenses/ffmpeg-COPYING.LGPLv2.1', 'w', 0o644)!
	defer { file.close() }
	file.seek(1024 * 1024, .start)!; file.write_string('\x00')!
}

fn ffmpeg_profile_zero_space(_ string) !u64 { return 0 }

fn ffmpeg_imported_invalid_entry(phase string, stage string) ! {
	if phase != 'created' { return }
	mut bytes := elffixture.image('aarch64', 'pie')
	elffixture.put(mut bytes, 24, 0x100200)
	os.write_file_array(os.dir(stage) + '/roots/aarch64/bin/ffmpeg', bytes)!
}

fn test_ffmpeg_profile_rechecks_imported_entry_before_source_pin_admission() {
	work := ffmpeg_test_roots()!
	defer { os.rmdir_all(work) or {} }
	mut refused := false
	ffmpeg_catalog_with('1.0.0', work + '/roots', work + '/refused', CatalogOptions{ checkpoint: ffmpeg_imported_invalid_entry }) or {
		refused = err.msg().contains('imported') && err.msg().contains('executable entry')
	}
	assert refused && !os.exists(work + '/refused')
	assert os.ls(work)!.all(!it.starts_with('.vinix-ffmpeg-profile-'))
}

fn test_ffmpeg_profile_requires_the_imported_source_filename_and_complete_bounded_notices() {
	for checkpoint in [ffmpeg_directory_imported_source, ffmpeg_empty_imported_notice,
		ffmpeg_empty_imported_build_record, ffmpeg_oversized_imported_notice] {
		work := ffmpeg_test_roots()!
		defer { os.rmdir_all(work) or {} }
		mut denied := false
		ffmpeg_catalog_with('1.0.0', work + '/roots', work + '/refused', CatalogOptions{ checkpoint: checkpoint }) or {
			// Synthetic source bytes are intentionally unpinned. These checks
			// must fail on the mutated inventory before reaching its hash check.
			denied = err.msg().contains('unexpected payload path') || err.msg().contains('invalid redistribution/build notice')
		}
		assert denied && !os.exists(work + '/refused')
		assert os.ls(work)!.all(!it.starts_with('.vinix-ffmpeg-profile-'))
	}
	work := ffmpeg_test_roots()!
	defer { os.rmdir_all(work) or {} }
	mut full := false
	ffmpeg_catalog_with('1.0.0', work + '/roots', work + '/refused', CatalogOptions{ available_space: ffmpeg_profile_zero_space }) or {
		full = err.msg().contains('insufficient disk space')
	}
	assert full && !os.exists(work + '/refused') && os.ls(work)!.all(!it.starts_with('.vinix-ffmpeg-profile-'))
}
