// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore
import os
import time

$if track_heap ? {
#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32
}

fn owned_recipe(architecture string, application bool) RootRecipe {
	return if application {
		RootRecipe{ manifest: Package{ id: 'org.example.win64', version: '1.0.0', architecture: architecture,
			name: 'Reviewed Win64 application', description: 'Explicit publisher-supplied compatibility closure.',
			license: 'Example-EULA', proprietary: true, kind: 'windows', runtime: 'org.example.wine',
			entrypoint: 'bin/wine-runner', arguments: ['@APP@/bin/program.exe', 'literal ; $ argument'],
			permissions: ['files', 'process'], associations: ['text/plain'],
			dependencies: [Dependency{ id: 'org.example.wine', minimum: '1.0.0', before: '2.0.0' }] },
			entries: [RootEntry{ source: 'app/program.exe', path: 'bin/program.exe' },
				RootEntry{ source: 'licenses/application-LICENSE.txt', path: wine_application_notice }] }
	} else {
		RootRecipe{ manifest: Package{ id: 'org.example.wine', version: '1.0.0', architecture: architecture,
			name: 'Reviewed Wine closure', license: 'LGPL-2.1-or-later', kind: 'runtime' },
			entries: [RootEntry{ source: 'runtime/runner', path: 'bin/wine-runner' },
				RootEntry{ source: 'runtime/closure.txt', path: 'share/closure.txt' },
				RootEntry{ source: 'licenses/runtime-LICENSE.txt', path: wine_runtime_notice }] }
	}
}


fn owned_fixture() !string {
	path := os.real_path(os.temp_dir()) + '/vinix-wine-metadata-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	for arch in ['aarch64', 'x86_64']! {
		os.mkdir_all(path + '/' + arch)!
		for role in ['application', 'runtime']! {
			text := publisher_json(owned_recipe(arch, role == 'application'))
			defer { unsafe { text.free() } }
			os.write_file(path + '/' + arch + '/' + role + '.json', text)!
		}
	}
	return path
}

fn owned_probe(recipes string, count int, fault string) ! {
	mut plan := wine_profile_plan(recipes)!
	defer { plan.close(); plan.close() }
	for index in 0 .. count {
		item := plan.imports[if fault == 'duplicate' && index == 3 { 0 } else { index }]
		recipe := item.recipe
		mut files := []Payload{cap: recipe.entries.len}
		defer { unsafe { (&array(&files)).free() } }
		for entry in recipe.entries {
			files << Payload{ path: entry.path, sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', bytes: 1, executable: entry.path == 'bin/wine-runner' }
		}
		text := publisher_json(Package{ ...recipe.manifest, files: files })
		defer { unsafe { text.free() } }
		p := decode_manifest(text, true)!
		plan.packages << CatalogImport{ source: item.architecture, recipe: RootRecipe{ ...recipe, manifest: p } }
	}
	if count == 4 || fault == 'empty' {
		canonical := plan.canonical()!
		defer { unsafe { canonical.free() } }
		mut reply := wine_profile_result(plan.imports[0].recipe.manifest, plan.imports[1].recipe.manifest, '/review/wine', canonical)
		plan.close()
		assert canonical.contains('literal ; $ argument') && canonical.contains('Example-EULA')
		assert reply.application == 'org.example.win64' && reply.runtime == 'org.example.wine'
		reply.close(); reply.close()
	}
}

fn owned_attempt(recipes string, count int, fault string) {
	if _ := owned_probe(recipes, count, fault) { assert fault == '' }
	else {
		message := err.msg()
		assert message.contains(if fault == 'empty' { 'empty' } else { 'duplicate catalog package' })
		unsafe { message.free(); err.free() }; assert fault != ''
	}
}

fn test_wine_owned_templates_partial_manifests_and_canonical_refusals() {
	recipes := owned_fixture()!; defer { os.rmdir_all(recipes) or {}; unsafe { recipes.free() } }
	for selection in 0 .. 7 {
		count := if selection < 5 { selection } else if selection == 5 { 4 } else { 0 }
		fault := if selection < 5 { '' } else if selection == 5 { 'duplicate' } else { 'empty' }
		owned_attempt(recipes, count, fault)
		mut maximum := u64(0); mut records := u32(0)
		for _ in 0 .. 128 {
			$if track_heap ? { C.vinix_heap_begin() }
			owned_attempt(recipes, count, fault)
			$if track_heap ? {
				kept := C.vinix_heap_end(); count_ := C.vinix_heap_count()
				if kept > maximum { maximum = kept }; if count_ > records { records = count_ }
			}
		}
		$if track_heap ? {
			println('WINE METADATA imports=' + count.str() + ' fault=' + if fault == '' { 'none' } else { fault } + ' retained=' + maximum.str() + ' allocations=' + records.str())
			assert maximum == 0 && records == 0
		}
	}
	println('WINE METADATA 896 cycles retire decoded templates, partial manifests, canonicalization, replies and late refusals PASS')
}

fn test_wine_owned_independent_replies_survive_plan_and_caller_retirement() {
	recipes := owned_fixture()!; defer { os.rmdir_all(recipes) or {}; unsafe { recipes.free() } }
	mut plan := wine_profile_plan(recipes)!
	directory := '/review/wine'.clone()
	mut one := wine_profile_result(plan.imports[0].recipe.manifest, plan.imports[1].recipe.manifest, directory, 'catalog\n')
	mut two := wine_profile_result(plan.imports[0].recipe.manifest, plan.imports[1].recipe.manifest, directory, 'catalog\n')
	plan.close(); plan.close(); unsafe { directory.free() }
	one.close(); one.close()
	assert two.application == 'org.example.win64' && two.version == '1.0.0' && two.runtime == 'org.example.wine' && two.runtime_version == '1.0.0'
	assert two.directory == '/review/wine' && two.catalog == '/review/wine/catalog.json' && two.architectures == ['aarch64', 'x86_64']
	assert two.catalog_sha256 == index_digest('catalog\n')
	two.close(); two.close(); assert two.application == '' && two.architectures.len == 0
	println('WINE METADATA independent replies survive plan and caller retirement and close idempotently PASS')
}
