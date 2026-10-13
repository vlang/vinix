// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
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

// A catalog lock must disclose these fields, even when false/zero. Package's
// older manifest defaults remain available to the single-package pack commands.
struct CatalogPinnedFile {
	path string @[required]
	sha256 string @[required]
	bytes u64 @[required]
	executable bool @[required]
}

struct CatalogDeclarations {
	packages []CatalogImportDeclaration @[required]
}

struct CatalogImportDeclaration {
	recipe CatalogRecipeDeclaration @[required]
}

struct CatalogRecipeDeclaration {
	format int @[required]
	manifest CatalogManifestDeclaration @[required]
	entries []RootEntry @[required]
}

struct CatalogManifestDeclaration {
	proprietary bool @[required]
	firmware bool @[required]
	files []CatalogPinnedFile @[required]
}

struct CatalogOptions {
	checkpoint fn (string, string) ! = mirror_no_checkpoint
	available_space fn (string) !u64 = free_bytes
}

fn catalog_key(context string, key string) bool {
	return match context {
		'' { key in ['format', 'architectures', 'packages'] }
		'packages' { key in ['source', 'recipe'] }
		'recipe' { key in ['format', 'manifest', 'entries'] }
		'manifest' { key in ['id', 'version', 'architecture', 'name', 'description', 'homepage',
			'license', 'proprietary', 'firmware', 'kind', 'runtime', 'entrypoint', 'arguments',
			'permissions', 'associations', 'dependencies', 'files', 'sdk'] }
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
	parts := source.split('/')
	if parts.len > 8 || !parts[..parts.len - 1].all(identifier(it)) { return false }
	return parts.last() == if architecture == 'all' { 'shared' } else { architecture }
}

// O_NOFOLLOW applies only to the final component of an openat path. Capture
// every profile directory separately so no ancestor can redirect the importer.
fn catalog_source_root(root int, source string) !int {
	mut directory := C.dup(root)
	if directory < 0 { return error('cannot retain catalog roots') }
	for component in source.split('/') {
		next := C.openat(directory, component.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
		C.close(directory)
		if next < 0 { return error('catalog source must be an ordinary directory at every component: ${source}') }
		directory = next
	}
	return directory
}

fn catalog_recipe(text string) !CatalogRecipe {
	input := json2.decode[CatalogRecipe](text)!
	json2.decode[CatalogDeclarations](text)!
	document_keys(text, catalog_key)!
	if input.format != 1 || input.architectures.len == 0 || input.architectures.len > 2
		|| input.packages.len == 0 || input.packages.len > 4096 {
		return error('unsupported, empty or oversized catalog recipe')
	}
	mut architectures := input.architectures.clone()
	architectures.sort()
	for i, architecture in architectures {
		if architecture !in ['aarch64', 'x86_64'] || (i > 0 && architecture == architectures[i - 1]) {
			return error('catalog requires distinct supported architectures')
		}
	}
	mut imports := []CatalogImport{}
	mut packages := []Package{}
	mut seen := map[string]bool{}
	for item in input.packages {
		validate_root_recipe(item.recipe)!
		p := canonical_package(item.recipe.manifest)!
		if !catalog_source(item.source, p.architecture)
			|| (p.architecture != 'all' && p.architecture !in architectures) {
			return error('catalog source must match the declared package architecture: ${p.id}')
		}
		identity := '${p.id}/${p.architecture}/${p.version}'
		if identity in seen { return error('duplicate catalog package: ${identity}') }
		seen[identity] = true
		mut entries := item.recipe.entries.clone()
		entries.sort(a.path < b.path)
		imports << CatalogImport{ source: item.source, recipe: RootRecipe{ manifest: p, entries: entries } }
		packages << p
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
	release_closures(Index{ repository: 'catalog', sequence: 1, packages: packages }, '0'.repeat(64))!
	imports.sort_with_compare(catalog_import_order)
	return CatalogRecipe{ format: 1, architectures: architectures, packages: imports }
}

pub fn pack_catalog(recipe_file string, source_roots string, destination string) !CatalogInfo {
	return catalog_build(recipe_file, source_roots, destination, CatalogOptions{})
}

fn catalog_build(recipe_file string, source_roots string, destination string, options CatalogOptions) !CatalogInfo {
	recipe := catalog_recipe(read_metadata(recipe_file)!)!
	text := json2.encode(recipe) + '\n'
	if text.len > max_metadata { return error('canonical catalog recipe exceeds metadata limit') }
	target := export_target(destination, 'catalog workspace')!
	parent := os.dir(target)
	mut objects := map[string]Payload{}
	mut needed := mirror_cost(u64(4 * 1024 * 1024), u64(text.len))!
	mut scratch := u64(0)
	for item in recipe.packages {
		needed = mirror_cost(needed, u64(json2.encode(item.recipe.manifest).len + 1))!
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
	// Conservatively budget workspace plus the largest materialized package;
	// also check the actual temporary filesystem, which may be another volume.
	disk_check(options.available_space(parent)!, mirror_cost(needed, scratch)!, 64 * 1024 * 1024)!
	disk_check(options.available_space(os.temp_dir())!, scratch, 64 * 1024 * 1024)!
	root := C.open(source_roots.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
	if root < 0 { return error('catalog source roots must be an ordinary directory') }
	defer { C.close(root) }
	mut roots := map[string]int{}
	defer { for _, fd in roots { C.close(fd) } }
	for item in recipe.packages {
		if item.source in roots { continue }
		fd := catalog_source_root(root, item.source)!
		roots[item.source] = fd
	}
	stage := export_stage(parent, '.vinix-catalog')!
	mut published := false
	defer { if !published { os.rmdir_all(stage) or {} } }
	options.checkpoint('created', stage)!
	for item in recipe.packages {
		expected := item.recipe.manifest
		packed := pack_root_descriptor(item.recipe, roots[item.source], stage, true) or {
			return error('catalog import ${expected.id}/${expected.architecture}/${expected.version}: ${err}')
		}
		if canonical_package(packed)! != expected {
			return error('catalog payload inventory differs from its lock: ${expected.id}/${expected.architecture}/${expected.version}; verify prepared sources and regenerate/review the lock')
		}
		atomic_write(stage + '/manifests/${expected.id}-${expected.architecture}-${expected.version}.json', json2.encode(expected) + '\n')!
		options.checkpoint('packed', stage)!
	}
	atomic_write(stage + '/catalog.json', text)!
	flush_tree(stage + '/objects')!
	flush_tree(stage + '/manifests')!
	sync_directory(stage)!
	options.checkpoint('ready', stage)!
	if os.ls(stage + '/manifests')!.len != recipe.packages.len { return error('catalog manifest set changed during import') }
	for item in recipe.packages {
		p := item.recipe.manifest
		if read_metadata(stage + '/manifests/${p.id}-${p.architecture}-${p.version}.json')! != json2.encode(p) + '\n' {
			return error('catalog manifest changed during import: ${p.id}')
		}
	}
	for hash, file in objects {
		if !verified_file(stage + '/objects/' + hash, file) { return error('catalog object changed during import: ${hash}') }
	}
	if read_metadata(stage + '/catalog.json')! != text { return error('catalog recipe changed during import') }
	publish_new_directory(stage, target, 'catalog workspace')!
	published = true
	sync_directory(parent) or {
		return error('catalog workspace published at ${target}, but its directory flush failed; verify storage and the workspace before signing: ${err}')
	}
	return CatalogInfo{ directory: target, architectures: recipe.architectures,
		package_count: recipe.packages.len, object_count: objects.len, catalog_sha256: index_digest(text) }
}
