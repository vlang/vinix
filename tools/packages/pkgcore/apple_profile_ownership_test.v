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

fn owned_info(id string) string {
	return '<plist><dict><key>CFBundleIdentifier</key><string>' + id + '</string><key>CFBundleExecutable</key><string>Example</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>'
}

fn owned_recipe(application bool) RootRecipe {
	return if application {
		RootRecipe{ manifest: Package{ id: 'org.example.apple', version: '1.0.0', architecture: 'aarch64',
			name: 'Reviewed Apple application', description: 'Publisher-supplied iOS bundle and isolated runtime.',
			license: 'Example-EULA', proprietary: true, kind: 'apple', runtime: 'org.example.ios-runtime',
			entrypoint: 'bin/run-ios', arguments: ['@APP@/Example.app/Example', 'literal ; $ argument'],
			permissions: ['files', 'process'], associations: ['text/plain'],
			dependencies: [Dependency{ id: 'org.example.ios-runtime', minimum: '1.0.0', before: '2.0.0' }] },
			entries: [RootEntry{ source: 'app/Example', path: 'Example.app/Example' },
				RootEntry{ source: 'app/Info.plist', path: 'Example.app/Info.plist' },
				RootEntry{ source: 'licenses/application-LICENSE.txt', path: apple_application_notice }] }
	} else {
		RootRecipe{ manifest: Package{ id: 'org.example.ios-runtime', version: '1.0.0', architecture: 'aarch64',
			name: 'Reviewed iOS runtime closure', license: 'GPL-2.0-or-later AND MIT', kind: 'runtime' },
			entries: [RootEntry{ source: 'runtime/runner', path: 'bin/run-ios' },
				RootEntry{ source: 'runtime/closure.txt', path: 'share/closure.txt' },
				RootEntry{ source: 'licenses/runtime-LICENSE.txt', path: apple_runtime_notice }] }
	}
}

fn owned_fixture() !string {
	path := os.real_path(os.temp_dir()) + '/vinix-apple-metadata-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	for arch in ['aarch64']! {
		os.mkdir_all(path + '/' + arch)!
		for role in ['application', 'runtime']! {
			text := publisher_json(owned_recipe(role == 'application'))
			defer { unsafe { text.free() } }
			os.write_file(path + '/' + arch + '/' + role + '.json', text)!
		}
	}
	return path
}

fn owned_probe(recipes string, count int, fault string) ! {
	mut plan := apple_profile_plan(recipes)!
	defer { plan.close(); plan.close() }
	for index in 0 .. count {
		recipe := plan.imports[if fault == 'duplicate' && index == 1 { 0 } else { index }]
		mut files := []Payload{cap: recipe.entries.len}
		defer { unsafe { (&array(&files)).free() } }
		for entry in recipe.entries {
			files << Payload{ path: entry.path, sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', bytes: 1, executable: entry.path == 'bin/run-ios' }
		}
		text := publisher_json(Package{ ...recipe.manifest, files: files })
		defer { unsafe { text.free() } }
		p := decode_manifest(text, true)!
		plan.packages << CatalogImport{ source: 'aarch64', recipe: RootRecipe{ ...recipe, manifest: p } }
	}
	if count == 2 || fault == 'empty' {
		canonical := plan.canonical()!
		defer { unsafe { canonical.free() } }
		mut reply := apple_profile_result(plan.imports[0].manifest, plan.imports[1].manifest, '/review/apple', canonical)
		plan.close()
		assert canonical.contains('literal ; $ argument') && canonical.contains('Example-EULA')
		assert reply.application == 'org.example.apple' && reply.runtime == 'org.example.ios-runtime'
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

fn test_apple_owned_templates_partial_manifests_and_canonical_refusals() {
	recipes := owned_fixture()!; defer { os.rmdir_all(recipes) or {}; unsafe { recipes.free() } }
	for selection in 0 .. 5 {
		count := if selection < 3 { selection } else if selection == 3 { 2 } else { 0 }
		fault := if selection < 3 { '' } else if selection == 3 { 'duplicate' } else { 'empty' }
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
			println('APPLE METADATA imports=' + count.str() + ' fault=' + if fault == '' { 'none' } else { fault } + ' retained=' + maximum.str() + ' allocations=' + records.str())
			assert maximum == 0 && records == 0
		}
	}
	println('APPLE METADATA 640 cycles retire decoded templates, partial manifests, canonicalization, replies and late refusals PASS')
}

fn test_apple_owned_independent_replies_survive_plan_and_caller_retirement() {
	recipes := owned_fixture()!; defer { os.rmdir_all(recipes) or {}; unsafe { recipes.free() } }
	mut plan := apple_profile_plan(recipes)!
	directory := '/review/apple'.clone()
	mut one := apple_profile_result(plan.imports[0].manifest, plan.imports[1].manifest, directory, 'catalog\n')
	mut two := apple_profile_result(plan.imports[0].manifest, plan.imports[1].manifest, directory, 'catalog\n')
	plan.close(); plan.close(); unsafe { directory.free() }
	one.close(); one.close()
	assert two.application == 'org.example.apple' && two.version == '1.0.0' && two.runtime == 'org.example.ios-runtime' && two.runtime_version == '1.0.0'
	assert two.directory == '/review/apple' && two.catalog == '/review/apple/catalog.json' && two.architectures == ['aarch64']
	assert two.catalog_sha256 == index_digest('catalog\n')
	two.close(); two.close(); assert two.application == '' && two.architectures.len == 0
	println('APPLE METADATA independent replies survive plan and caller retirement and close idempotently PASS')
}
