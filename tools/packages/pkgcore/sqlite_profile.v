// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os

pub const sqlite_application_id = 'org.sqlite.cli'
pub const sqlite_runtime_id = 'org.vinix.sqlite-runtime'

const sqlite_notices = ['licenses/sqlite-COPYRIGHT', 'licenses/musl-COPYRIGHT', 'licenses/vinix-COPYING']

pub struct SqliteProfileInfo {
pub:
	format int = 1
	profile string = 'sqlite-cli'
	directory string
	catalog string
	catalog_sha256 string
	sqlite_version string
	runtime_version string
	architectures []string
}

// Reply metadata owns its strings; the published lock and caller inputs survive.
pub fn (mut info SqliteProfileInfo) close() {
	unsafe {
		info.directory.free(); info.catalog.free(); info.catalog_sha256.free()
		info.sqlite_version.free(); info.runtime_version.free()
		for architecture in info.architectures { architecture.free() }
		(&array(&info.architectures)).free()
	}
	info = SqliteProfileInfo{}
}

fn sqlite_profile_result(sqlite_version string, runtime_version string, directory string, canonical string) SqliteProfileInfo {
	architectures := ['aarch64', 'x86_64']
	defer { unsafe { (&array(&architectures)).free() } }
	return SqliteProfileInfo{ directory: directory.clone(), catalog: directory + '/catalog.json',
		catalog_sha256: index_digest(canonical), sqlite_version: sqlite_version.clone(), runtime_version: runtime_version.clone(),
		architectures: review_strings(architectures) }
}

// Scalar template fields borrow caller strings/literals. The template owner
// retires argument/selector text and collection buffers. Packed manifests are
// independent decodes; their catalog wrappers borrow the template selectors.
struct SqliteProfilePlan {
	templates []RootRecipe
mut:
	packages []CatalogImport
}

fn sqlite_profile_plan(sqlite_version string, runtime_version string) SqliteProfilePlan {
	mut templates := []RootRecipe{cap: 4}
	for architecture in ['aarch64', 'x86_64']! {
		recipes := sqlite_profile_templates(architecture, sqlite_version, runtime_version)
		for recipe in recipes { unsafe { templates.push_many(&recipe, 1) } }
		unsafe { (&array(&recipes)).free() }
	}
	return SqliteProfilePlan{ templates: templates, packages: []CatalogImport{cap: 4} }
}

fn (mut plan SqliteProfilePlan) close() {
	for item in plan.packages { close_decoded_package(item.recipe.manifest) }
	unsafe {
		(&array(&plan.packages)).free()
		for recipe in plan.templates {
			for entry in recipe.entries { entry.source.free(); entry.path.free() }
			for argument in recipe.manifest.arguments { argument.free() }
			(&array(&recipe.entries)).free()
			(&array(&recipe.manifest.arguments)).free()
			(&array(&recipe.manifest.dependencies)).free()
		}
		(&array(&plan.templates)).free()
	}
	plan = SqliteProfilePlan{}
}

fn (plan SqliteProfilePlan) canonical() !string {
	architectures := ['aarch64', 'x86_64']
	defer { unsafe { (&array(&architectures)).free() } }
	text := publisher_json(CatalogRecipe{ format: 1, architectures: architectures, packages: plan.packages })
	defer { unsafe { text.free() } }
	input := catalog_recipe(text)!
	defer { close_decoded_catalog(input) }
	canonical := publisher_json(input)
	if canonical.len > max_metadata { unsafe { canonical.free() }; return error('SQLite catalog lock exceeds metadata limit') }
	return canonical
}

fn sqlite_profile_templates(architecture string, sqlite_version string, runtime_version string) []RootRecipe {
	return [
		RootRecipe{
			manifest: Package{ id: sqlite_application_id, version: sqlite_version, architecture: architecture,
				name: 'SQLite', description: 'Interactive SQLite command line. Run from Terminal; the default database is retained in this application\'s personal data directory.',
				homepage: 'https://www.sqlite.org/', license: 'SQLite-Public-Domain', kind: 'linux',
				runtime: sqlite_runtime_id, entrypoint: 'bin/vinix-linux-runner',
				arguments: ['@RUNTIME@/lib/ld-musl-' + architecture + '.so.1', '@APP@/bin/sqlite3', '@DATA@/database.sqlite3'],
				dependencies: [Dependency{ id: sqlite_runtime_id, minimum: '1.0.0', before: '2.0.0' }] }
			entries: [RootEntry{ source: 'bin/sqlite3', path: 'bin/sqlite3' },
				RootEntry{ source: 'licenses/sqlite-COPYRIGHT', path: 'licenses/sqlite-COPYRIGHT' }]
		},
		RootRecipe{
			manifest: Package{ id: sqlite_runtime_id, version: runtime_version, architecture: architecture,
				name: 'SQLite isolated runtime', description: 'Explicit musl loader, SQLite library and static SDK runner for the SQLite CLI profile.',
				homepage: 'https://www.sqlite.org/', license: 'GPL-2.0-or-later AND MIT AND SQLite-Public-Domain', kind: 'runtime' }
			entries: [RootEntry{ source: 'bin/vinix-linux-runner', path: 'bin/vinix-linux-runner' },
				RootEntry{ source: 'lib/libc.so', path: 'lib/libc.so' },
				RootEntry{ source: 'lib/libc.so', path: 'lib/ld-musl-' + architecture + '.so.1' },
				RootEntry{ source: 'lib/libsqlite3.so.0', path: 'lib/libsqlite3.so.0' },
				RootEntry{ source: 'licenses/sqlite-COPYRIGHT', path: 'licenses/sqlite-COPYRIGHT' },
				RootEntry{ source: 'licenses/musl-COPYRIGHT', path: 'licenses/musl-COPYRIGHT' },
				RootEntry{ source: 'licenses/vinix-COPYING', path: 'licenses/vinix-COPYING' }]
		},
	]
}

pub fn sqlite_catalog(sqlite_version string, runtime_version string, source_roots string, destination string) !SqliteProfileInfo {
	return sqlite_catalog_with(sqlite_version, runtime_version, source_roots, destination, CatalogOptions{})
}

fn sqlite_catalog_with(sqlite_version string, runtime_version string, source_roots string, destination string, options CatalogOptions) !SqliteProfileInfo {
	validated_version(sqlite_version)!
	validated_version(runtime_version)!
	if compare_versions(runtime_version, '1.0.0') < 0 || compare_versions(runtime_version, '2.0.0') >= 0 {
		return error('SQLite profile runtime must be in the supported 1.x compatibility range')
	}
	root := capture_prepared_root(source_roots, 'SQLite profile')!
	defer { C.close(root) }
	target := export_target(destination, 'SQLite profile')!
	defer { unsafe { target.free() } }
	mut roots := map[string]int{}
	defer { for _, fd in roots { C.close(fd) }; unsafe { roots.free() } }
	mut needed := u64(4 * 1024 * 1024)
	mut scratch := u64(0)
	for architecture in ['aarch64', 'x86_64']! {
		fd := C.openat(root, architecture.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
		if fd < 0 { return error('SQLite profile requires both ordinary architecture roots: ${architecture}') }
		roots[architecture] = fd
		mut root_bytes := u64(0)
		for index, path in ['bin/sqlite3', 'bin/vinix-linux-runner', 'lib/libc.so', 'lib/libsqlite3.so.0']! {
			kind := if index == 0 { 'pie' } else if index == 1 { 'static' } else { 'shared' }
			profile_elf(fd, path, architecture, kind, true)!
			node := import_node(fd, path)!
			C.close(node.fd)
			root_bytes = mirror_cost(root_bytes, node.bytes)!
		}
		for path in sqlite_notices {
			node := import_node(fd, path)!
			C.close(node.fd)
			if node.mode & 0o170000 != 0o100000 || node.bytes == 0 || node.bytes > u64(1024 * 1024) {
				return error('SQLite profile requires a nonempty redistribution notice of at most 1 MiB: ${path}')
			}
			root_bytes = mirror_cost(root_bytes, node.bytes)!
		}
		needed = mirror_cost(needed, root_bytes)!
		if root_bytes > scratch { scratch = root_bytes }
	}
	parent := os.dir(target)
	temporary := import_temporary_directory()
	defer { unsafe { parent.free(); temporary.free() } }
	scratch = mirror_cost(scratch, scratch)!
	disk_check(options.available_space(parent)!, mirror_cost(needed, scratch)!, 64 * 1024 * 1024)!
	disk_check(options.available_space(temporary)!, scratch, 64 * 1024 * 1024)!
	mut exporting := create_profile_stage(parent, '.vinix-sqlite-profile', 'SQLite profile')!
	defer { exporting.close() }
	canonical := write_sqlite_profile(sqlite_version, runtime_version, roots, target, options, mut exporting) or { return exporting.failure(err) }
	defer { unsafe { canonical.free() } }
	exporting.finish(target)!
	return sqlite_profile_result(sqlite_version, runtime_version, target, canonical)
}

fn write_sqlite_profile(sqlite_version string, runtime_version string, roots map[string]int, target string, options CatalogOptions, mut exporting ProfileStage) !string {
	stage := exporting.stage.path
	exporting.checkpoint('created', options)!
	mut plan := sqlite_profile_plan(sqlite_version, runtime_version)
	defer { plan.close() }
	inventory := stage + '/inventory'; object_path := inventory + '/objects'
	defer { unsafe { inventory.free(); object_path.free() } }
	for recipe in plan.templates {
		architecture := recipe.manifest.architecture
		p := pack_root_descriptor(recipe, roots[architecture], inventory, false)!
		mut transferred := false
		defer { if !transferred { close_decoded_package(p) } }
		profile_file_inventory(recipe, p, sqlite_notices)!
		// Validate the materialized bytes too: a source may have changed after
		// preflight. Object modes are storage modes; the manifest carries exec.
		objects := C.open(object_path.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
		if objects < 0 { return error('cannot inspect SQLite profile inventory') }
		for file in p.files {
			kind := if file.path == 'bin/sqlite3' { 'pie' } else if file.path == 'bin/vinix-linux-runner' { 'static' }
				else if file.path.starts_with('lib/') { 'shared' } else { '' }
			if kind == '' { continue }
			if !file.executable { C.close(objects); return error('SQLite profile payload is not executable: ${file.path}') }
			profile_elf(objects, file.sha256, architecture, kind, false) or {
				C.close(objects)
				cause := err.msg()
				message := 'SQLite profile imported ' + p.id + '/' + file.path + ': ' + cause
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
	// Only the reviewed lock is published. Temporary payload copies are removed;
	// pack-catalog rechecks these exact pins when constructing the workspace.
	exporting.publish(canonical, target, options)!
	published = true
	return canonical
}
