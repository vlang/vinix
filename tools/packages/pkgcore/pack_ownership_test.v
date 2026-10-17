// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
	fn C.vinix_heap_count() u32
}

fn pack_owned_fixture(count int) !(string, string, string, string) {
	work := os.real_path(os.temp_dir()) + '/vinix-pack-owned-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	root := work + '/source'; manifest := work + '/manifest.json'; repository := work + '/repository'
	os.mkdir_all(root + '/d')!
	for index in 0 .. count {
		digits := index.str(); path := root + '/d/data-' + digits; payload := 'payload-' + digits
		defer { unsafe { digits.free(); path.free(); payload.free() } }
		os.write_file(path, payload)!
	}
	p := Package{ id: 'fixture', name: 'Fixture', version: '1.0.0', architecture: 'all', kind: 'data', license: 'MIT',
		permissions: ['files'], arguments: ['--literal', 'a b'], associations: ['text/plain'],
		files: [Payload{ path: 'ignored/template', sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', bytes: 7 }] }
	text := publisher_json(p)
	defer { close_decoded_package(p); unsafe { text.free() } }
	os.write_file(manifest, text)!
	return work, root, manifest, repository
}

fn pack_owned_refuse(phase string, relative string) ! {
	if phase == 'hashed' && relative == 'd/data-9' { return error('injected late packing refusal') }
}
fn pack_owned_copied(phase string, relative string) ! {
	if phase == 'copied' && relative == 'd/data-9' { return error('injected late packing refusal') }
}
fn pack_owned_cached(phase string, relative string) ! {
	if phase == 'cached' && relative == 'd/data-9' { return error('injected late packing refusal') }
}
fn pack_owned_locked(phase string, _ string) ! {
	if phase == 'locked' { return error('injected late packing refusal') }
}

fn pack_owned_once(root string, manifest string, repository string, options PackSourceOptions, refused bool) ! {
	if result := pack_with(manifest, root, repository, options) {
		mut p := result
		p.close(); p.close()
		assert !refused
	} else {
		message := err.msg()
		assert refused && message.contains('injected late packing refusal')
		unsafe { message.free(); err.free() }
	}
}

fn pack_owned_walk(root string, repository string, options PackSourceOptions, refused bool) ! {
	fd := C.open(root.str, C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
	assert fd >= 0
	defer { C.close(fd) }
	mut source := PackSource{ repository: repository, options: options }
	defer { source.close(); source.close() }
	if _ := source.walk(fd, '', 0) { assert !refused }
	else {
		message := err.msg(); assert refused && message.contains('injected late packing refusal')
		unsafe { message.free(); err.free() }
	}
}

fn test_pack_owned_cold_cached_walks_and_late_refusals_retire_every_inventory() {
	for count in [16, 64]! {
		work, root, manifest, repository := pack_owned_fixture(count)!
		defer { os.rmdir_all(work) or {}; unsafe { work.free(); root.free(); manifest.free(); repository.free() } }
		objects := repository + '/objects'
		defer { unsafe { objects.free() } }
		for cold in [false, true]! {
			pack_owned_once(root, manifest, repository, PackSourceOptions{}, false)!
			for mode in ['complete', 'hashed', 'copied-or-cached']! {
				options := PackSourceOptions{ checkpoint: if mode == 'hashed' { pack_owned_refuse }
					else if mode == 'copied-or-cached' { if cold { pack_owned_copied } else { pack_owned_cached } }
					else { mirror_no_checkpoint } }
				cycles := $if track_heap ? { if cold { 8 } else { 128 } } $else { 2 }
				mut maximum := u64(0); mut records := u32(0)
				for _ in 0 .. cycles {
					if cold { os.rmdir_all(objects)!; os.mkdir(objects)! }
					$if track_heap ? { C.vinix_heap_begin() }
					pack_owned_walk(root, repository, options, mode != 'complete')!
					$if track_heap ? {
						kept := C.vinix_heap_end(); allocations := C.vinix_heap_count()
						if kept > maximum { maximum = kept }; if allocations > records { records = allocations }
					}
				}
				$if track_heap ? {
					println('PACK OWNERSHIP walk files=' + count.str() + ' cold=' + cold.str() + ' mode=' + mode + ' retained=' + maximum.str() + ' allocations=' + records.str())
					assert maximum == 0 && records == 0
				}
			}
		}
	}
	println('PACK OWNERSHIP cold/cache walks, growing inventories and late hash/copy/cache refusals retain zero owned scratch PASS')
}

fn test_pack_owned_existing_workspace_calls_retire_inventory_and_filesystem_scratch() {
	for count in [1, 32]! {
		work, root, manifest, repository := pack_owned_fixture(count)!
		defer { os.rmdir_all(work) or {}; unsafe { work.free(); root.free(); manifest.free(); repository.free() } }
		pack_owned_once(root, manifest, repository, PackSourceOptions{}, false)!
		for mode in ['complete', 'locked', 'hashed']! {
			if mode == 'hashed' && count == 1 { continue }
			options := PackSourceOptions{ checkpoint: if mode == 'locked' { pack_owned_locked } else if mode == 'hashed' { pack_owned_refuse } else { mirror_no_checkpoint } }
			mut maximum := u64(0); mut records := u32(0)
			for _ in 0 .. 16 {
				$if track_heap ? { C.vinix_heap_begin() }
				pack_owned_once(root, manifest, repository, options, mode != 'complete')!
				$if track_heap ? {
					kept := C.vinix_heap_end(); allocations := C.vinix_heap_count()
					if kept > maximum { maximum = kept }; if allocations > records { records = allocations }
				}
			}
			$if track_heap ? {
				println('PACK OWNERSHIP full files=' + count.str() + ' mode=' + mode + ' retained=' + maximum.str() + ' allocations=' + records.str())
				// Existing-workspace admission, locks, durability, metadata and
				// payload owners all retire here; first-time construction is separate.
				assert maximum == 0 && records == 0
			}
		}
	}
	println('PACK OWNERSHIP existing-workspace replies and locked/late-walk refusals retain zero owned scratch PASS')
}

fn test_pack_owned_replies_survive_arguments_templates_siblings_and_private_root_retirement() {
	work, root, manifest, repository := pack_owned_fixture(32)!
	defer { os.rmdir_all(work) or {} }
	mut one := pack(manifest, root, repository)!
	mut two := pack(manifest, root, repository)!
	text := read_metadata(manifest)!
	recipe := RootRecipe{ manifest: decode_manifest(text, false)!, entries: [RootEntry{ source: 'd', path: 'd' }] }
	recipe_text := publisher_json(recipe)
	close_decoded_root_recipe(recipe)
	path := work + '/recipe.json'; os.write_file(path, recipe_text)!
	mut imported := pack_root(path, root, repository)!
	assert imported == two && one == two && two.files.len == 32
	encoded := publisher_json(two)
	assert encoded == json2.encode(two) + '\n'
	assert read_metadata(repository + '/manifests/fixture-all-1.0.0.json')! == encoded
	os.write_file(manifest, '{}')!; os.write_file(path, '{}')!
	unsafe { root.free(); manifest.free(); path.free(); repository.free(); text.free(); recipe_text.free() }
	one.close(); one.close()
	assert two.name == 'Fixture' && two.arguments == ['--literal', 'a b'] && two.associations == ['text/plain']
	assert two.permissions == ['files'] && two.files.all(it.path.starts_with('d/data-'))
	assert imported == two && imported.files[31].sha256.len == 64
	imported.close(); imported.close(); two.close(); two.close()
	assert two.id == '' && two.files.len == 0 && two.arguments.len == 0
	assert read_metadata(work + '/repository/manifests/fixture-all-1.0.0.json')! == encoded
	println('PACK OWNERSHIP pack/root replies survive retired inputs and sibling close; ignored template inventory, literal declarations, legacy manifest bytes and saved objects remain intact PASS')
}

fn test_pack_owned_late_validation_publication_and_object_directory_failures_preserve_retry() {
	work, root, manifest, repository := pack_owned_fixture(32)!
	defer { os.rmdir_all(work) or {} }
	mut good := pack(manifest, root, repository)!
	defer { good.close() }
	canonical := publisher_json(good)
	slot := repository + '/manifests/fixture-all-1.0.0.json'
	original := read_metadata(manifest)!
	os.write_file(manifest, original.replace('"license":"MIT"', '"license":""'))!
	if result := pack(manifest, root, repository) { mut p := result; p.close(); assert false }
	else { message := err.msg(); assert message.contains('invalid descriptive metadata'); unsafe { message.free(); err.free() } }
	assert read_metadata(slot)! == canonical
	os.write_file(manifest, original)!
	os.rm(slot)!; os.mkdir(slot)!; os.write_file(slot + '/keep', 'retained')!
	if result := pack(manifest, root, repository) { mut p := result; p.close(); assert false }
	else { message := err.msg(); unsafe { message.free(); err.free() } }
	assert os.read_file(slot + '/keep')! == 'retained'
	os.rmdir_all(slot)!
	object := repository + '/objects/' + index_digest('payload-0')
	os.rm(object)!; os.mkdir(object)!; os.write_file(object + '/keep', 'retained')!
	if result := pack(manifest, root, repository) { mut p := result; p.close(); assert false }
	else { message := err.msg(); assert message.contains('cannot atomically replace'); unsafe { message.free(); err.free() } }
	assert os.ls(object)! == ['keep'] && os.read_file(object + '/keep')! == 'retained' && !os.exists(slot)
	os.rmdir_all(object)!
	mut retried := pack(manifest, root, repository)!
	assert publisher_json(retried) == canonical && read_metadata(slot)! == canonical
	retried.close()
	println('PACK OWNERSHIP late validation/publication/cache-directory refusals preserve saved metadata and recovery bytes; exact retry PASS')
}

fn test_pack_owned_cli_replies_preserve_pack_and_prepared_root_json() {
	binary := os.getenv('VINIX_PACKAGE_PACK_CLI')
	if binary == '' { return }
	work, root, manifest, repository := pack_owned_fixture(2)!
	defer { os.rmdir_all(work) or {} }
	mut expected := pack(manifest, root, repository)!
	defer { expected.close() }
	text := read_metadata(manifest)!
	recipe := RootRecipe{ manifest: decode_manifest(text, false)!, entries: [RootEntry{ source: 'd', path: 'd' }] }
	path := work + '/recipe.json'; os.write_file(path, publisher_json(recipe))!
	close_decoded_root_recipe(recipe)
	for command in ['pack', 'pack-root']! {
		mut child := os.new_process(binary)
		child.set_args([command, if command == 'pack' { manifest } else { path }, root, repository])
		child.set_redirect_stdio_merged(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
		assert code == 0
		mut received := decode_manifest(output, true)!
		assert received == expected && output == publisher_json(expected)
		received.close(); received.close()
	}
	println('PACK OWNERSHIP production pack/pack-root CLI retain exact JSON replies and declarations PASS')
}
