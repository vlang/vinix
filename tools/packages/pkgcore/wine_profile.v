// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os

const wine_application_notice = 'licenses/application-LICENSE.txt'
const wine_runtime_notice = 'licenses/runtime-LICENSE.txt'

pub struct WineProfileInfo {
pub:
	format int = 1
	profile string = 'wine-win64'
	directory string
	catalog string
	catalog_sha256 string
	application string
	version string
	runtime string
	runtime_version string
	architectures []string
}

struct WineImport {
	architecture string
	recipe RootRecipe
}

// A publisher supplies a complete runtime, including a native static launcher
// on each host. On AArch64 this launcher must explicitly package translation.
// The profile never selects a host Wine installation or infers license grants.
pub fn wine_catalog(recipes string, source_roots string, destination string) !WineProfileInfo {
	return wine_catalog_with(recipes, source_roots, destination, CatalogOptions{})
}

fn wine_profile_recipe(recipe RootRecipe, architecture string, application bool) ! {
	validate_root_recipe(recipe)!
	p := recipe.manifest
	if p.architecture != architecture || p.files.len != 0 || p.firmware {
		return error('Wine profile needs target-specific unpinned templates without firmware')
	}
	if application {
		if p.kind != 'windows' || p.entrypoint != 'bin/wine-runner' || p.runtime == ''
			|| p.arguments.len == 0 || p.arguments[0] != '@APP@/bin/program.exe'
			|| p.dependencies.len != 1 || p.dependencies[0].id != p.runtime
			|| p.dependencies[0].minimum == '' || p.dependencies[0].before == '' {
			return error('Wine profile application needs a bounded explicit runtime and packaged Win64 program')
		}
	} else if p.kind != 'runtime' || p.runtime != '' || p.dependencies.len != 0
		|| p.entrypoint != '' || p.arguments.len != 0 || p.permissions.len != 0 || p.associations.len != 0 {
		return error('Wine profile runtime must contain its complete closure without launchers or implicit grants')
	}
	required := if application { ['bin/program.exe', wine_application_notice] } else { ['bin/wine-runner', wine_runtime_notice] }
	for path in required {
		if !recipe.entries.any(it.path == path) { return error('Wine profile requires an explicit file selector: ' + path) }
	}
}

fn wine_profile_payload(root int, recipe RootRecipe, application bool) !u64 {
	mut bytes := u64(0)
	for entry in recipe.entries {
		node := import_node(root, entry.source)!
		C.close(node.fd)
		if node.mode & 0o170000 != 0o100000 {
			return error('Wine profile selectors must name individual ordinary files: ' + entry.source)
		}
		if entry.path.starts_with('licenses/') && (node.bytes == 0 || node.bytes > u64(1024 * 1024)) {
			return error('Wine profile requires nonempty redistribution notices of at most 1 MiB')
		}
		if application && entry.path == 'bin/program.exe' { profile_win64(root, entry.source)! }
		if !application && entry.path == 'bin/wine-runner' {
			profile_elf(root, entry.source, recipe.manifest.architecture, 'static', true)!
		}
		bytes = mirror_cost(bytes, node.bytes)!
	}
	return bytes
}

fn wine_catalog_with(recipes string, source_roots string, destination string, options CatalogOptions) !WineProfileInfo {
	// Read each bounded template once before creating output. Keep these exact
	// declarations through materialization; callbacks cannot replace approvals.
	mut imports := []WineImport{}
	defer { for item in imports { close_decoded_root_recipe(item.recipe) } }
	for architecture in ['aarch64', 'x86_64'] {
		for role in ['application', 'runtime'] {
			text := read_metadata(recipes + '/' + architecture + '/' + role + '.json')!
			defer { unsafe { text.free() } }
			recipe := decode_root_recipe(text)!
			wine_profile_recipe(recipe, architecture, role == 'application') or {
				close_decoded_root_recipe(recipe)
				return err
			}
			imports << WineImport{ architecture: architecture, recipe: recipe }
		}
	}
	// Descriptions, grants, proprietary declarations and compatibility ranges
	// must agree across hosts; only the explicit target architecture may differ.
	for index in 0 .. 2 {
		first := imports[index].recipe.manifest
		second := imports[index + 2].recipe.manifest
		if json2.encode(Package{ ...first, architecture: 'x86_64' }) != json2.encode(second) {
			return error('Wine profile application/runtime declarations must match across both hosts')
		}
	}
	app := imports[0].recipe.manifest
	runtime := imports[1].recipe.manifest
	if app.runtime != runtime.id || app.id == runtime.id {
		return error('Wine profile runtime does not match its application dependency')
	}
	root := capture_prepared_root(source_roots, 'Wine profile')!
	defer { C.close(root) }
	target := export_target(destination, 'Wine profile')!
	mut roots := map[string]int{}
	defer { for _, fd in roots { C.close(fd) } }
	mut needed := u64(4 * 1024 * 1024)
	mut scratch := u64(0)
	for architecture in ['aarch64', 'x86_64'] {
		fd := catalog_source_root(root, architecture)!
		roots[architecture] = fd
	}
	for item in imports {
		bytes := wine_profile_payload(roots[item.architecture], item.recipe, item.recipe.manifest.kind == 'windows')!
		needed = mirror_cost(needed, bytes)!
		if bytes > scratch { scratch = bytes }
	}
	parent := os.dir(target)
	scratch = mirror_cost(scratch, scratch)!
	disk_check(options.available_space(parent)!, mirror_cost(needed, scratch)!, 64 * 1024 * 1024)!
	disk_check(options.available_space(os.temp_dir())!, scratch, 64 * 1024 * 1024)!
	stage := export_stage(parent, '.vinix-wine-profile')!
	defer { os.rmdir_all(stage) or {} }
	options.checkpoint('created', stage)!
	mut packages := []CatalogImport{}
	for item in imports {
		recipe := item.recipe
		p := pack_root_descriptor(recipe, roots[item.architecture], stage + '/inventory', false)!
		mut notices := []string{}
		for entry in recipe.entries { if entry.path.starts_with('licenses/') { notices << entry.path } }
		defer { unsafe { notices.free() } }
		profile_file_inventory(recipe, p, notices)!
		objects := C.open((stage + '/inventory/objects').str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
		if objects < 0 { return error('cannot inspect Wine profile inventory') }
		defer { C.close(objects) }
		// Recheck the copied bytes too; preflight did not freeze source contents.
		for file in p.files {
			if p.kind == 'windows' && file.path == 'bin/program.exe' { profile_win64(objects, file.sha256)! }
			if p.kind == 'runtime' && file.path == 'bin/wine-runner' {
				if !file.executable { return error('Wine profile launcher lost executable permission') }
				profile_elf(objects, file.sha256, item.architecture, 'static', false)!
			}
		}
		packages << CatalogImport{ source: item.architecture, recipe: RootRecipe{ ...recipe, manifest: p } }
	}
	text := json2.encode(CatalogRecipe{ format: 1, architectures: ['aarch64', 'x86_64'], packages: packages })
	canonical := json2.encode(catalog_recipe(text)!) + '\n'
	if canonical.len > max_metadata { return error('Wine catalog lock exceeds metadata limit') }
	os.mkdir(stage + '/lock')!
	os.chmod(stage + '/lock', 0o700)!
	atomic_write(stage + '/lock/catalog.json', canonical)!
	options.checkpoint('ready', stage)!
	if read_metadata(stage + '/lock/catalog.json')! != canonical { return error('Wine catalog lock changed before publication') }
	publish_new_directory(stage + '/lock', target, 'Wine profile')!
	sync_directory(parent) or { return error('Wine profile published at ${target}, but its directory flush failed: ${err}') }
	return WineProfileInfo{ directory: target, catalog: target + '/catalog.json', catalog_sha256: index_digest(canonical),
		application: app.id.clone(), version: app.version.clone(), runtime: runtime.id.clone(), runtime_version: runtime.version.clone(),
		architectures: ['aarch64', 'x86_64'] }
}
