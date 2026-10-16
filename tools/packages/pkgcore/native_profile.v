// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
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

fn native_profile_templates(architecture string, version string) []RootRecipe {
	mut recipes := []RootRecipe{}
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
	] {
		mut entries := [RootEntry{ source: p.entrypoint, path: p.entrypoint }]
		for name in ['application-sdk-MIT.txt', 'v-MIT.txt', 'musl-MIT.txt'] {
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
	version_parts(version)!
	root := capture_prepared_root(source_roots, 'native SDK profile')!
	defer { C.close(root) }
	target := export_target(destination, 'native SDK profile')!
	mut roots := map[string]int{}
	defer { for _, fd in roots { C.close(fd) } }
	mut needed := u64(4 * 1024 * 1024)
	mut scratch := u64(0)
	for architecture in ['aarch64', 'x86_64'] {
		fd := C.openat(root, architecture.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
		if fd < 0 { return error('native SDK profile requires both ordinary architecture roots: ${architecture}') }
		roots[architecture] = fd
		mut size := u64(0)
		for path in ['bin/package-hello', 'bin/counter', 'bin/memo'] {
			profile_elf(fd, path, architecture, 'static', true)!
			node := import_node(fd, path)!
			C.close(node.fd)
			size = mirror_cost(size, node.bytes)!
		}
		for name in ['application-sdk-MIT.txt', 'v-MIT.txt', 'musl-MIT.txt'] {
			node := import_node(fd, 'licenses/' + name)!
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
	scratch = mirror_cost(scratch, scratch)!
	disk_check(options.available_space(parent)!, mirror_cost(needed, scratch)!, 64 * 1024 * 1024)!
	disk_check(options.available_space(os.temp_dir())!, scratch, 64 * 1024 * 1024)!
	mut exporting := create_profile_stage(parent, '.vinix-native-profile', 'native SDK profile')!
	defer { exporting.close() }
	canonical := write_native_profile(version, roots, target, options, mut exporting) or { return exporting.failure(err) }
	defer { unsafe { canonical.free() } }
	exporting.finish(target)!
	return NativeProfileInfo{ directory: target, catalog: target + '/catalog.json', catalog_sha256: index_digest(canonical),
		version: version, architectures: ['aarch64', 'x86_64'] }
}

fn write_native_profile(version string, roots map[string]int, target string, options CatalogOptions, mut exporting ProfileStage) !string {
	stage := exporting.stage.path
	exporting.checkpoint('created', options)!
	mut packages := []CatalogImport{}
	for architecture in ['aarch64', 'x86_64'] {
		for recipe in native_profile_templates(architecture, version) {
			p := pack_root_descriptor(recipe, roots[architecture], stage + '/inventory', false)!
			profile_file_inventory(recipe, p, native_notices)!
			objects := C.open((stage + '/inventory/objects').str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
			if objects < 0 { return error('cannot inspect native SDK profile inventory') }
			for file in p.files {
				if file.path != p.entrypoint { continue }
				if !file.executable { C.close(objects); return error('native SDK profile payload is not executable: ${file.path}') }
				profile_elf(objects, file.sha256, architecture, 'static', false) or {
					C.close(objects)
					return error('native SDK profile imported ${p.id}: ${err}')
				}
			}
			C.close(objects)
			packages << CatalogImport{ source: architecture, recipe: RootRecipe{ ...recipe, manifest: p } }
			exporting.checkpoint('packed', options)!
		}
	}
	text := json2.encode(CatalogRecipe{ format: 1, architectures: ['aarch64', 'x86_64'], packages: packages })
	canonical := json2.encode(catalog_recipe(text)!) + '\n'
	if canonical.len > max_metadata { return error('native SDK catalog lock exceeds metadata limit') }
	exporting.publish(canonical, target, options)!
	return canonical
}
