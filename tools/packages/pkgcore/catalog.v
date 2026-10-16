// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os

pub struct CatalogImport {
pub:
	source string @[required] // optional profile directories, then aarch64/x86_64/shared
	recipe RootRecipe @[required]
}

pub struct CatalogRecipe {
pub:
	format int = 1 @[required]
	architectures []string @[required]
	packages []CatalogImport @[required]
}

pub struct CatalogInfo {
pub:
	format int = 1
	directory string
	architectures []string
	package_count int
	object_count int
	catalog_sha256 string
}

// Releases owned reply metadata. The published workspace remains available.
pub fn (mut info CatalogInfo) close() {
	unsafe {
		info.directory.free(); info.catalog_sha256.free()
		for architecture in info.architectures { architecture.free() }
		(&array(&info.architectures)).free()
	}
	info = CatalogInfo{}
}

struct CatalogPlan {
	recipe CatalogRecipe
	text string
	needed u64
	scratch u64
mut:
	objects map[string]Payload // values borrow the recipe until close
	closed bool
}

fn (mut plan CatalogPlan) close() {
	if plan.closed { return }
	unsafe { plan.objects.free(); plan.text.free() }
	close_decoded_catalog(plan.recipe)
	plan.closed = true
}

fn (plan CatalogPlan) result(directory string) CatalogInfo {
	return CatalogInfo{ directory: directory.clone(), architectures: review_strings(plan.recipe.architectures),
		package_count: plan.recipe.packages.len, object_count: plan.objects.len, catalog_sha256: index_digest(plan.text) }
}

struct CatalogOptions {
	checkpoint fn (string, string) ! = mirror_no_checkpoint
	available_space fn (string) !u64 = free_bytes
	flush fn (int) int = atomic_flush
}

fn catalog_key(context string, key string) bool {
	return match context {
		'' { key in ['format', 'architectures', 'packages'] }
		'packages' { key in ['source', 'recipe'] }
		'recipe' { key in ['format', 'manifest', 'entries'] }
		'manifest' { key in ['id', 'version', 'architecture', 'name', 'description', 'homepage',
			'license', 'proprietary', 'firmware', 'kind', 'runtime', 'entrypoint', 'arguments',
			'permissions', 'associations', 'dependencies', 'files', 'sdk', 'window_protocol'] }
		'entries' { key in ['source', 'path'] }
		'files' { key in ['path', 'sha256', 'bytes', 'executable'] }
		'dependencies' { key in ['id', 'minimum', 'before'] }
		else { false }
	}
}

fn catalog_import_order(a &CatalogImport, b &CatalogImport) int {
	return package_order(&a.recipe.manifest, &b.recipe.manifest)
}

fn catalog_source(source string, architecture string) bool {
	if !relative_path(source) { return false }
	mut start := 0
	mut depth := 1
	for i, byte in source {
		if byte != `/` { continue }
		if depth == 8 || !identifier(unsafe { tos(source.str + start, i - start) }) { return false }
		depth++; start = i + 1
	}
	leaf := unsafe { tos(source.str + start, source.len - start) }
	return leaf == if architecture == 'all' { 'shared' } else { architecture }
}

// The decoded catalog is the sole owner. Sorting these borrowed buffers changes
// their order without cloning headers or borrowing storage from the JSON text.
fn order_catalog_import(item CatalogImport) {
	mut files := unsafe { item.recipe.manifest.files }; files.sort(a.path < b.path)
	mut dependencies := unsafe { item.recipe.manifest.dependencies }; dependencies.sort(a.id < b.id)
	mut permissions := unsafe { item.recipe.manifest.permissions }; permissions.sort()
	mut associations := unsafe { item.recipe.manifest.associations }; associations.sort()
	mut entries := unsafe { item.recipe.entries }; entries.sort(a.path < b.path)
}

// O_NOFOLLOW applies only to the final component of an openat path. Capture
// every profile directory separately so no ancestor can redirect the importer.
fn catalog_source_root(root int, source string) !int {
	mut directory := C.dup(root)
	if directory < 0 { return error('cannot retain catalog roots') }
	components := source.split('/')
	defer { unsafe { components.free() } }
	for component in components {
		next := C.openat(directory, component.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
		C.close(directory)
		if next < 0 { return error('catalog source must be an ordinary directory at every component: ${source}') }
		directory = next
	}
	return directory
}

fn catalog_recipe(text string) !CatalogRecipe {
	input := decode_catalog_recipe(text)!
	mut accepted := false
	defer { if !accepted { close_decoded_catalog(input) } }
	if input.format != 1 || input.architectures.len == 0 || input.architectures.len > 2
		|| input.packages.len == 0 || input.packages.len > 4096 {
		return error('unsupported, empty or oversized catalog recipe')
	}
	mut architectures := unsafe { input.architectures }
	architectures.sort()
	for i, architecture in architectures {
		if architecture !in ['aarch64', 'x86_64'] || (i > 0 && architecture == architectures[i - 1]) {
			return error('catalog requires distinct supported architectures')
		}
	}
	mut imports := unsafe { input.packages }
	mut packages := []Package{cap: imports.len}
	mut seen := map[string]bool{}
	defer { unsafe { (&array(&packages)).free(); seen.free() } }
	for item in input.packages {
		validate_root_recipe(item.recipe)!
		p := item.recipe.manifest
		p.validate()!
		if !catalog_source(item.source, p.architecture)
			|| (p.architecture != 'all' && p.architecture !in architectures) {
			return error('catalog source must match the declared package architecture: ${p.id}')
		}
		identity := '${p.id}/${p.architecture}/${p.version}'
		defer { unsafe { identity.free() } }
		if identity in seen { return error('duplicate catalog package: ${identity}') }
		seen[identity] = true
		order_catalog_import(item)
		pointer := unsafe { &p }
		unsafe { packages.push_many(pointer, 1) }
	}
	for p in packages {
		for architecture in architectures {
			if !packages.any(it.id == p.id && it.version == p.version && it.architecture in [architecture, 'all']) {
				return error('catalog lacks ${p.id}/${p.version} coverage on ${architecture}')
			}
		}
		if p.architecture == 'all' && packages.any(it.id == p.id && it.version == p.version && it.architecture != 'all') {
			return error('catalog mixes shared and target-specific variants: ${p.id}/${p.version}')
		}
	}
	// Structural resolution never enrolls a publisher or accepts consumer licenses.
	key := '0'.repeat(64)
	defer { unsafe { key.free() } }
	release_closures(Index{ repository: 'catalog', sequence: 1, packages: packages }, key)!
	imports.sort_with_compare(catalog_import_order)
	accepted = true
	return CatalogRecipe{ format: 1, architectures: architectures, packages: imports }
}

pub fn pack_catalog(recipe_file string, source_roots string, destination string) !CatalogInfo {
	return catalog_build(recipe_file, source_roots, destination, CatalogOptions{})
}

// Admit metadata and budget unique objects before touching prepared roots or
// creating a destination parent. One owner retires all partial plan state.
fn prepare_catalog(text_input string) !CatalogPlan {
	recipe := catalog_recipe(text_input)!
	mut objects := map[string]Payload{}
	mut text := ''
	mut accepted := false
	defer {
		if !accepted {
			mut retired := CatalogPlan{ recipe: recipe, text: text, objects: objects }
			retired.close()
		}
	}
	text = publisher_json(recipe)
	if text.len > max_metadata { return error('canonical catalog recipe exceeds metadata limit') }
	mut needed := mirror_cost(u64(4 * 1024 * 1024), u64(text.len))!
	mut scratch := u64(0)
	for item in recipe.packages {
		manifest := publisher_json(item.recipe.manifest)
		defer { unsafe { manifest.free() } }
		needed = mirror_cost(needed, u64(manifest.len))!
		mut size := u64(0)
		for file in item.recipe.manifest.files {
			size = mirror_cost(size, file.bytes)!
			if file.sha256 in objects {
				if objects[file.sha256].bytes != file.bytes { return error('catalog has inconsistent object lengths') }
				continue
			}
			objects[file.sha256] = file
			needed = mirror_cost(needed, file.bytes)!
		}
		if size > scratch { scratch = size }
	}
	accepted = true
	return CatalogPlan{ recipe: recipe, text: text, objects: objects, needed: needed, scratch: scratch }
}

fn catalog_packed_matches(packed Package, expected Package) !bool {
	canonical := canonical_package(packed)!
	// canonical_package clones only these collection buffers; fields borrow packed.
	defer { unsafe {
		(&array(&canonical.files)).free(); (&array(&canonical.dependencies)).free()
		(&array(&canonical.permissions)).free(); (&array(&canonical.associations)).free()
	} }
	return canonical == expected
}

fn catalog_build(recipe_file string, source_roots string, destination string, options CatalogOptions) !CatalogInfo {
	input := read_metadata(recipe_file)!
	mut plan := prepare_catalog(input) or { unsafe { input.free() }; return err }
	unsafe { input.free() }
	defer { plan.close() }
	root := capture_prepared_root(source_roots, 'catalog')!
	defer { C.close(root) }
	target := export_target(destination, 'catalog workspace')!
	parent := os.dir(target)
	defer { unsafe { target.free(); parent.free() } }
	// Conservatively budget workspace plus the largest materialized package;
	// also check the actual temporary filesystem, which may be another volume.
	disk_check(options.available_space(parent)!, mirror_cost(plan.needed, plan.scratch)!, 64 * 1024 * 1024)!
	disk_check(options.available_space(os.temp_dir())!, plan.scratch, 64 * 1024 * 1024)!
	mut roots := map[string]int{}
	defer { for _, fd in roots { C.close(fd) }; unsafe { roots.free() } }
	for item in plan.recipe.packages {
		if item.source in roots { continue }
		fd := catalog_source_root(root, item.source)!
		roots[item.source] = fd
	}
	mut exporting := create_export_stage(parent, '.vinix-catalog', 'catalog workspace')!
	defer { exporting.close() }
	write_catalog_stage(plan, roots, target, options, mut exporting) or { return exporting.failure(err) }
	return plan.result(target)
}

fn write_catalog_stage(plan CatalogPlan, roots map[string]int, target string, options CatalogOptions, mut exporting ExportStage) ! {
	stage := exporting.path
	options.checkpoint('created', stage)!
	exporting.check()!
	for item in plan.recipe.packages {
		expected := item.recipe.manifest
		packed := pack_root_descriptor(item.recipe, roots[item.source], stage, true) or {
			return error('catalog import ${expected.id}/${expected.architecture}/${expected.version}: ${err}')
		}
		defer { close_decoded_package(packed) }
		if !catalog_packed_matches(packed, expected)! {
			return error('catalog payload inventory differs from its lock: ${expected.id}/${expected.architecture}/${expected.version}; verify prepared sources and regenerate/review the lock')
		}
		manifest_path := stage + '/manifests/${expected.id}-${expected.architecture}-${expected.version}.json'
		manifest := publisher_json(expected)
		defer { unsafe { manifest_path.free(); manifest.free() } }
		atomic_write(manifest_path, manifest)!
		options.checkpoint('packed', stage)!
		exporting.check()!
	}
	catalog_path := stage + '/catalog.json'
	objects_path := stage + '/objects'
	manifests_path := stage + '/manifests'
	defer { unsafe { catalog_path.free(); objects_path.free(); manifests_path.free() } }
	atomic_write(catalog_path, plan.text)!
	flush_tree(objects_path)!
	flush_tree(manifests_path)!
	sync_directory(stage)!
	options.checkpoint('ready', stage)!
	exporting.check()!
	names := os.ls(manifests_path)!
	defer { unsafe { names.free() } }
	if names.len != plan.recipe.packages.len { return error('catalog manifest set changed during import') }
	for item in plan.recipe.packages {
		p := item.recipe.manifest
		path := manifests_path + '/${p.id}-${p.architecture}-${p.version}.json'
		defer { unsafe { path.free() } }
		actual := read_metadata(path)!
		expected := publisher_json(p)
		defer { unsafe { actual.free(); expected.free() } }
		if actual != expected {
			return error('catalog manifest changed during import: ${p.id}')
		}
	}
	for hash, file in plan.objects {
		path := objects_path + '/' + hash
		defer { unsafe { path.free() } }
		if !verified_file(path, file) { return error('catalog object changed during import: ${hash}') }
	}
	staged := read_metadata(catalog_path)!
	defer { unsafe { staged.free() } }
	if staged != plan.text { return error('catalog recipe changed during import') }
	exporting.publish_with(target, options.flush)!
}
