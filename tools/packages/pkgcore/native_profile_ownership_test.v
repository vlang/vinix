// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time
import tests.packages.elffixture

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
	fn C.vinix_heap_count() u32
}

fn native_owned_fixture() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-native-owned-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	for architecture in ['aarch64', 'x86_64']! {
		root := work + '/roots/' + architecture
		os.mkdir_all(root + '/bin')!
		os.mkdir_all(root + '/licenses')!
		bytes := elffixture.image(architecture, 'static')
		for name in ['package-hello', 'counter', 'memo']! {
			os.write_file_array(root + '/bin/' + name, bytes)!
			os.chmod(root + '/bin/' + name, 0o755)!
		}
		for name in ['application-sdk-MIT.txt', 'v-MIT.txt', 'musl-MIT.txt']! { os.write_file(root + '/licenses/' + name, name)! }
	}
	return work
}

fn test_native_owned_complete_build_preserves_catalog_and_reports_remaining_filesystem_scratch() {
	work := native_owned_fixture()!
	defer { os.rmdir_all(work) or {} }
	roots := work + '/roots'; target := work + '/lock'
	$if track_heap ? { C.vinix_heap_begin() }
	mut info := native_catalog('1.0.0', roots, target)!
	info.close(); info.close()
	$if track_heap ? {
		kept := C.vinix_heap_end(); count := C.vinix_heap_count()
		println('NATIVE OWNERSHIP whole-build retained=' + kept.str() + ' allocations=' + count.str())
		// The first build includes lazy JSON field metadata. The complete-call
		// owner is measured after initialization in native_builder_ownership_test.
		assert kept < 400000 && count < 1600
	}
	text := os.read_file(target + '/catalog.json')!
	assert index_digest(text) == '249d6bfb150918c4586f86d68da6b6394800d150f7385c3654fadb7ab19a3fce'
	if golden := os.getenv_opt('VINIX_NATIVE_OWNERSHIP_GOLDEN') { assert text == os.read_file(golden)! }
	assert os.ls(work)!.sorted() == ['lock', 'roots']
	println('NATIVE OWNERSHIP complete build preserves baseline canonical bytes and retires reply without removing published lock PASS')
}

fn native_owned_plan_probe(version string, count int, fault string) ! {
	mut plan := native_profile_plan(version)
	defer { plan.close(); plan.close() }
	for index in 0 .. count {
		recipe := plan.templates[if fault == 'duplicate' && index == 5 { 0 } else { index }]
		mut files := []Payload{cap: 4}
		defer { unsafe { (&array(&files)).free() } }
		for entry in recipe.entries {
			files << Payload{ path: entry.path, sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
				bytes: 1, executable: entry.path == recipe.manifest.entrypoint }
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
		assert canonical.contains('org.vinix.counter') && canonical.contains('licenses/musl-MIT.txt')
		mut reply := native_profile_result(version, '/review/native', canonical)
		reply.close(); reply.close()
	}
}

fn native_owned_attempt(version string, count int, fault string) {
	if _ := native_owned_plan_probe(version, count, fault) { assert fault == '' }
	else {
		message := err.msg()
		assert message.contains(if fault == 'empty' { 'empty' } else { 'duplicate catalog package' })
		unsafe { message.free(); err.free() }
		assert fault != ''
	}
}

fn test_native_owned_plans_retire_partial_imports_canonicalization_and_late_refusals() {
	version := '1.0.0'.clone()
	defer { unsafe { version.free() } }
	for selection in 0 .. 9 {
		count := if selection < 7 { selection } else if selection == 7 { 6 } else { 0 }
		fault := if selection < 7 { '' } else if selection == 7 { 'duplicate' } else { 'empty' }
		native_owned_attempt(version, count, fault)
		mut maximum := u64(0); mut records := u32(0)
		cycles := $if track_heap ? { 128 } $else { 4 }
		for _ in 0 .. cycles {
			$if track_heap ? { C.vinix_heap_begin() }
			native_owned_attempt(version, count, fault)
			$if track_heap ? {
				kept := C.vinix_heap_end(); allocations := C.vinix_heap_count()
				if kept > maximum { maximum = kept }; if allocations > records { records = allocations }
			}
		}
		$if track_heap ? {
			println('NATIVE OWNERSHIP imports=' + count.str() + ' fault=' + if fault == '' { 'none' } else { fault } +
				' retained=' + maximum.str() + ' allocations=' + records.str())
			assert maximum == 0 && records == 0
		}
	}
	assert version == '1.0.0'
	println('NATIVE OWNERSHIP templates, partial inventories, canonicalization and late refusals retire all owned metadata PASS')
}

fn test_native_owned_reply_and_canonical_bytes_survive_plan_and_argument_retirement() {
	version := '1.0.0'.clone(); directory := '/review/native'.clone()
	mut one := native_profile_result(version, directory, 'catalog\n')
	mut two := native_profile_result(version, directory, 'catalog\n')
	unsafe { version.free(); directory.free() }
	one.close(); one.close()
	assert two.version == '1.0.0' && two.directory == '/review/native' && two.catalog == '/review/native/catalog.json'
	assert two.architectures == ['aarch64', 'x86_64'] && two.catalog_sha256 == index_digest('catalog\n')
	two.close(); two.close()
	assert two.directory == '' && two.version == '' && two.architectures.len == 0
	println('NATIVE OWNERSHIP independent replies survive caller retirement and close idempotently PASS')
}
