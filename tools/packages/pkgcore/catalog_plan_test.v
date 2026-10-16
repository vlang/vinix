// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import json2

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
	fn C.vinix_heap_count() u32
}

fn catalog_plan_fixture(count int, fault string) string {
	mut imports := []CatalogImport{cap: count}
	for i in 0 .. count {
		id := 'item-' + i.str()
		mut files := []Payload{cap: 2}
		for path in ['one', 'two']! {
			digest := if fault == 'unique' { sha256.sum((id + path).bytes()).hex() } else { 'a'.repeat(64) }
			files << Payload{ path: path, sha256: digest, bytes: if fault == 'length' && i == count - 1 && path == 'two' { 12 } else { 11 } }
		}
		imports << CatalogImport{ source: if fault == 'depth' && i == count - 1 { 'a/b/c/d/e/f/g/h/shared' } else { 'shared' }, recipe: RootRecipe{
			manifest: Package{ id: id, name: id.clone(), architecture: 'all', version: '1.0.0', kind: 'data', description: 'd'.repeat(2048),
				license: 'Fixture-EULA', proprietary: true, firmware: true, permissions: ['files'], associations: ['text/plain'],
				dependencies: if fault == 'closure' && i == count - 1 { [Dependency{ id: 'missing' }] } else { []Dependency{} }, files: files },
			entries: [RootEntry{ source: 'one', path: 'one' }, RootEntry{ source: 'two', path: 'two' }] } }
	}
	recipe := CatalogRecipe{ format: 1, architectures: if fault == 'architecture' { ['arm64'] } else { ['x86_64', 'aarch64'] }, packages: imports }
	defer { close_decoded_catalog(recipe) }
	text := json2.encode(recipe)
	if fault == 'schema' { return text.replace_once('"format":1', '"format":1,"unknown":true') }
	return text
}

fn catalog_plan_probe(text string) ! {
	mut plan := prepare_catalog(text)!
	defer { plan.close() }
}

fn catalog_plan_attempt(text string, refused bool) {
	if _ := catalog_plan_probe(text) { assert !refused }
	else { message := err.msg(); unsafe { message.free(); err.free() }; assert refused }
}

fn test_catalog_workspace_planning_retires_budget_and_decoded_owners() {
	for count in [1, 64]! {
		for fault in ['', 'unique', 'length', 'schema', 'architecture', 'depth', 'closure']! {
			text := catalog_plan_fixture(count, fault)
			defer { unsafe { text.free() } }
			refused := fault !in ['', 'unique']
			catalog_plan_attempt(text, refused)
			mut maximum := u64(0); mut allocations := u32(0)
			cycles := $if track_heap ? { 128 } $else { 4 }
			for _ in 0 .. cycles {
				$if track_heap ? { C.vinix_heap_begin() }
				catalog_plan_attempt(text, refused)
				$if track_heap ? {
					kept := C.vinix_heap_end(); records := C.vinix_heap_count()
					if kept > maximum { maximum = kept }; if records > allocations { allocations = records }
				}
			}
			label := 'CATALOG PLAN imports=' + count.str() + ' fault=' + if fault == '' { 'none' } else { fault }
			$if track_heap ? {
				println(label + ' retained=' + maximum.str() + ' allocations=' + allocations.str())
				assert maximum == 0 && allocations == 0
			} $else { println(label + ' functional-cycles=' + cycles.str() + ' PASS') }
		}
	}
	println('CATALOG PLAN owned metadata/budget planning and schema/architecture/depth/closure/object-length refusals PASS')
}

fn test_catalog_plan_matches_legacy_bytes_budget_and_owns_result_independently() {
	for count in [1, 64]! {
		for fault in ['', 'unique']! {
			text := catalog_plan_fixture(count, fault)
			mut first := prepare_catalog(text)!
			mut second := prepare_catalog(text)!
			// Compare the original encoder/budget formula against the real plan.
			legacy := catalog_recipe(text)!
			canonical := json2.encode(legacy) + '\n'
			assert first.text == canonical
			mut needed := u64(4 * 1024 * 1024 + canonical.len + 8192)
			for item in legacy.packages {
				manifest := json2.encode(item.recipe.manifest)
				needed += u64(manifest.len + 1 + 8192)
				unsafe { manifest.free() }
			}
			objects := if fault == '' { 1 } else { count * 2 }
			assert first.objects.len == objects && first.needed == needed + u64(objects * (11 + 8192)) && first.scratch == 22 + 2 * 8192
			close_decoded_catalog(legacy)
			unsafe { canonical.free(); text.free() }
			directory := '/review/' + count.str()
			mut info := first.result(directory)
			unsafe { directory.free() }
			first.close(); first.close()
			assert second.recipe.packages.len == count && second.recipe.packages.all(it.recipe.manifest.firmware && it.recipe.manifest.proprietary)
			assert second.recipe.packages.all(it.recipe.manifest.license == 'Fixture-EULA' && it.recipe.manifest.permissions == ['files'] && it.recipe.manifest.associations == ['text/plain'])
			second.close()
			assert info.directory == '/review/' + count.str() && info.architectures == ['aarch64', 'x86_64'] && info.package_count == count
			assert info.object_count == objects && info.catalog_sha256.len == 64
			info.close(); info.close()
			assert info.directory == '' && info.catalog_sha256 == '' && info.architectures.len == 0 && info.package_count == 0
		}
	}
	println('CATALOG PLAN legacy bytes, deduplicated workspace/largest-package budgets, disclosures and independent idempotently closeable results PASS')
}
