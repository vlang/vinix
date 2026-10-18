// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
	fn C.vinix_heap_count() u32
}

fn sqlite_owned_plan_probe(sqlite_version string, runtime_version string, count int, fault string) ! {
	mut plan := sqlite_profile_plan(sqlite_version, runtime_version)
	defer { plan.close(); plan.close() }
	for index in 0 .. count {
		recipe := plan.templates[if fault == 'duplicate' && index == 3 { 0 } else { index }]
		mut files := []Payload{cap: recipe.entries.len}
		defer { unsafe { (&array(&files)).free() } }
		for entry in recipe.entries {
			files << Payload{ path: entry.path, sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
				bytes: 1, executable: !entry.path.starts_with('licenses/') }
		}
		text := publisher_json(Package{ ...recipe.manifest, files: files })
		defer { unsafe { text.free() } }
		p := decode_manifest(text, true)!
		plan.packages << CatalogImport{ source: p.architecture, recipe: RootRecipe{ ...recipe, manifest: p } }
	}
	if count == 4 || fault == 'empty' {
		canonical := plan.canonical()!
		defer { unsafe { canonical.free() } }
		plan.close()
		assert canonical.contains('@RUNTIME@/lib/ld-musl-aarch64.so.1') && canonical.contains('@DATA@/database.sqlite3')
		mut reply := sqlite_profile_result(sqlite_version, runtime_version, '/review/sqlite', canonical)
		reply.close(); reply.close()
	}
}

fn sqlite_owned_attempt(sqlite_version string, runtime_version string, count int, fault string) {
	if _ := sqlite_owned_plan_probe(sqlite_version, runtime_version, count, fault) { assert fault == '' }
	else {
		message := err.msg()
		assert message.contains(if fault == 'empty' { 'empty' } else { 'duplicate catalog package' })
		unsafe { message.free(); err.free() }
		assert fault != ''
	}
}

fn test_sqlite_owned_templates_partial_inventories_and_canonical_refusals() {
	sqlite_version := '3.53.4'.clone(); runtime_version := '1.1.0'.clone()
	defer { unsafe { sqlite_version.free(); runtime_version.free() } }
	for selection in 0 .. 7 {
		count := if selection < 5 { selection } else if selection == 5 { 4 } else { 0 }
		fault := if selection < 5 { '' } else if selection == 5 { 'duplicate' } else { 'empty' }
		sqlite_owned_attempt(sqlite_version, runtime_version, count, fault)
		mut maximum := u64(0); mut records := u32(0)
		for _ in 0 .. 128 {
			$if track_heap ? { C.vinix_heap_begin() }
			sqlite_owned_attempt(sqlite_version, runtime_version, count, fault)
			$if track_heap ? {
				kept := C.vinix_heap_end(); allocations := C.vinix_heap_count()
				if kept > maximum { maximum = kept }; if allocations > records { records = allocations }
			}
		}
		$if track_heap ? {
			println('SQLITE OWNERSHIP imports=' + count.str() + ' fault=' + if fault == '' { 'none' } else { fault } +
				' retained=' + maximum.str() + ' allocations=' + records.str())
			assert maximum == 0 && records == 0
		}
	}
	assert sqlite_version == '3.53.4' && runtime_version == '1.1.0'
	println('SQLITE OWNERSHIP 896 metadata cycles retire templates, partial inventories, canonicalization, replies and late refusals PASS')
}

fn test_sqlite_owned_independent_replies_survive_caller_retirement() {
	sqlite_version := '3.53.4'.clone(); runtime_version := '1.1.0'.clone(); directory := '/review/sqlite'.clone()
	mut one := sqlite_profile_result(sqlite_version, runtime_version, directory, 'catalog\n')
	mut two := sqlite_profile_result(sqlite_version, runtime_version, directory, 'catalog\n')
	unsafe { sqlite_version.free(); runtime_version.free(); directory.free() }
	one.close(); one.close()
	assert two.sqlite_version == '3.53.4' && two.runtime_version == '1.1.0'
	assert two.directory == '/review/sqlite' && two.catalog == '/review/sqlite/catalog.json'
	assert two.architectures == ['aarch64', 'x86_64'] && two.catalog_sha256 == index_digest('catalog\n')
	two.close(); two.close()
	assert two.directory == '' && two.sqlite_version == '' && two.runtime_version == '' && two.architectures.len == 0
	println('SQLITE OWNERSHIP independent replies survive caller retirement and close idempotently PASS')
}
