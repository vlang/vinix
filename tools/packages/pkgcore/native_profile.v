// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os

const native_notices = ['licenses/application-sdk-MIT.txt', 'licenses/v-MIT.txt', 'licenses/musl-MIT.txt']

pub struct NativeProfileInfo {
pub:
	format int = 1
	profile string = 'native-sdk'
	directory string
	catalog string
	catalog_sha256 string
	version string
	architectures []string
}

// Retire reply metadata only. The published lock and caller arguments survive.
pub fn (mut info NativeProfileInfo) close() {
	unsafe {
		info.directory.free(); info.catalog.free(); info.catalog_sha256.free(); info.version.free()
		for architecture in info.architectures { architecture.free() }
		(&array(&info.architectures)).free()
	}
	info = NativeProfileInfo{}
}

fn native_profile_result(version string, directory string, canonical string) NativeProfileInfo {
	architectures := ['aarch64', 'x86_64']
	defer { unsafe { (&array(&architectures)).free() } }
	return NativeProfileInfo{ directory: directory.clone(), catalog: directory + '/catalog.json', catalog_sha256: index_digest(canonical),
		version: version.clone(), architectures: review_strings(architectures) }
}

// Templates borrow manifest strings and permission names. Only selector text
// for notices and the collection buffers belong to this owner. Packed manifests
// are independent decodes; catalog wrappers borrow the templates' selectors.
struct NativeProfilePlan {
	templates []RootRecipe
mut:
	packages []CatalogImport
}

fn native_profile_plan(version string) NativeProfilePlan {
	mut templates := []RootRecipe{cap: 6}
	for architecture in ['aarch64', 'x86_64']! {
		recipes := native_profile_templates(architecture, version)
		// Move headers, avoiding V's implicit deep clone on variable append.
		for recipe in recipes { unsafe { templates.push_many(&recipe, 1) } }
		unsafe { (&array(&recipes)).free() }
	}
	return NativeProfilePlan{ templates: templates, packages: []CatalogImport{cap: 6} }
}

fn (mut plan NativeProfilePlan) close() {
	for item in plan.packages { close_decoded_package(item.recipe.manifest) }
	unsafe {
		(&array(&plan.packages)).free()
		for recipe in plan.templates {
			for entry in recipe.entries {
				if entry.path == recipe.manifest.entrypoint { continue }
				entry.source.free(); entry.path.free()
			}
			(&array(&recipe.entries)).free()
			(&array(&recipe.manifest.permissions)).free()
			(&array(&recipe.manifest.associations)).free()
		}
		(&array(&plan.templates)).free()
	}
	plan = NativeProfilePlan{}
}

fn (plan NativeProfilePlan) canonical() !string {
	architectures := ['aarch64', 'x86_64']
	defer { unsafe { (&array(&architectures)).free() } }
	text := publisher_json(CatalogRecipe{ format: 1, architectures: architectures, packages: plan.packages })
	defer { unsafe { text.free() } }
	input := catalog_recipe(text)!
	defer { close_decoded_catalog(input) }
	canonical := publisher_json(input)
	if canonical.len > max_metadata { unsafe { canonical.free() }; return error('native SDK catalog lock exceeds metadata limit') }
	return canonical
}

fn native_profile_templates(architecture string, version string) []RootRecipe {
	mut recipes := []RootRecipe{cap: 3}
	for p in [
		Package{ id: 'org.vinix.package-hello', version: version, architecture: architecture,
			name: 'Package Hello', description: 'A static V example of the signed package launch contract',
			license: 'MIT', kind: 'native', entrypoint: 'bin/package-hello', permissions: ['files'], associations: ['text/plain'] },
		Package{ id: 'org.vinix.counter', version: version, architecture: architecture,
			name: 'Native counter', description: 'A native SDK 1 window example with a button and retained private counter data.',
			license: 'MIT', kind: 'native', entrypoint: 'bin/counter', permissions: ['display'], window_protocol: 1 },
		Package{ id: 'org.vinix.memo', version: version, architecture: architecture,
			name: 'Native memo', description: 'A native SDK text-entry example with explicit saving to private application data.',
			license: 'MIT', kind: 'native', entrypoint: 'bin/memo', permissions: ['display'], window_protocol: 2 },
	]! {
		mut entries := []RootEntry{cap: 4}
		entries << RootEntry{ source: p.entrypoint, path: p.entrypoint }
		for name in ['application-sdk-MIT.txt', 'v-MIT.txt', 'musl-MIT.txt']! {
			entries << RootEntry{ source: 'licenses/' + name, path: 'licenses/' + name }
		}
		recipes << RootRecipe{ manifest: p, entries: entries }
	}
	return recipes
}

// Inventory reviewed, statically linked SDK examples; this never compiles code,
// invents a publisher identity or grants additional application permissions.
pub fn native_catalog(version string, source_roots string, destination string) !NativeProfileInfo {
	return native_catalog_with(version, source_roots, destination, CatalogOptions{})
}

fn native_catalog_with(version string, source_roots string, destination string, options CatalogOptions) !NativeProfileInfo {
	validated_version(version)!
	root := capture_prepared_root(source_roots, 'native SDK profile')!
	defer { C.close(root) }
	target := export_target(destination, 'native SDK profile')!
	defer { unsafe { target.free() } }
	mut roots := map[string]int{}
	defer { for _, fd in roots { C.close(fd) }; unsafe { roots.free() } }
	mut needed := u64(4 * 1024 * 1024)
	mut scratch := u64(0)
	for architecture in ['aarch64', 'x86_64']! {
		fd := C.openat(root, architecture.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
		if fd < 0 { return error('native SDK profile requires both ordinary architecture roots: ${architecture}') }
		roots[architecture] = fd
		mut size := u64(0)
		for path in ['bin/package-hello', 'bin/counter', 'bin/memo']! {
			profile_elf(fd, path, architecture, 'static', true)!
			node := import_node(fd, path)!
			C.close(node.fd)
			size = mirror_cost(size, node.bytes)!
		}
		for name in ['application-sdk-MIT.txt', 'v-MIT.txt', 'musl-MIT.txt']! {
			path := 'licenses/' + name
			defer { unsafe { path.free() } }
			node := import_node(fd, path)!
			C.close(node.fd)
			if node.mode & 0o170000 != 0o100000 || node.bytes == 0 || node.bytes > u64(1024 * 1024) {
				return error('native SDK profile requires a nonempty redistribution notice of at most 1 MiB: ${name}')
			}
			size = mirror_cost(size, node.bytes)!
		}
		needed = mirror_cost(needed, size)!
		if size > scratch { scratch = size }
	}
	parent := os.dir(target)
	temporary := import_temporary_directory()
	defer { unsafe { parent.free(); temporary.free() } }
	scratch = mirror_cost(scratch, scratch)!
	disk_check(options.available_space(parent)!, mirror_cost(needed, scratch)!, 64 * 1024 * 1024)!
	disk_check(options.available_space(temporary)!, scratch, 64 * 1024 * 1024)!
	mut exporting := create_profile_stage(parent, '.vinix-native-profile', 'native SDK profile')!
	defer { exporting.close() }
	canonical := write_native_profile(version, roots, target, options, mut exporting) or { return exporting.failure(err) }
	defer { unsafe { canonical.free() } }
	exporting.finish(target)!
	return native_profile_result(version, target, canonical)
}

fn write_native_profile(version string, roots map[string]int, target string, options CatalogOptions, mut exporting ProfileStage) !string {
	stage := exporting.stage.path
	exporting.checkpoint('created', options)!
	mut plan := native_profile_plan(version)
	defer { plan.close() }
	inventory := stage + '/inventory'
	object_path := inventory + '/objects'
	defer { unsafe { inventory.free(); object_path.free() } }
	for recipe in plan.templates {
		architecture := recipe.manifest.architecture
		p := pack_root_descriptor(recipe, roots[architecture], inventory, false)!
		mut transferred := false
		defer { if !transferred { close_decoded_package(p) } }
		profile_file_inventory(recipe, p, native_notices)!
		objects := C.open(object_path.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
		if objects < 0 { return error('cannot inspect native SDK profile inventory') }
		for file in p.files {
			if file.path != p.entrypoint { continue }
			if !file.executable { C.close(objects); return error('native SDK profile payload is not executable: ${file.path}') }
			profile_elf(objects, file.sha256, architecture, 'static', false) or {
				C.close(objects)
				cause := err.msg()
				message := 'native SDK profile imported ' + p.id + ': ' + cause
				unsafe { cause.free(); err.free() }
				return error(message)
			}
		}
		C.close(objects)
		plan.packages << CatalogImport{ source: architecture, recipe: RootRecipe{ ...recipe, manifest: p } }
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
