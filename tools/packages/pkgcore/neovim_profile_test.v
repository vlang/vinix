// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time
import tests.packages.elffixture

fn neovim_fixture() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-neovim-profile-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	for arch in ['aarch64', 'x86_64'] {
		root := work + '/roots/' + arch
		for directory in ['bin', 'lib', 'licenses', 'sources', 'share/nvim/runtime'] { os.mkdir_all(root + '/' + directory)! }
		for path in ['bin/nvim', 'bin/vinix-neovim-runner'] {
			os.write_file_array(root + '/' + path, elffixture.image(arch, neovim_kind(path)))!
			os.chmod(root + '/' + path, 0o755)!
		}
		for path in neovim_notices { os.write_file(root + '/' + path, 'fixture notice')! }
		for name, _ in neovim_archives { os.write_file(root + '/sources/' + name + '.tar.gz', 'intentionally not an upstream source')! }
		for path in neovim_runtime_required {
			os.mkdir_all(os.dir(root + '/share/nvim/runtime/' + path))!
			os.write_file(root + '/share/nvim/runtime/' + path, 'runtime fixture')!
		}
	}
	return work
}

fn neovim_refusal(work string, expected string, options CatalogOptions) ! {
	mut refused := false
	neovim_catalog_with('1.0.0', work + '/roots', work + '/lock', options) or {
		refused = err.msg().contains(expected)
		assert refused, err.msg()
	}
	assert refused && !os.exists(work + '/lock')
	assert os.ls(work)!.all(!it.starts_with('.vinix-neovim-profile-'))
}

fn neovim_empty_runtime_after_preflight(phase string, stage string) ! {
	if phase == 'created' { os.write_file(os.dir(stage) + '/roots/aarch64/share/nvim/runtime/doc/help.txt', '')! }
}

fn neovim_executable_runtime_after_preflight(phase string, stage string) ! {
	if phase == 'created' { os.chmod(os.dir(stage) + '/roots/aarch64/share/nvim/runtime/doc/help.txt', 0o755)! }
}

fn neovim_large_notice_after_preflight(phase string, stage string) ! {
	if phase != 'created' { return }
	mut file := os.open_file(os.dir(stage) + '/roots/aarch64/sources/build.json', 'w', 0o644)!
	defer { file.close() }
	file.seek(1024 * 1024, .start)!; file.write_string('x')!
}

fn neovim_zero_space(_ string) !u64 { return 0 }

struct NeovimCheckpointCase {
	checkpoint fn (string, string) ! @[required]
	expected string
}

fn test_neovim_admission_rechecks_runtime_and_notices_after_preflight_and_rolls_back() {
	for case in [
		NeovimCheckpointCase{neovim_empty_runtime_after_preflight, 'complete runtime data'},
		NeovimCheckpointCase{neovim_executable_runtime_after_preflight, 'must not be executable'},
		NeovimCheckpointCase{neovim_large_notice_after_preflight, 'redistribution/build notices'},
	] {
		work := neovim_fixture()!
		defer { os.rmdir_all(work) or {} }
		neovim_refusal(work, case.expected, CatalogOptions{checkpoint: case.checkpoint})!
	}
}

fn test_neovim_admission_requires_real_source_pins_and_confined_complete_roots() {
	work := neovim_fixture()!
	defer { os.rmdir_all(work) or {} }
	neovim_refusal(work, 'source archive differs', CatalogOptions{})!
	neovim_refusal(work, 'insufficient disk space', CatalogOptions{available_space: neovim_zero_space})!
	for version in ['0.9.0', '2.0.0', '1.01.0'] {
		mut refused := false
		neovim_catalog(version, work + '/roots', work + '/version') or { refused = true }
		assert refused && !os.exists(work + '/version')
	}
	os.write_file_array(work + '/roots/aarch64/bin/nvim', elffixture.image('x86_64', 'static'))!
	neovim_refusal(work, 'wrong ELF target/type', CatalogOptions{})!
	os.write_file_array(work + '/roots/aarch64/bin/nvim', elffixture.image('aarch64', 'pie'))!
	neovim_refusal(work, 'wrong ELF target/type', CatalogOptions{})!
	mut dynamic := elffixture.image('aarch64', 'shared')
	dynamic[16] = 2; elffixture.put(mut dynamic, 24, 0x100100)
	os.write_file_array(work + '/roots/aarch64/bin/nvim', dynamic)!
	neovim_refusal(work, 'static runner contains PT_DYNAMIC', CatalogOptions{})!
	os.write_file_array(work + '/roots/aarch64/bin/nvim', elffixture.image('aarch64', 'static'))!
	os.rename(work + '/roots/x86_64', work + '/saved')!
	os.symlink(work + '/saved', work + '/roots/x86_64')!
	neovim_refusal(work, 'ordinary architecture roots', CatalogOptions{})!
	os.mkdir(work + '/occupied')!
	mut refused := false
	neovim_catalog('1.0.0', work + '/roots', work + '/occupied') or { refused = err.msg().contains('must be new') }
	assert refused && os.ls(work + '/occupied')!.len == 0
}

fn test_neovim_runtime_tree_bounds_prevent_unbounded_recursion() {
	work := neovim_fixture()!
	defer { os.rmdir_all(work) or {} }
	mut path := work + '/roots/aarch64/share/nvim/runtime'
	for _ in 0 .. max_pack_depth + 1 { path += '/nested'; os.mkdir(path)! }
	neovim_refusal(work, 'import limits', CatalogOptions{})!
}
