// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import compat.ios.plist
import json2
import os

const apple_application_notice = 'licenses/application-LICENSE.txt'
const apple_runtime_notice = 'licenses/runtime-LICENSE.txt'

pub struct AppleProfileInfo {
pub:
	format int = 1
	profile string = 'apple-ios-arm64'
	directory string
	catalog string
	catalog_sha256 string
	application string
	version string
	runtime string
	runtime_version string
	architectures []string
}

// Borrow the declared bundle executable from the captured recipe. A single
// top-level .app directory makes the plist/keychain identity unambiguous.
fn apple_program(p Package) !string {
	if p.arguments.len == 0 || !p.arguments[0].starts_with('@APP@/') { return error('Apple profile needs an explicit @APP@/BUNDLE.app/EXECUTABLE argument') }
	path := unsafe { tos(p.arguments[0].str + 6, p.arguments[0].len - 6) }
	slash := path.index_u8(`/`)
	if !relative_path(path) || slash < 5 || slash == path.len - 1 { return error('Apple profile needs one top-level application bundle') }
	bundle := unsafe { tos(path.str, slash) }
	program := unsafe { tos(path.str + slash + 1, path.len - slash - 1) }
	if !bundle.ends_with('.app') || program.contains('/') || program == 'Info.plist' { return error('Apple profile has an invalid bundle executable path') }
	return path
}

fn apple_info_path(program string) string {
	return unsafe { tos(program.str, program.index_u8(`/`)) } + '/Info.plist'
}

fn apple_profile_recipe(recipe RootRecipe, application bool) ! {
	validate_root_recipe(recipe)!
	p := recipe.manifest
	if p.architecture != 'aarch64' || p.files.len != 0 || p.firmware { return error('Apple profile requires unpinned AArch64 templates without firmware') }
	program := if application { apple_program(p)! } else { '' }
	info := if application { apple_info_path(program) } else { '' }
	defer { unsafe { info.free() } }
	if application {
		if p.kind != 'apple' || p.entrypoint != 'bin/run-ios' || p.dependencies.len != 1
			|| p.runtime == '' || p.dependencies[0].id != p.runtime || p.dependencies[0].minimum == '' || p.dependencies[0].before == '' {
			return error('Apple profile application needs bin/run-ios and one bounded explicit runtime')
		}
	} else if p.kind != 'runtime' || p.runtime != '' || p.dependencies.len != 0 || p.entrypoint != ''
		|| p.arguments.len != 0 || p.permissions.len != 0 || p.associations.len != 0 {
		return error('Apple profile runtime must contain its complete closure without launchers or implicit grants')
	}
	required := if application { [apple_application_notice, program, info] } else { [apple_runtime_notice, 'bin/run-ios'] }
	defer { unsafe { (&array(&required)).free() } }
	for path in required { if !recipe.entries.any(it.path == path) { return error('Apple profile requires an explicit file selector: ' + path) } }
}

fn apple_profile_plist(root int, source string, p Package) ! {
	node := import_node(root, source)!
	defer { C.close(node.fd) }
	if node.mode & 0o170000 != 0o100000 || node.bytes == 0 || node.bytes > 1024 * 1024 { return error('Apple profile needs an ordinary Info.plist of at most 1 MiB') }
	mut bytes := []u8{len: int(node.bytes)}
	defer { unsafe { bytes.free() } }
	profile_read_at(node.fd, 0, mut bytes)!
	info := plist.parse(bytes)!
	defer { info.free() }
	if info.kind != .dictionary { return error('Apple profile needs a bundle property-list dictionary') }
	program := apple_program(p)!
	slash := program.index_u8(`/`)
	for name in ['CFBundleIdentifier', 'CFBundleExecutable', 'CFBundlePackageType']! {
		expected := match name { 'CFBundleIdentifier' { p.id } 'CFBundleExecutable' { unsafe { tos(program.str + slash + 1, program.len - slash - 1) } } else { 'APPL' } }
		value := info.fields[name] or { return error('Apple profile bundle is missing ' + name) }
		if value.kind != .string || value.text != expected { return error('Apple profile bundle disagrees with its declared identity/executable: ' + name) }
	}
}

fn apple_profile_payload(root int, recipe RootRecipe) !u64 {
	application := recipe.manifest.kind == 'apple'
	program := if application { apple_program(recipe.manifest)! } else { '' }
	info := if application { apple_info_path(program) } else { '' }
	defer { unsafe { info.free() } }
	mut bytes := u64(0)
	for entry in recipe.entries {
		node := import_node(root, entry.source)!
		C.close(node.fd)
		if node.mode & 0o170000 != 0o100000 { return error('Apple profile selectors must name individual ordinary files') }
		if entry.path.starts_with('licenses/') && (node.bytes == 0 || node.bytes > 1024 * 1024) { return error('Apple profile requires nonempty redistribution notices of at most 1 MiB') }
		if application && entry.path == program { profile_apple_image(root, entry.source)! }
		if application && entry.path == info { apple_profile_plist(root, entry.source, recipe.manifest)! }
		if !application && entry.path == 'bin/run-ios' { profile_elf(root, entry.source, 'aarch64', 'static', true)! }
		bytes = mirror_cost(bytes, node.bytes)!
	}
	return bytes
}

// The publisher supplies every application/runtime file and license notice.
// This profile neither selects host-global runtimes nor enables x86 translation.
pub fn apple_catalog(recipes string, source_roots string, destination string) !AppleProfileInfo {
	return apple_catalog_with(recipes, source_roots, destination, CatalogOptions{})
}

fn apple_catalog_with(recipes string, source_roots string, destination string, options CatalogOptions) !AppleProfileInfo {
	mut imports := []RootRecipe{cap: 2}
	defer { for recipe in imports { close_decoded_root_recipe(recipe) }; unsafe { (&array(&imports)).free() } }
	for role in ['application', 'runtime'] {
		text := read_metadata(recipes + '/aarch64/' + role + '.json')!
		defer { unsafe { text.free() } }
		recipe := decode_root_recipe(text)!
		apple_profile_recipe(recipe, role == 'application') or { close_decoded_root_recipe(recipe); return err }
		imports << recipe
	}
	app := imports[0].manifest; runtime := imports[1].manifest
	if app.runtime != runtime.id || app.id == runtime.id { return error('Apple profile runtime does not match its application dependency') }
	root := capture_prepared_root(source_roots, 'Apple profile')!
	defer { C.close(root) }
	fd := catalog_source_root(root, 'aarch64')!
	defer { C.close(fd) }
	target := export_target(destination, 'Apple profile')!
	parent := os.dir(target)
	mut needed := u64(4 * 1024 * 1024); mut scratch := u64(0)
	for recipe in imports {
		bytes := apple_profile_payload(fd, recipe)!
		needed = mirror_cost(needed, bytes)!
		if bytes > scratch { scratch = bytes }
	}
	scratch = mirror_cost(scratch, scratch)!
	disk_check(options.available_space(parent)!, mirror_cost(needed, scratch)!, 64 * 1024 * 1024)!
	disk_check(options.available_space(os.temp_dir())!, scratch, 64 * 1024 * 1024)!
	mut exporting := create_profile_stage(parent, '.vinix-apple-profile', 'Apple profile')!
	defer { exporting.close() }
	canonical := write_apple_profile(imports, fd, target, options, mut exporting) or { return exporting.failure(err) }
	defer { unsafe { canonical.free() } }
	exporting.finish(target)!
	return AppleProfileInfo{ directory: target, catalog: target + '/catalog.json', catalog_sha256: index_digest(canonical),
		application: app.id.clone(), version: app.version.clone(), runtime: runtime.id.clone(), runtime_version: runtime.version.clone(), architectures: ['aarch64'] }
}

fn write_apple_profile(imports []RootRecipe, fd int, target string, options CatalogOptions, mut exporting ProfileStage) !string {
	stage := exporting.stage.path
	exporting.checkpoint('created', options)!
	mut packages := []CatalogImport{cap: 2}
	for recipe in imports {
		p := pack_root_descriptor(recipe, fd, stage + '/inventory', false)!
		mut notices := []string{}
		defer { unsafe { (&array(&notices)).free() } }
		for entry in recipe.entries { if entry.path.starts_with('licenses/') { notices << entry.path } }
		profile_file_inventory(recipe, p, notices)!
		objects := C.open((stage + '/inventory/objects').str, C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
		if objects < 0 { return error('cannot inspect Apple profile inventory') }
		defer { C.close(objects) }
		program := if p.kind == 'apple' { apple_program(p)! } else { '' }
		info := if p.kind == 'apple' { apple_info_path(program) } else { '' }
		defer { unsafe { info.free() } }
		for file in p.files {
			if file.path == program { profile_apple_image(objects, file.sha256)! }
			if file.path == info { apple_profile_plist(objects, file.sha256, p)! }
			if p.kind == 'runtime' && file.path == 'bin/run-ios' {
				if !file.executable { return error('Apple profile runner lost executable permission') }
				profile_elf(objects, file.sha256, 'aarch64', 'static', false)!
			}
		}
		packages << CatalogImport{ source: 'aarch64', recipe: RootRecipe{ ...recipe, manifest: p } }
		exporting.checkpoint('packed', options)!
	}
	canonical := json2.encode(catalog_recipe(json2.encode(CatalogRecipe{ format: 1, architectures: ['aarch64'], packages: packages }))!) + '\n'
	if canonical.len > max_metadata { return error('Apple catalog lock exceeds metadata limit') }
	exporting.publish(canonical, target, options)!
	return canonical
}
