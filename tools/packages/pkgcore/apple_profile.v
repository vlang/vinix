// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import compat.ios.plist
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

// Replies own their metadata independently of caller paths and decoded plans.
pub fn (mut info AppleProfileInfo) close() {
	unsafe {
		info.directory.free(); info.catalog.free(); info.catalog_sha256.free()
		info.application.free(); info.version.free(); info.runtime.free(); info.runtime_version.free()
		for architecture in info.architectures { architecture.free() }
		(&array(&info.architectures)).free()
	}
	info = AppleProfileInfo{}
}

fn apple_profile_result(app Package, runtime Package, directory string, canonical string) AppleProfileInfo {
	architectures := ['aarch64']
	defer { unsafe { (&array(&architectures)).free() } }
	return AppleProfileInfo{ directory: directory.clone(), catalog: directory + '/catalog.json', catalog_sha256: index_digest(canonical),
		application: app.id.clone(), version: app.version.clone(), runtime: runtime.id.clone(), runtime_version: runtime.version.clone(),
		architectures: review_strings(architectures) }
}

// Decoded templates own their selectors. Packed manifests are independent;
// catalog wrappers borrow only the selectors and the literal architecture.
struct AppleProfilePlan {
mut:
	imports []RootRecipe
	packages []CatalogImport
}

fn (mut plan AppleProfilePlan) close() {
	for item in plan.packages { close_decoded_package(item.recipe.manifest) }
	for recipe in plan.imports { close_decoded_root_recipe(recipe) }
	unsafe { (&array(&plan.packages)).free(); (&array(&plan.imports)).free() }
	plan = AppleProfilePlan{}
}

fn apple_profile_plan(recipes string) !AppleProfilePlan {
	mut plan := AppleProfilePlan{ imports: []RootRecipe{cap: 2}, packages: []CatalogImport{cap: 2} }
	mut accepted := false
	defer { if !accepted { plan.close() } }
	for role in ['application', 'runtime']! {
		path := recipes + '/aarch64/' + role + '.json'
		defer { unsafe { path.free() } }
		text := read_metadata(path)!
		defer { unsafe { text.free() } }
		recipe := decode_root_recipe(text)!
		apple_profile_recipe(recipe, role == 'application') or { close_decoded_root_recipe(recipe); return err }
		// Transfer the decoded owner without V's implicit deep clone on append.
		unsafe { plan.imports.push_many(&recipe, 1) }
	}
	app := plan.imports[0].manifest; runtime := plan.imports[1].manifest
	if app.runtime != runtime.id || app.id == runtime.id { return error('Apple profile runtime does not match its application dependency') }
	accepted = true
	return plan
}

fn (plan AppleProfilePlan) canonical() !string {
	architectures := ['aarch64']
	defer { unsafe { (&array(&architectures)).free() } }
	text := publisher_json(CatalogRecipe{ format: 1, architectures: architectures, packages: plan.packages })
	defer { unsafe { text.free() } }
	input := catalog_recipe(text)!
	defer { close_decoded_catalog(input) }
	canonical := publisher_json(input)
	if canonical.len > max_metadata { unsafe { canonical.free() }; return error('Apple catalog lock exceeds metadata limit') }
	return canonical
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
	mut plan := apple_profile_plan(recipes)!
	defer { plan.close() }
	root := capture_prepared_root(source_roots, 'Apple profile')!
	defer { C.close(root) }
	fd := catalog_source_root(root, 'aarch64')!
	defer { C.close(fd) }
	target := export_target(destination, 'Apple profile')!
	defer { unsafe { target.free() } }
	parent := os.dir(target)
	temporary := import_temporary_directory()
	defer { unsafe { parent.free(); temporary.free() } }
	mut needed := u64(4 * 1024 * 1024); mut scratch := u64(0)
	for recipe in plan.imports {
		bytes := apple_profile_payload(fd, recipe)!
		needed = mirror_cost(needed, bytes)!
		if bytes > scratch { scratch = bytes }
	}
	scratch = mirror_cost(scratch, scratch)!
	disk_check(options.available_space(parent)!, mirror_cost(needed, scratch)!, 64 * 1024 * 1024)!
	disk_check(options.available_space(temporary)!, scratch, 64 * 1024 * 1024)!
	mut exporting := create_profile_stage(parent, '.vinix-apple-profile', 'Apple profile')!
	defer { exporting.close() }
	canonical := write_apple_profile(mut plan, fd, target, options, mut exporting) or { return exporting.failure(err) }
	defer { unsafe { canonical.free() } }
	exporting.finish(target)!
	return apple_profile_result(plan.imports[0].manifest, plan.imports[1].manifest, target, canonical)
}

fn write_apple_profile(mut plan AppleProfilePlan, fd int, target string, options CatalogOptions, mut exporting ProfileStage) !string {
	stage := exporting.stage.path
	exporting.checkpoint('created', options)!
	inventory := stage + '/inventory'; object_path := inventory + '/objects'
	defer { unsafe { inventory.free(); object_path.free() } }
	for recipe in plan.imports {
		p := pack_root_descriptor(recipe, fd, inventory, false)!
		mut transferred := false
		defer { if !transferred { close_decoded_package(p) } }
		mut notices := []string{cap: recipe.entries.len}
		defer { unsafe { (&array(&notices)).free() } }
		for entry in recipe.entries {
			if entry.path.starts_with('licenses/') { unsafe { notices.push_many(&entry.path, 1) } }
		}
		profile_file_inventory(recipe, p, notices)!
		objects := C.open(object_path.str, C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
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
		plan.packages << CatalogImport{ source: 'aarch64', recipe: RootRecipe{ ...recipe, manifest: p } }
		transferred = true
		exporting.checkpoint('packed', options)!
	}
	canonical := plan.canonical()!
	mut published := false
	defer { if !published { unsafe { canonical.free() } } }
	exporting.publish(canonical, target, options)!
	published = true
	return canonical
}
