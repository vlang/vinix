// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
	fn C.vinix_heap_count() u32
}

fn ffmpeg_owned_probe(version string, count int, fault string) ! {
	mut plan := ffmpeg_profile_plan(version)
	defer { plan.close(); plan.close() }
	for index in 0 .. count {
		recipe := plan.templates[if fault == 'duplicate' && index == 5 { 0 } else { index }]
		mut files := []Payload{cap: recipe.entries.len}
		defer { unsafe { (&array(&files)).free() } }
		for entry in recipe.entries {
			files << Payload{ path: entry.path, sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
				bytes: 1, executable: ffmpeg_elf_kind(entry.path) != '' }
		}
		text := publisher_json(Package{ ...recipe.manifest, files: files })
		defer { unsafe { text.free() } }
		p := decode_manifest(text, true)!
		plan.packages << CatalogImport{ source: p.architecture, recipe: RootRecipe{ ...recipe, manifest: p } }
	}
	if count == 6 || fault == 'empty' {
		canonical := plan.canonical()!
		defer { unsafe { canonical.free() } }
		plan.close()
		assert canonical.contains('@RUNTIME@/lib/ld-musl-aarch64.so.1') && canonical.contains('sources/ffmpeg.tar.xz')
		mut reply := ffmpeg_profile_result(version, '/review/ffmpeg', canonical)
		reply.close(); reply.close()
	}
}

fn ffmpeg_owned_attempt(version string, count int, fault string) {
	if _ := ffmpeg_owned_probe(version, count, fault) { assert fault == '' }
	else {
		message := err.msg()
		assert message.contains(if fault == 'empty' { 'empty' } else { 'duplicate catalog package' })
		unsafe { message.free(); err.free() }
		assert fault != ''
	}
}

fn test_ffmpeg_owned_templates_partial_inventories_and_canonical_refusals() {
	version := '1.1.0'.clone(); defer { unsafe { version.free() } }
	for selection in 0 .. 9 {
		count := if selection < 7 { selection } else if selection == 7 { 6 } else { 0 }
		fault := if selection < 7 { '' } else if selection == 7 { 'duplicate' } else { 'empty' }
		ffmpeg_owned_attempt(version, count, fault)
		mut maximum := u64(0); mut records := u32(0)
		for _ in 0 .. 128 {
			$if track_heap ? { C.vinix_heap_begin() }
			ffmpeg_owned_attempt(version, count, fault)
			$if track_heap ? {
				kept := C.vinix_heap_end(); allocations := C.vinix_heap_count()
				if kept > maximum { maximum = kept }; if allocations > records { records = allocations }
			}
		}
		$if track_heap ? {
			println('FFMPEG METADATA imports=' + count.str() + ' fault=' + if fault == '' { 'none' } else { fault } +
				' retained=' + maximum.str() + ' allocations=' + records.str())
			assert maximum == 0 && records == 0
		}
	}
	assert version == '1.1.0'
	println('FFMPEG METADATA 1152 cycles retire templates, partial inventories, canonicalization, replies and late refusals PASS')
}

fn test_ffmpeg_owned_independent_replies_survive_caller_retirement() {
	version := '1.1.0'.clone(); directory := '/review/ffmpeg'.clone()
	mut one := ffmpeg_profile_result(version, directory, 'catalog\n')
	mut two := ffmpeg_profile_result(version, directory, 'catalog\n')
	unsafe { version.free(); directory.free() }
	one.close(); one.close()
	assert two.ffmpeg_version == '8.0.1' && two.runtime_version == '1.1.0'
	assert two.directory == '/review/ffmpeg' && two.catalog == '/review/ffmpeg/catalog.json'
	assert two.architectures == ['aarch64', 'x86_64'] && two.catalog_sha256 == index_digest('catalog\n')
	two.close(); two.close()
	assert two.directory == '' && two.runtime_version == '' && two.architectures.len == 0
	println('FFMPEG METADATA independent replies survive caller retirement and close idempotently PASS')
}
