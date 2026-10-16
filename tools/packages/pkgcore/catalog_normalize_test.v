// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
	fn C.vinix_heap_count() u32
}

fn normalize_document(count int, fault string) string {
	mut imports := []CatalogImport{cap: count}
	for i in 0 .. count {
		digits := i.str(); defer { unsafe { digits.free() } }
		id := if fault in ['duplicate', 'shared-mix'] && i == count - 1 { 'item-0'.clone() } else { 'item-' + digits }
		architecture := if fault in ['coverage', 'shared-mix'] && i == count - 1 { 'aarch64' } else { 'all' }
		dependencies := if fault == 'closure' && i == count - 1 { [Dependency{ id: 'missing' }] }
			else if i > 0 { [Dependency{ id: 'item-0', minimum: '1.0.0', before: '2.0.0' }] } else { []Dependency{} }
		imports << CatalogImport{ source: if fault == 'source' && i == count - 1 { 'profile/../shared' } else if architecture == 'all' { 'profile/shared' } else { 'profile/aarch64' }, recipe: RootRecipe{
			manifest: Package{ id: id, name: 'Fixture ' + id, description: 'd'.repeat(2048), version: '1.0.0', architecture: architecture, kind: 'data',
				license: 'Fixture-EULA', proprietary: true, firmware: true, permissions: if fault == 'permissions' && i == count - 1 { ['files', 'files'] } else { ['files', 'audio'] }, associations: ['text/plain', 'image/png'],
				arguments: ['literal ; $ argument'], dependencies: dependencies,
				files: [Payload{ path: 'share/z', sha256: 'b'.repeat(64), bytes: 1 }, Payload{ path: 'share/a', sha256: 'a'.repeat(64), bytes: 1 }] },
			entries: [RootEntry{ source: 'source/z', path: 'share/z' }, RootEntry{ source: 'source/a', path: if fault == 'selectors' && i == count - 1 { 'share/z' } else { 'share/a' } }] } }
	}
	recipe := CatalogRecipe{ format: 1, architectures: if fault == 'architectures' { ['arm64'] } else { ['x86_64', 'aarch64'] }, packages: imports }
	defer { close_decoded_catalog(recipe) }
	return json2.encode(recipe)
}

fn normalize_once(text string, refused bool) {
	if result := catalog_recipe(text) { close_decoded_catalog(result); assert !refused }
	else { message := err.msg(); unsafe { message.free(); err.free() }; assert refused }
}

fn test_catalog_normalization_retires_complete_results_and_late_refusals() {
	for fault in ['', 'duplicate', 'closure', 'architectures', 'source', 'permissions', 'selectors', 'coverage', 'shared-mix']! {
		for count in [1, 64]! {
			if fault in ['duplicate', 'shared-mix'] && count == 1 { continue }
			text := normalize_document(count, fault); defer { unsafe { text.free() } }
			normalize_once(text, fault != '')
			mut maximum := u64(0); mut allocations := u32(0)
			cycles := if '--catalog-normalize-baseline' in os.args { 10 } else { $if track_heap ? { 1000 } $else { 16 } }
			for _ in 0 .. cycles {
				$if track_heap ? { C.vinix_heap_begin() }
				normalize_once(text, fault != '')
				$if track_heap ? {
					kept := C.vinix_heap_end(); records := C.vinix_heap_count()
					if kept > maximum { maximum = kept }; if records > allocations { allocations = records }
				}
			}
			label := 'CATALOG NORMALIZE imports=' + count.str() + ' fault=' + if fault == '' { 'none' } else { fault }
			$if track_heap ? {
				println(label + ' retained=' + maximum.str() + ' allocations=' + allocations.str())
				if '--catalog-normalize-baseline' !in os.args { assert maximum == 0 && allocations == 0 }
			} $else { println(label + ' functional-cycles=' + cycles.str() + ' PASS') }
		}
	}
	println('CATALOG NORMALIZE complete and refused single/64-import catalogs retire normalization and dependency-closure scratch PASS')
}

fn test_catalog_normalization_owns_sorted_output_after_source_and_other_results_are_retired() {
	text := normalize_document(64, '')
	one := catalog_recipe(text)!
	two := catalog_recipe(text)!
	unsafe { text.free() }
	assert one == two && one.architectures == ['aarch64', 'x86_64']
	for item in one.packages {
		p := item.recipe.manifest
		assert p.files.map(it.path) == ['share/a', 'share/z'] && item.recipe.entries.map(it.path) == ['share/a', 'share/z']
		assert p.permissions == ['audio', 'files'] && p.associations == ['image/png', 'text/plain']
		assert p.proprietary && p.firmware && p.license == 'Fixture-EULA' && p.description == 'd'.repeat(2048)
		assert p.arguments == ['literal ; $ argument']
	}
	canonical := json2.encode(one); defer { unsafe { canonical.free() } }
	close_decoded_catalog(one)
	assert json2.encode(two) == canonical
	close_decoded_catalog(two)
	three := catalog_recipe(canonical)!
	assert json2.encode(three) == canonical
	close_decoded_catalog(three)
	println('CATALOG NORMALIZE independent owned output survives retired source/results with unchanged canonical declarations and ordering PASS')
}
